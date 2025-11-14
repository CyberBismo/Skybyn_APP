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

      print('📡 [LeftPanel] API response status: ${response.statusCode}');
      print('📡 [LeftPanel] API response body: ${response.body}');

      if (response.statusCode == 200) {
        try {
          final data = json.decode(response.body);
          print('📡 [LeftPanel] Parsed data type: ${data.runtimeType}');
          
          if (data is List) {
            // Validate and filter shortcuts
            final validShortcuts = <Map<String, dynamic>>[];
            for (var item in data) {
              if (item is Map<String, dynamic>) {
                // Ensure required fields exist
                if (item.containsKey('name') && item['name'] != null) {
                  validShortcuts.add(item);
                } else {
                  print('⚠️ [LeftPanel] Skipping invalid shortcut: missing name field');
                }
              } else {
                print('⚠️ [LeftPanel] Skipping invalid shortcut: not a Map');
              }
            }
            
            setState(() {
              _shortcuts = validShortcuts;
              _isLoading = false;
            });
            print('✅ [LeftPanel] Loaded ${_shortcuts.length} shortcuts');
            // Debug: print shortcut names
            for (var shortcut in _shortcuts) {
              print('  - ${shortcut['name']} (icon: ${shortcut['icon'] ?? 'no icon'})');
            }
            if (_shortcuts.isEmpty) {
              print('⚠️ [LeftPanel] WARNING: Shortcuts list is empty!');
            }
          } else if (data is Map) {
            if (data.containsKey('error')) {
              print('❌ [LeftPanel] API returned error: ${data['error']}');
            } else if (data.containsKey('shortcuts') && data['shortcuts'] is List) {
              // Handle alternative response format with 'shortcuts' key
              final shortcutsList = data['shortcuts'] as List;
              final validShortcuts = <Map<String, dynamic>>[];
              for (var item in shortcutsList) {
                if (item is Map<String, dynamic> && item.containsKey('name')) {
                  validShortcuts.add(item);
                }
              }
              setState(() {
                _shortcuts = validShortcuts;
                _isLoading = false;
              });
              print('✅ [LeftPanel] Loaded ${_shortcuts.length} shortcuts from shortcuts key');
            } else {
              print('⚠️ [LeftPanel] API returned Map but no recognized format: $data');
              setState(() {
                _shortcuts = [];
                _isLoading = false;
              });
            }
          } else {
            print('⚠️ [LeftPanel] API returned unexpected data type: ${data.runtimeType}');
            print('⚠️ [LeftPanel] Data content: $data');
            setState(() {
              _shortcuts = [];
              _isLoading = false;
            });
          }
        } catch (e) {
          print('❌ [LeftPanel] JSON decode error: $e');
          print('❌ [LeftPanel] Response body: ${response.body}');
          setState(() {
            _shortcuts = [];
            _isLoading = false;
          });
        }
      } else {
        print('⚠️ [LeftPanel] API returned status ${response.statusCode}');
        print('⚠️ [LeftPanel] Response body: ${response.body}');
        setState(() {
          _shortcuts = [];
          _isLoading = false;
        });
      }

      // Load Discord widget data
      _loadDiscordWidget();
    } catch (e) {
      print('❌ [LeftPanel] Error loading panel data: $e');
      setState(() {
        _shortcuts = [];
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
    // Try to open Discord app first, then fallback to external browser
    final discordUrl = Uri.parse('https://discord.gg/wBhPvEvn87');
    final discordAppUrl = Uri.parse('discord://discord.gg/wBhPvEvn87');
    
    try {
      // Try Discord app first
      if (await canLaunchUrl(discordAppUrl)) {
        try {
          await launchUrl(discordAppUrl, mode: LaunchMode.externalApplication);
          return;
        } catch (e) {
          print('⚠️ [LeftPanel] Discord app not available, using browser');
        }
      }
      
      // Fallback to external browser
      if (await canLaunchUrl(discordUrl)) {
        await launchUrl(discordUrl, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      print('❌ [LeftPanel] Error opening Discord: $e');
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
      print('❌ [LeftPanel] Error opening URL: $e');
    }
  }

  Future<void> _navigateToShortcut(String name) async {
    // Skip Discord - it has its own handler
    if (name.toLowerCase() == 'discord') {
      return;
    }

    // Navigate to dedicated screen for each shortcut
    Widget? screen;
    switch (name.toLowerCase()) {
      case 'music':
        screen = const MusicScreen();
        break;
      case 'games':
        screen = const GamesScreen();
        break;
      case 'events':
        screen = const EventsScreen();
        break;
      case 'groups':
        screen = const GroupsScreen();
        break;
      case 'pages':
        screen = const PagesScreen();
        break;
      case 'markets':
        screen = const MarketsScreen();
        break;
      case 'beta feedback':
        screen = const FeedbackScreen();
        break;
      default:
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$name feature coming soon')),
          );
        }
        return;
    }

    if (screen != null && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => screen!),
      );
    }
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
            } else {
              // Navigate to dedicated screen
              _navigateToShortcut(name);
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
                                      return name != 'discord';
                                    })
                                    .toList();
                                
                                print('🔍 [LeftPanel] Displaying ${filteredShortcuts.length} shortcuts (total: ${_shortcuts.length})');
                                
                                return ListView(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  children: [
                                    // Discord section (always shown, like on website)
                                    _buildDiscordSection(),
                                    const SizedBox(height: 16),
                                    // Other shortcuts
                                    ...filteredShortcuts.map((shortcut) {
                                      print('✅ [LeftPanel] Building shortcut item: ${shortcut['name']}');
                                      return _buildShortcutItem(shortcut);
                                    }),
                                  ],
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

