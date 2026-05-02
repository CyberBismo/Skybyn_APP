import 'package:flutter/material.dart';
import 'dart:ui';
import '../services/auto_update_service.dart';
import 'app_colors.dart';

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
            content: TranslatedText(TranslationKeys.downloadUrlNotAvailable),
          ),
        );
      }
      return;
    }

    setState(() {
      _isUpdating = true;
      _updateStatus = 'Preparing update...';
      _updateProgress = 0.0;
    });

    try {
      setState(() {
        _updateStatus = 'Downloading...';
        _updateProgress = 0.0;
      });

      // Download the update with progress callback
      final downloadSuccess = await AutoUpdateService.downloadUpdate(
        widget.downloadUrl!,
        onProgress: (progress, status) {
          if (mounted) {
            setState(() {
              _updateProgress = (progress / 100.0).clamp(0.0, 1.0);
              _updateStatus = status;
            });
          }
        },
      );
      if (!downloadSuccess) {
        throw Exception('Failed to download update');
      }

      // Download complete - automatically proceed to installation
      if (mounted) {
        setState(() {
          _updateProgress = 1.0; // 100%
          _updateStatus = 'Downloaded. Starting installation...';
        });
        
        // Brief pause to show "Downloaded" status, then auto-install
        await Future.delayed(const Duration(milliseconds: 800));
      }

      // Automatically start installation after download
      if (mounted) {
        setState(() {
          _updateStatus = 'Opening installer...';
          _updateProgress = 1.0;
        });
      }

      // Install the update automatically
      final installSuccess = await AutoUpdateService.installUpdate(
        onProgress: (progress, status) {
          if (mounted) {
            setState(() {
              _updateProgress = 1.0;
              _updateStatus = status.contains('Installing') || status.contains('Opening') 
                  ? status 
                  : 'Opening installer...';
            });
          }
        },
      );
      if (!installSuccess) {
        throw Exception('Failed to install update');
      }

      // Cancel progress notification on success
      await AutoUpdateService.cancelUpdateProgressNotification();
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
            title: const TranslatedText(TranslationKeys.updateFailed),
            content: ListenableBuilder(
              listenable: TranslationService(),
              builder: (context, _) =>
                  Text('${TranslationKeys.failedToInstallUpdate.tr}: $e'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const TranslatedText(TranslationKeys.ok),
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
    final textColor = isDark ? Colors.white : Colors.black87;
    final secondaryTextColor = isDark ? Colors.white70 : Colors.black54;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          constraints: const BoxConstraints(maxWidth: 400),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark 
                      ? Colors.black.withOpacity(0.6) 
                      : Colors.white.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: isDark 
                        ? Colors.white.withOpacity(0.1) 
                        : Colors.white.withOpacity(0.4),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Clean header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 32, 24, 20),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: primaryColor.withOpacity(0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.system_update_rounded,
                              color: primaryColor,
                              size: 40,
                            ),
                          ),
                          const SizedBox(height: 20),
                          const TranslatedText(
                            TranslationKeys.updateAvailable,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          TranslatedText(
                            TranslationKeys.newVersionAvailable,
                            style: TextStyle(
                              color: secondaryTextColor,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),

                    // Content section
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Simple version comparison
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withOpacity(0.08)
                                  : Colors.black.withOpacity(0.04),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _buildVersionItem('Current', widget.currentVersion, secondaryTextColor, textColor, false),
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: primaryColor.withOpacity(0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.arrow_forward_rounded,
                                    color: primaryColor,
                                    size: 18,
                                  ),
                                ),
                                _buildVersionItem('Latest', widget.latestVersion, secondaryTextColor, textColor, true),
                              ],
                            ),
                          ),

                          // Release notes
                          if (widget.releaseNotes != null &&
                              widget.releaseNotes!.isNotEmpty) ...[
                            const SizedBox(height: 24),
                            Text(
                              'What\'s new',
                              style: TextStyle(
                                color: textColor,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withOpacity(0.05)
                                    : Colors.black.withOpacity(0.03),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                widget.releaseNotes!,
                                style: TextStyle(
                                  color: secondaryTextColor,
                                  fontSize: 14,
                                  height: 1.6,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],

                          // Progress indicator
                          if (_isUpdating) ...[
                            const SizedBox(height: 24),
                            Stack(
                              children: [
                                Container(
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: primaryColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                ),
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  height: 10,
                                  width: (MediaQuery.of(context).size.width - 96) * (_updateProgress.clamp(0.0, 1.0)),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        primaryColor,
                                        primaryColor.withOpacity(0.8),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(5),
                                    boxShadow: [
                                      BoxShadow(
                                        color: primaryColor.withOpacity(0.3),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 14,
                                  height: 14,
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
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Action buttons
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
                      child: _isUpdating
                          ? Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              decoration: BoxDecoration(
                                color: primaryColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  ListenableBuilder(
                                    listenable: TranslationService(),
                                    builder: (context, _) => Text(
                                      TranslationKeys.installingUpdate.tr,
                                      style: TextStyle(
                                        color: primaryColor,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : Row(
                              children: [
                                Expanded(
                                  child: TextButton(
                                    onPressed: () => Navigator.of(context).pop(),
                                    style: TextButton.styleFrom(
                                      foregroundColor: secondaryTextColor,
                                      padding: const EdgeInsets.symmetric(vertical: 18),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                    ),
                                    child: const Text(
                                      'Later',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  flex: 2,
                                  child: ElevatedButton(
                                    onPressed: _installUpdate,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: primaryColor,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 18),
                                      elevation: 8,
                                      shadowColor: primaryColor.withOpacity(0.4),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                    ),
                                    child: const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.download_rounded, size: 20),
                                        SizedBox(width: 10),
                                        TranslatedText(
                                          TranslationKeys.install,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                          ),
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
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVersionItem(String label, String version, Color labelColor, Color valueColor, bool isNew) {
    return Column(
      crossAxisAlignment: isNew ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: labelColor,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          version,
          style: TextStyle(
            color: valueColor,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}
