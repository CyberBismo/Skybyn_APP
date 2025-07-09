import 'package:flutter/material.dart';
// import 'dart:io' show Platform;
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/qr_scanner_screen.dart';
import 'screens/notification_test_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/profile_screen.dart';
import 'dart:io';
import 'screens/biometric_screen.dart';
import 'services/local_auth_service.dart';
import 'package:provider/provider.dart';
import 'services/theme_service.dart';
import 'package:flutter/services.dart'; // Import for SystemChrome
import 'dart:async';
import 'services/focus_service.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'services/background_service.dart';
import 'widgets/background_gradient.dart';

Future<void> main() async {
  // Ensure Flutter is initialized first
  WidgetsFlutterBinding.ensureInitialized();
  
  print('🚀 App starting...');
  
  try {
    // Initialize notification service
    final notificationService = NotificationService();
    await notificationService.initialize();
    print('✅ Notification service initialized');
    
    // Initialize background service
    final backgroundService = BackgroundService();
    await backgroundService.initialize();
    print('✅ Background service initialized');
    
    // Create theme service without async initialization
    final themeService = ThemeService();
    print('✅ Theme service created');
    
    // Run the app
    runApp(
      ChangeNotifierProvider(
        create: (_) => themeService,
        child: const MyApp(),
      ),
    );
    
    print('✅ App launched successfully');
  } catch (e, stackTrace) {
    print('❌ Critical error during app initialization: $e');
    print('Stack trace: $stackTrace');
    
    // Fallback: run app with minimal initialization
    runApp(
      MaterialApp(
        title: 'Skybyn',
        home: const Scaffold(
          body: Center(
            child: Text('App initialization failed. Please restart.'),
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const primaryBlue = Color(0xFF0D47A1);

    return Consumer<ThemeService>(
      builder: (context, themeService, child) {
        return MaterialApp(
          title: 'Skybyn',
          theme: ThemeData(
            brightness: Brightness.light,
            primaryColor: primaryBlue,
            scaffoldBackgroundColor: const Color(0xFF0D47A1),
            colorScheme: ColorScheme.light(
              primary: primaryBlue,
              secondary: const Color(0xFF6495ED),
              background: const Color(0xFF0D47A1),
              surface: const Color(0xFF0D47A1),
              onPrimary: Colors.white,
              onSecondary: Colors.white,
              onBackground: Colors.white,
              onSurface: Colors.white,
            ),
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              behavior: SnackBarBehavior.fixed,
              elevation: 0,
            ),
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primaryColor: primaryBlue,
            scaffoldBackgroundColor: Colors.black,
            colorScheme: ColorScheme.dark(
              primary: primaryBlue,
              secondary: const Color(0xFF000000),
              background: Colors.black,
              surface: Colors.black,
              onPrimary: Colors.white,
              onSecondary: Colors.white,
              onBackground: Colors.white,
              onSurface: Colors.white,
            ),
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
  const _InitialScreen({super.key});

  @override
  State<_InitialScreen> createState() => __InitialScreenState();
}

class __InitialScreenState extends State<_InitialScreen> with TickerProviderStateMixin {
  final AuthService _authService = AuthService();
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  OverlayEntry? _splashOverlay;

  @override
  void initState() {
    super.initState();
    print('🚀 _InitialScreen initState called');
    
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
    
    // Listen to animation completion
    _fadeController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _splashOverlay?.remove();
        _splashOverlay = null;
      }
    });
    
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    try {
      print('🔍 Checking authentication status...');
      
      final userId = await _authService.getStoredUserId();
      final userProfile = await _authService.getStoredUserProfile();
      
      print('📱 Stored user ID: $userId');
      print('👤 Stored user profile: ${userProfile?.username ?? 'None'}');
      
      if (mounted) {
        if (userId != null && userProfile != null) {
          print('✅ User is authenticated, navigating to home');
          // Navigate to home screen
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const HomeScreen()),
          );
        } else {
          print('❌ User is not authenticated, navigating to login');
          // Navigate to login screen
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const LoginScreen()),
          );
        }
        
        // Wait for the new screen to be fully loaded, then fade out splash overlay
        WidgetsBinding.instance.addPostFrameCallback((_) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _fadeController.forward();
            }
          });
        });
      }
    } catch (e) {
      print('❌ Error checking auth status: $e');
      if (mounted) {
        // Navigate to login screen
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
        
        // Wait for the new screen to be fully loaded, then fade out splash overlay
        WidgetsBinding.instance.addPostFrameCallback((_) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _fadeController.forward();
            }
          });
        });
      }
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _splashOverlay?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    print('🎨 Building _InitialScreen widget');
    
    // Create splash overlay that will fade out over the new screen
    _splashOverlay = OverlayEntry(
      builder: (context) => FadeTransition(
        opacity: _fadeAnimation,
        child: Material(
          color: Colors.transparent,
          child: Stack(
            children: [
              const BackgroundGradient(),
              Center(
                child: Image.asset(
                  'assets/images/logo.png',
                  width: 200,
                  height: 200,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    
    // Insert the overlay
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Overlay.of(context).insert(_splashOverlay!);
      }
    });
    
    // Return empty scaffold - the splash screen is now an overlay
    return const Scaffold(
      body: SizedBox.shrink(),
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
