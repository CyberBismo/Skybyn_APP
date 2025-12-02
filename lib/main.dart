import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
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
import 'services/friend_service.dart';
import 'services/chat_message_count_service.dart';
import 'services/navigation_service.dart';
import 'services/location_service.dart';
import 'services/floating_chat_bubble_service.dart';
import 'config/constants.dart';
import 'package:overlay_support/overlay_support.dart';
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
  const bool enableLogging = false;
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

      // CRITICAL: Register Firebase background message handler BEFORE runApp()
      // This ensures notifications work when app is terminated/closed
      // Must be at top level, not inside a class or method
      try {
        FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
        if (enableErrorLogging) {
          print('✅ [FCM] Background message handler registered at top level');
        }
      } catch (e) {
        // Handler may already be registered (e.g., during hot reload) - that's okay
        if (enableErrorLogging) {
          print('⚠️ [FCM] Background handler registration: $e');
        }
      }

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
      } catch (e) {
        if (enableErrorLogging) {
          print('Firebase Core initialization error: $e');
        }
        rethrow; // Re-throw to be caught by outer catch
      }
    } else {
    }

    // Skip Firebase Messaging on iOS - it requires APN configuration which is not set up
    if (Platform.isIOS) {
      return;
    }

    // Initialize Firebase Messaging for push notifications (Android release only)
    try {
      final firebaseMessagingService = FirebaseMessagingService();
      await firebaseMessagingService.initialize();

      // Token is already registered on app start in initialize() method
      // If user is logged in, it will be updated with user ID in auth_service.dart after login
    } catch (e) {
      if (enableErrorLogging) {
        print('Firebase Messaging initialization error: $e');
      }
    }
  } catch (e, stackTrace) {
    // Print detailed error
    if (enableErrorLogging) {
      print('═══════════════════════════════════════════════════════════════');
      print('FIREBASE INITIALIZATION ERROR');
      print('═══════════════════════════════════════════════════════════════');
      print('Error: $e');
      print('Stack: $stackTrace');
      print('═══════════════════════════════════════════════════════════════');
    }
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
  final ChatMessageCountService _chatMessageCountService = ChatMessageCountService();
  final FloatingChatBubbleService _floatingBubbleService = FloatingChatBubbleService();
  Timer? _serviceCheckTimer;
  Timer? _activityUpdateTimer;
  Timer? _webSocketConnectionCheckTimer;
  Timer? _profileCheckTimer;
  
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

    // Initialize services in the background
    _initializeServices();
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
      
      // Initialize floating chat bubble service
      await _floatingBubbleService.initialize();
      
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

      // Preload location and map data (non-blocking, in background)
      _preloadLocationAndMapData();
      
      // Preload map screen (non-blocking, in background)
      preloadMapScreen();

      // Check for updates after a delay
      if (Platform.isAndroid) {
        Future.delayed(const Duration(seconds: 5), () {
      // Note: Context not available during app startup
      // Updates will be checked when user manually checks or when context is available
        });
      }
    } catch (e) {
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
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _serviceCheckTimer?.cancel(); // This can be removed if _serviceCheckTimer is not used elsewhere
    _activityUpdateTimer?.cancel();
    _webSocketConnectionCheckTimer?.cancel();
    _profileCheckTimer?.cancel();
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.resumed:
        // App is in foreground - ensure Firebase and WebSocket are connected
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
    _webSocketService.connect().catchError((error) {
    });
  }

  /// Set up global chat message listener to update badge count
  void _setupGlobalChatMessageListener() {
    developer.log('Setting up global chat message listener', name: 'Main Chat Listener');
    developer.log('   - WebSocket connected: ${_webSocketService.isConnected}', name: 'Main Chat Listener');
    
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
        if (currentUserId != null && toUserId == currentUserId && fromUserId != currentUserId) {
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
              // Check if app is in foreground - only show system notification if app is in background
              // If app is in foreground, WebSocket service will show in-app notification
              final isAppInForeground = WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
              if (!isAppInForeground) {
                // App is in background - show system notification only
                try {
                  // Get friend's name for notification
                  final friendService = FriendService();
                  final friends = await friendService.fetchFriendsForUser(userId: currentUserId);
                  final friend = friends.firstWhere(
                    (f) => f.id == fromUserId,
                    orElse: () => Friend(
                      id: fromUserId,
                      username: fromUserId,
                      nickname: fromUserId,
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
                print('[SKYBYN] ⏭️ [Main Chat Listener] Skipping system notification - app is in foreground (WebSocket will show in-app notification)');
              }
            } else {
              print('[SKYBYN] ⏭️ [Main Chat Listener] Skipping notification - chat screen is open for this friend');
            }
          } else {
            print('[SKYBYN] ⏭️ [Main Chat Listener] Skipped (duplicate message)');
          }
        } else {
          print('[SKYBYN] ⏭️ [Main Chat Listener] Skipping (not for current user or from self)');
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
        if (currentUserId != null && toUserId == currentUserId && fromUserId != currentUserId) {
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
              // Show notification for new message
              try {
                // Get friend's name for notification
                final friendService = FriendService();
                final friends = await friendService.fetchFriendsForUser(userId: currentUserId);
                final friend = friends.firstWhere(
                  (f) => f.id == fromUserId,
                  orElse: () => Friend(
                    id: fromUserId,
                    username: fromUserId,
                    nickname: fromUserId,
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
                print('[SKYBYN] ✅ [Main Chat Listener] Notification shown for message from $friendName');
              } catch (e) {
                print('[SKYBYN] ⚠️ [Main Chat Listener] Failed to show notification: $e');
              }
            } else {
              print('[SKYBYN] ⏭️ [Main Chat Listener] Skipping notification - chat screen is open for this friend');
            }
          } else {
            print('[SKYBYN] ⏭️ [Main Chat Listener] Skipped (duplicate message)');
          }
        } else {
          print('[SKYBYN] ⏭️ [Main Chat Listener] Skipping (not for current user or from self)');
        }
      },
    );
    print('[SKYBYN] ✅ [Main Chat Listener] Firebase callback registered (fallback only)');
  }

  /// Set up handler for incoming calls from FCM notifications
  void _setupIncomingCallFromNotificationHandler() {
    FirebaseMessagingService.setIncomingCallCallback((callId, fromUserId, callType) async {
      // App was opened from a call notification
      // Ensure WebSocket is connected so we can receive the call offer
      if (!_webSocketService.isConnected) {
        try {
          await _webSocketService.connect().timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              // Timeout - show error
              final context = navigatorKey.currentContext;
              if (context != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Failed to connect. Please try again.'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
          );
        } catch (e) {
          // Connection failed - show error
          final context = navigatorKey.currentContext;
          if (context != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to connect: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      }
      
      // Wait a moment for WebSocket to receive any pending call offers
      // The server should resend the call offer when the user comes online
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Check if we already received the call offer via WebSocket
      // If not, the caller should resend it when they see us come online
      // For now, we'll wait for the WebSocket handler to receive it
      // The call offer should arrive within a few seconds
    });
  }

  /// Set up call handlers for incoming calls via WebSocket
  void _setupCallHandlers() {
    // Set up call callbacks directly on WebSocketService
    // These will be used when WebSocket receives call signals
    _webSocketService.setCallCallbacks(
      onCallOffer: (callId, fromUserId, offer, callType) async {
        // Check if app is in foreground
        final isAppInForeground = WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
        
        if (isAppInForeground) {
          // App is in foreground - show in-app notification
          await _handleIncomingCallInForeground(callId, fromUserId, offer, callType);
        } else {
          // App is in background - Firebase notification should be sent by server
          // But we can also handle it here if needed
        }
      },
      onCallAnswer: (callId, answer) {
        _callService.handleIncomingAnswer(answer);
      },
      onIceCandidate: (callId, candidate, sdpMid, sdpMLineIndex) {
        _callService.handleIceCandidate(
          candidate: candidate,
          sdpMid: sdpMid,
          sdpMLineIndex: sdpMLineIndex,
        );
      },
      onCallEnd: (callId, fromUserId, targetUserId) async {
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
              // Pop the dialog first
              Navigator.of(dialogContext).pop();
              
              try {
                // Handle the incoming offer
                await _callService.handleIncomingOffer(
                  callId: callId,
                  fromUserId: fromUserId,
                  offer: offer,
                  callType: callType,
                );

                // Navigate to call screen only if call setup succeeded
                // Use the same context that showed the dialog to ensure proper navigation stack
                if (context.mounted && _callService.callState != CallState.ended) {
                  // Wait a moment for dialog to fully close
                  await Future.delayed(const Duration(milliseconds: 100));
                  
                  if (context.mounted) {
                    Navigator.of(context, rootNavigator: false).push(
                      MaterialPageRoute(
                        builder: (newContext) => CallScreen(
                          friend: friend,
                          callType: callType == 'video' ? CallType.video : CallType.audio,
                          isIncoming: true,
                        ),
                        // Don't use maintainState: false - it can cause navigation issues
                        // The previous screen should remain in the stack
                      ),
                    );
                  }
                }
              } catch (e) {
                // Error already handled by CallService.onCallError
                // Just clear the active call tracking
                if (mounted) {
                  setState(() {
                    _activeCallId = null;
                    _activeCallFriend = null;
                  });
                  
                  // Show error dialog if call screen wasn't opened
                  final errorContext = navigatorKey.currentContext;
                  if (errorContext != null) {
                    ScaffoldMessenger.of(errorContext).showSnackBar(
                      SnackBar(
                        content: Text('Failed to accept call: $e'),
                        duration: const Duration(seconds: 5),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
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
        // Set status bar to transparent so background shows through
        SystemChrome.setSystemUIOverlayStyle(
          const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent, // Transparent so background is visible
            statusBarIconBrightness: Brightness.light, // Light icons (white)
            statusBarBrightness: Brightness.dark, // For iOS compatibility
            systemNavigationBarColor: Colors.transparent, // Also set navigation bar to transparent
            systemNavigationBarIconBrightness: Brightness.light,
          ),
        );
        
        return OverlaySupport(
          child: MaterialApp(
          navigatorKey: navigatorKey,
          title: 'Skybyn',
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
          onGenerateRoute: _generateRoute,
          onUnknownRoute: (settings) {
            return MaterialPageRoute(builder: (context) => const HomeScreen());
          },
          builder: (context, child) {
            // Always disable clouds in the global BackgroundGradient
            // Each screen (HomeScreen, MapScreen) manages its own clouds
            return BackgroundGradient(
              showClouds: false, // Always false - screens manage their own clouds
              child: GestureDetector(
                onTap: () {
                  FocusService().unfocusAll();
                },
                behavior: HitTestBehavior.translucent,
                child: AnimatedSwitcher(duration: const Duration(milliseconds: 300), child: child!),
              ),
            );
          },
        ),
        );
      },
    );
  }
  
  /// Generate routes for named navigation
  static Route<dynamic> _generateRoute(RouteSettings settings) {
    // Save the route when navigating
    NavigationService.saveLastRoute(settings.name ?? 'home');
    
    switch (settings.name) {
      case '/':
      case '/home':
        return MaterialPageRoute(builder: (_) => const HomeScreen());
      case '/login':
        return MaterialPageRoute(builder: (_) => const LoginScreen());
      case '/profile':
        return MaterialPageRoute(builder: (_) => const ProfileScreen());
      case '/settings':
        return MaterialPageRoute(builder: (_) => const SettingsScreen());
      case '/qr-scanner':
        return MaterialPageRoute(builder: (_) => const QrScannerScreen());
      case '/share':
        return MaterialPageRoute(builder: (_) => const ShareScreen());
      case '/chat':
        final args = settings.arguments as Map<String, dynamic>?;
        final friend = args?['friend'] as Friend?;
        if (friend != null) {
          return MaterialPageRoute(
            builder: (_) => ChatScreen(friend: friend),
          );
        }
        // Check if opened from native bubble (friendId in arguments)
        final friendId = args?['friendId'] as String?;
        if (friendId != null) {
          // Try to load friend and navigate
          // This will be handled by the app's navigation system
          return MaterialPageRoute(builder: (_) => const HomeScreen());
        }
        return MaterialPageRoute(builder: (_) => const HomeScreen());
      case '/create-post':
        return MaterialPageRoute(builder: (_) => const CreatePostScreen());
      case '/register':
        return MaterialPageRoute(builder: (_) => const RegisterScreen());
      case '/forgot-password':
        return MaterialPageRoute(builder: (_) => const ForgotPasswordScreen());
      case '/call':
        final args = settings.arguments as Map<String, dynamic>?;
        return MaterialPageRoute(
          builder: (_) => CallScreen(
            friend: args?['friend'] as Friend,
            callType: args?['callType'] ?? CallType.audio,
            isIncoming: args?['isIncoming'] ?? false,
          ),
        );
      case '/events':
        return MaterialPageRoute(builder: (_) => const EventsScreen());
      case '/games':
        return MaterialPageRoute(builder: (_) => const GamesScreen());
      case '/groups':
        return MaterialPageRoute(builder: (_) => const GroupsScreen());
      case '/markets':
        return MaterialPageRoute(builder: (_) => const MarketsScreen());
      case '/music':
        return MaterialPageRoute(builder: (_) => const MusicScreen());
      case '/pages':
        return MaterialPageRoute(builder: (_) => const PagesScreen());
      case '/feedback':
        return MaterialPageRoute(builder: (_) => const FeedbackScreen());
      case '/map':
        return MaterialPageRoute(builder: (_) => const MapScreen());
      default:
        return MaterialPageRoute(builder: (_) => const HomeScreen());
    }
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
            // Restore last screen or default to home
            await _navigateToLastScreen();
            return;
          } else {
            // Try to fetch the profile again
            try {
              final username = await _authService.getStoredUsername();
              if (username != null) {
                final profile = await _authService.fetchUserProfile(username).timeout(const Duration(seconds: 5));
                if (profile != null && mounted) {
                  // Restore last screen or default to home
                  await _navigateToLastScreen();
                  return;
                }
              }
            } catch (e) {
            }
          }
        }
        // Navigate to login if we reach here
        if (mounted) {
          // Clear last route on logout
          await NavigationService.clearLastRoute();
          Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (context) => const LoginScreen()));
        }
      }
    } catch (e) {
      if (mounted) {
        // Clear last route on error
        await NavigationService.clearLastRoute();
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (context) => const LoginScreen()));
      }
    }
  }
  
  /// Navigate to the last saved screen or default to home
  Future<void> _navigateToLastScreen() async {
    if (!mounted) return;
    
    try {
      final lastRoute = await NavigationService.getLastRoute();
      
      if (lastRoute != null && lastRoute.isNotEmpty) {
        // Navigate to the last route
        Navigator.of(context).pushReplacementNamed(lastRoute);
      } else {
        // Default to home if no last route saved
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (context) => const HomeScreen()));
      }
    } catch (e) {
      // Fallback to home on error
      if (mounted) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (context) => const HomeScreen()));
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
    
    // Use default SSL validation (secure)
    
    return client;
  }
}
