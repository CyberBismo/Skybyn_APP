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
  Timer? _connectionCheckTimer;
  static const Duration _callTimeoutDuration = Duration(seconds: 45);
  static const Duration _connectionCheckInterval = Duration(seconds: 1);

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
        // Try to connect WebSocket
        await _signalingService.connect().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
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
      } else {
      }
      // Send offer through WebSocket
      _signalingService.sendCallOffer(
        callId: _currentCallId!,
        targetUserId: otherUserId,
        offer: offer.sdp!,
        callType: callType == CallType.video ? 'video' : 'audio',
      );
      // Start call timeout timer
      _startCallTimeout();
      // Start connection check timer to ensure state updates when media arrives
      _startConnectionCheck();
    } catch (e) {
      _stopConnectionCheck();
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
      // Start call timeout timer
      _startCallTimeout();
      // Start connection check timer to ensure state updates when media arrives
      _startConnectionCheck();
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
      // Create and send answer
      final answer = await _peerConnection!.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': _currentCallType == CallType.video,
      });
      await _peerConnection!.setLocalDescription(answer);
      // Verify we have the expected tracks
      if (_localStream != null) {
        final videoTracks = _localStream!.getVideoTracks();
        final audioTracks = _localStream!.getAudioTracks();
      }

      // Send answer through WebSocket
      if (!_signalingService.isConnected) {
        throw Exception('WebSocket not connected - cannot send answer');
      }
      _signalingService.sendCallAnswer(
        callId: callId,
        targetUserId: fromUserId,
        answer: answer.sdp!,
      );
      // Update state to "calling" to indicate we've answered and are connecting
      // This prevents showing the answer button again in CallScreen
      // The state will be updated to connected when remote stream is received
      _updateCallState(CallState.calling);
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
        return;
      }
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(answer, 'answer'),
      );
      
      // Log current ICE connection state after setting answer
      final iceState = _peerConnection?.iceConnectionState;
      final connectionState = _peerConnection?.connectionState;
    } catch (e) {
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
      // Only add candidate if peer connection exists and is in a valid state
      if (_peerConnection != null && 
          _peerConnection!.signalingState != RTCSignalingState.RTCSignalingStateClosed) {
        await _peerConnection!.addCandidate(
          RTCIceCandidate(candidate, sdpMid, sdpMLineIndex),
        );
      }
    } catch (e) {
      // Don't fail the call on ICE candidate errors - they're often non-critical
      // Some candidates may be invalid or arrive after connection is established
      // This is normal WebRTC behavior
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
      // Stop connection check timer
      _stopConnectionCheck();

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
    } catch (e) {
    }
  }

  /// Start call timeout timer
  void _startConnectionCheck() {
    _stopConnectionCheck();
    _connectionCheckTimer = Timer.periodic(_connectionCheckInterval, (timer) {
      // Try to get remote stream from peer connection if we don't have it yet
      if (_remoteStream == null && _peerConnection != null) {
        // Check transceivers for remote streams (async, so use then)
        _peerConnection!.getTransceivers().then((transceivers) {
          try {
            List<MediaStreamTrack> videoTracks = [];
            List<MediaStreamTrack> audioTracks = [];
            
            for (final transceiver in transceivers) {
              final receiver = transceiver.receiver!;
              if (receiver.track != null) {
                final track = receiver.track!;
                if (track.kind == 'video') {
                  videoTracks.add(track);
                } else if (track.kind == 'audio') {
                  audioTracks.add(track);
                }
              }
                        }
            
            // If we have tracks but no stream, try to get the stream
            // The issue is that onTrack might have fired with empty event.streams
            // We need to wait for onTrack to fire again with the stream, or check if
            // the stream is available through another mechanism
            if ((videoTracks.isNotEmpty || audioTracks.isNotEmpty) && _remoteStream == null) {
              // Tracks exist but no stream - this means onTrack might not have fired
              // or event.streams was empty when it did fire
              // Update state to connected since we have tracks
              if (_callState != CallState.connected && _callState != CallState.ended) {
                _updateCallState(CallState.connected);
                _cancelCallTimeout();
              }
              
              // Keep checking - onTrack might fire again with the stream
              // The connection check timer will continue to run and check periodically
            }
          } catch (e) {
            // Ignore errors when checking transceivers
          }
        }).catchError((e) {
          // Ignore errors when getting transceivers
        });
      }
      
      // Periodically check if we have a remote stream but state isn't connected
      // This is a fallback in case onTrack doesn't fire or there's a timing issue
      if (_remoteStream != null && 
          _callState != CallState.connected && 
          _callState != CallState.ended &&
          _callState != CallState.idle) {
        _updateCallState(CallState.connected);
        _cancelCallTimeout();
        // Keep checking for a bit to ensure state stays updated
      } else if (_callState == CallState.ended || _callState == CallState.idle) {
        // Stop checking if call has ended
        _stopConnectionCheck();
      }
    });
  }

  void _stopConnectionCheck() {
    _connectionCheckTimer?.cancel();
    _connectionCheckTimer = null;
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
        } else        // Track exists but no stream in event.streams
        // This can happen - onTrack might fire multiple times
        // Wait a bit and check if stream becomes available
        // Also check receivers periodically to see if we can get the stream
        Future.delayed(const Duration(milliseconds: 100), () {
          if (_remoteStream == null && _peerConnection != null) {
            // Check if onTrack fired again with a stream
            // If not, check receivers to see if tracks exist
            _peerConnection!.getTransceivers().then((transceivers) {
              bool hasVideoTrack = false;
              bool hasAudioTrack = false;
              for (final transceiver in transceivers) {
                if (transceiver.receiver?.track != null) {
                  if (transceiver.receiver!.track!.kind == 'video') {
                    hasVideoTrack = true;
                  } else if (transceiver.receiver!.track!.kind == 'audio') {
                    hasAudioTrack = true;
                  }
                }
              }
              // If we have tracks but no stream, update state to connected
              // The connection check timer will continue to look for streams
              if ((hasVideoTrack || hasAudioTrack) && _remoteStream == null && 
                  _callState != CallState.connected && _callState != CallState.ended) {
                _updateCallState(CallState.connected);
                _cancelCallTimeout();
              }
            });
          }
        });
      
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
        // Check if we have a remote stream - if so, connection might still work
        // Use a delayed check to ensure onTrack has had time to set the stream
        Future.delayed(const Duration(milliseconds: 500), () {
          final hasRemoteStream = _remoteStream != null;
          
          // If we have a remote stream, update state to CONNECTED regardless of connection state
          // This ensures the UI shows the call as connected when media is flowing
          if (hasRemoteStream && _callState != CallState.connected && _callState != CallState.ended) {
            _updateCallState(CallState.connected);
            _cancelCallTimeout();
          }
          
          if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
            // Don't end call immediately on disconnect - wait to see if it reconnects
            // Especially if we have a stream, it might just be a temporary disconnection
          } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnecting) {
            // If we have a remote stream while connecting, we're actually connected
            // Update state to CONNECTED to show the UI correctly
            if (hasRemoteStream && _callState != CallState.connected && _callState != CallState.ended) {
              _updateCallState(CallState.connected);
              _cancelCallTimeout();
            }
          } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
            // Only fail if we don't have a remote stream yet
            // If we have a stream, the media connection might still work
            if (!hasRemoteStream) {
              // Check ICE state before ending - might be able to recover
              final iceState = _peerConnection?.iceConnectionState;
              // Give it more time to potentially recover and receive stream
              Future.delayed(const Duration(seconds: 5), () {
                final currentState = _peerConnection?.connectionState;
                // Only end if still failed AND no remote stream
                if (currentState == RTCPeerConnectionState.RTCPeerConnectionStateFailed &&
                    _remoteStream == null) {
                  onCallError?.call('Connection failed. Please check your network and try again.');
                  endCall();
                }
              });
            }
            // If we have a stream, don't end the call - media might still work
            // The connection state can be misleading - if media is flowing, keep the call
          } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
            // Only end call if it wasn't already ended AND we don't have a remote stream
            // If we have a remote stream, the call might still be working
            // The CLOSED state can sometimes be triggered prematurely or incorrectly
            if (_callState != CallState.ended && _callState != CallState.idle) {
              // Check if we have a remote stream - if so, don't end immediately
              // Give it a moment to see if the stream is still active
              if (!hasRemoteStream) {
                // No remote stream - safe to end
                endCall();
              } else {
                // We have a remote stream - check if tracks exist and are enabled
                final videoTracks = _remoteStream?.getVideoTracks() ?? [];
                final audioTracks = _remoteStream?.getAudioTracks() ?? [];
                final hasTracks = videoTracks.isNotEmpty || audioTracks.isNotEmpty;
                
                if (!hasTracks) {
                  // No tracks at all - safe to end
                  endCall();
                } else {
                  // We have tracks - wait a bit to see if they're still working
                  // The CLOSED state might be a false positive
                  Future.delayed(const Duration(seconds: 2), () {
                    // Check again - if call is still in connected state, don't end
                    if (_callState == CallState.connected && _remoteStream != null) {
                      // Call is still connected and we have a stream - don't end
                      // The CLOSED state was likely a false positive
                    } else if (_callState != CallState.ended && _callState != CallState.idle) {
                      // Call state changed or stream is gone - safe to end now
                      endCall();
                    }
                  });
                }
              }
            }
          } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
            // Also update call state to connected when peer connection is established
            // This is a backup in case onTrack doesn't fire (e.g., for audio-only calls)
            if (_callState != CallState.connected && _callState != CallState.ended) {
              _updateCallState(CallState.connected);
              // Cancel timeout when call is connected
              _cancelCallTimeout();
            }
          }
        });
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
}

