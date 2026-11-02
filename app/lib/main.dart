import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'constants/app_features.dart';
import 'constants/routing_weights.dart';
import 'constants/app_shadows.dart';
import 'l10n/generated/app_localizations.dart';
import 'screens/home_screen.dart';
import 'screens/map_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/race_screen.dart';
import 'screens/stations_screen.dart';
import 'screens/track_route_screen.dart';
import 'services/accessibility_service.dart';
import 'services/active_trip_service.dart';
import 'services/auth_service.dart';
import 'services/commuter_ml_service.dart';
import 'services/database_service.dart';
import 'services/closing_time_service.dart';
import 'services/database_health_service.dart';
import 'services/locale_controller.dart';
import 'services/location_sharing_service.dart';
import 'services/ml_consent_service.dart';
import 'services/navigation_state.dart';
import 'services/notification_service.dart';
import 'services/offline_mode_service.dart';
import 'services/theme_controller.dart';
import 'services/theme_preset_controller.dart';
import 'theme/app_themes.dart';
import 'widgets/ml_consent_sheet.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
    try {
      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabaseAnonKey,
      );
      DatabaseHealthService.instance.markConfigured();
    } catch (error) {
      debugPrint('Supabase init skipped, using local guest mode: $error');
    }
  } else {
    debugPrint('Supabase config missing, starting in local guest mode.');
  }

  const sentryDsn = String.fromEnvironment('SENTRY_DSN');
  if (sentryDsn.isEmpty) {
    if (kReleaseMode) {
      debugPrint('SENTRY_DSN is not configured; crash reporting is disabled.');
    }
    runApp(const SmartCommuterApp());
    return;
  }

  await SentryFlutter.init(
    (options) {
      options.dsn = sentryDsn;
      options.tracesSampleRate = 0.2;
      options.environment = kReleaseMode ? 'production' : 'development';
    },
    appRunner: () => runApp(const SmartCommuterApp()),
  );
}

