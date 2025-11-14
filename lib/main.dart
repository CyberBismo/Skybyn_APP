import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
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
import 'services/firebase_realtime_service.dart';
import 'services/firebase_call_signaling_service.dart';
import 'services/firebase_messaging_service.dart';
import 'services/websocket_service.dart';
import 'services/translation_service.dart';
import 'services/background_update_scheduler.dart';
import 'services/background_activity_service.dart';
import 'services/call_service.dart';
import 'services/friend_service.dart';
import 'widgets/background_gradient.dart';
import 'widgets/incoming_call_notification.dart';
import 'screens/call_screen.dart';
import 'models/friend.dart';

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

      // Initialize theme and translation services
      final themeService = ThemeService();
      final translationService = TranslationService();
      
      // Run theme service initialization (fast, local only)
      await themeService.initialize();

      // Initialize translation service BEFORE showing UI to prevent translation keys from showing
      // This loads cached translations first (fast), then updates from API in background
      await translationService.initialize();

      // Initialize Firebase BEFORE running the app (needed for Firestore)
      await _initializeFirebase().catchError((error) {
        if (enableLogging) {
          print('⚠️ [Startup] Firebase initialization error: $error');
        }
      });

      // Run the app after Firebase and translations are loaded
      runApp(ChangeNotifierProvider.value(value: themeService, child: const MyApp()));
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
  try {
    print('🔄 [Firebase] Starting Firebase initialization...');
    
    // Always initialize Firebase Core (needed for Firestore)
    // Check if Firebase is already initialized
    if (Firebase.apps.isEmpty) {
      print('🔄 [Firebase] Initializing Firebase Core...');
      try {
        await Firebase.initializeApp();
        print('✅ [Firebase] Firebase Core initialized successfully');
      } catch (e) {
        print('❌ [Firebase] Failed to initialize Firebase Core: $e');
        rethrow; // Re-throw to be caught by outer catch
      }
    } else {
      print('✅ [Firebase] Firebase Core already initialized');
    }

    // Skip Firebase Messaging in debug mode (but Firestore still works)
    if (kDebugMode) {
      print('ℹ️ [Firebase] Skipping Firebase Messaging initialization in debug mode');
      print('ℹ️ [Firebase] Firestore is available for real-time communication');
      return;
    }

    // Skip Firebase Messaging on iOS - it requires APN configuration which is not set up
    if (Platform.isIOS) {
      print('ℹ️ [Firebase] Skipping Firebase Messaging initialization on iOS (APN not configured)');
      print('ℹ️ [Firebase] Firestore is available for real-time communication');
      return;
    }

    // Initialize Firebase Messaging for push notifications (Android release only)
    print('🔄 [Firebase] Starting Firebase Messaging initialization...');
    try {
      final firebaseMessagingService = FirebaseMessagingService();
      await firebaseMessagingService.initialize();

      // Token is already registered on app start in initialize() method
      // If user is logged in, it will be updated with user ID in auth_service.dart after login
      print('✅ [Firebase] Firebase Messaging initialized successfully');
    } catch (e) {
      print('❌ [Firebase] Firebase Messaging initialization failed: $e');
    }
  } catch (e, stackTrace) {
    // Print detailed error
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
  final FirebaseRealtimeService _firebaseRealtimeService = FirebaseRealtimeService();
  final WebSocketService _webSocketService = WebSocketService();
  final BackgroundUpdateScheduler _backgroundUpdateScheduler = BackgroundUpdateScheduler();
  final CallService _callService = CallService();
  final FriendService _friendService = FriendService();
  Timer? _serviceCheckTimer;
  Timer? _activityUpdateTimer;
  Timer? _webSocketConnectionCheckTimer;
  
  // Track active incoming call
  String? _activeCallId;
  Friend? _activeCallFriend;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Initialize services in the background
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    try {
      // Initialize notification and Firebase services in parallel (non-blocking)
      await Future.wait([
        _notificationService.initialize(),
        _firebaseRealtimeService.initialize(),
      ]);

      // Initialize background update scheduler
      await _backgroundUpdateScheduler.initialize();
      
      // Initialize background activity service (updates activity even when app is closed)
      await BackgroundActivityService.initialize();
      
      // Set up call callbacks for incoming calls via WebSocket
      _setupCallHandlers();
      
      // Set up WebSocket connection state listener
      _setupWebSocketConnectionListener();
      
      // Initialize and connect WebSocket globally (works from any screen)
      await _webSocketService.initialize();
      _connectWebSocketGlobally();

      // Start periodic activity updates (every 5 seconds when WebSocket is connected)
      _startActivityUpdates();

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

  /// Start periodic activity updates
  /// Updates activity every few seconds while WebSocket is connected
  void _startActivityUpdates() {
    // Cancel any existing timer
    _activityUpdateTimer?.cancel();
    
    // Update activity immediately
    _updateActivity();
    
    // Update every 5 seconds while WebSocket is connected
    // This keeps the user's last_active timestamp fresh and shows them as online
    _activityUpdateTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      // Only update if WebSocket is connected
      if (_webSocketService.isConnected) {
        _updateActivity();
      } else {
        // If WebSocket is not connected, stop the timer
        timer.cancel();
        _activityUpdateTimer = null;
      }
    });
  }

  /// Update user activity
  Future<void> _updateActivity() async {
    try {
      // Update activity in your own database only
      final authService = AuthService();
      await authService.updateActivity();
    } catch (e) {
      // Silently fail - activity updates are not critical
      if (kDebugMode) {
        print('⚠️ [MyApp] Failed to update activity: $e');
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _serviceCheckTimer?.cancel(); // This can be removed if _serviceCheckTimer is not used elsewhere
    _activityUpdateTimer?.cancel();
    _webSocketConnectionCheckTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.resumed:
        // App is in foreground - ensure Firebase and WebSocket are connected
        print('✅ [MyApp] App resumed - ensuring Firebase and WebSocket connections');
        // Reconnect Firebase if not connected (it may have been disconnected in background)
        if (!_firebaseRealtimeService.isConnected) {
          print('🔄 [MyApp] Firebase not connected, reconnecting...');
          _firebaseRealtimeService.connect();
        }
        // Always force reconnect WebSocket when app resumes to ensure connection is alive
        // The connection might appear connected but actually be dead after backgrounding
        print('🔄 [MyApp] Force reconnecting WebSocket to ensure active connection...');
        _webSocketService.forceReconnect().catchError((error) {
          print('❌ [MyApp] Error force reconnecting WebSocket: $error');
        });
        // Activity updates continue while WebSocket is connected
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        // App is in background - keep WebSocket connected to respond to pings
        // Activity updates continue while WebSocket is connected
        // Activity updates every 5 seconds while WebSocket is connected
        // Friends will see user as:
        // - Online: last_active <= 2 minutes
        // - Away: last_active > 2 minutes
        print('ℹ️ [MyApp] App backgrounded - keeping WebSocket connected for ping/pong');
        print('ℹ️ [MyApp] Activity updates continue while WebSocket is connected');
        break;
      case AppLifecycleState.detached:
        // App is being terminated - disconnect Firebase
        print('ℹ️ [MyApp] App detached - disconnecting Firebase');
        _firebaseRealtimeService.disconnect();
        // Online status is now calculated from last_active, no need to update
        break;
    }
  }

  /// Set up WebSocket connection state listener
  /// Manages activity updates based on WebSocket connection state
  void _setupWebSocketConnectionListener() {
    // Cancel any existing timer
    _webSocketConnectionCheckTimer?.cancel();
    
    // Check WebSocket connection state periodically
    _webSocketConnectionCheckTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!mounted) {
        timer.cancel();
        _webSocketConnectionCheckTimer = null;
        return;
      }
      
      final isConnected = _webSocketService.isConnected;
      
      // Manage activity updates based on WebSocket connection
      if (isConnected) {
        // WebSocket is connected - ensure activity updates are running
        if (_activityUpdateTimer == null || !_activityUpdateTimer!.isActive) {
          _startActivityUpdates();
        }
      } else {
        // Stop activity updates when disconnected
        _activityUpdateTimer?.cancel();
        _activityUpdateTimer = null;
      }
    });
  }

  /// Connect WebSocket globally (works from any screen)
  /// This ensures WebSocket is always connected as long as the app is running
  void _connectWebSocketGlobally() {
    print('🔄 [MyApp] Connecting WebSocket globally...');
    _webSocketService.connect().catchError((error) {
      print('❌ [MyApp] Error connecting WebSocket globally: $error');
    });
  }

  /// Set up call handlers for incoming calls via WebSocket
  void _setupCallHandlers() {
    // Set up call callbacks directly on WebSocketService
    // These will be used when WebSocket receives call signals
    _webSocketService.setCallCallbacks(
      onCallOffer: (callId, fromUserId, offer, callType) async {
        print('📞 [MyApp] Incoming call offer: callId=$callId, fromUserId=$fromUserId, type=$callType');
        
        // Check if app is in foreground
        final isAppInForeground = WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
        
        if (isAppInForeground) {
          // App is in foreground - show in-app notification
          await _handleIncomingCallInForeground(callId, fromUserId, offer, callType);
        } else {
          // App is in background - Firebase notification should be sent by server
          // But we can also handle it here if needed
          print('ℹ️ [MyApp] App is in background - Firebase notification should handle this');
        }
      },
      onCallAnswer: (callId, answer) {
        print('📞 [MyApp] Call answer received: callId=$callId');
        _callService.handleIncomingAnswer(answer);
      },
      onIceCandidate: (callId, candidate, sdpMid, sdpMLineIndex) {
        print('📞 [MyApp] ICE candidate received: callId=$callId');
        _callService.handleIceCandidate(
          candidate: candidate,
          sdpMid: sdpMid,
          sdpMLineIndex: sdpMLineIndex,
        );
      },
      onCallEnd: (callId, fromUserId, targetUserId) async {
        print('📞 [MyApp] Call ended: callId=$callId, fromUserId=$fromUserId, targetUserId=$targetUserId');
        
        // Get current user ID to determine if this call_end is for us
        final authService = AuthService();
        final currentUserId = await authService.getStoredUserId();
        if (currentUserId == null) return;
        
        // Check if this call_end is for the current user
        // Either we're the target (someone ended a call to us) or we're the sender (we ended a call)
        final isForCurrentUser = targetUserId == currentUserId || fromUserId == currentUserId;
        
        if (isForCurrentUser) {
          // Check if we have an active call that matches
          final activeOtherUserId = _callService.otherUserId;
          final activeCallId = _callService.currentCallId;
          
          // Match by callId if available, otherwise match by user ID
          final shouldEndCall = callId.isEmpty || 
                                 activeCallId == callId ||
                                 (activeOtherUserId != null && 
                                  (activeOtherUserId == fromUserId || activeOtherUserId == targetUserId));
          
          if (shouldEndCall) {
            // Clear active call tracking
            if (mounted) {
              setState(() {
                _activeCallId = null;
                _activeCallFriend = null;
              });
            }
            // End the call in CallService
            await _callService.endCall();
          }
        }
      },
      onCallError: (callId, targetUserId, errorMessage) async {
        print('❌ [MyApp] Call error: callId=$callId, targetUserId=$targetUserId, message=$errorMessage');
        
        // Get current user ID
        final authService = AuthService();
        final currentUserId = await authService.getStoredUserId();
        if (currentUserId == null) return;
        
        // Check if this error is for a call we initiated
        final activeOtherUserId = _callService.otherUserId;
        final activeCallId = _callService.currentCallId;
        
        if (activeCallId == callId || activeOtherUserId == targetUserId) {
          // This error is for our active call
          // End the call and show error message
          await _callService.endCall();
          
          // Show error to user
          if (mounted) {
            final context = navigatorKey.currentContext;
            if (context != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(errorMessage),
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          }
          
          // Clear active call tracking
          if (mounted) {
            setState(() {
              _activeCallId = null;
              _activeCallFriend = null;
            });
          }
        }
      },
    );
  }

  /// Handle incoming call when app is in foreground
  Future<void> _handleIncomingCallInForeground(
    String callId,
    String fromUserId,
    String offer,
    String callType,
  ) async {
    try {
      // Get current user ID
      final authService = AuthService();
      final currentUserId = await authService.getStoredUserId();
      if (currentUserId == null) {
        print('⚠️ [MyApp] Cannot handle incoming call - no user logged in');
        return;
      }

      // Fetch friend information
      final friends = await _friendService.fetchFriendsForUser(userId: currentUserId);
      final friend = friends.firstWhere(
        (f) => f.id == fromUserId,
        orElse: () => Friend(
          id: fromUserId,
          username: fromUserId, // Fallback
          nickname: '',
          avatar: '',
          online: false,
        ),
      );

      // Store active call info
      setState(() {
        _activeCallId = callId;
        _activeCallFriend = friend;
      });

      // Show in-app call notification
      final context = navigatorKey.currentContext;
      if (context != null) {
        showDialog(
          context: context,
          barrierDismissible: false,
          barrierColor: Colors.black.withOpacity(0.5),
          builder: (dialogContext) => Center(
            child: IncomingCallNotification(
            callId: callId,
            fromUserId: fromUserId,
            fromUsername: friend.nickname.isNotEmpty ? friend.nickname : friend.username,
            avatarUrl: friend.avatar,
            callType: callType == 'video' ? CallType.video : CallType.audio,
            onAccept: () async {
              Navigator.of(dialogContext).pop();
              
              // Handle the incoming offer
              await _callService.handleIncomingOffer(
                callId: callId,
                fromUserId: fromUserId,
                offer: offer,
                callType: callType,
              );

              // Navigate to call screen
              if (context.mounted) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => CallScreen(
                      friend: friend,
                      callType: callType == 'video' ? CallType.video : CallType.audio,
                      isIncoming: true,
                    ),
                  ),
                );
              }
            },
            onReject: () async {
              Navigator.of(dialogContext).pop();
              
              // Reject the call
              await _callService.rejectCall();
              
              // Clear active call tracking
              setState(() {
                _activeCallId = null;
                _activeCallFriend = null;
              });
            },
          ),
        ),
        );
      }
    } catch (e) {
      print('❌ [MyApp] Error handling incoming call: $e');
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
          title: kDebugMode ? 'Skybyn DEV' : 'Skybyn',
          theme: ThemeData(
            brightness: Brightness.light,
            primaryColor: webLightPrimary,
            scaffoldBackgroundColor: webLightPrimary,
            colorScheme: const ColorScheme.light(brightness: Brightness.light, primary: webLightPrimary, secondary: webLightSecondary, surface: webLightPrimary, onPrimary: Colors.white, onSecondary: Colors.white, onSurface: Colors.white),
            textTheme: const TextTheme(
              displayLarge: TextStyle(decoration: TextDecoration.none),
              displayMedium: TextStyle(decoration: TextDecoration.none),
              displaySmall: TextStyle(decoration: TextDecoration.none),
              headlineLarge: TextStyle(decoration: TextDecoration.none),
              headlineMedium: TextStyle(decoration: TextDecoration.none),
              headlineSmall: TextStyle(decoration: TextDecoration.none),
              titleLarge: TextStyle(decoration: TextDecoration.none),
              titleMedium: TextStyle(decoration: TextDecoration.none),
              titleSmall: TextStyle(decoration: TextDecoration.none),
              bodyLarge: TextStyle(decoration: TextDecoration.none),
              bodyMedium: TextStyle(decoration: TextDecoration.none),
              bodySmall: TextStyle(decoration: TextDecoration.none),
              labelLarge: TextStyle(decoration: TextDecoration.none),
              labelMedium: TextStyle(decoration: TextDecoration.none),
              labelSmall: TextStyle(decoration: TextDecoration.none),
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.transparent,
              elevation: 0,
              iconTheme: IconThemeData(color: Colors.white),
              actionsIconTheme: IconThemeData(color: Colors.white),
              titleTextStyle: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, decoration: TextDecoration.none),
            ),
            snackBarTheme: SnackBarThemeData(
              backgroundColor: Colors.transparent,
              contentTextStyle: const TextStyle(color: Colors.white, decoration: TextDecoration.none),
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
            textTheme: const TextTheme(
              displayLarge: TextStyle(decoration: TextDecoration.none),
              displayMedium: TextStyle(decoration: TextDecoration.none),
              displaySmall: TextStyle(decoration: TextDecoration.none),
              headlineLarge: TextStyle(decoration: TextDecoration.none),
              headlineMedium: TextStyle(decoration: TextDecoration.none),
              headlineSmall: TextStyle(decoration: TextDecoration.none),
              titleLarge: TextStyle(decoration: TextDecoration.none),
              titleMedium: TextStyle(decoration: TextDecoration.none),
              titleSmall: TextStyle(decoration: TextDecoration.none),
              bodyLarge: TextStyle(decoration: TextDecoration.none),
              bodyMedium: TextStyle(decoration: TextDecoration.none),
              bodySmall: TextStyle(decoration: TextDecoration.none),
              labelLarge: TextStyle(decoration: TextDecoration.none),
              labelMedium: TextStyle(decoration: TextDecoration.none),
              labelSmall: TextStyle(decoration: TextDecoration.none),
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.transparent,
              elevation: 0,
              iconTheme: IconThemeData(color: Colors.white),
              actionsIconTheme: IconThemeData(color: Colors.white),
              titleTextStyle: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, decoration: TextDecoration.none),
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
      // Add timeout to ensure we always navigate
      await _authService.initPrefs().timeout(const Duration(seconds: 5));
      final userId = await _authService.getStoredUserId();
      final userProfile = await _authService.getStoredUserProfile();

      if (mounted) {
        if (userId != null) {
          if (userProfile != null) {
            Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (context) => const HomeScreen()));
            return;
          } else {
            // Try to fetch the profile again
            try {
              final username = await _authService.getStoredUsername();
              if (username != null) {
                final profile = await _authService.fetchUserProfile(username).timeout(const Duration(seconds: 5));
                if (profile != null && mounted) {
                  Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (context) => const HomeScreen()));
                  return;
                }
              }
            } catch (e) {
              print('⚠️ [Auth] Error fetching profile: $e');
            }
          }
        }
        // Navigate to login if we reach here
        if (mounted) {
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
      backgroundColor: Colors.grey[900], // Grey background during initial load
      body: Stack(
        children: [
          Container(color: Colors.grey[900]), // Grey background
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
    final client = super.createHttpClient(context);
    
    // Only bypass SSL certificate validation in debug mode
    // This allows dev servers with self-signed certificates to work
    if (kDebugMode) {
      client.badCertificateCallback = (X509Certificate cert, String host, int port) {
        print('⚠️ [HTTP] Accepting certificate for $host:$port in debug mode');
        return true; // Accept all certificates in debug mode
      };
    }
    // In release mode, use default SSL validation (secure)
    
    return client;
  }
}
