import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'auth_service.dart';

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
          final callType = data['callType'] as String? ?? 'audio';
          
          print('📞 [FirebaseCallSignaling] Received call_offer: callId=$callId, fromUserId=$fromUserId');
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
      await _firestore.collection('call_signals').doc(callId).set({
        'type': 'call_offer',
        'callId': callId,
        'fromUserId': _userId,
        'targetUserId': targetUserId,
        'offer': offer,
        'callType': callType,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
      
      print('📞 [FirebaseCallSignaling] Sent call_offer: callId=$callId, targetUserId=$targetUserId, type=$callType');
    } catch (e) {
      print('❌ [FirebaseCallSignaling] Error sending call offer: $e');
      rethrow;
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

