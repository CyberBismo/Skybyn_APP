import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/auth_service.dart';
import '../config/constants.dart';
import '../utils/translation_keys.dart';
import '../widgets/translated_text.dart';

class LeftPanel extends StatefulWidget {
  const LeftPanel({super.key});

  @override
  State<LeftPanel> createState() => _LeftPanelState();
}

class _LeftPanelState extends State<LeftPanel> {
  final AuthService _authService = AuthService();
  List<Map<String, dynamic>> _shortcuts = [];
  bool _isLoading = true;
  String? _discordOnlineMembers;

  @override
  void initState() {
    super.initState();
    _loadPanelData();
  }

  Future<void> _loadPanelData() async {
    final userId = await _authService.getStoredUserId();
    if (userId == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      // Load shortcuts from API
      final response = await http.post(
        Uri.parse('${ApiConstants.apiBase}/left_panel.php'),
        body: {
          'uid': userId,
        },
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List) {
          setState(() {
            _shortcuts = List<Map<String, dynamic>>.from(data);
            _isLoading = false;
          });
        } else {
          setState(() {
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _isLoading = false;
        });
      }

      // Load Discord widget data
      _loadDiscordWidget();
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadDiscordWidget() async {
    try {
      // Use apiBase to access API folder (new location: api/discordStatus.php)
      final response = await http.get(
        Uri.parse('${ApiConstants.apiBase}/discordStatus.php'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        // Check if response body is not empty
        if (response.body.isEmpty || response.body.trim().isEmpty) {
          print('⚠️ [LeftPanel] Discord widget: Empty response body');
          return;
        }

        // Try to decode JSON
        dynamic data;
        try {
          data = json.decode(response.body);
        } catch (e) {
          print('⚠️ [LeftPanel] Discord widget: Invalid JSON - ${e.toString()}');
          print('⚠️ [LeftPanel] Discord widget: Response body: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}');
          return;
        }

        // Validate data structure
        if (data is Map && data['members'] != null && data['members'] is List) {
          // Filter members with status === 'online' (matching website implementation)
          final members = data['members'] as List;
          final onlineCount = members
              .where((member) => 
                  member is Map && 
                  member['status'] != null && 
                  member['status'].toString().toLowerCase() == 'online')
              .length;
          
          if (mounted) {
            setState(() {
              _discordOnlineMembers = onlineCount.toString();
            });
          }
        } else if (data is Map && data['error'] != null) {
          // API returned an error message
          print('⚠️ [LeftPanel] Discord widget error: ${data['error']}');
        }
      } else {
        print('⚠️ [LeftPanel] Discord widget: HTTP ${response.statusCode}');
      }
    } catch (e) {
      // Silently fail - Discord widget is optional
      print('⚠️ [LeftPanel] Failed to load Discord widget: $e');
    }
  }

  Future<void> _openDiscord() async {
    final url = Uri.parse('https://discord.gg/wBhPvEvn87');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildDiscordSection() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with Discord icon, title, and external link icon
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _openDiscord,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // Discord logo
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: SvgPicture.network(
                        'https://cdn.jsdelivr.net/npm/simple-icons@v9/icons/discord.svg',
                        width: 20,
                        height: 20,
                        colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                        placeholderBuilder: (context) => Container(
                          width: 20,
                          height: 20,
                          color: Colors.white.withOpacity(0.1),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TranslatedText(
                        TranslationKeys.discord,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                    const Icon(Icons.open_in_new, color: Colors.white70, size: 18),
                  ],
                ),
              ),
            ),
          ),
          // Discord widget content
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: _discordOnlineMembers != null
                ? Text(
                    'Online Members: $_discordOnlineMembers',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      decoration: TextDecoration.none,
                    ),
                  )
                : const SizedBox(
                    height: 20,
                    child: Center(
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildShortcutItem(Map<String, dynamic> shortcut) {
    final name = shortcut['name']?.toString() ?? '';
    final icon = shortcut['icon']?.toString() ?? '';
    final url = shortcut['url']?.toString();

    IconData iconData;
    switch (icon) {
      case 'fa-brands fa-discord':
        iconData = Icons.chat_bubble_outline; // Using chat icon as Discord alternative
        break;
      case 'fa-solid fa-bug':
        iconData = Icons.bug_report;
        break;
      case 'fa-solid fa-music':
        iconData = Icons.music_note;
        break;
      case 'fa-solid fa-gamepad':
        iconData = Icons.sports_esports;
        break;
      case 'fa-solid fa-calendar-days':
        iconData = Icons.calendar_today;
        break;
      case 'fa-solid fa-comments':
        iconData = Icons.group;
        break;
      case 'fa-regular fa-newspaper':
        iconData = Icons.newspaper;
        break;
      case 'fa-solid fa-store':
        iconData = Icons.store;
        break;
      default:
        iconData = Icons.category;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(iconData, color: Colors.white),
        title: Text(
          name,
          style: const TextStyle(
            color: Colors.white,
            decoration: TextDecoration.none,
          ),
        ),
        trailing: url != null
            ? const Icon(Icons.open_in_new, color: Colors.white70, size: 18)
            : const Icon(Icons.chevron_right, color: Colors.white70),
        onTap: () {
          if (url != null) {
            _openDiscord();
          } else {
            // Handle other shortcuts - can be implemented later
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('$name feature coming soon'),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Get screen dimensions once - these won't change during animation
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;
    final appBarHeight = 60.0;
    final statusBarHeight = mediaQuery.padding.top;
    final bottomNavHeight = 80.0;
    final bottomPadding = Theme.of(context).platform == TargetPlatform.iOS 
        ? 8.0 
        : 8.0 + mediaQuery.padding.bottom;
    // Height = screen height - header (appBar + statusBar) - bottom nav (bottomNav + bottomPadding)
    final panelHeight = screenHeight - 
        (appBarHeight + statusBarHeight) - 
        (bottomNavHeight + bottomPadding);
    final panelWidth = screenWidth * 0.9;
    
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: EdgeInsets.only(
          top: appBarHeight + statusBarHeight,
        ),
        child: SizedBox(
          width: panelWidth,
          height: panelHeight,
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                color: Colors.white.withOpacity(0.05),
                child: Column(
                  children: [
                    // Title with close button
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          TranslatedText(
                            TranslationKeys.shortcuts,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              decoration: TextDecoration.none,
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: IconButton(
                              icon: const Icon(Icons.close, color: Colors.white),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Content area
                    Expanded(
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : ListView(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              children: [
                                // Discord section (always shown, like on website)
                                _buildDiscordSection(),
                                const SizedBox(height: 16),
                                // Other shortcuts
                                ..._shortcuts
                                    .where((shortcut) => 
                                        shortcut['name']?.toString().toLowerCase() != 'discord')
                                    .map((shortcut) => _buildShortcutItem(shortcut))
                                    .toList(),
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
}

