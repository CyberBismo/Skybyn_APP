import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import '../services/auth_service.dart';
import '../config/constants.dart';
import '../utils/translation_keys.dart';
import '../widgets/translated_text.dart';
import '../screens/music_screen.dart';
import '../screens/games_screen.dart';
import '../screens/events_screen.dart';
import '../screens/groups_screen.dart';
import '../screens/pages_screen.dart';
import '../screens/markets_screen.dart';
import '../screens/feedback_screen.dart';

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
      // Load cached data first
      final prefs = await SharedPreferences.getInstance();
      final cachedData = prefs.getString('left_panel_shortcuts');
      final cachedHash = prefs.getString('left_panel_hash');
      
      if (cachedData != null && cachedHash != null) {
        try {
          final cachedShortcuts = List<Map<String, dynamic>>.from(
            json.decode(cachedData) as List
          );
          setState(() {
            _shortcuts = cachedShortcuts;
            _isLoading = false;
          });
        } catch (e) {
        }
      }

      // Check for updates from API
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
        try {
          final trimmedBody = response.body.trim();
          final data = json.decode(trimmedBody);
          
          List<Map<String, dynamic>> validShortcuts = [];
          String? newHash;
          
          // Handle new format with hash
          if (data is Map && data.containsKey('shortcuts')) {
            newHash = data['hash']?.toString();
            final shortcutsList = data['shortcuts'] as List;
            for (var item in shortcutsList) {
              if (item is Map<String, dynamic> && item.containsKey('name')) {
                validShortcuts.add(item);
              }
            }
          } 
          // Handle old format (direct list)
          else if (data is List) {
            for (var item in data) {
              if (item is Map<String, dynamic> && item.containsKey('name')) {
                validShortcuts.add(item);
              }
            }
            // Calculate hash for old format
            newHash = _calculateHash(validShortcuts);
          }
          // Handle error response
          else if (data is Map && data.containsKey('error')) {
            // Keep cached data if available
            if (_shortcuts.isEmpty && cachedData != null) {
              return; // Already loaded from cache
            }
            setState(() {
              _shortcuts = [];
              _isLoading = false;
            });
            return;
          }

          // Check if data has changed
          if (newHash != null && newHash != cachedHash) {
            // Update cache
            await prefs.setString('left_panel_shortcuts', json.encode(validShortcuts));
            await prefs.setString('left_panel_hash', newHash);
            
            setState(() {
              _shortcuts = validShortcuts;
              _isLoading = false;
            });
          } else if (newHash == cachedHash) {
            // Data is the same, no update needed
          } else {
            // No hash available, update anyway
            await prefs.setString('left_panel_shortcuts', json.encode(validShortcuts));
            if (newHash != null) {
              await prefs.setString('left_panel_hash', newHash);
            }
            setState(() {
              _shortcuts = validShortcuts;
              _isLoading = false;
            });
          }
        } catch (e) {
          // Keep cached data if available
          if (_shortcuts.isEmpty) {
            setState(() {
              _shortcuts = [];
              _isLoading = false;
            });
          }
        }
      } else {
        // Keep cached data if available
        if (_shortcuts.isEmpty) {
          setState(() {
            _shortcuts = [];
            _isLoading = false;
          });
        }
      }

      // Load Discord widget data
      _loadDiscordWidget();
    } catch (e) {
      // Keep cached data if available
      if (_shortcuts.isEmpty) {
        setState(() {
          _shortcuts = [];
          _isLoading = false;
        });
      }
    }
  }

  String _calculateHash(List<Map<String, dynamic>> shortcuts) {
    // Calculate MD5 hash to match API
    final jsonString = json.encode(shortcuts);
    final bytes = utf8.encode(jsonString);
    final digest = md5.convert(bytes);
    return digest.toString();
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
          return;
        }

        // Try to decode JSON
        dynamic data;
        try {
          data = json.decode(response.body);
        } catch (e) {
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
        }
      } else {
      }
    } catch (e) {
      // Silently fail - Discord widget is optional
    }
  }

  Future<void> _openDiscord() async {
    final discordWebUrl = 'https://discord.gg/wBhPvEvn87';
    
    try {
      // Try to open Discord app first with invite deep link
      try {
        final inviteUrl = Uri.parse('discord://invite/wBhPvEvn87');
        await launchUrl(inviteUrl, mode: LaunchMode.externalApplication);
        return;
      } catch (e) {
      }
      
      // Fallback to web URL in external browser
      final webUri = Uri.parse(discordWebUrl);
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      // Show error to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to open Discord. Please try again.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
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

  Future<void> _openUrl(String urlString) async {
    try {
      final url = Uri.parse(urlString);
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
    }
  }

  Future<void> _navigateToShortcut(String screen) async {
    // Navigate to dedicated screen based on screen identifier from API
    Widget? targetScreen;
    switch (screen.toLowerCase()) {
      case 'music':
        targetScreen = const MusicScreen();
        break;
      case 'games':
        targetScreen = const GamesScreen();
        break;
      case 'events':
        targetScreen = const EventsScreen();
        break;
      case 'groups':
        targetScreen = const GroupsScreen();
        break;
      case 'pages':
        targetScreen = const PagesScreen();
        break;
      case 'markets':
        targetScreen = const MarketsScreen();
        break;
      case 'feedback':
        targetScreen = const FeedbackScreen();
        break;
      default:
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$screen feature coming soon')),
          );
        }
        return;
    }

    if (targetScreen != null && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => targetScreen!),
      );
    }
  }

  Widget _buildShortcutItem(Map<String, dynamic> shortcut) {
    final name = shortcut['name']?.toString() ?? '';
    final icon = shortcut['icon']?.toString() ?? '';
    final url = shortcut['url']?.toString();
    final screen = shortcut['screen']?.toString();

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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            // Discord has special handling
            if (name.toLowerCase() == 'discord') {
              _openDiscord();
            } else if (url != null && url.isNotEmpty) {
              // If shortcut has URL, open in external browser
              _openUrl(url);
            } else if (screen != null && screen.isNotEmpty) {
              // Navigate to dedicated screen using screen identifier from API
              _navigateToShortcut(screen);
            } else {
              // Fallback: try using name (for backward compatibility)
              _navigateToShortcut(name.toLowerCase());
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(iconData, color: Colors.white, size: 24),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white70, size: 18),
              ],
            ),
          ),
        ),
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
                          : Builder(
                              builder: (context) {
                                // Filter shortcuts (exclude Discord since it's shown separately)
                                final filteredShortcuts = _shortcuts
                                    .where((shortcut) {
                                      final name = shortcut['name']?.toString().toLowerCase() ?? '';
                                      final shouldInclude = name != 'discord';
                                      if (!shouldInclude) {
                                      }
                                      return shouldInclude;
                                    })
                                    .toList();
                                
                                final children = <Widget>[
                                  // Discord section (always shown, like on website)
                                  _buildDiscordSection(),
                                  const SizedBox(height: 16),
                                ];
                                
                                // Add shortcuts
                                for (var shortcut in filteredShortcuts) {
                                  children.add(_buildShortcutItem(shortcut));
                                }
                                
                                if (filteredShortcuts.isEmpty && _shortcuts.isNotEmpty) {
                                }
                                
                                return ListView(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  children: children,
                                );
                              },
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

