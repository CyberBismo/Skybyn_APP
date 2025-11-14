import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter/material.dart';
import 'websocket_service.dart';
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

  final WebSocketService _signalingService = WebSocketService();
  final AuthService _authService = AuthService();

  /// Initialize WebRTC configuration
  Map<String, dynamic> get _configuration {
    return {
      'iceServers': [
        // STUN servers for NAT discovery
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
        {'urls': 'stun:stun2.l.google.com:19302'},
        // TURN servers for relay (when direct P2P connection fails)
        // Free public TURN servers (use with caution - may have rate limits)
        {
          'urls': 'turn:openrelay.metered.ca:80',
          'username': 'openrelayproject',
          'credential': 'openrelayproject'
        },
        {
          'urls': 'turn:openrelay.metered.ca:443',
          'username': 'openrelayproject',
          'credential': 'openrelayproject'
        },
        {
          'urls': 'turn:openrelay.metered.ca:443?transport=tcp',
          'username': 'openrelayproject',
          'credential': 'openrelayproject'
        },
        // Additional free TURN server
        {
          'urls': 'turn:relay.metered.ca:80',
          'username': 'openrelayproject',
          'credential': 'openrelayproject'
        },
        {
          'urls': 'turn:relay.metered.ca:443',
          'username': 'openrelayproject',
          'credential': 'openrelayproject'
        },
        {
          'urls': 'turn:relay.metered.ca:443?transport=tcp',
          'username': 'openrelayproject',
          'credential': 'openrelayproject'
        },
        // Note: For production, consider using your own TURN server
        // Example: {'urls': 'turn:your-turn-server.com:3478', 'username': 'user', 'credential': 'pass'}
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

      // Ensure WebSocket is connected before sending call offer
      if (!_signalingService.isConnected) {
        print('⚠️ [CallService] WebSocket not connected, attempting to connect...');
        // Try to connect WebSocket
        await _signalingService.connect().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            print('❌ [CallService] WebSocket connection timeout');
            throw Exception('WebSocket connection timeout');
          },
        );
        
        // Wait a bit more for connection to be fully established
        int waitAttempts = 0;
        while (!_signalingService.isConnected && waitAttempts < 10) {
          await Future.delayed(const Duration(milliseconds: 200));
          waitAttempts++;
        }
        
        if (!_signalingService.isConnected) {
          throw Exception('WebSocket failed to connect');
        }
        
        print('✅ [CallService] WebSocket connected, proceeding with call');
      }

      // Send offer through WebSocket
      _signalingService.sendCallOffer(
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
      // The answer will automatically include the tracks we added to the peer connection
      // For video calls, we need to ensure the answer includes video tracks
      final answer = await _peerConnection!.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': _currentCallType == CallType.video,
      });
      await _peerConnection!.setLocalDescription(answer);
      
      // Log tracks to verify they're included
      print('📞 [CallService] Answer created - local tracks: ${_localStream?.getTracks().length ?? 0}');
      if (_localStream != null) {
        final videoTracks = _localStream!.getVideoTracks();
        final audioTracks = _localStream!.getAudioTracks();
        print('📞 [CallService] Local video tracks: ${videoTracks.length}, audio tracks: ${audioTracks.length}');
      }

      // Send answer through WebSocket
      _signalingService.sendCallAnswer(
        callId: callId,
        targetUserId: fromUserId,
        answer: answer.sdp!,
      );

      // Update state to "calling" to indicate we've answered and are connecting
      // This prevents showing the answer button again in CallScreen
      // The state will be updated to connected when remote stream is received
      _updateCallState(CallState.calling);

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
      // Answer was already sent in handleIncomingOffer
      // Update state to indicate we're connecting (waiting for ICE connection)
      // The state will be updated to connected when remote stream is received
      _updateCallState(CallState.calling); // Use calling state to indicate "connecting"
    }
  }

  /// Reject incoming call
  Future<void> rejectCall() async {
    if (_currentCallId != null && _otherUserId != null) {
      _signalingService.sendCallEnd(
        callId: _currentCallId!,
        targetUserId: _otherUserId!,
      );
    }
    await endCall();
  }

  /// End the call
  Future<void> endCall() async {
    try {
      if (_currentCallId != null && _otherUserId != null) {
        _signalingService.sendCallEnd(
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
          
          // Log remote stream details
          final videoTracks = _remoteStream!.getVideoTracks();
          final audioTracks = _remoteStream!.getAudioTracks();
          print('📞 [CallService] Remote stream received - video tracks: ${videoTracks.length}, audio tracks: ${audioTracks.length}');
          print('📞 [CallService] Remote stream received, current state: $_callState');
          
          // Update to connected if we're in calling or ringing state
          if (_callState == CallState.calling || _callState == CallState.ringing) {
            print('📞 [CallService] Updating call state to connected');
            _updateCallState(CallState.connected);
          }
        } else {
          print('⚠️ [CallService] onTrack event received but streams is empty');
        }
      };

      // Handle connection state changes
      _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
        print('📞 [CallService] Connection state: $state, current call state: $_callState');
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
          print('✅ [CallService] Connection established, updating call state to connected');
          // Also update call state to connected when peer connection is established
          // This is a backup in case onTrack doesn't fire (e.g., for audio-only calls)
          if (_callState == CallState.calling || _callState == CallState.ringing) {
            _updateCallState(CallState.connected);
          }
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

