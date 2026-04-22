import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'constants/app_shadows.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/map_view.dart';
import 'screens/profile_screen.dart';
import 'screens/track_route_screen.dart';
import 'services/active_trip_service.dart';
import 'services/auth_service.dart';
import 'services/database_service.dart';
import 'services/navigation_state.dart';
import 'services/notification_service.dart';
import 'services/theme_controller.dart';
import 'widgets/train_loading_transition.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const defaultSupabaseUrl = 'https://imrozxnhigihxcwlribr.supabase.co';
  const defaultSupabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imltcm96eG5oaWdpaHhjd2xyaWJyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM5Mjg5MTgsImV4cCI6MjA4OTUwNDkxOH0.JEPPPrSFWZRgtYP4maS1iz-4MHOnY06ua4ZvwHKzZWk';

  const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: defaultSupabaseUrl,
  );
  const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: defaultSupabaseAnonKey,
  );

  assert(() {
    debugPrint('SUPABASE_URL=$supabaseUrl');
    final keyPreview = supabaseAnonKey.length >= 10
        ? supabaseAnonKey.substring(0, 10)
        : supabaseAnonKey;
    debugPrint('SUPABASE_ANON_KEY prefix=$keyPreview');
    return true;
  }());

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  await DatabaseService().initialize();
  await AuthService().initialize();
  await ActiveTripService.instance.initialize();
  await NotificationService().initialize();
  await ThemeController.initialize();

  runApp(const SmartCommuterApp());
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
          themeMode: mode,
          theme: lightTheme,
          darkTheme: darkTheme,
          home: const AuthGate(),
        );
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
  Timer? tabSwitchTimer;

  int currentIndex = 0;
  final List<int> screenGenerations = <int>[0, 0, 0, 0];
  bool isConnected = true;
  bool isTabSwitching = false;
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
    tabSwitchTimer?.cancel();
    connectivitySubscription?.cancel();
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

  Widget buildCurrentScreen() {
    switch (currentIndex) {
      case 0:
        return HomeScreen(key: ValueKey('home_${screenGenerations[0]}'));
      case 1:
        return MapView(key: ValueKey('map_${screenGenerations[1]}'));
      case 2:
        return TrackRouteScreen(key: ValueKey('track_${screenGenerations[2]}'));
      case 3:
      default:
        return ProfileScreen(key: ValueKey('profile_${screenGenerations[3]}'));
    }
  }

  void handleTabSwitch(int index) {
    if (index == currentIndex) return;
    tabSwitchTimer?.cancel();
    setState(() {
      currentIndex = index;
      isTabSwitching = true;
    });
    NavigationState.instance.selectedIndex.value = index;
    tabSwitchTimer = Timer(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      setState(() => isTabSwitching = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      body: Stack(
        children: [
          TrainLoadingTransition(
            isLoading: isTabSwitching,
            loadingLabel: 'Loading page...',
            arrivalLabel: 'Page ready',
            child: buildCurrentScreen(),
          ),
          _NetworkStatusBanner(type: bannerType),
        ],
      ),
      bottomNavigationBar: SafeArea(
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
