import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter/material.dart';
import 'firebase_call_signaling_service.dart';
import 'auth_service.dart';

enum CallType { audio, video }
enum CallState { idle, calling, ringing, connected, ended }

class CallService {
  static final CallService _instance = CallService._internal();
  factory CallService() => _instance;
  CallService._internal();

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  CallState _callState = CallState.idle;
  CallType? _currentCallType;
  String? _currentCallId;
  String? _otherUserId;
  bool _isCaller = false;

  // Callbacks
  Function(CallState)? onCallStateChanged;
  Function(MediaStream?)? onLocalStream;
  Function(MediaStream?)? onRemoteStream;
  Function(String)? onCallError;

  // Getters
  CallState get callState => _callState;
  CallType? get currentCallType => _currentCallType;
  String? get currentCallId => _currentCallId;
  String? get otherUserId => _otherUserId;
  bool get isCaller => _isCaller;

  final FirebaseCallSignalingService _signalingService = FirebaseCallSignalingService();
  final AuthService _authService = AuthService();

  /// Initialize WebRTC configuration
  Map<String, dynamic> get _configuration {
    return {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        // Add your TURN servers here if needed
        // {'urls': 'turn:your-turn-server.com:3478', 'username': 'user', 'credential': 'pass'}
      ],
    };
  }

  /// Start a call (initiate)
  Future<void> startCall(String otherUserId, CallType callType) async {
    try {
      _otherUserId = otherUserId;
      _currentCallType = callType;
      _isCaller = true;
      _currentCallId = DateTime.now().millisecondsSinceEpoch.toString();
      _updateCallState(CallState.calling);

      // Get user media
      await _getUserMedia(callType);

      // Create peer connection
      await _createPeerConnection();

      // Add local stream to peer connection
      if (_localStream != null) {
        _localStream!.getTracks().forEach((track) {
          _peerConnection?.addTrack(track, _localStream!);
        });
      }

      // Create and send offer
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      // Ensure signaling service is initialized
      if (!_signalingService.isInitialized) {
        await _signalingService.initialize();
      }

      // Send offer through Firebase
      await _signalingService.sendCallOffer(
        callId: _currentCallId!,
        targetUserId: otherUserId,
        offer: offer.sdp!,
        callType: callType == CallType.video ? 'video' : 'audio',
      );

      print('📞 [CallService] Call initiated: $callType to $otherUserId');
    } catch (e) {
      print('❌ [CallService] Error starting call: $e');
      _updateCallState(CallState.ended);
      onCallError?.call('Failed to start call: $e');
    }
  }

  /// Handle incoming call offer
  Future<void> handleIncomingOffer({
    required String callId,
    required String fromUserId,
    required String offer,
    required String callType,
  }) async {
    try {
      _currentCallId = callId;
      _otherUserId = fromUserId;
      _isCaller = false;
      _currentCallType = callType == 'video' ? CallType.video : CallType.audio;
      _updateCallState(CallState.ringing);

      // Get user media
      await _getUserMedia(_currentCallType!);

      // Create peer connection
      await _createPeerConnection();

      // Add local stream to peer connection
      if (_localStream != null) {
        _localStream!.getTracks().forEach((track) {
          _peerConnection?.addTrack(track, _localStream!);
        });
      }

      // Set remote description
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(offer, 'offer'),
      );

      // Create and send answer
      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);

      // Send answer through Firebase
      await _signalingService.sendCallAnswer(
        callId: callId,
        targetUserId: fromUserId,
        answer: answer.sdp!,
      );

      print('📞 [CallService] Incoming call answered: $callType from $fromUserId');
    } catch (e) {
      print('❌ [CallService] Error handling offer: $e');
      _updateCallState(CallState.ended);
      onCallError?.call('Failed to handle incoming call: $e');
    }
  }

  /// Handle incoming call answer
  Future<void> handleIncomingAnswer(String answer) async {
    try {
      if (_peerConnection == null) {
        print('⚠️ [CallService] Cannot handle answer - peer connection is null');
        return;
      }
      print('📞 [CallService] Handling call answer (length: ${answer.length})');
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(answer, 'answer'),
      );
      print('✅ [CallService] Call answer processed successfully');
    } catch (e) {
      print('❌ [CallService] Error handling answer: $e');
      onCallError?.call('Failed to handle answer: $e');
    }
  }

  /// Handle ICE candidate
  Future<void> handleIceCandidate({
    required String candidate,
    required String sdpMid,
    required int sdpMLineIndex,
  }) async {
    try {
      await _peerConnection?.addCandidate(
        RTCIceCandidate(candidate, sdpMid, sdpMLineIndex),
      );
      print('📞 [CallService] ICE candidate added');
    } catch (e) {
      print('❌ [CallService] Error handling ICE candidate: $e');
    }
  }

  /// Accept incoming call
  Future<void> acceptCall() async {
    if (_callState == CallState.ringing) {
      _updateCallState(CallState.connected);
      // Answer was already sent in handleIncomingOffer
    }
  }

  /// Reject incoming call
  Future<void> rejectCall() async {
    if (_currentCallId != null && _otherUserId != null) {
      await _signalingService.sendCallEnd(
        callId: _currentCallId!,
        targetUserId: _otherUserId!,
      );
    }
    await endCall();
  }

  /// End the call
  Future<void> endCall() async {
    try {
      if (_currentCallId != null && _otherUserId != null && _isCaller) {
        await _signalingService.sendCallEnd(
          callId: _currentCallId!,
          targetUserId: _otherUserId!,
        );
      }

      await _localStream?.dispose();
      await _remoteStream?.dispose();
      await _peerConnection?.close();

      _localStream = null;
      _remoteStream = null;
      _peerConnection = null;
      _currentCallId = null;
      _otherUserId = null;
      _currentCallType = null;
      _isCaller = false;

      _updateCallState(CallState.ended);
      _updateCallState(CallState.idle);

      print('📞 [CallService] Call ended');
    } catch (e) {
      print('❌ [CallService] Error ending call: $e');
    }
  }

  /// Get user media (camera/microphone)
  Future<void> _getUserMedia(CallType callType) async {
    try {
      final constraints = <String, dynamic>{
        'audio': true,
        'video': callType == CallType.video
            ? {
                'facingMode': 'user',
                'width': {'ideal': 1280},
                'height': {'ideal': 720},
              }
            : false,
      };

      _localStream = await navigator.mediaDevices.getUserMedia(constraints);
      onLocalStream?.call(_localStream);
      print('📞 [CallService] Local media stream obtained');
    } catch (e) {
      print('❌ [CallService] Error getting user media: $e');
      onCallError?.call('Failed to access camera/microphone: $e');
      rethrow;
    }
  }

  /// Create peer connection
  Future<void> _createPeerConnection() async {
    try {
      _peerConnection = await createPeerConnection(_configuration);

      // Handle ICE candidates
      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        if (_currentCallId != null && _otherUserId != null) {
          _signalingService.sendIceCandidate(
            callId: _currentCallId!,
            targetUserId: _otherUserId!,
            candidate: candidate.candidate!,
            sdpMid: candidate.sdpMid ?? '',
            sdpMLineIndex: candidate.sdpMLineIndex ?? 0,
          );
        }
      };

      // Handle remote stream
      _peerConnection!.onTrack = (RTCTrackEvent event) {
        if (event.streams.isNotEmpty) {
          _remoteStream = event.streams[0];
          onRemoteStream?.call(_remoteStream);
          if (_callState == CallState.calling || _callState == CallState.ringing) {
            _updateCallState(CallState.connected);
          }
          print('📞 [CallService] Remote stream received');
        }
      };

      // Handle connection state changes
      _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
        print('📞 [CallService] Connection state: $state');
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          print('⚠️ [CallService] Connection disconnected - may reconnect');
          // Don't end call immediately on disconnect - wait to see if it reconnects
        } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          print('❌ [CallService] Connection failed - ending call');
          onCallError?.call('Connection failed. Please try again.');
          endCall();
        } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          print('❌ [CallService] Connection closed - ending call');
          // Only end call if it wasn't already ended
          if (_callState != CallState.ended && _callState != CallState.idle) {
            endCall();
          }
        } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          print('✅ [CallService] Connection established');
        }
      };

      print('📞 [CallService] Peer connection created');
    } catch (e) {
      print('❌ [CallService] Error creating peer connection: $e');
      onCallError?.call('Failed to create connection: $e');
      rethrow;
    }
  }

  /// Update call state
  void _updateCallState(CallState state) {
    _callState = state;
    onCallStateChanged?.call(state);
  }

  /// Toggle camera (for video calls)
  Future<void> toggleCamera() async {
    if (_localStream != null && _currentCallType == CallType.video) {
      final videoTrack = _localStream!.getVideoTracks().firstOrNull;
      if (videoTrack != null) {
        videoTrack.enabled = !videoTrack.enabled!;
      }
    }
  }

  /// Toggle microphone
  Future<void> toggleMicrophone() async {
    if (_localStream != null) {
      final audioTrack = _localStream!.getAudioTracks().firstOrNull;
      if (audioTrack != null) {
        audioTrack.enabled = !audioTrack.enabled!;
      }
    }
  }

  /// Switch camera (front/back)
  Future<void> switchCamera() async {
    if (_localStream != null && _currentCallType == CallType.video) {
      final videoTrack = _localStream!.getVideoTracks().firstOrNull;
      if (videoTrack != null && videoTrack is MediaStreamTrack) {
        await Helper.switchCamera(videoTrack);
      }
    }
  }
}

