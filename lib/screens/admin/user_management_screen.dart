import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '../../widgets/background_gradient.dart';
import '../../widgets/custom_app_bar.dart';
import '../../models/admin_user.dart';
import '../../services/auth_service.dart';
import '../../config/constants.dart';
import '../../utils/translation_keys.dart';
import '../../widgets/translated_text.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  List<AdminUser> _users = [];
  bool _isLoading = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  int _totalUsers = 0;
  int _currentOffset = 0;
  final int _limit = 50;
  String? _currentUserId;

  // HTTP client
  static http.Client? _httpClient;
  static http.Client get _client {
    _httpClient ??= _createHttpClient();
    return _httpClient!;
  }

  static http.Client _createHttpClient() {
    HttpClient httpClient;
    if (HttpOverrides.current != null) {
      httpClient = HttpOverrides.current!.createHttpClient(null);
    } else {
      httpClient = HttpClient();
    }
    httpClient.userAgent = 'Skybyn-App/1.0';
    httpClient.connectionTimeout = const Duration(seconds: 30);
    return IOClient(httpClient);
  }

  @override
  void initState() {
    super.initState();
    _loadCurrentUserId();
    _loadUsers();
  }

  Future<void> _loadCurrentUserId() async {
    final authService = AuthService();
    _currentUserId = await authService.getStoredUserId();
  }

  Future<void> _loadUsers({bool reset = false}) async {
    if (reset) {
      _currentOffset = 0;
      _users.clear();
    }

    setState(() => _isLoading = true);

    try {
      final response = await _client.post(
        Uri.parse(ApiConstants.adminUsers),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'X-API-Key': ApiConstants.apiKey,
        },
        body: {
          'userID': _currentUserId ?? '',
          'action': 'list',
          'search': _searchQuery,
          'limit': _limit.toString(),
          'offset': _currentOffset.toString(),
        },
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final usersData = data['data']['users'] as List;
          final newUsers = usersData.map((u) => AdminUser.fromJson(u)).toList();
          
          setState(() {
            if (reset) {
              _users = newUsers;
            } else {
              _users.addAll(newUsers);
            }
            _totalUsers = data['data']['total'] ?? 0;
            _currentOffset += newUsers.length;
            _isLoading = false;
          });
        } else {
          throw Exception(data['message'] ?? 'Failed to load users');
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading users: $e')),
        );
      }
    }
  }

  Future<void> _updateUserRank(AdminUser user, int newRank) async {
    try {
      final response = await _client.post(
        Uri.parse(ApiConstants.adminUsers),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'X-API-Key': ApiConstants.apiKey,
        },
        body: {
          'userID': _currentUserId ?? '',
          'action': 'update_rank',
          'target_user_id': user.id.toString(),
          'new_rank': newRank.toString(),
        },
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('User rank updated successfully')),
            );
            _loadUsers(reset: true);
          }
        } else {
          throw Exception(data['message'] ?? 'Failed to update rank');
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _banUser(AdminUser user, bool ban) async {
    try {
      final response = await _client.post(
        Uri.parse(ApiConstants.adminUsers),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'X-API-Key': ApiConstants.apiKey,
        },
        body: {
          'userID': _currentUserId ?? '',
          'action': 'ban_user',
          'target_user_id': user.id.toString(),
          'banned': ban ? '1' : '0',
          'reason': ban ? 'Banned by admin' : '',
        },
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(ban ? 'User banned' : 'User unbanned')),
            );
            _loadUsers(reset: true);
          }
        } else {
          throw Exception(data['message'] ?? 'Failed to update ban status');
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _showUserActions(AdminUser user) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person, color: Colors.white),
              title: const Text('View Profile', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                // Navigate to profile screen
              },
            ),
            ListTile(
              leading: const Icon(Icons.admin_panel_settings, color: Colors.white),
              title: const Text('Change Rank', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _showRankDialog(user);
              },
            ),
            if (user.isBanned)
              ListTile(
                leading: const Icon(Icons.check_circle, color: Colors.green),
                title: const Text('Unban User', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _banUser(user, false);
                },
              )
            else
              ListTile(
                leading: const Icon(Icons.block, color: Colors.red),
                title: const Text('Ban User', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _showBanConfirmDialog(user);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showRankDialog(AdminUser user) {
    int selectedRank = user.rank;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Change User Rank'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Current rank: ${user.rank}'),
              const SizedBox(height: 16),
              DropdownButton<int>(
                value: selectedRank,
                items: List.generate(11, (i) => DropdownMenuItem(
                  value: i,
                  child: Text('Rank $i'),
                )),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => selectedRank = value);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _updateUserRank(user, selectedRank);
              },
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  void _showBanConfirmDialog(AdminUser user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ban User'),
        content: Text('Are you sure you want to ban ${user.nickname.isNotEmpty ? user.nickname : user.username}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _banUser(user, true);
            },
            child: const Text('Ban', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final statusBarHeight = mediaQuery.padding.top;
    const appBarHeight = 60.0;

    return Scaffold(
      body: Stack(
        children: [
          const BackgroundGradient(),
          Column(
            children: [
              CustomAppBar(
                logoPath: 'assets/images/logo_faded_clean.png',
                onLogoPressed: () => Navigator.pop(context),
                appBarHeight: appBarHeight,
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    top: statusBarHeight,
                    left: 16,
                    right: 16,
                    bottom: 16,
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 20),
                      const TranslatedText(
                        TranslationKeys.userManagement,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _searchController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Search users...',
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                          prefixIcon: const Icon(Icons.search, color: Colors.white70),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.1),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                          ),
                        ),
                        onChanged: (value) {
                          _searchQuery = value;
                        },
                        onSubmitted: (_) {
                          _loadUsers(reset: true);
                        },
                      ),
                      const SizedBox(height: 16),
                      if (_isLoading && _users.isEmpty)
                        const Expanded(
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else
                        Expanded(
                          child: ListView.builder(
                            itemCount: _users.length + (_isLoading ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == _users.length) {
                                return const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(16.0),
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }
                              final user = _users[index];
                              return _buildUserCard(user);
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUserCard(AdminUser user) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: ListTile(
        title: Text(
          user.nickname.isNotEmpty ? user.nickname : user.username,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('@${user.username}', style: TextStyle(color: Colors.white.withOpacity(0.7))),
            const SizedBox(height: 4),
            Row(
              children: [
                if (user.isBanned)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('BANNED', style: TextStyle(color: Colors.white, fontSize: 10)),
                  ),
                if (user.isDeactivated)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('DEACTIVATED', style: TextStyle(color: Colors.white, fontSize: 10)),
                  ),
                const SizedBox(width: 8),
                Text('Rank: ${user.rank}', style: TextStyle(color: Colors.white.withOpacity(0.7))),
                const SizedBox(width: 8),
                if (user.isOnline)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.more_vert, color: Colors.white),
          onPressed: () => _showUserActions(user),
        ),
        onTap: () => _showUserActions(user),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}

