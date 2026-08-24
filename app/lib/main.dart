import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'constants/app_shadows.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/map_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/track_route_screen.dart';
import 'services/active_trip_service.dart';
import 'services/auth_service.dart';
import 'services/commuter_ml_service.dart';
import 'services/database_service.dart';
import 'services/closing_time_service.dart';
import 'services/database_health_service.dart';
import 'services/navigation_state.dart';
import 'services/notification_service.dart';
import 'services/theme_controller.dart';

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

  await SentryFlutter.init(
    (options) {
      options.dsn = const String.fromEnvironment(
        'SENTRY_DSN',
        defaultValue: '',
      );
      options.tracesSampleRate = 0.2;
    },
    appRunner: () => runApp(const SmartCommuterApp()),
  );
}

class SmartCommuterApp extends StatelessWidget {
  const SmartCommuterApp({super.key});

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF0A3A8B);
    const secondary = Color(0xFFD7263D);
    const tertiary = Color(0xFFF4B400);
    const lightSurface = Color(0xFFF4F7FC);
    const darkSurface = Color(0xFF0B1220);

    final lightScheme = ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      secondary: secondary,
      tertiary: tertiary,
      surface: lightSurface,
      brightness: Brightness.light,
    );

    final darkScheme = ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      secondary: secondary,
      tertiary: tertiary,
      surface: darkSurface,
      brightness: Brightness.dark,
    );

    final lightTheme = ThemeData(
      useMaterial3: true,
      colorScheme: lightScheme,
      scaffoldBackgroundColor: lightScheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: lightScheme.onSurface,
        titleTextStyle: TextStyle(
          color: lightScheme.onSurface,
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
      textTheme: const TextTheme(
        headlineSmall:
            TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.2),
        titleLarge: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.2),
        titleMedium: TextStyle(fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(height: 1.3),
      ),
      cardTheme: CardThemeData(
        elevation: 6,
        shadowColor: const Color(0x33101828),
        surfaceTintColor: Colors.transparent,
        color: lightScheme.surface,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
          side: BorderSide(color: Color(0xFFE6EBF5)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: lightScheme.primary,
          foregroundColor: lightScheme.onPrimary,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          side: const BorderSide(color: Color(0xFFCFD9EA)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFDCE4F3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFDCE4F3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: lightScheme.primary, width: 1.6),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );

    final darkTheme = ThemeData(
      useMaterial3: true,
      colorScheme: darkScheme,
      scaffoldBackgroundColor: darkScheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: darkScheme.onSurface,
        titleTextStyle: TextStyle(
          color: darkScheme.onSurface,
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
      textTheme: const TextTheme(
        headlineSmall:
            TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.2),
        titleLarge: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.2),
        titleMedium: TextStyle(fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(height: 1.3),
      ),
      cardTheme: CardThemeData(
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: 0.32),
        surfaceTintColor: Colors.transparent,
        color: darkScheme.surface,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: darkScheme.primary,
          foregroundColor: darkScheme.onPrimary,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          side: BorderSide(color: darkScheme.onSurface.withValues(alpha: 0.12)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkScheme.surface.withValues(alpha: 0.06),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              BorderSide(color: darkScheme.onSurface.withValues(alpha: 0.12)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              BorderSide(color: darkScheme.onSurface.withValues(alpha: 0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: darkScheme.primary, width: 1.6),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.instance.mode,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'Smart Commuter Assistant+',
          debugShowCheckedModeBanner: false,
          themeMode: mode,
          theme: lightTheme,
          darkTheme: darkTheme,
          home: const _BootstrapGate(),
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

  Future<void> _bootstrap() async {
    await DatabaseService().initialize();
    await ThemeController.initialize();
    await AuthService().initialize();
    await ActiveTripService.instance.initialize();
    await NotificationService().initialize();
    await DatabaseHealthService.instance.initialize();
    await CommuterMlService().initialize();
    ClosingTimeService.instance.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _bootstrapFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _ConfigurationErrorScreen(
            message: 'Startup failed.\n\n${snapshot.error}',
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
          return const LoginScreen();
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
                  const Text(
                    'Configuration Required',
                    style: TextStyle(
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
                      child: const Text('Retry'),
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
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: const Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 18),
                Text(
                  'Preparing your commute data...',
                  style: TextStyle(
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
  static const double _bottomToolbarHorizontalMargin = 14;
  static const double _bottomToolbarBottomMargin = 14;
  static const double _bottomToolbarRadius = 30;

  final Connectivity connectivity = Connectivity();
  StreamSubscription<dynamic>? connectivitySubscription;
  Timer? bannerTimer;

  Timer? _tabSwitchTimer;

  int currentIndex = 0;
  final List<int> screenGenerations = <int>[0, 0, 0, 0];
  bool isConnected = true;
  _NetworkBannerType bannerType = _NetworkBannerType.hidden;

  @override
  void initState() {
    super.initState();
    currentIndex = widget.initialIndex;
    NavigationState.instance.selectedIndex.value = currentIndex;
    initializeConnectivity();
    NavigationState.instance.selectedIndex
        .addListener(_handleExternalNavigation);
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
      setState(() => bannerType = _NetworkBannerType.disconnected);
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
      TrackRouteScreen(key: ValueKey('track_${screenGenerations[2]}')),
      ProfileScreen(key: ValueKey('profile_${screenGenerations[3]}')),
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
          ValueListenableBuilder<bool>(
            valueListenable: ClosingTimeService.instance.isClosingSoon,
            builder: (context, closingSoon, _) {
              if (!closingSoon) return const SizedBox.shrink();
              final remaining = ClosingTimeService.instance.minutesUntilCloseFormatted;
              return IgnorePointer(
                ignoring: true,
                child: SafeArea(
                  minimum: const EdgeInsets.only(top: 44, left: 12, right: 12),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 260),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626),
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: appCardShadows(context),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.access_time_rounded, size: 16, color: Colors.white),
                          const SizedBox(width: 8),
                          Text(
                            'Trains closing in $remaining',
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
              );
            },
          ),
        ],
      ),
      bottomNavigationBar: Stack(
        clipBehavior: Clip.none,
        children: [
          SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(
              _bottomToolbarHorizontalMargin,
              10,
              _bottomToolbarHorizontalMargin,
              _bottomToolbarBottomMargin,
            ),
            child: Container(
              height: _bottomToolbarHeight,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    scheme.surface,
                    Color.lerp(scheme.surface, scheme.primary, 0.03) ??
                        scheme.surface,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(_bottomToolbarRadius),
                border: Border.all(
                  color: scheme.primary.withValues(alpha: 0.12),
                ),
                boxShadow: [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.10),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                  const BoxShadow(
                    color: Color(0x14101828),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
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
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                      color: selected
                          ? scheme.primary
                          : scheme.onSurface.withValues(alpha: 0.62),
                    );
                  }),
                  iconTheme: WidgetStateProperty.resolveWith((states) {
                    final selected = states.contains(WidgetState.selected);
                    return IconThemeData(
                      size: selected ? 25 : 22,
                      color: selected
                          ? scheme.primary
                          : scheme.onSurface.withValues(alpha: 0.62),
                    );
                  }),
                  indicatorColor: scheme.primary.withValues(alpha: 0.12),
                  indicatorShape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                ),
                child: NavigationBar(
                  selectedIndex: currentIndex,
                  onDestinationSelected: handleTabSwitch,
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home_rounded),
                      label: 'Home',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.map_outlined),
                      selectedIcon: Icon(Icons.map_rounded),
                      label: 'Map',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.route_outlined),
                      selectedIcon: Icon(Icons.route_rounded),
                      label: 'Track',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.person_outline_rounded),
                      selectedIcon: Icon(Icons.person_rounded),
                      label: 'Profile',
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Positioned(
            right: 18,
            bottom: 10,
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
        final color = connected ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
        final label = connected ? 'LIVE' : 'OFFLINE';
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
    final visible = type != _NetworkBannerType.hidden;
    final isConnected = type == _NetworkBannerType.connected;
    final color =
        isConnected ? const Color(0xFF16A34A) : const Color(0xFF111827);
    final text = isConnected ? 'You are connected' : 'Disconnected';
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
