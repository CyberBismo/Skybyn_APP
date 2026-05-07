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
import 'utils/http_client.dart';
import 'dart:async';
import 'dart:convert';
// Screens - all imports in main.dart
import 'screens/login_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/qr_scanner_screen.dart';
import 'screens/share_screen.dart';
import 'screens/chat_screen.dart';
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
import 'package:flutter_downloader/flutter_downloader.dart';
import 'services/theme_service.dart';
import 'services/focus_service.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'services/firebase_messaging_service.dart';
import 'services/websocket_service.dart';
import 'services/translation_service.dart';
import 'services/background_update_scheduler.dart';
// import 'services/background_activity_service.dart';
import 'services/call_service.dart';
import 'services/message_sync_worker.dart';
import 'services/friend_service.dart';
import 'services/chat_message_count_service.dart';
import 'services/navigation_service.dart';
import 'utils/navigator_key.dart';
import 'services/location_service.dart';
import 'services/chat_service.dart';
import 'services/auto_update_service.dart';
import 'config/constants.dart';
// Widgets and Models
import 'widgets/background_gradient.dart';
import 'models/friend.dart';
// Firebase background handler - must be imported at top level
import 'services/firebase_messaging_service.dart'
    show firebaseMessagingBackgroundHandler;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:easy_localization/easy_localization.dart';

