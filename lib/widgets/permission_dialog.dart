import 'package:flutter/material.dart';
import '../services/auto_update_service.dart';

class PermissionDialog extends StatefulWidget {
  final VoidCallback? onGranted;
  final VoidCallback? onDenied;

  const PermissionDialog({
    super.key,
    this.onGranted,
    this.onDenied,
  });

  @override
  State<PermissionDialog> createState() => _PermissionDialogState();
}

class _PermissionDialogState extends State<PermissionDialog> {
  bool _isRequesting = false;
  bool _hasPermission = false;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final hasPermission = await AutoUpdateService.hasInstallPermission();
    setState(() {
      _hasPermission = hasPermission;
    });
  }

  Future<void> _requestPermission() async {
    setState(() {
      _isRequesting = true;
    });

    try {
      final granted = await AutoUpdateService.requestInstallPermission();
      setState(() {
        _hasPermission = granted;
        _isRequesting = false;
      });

      if (granted) {
        widget.onGranted?.call();
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Install Permission Required'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'To install app updates, Skybyn needs permission to install packages from unknown sources.',
            style: TextStyle(fontSize: 16),
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
          child: const Text('Cancel'),
        ),
        if (!_hasPermission)
          ElevatedButton(
            onPressed: _isRequesting ? null : _requestPermission,
            child: _isRequesting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Grant Permission'),
          ),
        if (_hasPermission)
          ElevatedButton(
            onPressed: widget.onGranted,
            child: const Text('Continue'),
          ),
      ],
    );
  }
}
