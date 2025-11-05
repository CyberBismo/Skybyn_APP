import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'services/translation_service.dart';
import 'widgets/background_gradient.dart';

Future<void> main() async {
  // Gate all print calls behind a debug flag using Zone
  // Logging enabled for debugging FCM token
  const bool enableLogging = true;

  runZonedGuarded(
    () async {
      // Ensure Flutter is initialized first
      WidgetsFlutterBinding.ensureInitialized();

      // Set preferred orientations to portrait only
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);

      // Initialize HTTP overrides to handle SSL certificates
      HttpOverrides.global = MyHttpOverrides();

      // Initialize theme and translation services in parallel (non-blocking)
      final themeService = ThemeService();
      final translationService = TranslationService();
      
      // Run theme service initialization (fast, local only)
      await themeService.initialize();

      // Run the app immediately - don't wait for translation service or Firebase
      runApp(ChangeNotifierProvider.value(value: themeService, child: const MyApp()));

      // Initialize translation service and Firebase in background (non-blocking)
      // These will complete after the app UI is already shown
      Future.wait([
        translationService.initialize(),
        _initializeFirebase(),
      ]).catchError((error) {
        if (enableLogging) {
          print('⚠️ [Startup] Background initialization error: $error');
        }
      });
    },
    (error, stack) {
      if (enableLogging) {
        // ignore: avoid_print
        print('Uncaught zone error: $error');
      }
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        if (enableLogging) {
          parent.print(zone, line);
        }
      },
    ),
  );
}

