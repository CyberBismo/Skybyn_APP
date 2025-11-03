import 'package:flutter/material.dart';
import '../services/auto_update_service.dart';

class UpdateDialog extends StatefulWidget {
  final String currentVersion;
  final String latestVersion;
  final String? releaseNotes;
  final String? downloadUrl;

  const UpdateDialog({
    super.key,
    required this.currentVersion,
    required this.latestVersion,
    this.releaseNotes,
    this.downloadUrl,
  });

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isUpdating = false;
  double _updateProgress = 0.0;
  String _updateStatus = '';

  Future<void> _installUpdate() async {
    // Check if download URL is available
    if (widget.downloadUrl == null || widget.downloadUrl!.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Download URL not available. Cannot install update.'),
          ),
        );
      }
      return;
    }

    setState(() {
      _isUpdating = true;
      _updateStatus = 'Preparing update...';
    });

    try {
      setState(() {
        _updateStatus = 'Downloading update...';
        _updateProgress = 0.3;
      });

      // Download the update
      final downloadSuccess =
          await AutoUpdateService.downloadUpdate(widget.downloadUrl!);
      if (!downloadSuccess) {
        throw Exception('Failed to download update');
      }

      setState(() {
        _updateStatus = 'Installing update...';
        _updateProgress = 0.7;
      });

      // Install the update
      final installSuccess = await AutoUpdateService.installUpdate();
      if (!installSuccess) {
        throw Exception('Failed to install update');
      }

      setState(() {
        _updateStatus = 'Update completed successfully!';
        _updateProgress = 1.0;
      });

      // Close dialog after a delay
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _updateStatus = 'Error: $e';
        });

        // Show error dialog
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Update Failed'),
            content: Text('Failed to install update: $e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.system_update,
            color: Theme.of(context).primaryColor,
            size: 28,
          ),
          const SizedBox(width: 12),
          const Text('Update Available'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'A new version of Skybyn is available!',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),

          // Version info
          Row(
            children: [
              Text(
                'Current: ',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
              ),
              Text(
                widget.currentVersion,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                'Latest: ',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
              ),
              Text(
                widget.latestVersion,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).primaryColor,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),

          // Release notes
          if (widget.releaseNotes != null &&
              widget.releaseNotes!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'What\'s new:',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                widget.releaseNotes!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],

          // Update progress
          if (_isUpdating) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: _updateProgress,
              backgroundColor: Colors.white.withOpacity(0.3),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _updateStatus,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
      actions: [
        if (!_isUpdating) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Ignore'),
          ),
          ElevatedButton(
            onPressed: _installUpdate,
            child: const Text('Install'),
          ),
        ] else ...[
          const TextButton(
            onPressed: null,
            child: Text('Installing...'),
          ),
        ],
      ],
    );
  }
}
