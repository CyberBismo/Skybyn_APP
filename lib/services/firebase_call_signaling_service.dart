import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import '../config/constants.dart';

/// Firebase-based WebRTC signaling service
class FirebaseCallSignalingService {
  static final FirebaseCallSignalingService _instance = FirebaseCallSignalingService._internal();
  factory FirebaseCallSignalingService() => _instance;
  FirebaseCallSignalingService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String? _userId;
  
  // Stream subscriptions
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _callOfferSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _callAnswerSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _iceCandidatesSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _callEndSubscription;

  // Callbacks for WebRTC signaling
  Function(String, String, String, String)? _onCallOffer; // callId, fromUserId, offer, callType
  Function(String, String)? _onCallAnswer; // callId, answer
  Function(String, String, String, int)? _onIceCandidate; // callId, candidate, sdpMid, sdpMLineIndex
  Function(String, String, String)? _onCallEnd; // callId, fromUserId, targetUserId
  Function(String, String, String, String)? _onCallInitiate; // callId, fromUserId, callType, fromUsername

  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  /// Initialize the service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      print('🔄 [FirebaseCallSignaling] Initializing...');
      
      final authService = AuthService();
      final user = await authService.getStoredUserProfile();
      _userId = user?.id;
      
      if (_userId == null) {
        print('⚠️ [FirebaseCallSignaling] No user logged in');
        return;
      }

