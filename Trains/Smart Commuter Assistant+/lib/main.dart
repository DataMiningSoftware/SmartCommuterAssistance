import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/map_view.dart';
import 'screens/profile_screen.dart';
import 'services/auth_service.dart';
import 'services/database_service.dart';
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

  runApp(const SmartCommuterApp());
}

class SmartCommuterApp extends StatelessWidget {
  const SmartCommuterApp({super.key});

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF0A3A8B);
    const secondary = Color(0xFFD7263D);
    const tertiary = Color(0xFFF4B400);
    const surface = Color(0xFFF4F7FC);

    return MaterialApp(
      title: 'Smart Commuter Assistant+',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primary,
          primary: primary,
          secondary: secondary,
          tertiary: tertiary,
          surface: surface,
        ),
        scaffoldBackgroundColor: surface,
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Colors.transparent,
          foregroundColor: Color(0xFF0E1C3B),
          titleTextStyle: TextStyle(
            color: Color(0xFF0E1C3B),
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        textTheme: const TextTheme(
          headlineSmall:
              TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.2),
          titleLarge:
              TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.2),
          titleMedium: TextStyle(fontWeight: FontWeight.w600),
          bodyLarge: TextStyle(height: 1.3),
        ),
        cardTheme: const CardThemeData(
          elevation: 0,
          color: Colors.white,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(20)),
            side: BorderSide(color: Color(0xFFE6EBF5)),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            backgroundColor: primary,
            foregroundColor: Colors.white,
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
            borderSide: const BorderSide(color: primary, width: 1.6),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
      home: const AuthGate(),
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
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<dynamic>? _connectivitySubscription;
  Timer? _bannerTimer;
  Timer? _tabSwitchTimer;

  int _currentIndex = 0;
  final List<int> _screenGenerations = <int>[0, 0, 0];
  bool _isConnected = true;
  bool _isTabSwitching = false;
  _NetworkBannerType _bannerType = _NetworkBannerType.hidden;

  @override
  void initState() {
    super.initState();
    _initializeConnectivity();
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _tabSwitchTimer?.cancel();
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  Future<void> _initializeConnectivity() async {
    final initial = await _connectivity.checkConnectivity();
    if (!mounted) return;
    _applyConnectivity(initial, isInitial: true);

    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen((event) {
      _applyConnectivity(event);
    });
  }

  void _applyConnectivity(dynamic event, {bool isInitial = false}) {
    final connected = _eventHasConnection(event);
    final previouslyConnected = _isConnected;
    if (!isInitial && connected == previouslyConnected) {
      return;
    }

    _isConnected = connected;
    if (!connected) {
      _bannerTimer?.cancel();
      if (!mounted) return;
      setState(() => _bannerType = _NetworkBannerType.disconnected);
      return;
    }

    if (isInitial || previouslyConnected) {
      if (!mounted) return;
      setState(() => _bannerType = _NetworkBannerType.hidden);
      return;
    }

    _bannerTimer?.cancel();
    if (!mounted) return;
    setState(() => _bannerType = _NetworkBannerType.connected);
    _refreshCurrentScreen();
    _bannerTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _bannerType = _NetworkBannerType.hidden);
    });
  }

  bool _eventHasConnection(dynamic event) {
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

  void _refreshCurrentScreen() {
    if (_currentIndex < 0 || _currentIndex >= _screenGenerations.length) {
      return;
    }
    setState(() {
      _screenGenerations[_currentIndex] = _screenGenerations[_currentIndex] + 1;
    });
  }

  Widget _buildCurrentScreen() {
    switch (_currentIndex) {
      case 0:
        return HomeScreen(key: ValueKey('home_${_screenGenerations[0]}'));
      case 1:
        return MapView(key: ValueKey('map_${_screenGenerations[1]}'));
      case 2:
      default:
        return ProfileScreen(key: ValueKey('profile_${_screenGenerations[2]}'));
    }
  }

  void _handleTabSwitch(int index) {
    if (index == _currentIndex) return;
    _tabSwitchTimer?.cancel();
    setState(() {
      _currentIndex = index;
      _isTabSwitching = true;
    });
    _tabSwitchTimer = Timer(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      setState(() => _isTabSwitching = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          TrainLoadingTransition(
            isLoading: _isTabSwitching,
            loadingLabel: 'Loading page...',
            arrivalLabel: 'Page ready',
            child: _buildCurrentScreen(),
          ),
          _NetworkStatusBanner(type: _bannerType),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFFE3E9F5))),
        ),
        child: NavigationBar(
          height: 70,
          backgroundColor: Colors.white,
          indicatorColor:
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
          selectedIndex: _currentIndex,
          onDestinationSelected: _handleTabSwitch,
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Home'),
            NavigationDestination(
                icon: Icon(Icons.map_outlined),
                selectedIcon: Icon(Icons.map),
                label: 'Map'),
            NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Profile'),
          ],
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
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x2F000000),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
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