Future<void> _initializeFirebase() async {
  // Skip Firebase on iOS - it requires APN configuration which is not set up
  if (Platform.isIOS) {
    print('ℹ️ [Firebase] Skipping Firebase initialization on iOS (APN not configured)');
    print('ℹ️ [Firebase] iOS will use WebSocket only for notifications');
    return;
  }

  try {
    print('🔄 [Firebase] Starting Firebase initialization...');
    
    // Check if Firebase is already initialized
    if (Firebase.apps.isEmpty) {
      print('🔄 [Firebase] Initializing Firebase Core...');
      try {
        await Firebase.initializeApp();
        print('✅ [Firebase] Firebase Core initialized successfully');
      } catch (e) {
        print('❌ [Firebase] Failed to initialize Firebase Core: $e');
        rethrow; // Re-throw on Android to be caught by outer catch
      }
    } else {
      print('✅ [Firebase] Firebase Core already initialized');
    }

    // Initialize Firebase Messaging for push notifications (Android only)
    print('🔄 [Firebase] Starting Firebase Messaging initialization...');
    try {
      final firebaseMessagingService = FirebaseMessagingService();
      await firebaseMessagingService.initialize();

      // Auto-register FCM token when app opens if user is logged in
      await firebaseMessagingService.autoRegisterTokenOnAppOpen();
      print('✅ [Firebase] Firebase Messaging initialized successfully');
    } catch (e) {
      print('❌ [Firebase] Firebase Messaging initialization failed: $e');
    }
  } catch (e, stackTrace) {
    // Only print detailed error for Android
    print('❌ [Firebase] Firebase initialization failed: $e');
    print('Stack trace: $stackTrace');
    // Continue without Firebase - app will still work
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

// Global navigator key for showing dialogs from anywhere
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final NotificationService _notificationService = NotificationService();
  final WebSocketService _webSocketService = WebSocketService();
  bool _isAppInForeground = true;
  Timer? _serviceCheckTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // App starts in foreground
    _isAppInForeground = true;

    // Initialize services in the background
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    try {
      // Initialize notification and WebSocket services in parallel (non-blocking)
      await Future.wait([
        _notificationService.initialize(),
        _webSocketService.initialize(),
      ]);

      // Ensure background notification is hidden when app starts (in foreground)
      if (Platform.isAndroid) {
        _hideBackgroundNotification();
      }

      // Check for updates after a delay
      if (Platform.isAndroid) {
        Future.delayed(const Duration(seconds: 5), () {
      // Note: Context not available during app startup
      // Updates will be checked when user manually checks or when context is available
        });
      }
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
        // App is in foreground - hide notification immediately
        _isAppInForeground = true;
        _hideBackgroundNotification();
        break;
      case AppLifecycleState.paused:
        // App is definitely in background - show notification
        _isAppInForeground = false;
        _showBackgroundNotification();
        break;
      case AppLifecycleState.inactive:
        // Transitional state - app might still be visible (e.g., overlay, dialog)
        // Don't change notification state, keep current state
        break;
      case AppLifecycleState.hidden:
        // App is hidden - show notification
        _isAppInForeground = false;
        _showBackgroundNotification();
        break;
      case AppLifecycleState.detached:
        // App is being destroyed - show notification since app won't be visible
        _isAppInForeground = false;
        _showBackgroundNotification();
        break;
    }
  }
  
  Future<void> _showBackgroundNotification() async {
    // Only show if app is actually not in foreground
    if (!_isAppInForeground && Platform.isAndroid) {
      try {
        const platform = MethodChannel('no.skybyn.app/background_service');
        await platform.invokeMethod('showBackgroundNotification');
        print('✅ [MyApp] Background notification shown (app is in background)');
      } catch (e) {
        print('❌ [MyApp] Error showing background notification: $e');
      }
    } else {
      print('ℹ️ [MyApp] Skipping background notification (app is in foreground: $_isAppInForeground)');
    }
  }
  
  Future<void> _hideBackgroundNotification() async {
    // Always hide when app is in foreground
    if (Platform.isAndroid) {
      try {
        const platform = MethodChannel('no.skybyn.app/background_service');
        await platform.invokeMethod('hideBackgroundNotification');
        print('✅ [MyApp] Background notification hidden (app is in foreground)');
      } catch (e) {
        print('❌ [MyApp] Error hiding background notification: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Web platform colors
    const webLightPrimary = Color.fromRGBO(72, 198, 239, 1.0); // Light blue from web light mode
    const webLightSecondary = Color.fromRGBO(111, 134, 214, 1.0); // Blue from web light mode
    const webDarkPrimary = Color.fromRGBO(36, 59, 85, 1.0); // Dark blue from web dark mode
    const webDarkSecondary = Color.fromRGBO(20, 30, 48, 1.0); // Almost black from web dark mode

    return Consumer<ThemeService>(
      builder: (context, themeService, child) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          title: 'Skybyn',
          theme: ThemeData(
            brightness: Brightness.light,
            primaryColor: webLightPrimary,
            scaffoldBackgroundColor: webLightPrimary,
            colorScheme: const ColorScheme.light(brightness: Brightness.light, primary: webLightPrimary, secondary: webLightSecondary, surface: webLightPrimary, onPrimary: Colors.white, onSecondary: Colors.white, onSurface: Colors.white),
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.transparent,
              elevation: 0,
              iconTheme: IconThemeData(color: Colors.white),
              actionsIconTheme: IconThemeData(color: Colors.white),
              titleTextStyle: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            snackBarTheme: SnackBarThemeData(
              backgroundColor: Colors.transparent,
              contentTextStyle: const TextStyle(color: Colors.white),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              behavior: SnackBarBehavior.fixed,
              elevation: 0,
            ),
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primaryColor: webDarkPrimary,
            scaffoldBackgroundColor: webDarkPrimary,
            colorScheme: const ColorScheme.dark(brightness: Brightness.dark, primary: webDarkPrimary, secondary: webDarkSecondary, surface: webDarkPrimary, onPrimary: Colors.white, onSecondary: Colors.white, onSurface: Colors.white),
            appBarTheme: const AppBarTheme(
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
            return MaterialPageRoute(builder: (context) => const HomeScreen());
          },
          builder: (context, child) {
            return GestureDetector(
              onTap: () {
                FocusService().unfocusAll();
              },
              behavior: HitTestBehavior.translucent,
              child: AnimatedSwitcher(duration: const Duration(milliseconds: 300), child: child!),
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

    _fadeController = AnimationController(duration: const Duration(milliseconds: 800), vsync: this);

    _fadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));

    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    try {
      await _authService.initPrefs();
      final userId = await _authService.getStoredUserId();
      final userProfile = await _authService.getStoredUserProfile();

      if (mounted) {
        if (userId != null) {
          if (userProfile != null) {
            Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (context) => const HomeScreen()));
          } else {
            // Try to fetch the profile again
            try {
              final username = await _authService.getStoredUsername();
              if (username != null) {
                final profile = await _authService.fetchUserProfile(username);
                if (profile != null) {
                  Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (context) => const HomeScreen()));
                } else {
                  Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (context) => const LoginScreen()));
                }
              } else {
                Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (context) => const LoginScreen()));
              }
            } catch (e) {
              Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (context) => const LoginScreen()));
            }
          }
        } else {
          Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (context) => const LoginScreen()));
        }
      }
    } catch (e) {
      print('❌ [Auth] Error during authentication check: $e');
      if (mounted) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (context) => const LoginScreen()));
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
                Image.asset('assets/images/logo.png', width: 150, height: 150),
                const SizedBox(height: 30),
                const CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
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
    return super.createHttpClient(context)..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}