class SmartCommuterApp extends StatelessWidget {
  const SmartCommuterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.instance.mode,
      builder: (context, mode, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: AccessibilityService.instance.enabled,
          builder: (context, accessible, _) {
            return ValueListenableBuilder<Locale?>(
              valueListenable: LocaleController.instance.locale,
              builder: (context, locale, _) {
                return ValueListenableBuilder<AppThemePreset>(
                  valueListenable: ThemePresetController.instance.preset,
                  builder: (context, preset, _) {
                    return MaterialApp(
                  onGenerateTitle: (context) =>
                      AppLocalizations.of(context).appTitle,
                  debugShowCheckedModeBanner: false,
                  locale: locale,
                  localizationsDelegates: const [
                    AppLocalizations.delegate,
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                  ],
                  supportedLocales: AppLocalizations.supportedLocales,
                  themeMode: mode,
                  theme: buildAppTheme(preset, Brightness.light),
                  darkTheme: buildAppTheme(preset, Brightness.dark),
                  builder: (context, child) {
                    if (!accessible || child == null) {
                      return child ?? const SizedBox.shrink();
                    }
                    final media = MediaQuery.of(context);
                    return MediaQuery(
                      data: media.copyWith(
                        textScaler:
                            media.textScaler.clamp(minScaleFactor: 1.15),
                        boldText: true,
                      ),
                      child: child,
                    );
                  },
                  home: const _BootstrapGate(),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class _BootstrapGate extends StatefulWidget {
  const _BootstrapGate();

  @override
  State<_BootstrapGate> createState() => _BootstrapGateState();
}

class _BootstrapGateState extends State<_BootstrapGate> {
  Future<void>? _bootstrapFuture;

  @override
  void initState() {
    super.initState();
    _runBootstrap();
  }

  void _runBootstrap() {
    _bootstrapFuture = _bootstrap();
    setState(() {});
  }

  static const Duration _stepTimeout = Duration(seconds: 5);
  static const Duration _bootstrapBudget = Duration(seconds: 8);

  Future<void> _runStep(
    Future<void> Function() step, {
    required String label,
  }) async {
    try {
      await step().timeout(_stepTimeout);
    } catch (error) {
      debugPrint('Bootstrap step "$label" skipped: $error');
    }
  }

  Future<void> _bootstrap() async {
    await _runStep(DatabaseService().initialize, label: 'database');

    await Future.wait<void>([
      _runStep(ThemeController.initialize, label: 'theme'),
      _runStep(ThemePresetController.initialize, label: 'theme preset'),
      _runStep(RoutingWeightsStore.instance.initialize, label: 'routing weights'),
      _runStep(LocaleController.initialize, label: 'locale'),
      _runStep(AuthService().initialize, label: 'auth'),
      _runStep(ActiveTripService.instance.initialize, label: 'active trip'),
      _runStep(NotificationService().initialize, label: 'notifications'),
      _runStep(OfflineModeService.instance.load, label: 'offline mode'),
      _runStep(AccessibilityService.instance.load, label: 'accessibility'),
      _runStep(MlConsentService.instance.load, label: 'ml consent'),
    ]).timeout(
      _bootstrapBudget,
      onTimeout: () {
        debugPrint('Bootstrap watchdog fired; opening the app without waiting.');
        return const <void>[];
      },
    );

    ClosingTimeService.instance.initialize();
    unawaited(_deferredInitialize());
  }

  Future<void> _deferredInitialize() async {
    await _runStep(
      DatabaseHealthService.instance.initialize,
      label: 'database health',
    );
    await _runStep(CommuterMlService().initialize, label: 'on-device ml');
    await _runStep(
      () async => LocationSharingService.instance.start(),
      label: 'location sharing',
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _bootstrapFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _ConfigurationErrorScreen(
            message: AppLocalizations.of(context)
                .startupFailed('${snapshot.error}'),
            onRetry: _runBootstrap,
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const _StartupLoadingScreen();
        }
        return const AuthGate();
      },
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AuthService();
    return ValueListenableBuilder(
      valueListenable: auth.currentUser,
      builder: (context, user, _) {
        if (user == null) {
          return const _StartupLoadingScreen();
        }
        return const MainNavigation();
      },
    );
  }
}

class _ConfigurationErrorScreen extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const _ConfigurationErrorScreen({
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFDCE4F3)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.cloud_off_rounded,
                    size: 40,
                    color: Color(0xFFD7263D),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.configurationRequired,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF667085),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (onRetry != null) ...[
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: onRetry,
                      child: Text(l10n.retry),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StartupLoadingScreen extends StatelessWidget {
  const _StartupLoadingScreen();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 18),
                Text(
                  l10n.preparingData,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MainNavigation extends StatefulWidget {
  final int initialIndex;

  const MainNavigation({
    super.key,
    this.initialIndex = 0,
  });

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  // These measurements are kept explicit so the bottom toolbar can be
  // recreated accurately in external design tools.
  static const double _bottomToolbarHeight = 88;
  static const double _bottomToolbarNavigationHeight = 76;
  static const double _bottomToolbarBottomMargin = 14;

  final Connectivity connectivity = Connectivity();
  StreamSubscription<dynamic>? connectivitySubscription;
  Timer? bannerTimer;

  Timer? _tabSwitchTimer;

  int currentIndex = 0;
  final List<int> screenGenerations = <int>[0, 0, 0, 0, 0];
  bool isConnected = true;
  bool _offlineOverlayDismissed = false;
  _NetworkBannerType bannerType = _NetworkBannerType.hidden;

  @override
  void initState() {
    super.initState();
    currentIndex = widget.initialIndex;
    NavigationState.instance.selectedIndex.value = currentIndex;
    initializeConnectivity();
    NavigationState.instance.selectedIndex
        .addListener(_handleExternalNavigation);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAskMlConsent());
  }

  Future<void> _maybeAskMlConsent() async {
    if (AuthService().isGuestMode) return;
    final consent = MlConsentService.instance;
    if (await consent.hasBeenAsked()) return;
    if (!mounted) return;
    await showMlConsentSheet(context, source: 'onboarding');
  }

  @override
  void dispose() {
    bannerTimer?.cancel();
    connectivitySubscription?.cancel();
    _tabSwitchTimer?.cancel();
    NavigationState.instance.selectedIndex
        .removeListener(_handleExternalNavigation);
    super.dispose();
  }

  void _handleExternalNavigation() {
    final target = NavigationState.instance.selectedIndex.value;
    if (target == currentIndex) return;
    handleTabSwitch(target);
  }

  Future<void> initializeConnectivity() async {
    final initial = await connectivity.checkConnectivity();
    if (!mounted) return;
    applyConnectivity(initial, isInitial: true);

    connectivitySubscription =
        connectivity.onConnectivityChanged.listen((event) {
      applyConnectivity(event);
    });
  }

  void applyConnectivity(dynamic event, {bool isInitial = false}) {
    final connected = eventHasConnection(event);
    final previouslyConnected = isConnected;
    if (!isInitial && connected == previouslyConnected) {
      return;
    }

    isConnected = connected;
    if (!connected) {
      bannerTimer?.cancel();
      if (!mounted) return;
      setState(() {
        bannerType = _NetworkBannerType.disconnected;
        _offlineOverlayDismissed = false;
      });
      return;
    }

    if (isInitial || previouslyConnected) {
      if (!mounted) return;
      setState(() => bannerType = _NetworkBannerType.hidden);
      return;
    }

    bannerTimer?.cancel();
    if (!mounted) return;
    setState(() => bannerType = _NetworkBannerType.connected);
    refreshCurrentScreen();
    bannerTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => bannerType = _NetworkBannerType.hidden);
    });
  }

  bool eventHasConnection(dynamic event) {
    if (event is ConnectivityResult) {
      return event != ConnectivityResult.none;
    }
    if (event is List<ConnectivityResult>) {
      return event.any((result) => result != ConnectivityResult.none);
    }
    if (event is Iterable) {
      for (final item in event) {
        if (item is ConnectivityResult && item != ConnectivityResult.none) {
          return true;
        }
      }
      return false;
    }
    return true;
  }

  void refreshCurrentScreen() {
    if (currentIndex < 0 || currentIndex >= screenGenerations.length) {
      return;
    }
    setState(() {
      screenGenerations[currentIndex] = screenGenerations[currentIndex] + 1;
    });
  }

  List<Widget> buildScreens() {
    return <Widget>[
      HomeScreen(key: ValueKey('home_${screenGenerations[0]}')),
      MapScreen(key: ValueKey('map_${screenGenerations[1]}')),
      ValueListenableBuilder<ActiveTrip?>(
        valueListenable: ActiveTripService.instance.activeTrip,
        builder: (context, trip, _) {
          final key = ValueKey('track_${screenGenerations[2]}');
          if (trip == null) {
            return StationsScreen(key: key, asTrackTab: true);
          }
          return TrackRouteScreen(key: key);
        },
      ),
      if (AppFeatures.racingEnabled)
        RaceScreen(key: ValueKey('race_${screenGenerations[3]}')),
      ProfileScreen(key: ValueKey('profile_${screenGenerations[4]}')),
    ];
  }

  List<NavigationDestination> buildDestinations(AppLocalizations l10n) {
    return [
      NavigationDestination(
        icon: const Icon(Icons.home_outlined),
        selectedIcon: const Icon(Icons.home_rounded),
        label: l10n.navHome,
      ),
      NavigationDestination(
        icon: const Icon(Icons.map_outlined),
        selectedIcon: const Icon(Icons.map_rounded),
        label: l10n.navMap,
      ),
      NavigationDestination(
        icon: const Icon(Icons.route_outlined),
        selectedIcon: const Icon(Icons.route_rounded),
        label: l10n.navTrack,
      ),
      if (AppFeatures.racingEnabled)
        NavigationDestination(
          icon: const Icon(Icons.emoji_events_outlined),
          selectedIcon: const Icon(Icons.emoji_events_rounded),
          label: l10n.navRace,
        ),
      NavigationDestination(
        icon: const Icon(Icons.person_outline_rounded),
        selectedIcon: const Icon(Icons.person_rounded),
        label: l10n.navProfile,
      ),
    ];
  }

  void handleTabSwitch(int index) {
    if (index == currentIndex) return;
    _tabSwitchTimer?.cancel();
    setState(() {
      if (index == 2) {
        screenGenerations[index] = screenGenerations[index] + 1;
      }
      currentIndex = index;
    });
    NavigationState.instance.selectedIndex.value = index;
    _tabSwitchTimer = Timer(const Duration(seconds: 1), () {
      if (!mounted) return;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = buildScreens();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: currentIndex,
            children: screens,
          ),

          _NetworkStatusBanner(type: bannerType),
          if (!isConnected && !_offlineOverlayDismissed)
            Positioned.fill(
              child: _OfflineOverlay(
                onRetry: () async {
                  setState(() => _offlineOverlayDismissed = true);
                  await initializeConnectivity();
                },
                onContinue: () =>
                    setState(() => _offlineOverlayDismissed = true),
              ),
            ),
        ],
      ),
      bottomNavigationBar: Stack(
        clipBehavior: Clip.none,
        children: [
          SafeArea(
            top: false,
            minimum: EdgeInsets.zero,
            child: Container(
              height: _bottomToolbarHeight,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: theme.cardColor,
                border: Border(
                  top: BorderSide(color: theme.dividerColor),
                ),
              ),
              child: NavigationBarTheme(
                data: NavigationBarThemeData(
                  height: _bottomToolbarNavigationHeight,
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  surfaceTintColor: Colors.transparent,
                  labelTextStyle: WidgetStateProperty.resolveWith((states) {
                    final selected = states.contains(WidgetState.selected);
                    return TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? scheme.primary
                          : scheme.onSurface.withValues(alpha: 0.55),
                    );
                  }),
                  iconTheme: WidgetStateProperty.resolveWith((states) {
                    final selected = states.contains(WidgetState.selected);
                    return IconThemeData(
                      size: 22,
                      color: selected
                          ? scheme.primary
                          : scheme.onSurface.withValues(alpha: 0.55),
                    );
                  }),
                  indicatorColor: scheme.primary.withValues(alpha: 0.10),
                  indicatorShape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                child: NavigationBar(
                  selectedIndex: currentIndex,
                  onDestinationSelected: handleTabSwitch,
                  destinations: buildDestinations(l10n),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: _bottomToolbarHeight + _bottomToolbarBottomMargin + 10,
            child: ValueListenableBuilder<bool>(
              valueListenable: ClosingTimeService.instance.isClosingSoon,
              builder: (context, closingSoon, _) {
                if (!closingSoon) return const SizedBox.shrink();
                return IgnorePointer(
                  child: Center(
                    child: ValueListenableBuilder<Duration>(
                      valueListenable: ClosingTimeService.instance.timeUntilClose,
                      builder: (context, remaining, _) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDC2626)
                                .withValues(alpha: 0.94),
                            borderRadius: BorderRadius.circular(999),
                            boxShadow: appCardShadows(context),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.access_time_rounded,
                                size: 13,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                l10n.closingIn(
                                  ClosingTimeService.instance
                                      .countdownFormatted,
                                ),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
          const Positioned(
            right: 18,
            top: 10,
            child: _DataModeIndicator(),
          ),
        ],
      ),
    );
  }
}

class _DataModeIndicator extends StatelessWidget {
  const _DataModeIndicator();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: DatabaseHealthService.instance.isConnected,
      builder: (context, connected, _) {
        final l10n = AppLocalizations.of(context);
        final color = connected ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
        final label = connected ? l10n.dataLive : l10n.dataOffline;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _OfflineOverlay extends StatelessWidget {
  const _OfflineOverlay({required this.onRetry, required this.onContinue});

  final Future<void> Function() onRetry;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface.withValues(alpha: 0.97),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wifi_off_rounded, size: 48, color: scheme.primary),
                const SizedBox(height: 16),
                Text(
                  l10n.offlineTitle,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.offlineBody,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: scheme.onSurface.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => onRetry(),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(l10n.tryAgain),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: onContinue,
                    child: Text(l10n.continueOffline),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _NetworkBannerType {
  hidden,
  disconnected,
  connected,
}

class _NetworkStatusBanner extends StatelessWidget {
  final _NetworkBannerType type;

  const _NetworkStatusBanner({
    required this.type,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final visible = type != _NetworkBannerType.hidden;
    final isConnected = type == _NetworkBannerType.connected;
    final color =
        isConnected ? const Color(0xFF16A34A) : const Color(0xFF111827);
    final text = isConnected
        ? l10n.connectivityConnected
        : l10n.connectivityDisconnected;
    final icon = isConnected ? Icons.wifi_rounded : Icons.wifi_off_rounded;

    return IgnorePointer(
      ignoring: true,
      child: SafeArea(
        minimum: const EdgeInsets.only(top: 8, left: 12, right: 12),
        child: Align(
          alignment: Alignment.topCenter,
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            offset: visible ? Offset.zero : const Offset(0, -1.2),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: visible ? 1 : 0,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: appCardShadows(context),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 16, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      text,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