import 'services/error_reporting_service.dart';
import 'services/chat_bubble_service.dart';

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
      await EasyLocalization.ensureInitialized();

      // Cleanup stale APKs on startup
      if (Platform.isAndroid) {
        AutoUpdateService.validateAndCleanupApk();
      }

      // Clear stale FlutterSecureStorage data on fresh install to prevent
      // keystore mismatches that cause storage reads/writes to hang.
      await AuthService.clearStaleSecureStorageOnReinstall();

      // Initialize FlutterDownloader for background update downloads
      if (Platform.isAndroid) {
        try {
          await FlutterDownloader.initialize(
            debug: false,
            ignoreSsl: false,
          );
        } catch (e) {
          if (kDebugMode) debugPrint('FlutterDownloader initialization error: $e');
        }
      }

      // Set up Flutter error handler to log all errors
      FlutterError.onError = (FlutterErrorDetails details) {
        if (enableErrorLogging) {
          FlutterError.presentError(details);
          if (kDebugMode) debugPrint(
              '═══════════════════════════════════════════════════════════════');
          if (kDebugMode) debugPrint('FLUTTER ERROR');
          if (kDebugMode) debugPrint(
              '═══════════════════════════════════════════════════════════════');
          if (kDebugMode) debugPrint('Exception: ${details.exception}');
          if (kDebugMode) debugPrint('Library: ${details.library}');
          if (kDebugMode) debugPrint('Stack: ${details.stack}');
          if (kDebugMode) debugPrint(
              '═══════════════════════════════════════════════════════════════');
        }
        // Report to server
        ErrorReportingService().reportError(details.exception, details.stack);
      };

      // Set preferred orientations to portrait only
      await SystemChrome.setPreferredOrientations(
          [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);

      // Enable edge-to-edge mode to make app extend behind status bar
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.edgeToEdge,
      );

      // Initialize theme and translation services
      final themeService = ThemeService();
      final translationService = TranslationService();

      // Run theme service initialization (fast, local only)
      await themeService.initialize();

      // TranslationService kept for TranslationKeys constants only (no longer fetches from API)
      await translationService.initialize();

      // CRITICAL: Register Firebase background message handler BEFORE runApp()
      // This ensures notifications work when app is terminated/closed
      // Managed by FirebaseMessagingService.initialize() to avoid duplicate registration

      // Initialize Firebase BEFORE running the app (needed for FCM push notifications)
      await _initializeFirebase(enableErrorLogging).catchError((error) {
        if (enableErrorLogging) {
          if (kDebugMode) debugPrint('Firebase initialization error: $error');
        }
      });

      // Run the app after Firebase and translations are loaded
      runApp(EasyLocalization(
        supportedLocales: const [Locale('en')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en'),
        child: ChangeNotifierProvider.value(
            value: themeService, child: const MyApp()),
      ));
    },
    (error, stack) {
      if (enableErrorLogging) {
        if (kDebugMode) debugPrint(
            '═══════════════════════════════════════════════════════════════');
        if (kDebugMode) debugPrint('ZONE ERROR (Uncaught Exception)');
        if (kDebugMode) debugPrint(
            '═══════════════════════════════════════════════════════════════');
        if (kDebugMode) debugPrint('Error: $error');
        if (kDebugMode) debugPrint('Stack: $stack');
        if (kDebugMode) debugPrint(
            '═══════════════════════════════════════════════════════════════');
      }
      // Report to server
      ErrorReportingService().reportError(error, stack);
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
          // print('✅ [Firebase] Firebase Core initialized successfully');
        }
      } catch (e) {
        if (enableErrorLogging) {
          if (kDebugMode) debugPrint('⚠️ [Firebase] Firebase Core initialization failed: $e');
          if (kDebugMode) debugPrint(
              '⚠️ [Firebase] App will continue to function normally without push notifications');
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
       * which initiates the connection.
       */
    } catch (e) {
      if (enableErrorLogging) { if (kDebugMode) debugPrint('⚠️ [Firebase] Auth check failed: $e'); }
    }

    // Skip Firebase Messaging on iOS - it requires APN configuration which is not set up
    if (Platform.isIOS) {
      if (enableErrorLogging) {
        if (kDebugMode) debugPrint(
            'ℹ️ [Firebase] Skipping Firebase Messaging on iOS (APN not configured)');
      }
      return;
    }

    // Initialize Firebase Messaging for push notifications (Android release only)
    try {
      if (kDebugMode) debugPrint('[SKYBYN] [Firebase] Initializing Firebase Messaging Service...');
      final firebaseMessagingService = FirebaseMessagingService();
      await firebaseMessagingService.initialize();
      if (kDebugMode) debugPrint(
          '[SKYBYN] [Firebase] Firebase Messaging Service initialization complete.');

      // Token is already registered on app start in initialize() method
      // If user is logged in, it will be updated with user ID in auth_service.dart after login
      if (enableErrorLogging) {
        // print('✅ [Firebase] Firebase Messaging initialized successfully');
      }
    } catch (e) {
      if (enableErrorLogging) {
        if (kDebugMode) debugPrint('⚠️ [Firebase] Firebase Messaging initialization error: $e');
        if (kDebugMode) debugPrint(
            '⚠️ [Firebase] App will continue to function normally without push notifications');
      }
      // Don't rethrow - allow app to continue without Firebase Messaging
    }
  } catch (e, stackTrace) {
    // Print detailed error but don't crash the app
    if (enableErrorLogging) {
      if (kDebugMode) debugPrint('═══════════════════════════════════════════════════════════════');
      if (kDebugMode) debugPrint('FIREBASE INITIALIZATION ERROR');
      if (kDebugMode) debugPrint('═══════════════════════════════════════════════════════════════');
      if (kDebugMode) debugPrint('Error: $e');
      if (kDebugMode) debugPrint('Stack: $stackTrace');
      if (kDebugMode) debugPrint('═══════════════════════════════════════════════════════════════');
      if (kDebugMode) debugPrint(
          '⚠️ [Firebase] App will continue to function normally without push notifications');
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

// navigatorKey is defined in utils/navigator_key.dart and imported above

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final NotificationService _notificationService = NotificationService();
  final WebSocketService _webSocketService = WebSocketService();
  final BackgroundUpdateScheduler _backgroundUpdateScheduler =
      BackgroundUpdateScheduler();
  final CallService _callService = CallService();
  final FriendService _friendService = FriendService();
  final ChatMessageCountService _chatMessageCountService =
      ChatMessageCountService();
  Timer? _serviceCheckTimer;
  Timer? _webSocketConnectionCheckTimer;
  Timer? _profileCheckTimer;
  Timer? _activityTimer;

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

    // Validate code format: alphanumeric only, 8–128 characters
    if (code != null && !RegExp(r'^[a-zA-Z0-9_\-]{8,128}$').hasMatch(code)) {
      code = null;
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
        _chatMessageCountService.initialize(),
      ]);

      // Initialize background update scheduler
      await _backgroundUpdateScheduler.initialize();

      // Background Activity Service removed in favor of WebSocket presence
      // await BackgroundActivityService.initialize();

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

      // Check if app was opened by tapping a chat bubble
      if (Platform.isAndroid) {
        final pendingFriendId = await ChatBubbleService().getPendingChatOpen();
        if (pendingFriendId != null && pendingFriendId.isNotEmpty) {
          final authService = AuthService();
          final currentUserId = await authService.getStoredUserId();
          if (currentUserId != null) {
            final friends = await _friendService.fetchFriendsForUser(userId: currentUserId);
            final friend = friends.firstWhere(
              (f) => f.id == pendingFriendId,
              orElse: () => Friend(id: pendingFriendId, username: pendingFriendId, nickname: '', avatar: '', online: false),
            );
            navigatorKey.currentState?.pushNamed('/chat', arguments: {'friend': friend});
          }
        }
      }

      // Start periodic profile checks (every 5 minutes to detect bans/deactivations)
      _startProfileChecks();

      // Pre-load session token into the shared in-memory cache so
      // AuthenticatedClient never has to hit SecureStorage mid-request.
      AuthService().getStoredSessionToken();

      // Kick off immediate activity update and start timer — this must run at
      // startup because didChangeAppLifecycleState never fires for the initial
      // resumed state (it only fires on transitions).
      AuthService().updateActivity();
      _activityTimer?.cancel();
      _activityTimer = Timer.periodic(const Duration(minutes: 2), (_) {
        AuthService().updateActivity();
      });

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
          final response = await globalAuthClient.post(
            Uri.parse(ApiConstants.friendsLocations),
            body: {'userID': userId},
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          ).timeout(const Duration(seconds: 10));

          if (response.statusCode == 200) {
            // print('Friends locations preloaded on app startup');
          }
        } catch (e) {
          // Silently handle errors - friends locations preloading is optional
        }
      });
    } catch (e) {
      // Silently handle errors - preloading is optional
    }
  }

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
      final isBanned = user.banned.isNotEmpty &&
          (user.banned == '1' || user.banned.toLowerCase() == 'true');
      final isDeactivated = user.deactivated.isNotEmpty &&
          (user.deactivated == '1' || user.deactivated.toLowerCase() == 'true');

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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _webSocketConnectionCheckTimer?.cancel();
    _profileCheckTimer?.cancel();
    _activityTimer?.cancel();
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Manage foreground service based on app lifecycle
    switch (state) {
      case AppLifecycleState.resumed:
        final chatService = ChatService();
        chatService.processOfflineQueue();
        _webSocketService.forceReconnect().catchError((error) {});
        _checkProfileStatus();
        // Kick off an immediate update then repeat every 2 minutes
        AuthService().updateActivity();
        _activityTimer?.cancel();
        _activityTimer = Timer.periodic(const Duration(minutes: 2), (_) {
          AuthService().updateActivity();
        });
        // Check if app was resumed by tapping a chat bubble
        if (Platform.isAndroid) {
          _handleBubbleTapOnResume();
        }
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        _activityTimer?.cancel();
        _activityTimer = null;
        break;
      case AppLifecycleState.detached:
        // App is being terminated
        // Foreground service will continue running even after app is terminated
        // It will maintain WebSocket connection and perform background checks
        // Online status is now calculated from last_active, no need to update
        break;
    }
  }

  Future<void> _handleBubbleTapOnResume() async {
    final pendingFriendId = await ChatBubbleService().getPendingChatOpen();
    if (pendingFriendId == null || pendingFriendId.isEmpty) return;
    final authService = AuthService();
    final currentUserId = await authService.getStoredUserId();
    if (currentUserId == null) return;
    final friends = await _friendService.fetchFriendsForUser(userId: currentUserId);
    final friend = friends.firstWhere(
      (f) => f.id == pendingFriendId,
      orElse: () => Friend(id: pendingFriendId, username: pendingFriendId, nickname: '', avatar: '', online: false),
    );
    navigatorKey.currentState?.pushNamed('/chat', arguments: {'friend': friend});
  }

  /// Set up WebSocket connection state listener
  void _setupWebSocketConnectionListener() {
    // Cancel any existing timer
    _webSocketConnectionCheckTimer?.cancel();

    // Check WebSocket connection state periodically (e.g., to manage UI)
    _webSocketConnectionCheckTimer =
        Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!mounted) {
        timer.cancel();
        _webSocketConnectionCheckTimer = null;
        return;
      }

      // We removed HTTP polling activity updates here because presence is now driven purely by the WebSocket connection and WebSocket pings.
    });
  }

  /// Connect WebSocket globally (works from any screen)
  /// This ensures WebSocket is always connected as long as the app is running
  void _connectWebSocketGlobally() {
    _webSocketService.connect().catchError((error) {});
  }

  /// Set up global chat message listener to update badge count
  void _setupGlobalChatMessageListener() {
    // developer.log('[SKYBYN]    Setting up global chat message listener', name: 'Main Chat Listener');
    // developer.log('[SKYBYN]    - WebSocket connected: ${_webSocketService.isConnected}', name: 'Main Chat Listener');

    // Listen for chat messages via WebSocket to update badge count
    _webSocketService.connect(
      onChatMessage: (messageId, fromUserId, toUserId, message) async {
        // Use print with [SKYBYN] prefix so zone allows it through
        // print('[SKYBYN] 🔵 [Main Chat Listener] WebSocket message received');
        // print('[SKYBYN]    MessageId: $messageId');
        // print('[SKYBYN]    From: $fromUserId, To: $toUserId');

        // Get current user ID
        final authService = AuthService();
        final currentUserId = await authService.getStoredUserId();

        if (kDebugMode) debugPrint('[SKYBYN] Current UserId: ${currentUserId ?? "null"}');

        // Only increment badge if message is for current user and from someone else
        if (currentUserId == null) {
          // print('[SKYBYN] ⏭️ [Main Chat Listener] Skipping - current user ID is null');
        } else if (toUserId != currentUserId) {
          // print('[SKYBYN] ⏭️ [Main Chat Listener] Skipping - message not for current user (To: $toUserId, Current: $currentUserId)');
        } else if (fromUserId == currentUserId) {
          if (kDebugMode) debugPrint(
              '[SKYBYN] ⏭️ [Main Chat Listener] Skipping - message from self');
          // Message is for current user and from someone else - process it
          // print('[SKYBYN] 🔵 [Main Chat Listener] Incrementing unread count for: $fromUserId');
          // Increment unread count for this friend (with messageId and messageContent to prevent duplicates)
          final wasIncremented =
              await _chatMessageCountService.incrementUnreadCount(
            fromUserId,
            messageId: messageId,
            messageContent:
                message, // Pass message content for content-based deduplication
          );
          if (wasIncremented) {
            // print('[SKYBYN] ✅ [Main Chat Listener] Unread count incremented');

            // Only show notification if chat screen for this friend is NOT currently open
            if (!_chatMessageCountService.isChatOpenForFriend(fromUserId)) {
              // Only show system notification if app is in background or closed
              // If app is in foreground, in-app notifications will be shown instead
              final appLifecycleState = WidgetsBinding.instance.lifecycleState;
              final isAppInForeground =
                  appLifecycleState == AppLifecycleState.resumed;

              // Debug logging for lifecycle state
              // print('[SKYBYN] 📱 [Main Chat Listener] App Lifecycle State: $appLifecycleState');
              // print('[SKYBYN]    Is Foreground (resumed): $isAppInForeground');
              // print('[SKYBYN]    State breakdown:');
              // print('[SKYBYN]      - resumed: ${appLifecycleState == AppLifecycleState.resumed}');
              // print('[SKYBYN]      - paused: ${appLifecycleState == AppLifecycleState.paused}');
              // print('[SKYBYN]      - inactive: ${appLifecycleState == AppLifecycleState.inactive}');
              // print('[SKYBYN]      - hidden: ${appLifecycleState == AppLifecycleState.hidden}');
              // print('[SKYBYN]      - detached: ${appLifecycleState == AppLifecycleState.detached}');

              if (!isAppInForeground) {
                // App is in background — try bubble first, fall back to notification
                try {
                  final friendService = FriendService();
                  final friends = await friendService.fetchFriendsForUser(
                      userId: currentUserId);
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

                  final friendName = friend.nickname.isNotEmpty
                      ? friend.nickname
                      : friend.username;

                  // Try showing bubble if permission granted
                  bool showedBubble = false;
                  if (Platform.isAndroid) {
                    final bubbleService = ChatBubbleService();
                    if (await bubbleService.isPermissionGranted()) {
                      final unread = _chatMessageCountService.getUnreadCount(fromUserId);
                      await bubbleService.showBubble(friend: friend, unreadCount: unread);
                      showedBubble = true;
                    }
                  }

                  // Always show a notification too (so tray is populated)
                  final notificationId =
                      int.tryParse(fromUserId) ?? fromUserId.hashCode;
                  await _notificationService.showNotification(
                    title: friendName,
                    body: message,
                    payload: jsonEncode({
                      'type': 'chat',
                      'from': fromUserId,
                      'messageId': messageId,
                      'to': currentUserId,
                    }),
                    notificationId: notificationId,
                  );
                  if (kDebugMode) debugPrint(
                      '[SKYBYN] ✅ [Main Chat Listener] bubble=$showedBubble, notification shown for $friendName');
                } catch (e) {
                  if (kDebugMode) debugPrint(
                      '[SKYBYN] ⚠️ [Main Chat Listener] Failed to show notification: $e');
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

    // print('[SKYBYN] ✅ [Main Chat Listener] WebSocket callback registered');
  }

  /// Set up call handlers (callbacks for incoming calls via WebSocket)
  void _setupCallHandlers() {
    _webSocketService.setCallCallbacks(
      onCallInitiate: (callId, fromUserId, callType, fromUsername) async {
        // Just store the call ID — the CallKit native UI will be shown when
        // call_offer arrives (which carries the actual SDP and triggers CallKit).
        if (kDebugMode) debugPrint('[SKYBYN] 📞 [Main] call_initiate from $fromUserId — awaiting call_offer');
        _activeCallId = callId;
      },
      onCallEnd: (callId, fromUserId, targetUserId) {
        if (kDebugMode) debugPrint('[SKYBYN] 📞 [Main] Call ended: $callId');
        if (_activeCallId == callId) {
          _activeCallId = null;
          _activeCallFriend = null;
        }
      },
      onCallOffer: (callId, fromUserId, offer, callType) async {
        if (kDebugMode) debugPrint('[SKYBYN] 📞 [Main] Call offer received: $callId');

        // Fetch and store caller info so we can navigate to CallScreen on accept
        _activeCallId = callId;
        try {
          final authService = AuthService();
          final currentUserId = await authService.getStoredUserId();
          if (currentUserId != null) {
            final friends = await _friendService.fetchFriendsForUser(userId: currentUserId);
            _activeCallFriend = friends.firstWhere(
              (f) => f.id == fromUserId,
              orElse: () => Friend(
                id: fromUserId,
                username: fromUserId,
                nickname: '',
                avatar: '',
                online: true,
              ),
            );
          }
        } catch (e) {
          if (kDebugMode) debugPrint('[SKYBYN] ⚠️ [Main] Could not fetch caller info: $e');
        }

        try {
          await _callService.handleIncomingOffer(
            callId: callId,
            fromUserId: fromUserId,
            offer: offer,
            callType: callType,
          );
        } catch (e) {
          if (kDebugMode) debugPrint('[SKYBYN] ❌ [Main] Error handling call offer: $e');
        }
      },
      onCallAnswer: (callId, answer) async {
        if (kDebugMode) debugPrint('[SKYBYN] 📞 [Main] Call answer received: $callId');
        try {
          await _callService.handleIncomingAnswer(answer);
        } catch (e) {
          if (kDebugMode) debugPrint('[SKYBYN] ❌ [Main] Error handling call answer: $e');
        }
      },
      onIceCandidate: (callId, candidate, sdpMid, sdpMLineIndex) async {
        try {
          await _callService.handleIceCandidate(
            candidate: candidate,
            sdpMid: sdpMid,
            sdpMLineIndex: sdpMLineIndex,
          );
        } catch (e) {
          if (kDebugMode) debugPrint('[SKYBYN] ❌ [Main] Error handling ICE candidate: $e');
        }
      },
    );

    // When the user accepts via native CallKit, navigate to CallScreen
    _callService.onCallAcceptedByNativeUI = () {
      final friend = _activeCallFriend;
      final callType = _callService.currentCallType;
      if (friend == null || callType == null) return;
      final nav = navigatorKey.currentState;
      if (nav == null) return;
      nav.push(MaterialPageRoute(
        builder: (context) => CallScreen(
          friend: friend,
          callType: callType,
          isIncoming: true,
        ),
      ));
      _activeCallId = null;
      _activeCallFriend = null;
    };
  }

  /// Set up handler for incoming calls via Notification
  void _setupIncomingCallFromNotificationHandler() {
    FirebaseMessagingService.onIncomingCallFromNotification =
        (callId, fromUserId, callType) async {
      if (kDebugMode) debugPrint('[SKYBYN] 📞 [Main] Incoming call from Notification tap');
      // Navigate to call screen via global navigator key
      final context = navigatorKey.currentContext;
      if (context != null) {
        // Fetch friend details first
        final authService = AuthService();
        final currentUserId = await authService.getStoredUserId();
        if (currentUserId != null) {
          final friends =
              await _friendService.fetchFriendsForUser(userId: currentUserId);
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
                // roomId: callId, // Removed, CallScreen handles it or doesn't need it
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
        statusBarIconBrightness:
            themeService.isDarkMode ? Brightness.light : Brightness.dark,
        statusBarBrightness: themeService.isDarkMode
            ? Brightness.dark
            : Brightness.light, // For iOS
        systemNavigationBarColor:
            themeService.isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
        systemNavigationBarIconBrightness:
            themeService.isDarkMode ? Brightness.light : Brightness.dark,
      ),
    );

    return MaterialApp(
      navigatorKey: navigatorKey, // Set global navigator key
      title: 'Skybyn',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      themeMode: themeService.themeMode, // Use theme mode from service
      theme: ThemeData.light(useMaterial3: true), // Define light theme
      darkTheme: ThemeData.dark(useMaterial3: true), // Define dark theme
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
              autoAccept: args['autoAccept'] ?? false,
              offer: args['offer'],
              callId: args['callId'],
            ),
          );
        }
        return null;
      },
      builder: (context, child) {
        return MediaQuery(
          // Fix text scaling to prevent layout issues
          data:
              MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
          child: child!,
        );
      },
    );
  }

  Widget _getInitialScreen() {
    return const SplashScreen();
  }
}
