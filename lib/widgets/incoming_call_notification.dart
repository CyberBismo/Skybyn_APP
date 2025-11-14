import 'package:flutter/material.dart';
import 'dart:ui';
import '../services/call_service.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// In-app notification widget for incoming calls when app is in foreground
class IncomingCallNotification extends StatelessWidget {
  final String callId;
  final String fromUserId;
  final String fromUsername;
  final String? avatarUrl;
  final CallType callType;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const IncomingCallNotification({
    super.key,
    required this.callId,
    required this.fromUserId,
    required this.fromUsername,
    this.avatarUrl,
    required this.callType,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        padding: const EdgeInsets.all(16),
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.8),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withOpacity(0.2),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Caller info
            Row(
              children: [
                // Avatar
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                  child: ClipOval(
                    child: avatarUrl != null && avatarUrl!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: avatarUrl!,
                            placeholder: (context, url) => Image.asset(
                              'assets/images/icon.png',
                              width: 60,
                              height: 60,
                              fit: BoxFit.cover,
                            ),
                            errorWidget: (context, url, error) => Image.asset(
                              'assets/images/icon.png',
                              width: 60,
                              height: 60,
                              fit: BoxFit.cover,
                            ),
                            width: 60,
                            height: 60,
                            fit: BoxFit.cover,
                          )
                        : Image.asset(
                            'assets/images/icon.png',
                            width: 60,
                            height: 60,
                            fit: BoxFit.cover,
                          ),
                  ),
                ),
                const SizedBox(width: 16),
                // Name and call type
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fromUsername,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        callType == CallType.video
                            ? 'Incoming video call'
                            : 'Incoming voice call',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Reject button
                _buildCallButton(
                  icon: Icons.call_end,
                  onPressed: onReject,
                  backgroundColor: Colors.red.withOpacity(0.8),
                  size: 56,
                ),
                const SizedBox(width: 20),
                // Accept button
                _buildCallButton(
                  icon: Icons.call,
                  onPressed: onAccept,
                  backgroundColor: Colors.green.withOpacity(0.8),
                  size: 56,
                ),
              ],
            ),
          ],
        ),
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
}

