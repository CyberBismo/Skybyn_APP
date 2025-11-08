import 'package:flutter/material.dart';
import '../services/auto_update_service.dart';
import 'app_colors.dart';
import '../utils/translation_keys.dart';
import '../widgets/translated_text.dart';
import '../services/translation_service.dart';

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

class _UpdateDialogState extends State<UpdateDialog> with SingleTickerProviderStateMixin {
  bool _isUpdating = false;
  double _updateProgress = 0.0;
  String _updateStatus = '';
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    // Mark dialog as showing when it opens
    AutoUpdateService.setDialogShowing(true);
    
    // Pulse animation for update icon
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
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
            content: TranslatedText(TranslationKeys.downloadUrlNotAvailable),
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
            title: TranslatedText(TranslationKeys.updateFailed),
            content: ListenableBuilder(
              listenable: TranslationService(),
              builder: (context, _) => Text('${TranslationKeys.failedToInstallUpdate.tr}: $e'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: TranslatedText(TranslationKeys.ok),
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
    final primaryColor = Theme.of(context).primaryColor;
    final textColor = AppColors.getTextColor(context);
    final secondaryTextColor = AppColors.getSecondaryTextColor(context);

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      elevation: 0,
      backgroundColor: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color.fromRGBO(30, 45, 60, 1.0) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with gradient background
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    primaryColor,
                    primaryColor.withOpacity(0.7),
                  ],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // Animated update icon
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: 1.0 + (_pulseController.value * 0.1),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.system_update_alt,
                            color: Colors.white,
                            size: 48,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  TranslatedText(
                    TranslationKeys.updateAvailable,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.visible,
                    softWrap: true,
                  ),
                  const SizedBox(height: 8),
                  TranslatedText(
                    TranslationKeys.newVersionAvailable,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.visible,
                    softWrap: true,
                  ),
                ],
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Version comparison card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          // Current version
                          Expanded(
                            child: Column(
                              children: [
                                Text(
                                  'Current',
                                  style: TextStyle(
                                    color: secondaryTextColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    widget.currentVersion,
                                    style: TextStyle(
                                      color: textColor,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Arrow icon
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Icon(
                              Icons.arrow_forward,
                              color: primaryColor,
                              size: 20,
                            ),
                          ),
                          // Latest version
                          Expanded(
                            child: Column(
                              children: [
                                Text(
                                  'Latest',
                                  style: TextStyle(
                                    color: secondaryTextColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: primaryColor.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    widget.latestVersion,
                                    style: TextStyle(
                                      color: primaryColor,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Release notes
                    if (widget.releaseNotes != null && widget.releaseNotes!.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Icon(
                            Icons.new_releases,
                            color: primaryColor,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'What\'s new:',
                            style: TextStyle(
                              color: textColor,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          widget.releaseNotes!,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 14,
                            height: 1.5,
                          ),
                          overflow: TextOverflow.visible,
                          softWrap: true,
                        ),
                      ),
                    ],

                    // Update progress
                    if (_isUpdating) ...[
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            // Progress indicator
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: _updateProgress,
                                minHeight: 8,
                                backgroundColor: isDark ? Colors.white.withOpacity(0.2) : Colors.grey.withOpacity(0.3),
                                valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Status text
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _updateStatus,
                                    style: TextStyle(
                                      color: textColor,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    textAlign: TextAlign.center,
                                    overflow: TextOverflow.visible,
                                    softWrap: true,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // Progress percentage
                            Text(
                              '${(_updateProgress * 100).toInt()}%',
                              style: TextStyle(
                                color: primaryColor,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Actions
            Container(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: _isUpdating
                  ? SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor.withOpacity(0.3),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                            const SizedBox(width: 12),
                            ListenableBuilder(
                              listenable: TranslationService(),
                              builder: (context, _) => Text(
                                TranslationKeys.installingUpdate.tr,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                                softWrap: true,
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: textColor,
                              side: BorderSide(
                                color: isDark ? Colors.white.withOpacity(0.3) : Colors.grey.withOpacity(0.5),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Later',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: _installUpdate,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.download, size: 20),
                                const SizedBox(width: 8),
                                TranslatedText(
                                  TranslationKeys.install,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
