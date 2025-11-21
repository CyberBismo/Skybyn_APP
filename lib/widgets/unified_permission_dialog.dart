import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Unified permission dialog that matches the style of notification permission prompts
class UnifiedPermissionDialog extends StatefulWidget {
  final String title;
  final String description;
  final String detailedDescription;
  final Permission permission;
  final IconData? icon;
  final VoidCallback? onGranted;
  final VoidCallback? onDenied;

  const UnifiedPermissionDialog({
    super.key,
    required this.title,
    required this.description,
    required this.detailedDescription,
    required this.permission,
    this.icon,
    this.onGranted,
    this.onDenied,
  });

  @override
  State<UnifiedPermissionDialog> createState() => _UnifiedPermissionDialogState();
}

class _UnifiedPermissionDialogState extends State<UnifiedPermissionDialog> {
  bool _isRequesting = false;
  bool _hasPermission = false;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final status = await widget.permission.status;
    setState(() {
      _hasPermission = status.isGranted;
    });
  }

  Future<void> _requestPermission() async {
    setState(() {
      _isRequesting = true;
    });

    try {
      final status = await widget.permission.request();
      setState(() {
        _hasPermission = status.isGranted;
        _isRequesting = false;
      });

      if (_hasPermission) {
        widget.onGranted?.call();
      } else if (status.isPermanentlyDenied) {
        // Show option to open settings
        _showSettingsDialog();
      }
    } catch (e) {
      setState(() {
        _isRequesting = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error requesting permission: $e')),
        );
      }
    }
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${widget.title} Required'),
        content: const Text(
          'This permission has been permanently denied. Please enable it in your device settings to use this feature.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.icon != null) ...[
            Icon(
              widget.icon,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
          ],
          Text(
            widget.description,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          Text(
            widget.detailedDescription,
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          if (_hasPermission)
            const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text(
                  'Permission granted!',
                  style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                ),
              ],
            )
          else
            const Row(
              children: [
                Icon(Icons.warning, color: Colors.orange),
                SizedBox(width: 8),
                Text(
                  'Permission not granted',
                  style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                ),
              ],
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: widget.onDenied,
          child: Text(
            'Cancel',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        if (!_hasPermission)
          ElevatedButton(
            onPressed: _isRequesting ? null : _requestPermission,
            style: ElevatedButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
            child: _isRequesting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text(
                    'Grant Permission',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        if (_hasPermission)
          ElevatedButton(
            onPressed: widget.onGranted,
            style: ElevatedButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
            child: const Text(
              'Continue',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

