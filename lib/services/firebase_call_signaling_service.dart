// Firestore disabled - using WebSocket for real-time features instead
// import 'package:cloud_firestore/cloud_firestore.dart';
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

  // Firestore disabled - using WebSocket for real-time features instead
  // final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String? _userId;
  
  // Stream subscriptions (Firestore disabled - these are not used)
  StreamSubscription<dynamic>? _callOfferSubscription;
  StreamSubscription<dynamic>? _callAnswerSubscription;
  StreamSubscription<dynamic>? _iceCandidatesSubscription;
  StreamSubscription<dynamic>? _callEndSubscription;

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
      final authService = AuthService();
      final user = await authService.getStoredUserProfile();
      _userId = user?.id;
      
      if (_userId == null) {
        return;
      }

      _isInitialized = true;
    } catch (e) {
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
  /// DISABLED: Firestore is not used - WebSocket handles call signaling
  void _setupCallListeners() {
    // Firestore disabled - using WebSocket for real-time features instead
    return;
    
    /* DISABLED - Firestore not used
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
              callType = 'audio';
            }
          } else {
            callType = 'audio';
          }
          
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
          _onCallEnd?.call(callId, fromUserId, targetUserId);
          
          // Mark as received
          doc.doc.reference.update({'status': 'received'});
        }
      }
    });
    */ // End of disabled Firestore code
  }

  /// Send call offer
  /// DISABLED: Firestore is not used - WebSocket handles call signaling
  Future<void> sendCallOffer({
    required String callId,
    required String targetUserId,
    required String offer,
    required String callType,
  }) async {
    // Firestore disabled - using WebSocket for real-time features instead
    return;
    
    /* DISABLED - Firestore not used
    if (_userId == null) {
      return;
    }

    try {
      // Normalize callType to ensure it's 'video' or 'audio'
      final normalizedCallType = callType.toLowerCase().trim();
      final finalCallType = (normalizedCallType == 'video' || normalizedCallType == 'audio') 
          ? normalizedCallType 
          : 'audio';
      
      if (finalCallType != normalizedCallType) {
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
      
      
      // Note: FCM notifications are handled by the backend WebSocket server
      // The backend will send notifications when it receives the call_offer via WebSocket
      // This service is only used for Firestore-based signaling (fallback/alternative path)
    } catch (e) {
      rethrow;
    }
    */ // End of disabled Firestore code
  }
  
  /// Send FCM push notification for incoming call
  Future<void> _sendCallNotification(String targetUserId, String callId, String callType) async {
    try {
      // Get API base URL from constants
      final apiBase = ApiConstants.apiBase;
      
      // Get sender's username/nickname for notification
      final authService = AuthService();
      final user = await authService.getStoredUserProfile();
      final senderName = user?.nickname.isNotEmpty == true 
          ? user!.nickname 
          : user?.username ?? 'Someone';
      
      final callTypeText = callType == 'video' ? 'video call' : 'voice call';
      
      final requestBody = {
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
      };
      // Send FCM notification via backend API
      final response = await http.post(
        Uri.parse('$apiBase/firebase.php'),
        body: requestBody,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['status'] == 'success') {
        } else {
        }
      } else {
      }
    } catch (e) {
      // Don't fail the call if FCM notification fails - it's optional
    }
  }

  /// Send call answer
  /// DISABLED: Firestore is not used - WebSocket handles call signaling
  Future<void> sendCallAnswer({
    required String callId,
    required String targetUserId,
    required String answer,
  }) async {
    // Firestore disabled - using WebSocket for real-time features instead
    return;
    
    /* DISABLED - Firestore not used
    if (_userId == null) {
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
    } catch (e) {
      rethrow;
    }
    */ // End of disabled Firestore code
  }

  /// Send ICE candidate
  /// DISABLED: Firestore is not used - WebSocket handles call signaling
  Future<void> sendIceCandidate({
    required String callId,
    required String targetUserId,
    required String candidate,
    required String sdpMid,
    required int sdpMLineIndex,
  }) async {
    // Firestore disabled - using WebSocket for real-time features instead
    return;
    
    /* DISABLED - Firestore not used
    if (_userId == null) {
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
    } catch (e) {
      rethrow;
    }
    */ // End of disabled Firestore code
  }

  /// Send call end
  /// DISABLED: Firestore is not used - WebSocket handles call signaling
  Future<void> sendCallEnd({
    required String callId,
    required String targetUserId,
  }) async {
    // Firestore disabled - using WebSocket for real-time features instead
    return;
    
    /* DISABLED - Firestore not used
    if (_userId == null) {
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
    } catch (e) {
      rethrow;
    }
    */ // End of disabled Firestore code
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
  }
}

