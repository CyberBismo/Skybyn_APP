import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import 'websocket_service.dart';
import 'auth_service.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/notification_params.dart';
import 'package:uuid/uuid.dart';
import 'dart:convert';

enum CallType { audio, video }
enum CallState { idle, calling, ringing, connected, ended }

class CallService {
  static final CallService _instance = CallService._internal();
  factory CallService() => _instance;
  
  // Initialize callkit listeners
  CallService._internal() {
    _setupCallKitListeners();
    // Bind WebSocket reconnection to WebRTC ICE recovery
    _signalingService.onWebSocketConnected = _handleWebSocketReconnected;
  }

  void _setupCallKitListeners() {
    FlutterCallkitIncoming.onEvent.listen((CallEvent? event) {
      if (event == null) return;
      
      switch (event.event) {
        case Event.actionCallAccept:
          // User accepted the call from the native UI
          print('✅ [CallKit] User accepted call');
          if (callState == CallState.ringing) {
            acceptCall();
          }
          break;
        case Event.actionCallDecline:
          // User rejected the call from the native UI
          print('❌ [CallKit] User declined call');
          rejectCall();
          break;
        case Event.actionCallEnded:
          // Call ended from native UI
          print('🛑 [CallKit] User ended call');
          endCall();
          break;
        case Event.actionCallTimeout:
          // Native UI timed out
          print('⏰ [CallKit] Call timed out');
          endCall();
          break;
        default:
          break;
      }
    });
  }

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
  final List<RTCIceCandidate> _remoteIceCandidateQueue = [];


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
  MediaStream? get remoteStream => _remoteStream;
  MediaStream? get localStream => _localStream;
  
  /// Get remote video track directly from receivers (fallback if stream not available)
  Future<MediaStreamTrack?> getRemoteVideoTrack() async {
    if (_peerConnection == null) return null;
    try {
      final transceivers = await _peerConnection!.getTransceivers();
      for (final transceiver in transceivers) {
        if (transceiver.receiver.track?.kind == 'video') {
          return transceiver.receiver.track;
        }
      }
    } catch (e) {
      // Ignore errors
    }
    return null;
  }

  final WebSocketService _signalingService = WebSocketService();
  final AuthService _authService = AuthService();

