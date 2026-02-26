import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../models/friend.dart';
import '../services/call_service.dart';
import '../config/constants.dart';

class CallScreen extends StatefulWidget {
  final Friend friend;
  final CallType callType;
  final bool isIncoming;
  final bool autoAccept;
  final String? offer;
  final String? callId;

  const CallScreen({
    super.key,
    required this.friend,
    required this.callType,
    this.isIncoming = false,
    this.autoAccept = false,
    this.offer,
    this.callId,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final CallService _callService = CallService();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _isMuted = false;
  bool _isCameraOff = false;
  bool _isLocalVideoInitialized = false;
  bool _isRemoteVideoInitialized = false;
  bool _isNavigatingBack = false; // Prevent multiple navigation attempts
  MediaStream? _lastRemoteStream; // Store reference to remote stream
  bool _shouldAutoAccept = false;

  @override
  void initState() {
    super.initState();
    _shouldAutoAccept = widget.autoAccept;
    _isCameraOff = widget.callType == CallType.audio;
    _initializeRenderers();
    _setupCallService();
    
    if (!widget.isIncoming) {
      // Start outgoing call
      _startOutgoingCall();
    } else {
      // For incoming calls, handle the offer if provided directly via arguments
      if (widget.offer != null && widget.callId != null) {
        print('[SKYBYN] 📞 [CallScreen] Initializing call from provided offer/callId');
        _callService.handleIncomingOffer(
          callId: widget.callId!,
          fromUserId: widget.friend.id,
          offer: widget.offer!,
          callType: widget.callType == CallType.video ? 'video' : 'audio',
        ).then((_) {
            _checkAndSetExistingStreams();
        }).catchError((e) {
            print('[SKYBYN] ❌ [CallScreen] Error handling provided offer: $e');
        });
      }

      // Check if local/remote streams are already available in service
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkAndSetExistingStreams();
      });
    }
    

    
    // Check for auto-accept if already ringing
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _shouldAutoAccept && _callService.callState == CallState.ringing) {
        _shouldAutoAccept = false;
        _acceptCall();
      }
    });
  }
  
  void _checkAndSetExistingStreams() {
    if (!mounted) return;
    
    // Check for existing local stream from service
    final localStream = _callService.localStream;
    if (localStream != null && _isLocalVideoInitialized) {
      if (_localRenderer.srcObject != localStream) {
        _localRenderer.srcObject = localStream;
        setState(() {});
      }
    }
    
    // Check for existing remote stream from service
    final remoteStream = _callService.remoteStream;
    if (remoteStream != null && _isRemoteVideoInitialized) {
      _lastRemoteStream = remoteStream;
      if (_remoteRenderer.srcObject != remoteStream) {
        _remoteRenderer.srcObject = remoteStream;
        setState(() {});
      }
    }
  }

  Future<void> _initializeRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    setState(() {
      _isLocalVideoInitialized = true;
      _isRemoteVideoInitialized = true;
    });
  }

  void _setupCallService() {
    _callService.onLocalStream = (stream) {
      if (stream != null && _isLocalVideoInitialized) {
        _localRenderer.srcObject = stream;
        setState(() {});
      }
    };

    _callService.onRemoteStream = (stream) {
      if (!mounted) return;
      _lastRemoteStream = stream;
      
      if (stream != null) {
        if (_isRemoteVideoInitialized) {
          final videoTracks = stream.getVideoTracks();
          if (videoTracks.isNotEmpty) {
            for (final track in videoTracks) {
              track.enabled = true;
            }
          }
          _remoteRenderer.srcObject = stream;
          setState(() {});
        }
      } else {
        if (_isRemoteVideoInitialized) {
          _remoteRenderer.srcObject = null;
          setState(() {});
        }
      }
    };

    _callService.onCallStateChanged = (state) {
      if (mounted) {
        // Always check for remote stream when state changes, not just on connected
        // This ensures we catch the stream even if state updates are delayed
        final serviceRemoteStream = _callService.remoteStream;
        if (serviceRemoteStream != null) {
          if (_lastRemoteStream != serviceRemoteStream) {
            _lastRemoteStream = serviceRemoteStream;
          }
          if (_isRemoteVideoInitialized && _remoteRenderer.srcObject != serviceRemoteStream) {
            _remoteRenderer.srcObject = serviceRemoteStream;
            setState(() {});
          }
        } else if (_lastRemoteStream != null && _isRemoteVideoInitialized) {
          // Ensure stored stream is set on renderer
          if (_remoteRenderer.srcObject != _lastRemoteStream) {
            _remoteRenderer.srcObject = _lastRemoteStream;
            setState(() {});
          }
        }
        setState(() {});
        
        // Auto-accept if requested and call is ringing
        if (state == CallState.ringing && _shouldAutoAccept) {
          _shouldAutoAccept = false;
          _acceptCall();
        }
        
        if ((state == CallState.ended || state == CallState.idle) && !_isNavigatingBack) {
          _isNavigatingBack = true;
          
          // Use post-frame callback to ensure we have a fresh context
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              // Use a small delay to ensure state updates are complete
              Future.delayed(const Duration(milliseconds: 200), () {
                if (mounted) {
                  // Get the current route to check navigation stack
                  final currentRoute = ModalRoute.of(context);
                  if (currentRoute != null && currentRoute.isCurrent) {
                    // Try to get the navigator that pushed this screen
                    // Use rootNavigator: false first to get the navigator that's managing this route
                    final navigator = Navigator.of(context, rootNavigator: false);
                    
                    // Check if we can pop from the non-root navigator
                    if (navigator.canPop()) {
                      // Pop once - this should take us back to the screen that pushed CallScreen
                      navigator.pop();
                    } else {
                      // Can't pop from non-root navigator
                      // This could mean:
                      // 1. We're at the root (e.g., home screen) - in this case, we should still pop
                      // 2. The navigation stack is empty - shouldn't happen, but handle gracefully
                      
                      // Check if we can pop from root navigator
                      // This handles the case where CallScreen was pushed from home screen
                      final rootNavigator = Navigator.of(context, rootNavigator: true);
                      if (rootNavigator.canPop()) {
                        // Pop from root navigator - this will take us back to home screen
                        // which is correct if we answered the call from home screen
                        rootNavigator.pop();
                      } else {
                        // Can't pop from either navigator - shouldn't happen
                        // Reset flag so user can manually navigate back
                        _isNavigatingBack = false;
                      }
                    }
                  } else {
                    // Route is not current, reset flag
                    _isNavigatingBack = false;
                  }
                }
              });
            }
          });
        }
      }
    };

    _callService.onCallError = (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error),
            duration: const Duration(seconds: 5),
            backgroundColor: Colors.red,
          ),
        );
        // Don't auto-close on error - let user see the error message
        // The call state change handler will close when state becomes ended/idle
      }
    };
  }

  Future<void> _startOutgoingCall() async {
    try {
      await _callService.startCall(
        widget.friend.id,
        widget.callType,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start call: $e')),
        );
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _acceptCall() async {
    await _callService.acceptCall();
  }

  Future<void> _rejectCall() async {
    await _callService.rejectCall();
  }

  Future<void> _endCall() async {
    await _callService.endCall();
  }

  Future<void> _toggleMute() async {
    await _callService.toggleMicrophone();
    setState(() {
      _isMuted = !_isMuted;
    });
  }

  Future<void> _toggleCamera() async {
    await _callService.toggleCamera();
    setState(() {
      _isCameraOff = !_isCameraOff;
    });
  }

  Future<void> _switchCamera() async {
    if (widget.callType == CallType.video) {
      await _callService.switchCamera();
    }
  }

  String _getCallStateText() {
    switch (_callService.callState) {
      case CallState.idle:
        return 'Idle';
      case CallState.calling:
        return widget.isIncoming ? 'Connecting...' : 'Calling...';
      case CallState.ringing:
        return widget.isIncoming ? 'Incoming call' : 'Ringing...';
      case CallState.connected:
        return 'Connected';
      case CallState.ended:
        return 'Call ended';
    }
  }
  
  Color _getCallStateColor() {
    switch (_callService.callState) {
      case CallState.idle:
        return Colors.grey;
      case CallState.calling:
      case CallState.ringing:
        return Colors.orange;
      case CallState.connected:
        return Colors.green;
      case CallState.ended:
        return Colors.red;
    }
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isVideoCall = widget.callType == CallType.video;
    final callState = _callService.callState;
    // Consider connected if state is connected OR if we have a remote stream
    // This handles cases where the state update hasn't happened yet but media is flowing
    final hasRemoteStream = _remoteRenderer.srcObject != null || _lastRemoteStream != null;
    final isConnected = callState == CallState.connected || 
                       (hasRemoteStream && callState != CallState.ended && callState != CallState.idle);
    
    // Ensure local stream is set on renderer - check service directly
    if (isVideoCall && _isLocalVideoInitialized) {
      final serviceLocalStream = _callService.localStream;
      if (serviceLocalStream != null && _localRenderer.srcObject != serviceLocalStream) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _localRenderer.srcObject = serviceLocalStream;
            setState(() {});
          }
        });
      }
    }
    
    // Ensure remote stream is set on renderer - check multiple sources
    // This runs on every build to catch streams that arrive at any time
    if (isVideoCall && _isRemoteVideoInitialized) {
      // First, try to get stream from service directly
      final serviceRemoteStream = _callService.remoteStream;
      if (serviceRemoteStream != null) {
        // Update stored reference
        if (_lastRemoteStream != serviceRemoteStream) {
          _lastRemoteStream = serviceRemoteStream;
        }
        // Always ensure it's set on renderer - even if it seems to be set
        if (_remoteRenderer.srcObject != serviceRemoteStream) {
          // Set immediately if possible
          _remoteRenderer.srcObject = serviceRemoteStream;
          // Also set in post-frame callback as backup
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              if (_remoteRenderer.srcObject != serviceRemoteStream) {
                _remoteRenderer.srcObject = serviceRemoteStream;
              }
              setState(() {});
            }
          });
        }
      } else if (_lastRemoteStream != null) {
        // Stream is stored - ensure it's set on renderer
        if (_remoteRenderer.srcObject != _lastRemoteStream) {
          _remoteRenderer.srcObject = _lastRemoteStream;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _lastRemoteStream != null) {
              if (_remoteRenderer.srcObject != _lastRemoteStream) {
                _remoteRenderer.srcObject = _lastRemoteStream;
              }
              setState(() {});
            }
          });
        }
      } else {
        // No stream available - check if renderer already has a stream set by the plugin
        // Sometimes the plugin sets the stream directly on the renderer before onTrack fires
        if (_isRemoteVideoInitialized && _remoteRenderer.srcObject != null) {
          // Renderer has a stream! This means the plugin set it directly
          // Store it and notify the service
          if (_lastRemoteStream != _remoteRenderer.srcObject) {
            _lastRemoteStream = _remoteRenderer.srcObject;
            // Update service's remote stream reference if possible
            // Note: We can't directly set _callService._remoteStream, but we can
            // at least use the stream from the renderer
          }
        } else if (callState == CallState.connected || callState == CallState.ringing) {
          // Check if we can get tracks directly as a fallback
          _callService.getRemoteVideoTrack().then((track) {
            if (mounted && track != null && _remoteRenderer.srcObject == null) {
              // We have a track but no stream - this means onTrack didn't provide a stream
              // Unfortunately, Flutter WebRTC requires streams for renderers, not just tracks
              // So we'll wait for the stream to arrive via onTrack
              // But we can at least verify the track exists
            }
          });
        }
      }
    }

    return WillPopScope(
      onWillPop: () async {
        // If call is connected, end it first
        if (callState == CallState.connected) {
          await _endCall();
          // Don't pop immediately - let the state change handler do it
          return false;
        }
        // For other states (calling, ringing, ended), allow back button
        // But prevent multiple navigation attempts
        if (!_isNavigatingBack) {
          _isNavigatingBack = true;
          return true;
        }
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              // Remote video (full screen for video calls)
              // Show remote video if renderer is initialized and has a stream
              // Also check if we have a stored stream reference
              if (isVideoCall && 
                  _isRemoteVideoInitialized && 
                  (_remoteRenderer.srcObject != null || _lastRemoteStream != null))
                Positioned.fill(
                  child: Builder(
                    builder: (context) {
                      // Ensure stream is set on renderer if we have it stored
                      final streamToUse = _remoteRenderer.srcObject ?? _lastRemoteStream;
                      if (streamToUse != null && _remoteRenderer.srcObject != streamToUse) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) {
                            _remoteRenderer.srcObject = streamToUse;
                            setState(() {});
                          }
                        });
                      }
                      
                      // Verify stream has video tracks before displaying
                      final currentStream = _remoteRenderer.srcObject ?? streamToUse;
                      if (currentStream != null) {
                        final videoTracks = currentStream.getVideoTracks();
                        // If stream has no video tracks yet, still try to display
                        // Tracks might be added asynchronously
                        if (videoTracks.isEmpty && _remoteRenderer.srcObject == null) {
                          return Container(
                            color: Colors.black,
                            child: const Center(
                              child: Text(
                                'Waiting for video...',
                                style: TextStyle(color: Colors.white70),
                              ),
                            ),
                          );
                        }
                      } else if (streamToUse == null) {
                        // No stream at all - show loading
                        return Container(
                          color: Colors.black,
                          child: const Center(
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                        );
                      }
                      
                      // Ensure we have a stream on the renderer before displaying
                      if (_remoteRenderer.srcObject == null && streamToUse != null) {
                        // Stream is available but not set - set it in post-frame callback
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) {
                            _remoteRenderer.srcObject = streamToUse;
                            setState(() {});
                          }
                        });
                        // Return placeholder while setting up
                        return Container(
                          color: Colors.black,
                          child: const Center(
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                        );
                      }
                      
                      return RTCVideoView(
                        _remoteRenderer,
                        mirror: false,
                        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      );
                    },
                  ),
                )
              else if (isVideoCall)
                Positioned.fill(
                  child: Container(
                    color: Colors.black,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _getCallStateText(),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Local video preview (small overlay for video calls)
              // Show local video whenever we have a local stream, not just when connected
              // This ensures local video shows during ringing state for incoming calls
              if (isVideoCall && _isLocalVideoInitialized && _localRenderer.srcObject != null)
                Positioned(
                  top: 20,
                  right: 20,
                  width: 120,
                  height: 160,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: RTCVideoView(
                        _localRenderer,
                        mirror: true,
                        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      ),
                    ),
                  ),
                ),

              // Caller info overlay (when not connected or audio call)
              if (!isConnected || !isVideoCall)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.7),
                          Colors.black.withOpacity(0.9),
                        ],
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Avatar
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                          ),
                          child: widget.friend.avatar.isNotEmpty
                              ? ClipOval(
                                  child: Image.network(
                                    UrlHelper.convertUrl(widget.friend.avatar),
                                    width: 120,
                                    height: 120,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        width: 120,
                                        height: 120,
                                        color: Colors.grey[800],
                                        child: const Icon(
                                          Icons.person,
                                          size: 60,
                                          color: Colors.white,
                                        ),
                                      );
                                    },
                                    loadingBuilder: (context, child, loadingProgress) {
                                      if (loadingProgress == null) return child;
                                      return Container(
                                        width: 120,
                                        height: 120,
                                        color: Colors.grey[800],
                                        child: Center(
                                          child: CircularProgressIndicator(
                                            value: loadingProgress.expectedTotalBytes != null
                                                ? loadingProgress.cumulativeBytesLoaded /
                                                    loadingProgress.expectedTotalBytes!
                                                : null,
                                            color: Colors.white,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                )
                              : Container(
                                  width: 120,
                                  height: 120,
                                  color: Colors.grey[800],
                                  child: const Icon(
                                    Icons.person,
                                    size: 60,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                        const SizedBox(height: 24),
                        // Name
                        Text(
                          widget.friend.nickname.isNotEmpty
                              ? widget.friend.nickname
                              : widget.friend.username,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Call state with color indicator
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _getCallStateColor(),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _getCallStateText(),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        if (isVideoCall) ...[
                          const SizedBox(height: 4),
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.videocam, color: Colors.white70, size: 16),
                              SizedBox(width: 4),
                              Text(
                                'Video Call',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

              // Call controls at the bottom
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.8),
                      ],
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Mute button
                      if (isConnected)
                        _buildControlButton(
                          icon: _isMuted ? Icons.mic_off : Icons.mic,
                          label: 'Mute',
                          onPressed: _toggleMute,
                          backgroundColor: Colors.white.withOpacity(0.2),
                        ),

                      // Camera toggle - always visible
                      _buildControlButton(
                        icon: _isCameraOff ? Icons.videocam_off : Icons.videocam,
                        label: 'Camera',
                        onPressed: _toggleCamera,
                        backgroundColor: Colors.white.withOpacity(0.2),
                      ),

                      // Switch camera - only visible while camera is toggled on
                      if (!_isCameraOff)
                        _buildControlButton(
                          icon: Icons.switch_camera,
                          label: 'Switch',
                          onPressed: _switchCamera,
                          backgroundColor: Colors.white.withOpacity(0.2),
                        ),

                      // Accept/Reject buttons (incoming calls)
                      if (widget.isIncoming && callState == CallState.ringing) ...[
                        _buildControlButton(
                          icon: Icons.call_end,
                          label: 'Decline',
                          onPressed: _rejectCall,
                          backgroundColor: Colors.red,
                        ),
                        _buildControlButton(
                          icon: Icons.call,
                          label: 'Accept',
                          onPressed: _acceptCall,
                          backgroundColor: Colors.green,
                        ),
                      ],

                      // End call button
                      if (callState != CallState.ringing || !widget.isIncoming)
                        _buildControlButton(
                          icon: Icons.call_end,
                          label: 'End',
                          onPressed: _endCall,
                          backgroundColor: Colors.red,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required Color backgroundColor,
  }) {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: backgroundColor,
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: Icon(icon, color: Colors.white, size: 28),
            onPressed: onPressed,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
