import 'package:flutter/material.dart';
import '../services/auto_update_service.dart';
import 'custom_app_bar.dart';

class UpdateDialog extends StatefulWidget {
  final String currentVersion;
  final String latestVersion;
  final String? releaseNotes;

  const UpdateDialog({
    super.key,
    required this.currentVersion,
    required this.latestVersion,
    this.releaseNotes,
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
    _setupUpdateListener();
  }

  void _setupUpdateListener() {
    // This will be implemented when Firebase App Distribution is configured
    print('ℹ️ [UpdateDialog] Update listener not yet configured');
  }

  Future<void> _startUpdate() async {
    setState(() {
      _isUpdating = true;
      _updateStatus = 'Preparing update...';
    });

    try {
      // For now, we'll simulate the update process
      // In production, this would use the actual update service
      await Future.delayed(const Duration(seconds: 2));
      
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
            content: Text('Failed to start update: $e'),
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
                  color: Colors.grey[600],
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
          if (widget.releaseNotes != null && widget.releaseNotes!.isNotEmpty) ...[
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
                color: Colors.grey[100],
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
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _updateStatus,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
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
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: _startUpdate,
            child: const Text('Update Now'),
          ),
        ] else ...[
          TextButton(
            onPressed: null,
            child: const Text('Updating...'),
          ),
        ],
      ],
    );
  }
}