      _isInitialized = true;
      print('✅ [FirebaseCallSignaling] Initialized');
    } catch (e) {
      print('❌ [FirebaseCallSignaling] Error initializing: $e');
      rethrow;
    }
  }

  /// Set up call-related callbacks
  void setCallCallbacks({
    Function(String, String, String, String)? onCallInitiate,
    Function(String, String, String, String)? onCallOffer,
    Function(String, String)? onCallAnswer,
    Function(String, String, String, int)? onIceCandidate,
    Function(String, String, String)? onCallEnd,
  }) {
    _onCallInitiate = onCallInitiate;
    _onCallOffer = onCallOffer;
    _onCallAnswer = onCallAnswer;
    _onIceCandidate = onIceCandidate;
    _onCallEnd = onCallEnd;

    // Set up listeners if initialized
    if (_isInitialized && _userId != null) {
      _setupCallListeners();
    }
  }

  /// Set up Firestore listeners for call signaling
  void _setupCallListeners() {
    if (_userId == null) return;

    // Listen to incoming call offers
    _callOfferSubscription = _firestore
        .collection('call_signals')
        .where('targetUserId', isEqualTo: _userId)
        .where('type', isEqualTo: 'call_offer')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snapshot) {
      for (var doc in snapshot.docChanges) {
        if (doc.type == DocumentChangeType.added) {
          final data = doc.doc.data() as Map<String, dynamic>;
          final callId = doc.doc.id;
          final fromUserId = data['fromUserId'] as String? ?? '';
          final offer = data['offer'] as String? ?? '';
          // Extract callType - must be present, log warning if missing
          final callTypeRaw = data['callType'];
          String callType;
          if (callTypeRaw != null) {
            callType = callTypeRaw is String 
                ? callTypeRaw.toLowerCase().trim()
                : callTypeRaw.toString().toLowerCase().trim();
            // Normalize to 'video' or 'audio'
            if (callType != 'video' && callType != 'audio') {
              print('⚠️ [FirebaseCallSignaling] Invalid callType: $callType, defaulting to audio');
              callType = 'audio';
            }
          } else {
            print('⚠️ [FirebaseCallSignaling] callType missing in call_offer, defaulting to audio');
            callType = 'audio';
          }
          
          print('📞 [FirebaseCallSignaling] Received call_offer: callId=$callId, fromUserId=$fromUserId, callType=$callType (raw: $callTypeRaw)');
          _onCallOffer?.call(callId, fromUserId, offer, callType);
          
          // Mark as received
          doc.doc.reference.update({'status': 'received'});
        }
      }
    });

    // Listen to call answers
    _callAnswerSubscription = _firestore
        .collection('call_signals')
        .where('targetUserId', isEqualTo: _userId)
        .where('type', isEqualTo: 'call_answer')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snapshot) {
      for (var doc in snapshot.docChanges) {
        if (doc.type == DocumentChangeType.added) {
          final data = doc.doc.data() as Map<String, dynamic>;
          final callId = doc.doc.id;
          final answer = data['answer'] as String? ?? '';
          
          print('📞 [FirebaseCallSignaling] Received call_answer: callId=$callId');
          _onCallAnswer?.call(callId, answer);
          
          // Mark as received
          doc.doc.reference.update({'status': 'received'});
        }
      }
    });

    // Listen to ICE candidates
    _iceCandidatesSubscription = _firestore
        .collection('call_signals')
        .where('targetUserId', isEqualTo: _userId)
        .where('type', isEqualTo: 'ice_candidate')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snapshot) {
      for (var doc in snapshot.docChanges) {
        if (doc.type == DocumentChangeType.added) {
          final data = doc.doc.data() as Map<String, dynamic>;
          final callId = data['callId'] as String? ?? '';
          final candidate = data['candidate'] as String? ?? '';
          final sdpMid = data['sdpMid'] as String? ?? '';
          final sdpMLineIndex = (data['sdpMLineIndex'] as num?)?.toInt() ?? 0;
          
          if (kDebugMode) {
            print('📞 [FirebaseCallSignaling] Received ice_candidate: callId=$callId');
          }
          _onIceCandidate?.call(callId, candidate, sdpMid, sdpMLineIndex);
          
          // Mark as received and delete (ICE candidates are one-time use)
          doc.doc.reference.delete();
        }
      }
    });

    // Listen to call end
    _callEndSubscription = _firestore
        .collection('call_signals')
        .where('targetUserId', isEqualTo: _userId)
        .where('type', isEqualTo: 'call_end')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snapshot) {
      for (var doc in snapshot.docChanges) {
        if (doc.type == DocumentChangeType.added) {
          final data = doc.doc.data() as Map<String, dynamic>;
          final callId = doc.doc.id;
          final fromUserId = data['fromUserId'] as String? ?? '';
          final targetUserId = data['targetUserId'] as String? ?? '';
          
          print('📞 [FirebaseCallSignaling] Received call_end: callId=$callId, fromUserId=$fromUserId, targetUserId=$targetUserId');
          _onCallEnd?.call(callId, fromUserId, targetUserId);
          
          // Mark as received
          doc.doc.reference.update({'status': 'received'});
        }
      }
    });
  }

  /// Send call offer
  Future<void> sendCallOffer({
    required String callId,
    required String targetUserId,
    required String offer,
    required String callType,
  }) async {
    if (_userId == null) {
      print('⚠️ [FirebaseCallSignaling] Cannot send call offer - no user logged in');
      return;
    }

    try {
      // Normalize callType to ensure it's 'video' or 'audio'
      final normalizedCallType = callType.toLowerCase().trim();
      final finalCallType = (normalizedCallType == 'video' || normalizedCallType == 'audio') 
          ? normalizedCallType 
          : 'audio';
      
      if (finalCallType != normalizedCallType) {
        print('⚠️ [FirebaseCallSignaling] Invalid callType "$callType" normalized to "$finalCallType"');
      }
      
      // Write call offer to Firestore for real-time signaling
      await _firestore.collection('call_signals').doc(callId).set({
        'type': 'call_offer',
        'callId': callId,
        'fromUserId': _userId,
        'targetUserId': targetUserId,
        'offer': offer,
        'callType': finalCallType, // Store normalized callType
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
      
      print('📞 [FirebaseCallSignaling] Sent call_offer: callId=$callId, targetUserId=$targetUserId, type=$finalCallType (original: $callType)');
      
      // ALWAYS send FCM push notification (for both online and offline users)
      // This ensures the recipient gets a notification even if they're offline or the app is closed
      // Await the notification to ensure it's sent, but don't fail the call if it fails
      try {
        await _sendCallNotification(targetUserId, callId, finalCallType);
        print('✅ [FirebaseCallSignaling] FCM notification sent successfully');
      } catch (error) {
        // Don't fail the call if FCM notification fails - it's optional but log the error
        print('⚠️ [FirebaseCallSignaling] FCM notification failed (non-critical): $error');
      }
    } catch (e) {
      print('❌ [FirebaseCallSignaling] Error sending call offer: $e');
      rethrow;
    }
  }
  
  /// Send FCM push notification for incoming call
  Future<void> _sendCallNotification(String targetUserId, String callId, String callType) async {
    try {
      // Get API base URL from constants
      final apiBase = ApiConstants.apiBase;
      
      // Get sender's username/nickname for notification
      final authService = AuthService();
      final user = await authService.getStoredUserProfile();
      final senderName = user?.nickname?.isNotEmpty == true 
          ? user!.nickname 
          : user?.username ?? 'Someone';
      
      final callTypeText = callType == 'video' ? 'video call' : 'voice call';
      
      // Send FCM notification via backend API
      final response = await http.post(
        Uri.parse('$apiBase/firebase.php'),
        body: {
          'user': targetUserId,
          'title': senderName,
          'body': 'Incoming $callTypeText',
          'type': 'call',
          'from': _userId!,
          'priority': 'high',
          'channel': 'calls',
          'payload': jsonEncode({
            'callId': callId,
            'callType': callType,
            'fromUserId': _userId,
            'incomingCall': 'true',
          }),
        },
      );
      
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['status'] == 'success') {
          print('✅ [FirebaseCallSignaling] FCM call notification sent successfully');
        } else {
          print('⚠️ [FirebaseCallSignaling] FCM notification failed: ${result['message']}');
        }
      } else {
        print('⚠️ [FirebaseCallSignaling] FCM notification HTTP error: ${response.statusCode}');
      }
    } catch (e) {
      // Don't fail the call if FCM notification fails - it's optional
      print('⚠️ [FirebaseCallSignaling] Error sending FCM notification: $e');
    }
  }

  /// Send call answer
  Future<void> sendCallAnswer({
    required String callId,
    required String targetUserId,
    required String answer,
  }) async {
    if (_userId == null) {
      print('⚠️ [FirebaseCallSignaling] Cannot send call answer - no user logged in');
      return;
    }

    try {
      await _firestore.collection('call_signals').doc('${callId}_answer').set({
        'type': 'call_answer',
        'callId': callId,
        'fromUserId': _userId,
        'targetUserId': targetUserId,
        'answer': answer,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
      
      print('📞 [FirebaseCallSignaling] Sent call_answer: callId=$callId, targetUserId=$targetUserId');
    } catch (e) {
      print('❌ [FirebaseCallSignaling] Error sending call answer: $e');
      rethrow;
    }
  }

  /// Send ICE candidate
  Future<void> sendIceCandidate({
    required String callId,
    required String targetUserId,
    required String candidate,
    required String sdpMid,
    required int sdpMLineIndex,
  }) async {
    if (_userId == null) {
      print('⚠️ [FirebaseCallSignaling] Cannot send ICE candidate - no user logged in');
      return;
    }

    try {
      await _firestore.collection('call_signals').add({
        'type': 'ice_candidate',
        'callId': callId,
        'fromUserId': _userId,
        'targetUserId': targetUserId,
        'candidate': candidate,
        'sdpMid': sdpMid,
        'sdpMLineIndex': sdpMLineIndex,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
      
      if (kDebugMode) {
        print('📞 [FirebaseCallSignaling] Sent ice_candidate: callId=$callId, targetUserId=$targetUserId');
      }
    } catch (e) {
      print('❌ [FirebaseCallSignaling] Error sending ICE candidate: $e');
      rethrow;
    }
  }

  /// Send call end
  Future<void> sendCallEnd({
    required String callId,
    required String targetUserId,
  }) async {
    if (_userId == null) {
      print('⚠️ [FirebaseCallSignaling] Cannot send call end - no user logged in');
      return;
    }

    try {
      await _firestore.collection('call_signals').doc('${callId}_end').set({
        'type': 'call_end',
        'callId': callId,
        'fromUserId': _userId,
        'targetUserId': targetUserId,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
      
      print('📞 [FirebaseCallSignaling] Sent call_end: callId=$callId, targetUserId=$targetUserId');
    } catch (e) {
      print('❌ [FirebaseCallSignaling] Error sending call end: $e');
      rethrow;
    }
  }

  /// Clean up and disconnect
  Future<void> disconnect() async {
    await _callOfferSubscription?.cancel();
    await _callAnswerSubscription?.cancel();
    await _iceCandidatesSubscription?.cancel();
    await _callEndSubscription?.cancel();
    
    _callOfferSubscription = null;
    _callAnswerSubscription = null;
    _iceCandidatesSubscription = null;
    _callEndSubscription = null;
    
    print('✅ [FirebaseCallSignaling] Disconnected');
  }
}

