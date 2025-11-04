import 'package:flutter/material.dart';
import '../services/auto_update_service.dart';
import 'app_colors.dart';

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

  @override
  void initState() {
    super.initState();
    // Mark dialog as showing when it opens
    AutoUpdateService.setDialogShowing(true);
  }

  @override
  void dispose() {
    // Cancel progress notification when dialog is closed
    AutoUpdateService.cancelUpdateProgressNotification();
    // Mark dialog as not showing when it closes
    AutoUpdateService.setDialogShowing(false);
    super.dispose();
  }

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

      // Download the update with progress callback
      final downloadSuccess = await AutoUpdateService.downloadUpdate(
        widget.downloadUrl!,
        onProgress: (progress, status) {
          if (mounted) {
            setState(() {
              _updateProgress = progress / 100.0;
              _updateStatus = status;
            });
          }
        },
      );
      if (!downloadSuccess) {
        throw Exception('Failed to download update');
      }

      setState(() {
        _updateStatus = 'Installing update...';
        _updateProgress = 0.95;
      });

      // Install the update with progress callback
      final installSuccess = await AutoUpdateService.installUpdate(
        onProgress: (progress, status) {
          if (mounted) {
            setState(() {
              _updateProgress = 0.95 + (progress / 100.0 * 0.05); // 95-100%
              _updateStatus = status;
            });
          }
        },
      );
      if (!installSuccess) {
        throw Exception('Failed to install update');
      }

      setState(() {
        _updateStatus = 'Update completed successfully!';
        _updateProgress = 1.0;
      });

      // Cancel progress notification on success
      await AutoUpdateService.cancelUpdateProgressNotification();

      // Close dialog after a delay
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      // Cancel progress notification on error
      await AutoUpdateService.cancelUpdateProgressNotification();

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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      backgroundColor: isDark ? const Color.fromRGBO(36, 59, 85, 1.0) : Colors.white,
      title: Row(
        children: [
          Icon(
            Icons.system_update,
            color: Theme.of(context).primaryColor,
            size: 28,
          ),
          const SizedBox(width: 12),
          Text(
            'Update Available',
            style: TextStyle(
              color: AppColors.getTextColor(context),
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'A new version of Skybyn is available!',
            style: TextStyle(
              color: AppColors.getTextColor(context),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 16),

          // Version info
          Row(
            children: [
              Text(
                'Current: ',
                style: TextStyle(
                  color: AppColors.getTextColor(context),
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
              Text(
                widget.currentVersion,
                style: TextStyle(
                  color: AppColors.getSecondaryTextColor(context),
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                'Latest: ',
                style: TextStyle(
                  color: AppColors.getTextColor(context),
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
              Text(
                widget.latestVersion,
                style: TextStyle(
                  color: AppColors.getTextColor(context),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),

          // Release notes
          if (widget.releaseNotes != null && widget.releaseNotes!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'What\'s new:',
              style: TextStyle(
                color: AppColors.getTextColor(context),
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                widget.releaseNotes!,
                style: TextStyle(
                  color: AppColors.getTextColor(context),
                  fontSize: 12,
                ),
              ),
            ),
          ],

          // Update progress
          if (_isUpdating) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: _updateProgress,
              backgroundColor: isDark ? Colors.white.withOpacity(0.3) : Colors.grey.withOpacity(0.3),
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _updateStatus,
              style: TextStyle(
                color: AppColors.getTextColor(context),
                fontSize: 12,
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
            child: Text(
              'Ignore',
              style: TextStyle(
                color: AppColors.getTextColor(context),
              ),
            ),
          ),
          ElevatedButton(
            onPressed: _installUpdate,
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Install'),
          ),
        ] else ...[
          TextButton(
            onPressed: null,
            child: Text(
              'Installing...',
              style: TextStyle(
                color: AppColors.getHintColor(context),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
