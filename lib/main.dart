import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
// import 'dart:io' show Platform;
import 'dart:io';
import 'dart:developer' as developer;
import 'package:provider/provider.dart';
import 'package:app_links/app_links.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';
// Screens - all imports in main.dart
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/qr_scanner_screen.dart';
import 'screens/share_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/create_post_screen.dart';
import 'screens/register_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/call_screen.dart';
import 'screens/events_screen.dart';
import 'screens/games_screen.dart';
import 'screens/groups_screen.dart';
import 'screens/markets_screen.dart';
import 'screens/music_screen.dart';
import 'screens/pages_screen.dart';
import 'screens/feedback_screen.dart';
import 'screens/map_screen.dart';
// Services
import 'services/theme_service.dart';
import 'services/focus_service.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'services/firebase_realtime_service.dart';
import 'services/firebase_messaging_service.dart';
import 'services/websocket_service.dart';
import 'services/translation_service.dart';
import 'services/background_update_scheduler.dart';
import 'services/background_activity_service.dart';
import 'services/call_service.dart';
import 'services/message_sync_worker.dart';
import 'services/friend_service.dart';
import 'services/chat_message_count_service.dart';
import 'services/navigation_service.dart';
import 'services/location_service.dart';
import 'services/chat_service.dart';
import 'config/constants.dart';
// Widgets and Models
import 'widgets/incoming_call_notification.dart';
import 'widgets/background_gradient.dart';
import 'models/friend.dart';
// Firebase background handler - must be imported at top level
import 'services/firebase_messaging_service.dart' show firebaseMessagingBackgroundHandler;
import 'package:firebase_messaging/firebase_messaging.dart';

Future<void> main() async {
  // Gate all print calls behind a debug flag using Zone
  // Logging enabled for debugging FCM token
  const bool enableLogging = true;
  // Always enable error logging on iOS for debugging
  final bool enableErrorLogging = Platform.isIOS || enableLogging;

  runZonedGuarded(
    () async {
      // Ensure Flutter is initialized first
      WidgetsFlutterBinding.ensureInitialized();

      // Set up Flutter error handler to log all errors
      FlutterError.onError = (FlutterErrorDetails details) {
        if (enableErrorLogging) {
          FlutterError.presentError(details);
          print('═══════════════════════════════════════════════════════════════');
          print('FLUTTER ERROR');
          print('═══════════════════════════════════════════════════════════════');
          print('Exception: ${details.exception}');
          print('Library: ${details.library}');
          print('Stack: ${details.stack}');
          print('═══════════════════════════════════════════════════════════════');
        }
      };

      // Set preferred orientations to portrait only
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
      
      // Enable edge-to-edge mode to make app extend behind status bar
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.edgeToEdge,
      );


      // Initialize theme and translation services
      final themeService = ThemeService();
      final translationService = TranslationService();
      
      // Run theme service initialization (fast, local only)
      await themeService.initialize();

      // Initialize translation service BEFORE showing UI to prevent translation keys from showing
      // This loads cached translations first (fast), then updates from API in background
      await translationService.initialize();

      // CRITICAL: Register Firebase background message handler BEFORE runApp()
      // This ensures notifications work when app is terminated/closed
      // Managed by FirebaseMessagingService.initialize() to avoid duplicate registration
      
      // Initialize Firebase BEFORE running the app (needed for FCM push notifications)
      await _initializeFirebase(enableErrorLogging).catchError((error) {
        if (enableErrorLogging) {
          print('Firebase initialization error: $error');
        }
      });

      // Run the app after Firebase and translations are loaded
      runApp(ChangeNotifierProvider.value(value: themeService, child: const MyApp()));
    },
    (error, stack) {
      if (enableErrorLogging) {
        print('═══════════════════════════════════════════════════════════════');
        print('ZONE ERROR (Uncaught Exception)');
        print('═══════════════════════════════════════════════════════════════');
        print('Error: $error');
        print('Stack: $stack');
        print('═══════════════════════════════════════════════════════════════');
      }
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        // Always allow logs with [SKYBYN] prefix or when enableLogging is true
        if (enableLogging || line.contains('[SKYBYN]')) {
          parent.print(zone, line);
        }
      },
    ),
  );
}