  /// Fetch WebRTC configuration from backend securely
  Future<Map<String, dynamic>> get _configuration async {
    try {
      final token = await _authService.getStoredUserId();
      if (token == null) throw Exception("User not authenticated.");

      final response = await http.get(
        Uri.parse('${ApiConstants.apiBase}/call/get_ice_servers.php'), // Example endpoint
        headers: {
          'X-API-KEY': ApiConstants.apiKey,
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success' && data['iceServers'] != null) {
          return {
            'iceServers': data['iceServers'],
          };
        }
      }
      debugPrint('⚠️ [Call] Failed to fetch dynamic TURN servers. Falling back to public STUN.');
    } catch (e) {
      debugPrint('⚠️ [Call] Error fetching dynamic TURN servers: $e. Falling back to public STUN.');
    }

    // Fallback to basic STUN servers
    return {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
        {'urls': 'stun:stun2.l.google.com:19302'},
      ],
    };
  }

  /// Recover WebRTC connection after WebSocket reconnect
  Future<void> _handleWebSocketReconnected() async {
    if (_peerConnection == null || _callState != CallState.connected) return;

    debugPrint('🔄 [Call] WebSocket reconnected. Restarting ICE to recover WebRTC media session...');
    try {
      // 1. Force the peer connection to gather new ICE candidates
      await _peerConnection!.restartIce();

      // 2. We only want the original Caller to send the new Offer
      // If we are the callee, we wait for the caller's new offer.
      if (_isCaller && _otherUserId != null && _currentCallId != null) {
        final offer = await _peerConnection!.createOffer();
        await _peerConnection!.setLocalDescription(offer);

        _signalingService.sendCallOffer(
          callId: _currentCallId!,
          targetUserId: _otherUserId!,
          offer: offer.sdp!,
          callType: _currentCallType == CallType.video ? 'video' : 'audio',
        );
      }
    } catch (e) {
      debugPrint('❌ [Call] Failed to recover WebRTC connection: $e');
    }
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
        final tracks = _localStream!.getTracks();
        for (var track in tracks) {
          _peerConnection?.addTrack(track, _localStream!);
        }
      } else {
        throw Exception('Local stream is null');
      }

      // Create and send offer
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);
      // Ensure WebSocket is connected before sending call offer
      if (!_signalingService.isConnected) {
        debugPrint('⚠️ [Call] WebSocket not connected. Attempting to connect...');
        // Try to connect WebSocket
        try {
          await _signalingService.connect().timeout(
            const Duration(seconds: 3), // Reduced timeout to fail faster and try push
          );
          
          // Wait a bit more for connection to be fully established (ping/pong)
          int waitAttempts = 0;
          while (!_signalingService.isConnected && waitAttempts < 5) {
            await Future.delayed(const Duration(milliseconds: 200));
            waitAttempts++;
          }
        } catch (e) {
          debugPrint('⚠️ [Call] WebSocket connection attempt failed: $e');
        }
        
        if (!_signalingService.isConnected) {
          debugPrint('⚠️ [Call] WebSocket still not connected. Proceeding with Push Notification fallback.');
          // We don't throw exception here anymore. 
          // We rely on:
          // 1. Queueing the offer message (WebSocketService queues messages when offline)
          // 2. Sending the Push Notification to wake up the other party
          // 3. Background reconnection attempting to restore link
        }
      }

      // Send offer through WebSocket (will be queued if disconnected)
      _signalingService.sendCallOffer(
        callId: _currentCallId!,
        targetUserId: otherUserId,
        offer: offer.sdp!,
        callType: callType == CallType.video ? 'video' : 'audio',
      );
      
      // Send push notification to wake up recipient (high priority)
      // We do this concurrently with the offer
      _sendCallPushNotification(
        otherUserId,
        _currentCallId!,
        callType,
        offer.sdp!,
      );

      // Start call timeout timer
      _startCallTimeout();
    } catch (e) {
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
    // Foreground service was removed as it was causing issues or no longer needed
    try {
      _currentCallId = callId;
      _otherUserId = fromUserId;
      _isCaller = false;
      _currentCallType = callType == 'video' ? CallType.video : CallType.audio;
      _updateCallState(CallState.ringing);
      // Start call timeout timer
      _startCallTimeout();
      // Get user media
      await _getUserMedia(_currentCallType!);
      // Create peer connection
      await _createPeerConnection();
      // Add local stream to peer connection
      if (_localStream != null) {
        final tracks = _localStream!.getTracks();
        _localStream!.getTracks().forEach((track) {
          _peerConnection?.addTrack(track, _localStream!);
        });
      } else {
        throw Exception('Local stream is null');
      }

      // Set remote description
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(offer, 'offer'),
      );
      
      // Do NOT send answer automatically. Wait for user to accept.
      // The state is already set to ringing above.
      
      // Look up caller details to show in native UI
      String callerName = "Incoming Call";
      String? avatarUrl;
      try {
        final authService = AuthService();
        final userId = await authService.getStoredUserId();
        if (userId != null) {
          final response = await http.get(
            Uri.parse('${ApiConstants.apiBase}/user/get_profile.php?user_id=$fromUserId'),
            headers: {
              'X-API-KEY': ApiConstants.apiKey,
              'Authorization': 'Bearer $userId', // Some endpoints expect userId here
            },
          );
          if (response.statusCode == 200) {
             final data = jsonDecode(response.body);
             if (data['status'] == 'success') {
                 callerName = data['data']['nickname']?.isNotEmpty == true ? data['data']['nickname'] : data['data']['username'];
                 avatarUrl = data['data']['avatar'];
                 if (avatarUrl != null && avatarUrl.isNotEmpty) {
                    avatarUrl = UrlHelper.convertUrl(avatarUrl);
                 }
             }
          }
        }
      } catch (e) {
        print("Error fetching caller info for CallKit: $e");
      }

      // Show native incoming call UI
      final params = CallKitParams(
        id: callId,
        nameCaller: callerName,
        appName: 'Skybyn',
        avatar: avatarUrl ?? '',
        handle: callType == 'video' ? 'Video Call' : 'Audio Call',
        type: callType == 'video' ? 1 : 0, 
        duration: 45000, 
        textAccept: 'Accept',
        textDecline: 'Decline',
        missedCallNotification: const NotificationParams(
          showNotification: true,
          isShowCallback: true,
          subtitle: 'Missed call',
          callbackText: 'Call back',
        ),
        extra: <String, dynamic>{'userId': fromUserId},
        headers: <String, dynamic>{'apiKey': 'xxx', 'apiSecret': 'xxx'},
        android: const AndroidParams(
          isCustomNotification: true,
          isShowLogo: false,
          ringtonePath: 'system_ringtone_default',
          backgroundColor: '#0955fa',
          backgroundUrl: 'assets/test.png',
          actionColor: '#4CAF50',
          textColor: '#ffffff',
          incomingCallNotificationChannelName: "Incoming Call",
          missedCallNotificationChannelName: "Missed Call",
          isShowCallID: false
        ),
        ios: const IOSParams(
          iconName: 'CallKitLogo',
          handleType: 'generic',
          supportsVideo: true,
          maximumCallGroups: 2,
          maximumCallsPerCallGroup: 1,
          audioSessionMode: 'default',
          audioSessionActive: true,
          audioSessionPreferredSampleRate: 44100.0,
          audioSessionPreferredIOBufferDuration: 0.005,
          supportsDTMF: true,
          supportsHolding: true,
          supportsGrouping: false,
          supportsUngrouping: false,
          ringtonePath: 'system_ringtone_default'
        ),
      );
      await FlutterCallkitIncoming.showCallkitIncoming(params);
      
      
    } catch (e) {
      _updateCallState(CallState.ended);
      final errorMsg = 'Failed to handle incoming call: $e';
      onCallError?.call(errorMsg);
      // Re-throw to allow caller to handle
      rethrow;
    }
  }

  /// Handle incoming call answer
  Future<void> handleIncomingAnswer(String answer) async {
    try {
      if (_peerConnection == null) {
        debugPrint('⚠️ [Call] Received answer but peer connection is null');
        return;
      }
      debugPrint('📞 [Call] Setting remote description (answer)');
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(answer, 'answer'),
      );
      
      // Log current ICE connection state after setting answer
      final iceState = _peerConnection?.iceConnectionState;
      debugPrint('🧊 [Call] ICE State after answer: $iceState');
    } catch (e) {
      debugPrint('❌ [Call] Error handling answer: $e');
      onCallError?.call('Failed to handle answer: $e');
    }
  }

  /// Handle ICE candidate
  Future<void> handleIceCandidate({
    required String candidate,
    required String sdpMid,
    required int sdpMLineIndex,
  }) async {
    final iceCandidate = RTCIceCandidate(candidate, sdpMid, sdpMLineIndex);
    
    try {
      // Only add candidate if peer connection exists and is in a valid state
      if (_peerConnection != null && 
          _peerConnection!.signalingState != RTCSignalingState.RTCSignalingStateClosed) {
        // debugPrint('🧊 [Call] Adding ICE candidate');
        await _peerConnection!.addCandidate(iceCandidate);
      } else {
        // Queue candidate until peer connection is ready
        debugPrint('🧊 [Call] Queueing ICE candidate (connection not ready)');
        _remoteIceCandidateQueue.add(iceCandidate);
      }
    } catch (e) {
      // Don't fail the call on ICE candidate errors
    }
  }

  /// Accept incoming call
  Future<void> acceptCall() async {
    if (_callState == CallState.ringing) {
      try {
        if (_peerConnection == null) {
          debugPrint('⚠️ [Call] Cannot accept call - peer connection is null');
          return;
        }
        
        debugPrint('📞 [Call] Accepting call $_currentCallId');
        
        // Ensure CallKit considers the call answered internally
        if (_currentCallId != null && !_isCaller) {
           await FlutterCallkitIncoming.setCallConnected(_currentCallId!);
        }

        // Create and send answer
        final answer = await _peerConnection!.createAnswer({
          'offerToReceiveAudio': true,
          'offerToReceiveVideo': _currentCallType == CallType.video,
        });
        await _peerConnection!.setLocalDescription(answer);
        
        // Send answer through WebSocket
        if (_currentCallId != null && _otherUserId != null) {
           _signalingService.sendCallAnswer(
            callId: _currentCallId!,
            targetUserId: _otherUserId!,
            answer: answer.sdp!,
          );
        }
        
        // Update state to "calling" (connecting)
        _updateCallState(CallState.calling);
        _cancelCallTimeout();
      } catch (e) {
        debugPrint('❌ [Call] Error accepting call: $e');
        onCallError?.call('Failed to accept call: $e');
        endCall();
      }
    } else {
      debugPrint('⚠️ [Call] Cannot accept call - state is $_callState (expected ringing)');
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
      // Foreground service was removed
      
      // Cancel timeout timer
      _cancelCallTimeout();

      if (_currentCallId != null && _otherUserId != null) {
        _signalingService.sendCallEnd(
          callId: _currentCallId!,
          targetUserId: _otherUserId!,
        );
      }

      // End call in CallKit natively
      if (_currentCallId != null) {
          await FlutterCallkitIncoming.endCall(_currentCallId!);
          // Alternatively ending all calls to be safe
          await FlutterCallkitIncoming.endAllCalls();
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
    } catch (e) {
    }
  }

  void _startCallTimeout() {
    _cancelCallTimeout();
    _callTimeoutTimer = Timer(_callTimeoutDuration, () {
      if (_callState == CallState.calling || _callState == CallState.ringing) {
        final timeoutMsg = _callState == CallState.ringing
            ? 'Call timeout - no answer received'
            : 'Call timeout - connection not established';
        onCallError?.call(timeoutMsg);
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
      // Dispose any existing local stream first
      if (_localStream != null) {
        await _localStream!.dispose();
        _localStream = null;
      }
      
      final constraints = <String, dynamic>{
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': callType == CallType.video
            ? {
                'facingMode': 'user',
                'width': {'ideal': 1280, 'min': 640},
                'height': {'ideal': 720, 'min': 480},
                'frameRate': {'ideal': 30, 'min': 15},
              }
            : false,
      };

      _localStream = await navigator.mediaDevices.getUserMedia(constraints);
      
      // Verify we got the expected tracks
      if (_localStream == null) {
        throw Exception('Failed to get media stream - stream is null');
      }
      
      final audioTracks = _localStream!.getAudioTracks();
      if (audioTracks.isEmpty) {
        throw Exception('Failed to get audio track');
      }
      
      if (callType == CallType.video) {
        final videoTracks = _localStream!.getVideoTracks();
        if (videoTracks.isEmpty) {
          throw Exception('Failed to get video track');
        }
      }
      
      onLocalStream?.call(_localStream);
    } catch (e) {
      // Clean up on error
      if (_localStream != null) {
        await _localStream!.dispose();
        _localStream = null;
      }
      onCallError?.call('Failed to access camera/microphone: $e');
      rethrow;
    }
  }

  /// Create peer connection
  Future<void> _createPeerConnection() async {
    try {
      final config = await _configuration;
      _peerConnection = await createPeerConnection(config);
    debugPrint('📞 [Call] Peer connection created');

    // Drain queued remote ICE candidates
    if (_remoteIceCandidateQueue.isNotEmpty) {
      debugPrint('🧊 [Call] Draining ${_remoteIceCandidateQueue.length} queued ICE candidates');
      for (final candidate in _remoteIceCandidateQueue) {
        await _peerConnection!.addCandidate(candidate);
      }
      _remoteIceCandidateQueue.clear();
    }

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
        // CRITICAL: Always try to get the stream from the event
        // In Flutter WebRTC, onTrack should provide streams, but handle all cases
        MediaStream? streamToUse;
        
        // First priority: Get stream from event.streams
        if (event.streams.isNotEmpty) {
          streamToUse = event.streams[0];
        }
        
        // If we have a stream, process it immediately
        if (streamToUse != null) {
          _remoteStream = streamToUse;
          
          // Update to connected IMMEDIATELY when remote stream is received
          // This is the most reliable indicator that the call is working
          // Even if connection state reports failure, if we have media, the call works
          if (_callState != CallState.connected && _callState != CallState.ended) {
            _updateCallState(CallState.connected);
            // Cancel timeout when call is connected
            _cancelCallTimeout();
          }
          
          // Notify listeners about the remote stream IMMEDIATELY
          onRemoteStream?.call(_remoteStream);
          
          // Verify we have the expected tracks
          final videoTracks = _remoteStream!.getVideoTracks();
          final audioTracks = _remoteStream!.getAudioTracks();
          
          // Set up track event listeners for better error handling
          for (final track in videoTracks) {
            track.onEnded = () {
              // Video track ended - might indicate connection issue
              if (_callState == CallState.connected) {
                // Try to recover or notify user
              }
            };
          }
          
          for (final track in audioTracks) {
            track.onEnded = () {
              // Audio track ended - critical issue
              if (_callState == CallState.connected) {
                onCallError?.call('Audio connection lost. Please check your network.');
                endCall();
              }
            };
          }
        } else if (event.track != null) {
          debugPrint('⚠️ [Call] onTrack fired but no streams available in event.streams. Waiting for later event.');
        }
      
      };

      // Handle ICE connection state changes
      _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
        // If we already have a remote stream, don't fail immediately on ICE issues
        // The stream might still work even if ICE state is problematic
        final hasRemoteStream = _remoteStream != null;
        
        if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
          // If we have a remote stream, the connection might still work
          // Only fail if we don't have a stream yet
          if (!hasRemoteStream) {
            // Try to restart ICE before giving up
            try {
              _peerConnection?.restartIce();
              // Give it a moment to recover after ICE restart
              Future.delayed(const Duration(seconds: 5), () {
                final currentIceState = _peerConnection?.iceConnectionState;
                if (currentIceState == RTCIceConnectionState.RTCIceConnectionStateFailed &&
                    _remoteStream == null) {
                  // Still failed after restart and no stream - end the call
                  onCallError?.call('Connection failed. Please check your network and try again.');
                  endCall();
                }
              });
            } catch (e) {
              // ICE restart failed - only end if no stream
              if (!hasRemoteStream) {
                onCallError?.call('Connection failed. Please check your network and try again.');
                endCall();
              }
            }
          }
          // If we have a stream, just log the ICE failure but don't end the call
          // The media connection might still work
        } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
          // Wait a bit to see if it reconnects
          Future.delayed(const Duration(seconds: 5), () {
            final currentIceState = _peerConnection?.iceConnectionState;
            if (currentIceState == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
                currentIceState == RTCIceConnectionState.RTCIceConnectionStateFailed) {
              // Still disconnected - try to recover or end call
              if (_callState == CallState.connected) {
                // Was connected, now disconnected - try ICE restart
                try {
                  _peerConnection?.restartIce();
                } catch (e) {
                  onCallError?.call('Connection lost. Please check your network.');
                  endCall();
                }
              }
            }
          });
        } else if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
                   state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
          // ICE connection established successfully
          // State will be updated to connected when remote stream is received (onTrack)
        }
      };

      // Handle ICE gathering state
      _peerConnection!.onIceGatheringState = (RTCIceGatheringState state) {
      };

      // Handle connection state changes
      _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
        final hasRemoteStream = _remoteStream != null;
        
        if (hasRemoteStream && _callState != CallState.connected && _callState != CallState.ended) {
          _updateCallState(CallState.connected);
          _cancelCallTimeout();
        }
        
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          debugPrint('⚠️ [Call] Peer connection disconnected');
        } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          if (!hasRemoteStream) {
            onCallError?.call('Connection failed. Please check your network and try again.');
            endCall();
          }
        } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          if (_callState != CallState.ended && _callState != CallState.idle) {
            endCall();
          }
        } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          if (_callState != CallState.connected && _callState != CallState.ended) {
            _updateCallState(CallState.connected);
            _cancelCallTimeout();
          }
        }
      };
    } catch (e) {
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
        videoTrack.enabled = !videoTrack.enabled;
      }
    }
  }

  /// Toggle microphone
  Future<void> toggleMicrophone() async {
    if (_localStream != null) {
      final audioTrack = _localStream!.getAudioTracks().firstOrNull;
      if (audioTrack != null) {
        audioTrack.enabled = !audioTrack.enabled;
      }
    }
  }

  /// Switch camera (front/back)
  Future<void> switchCamera() async {
    if (_localStream != null && _currentCallType == CallType.video) {
      final videoTrack = _localStream!.getVideoTracks().firstOrNull;
      if (videoTrack != null) {
        await Helper.switchCamera(videoTrack);
      }
    }
  }

  /// Send high-priority push notification to recipient to wake up the app
  Future<void> _sendCallPushNotification(
    String targetUserId,
    String callId,
    CallType callType,
    String offer,
  ) async {
    try {
      final currentUserId = await _authService.getStoredUserId();
      if (currentUserId == null) return;

      final response = await http.post(
        Uri.parse('${ApiConstants.apiBase}/call/send_call_notification.php'),
        headers: {'X-API-KEY': ApiConstants.apiKey},
        body: {
          'user': targetUserId,
          'from': currentUserId,
          'callId': callId,
          'callType': callType == CallType.video ? 'video' : 'audio',
          'offer': offer,
        },
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        debugPrint('❌ [Call] Failed to send push notification: ${response.statusCode}');
      } else {
        debugPrint('✅ [Call] Push notification sent to recipient');
      }
    } catch (e) {
      debugPrint('❌ [Call] Error sending push notification: $e');
    }
  }
}

