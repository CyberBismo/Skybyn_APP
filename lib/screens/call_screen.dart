import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/call_service.dart';
import '../models/friend.dart';
import '../widgets/background_gradient.dart';
import '../utils/translation_keys.dart';
import '../widgets/translated_text.dart';
import '../services/translation_service.dart';
import '../config/constants.dart';

class CallScreen extends StatefulWidget {
  final Friend? friend; // null if receiving call
  final CallType callType;
  final bool isIncoming;

  const CallScreen({
    super.key,
    this.friend,
    required this.callType,
    this.isIncoming = false,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final CallService _callService = CallService();
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  CallState _callState = CallState.idle;
  bool _isMuted = false;
  bool _isVideoEnabled = true;
  bool _isFrontCamera = true;
  RTCVideoRenderer? _localRenderer;
  RTCVideoRenderer? _remoteRenderer;

  @override
  void initState() {
    super.initState();
    _localRenderer = RTCVideoRenderer();
    _remoteRenderer = RTCVideoRenderer();
    _initializeRenderers();
    _setupCallService();
    if (!widget.isIncoming && widget.friend != null) {
      _startCall();
    } else if (widget.isIncoming) {
      _callState = CallState.ringing;
    }
  }

  Future<void> _initializeRenderers() async {
    await _localRenderer?.initialize();
    await _remoteRenderer?.initialize();
  }

  void _setupCallService() {
    _callService.onCallStateChanged = (state) {
      if (mounted) {
        setState(() {
          _callState = state;
        });
      }
    };

    _callService.onLocalStream = (stream) async {
      if (mounted) {
        setState(() {
          _localStream = stream;
        });
        if (stream != null && _localRenderer != null) {
          final videoTrack = stream.getVideoTracks().firstOrNull;
          if (videoTrack != null) {
            _localRenderer!.srcObject = stream;
          }
        }
      }
    };

    _callService.onRemoteStream = (stream) async {
      if (mounted) {
        setState(() {
          _remoteStream = stream;
        });
        if (stream != null && _remoteRenderer != null) {
          final videoTrack = stream.getVideoTracks().firstOrNull;
          if (videoTrack != null) {
            _remoteRenderer!.srcObject = stream;
          }
        }
      }
    };

    _callService.onCallError = (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: ListenableBuilder(
              listenable: TranslationService(),
              builder: (context, _) => Text('${TranslationKeys.callError.tr}: $error'),
            ),
          ),
        );
      }
    };
  }

  Future<void> _startCall() async {
    if (widget.friend != null) {
      // Check permissions before starting call
      final hasPermission = await _checkCallPermissions(widget.callType);
      if (hasPermission) {
        await _callService.startCall(widget.friend!.id, widget.callType);
      } else {
        // If permissions denied, end the call
        await _endCall();
      }
    }
  }

  Future<void> _acceptCall() async {
    // Check permissions before accepting call
    final hasPermission = await _checkCallPermissions(widget.callType);
    if (hasPermission) {
      await _callService.acceptCall();
    } else {
      // If permissions denied, end the call
      await _endCall();
    }
  }

  /// Check and request permissions for voice/video calls using Android system dialogs
  Future<bool> _checkCallPermissions(CallType callType) async {
    try {
      // Always need microphone for calls - use Android system dialog
      final micStatus = await Permission.microphone.status;
      if (!micStatus.isGranted) {
        final micRequest = await Permission.microphone.request();
        if (!micRequest.isGranted) {
          if (micRequest.isPermanentlyDenied && mounted) {
            _showSettingsDialog('Microphone Permission Required',
                'Skybyn needs microphone access to make voice and video calls. Please enable it in settings.');
          }
          return false;
        }
      }

      // For video calls, also need camera - use Android system dialog
      if (callType == CallType.video) {
        final cameraStatus = await Permission.camera.status;
        if (!cameraStatus.isGranted) {
          final cameraRequest = await Permission.camera.request();
          if (!cameraRequest.isGranted) {
            if (cameraRequest.isPermanentlyDenied && mounted) {
              _showSettingsDialog('Camera Permission Required',
                  'Skybyn needs camera access to make video calls. Please enable it in settings.');
            }
            return false;
          }
        }
      }

      return true;
    } catch (e) {
      print('❌ [CallScreen] Error checking permissions: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: ListenableBuilder(
              listenable: TranslationService(),
              builder: (context, _) => Text('${TranslationKeys.errorCheckingPermissions.tr}: $e'),
            ),
          ),
        );
      }
      return false;
    }
  }

  /// Show settings dialog when permission is permanently denied
  void _showSettingsDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: TranslatedText(TranslationKeys.cancel),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await openAppSettings();
            },
            child: TranslatedText(TranslationKeys.openSettings),
          ),
        ],
      ),
    );
  }

  Future<void> _endCall() async {
    await _callService.endCall();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _toggleMute() async {
    await _callService.toggleMicrophone();
    setState(() {
      _isMuted = !_isMuted;
    });
  }

  Future<void> _toggleVideo() async {
    if (widget.callType == CallType.video) {
      await _callService.toggleCamera();
      setState(() {
        _isVideoEnabled = !_isVideoEnabled;
      });
    }
  }

  Future<void> _switchCamera() async {
    await _callService.switchCamera();
    setState(() {
      _isFrontCamera = !_isFrontCamera;
    });
  }

  @override
  void dispose() {
    if (_callState != CallState.ended && _callState != CallState.idle) {
      _callService.endCall();
    }
    _localRenderer?.dispose();
    _remoteRenderer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final friend = widget.friend;
    final friendName = friend?.nickname.isNotEmpty == true
        ? friend!.nickname
        : friend?.username ?? 'Unknown';

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          const BackgroundGradient(),
          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: _endCall,
                      ),
                      const Spacer(),
                      if (widget.callType == CallType.video)
                        IconButton(
                          icon: Icon(
                            _isFrontCamera ? Icons.camera_front : Icons.camera_rear,
                            color: Colors.white,
                          ),
                          onPressed: _switchCamera,
                        ),
                    ],
                  ),
                ),
                // Main content
                Expanded(
                  child: Stack(
                    children: [
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Remote video (for video calls) or avatar
                            if (widget.callType == CallType.video && _remoteStream != null && _remoteRenderer != null)
                              Expanded(
                                child: Container(
                                  width: double.infinity,
                                  child: RTCVideoView(
                                    _remoteRenderer!,
                                    mirror: false,
                                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                                  ),
                                ),
                              )
                            else
                              Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 3),
                                ),
                                child: friend?.avatar.isNotEmpty == true
                                    ? ClipOval(
                                        child: CachedNetworkImage(
                                          imageUrl: UrlHelper.convertUrl(friend!.avatar),
                                          width: 120,
                                          height: 120,
                                          fit: BoxFit.cover,
                                          placeholder: (context, url) => Image.asset(
                                            'assets/images/icon.png',
                                            width: 120,
                                            height: 120,
                                            fit: BoxFit.cover,
                                          ),
                                          errorWidget: (context, url, error) => Image.asset(
                                            'assets/images/icon.png',
                                            width: 120,
                                            height: 120,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      )
                                    : Image.asset(
                                        'assets/images/icon.png',
                                        width: 120,
                                        height: 120,
                                        fit: BoxFit.cover,
                                      ),
                              ),
                            const SizedBox(height: 32),
                            // Friend name
                            Text(
                              friendName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Call status
                            Text(
                              _getCallStatusText(),
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Local video preview (for video calls)
                      if (widget.callType == CallType.video && _localStream != null)
                        Positioned(
                          bottom: 100,
                          right: 16,
                          child: Container(
                            width: 120,
                            height: 160,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: _localRenderer != null
                                  ? RTCVideoView(
                                      _localRenderer!,
                                      mirror: _isFrontCamera,
                                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                                    )
                                  : const SizedBox(),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // Call controls
                Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Mute button
                      _buildCallButton(
                        icon: _isMuted ? Icons.mic_off : Icons.mic,
                        onPressed: _toggleMute,
                        backgroundColor: _isMuted
                            ? Colors.red.withOpacity(0.8)
                            : Colors.white.withOpacity(0.2),
                      ),
                      // Video toggle (for video calls)
                      if (widget.callType == CallType.video)
                        _buildCallButton(
                          icon: _isVideoEnabled ? Icons.videocam : Icons.videocam_off,
                          onPressed: _toggleVideo,
                          backgroundColor: _isVideoEnabled
                              ? Colors.white.withOpacity(0.2)
                              : Colors.red.withOpacity(0.8),
                        ),
                      // Accept/End call button
                      if (_callState == CallState.ringing && widget.isIncoming)
                        _buildCallButton(
                          icon: Icons.call,
                          onPressed: _acceptCall,
                          backgroundColor: Colors.green.withOpacity(0.8),
                          size: 64,
                        )
                      else
                        _buildCallButton(
                          icon: Icons.call_end,
                          onPressed: _endCall,
                          backgroundColor: Colors.red.withOpacity(0.8),
                          size: 64,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCallButton({
    required IconData icon,
    required VoidCallback onPressed,
    required Color backgroundColor,
    double size = 56,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withOpacity(0.3),
          width: 2,
        ),
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.white, size: size * 0.5),
        onPressed: onPressed,
      ),
    );
  }

  String _getCallStatusText() {
    switch (_callState) {
      case CallState.idle:
        return 'Connecting...';
      case CallState.calling:
        return 'Calling...';
      case CallState.ringing:
        return widget.isIncoming ? 'Incoming call' : 'Ringing...';
      case CallState.connected:
        return widget.callType == CallType.video ? 'Video call' : 'Audio call';
      case CallState.ended:
        return 'Call ended';
    }
  }
}

