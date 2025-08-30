import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
// import 'dart:io' show Platform;
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'dart:io';
import 'package:provider/provider.dart';
import 'services/theme_service.dart';
// Import for SystemChrome
import 'dart:async';
import 'services/focus_service.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'services/websocket_service.dart';
import 'services/firebase_messaging_service.dart';
import 'widgets/background_gradient.dart';

Future<void> main() async {
  // Gate all print calls behind a debug flag using Zone
  const bool enableLogging = bool.fromEnvironment('SKYBYN_DEBUG_LOGS', defaultValue: false);
  
  runZonedGuarded(() async {
    // Ensure Flutter is initialized first
    WidgetsFlutterBinding.ensureInitialized();
    
    // Initialize HTTP overrides to handle SSL certificates
    HttpOverrides.global = MyHttpOverrides();
    
    // Initialize theme service first
    final themeService = ThemeService();
    await themeService.initialize();
    
    // Run the app
    runApp(
      ChangeNotifierProvider.value(
        value: themeService,
        child: const MyApp(),
      ),
    );
    
    // Initialize Firebase in the background (non-blocking)
    _initializeFirebaseInBackground();
  }, (error, stack) {
    if (enableLogging) {
      // ignore: avoid_print
      print('Uncaught zone error: $error');
    }
  }, zoneSpecification: ZoneSpecification(
    print: (self, parent, zone, line) {
      if (enableLogging) {
        parent.print(zone, line);
      }
    },
  ));
}

Future<void> _initializeFirebaseInBackground() async {
  try {
    print('🔄 [Firebase] Starting background initialization...');
    
    // Check if Firebase is already initialized
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
      print('✅ [Firebase] Firebase initialized successfully');
    } else {
      print('ℹ️ [Firebase] Firebase already initialized, skipping...');
    }
    
    // Initialize Firebase Messaging for background notifications (Android only)
    if (Platform.isAndroid) {
      try {
        final firebaseMessagingService = FirebaseMessagingService();
        await firebaseMessagingService.initialize();
        print('✅ [Firebase] Firebase Messaging initialized for background notifications');
      } catch (e) {
        print('❌ [Firebase] Firebase Messaging initialization failed: $e');
      }
    } else {
      print('ℹ️ [Firebase] Firebase Messaging skipped for iOS (using WebSocket instead)');
    }
  } catch (e) {
    print('❌ [Firebase] Background initialization failed: $e');
    // Continue without Firebase - app will still work
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final NotificationService _notificationService = NotificationService();
  final WebSocketService _webSocketService = WebSocketService();
  bool _isAppInForeground = true;
  Timer? _serviceCheckTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Initialize services in the background
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    try {
      // Initialize notification service
      await _notificationService.initialize();
      
      // Initialize WebSocket service
      await _webSocketService.initialize();
    } catch (e) {
      print('❌ [Services] Error initializing services: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _serviceCheckTimer?.cancel(); // This can be removed if _serviceCheckTimer is not used elsewhere
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.resumed:
        print('🔄 App resumed');
        _isAppInForeground = true;
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        print('🔄 App paused/inactive');
        _isAppInForeground = false;
        break;
      case AppLifecycleState.detached:
        print('🔄 App detached - keeping background service running');
        // Don't stop background service when app is detached
        break;
      case AppLifecycleState.hidden:
        print('🔄 App hidden');
        _isAppInForeground = false;
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Web platform colors
    const webLightPrimary = Color(0xFF48C6EF); // Light blue from web light mode
    const webLightSecondary = Color(0xFF6F86D6); // Blue from web light mode
    const webDarkPrimary = Color(0xFF243B55); // Dark blue from web dark mode
    const webDarkSecondary = Color(0xFF141E30); // Almost black from web dark mode

    return Consumer<ThemeService>(
      builder: (context, themeService, child) {
        return MaterialApp(
          title: 'Skybyn',
          theme: ThemeData(
            brightness: Brightness.light,
            primaryColor: webLightPrimary,
            scaffoldBackgroundColor: webLightPrimary,
            colorScheme: ColorScheme.light(
              brightness: Brightness.light,
              primary: webLightPrimary,
              secondary: webLightSecondary,
              surface: webLightPrimary,
              onPrimary: Colors.black,
              onSecondary: Colors.black,
              onSurface: Colors.black,
            ),
            appBarTheme: AppBarTheme(
              backgroundColor: Colors.transparent,
              elevation: 0,
              iconTheme: IconThemeData(color: Colors.black),
              actionsIconTheme: IconThemeData(color: Colors.black),
              titleTextStyle: TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            snackBarTheme: SnackBarThemeData(
              backgroundColor: Colors.transparent,
              contentTextStyle: TextStyle(color: Colors.black),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              behavior: SnackBarBehavior.fixed,
              elevation: 0,
            ),
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primaryColor: webDarkPrimary,
            scaffoldBackgroundColor: webDarkPrimary,
            colorScheme: ColorScheme.dark(
              brightness: Brightness.dark,
              primary: webDarkPrimary,
              secondary: webDarkSecondary,
              surface: webDarkPrimary,
              onPrimary: Colors.white,
              onSecondary: Colors.white,
              onSurface: Colors.white,
            ),
            appBarTheme: AppBarTheme(
              backgroundColor: Colors.transparent,
              elevation: 0,
              iconTheme: IconThemeData(color: Colors.white),
              actionsIconTheme: IconThemeData(color: Colors.white),
              titleTextStyle: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          themeMode: themeService.themeMode,
          home: const _InitialScreen(),
          onUnknownRoute: (settings) {
            print('⚠️ Unknown route: ${settings.name}, redirecting to home');
            return MaterialPageRoute(builder: (context) => const HomeScreen());
          },
          builder: (context, child) {
            return GestureDetector(
              onTap: () {
                FocusService().unfocusAll();
              },
              behavior: HitTestBehavior.translucent,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: child!,
              ),
            );
          },
        );
      },
    );
  }
}

class _InitialScreen extends StatefulWidget {
  const _InitialScreen();

  @override
  State<_InitialScreen> createState() => __InitialScreenState();
}

class __InitialScreenState extends State<_InitialScreen> with TickerProviderStateMixin {
  final AuthService _authService = AuthService();
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  final bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    ));
    
    print('🚀 [Splash] InitialScreen initState called');
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    print('🔍 [Auth] Starting authentication check...');
    
    // Add a small delay to ensure the UI is ready
    await Future.delayed(const Duration(milliseconds: 500));
    
    try {
      final userId = await _authService.getStoredUserId();
      final userProfile = await _authService.getStoredUserProfile();
      
      print('🔍 [Auth] User ID: $userId');
      print('🔍 [Auth] User Profile: $userProfile');
      
      if (mounted) {
        if (userId != null && userProfile != null) {
          print('🔍 [Auth] User is logged in, navigating to home screen');
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const HomeScreen()),
          );
        } else {
          print('🔍 [Auth] User is not logged in, navigating to login screen');
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const LoginScreen()),
          );
        }
      } else {
        print('🔍 [Auth] Widget not mounted, skipping navigation');
      }
    } catch (e) {
      print('❌ [Auth] Error during authentication check: $e');
      if (mounted) {
        print('🔍 [Auth] Navigating to login screen due to error');
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      }
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const BackgroundGradient(),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/images/logo.png',
                  width: 150,
                  height: 150,
                ),
                const SizedBox(height: 30),
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}
