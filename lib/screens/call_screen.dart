import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../models/friend.dart';
import '../services/call_service.dart';
import '../services/websocket_service.dart';

class CallScreen extends StatefulWidget {
  final Friend friend;
  final CallType callType;
  final bool isIncoming;

  const CallScreen({
    Key? key,
    required this.friend,
    required this.callType,
    this.isIncoming = false,
  }) : super(key: key);

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

  @override
  void initState() {
    super.initState();
    _initializeRenderers();
    _setupCallService();
    
    if (!widget.isIncoming) {
      // Start outgoing call
      _startOutgoingCall();
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
      if (stream != null && _isRemoteVideoInitialized) {
        _remoteRenderer.srcObject = stream;
        setState(() {});
      }
    };

    _callService.onCallStateChanged = (state) {
      setState(() {});
      if (state == CallState.ended || state == CallState.idle) {
        Navigator.of(context).pop();
      }
    };

    _callService.onCallError = (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
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
    if (widget.callType == CallType.video) {
      await _callService.toggleCamera();
      setState(() {
        _isCameraOff = !_isCameraOff;
      });
    }
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
        return 'Ringing...';
      case CallState.connected:
        return 'Connected';
      case CallState.ended:
        return 'Ended';
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
    final isConnected = callState == CallState.connected;

    return WillPopScope(
      onWillPop: () async {
        // Prevent back button from ending call accidentally
        if (callState == CallState.connected) {
          _endCall();
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              // Remote video (full screen for video calls)
              if (isVideoCall && _isRemoteVideoInitialized)
                Positioned.fill(
                  child: RTCVideoView(
                    _remoteRenderer,
                    mirror: false,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                )
              else if (isVideoCall)
                Positioned.fill(
                  child: Container(
                    color: Colors.black,
                    child: Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),
                ),

              // Local video preview (small overlay for video calls)
              if (isVideoCall && _isLocalVideoInitialized && isConnected)
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
                                    widget.friend.avatar,
                                    width: 120,
                                    height: 120,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        width: 120,
                                        height: 120,
                                        color: Colors.grey[800],
                                        child: Icon(
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
                                  child: Icon(
                                    Icons.person,
                                    size: 60,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                        SizedBox(height: 24),
                        // Name
                        Text(
                          widget.friend.nickname.isNotEmpty
                              ? widget.friend.nickname
                              : widget.friend.username,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 8),
                        // Call state
                        Text(
                          _getCallStateText(),
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                          ),
                        ),
                        if (isVideoCall) ...[
                          SizedBox(height: 4),
                          Row(
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
                  padding: EdgeInsets.symmetric(vertical: 40, horizontal: 20),
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

                      // Camera toggle (video calls only)
                      if (isConnected && isVideoCall)
                        _buildControlButton(
                          icon: _isCameraOff ? Icons.videocam_off : Icons.videocam,
                          label: 'Camera',
                          onPressed: _toggleCamera,
                          backgroundColor: Colors.white.withOpacity(0.2),
                        ),

                      // Switch camera (video calls only, when connected)
                      if (isConnected && isVideoCall)
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
        SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
