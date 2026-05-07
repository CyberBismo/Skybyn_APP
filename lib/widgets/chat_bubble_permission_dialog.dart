import 'package:flutter/material.dart';
import '../services/chat_bubble_service.dart';

/// Shows an explanation dialog, then redirects to the system Settings toggle.
/// Returns true if permission was already granted or user went to Settings.
Future<bool> showChatBubblePermissionDialog(BuildContext context) async {
  final already = await ChatBubbleService().isPermissionGranted();
  if (already) return true;

  if (!context.mounted) return false;

  final proceed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
              ),
            ),
            child: const Icon(Icons.chat_bubble, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          const Text('Floating Chat'),
        ],
      ),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Chat without switching apps.',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          SizedBox(height: 8),
          Text(
            'A floating bubble will appear when you get a message, so you can reply without leaving what you\'re doing.',
            style: TextStyle(fontSize: 14, height: 1.4),
          ),
          SizedBox(height: 16),
          _PermissionStep(
            icon: Icons.settings,
            text: 'We\'ll open Settings — just flip the switch next to Skybyn.',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Enable'),
        ),
      ],
    ),
  );

  if (proceed != true) return false;

  final result = await ChatBubbleService().requestPermission();
  if (result == true) return true;
  // requestPermission may return null on some devices — re-check after brief delay
  await Future.delayed(const Duration(milliseconds: 300));
  return await ChatBubbleService().isPermissionGranted();
}

class _PermissionStep extends StatelessWidget {
  final IconData icon;
  final String text;

  const _PermissionStep({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.blue),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 13, height: 1.4)),
        ),
      ],
    );
  }
}