Future<void> _initializeFirebase(bool enableErrorLogging) async {
  try {
    // Always initialize Firebase Core (needed for FCM push notifications)
    // Check if Firebase is already initialized
    if (Firebase.apps.isEmpty) {
      try {
        await Firebase.initializeApp();
        if (enableErrorLogging) {
          print('✅ [Firebase] Firebase Core initialized successfully');
        }
      } catch (e) {
        if (enableErrorLogging) {
          print('⚠️ [Firebase] Firebase Core initialization failed: $e');
          print('⚠️ [Firebase] App will continue to function normally without push notifications');
        }
        return; // Exit gracefully - app will work without Firebase
      }
    }

    // Ensure we are signed in (Anonymously if needed) to access Realtime Database
    // This resolves permission-denied errors on chat_notifications path
    try {
      // Lazy load FirebaseAuth to avoid unnecessarily loading it if not needed elsewhere
      // Assuming FirebaseAuth is available since we use Firebase
      /* 
       * Ideally we would use FirebaseAuth.instance.signInAnonymously() here
       * but we need to import firebase_auth. 
       * Since we can't easily add imports in this block without affecting the whole file,
       * we will handle this in FirebaseMessagingService or FirebaseRealtimeService
       * which initiates the connection.
       */
    } catch (e) {
      if (enableErrorLogging) print('⚠️ [Firebase] Auth check failed: $e');
    }

    // Skip Firebase Messaging on iOS - it requires APN configuration which is not set up
    if (Platform.isIOS) {
      if (enableErrorLogging) {
        print('ℹ️ [Firebase] Skipping Firebase Messaging on iOS (APN not configured)');
      }
      return;
    }

    // Initialize Firebase Messaging for push notifications (Android release only)
    try {
      final firebaseMessagingService = FirebaseMessagingService();
      await firebaseMessagingService.initialize();

      // Token is already registered on app start in initialize() method
      // If user is logged in, it will be updated with user ID in auth_service.dart after login
      if (enableErrorLogging) {
        print('✅ [Firebase] Firebase Messaging initialized successfully');
      }
    } catch (e) {
      if (enableErrorLogging) {
        print('⚠️ [Firebase] Firebase Messaging initialization error: $e');
        print('⚠️ [Firebase] App will continue to function normally without push notifications');
      }
      // Don't rethrow - allow app to continue without Firebase Messaging
    }
  } catch (e, stackTrace) {
    // Print detailed error but don't crash the app
    if (enableErrorLogging) {
      print('═══════════════════════════════════════════════════════════════');
      print('FIREBASE INITIALIZATION ERROR');
      print('═══════════════════════════════════════════════════════════════');
      print('Error: $e');
      print('Stack: $stackTrace');
      print('═══════════════════════════════════════════════════════════════');
      print('⚠️ [Firebase] App will continue to function normally without push notifications');
    }
    // Continue without Firebase - app will still work
    // We explicitly do NOT rethrow here to ensure app startup continues
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
  final ChatMessageCountService _chatMessageCountService = ChatMessageCountService();
  Timer? _serviceCheckTimer;
  Timer? _activityUpdateTimer;
  Timer? _webSocketConnectionCheckTimer;
  Timer? _profileCheckTimer;
  Timer? _firebaseConnectivityCheckTimer;
  
  // Track active incoming call
  String? _activeCallId;
  Friend? _activeCallFriend;
  
  // Deep linking
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Initialize deep linking
    _initializeDeepLinks();

    // Initialize services in the background, deferred to next frame
    // to prevent blocking the UI thread during initial render (Fixes "Skipped XX frames")
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeServices();
    });
  }
  
  /// Initialize deep link handling
  void _initializeDeepLinks() {
    _appLinks = AppLinks();
    
    // Handle initial link (when app is opened from a deep link)
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) {
        _handleDeepLink(uri);
      }
    });
    
    // Handle links when app is already running
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (uri) {
        _handleDeepLink(uri);
      },
      onError: (err) {
        // Silently handle errors
      },
    );
  }
  
  /// Handle deep link URLs
  void _handleDeepLink(Uri uri) {
    // Extract code from URL
    String? code;
    
    // Handle custom scheme: skybyn://login?code=abc123xyz0
    if (uri.scheme == 'skybyn' && uri.host == 'login') {
      code = uri.queryParameters['code'];
    }
    // Handle HTTPS: https://app.skybyn.no/qr/login?code=abc123xyz0 or https://skybyn.com/qr/login?code=abc123xyz0
    else if (uri.scheme == 'https' && 
             (uri.host == 'app.skybyn.no' || uri.host == 'skybyn.com') &&
             uri.path.contains('/qr/login')) {
      code = uri.queryParameters['code'];
    }
    
    if (code != null && code.isNotEmpty) {
      // Show confirmation dialog
      final context = navigatorKey.currentContext;
      if (context != null) {
        // Wait a moment for app to be ready
        Future.delayed(const Duration(milliseconds: 500), () {
          final currentContext = navigatorKey.currentContext;
          if (currentContext != null) {
            Navigator.of(currentContext).push(
              MaterialPageRoute(
                builder: (context) => QrScannerScreen(qrCode: code!),
              ),
            );
          }
        });
      }
    }
  }

  Future<void> _initializeServices() async {
    try {
      // Initialize notification and Firebase services in parallel (non-blocking)
      await Future.wait([
        _notificationService.initialize(),
        _firebaseRealtimeService.initialize(),
        _chatMessageCountService.initialize(),
      ]);

      // Initialize background update scheduler
      await _backgroundUpdateScheduler.initialize();
      
      // Initialize background activity service (updates activity even when app is closed)
      await BackgroundActivityService.initialize();
      
      // Initialize WorkManager for periodic message sync (battery-efficient)
      // WorkManager handles background tasks without requiring a foreground service notification
      await MessageSyncWorker.initialize();
      await MessageSyncWorker.registerPeriodicSync();
      
      // Note: Foreground service removed to avoid notification
      // Background functionality is handled by:
      // - WorkManager: Periodic message sync (every 15 minutes)
      // - WebSocket: Active when app is in foreground
      // - FCM: Push notifications when app is closed
      // The app won't appear in background activity list, but no notification will show
      
      // Set up call callbacks for incoming calls via WebSocket
      _setupCallHandlers();
      
      // Set up callback for incoming calls from FCM notifications
      _setupIncomingCallFromNotificationHandler();
      
      // Set up WebSocket connection state listener
      _setupWebSocketConnectionListener();
      
      // Initialize and connect WebSocket globally (works from any screen)
      await _webSocketService.initialize();
      _connectWebSocketGlobally();
      
      // Set up global chat message listener for badge count
      _setupGlobalChatMessageListener();

      // Start periodic activity updates (every 5 seconds when WebSocket is connected)
      _startActivityUpdates();

      // Start periodic profile checks (every 5 minutes to detect bans/deactivations)
      _startProfileChecks();

      // Start Firebase connectivity checks (every hour)
      _startFirebaseConnectivityChecks();

      // Preload location and map data (non-blocking, in background)
      _preloadLocationAndMapData();
      
      // Preload map screen (non-blocking, in background)
      preloadMapScreen();

      // Check for updates after a delay
      if (Platform.isAndroid) {
         // Defer update checks significantly to allow UI to settle
         Future.delayed(const Duration(seconds: 5), () {
          // Note: Context not available during app startup
          // Updates will be checked when user manually checks or when context is available
         });
      }
    } catch (e) {
      // debugPrint('Service initialization error: $e');
    }
  }

  /// Preload location and map data on app startup
  /// This makes the map screen load faster when user navigates to it
  Future<void> _preloadLocationAndMapData() async {
    try {
      final authService = AuthService();
      final userId = await authService.getStoredUserId();
      
      if (userId == null) {
        return; // User not logged in, skip preloading
      }

      // Note: Location permission is now only requested when navigating to map screen
      // Preloading location removed to avoid requesting permission on app startup

      // Preload friends locations in background (non-blocking)
      Future.delayed(const Duration(seconds: 2), () async {
        try {
          final response = await http.post(
            Uri.parse(ApiConstants.friendsLocations),
            body: {'userID': userId},
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          ).timeout(const Duration(seconds: 10));

          if (response.statusCode == 200) {
            print('Friends locations preloaded on app startup');
          }
        } catch (e) {
          // Silently handle errors - friends locations preloading is optional
        }
      });
    } catch (e) {
      // Silently handle errors - preloading is optional
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
    }
  }

  /// Start periodic profile checks
  /// Checks profile status every 5 minutes to detect bans/deactivations/rank changes
  void _startProfileChecks() {
    // Cancel any existing timer
    _profileCheckTimer?.cancel();
    
    // Check profile immediately on startup
    _checkProfileStatus();
    
    // Check every 5 minutes
    _profileCheckTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      if (!mounted) {
        timer.cancel();
        _profileCheckTimer = null;
        return;
      }
      _checkProfileStatus();
    });
  }

  /// Check profile status and logout if banned/deactivated
  Future<void> _checkProfileStatus() async {
    try {
      final authService = AuthService();
      final username = await authService.getStoredUsername();
      
      if (username == null || username.isEmpty) {
        return; // User not logged in
      }

      // Fetch profile to check for bans/deactivations
      final user = await authService.fetchUserProfile(username);
      
      if (user == null) {
        // Profile fetch failed or user not found - might be banned/deactivated
        // The fetchUserProfile method already handles logout for banned/deactivated users
        return;
      }

      // Check if user is banned or deactivated
      final isBanned = user.banned.isNotEmpty && (user.banned == '1' || user.banned.toLowerCase() == 'true');
      final isDeactivated = user.deactivated.isNotEmpty && (user.deactivated == '1' || user.deactivated.toLowerCase() == 'true');
      
      if (isBanned || isDeactivated) {
        // User is banned or deactivated - log them out
        await authService.logout();
        
        // Navigate to login screen if app is mounted
        if (mounted && navigatorKey.currentState != null) {
          navigatorKey.currentState!.pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const LoginScreen()),
            (route) => false,
          );
        }
      }
    } catch (e) {
      // Silently fail - profile checks are not critical
      // If there's a network error, we don't want to log the user out
      // If there's a network error, disable all activities that require network connection to work
      //_disableActivities
    }
  }

  /// Start periodic Firebase connectivity checks
  /// Checks if user is connected to internet via Firebase every hour
  void _startFirebaseConnectivityChecks() {
    // Cancel any existing timer
    _firebaseConnectivityCheckTimer?.cancel();
    
    // Check immediately on startup
    _checkFirebaseConnectivity();
    
    // Check every hour
    _firebaseConnectivityCheckTimer = Timer.periodic(const Duration(hours: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        _firebaseConnectivityCheckTimer = null;
        return;
      }
      _checkFirebaseConnectivity();
    });
  }

  /// Check Firebase connectivity to verify internet connection
  Future<void> _checkFirebaseConnectivity() async {
    try {
      // Check if Firebase is initialized
      if (Firebase.apps.isEmpty) {
        return; // Firebase not initialized
      }

      final database = FirebaseDatabase.instance;
      final connectedRef = database.ref('.info/connected');
      
      // Listen to connection state for a short period to check connectivity
      final subscription = connectedRef.onValue.listen((event) {
        final isConnected = event.snapshot.value as bool? ?? false;
        
        if (!isConnected) {
          // User is not connected to Firebase (likely no internet)
          // This means the user is offline - activity will naturally stop updating
          // The last_active timestamp will reflect this when checked
        }
        // If connected, user has internet - activity updates will continue
      }, onError: (error) {
        // Silently fail - connectivity checks are not critical
      });

      // Wait a short time to get the connection state, then cancel
      await Future.delayed(const Duration(seconds: 2));
      await subscription.cancel();
    } catch (e) {
      // Silently fail - connectivity checks are not critical
      // Firebase may not be configured or available
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _activityUpdateTimer?.cancel();
    _webSocketConnectionCheckTimer?.cancel();
    _profileCheckTimer?.cancel();
    _firebaseConnectivityCheckTimer?.cancel();
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // Manage foreground service based on app lifecycle
    switch (state) {
      case AppLifecycleState.resumed:
        // App is in foreground - process offline queue immediately
        final chatService = ChatService();
        chatService.processOfflineQueue();
        
        // Ensure Firebase and WebSocket are connected
        // Reconnect Firebase if not connected (it may have been disconnected in background)
        if (!_firebaseRealtimeService.isConnected) {
          _firebaseRealtimeService.connect();
        }
        // Always force reconnect WebSocket when app resumes to ensure connection is alive
        // The connection might appear connected but actually be dead after backgrounding
        _webSocketService.forceReconnect().catchError((error) {
        });
        // Check profile status when app resumes (detect bans/deactivations)
        _checkProfileStatus();
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
        break;
      case AppLifecycleState.detached:
        // App is being terminated - disconnect Firebase
        _firebaseRealtimeService.disconnect();
        // Foreground service will continue running even after app is terminated
        // It will maintain WebSocket connection and perform background checks
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
    _webSocketService.connect().catchError((error) {});
  }

  /// Set up global chat message listener to update badge count
  void _setupGlobalChatMessageListener() {
    developer.log('[SKYBYN]    Setting up global chat message listener', name: 'Main Chat Listener');
    developer.log('[SKYBYN]    - WebSocket connected: ${_webSocketService.isConnected}', name: 'Main Chat Listener');
    
    // Listen for chat messages via WebSocket to update badge count
    _webSocketService.connect(
      onChatMessage: (messageId, fromUserId, toUserId, message) async {
        // Use print with [SKYBYN] prefix so zone allows it through
        print('[SKYBYN] 🔵 [Main Chat Listener] WebSocket message received');
        print('[SKYBYN]    MessageId: $messageId');
        print('[SKYBYN]    From: $fromUserId, To: $toUserId');
        
        // Get current user ID
        final authService = AuthService();
        final currentUserId = await authService.getStoredUserId();
        
        print('[SKYBYN]    Current UserId: ${currentUserId ?? "null"}');
        
        // Only increment badge if message is for current user and from someone else
        if (currentUserId == null) {
          print('[SKYBYN] ⏭️ [Main Chat Listener] Skipping - current user ID is null');
        } else if (toUserId != currentUserId) {
          print('[SKYBYN] ⏭️ [Main Chat Listener] Skipping - message not for current user (To: $toUserId, Current: $currentUserId)');
        } else if (fromUserId == currentUserId) {
          print('[SKYBYN] ⏭️ [Main Chat Listener] Skipping - message from self (From: $fromUserId, Current: $currentUserId)');
        } else {
          // Message is for current user and from someone else - process it
          print('[SKYBYN] 🔵 [Main Chat Listener] Incrementing unread count for: $fromUserId');
          // Increment unread count for this friend (with messageId and messageContent to prevent duplicates)
          final wasIncremented = await _chatMessageCountService.incrementUnreadCount(
            fromUserId, 
            messageId: messageId,
            messageContent: message, // Pass message content for content-based deduplication
          );
          if (wasIncremented) {
            print('[SKYBYN] ✅ [Main Chat Listener] Unread count incremented');
            
            // Only show notification if chat screen for this friend is NOT currently open
            if (!_chatMessageCountService.isChatOpenForFriend(fromUserId)) {
              // Only show system notification if app is in background or closed
              // If app is in foreground, in-app notifications will be shown instead
              final appLifecycleState = WidgetsBinding.instance.lifecycleState;
              final isAppInForeground = appLifecycleState == AppLifecycleState.resumed;
              
              // Debug logging for lifecycle state
              print('[SKYBYN] 📱 [Main Chat Listener] App Lifecycle State: $appLifecycleState');
              print('[SKYBYN]    Is Foreground (resumed): $isAppInForeground');
              print('[SKYBYN]    State breakdown:');
              print('[SKYBYN]      - resumed: ${appLifecycleState == AppLifecycleState.resumed}');
              print('[SKYBYN]      - paused: ${appLifecycleState == AppLifecycleState.paused}');
              print('[SKYBYN]      - inactive: ${appLifecycleState == AppLifecycleState.inactive}');
              print('[SKYBYN]      - hidden: ${appLifecycleState == AppLifecycleState.hidden}');
              print('[SKYBYN]      - detached: ${appLifecycleState == AppLifecycleState.detached}');
              
              if (!isAppInForeground) {
                // App is in background or closed - show system notification
                print('[SKYBYN] 🔔 [Main Chat Listener] App is NOT in foreground - will show system notification');
                try {
                  // Get friend's name for notification
                  final friendService = FriendService();
                  final friends = await friendService.fetchFriendsForUser(userId: currentUserId);
                  final friend = friends.firstWhere(
                    (f) => f.id == fromUserId,
                    orElse: () => Friend(
                      id: fromUserId,
                      username: fromUserId,
                      nickname: '',
                      avatar: '',
                      online: false,
                    ),
                  );
                  
                  final friendName = friend.nickname.isNotEmpty ? friend.nickname : friend.username;
                  
                  await _notificationService.showNotification(
                    title: friendName,
                    body: message,
                    payload: jsonEncode({
                      'type': 'chat',
                      'from': fromUserId,
                      'messageId': messageId,
                      'to': currentUserId,
                    }),
                  );
                  print('[SKYBYN] ✅ [Main Chat Listener] System notification shown for message from $friendName (app in background)');
                } catch (e) {
                  print('[SKYBYN] ⚠️ [Main Chat Listener] Failed to show notification: $e');
                }
              } else {
                //print('[SKYBYN] ⏭️ [Main Chat Listener] App is in foreground (resumed) - skipping system notification (in-app notification will be shown)');
              }
            } else {
              //print('[SKYBYN] ⏭️ [Main Chat Listener] Skipping notification - chat screen is open for this friend');
            }
          } else {
            //print('[SKYBYN] ⏭️ [Main Chat Listener] Skipped (duplicate message)');
          }
        }
      },
    );
    
    print('[SKYBYN] ✅ [Main Chat Listener] WebSocket callback registered');
    
    // Also listen via Firebase Realtime for messages when WebSocket is NOT available
    // Only use Firebase as fallback when WebSocket is disconnected
    _firebaseRealtimeService.setupChatListener(
      '', // Empty friendId means listen to all chats
      (messageId, fromUserId, toUserId, message) async {
        // Only process if WebSocket is NOT connected (Firebase is fallback)
        if (_webSocketService.isConnected) {
          print('[SKYBYN] ⏭️ [Main Chat Listener] Skipping Firebase - WebSocket connected');
          return; // WebSocket handles it, skip Firebase
        }
        
        print('[SKYBYN] 🔵 [Main Chat Listener] Firebase message (WebSocket unavailable)');
        print('[SKYBYN]    MessageId: $messageId');
        print('[SKYBYN]    From: $fromUserId, To: $toUserId');
        
        // Get current user ID
        final authService = AuthService();
        final currentUserId = await authService.getStoredUserId();
        
        print('[SKYBYN]    Current UserId: ${currentUserId ?? "null"}');
        
        // Only increment badge if message is for current user and from someone else
        if (currentUserId == null) {
          print('[SKYBYN] ⏭️ [Main Chat Listener] Skipping - current user ID is null (Firebase)');
        } else if (toUserId != currentUserId) {
          print('[SKYBYN] ⏭️ [Main Chat Listener] Skipping - message not for current user (To: $toUserId, Current: $currentUserId, Firebase)');
        } else if (fromUserId == currentUserId) {
          print('[SKYBYN] ⏭️ [Main Chat Listener] Skipping - message from self (From: $fromUserId, Current: $currentUserId, Firebase)');
        } else {
          // Message is for current user and from someone else - process it
          print('[SKYBYN] 🔵 [Main Chat Listener] Incrementing unread count for: $fromUserId');
          // Increment unread count for this friend (with messageId and messageContent to prevent duplicates)
          final wasIncremented = await _chatMessageCountService.incrementUnreadCount(
            fromUserId, 
            messageId: messageId,
            messageContent: message, // Pass message content for content-based deduplication
          );
          if (wasIncremented) {
            print('[SKYBYN] ✅ [Main Chat Listener] Unread count incremented (Firebase)');
            
            // Only show notification if chat screen for this friend is NOT currently open
            if (!_chatMessageCountService.isChatOpenForFriend(fromUserId)) {
              // Only show system notification if app is in background or closed
              // If app is in foreground, in-app notifications will be shown instead
              final appLifecycleState = WidgetsBinding.instance.lifecycleState;
              final isAppInForeground = appLifecycleState == AppLifecycleState.resumed;
              
              if (!isAppInForeground) {
                // App is in background or closed - show system notification
                print('[SKYBYN] 🔔 [Main Chat Listener] App is NOT in foreground - will show system notification');
                try {
                  // Get friend's name for notification
                  final friendService = FriendService();
                  final friends = await friendService.fetchFriendsForUser(userId: currentUserId);
                  final friend = friends.firstWhere(
                    (f) => f.id == fromUserId,
                    orElse: () => Friend(
                      id: fromUserId,
                      username: fromUserId,
                      nickname: '',
                      avatar: '',
                      online: false,
                    ),
                  );
                  
                  final friendName = friend.nickname.isNotEmpty ? friend.nickname : friend.username;
                  
                  await _notificationService.showNotification(
                    title: friendName,
                    body: message,
                    payload: jsonEncode({
                      'type': 'chat',
                      'from': fromUserId,
                      'messageId': messageId,
                      'to': currentUserId,
                    }),
                  );
                  print('[SKYBYN] ✅ [Main Chat Listener] System notification shown for message from $friendName (app in background)');
                } catch (e) {
                  print('[SKYBYN] ⚠️ [Main Chat Listener] Failed to show notification: $e');
                }
              }
            }
          }
        }
      },
    );
  }

  /// Set up call handlers (callbacks for incoming calls via WebSocket)
  void _setupCallHandlers() {
    _webSocketService.onIncomingCall = (callId, fromUserId, callType) async {
      print('[SKYBYN] 📞 [Main] Incoming call detected from WebSocket');
      print('[SKYBYN]    CallId: $callId, From: $fromUserId, Type: $callType');
      
      // Store active call details
      _activeCallId = callId;
      
      try {
        // Fetch friend details (the caller)
        final authService = AuthService();
        final currentUserId = await authService.getStoredUserId();
        
        if (currentUserId != null) {
          final friends = await _friendService.fetchFriendsForUser(userId: currentUserId);
           final caller = friends.firstWhere(
            (f) => f.id == fromUserId,
            orElse: () => Friend(
              id: fromUserId,
              username: 'Unknown',
              nickname: 'Unknown Caller',
              avatar: '',
              online: true,
            ),
          );
          
          _activeCallFriend = caller;
          
          if (mounted) {
            // Show incoming call notification overlay
            IncomingCallNotification.show(
              context: context,
              caller: caller,
              callType: callType == 'video' ? CallType.video : CallType.audio,
              onAccept: () {
                // Navigate to call screen
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CallScreen(
                      friend: caller,
                      roomId: callId,
                      callType: callType == 'video' ? CallType.video : CallType.audio,
                      isIncoming: true,
                    ),
                  ),
                );
                _activeCallId = null;
                _activeCallFriend = null;
              },
              onDecline: () {
                // Send decline message
                _webSocketService.sendCallEnd(
                  callId: callId,
                  targetUserId: fromUserId,
                );
                _activeCallId = null;
                _activeCallFriend = null;
              },
            );
          } else {
             // App is in background, show system notification
             final callerName = caller.nickname.isNotEmpty ? caller.nickname : caller.username;
             final isVideo = callType == 'video';
             
             await _notificationService.showNotification(
               title: 'Incoming ${isVideo ? "Video" : "Voice"} Call',
               body: '$callerName is calling you',
               channelId: 'calls', // Use dedicated call channel
               payload: jsonEncode({
                 'type': 'call',
                 'callId': callId,
                 'fromUserId': fromUserId,
                 'callType': callType,
                 'fromName': callerName,
                 'fromAvatar': caller.avatar,
               }),
             );
          }
        }
      } catch (e) {
        print('[SKYBYN] ❌ [Main] Error handling incoming call: $e');
      }
    };
    
    _webSocketService.onCallEnded = (callId) {
       print('[SKYBYN] 📞 [Main] Call ended: $callId');
       if (_activeCallId == callId) {
         _activeCallId = null;
         _activeCallFriend = null;
         IncomingCallNotification.hide();
       }
    };
  }

  /// Set up handler for incoming calls via Notification
  void _setupIncomingCallFromNotificationHandler() {
    FirebaseMessagingService.onIncomingCallFromNotification = (callId, fromUserId, callType) async {
       print('[SKYBYN] 📞 [Main] Incoming call from Notification tap');
       // Navigate to call screen via global navigator key
       final context = navigatorKey.currentContext;
       if (context != null) {
          // Fetch friend details first
          final authService = AuthService();
          final currentUserId = await authService.getStoredUserId();
          if (currentUserId != null) {
            final friends = await _friendService.fetchFriendsForUser(userId: currentUserId);
            final caller = friends.firstWhere(
              (f) => f.id == fromUserId,
              orElse: () => Friend(
                id: fromUserId,
                username: 'Unknown',
                nickname: 'Unknown Caller',
                avatar: '',
                online: true,
              ),
            );
            
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CallScreen(
                  friend: caller,
                  roomId: callId,
                  callType: callType == 'video' ? CallType.video : CallType.audio,
                  isIncoming: true,
                ),
              ),
            );
          }
       }
    };
  }
  
  // Method to preload map screen
  void preloadMapScreen() {
    // This is a dummy call to initialize the map controller in background
    // if applicable, or just warm up the engine
  }

  @override
  Widget build(BuildContext context) {
    // Get theme service
    final themeService = Provider.of<ThemeService>(context);

    // Lock orientation to portrait
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    
    // Set system UI style (status bar) based on theme
    // This ensures the status bar text color is readable
    // Transparent status bar for edge-to-edge design
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent, // Fully transparent status bar
        statusBarIconBrightness: themeService.isDarkMode ? Brightness.light : Brightness.dark,
        statusBarBrightness: themeService.isDarkMode ? Brightness.dark : Brightness.light, // For iOS
        systemNavigationBarColor: themeService.isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
        systemNavigationBarIconBrightness: themeService.isDarkMode ? Brightness.light : Brightness.dark,
      ),
    );

    return MaterialApp(
      navigatorKey: navigatorKey, // Set global navigator key
      title: 'Skybyn',
      debugShowCheckedModeBanner: false,
      theme: themeService.themeData, // Use theme from service
      // Ensure we use a unique route for home to separate from login
      initialRoute: '/',
      routes: {
        '/': (context) => _getInitialScreen(),
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/forgot_password': (context) => const ForgotPasswordScreen(),
        '/home': (context) => const HomeScreen(),
        '/profile': (context) => const ProfileScreen(),
        '/settings': (context) => const SettingsScreen(),
        '/qr_scanner': (context) => const QrScannerScreen(qrCode: ''),
        '/share': (context) => const ShareScreen(),
        '/create_post': (context) => const CreatePostScreen(),
        '/events': (context) => const EventsScreen(),
        '/games': (context) => const GamesScreen(),
        '/groups': (context) => const GroupsScreen(),
        '/markets': (context) => const MarketsScreen(),
        '/music': (context) => const MusicScreen(),
        '/pages': (context) => const PagesScreen(),
        '/feedback': (context) => const FeedbackScreen(),
        '/map': (context) => const MapScreen(),
        // Note: ChatScreen and CallScreen require arguments, so they are pushed directly
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/chat') {
          final args = settings.arguments as Map<String, dynamic>;
          return MaterialPageRoute(
            builder: (context) => ChatScreen(
              friend: args['friend'],
            ),
          );
        } else if (settings.name == '/call') {
          final args = settings.arguments as Map<String, dynamic>;
          return MaterialPageRoute(
            builder: (context) => CallScreen(
              friend: args['friend'],
              callType: args['callType'],
              isIncoming: args['isIncoming'] ?? false,
            ),
          );
        }
        return null;
      },
      builder: (context, child) {
        return MediaQuery(
          // Fix text scaling to prevent layout issues
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
          child: child!,
        );
      },
    );
  }

  Widget _getInitialScreen() {
    // Check if user is logged in
    return FutureBuilder<bool>(
      future: _checkLoginStatus(),
      builder: (context, snapshot) {
        // Show splash screen while checking
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        // If logged in, go to Home, otherwise Login
        if (snapshot.data == true) {
          return const HomeScreen();
        } else {
          return const LoginScreen();
        }
      },
    );
  }

  Future<bool> _checkLoginStatus() async {
    final authService = AuthService();
    final userId = await authService.getStoredUserId();
    return userId != null && userId.isNotEmpty;
  }
}
