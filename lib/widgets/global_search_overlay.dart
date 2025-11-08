import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/auth_service.dart';
import '../config/constants.dart';
import '../utils/translation_keys.dart';
import '../widgets/translated_text.dart';
import '../widgets/search_form.dart';
import '../screens/profile_screen.dart';
import 'app_colors.dart';

class GlobalSearchOverlay extends StatefulWidget {
  final bool isVisible;
  final VoidCallback onClose;

  const GlobalSearchOverlay({
    super.key,
    required this.isVisible,
    required this.onClose,
  });

  @override
  State<GlobalSearchOverlay> createState() => _GlobalSearchOverlayState();
}

class _GlobalSearchOverlayState extends State<GlobalSearchOverlay> {
  final AuthService _authService = AuthService();
  
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  String? _searchQuery;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _loadCurrentUserId();
  }

  Future<void> _loadCurrentUserId() async {
    final userId = await _authService.getStoredUserId();
    if (mounted) {
      setState(() {
        _currentUserId = userId;
      });
    }
  }

  Future<void> _performSearch(String query) async {
    setState(() {
      _isSearching = true;
      _searchQuery = query;
      _searchResults = [];
    });

    try {
      final userId = await _authService.getStoredUserId();
      if (userId == null) {
        setState(() {
          _isSearching = false;
        });
        return;
      }

      final response = await http.post(
        Uri.parse('${ApiConstants.apiBase}/search.php'),
        body: {
          'userID': userId,
          'keyword': query,
        },
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data is List) {
          // Filter out current user from results
          final filteredResults = List<Map<String, dynamic>>.from(data)
              .where((user) => user['id']?.toString() != userId)
              .toList();
          
          setState(() {
            _searchResults = filteredResults;
            _isSearching = false;
          });
        } else if (data is Map && data['responseCode'] == '0') {
          setState(() {
            _searchResults = [];
            _isSearching = false;
          });
        } else {
          setState(() {
            _searchResults = [];
            _isSearching = false;
          });
        }
      } else {
        setState(() {
          _searchResults = [];
          _isSearching = false;
        });
      }
    } catch (e) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
    }
  }

  void _navigateToProfile(Map<String, dynamic> user) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProfileScreen(
          userId: user['id']?.toString(),
          username: user['username']?.toString(),
        ),
      ),
    );
  }

  Widget _buildSearchUserCard(Map<String, dynamic> user) {
    final username = user['username'] ?? '';
    final nickname = user['nickname'] ?? username;
    final avatar = user['avatar'] ?? '';
    final online = user['online'] == 1 || user['online'] == '1';
    final friendStatus = user['friends']?.toString() ?? '0';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.white.withOpacity(0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => _navigateToProfile(user),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: CachedNetworkImage(
                      imageUrl: avatar,
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        width: 60,
                        height: 60,
                        color: Colors.grey.withOpacity(0.3),
                        child: const Icon(
                          Icons.person,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        width: 60,
                        height: 60,
                        color: Colors.grey.withOpacity(0.3),
                        child: const Icon(
                          Icons.person,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                    ),
                  ),
                  if (online)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nickname,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (username != nickname)
                      Text(
                        '@$username',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 14,
                        ),
                      ),
                  ],
                ),
              ),
              _buildFriendStatusIcon(friendStatus),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFriendStatusIcon(String friendStatus) {
    switch (friendStatus) {
      case '1': // Friends
        return const Icon(
          Icons.check_circle,
          color: Colors.green,
          size: 24,
        );
      case '2': // Received request
        return const Icon(
          Icons.person_add_alt_1,
          color: Colors.blue,
          size: 24,
        );
      case '3': // Sent request
        return const Icon(
          Icons.hourglass_empty,
          color: Colors.orange,
          size: 24,
        );
      case '4': // Blocked
        return const Icon(
          Icons.block,
          color: Colors.red,
          size: 24,
        );
      default: // Not friends
        return Icon(
          Icons.person_add,
          color: Colors.white.withOpacity(0.5),
          size: 24,
        );
    }
  }

  void _handleClose() {
    setState(() {
      _searchQuery = null;
      _searchResults = [];
    });
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isVisible) {
      return const SizedBox.shrink();
    }

    return Stack(
      children: [
        // Search form
        SearchForm(
          onClose: _handleClose,
          onSearch: (query) {
            if (query.trim().isNotEmpty) {
              _performSearch(query.trim());
            } else {
              setState(() {
                _searchResults = [];
                _searchQuery = null;
              });
            }
          },
        ),
        // Search results overlay
        if (_searchQuery != null)
          Positioned(
            top: 60.0 + MediaQuery.of(context).padding.top + 70.0, // Below search form
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _isSearching
                  ? const Center(child: CircularProgressIndicator())
                  : _searchResults.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.search_off,
                                size: 64,
                                color: Colors.white.withOpacity(0.5),
                              ),
                              const SizedBox(height: 16),
                              TranslatedText(
                                TranslationKeys.noResultsFound,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 18,
                                ),
                              ),
                            ],
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 8, bottom: 8),
                              child: TranslatedText(
                                TranslationKeys.searchResults,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.9),
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Expanded(
                              child: ListView.builder(
                                itemCount: _searchResults.length,
                                itemBuilder: (context, index) {
                                  return _buildSearchUserCard(_searchResults[index]);
                                },
                              ),
                            ),
                          ],
                        ),
            ),
          ),
      ],
    );
  }
}

