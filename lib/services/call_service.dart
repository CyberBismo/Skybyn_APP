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
  Timer? _callTimeoutTimer;
  static const Duration _callTimeoutDuration = Duration(seconds: 45);

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
    print('');
    print('═══════════════════════════════════════════════════════════');
    print('📞 [CALL] STEP 0: CALL INITIATION STARTED');
    print('📞 [CALL] Target: $otherUserId | Type: $callType');
    print('═══════════════════════════════════════════════════════════');
    try {
      _otherUserId = otherUserId;
      _currentCallType = callType;
      _isCaller = true;
      _currentCallId = DateTime.now().millisecondsSinceEpoch.toString();
      print('📞 [CALL] Call ID: $_currentCallId');
      _updateCallState(CallState.calling);
      print('📞 [CALL] State: calling');

      // Get user media
      print('');
      print('📞 [CALL] STEP 1: GETTING USER MEDIA');
      print('─────────────────────────────────────────────────────────');
      await _getUserMedia(callType);
      print('✅ [CALL] STEP 1: COMPLETE - User media obtained');

      // Create peer connection
      print('');
      print('📞 [CALL] STEP 2: CREATING PEER CONNECTION');
      print('─────────────────────────────────────────────────────────');
      await _createPeerConnection();
      print('✅ [CALL] STEP 2: COMPLETE - Peer connection created');

      // Add local stream to peer connection
      print('');
      print('📞 [CALL] STEP 3: ADDING LOCAL STREAM TRACKS');
      print('─────────────────────────────────────────────────────────');
      if (_localStream != null) {
        final tracks = _localStream!.getTracks();
        print('📞 [CALL] Found ${tracks.length} tracks in local stream');
        tracks.forEach((track) {
          print('📞 [CALL] Adding track: ${track.kind} (enabled: ${track.enabled})');
          _peerConnection?.addTrack(track, _localStream!);
        });
        print('✅ [CALL] STEP 3: COMPLETE - All tracks added');
      } else {
        print('❌ [CALL] STEP 3: FAILED - Local stream is null!');
        throw Exception('Local stream is null');
      }

      // Create and send offer
      print('');
      print('📞 [CALL] STEP 4: CREATING OFFER');
      print('─────────────────────────────────────────────────────────');
      final offer = await _peerConnection!.createOffer();
      print('📞 [CALL] Offer created - SDP length: ${offer.sdp?.length ?? 0}');
      print('📞 [CALL] Offer type: ${offer.type}');
      await _peerConnection!.setLocalDescription(offer);
      print('✅ [CALL] STEP 4: COMPLETE - Local description set');

      // Ensure WebSocket is connected before sending call offer
      print('');
      print('📞 [CALL] STEP 5: CHECKING WEBSOCKET CONNECTION');
      print('─────────────────────────────────────────────────────────');
      if (!_signalingService.isConnected) {
        print('⚠️ [CALL] WebSocket not connected, attempting to connect...');
        // Try to connect WebSocket
        await _signalingService.connect().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            print('❌ [CALL] STEP 5: FAILED - WebSocket connection timeout');
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
          print('❌ [CALL] STEP 5: FAILED - WebSocket failed to connect');
          throw Exception('WebSocket failed to connect');
        }
        
        print('✅ [CALL] WebSocket connected');
      } else {
        print('✅ [CALL] WebSocket already connected');
      }
      print('✅ [CALL] STEP 5: COMPLETE');

      // Send offer through WebSocket
      print('');
      print('📞 [CALL] STEP 6: SENDING OFFER VIA WEBSOCKET');
      print('─────────────────────────────────────────────────────────');
      print('📞 [CALL] Call ID: $_currentCallId');
      print('📞 [CALL] Target User ID: $otherUserId');
      print('📞 [CALL] Offer SDP preview: ${offer.sdp?.substring(0, 100) ?? 'null'}...');
      _signalingService.sendCallOffer(
        callId: _currentCallId!,
        targetUserId: otherUserId,
        offer: offer.sdp!,
        callType: callType == CallType.video ? 'video' : 'audio',
      );
      print('✅ [CALL] STEP 6: COMPLETE - Offer sent via WebSocket');

      // Start call timeout timer
      print('');
      print('📞 [CALL] STEP 7: STARTING CALL TIMEOUT TIMER');
      print('─────────────────────────────────────────────────────────');
      _startCallTimeout();
      print('✅ [CALL] STEP 7: COMPLETE - Timeout timer started');

      print('');
      print('═══════════════════════════════════════════════════════════');
      print('✅ [CALL] CALL INITIATION COMPLETE - Waiting for answer...');
      print('═══════════════════════════════════════════════════════════');
      print('');
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
    print('');
    print('═══════════════════════════════════════════════════════════');
    print('📞 [CALL] INCOMING CALL - HANDLING OFFER');
    print('📞 [CALL] From: $fromUserId | Type: $callType | Call ID: $callId');
    print('═══════════════════════════════════════════════════════════');
    try {
      _currentCallId = callId;
      _otherUserId = fromUserId;
      _isCaller = false;
      _currentCallType = callType == 'video' ? CallType.video : CallType.audio;
      _updateCallState(CallState.ringing);
      print('📞 [CALL] State: ringing');

      // Start call timeout timer
      print('');
      print('📞 [CALL] STEP A1: STARTING CALL TIMEOUT TIMER');
      print('─────────────────────────────────────────────────────────');
      _startCallTimeout();
      print('✅ [CALL] STEP A1: COMPLETE');

      // Get user media
      print('');
      print('📞 [CALL] STEP A2: GETTING USER MEDIA');
      print('─────────────────────────────────────────────────────────');
      await _getUserMedia(_currentCallType!);
      print('✅ [CALL] STEP A2: COMPLETE');

      // Create peer connection
      print('');
      print('📞 [CALL] STEP A3: CREATING PEER CONNECTION');
      print('─────────────────────────────────────────────────────────');
      await _createPeerConnection();
      print('✅ [CALL] STEP A3: COMPLETE');

      // Add local stream to peer connection
      print('');
      print('📞 [CALL] STEP A4: ADDING LOCAL STREAM TRACKS');
      print('─────────────────────────────────────────────────────────');
      if (_localStream != null) {
        final tracks = _localStream!.getTracks();
        print('📞 [CALL] Found ${tracks.length} tracks');
        _localStream!.getTracks().forEach((track) {
          _peerConnection?.addTrack(track, _localStream!);
        });
        print('✅ [CALL] STEP A4: COMPLETE');
      } else {
        print('❌ [CALL] STEP A4: FAILED - Local stream is null');
        throw Exception('Local stream is null');
      }

      // Set remote description
      print('');
      print('📞 [CALL] STEP A5: SETTING REMOTE DESCRIPTION (OFFER)');
      print('─────────────────────────────────────────────────────────');
      print('📞 [CALL] Offer length: ${offer.length}');
      print('📞 [CALL] Offer preview: ${offer.substring(0, 100)}...');
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(offer, 'offer'),
      );
      print('✅ [CALL] STEP A5: COMPLETE');

      // Create and send answer
      print('');
      print('📞 [CALL] STEP A6: CREATING ANSWER');
      print('─────────────────────────────────────────────────────────');
      final answer = await _peerConnection!.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': _currentCallType == CallType.video,
      });
      print('📞 [CALL] Answer created - SDP length: ${answer.sdp?.length ?? 0}');
      print('📞 [CALL] Answer type: ${answer.type}');
      await _peerConnection!.setLocalDescription(answer);
      print('✅ [CALL] STEP A6: COMPLETE');
      
      // Log tracks to verify they're included
      print('📞 [CallService] Answer created - local tracks: ${_localStream?.getTracks().length ?? 0}');
      if (_localStream != null) {
        final videoTracks = _localStream!.getVideoTracks();
        final audioTracks = _localStream!.getAudioTracks();
        print('📞 [CallService] Local video tracks: ${videoTracks.length}, audio tracks: ${audioTracks.length}');
      }

      // Send answer through WebSocket
      print('');
      print('📞 [CALL] STEP A7: SENDING ANSWER VIA WEBSOCKET');
      print('─────────────────────────────────────────────────────────');
      print('📞 [CALL] Call ID: $callId');
      print('📞 [CALL] Target User ID: $fromUserId');
      print('📞 [CALL] Answer SDP preview: ${answer.sdp?.substring(0, 100) ?? 'null'}...');
      _signalingService.sendCallAnswer(
        callId: callId,
        targetUserId: fromUserId,
        answer: answer.sdp!,
      );
      print('✅ [CALL] STEP A7: COMPLETE - Answer sent');
      
      print('');
      print('═══════════════════════════════════════════════════════════');
      print('✅ [CALL] INCOMING CALL HANDLED - Waiting for connection...');
      print('═══════════════════════════════════════════════════════════');
      print('');

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
    print('');
    print('═══════════════════════════════════════════════════════════');
    print('📞 [CALL] RECEIVED ANSWER');
    print('═══════════════════════════════════════════════════════════');
    try {
      if (_peerConnection == null) {
        print('❌ [CALL] Cannot handle answer - peer connection is null');
        return;
      }
      print('📞 [CALL] Answer length: ${answer.length}');
      print('📞 [CALL] Answer preview: ${answer.substring(0, 100)}...');
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(answer, 'answer'),
      );
      print('✅ [CALL] Remote description (answer) set');
      
      // Log current ICE connection state after setting answer
      final iceState = _peerConnection?.iceConnectionState;
      final connectionState = _peerConnection?.connectionState;
      print('📞 [CALL] ICE state: $iceState');
      print('📞 [CALL] Connection state: $connectionState');
      print('═══════════════════════════════════════════════════════════');
      print('');
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
      print('📞 [CALL] ICE candidate received: ${candidate.substring(0, 50)}...');
      print('📞 [CALL] sdpMid: $sdpMid, index: $sdpMLineIndex');
      await _peerConnection?.addCandidate(
        RTCIceCandidate(candidate, sdpMid, sdpMLineIndex),
      );
      print('✅ [CALL] ICE candidate added');
    } catch (e) {
      print('❌ [CallService] Error handling ICE candidate: $e');
      // Don't fail the call on ICE candidate errors - they're often non-critical
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
      // Cancel timeout timer
      _cancelCallTimeout();

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

  /// Start call timeout timer
  void _startCallTimeout() {
    _cancelCallTimeout();
    _callTimeoutTimer = Timer(_callTimeoutDuration, () {
      if (_callState == CallState.calling || _callState == CallState.ringing) {
        print('⏰ [CallService] Call timeout - ending call');
        onCallError?.call('Call timeout - no answer received');
        endCall();
      }
    });
  }

  /// Cancel call timeout timer
  void _cancelCallTimeout() {
    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = null;
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
          print('📞 [CALL] ICE candidate generated: ${candidate.candidate?.substring(0, 50)}...');
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
            // Cancel timeout when call is connected
            _cancelCallTimeout();
          }
        } else {
          print('⚠️ [CallService] onTrack event received but streams is empty');
        }
      };

      // Handle ICE connection state changes
      _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
        print('📞 [CallService] ICE connection state: $state, current call state: $_callState');
        if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
          print('❌ [CallService] ICE connection failed - attempting to restart ICE');
          // Try to restart ICE before giving up
          _peerConnection?.restartIce();
        } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
          print('⚠️ [CallService] ICE connection disconnected - may reconnect');
        } else if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
                   state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
          print('✅ [CallService] ICE connection established');
        }
      };

      // Handle ICE gathering state
      _peerConnection!.onIceGatheringState = (RTCIceGatheringState state) {
        print('📞 [CallService] ICE gathering state: $state');
      };

      // Handle connection state changes
      _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
        print('📞 [CallService] Connection state: $state, current call state: $_callState');
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          print('⚠️ [CallService] Connection disconnected - may reconnect');
          // Don't end call immediately on disconnect - wait to see if it reconnects
        } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          print('❌ [CallService] Connection failed - checking ICE state before ending');
          // Check ICE state before ending - might be able to recover
          final iceState = _peerConnection?.iceConnectionState;
          print('📞 [CallService] Current ICE state: $iceState');
          
          // Give it a moment to potentially recover
          Future.delayed(const Duration(seconds: 2), () {
            final currentState = _peerConnection?.connectionState;
            if (currentState == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
              print('❌ [CallService] Connection still failed after 2 seconds - ending call');
              onCallError?.call('Connection failed. Please check your network and try again.');
              endCall();
            }
          });
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
            // Cancel timeout when call is connected
            _cancelCallTimeout();
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

