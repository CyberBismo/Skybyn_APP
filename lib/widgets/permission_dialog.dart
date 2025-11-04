import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/auto_update_service.dart';

/// Permission dialog for install permissions - uses Android system dialog
/// Only shows custom dialog if permission is permanently denied
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
  /// Request install permission using Android system dialog
  Future<bool> _requestPermission() async {
    try {
      final status = await Permission.requestInstallPackages.request();
      return status.isGranted;
    } catch (e) {
      print('❌ [PermissionDialog] Error requesting install permission: $e');
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    // Request permission directly using Android system dialog
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final hasPermission = await AutoUpdateService.hasInstallPermission();
      if (hasPermission) {
        if (mounted) {
          Navigator.of(context).pop();
          widget.onGranted?.call();
        }
        return;
      }

      // Close this dialog first so Android system dialog can appear
      if (mounted) {
        Navigator.of(context).pop();
      }
      
      // Request permission - this will show Android system dialog
      final granted = await _requestPermission();
      
      if (granted) {
        widget.onGranted?.call();
      } else {
        // Check if permanently denied
        final status = await Permission.requestInstallPackages.status;
        if (status.isPermanentlyDenied && mounted) {
          _showSettingsDialog(context);
        } else {
          widget.onDenied?.call();
        }
      }
    });
  }

  void _showSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Install Permission Required'),
        content: const Text(
          'This permission has been permanently denied. Please enable "Install unknown apps" for Skybyn in your device settings.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              widget.onDenied?.call();
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await openAppSettings();
              widget.onDenied?.call();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Return minimal dialog that will close immediately
    return const AlertDialog(
      content: SizedBox(
        width: 50,
        height: 50,
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
