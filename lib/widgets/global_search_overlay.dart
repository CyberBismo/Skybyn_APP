import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/auth_service.dart';
import '../config/constants.dart';
import '../widgets/search_form.dart';
import '../screens/profile_screen.dart';

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
    // If query is empty or less than 3 characters, clear results
    if (query.isEmpty || query.length < 3) {
      setState(() {
        _searchQuery = null;
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

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
        if (data is List && data.isNotEmpty) {
          // Filter out current user from results - check both id and userID fields
          final userIdStr = userId.toString();
          
          final filteredResults = <Map<String, dynamic>>[];
          for (final user in data) {
            final userMap = Map<String, dynamic>.from(user);
            final userIdFromData = userMap['id']?.toString() ?? userMap['userID']?.toString();
            
            
            if (userIdFromData != null && userIdFromData != userIdStr) {
              filteredResults.add(userMap);
            } else {
            }
          }
          if (mounted) {
            setState(() {
              _searchResults = filteredResults;
              _isSearching = false;
            });
          }
        } else if (data is Map) {
          if (data['responseCode'] == '0' || data['responseCode'] == 0) {
            if (mounted) {
              setState(() {
                _searchResults = [];
                _isSearching = false;
              });
            }
          } else {
            // Sometimes API might return a single user object
            final userIdStr = userId.toString();
            final userDataId = data['id']?.toString() ?? data['userID']?.toString();
            if (userDataId != null && userDataId != userIdStr) {
              if (mounted) {
                setState(() {
                  _searchResults = [Map<String, dynamic>.from(data)];
                  _isSearching = false;
                });
              }
            } else {
              if (mounted) {
                setState(() {
                  _searchResults = [];
                  _isSearching = false;
                });
              }
            }
          }
        } else {
          if (mounted) {
            setState(() {
              _searchResults = [];
              _isSearching = false;
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _searchResults = [];
            _isSearching = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _searchResults = [];
          _isSearching = false;
        });
      }
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
    final username = user['username']?.toString() ?? '';
    final nickname = user['nickname']?.toString() ?? username;
    final avatar = user['avatar']?.toString() ?? '';
    final online = user['online'] == 1 || user['online'] == '1' || user['online']?.toString() == '1';
    final friendStatus = user['friends']?.toString() ?? '0';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.white.withOpacity(0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias, // Prevent overflow
      child: InkWell(
        onTap: () => _navigateToProfile(user),
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: 84, // Minimum: 12 padding + 60 avatar + 12 padding
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start, // Align to top
              children: [
              // Avatar
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: CachedNetworkImage(
                      imageUrl: UrlHelper.convertUrl(avatar),
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                      httpHeaders: const {},
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
                      errorWidget: (context, url, error) {
                        // Handle all errors including 404 (HttpExceptionWithStatus)
                        return Container(
                          width: 60,
                          height: 60,
                          color: Colors.grey.withOpacity(0.3),
                          child: const Icon(
                            Icons.person,
                            color: Colors.white,
                            size: 30,
                          ),
                        );
                      },
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
              // Username/nickname column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min, // Take minimum space needed
                  children: [
                    Text(
                      nickname,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        height: 1.0, // Minimal line height
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    if (username != nickname)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          '@$username',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 14,
                            height: 1.0, // Minimal line height
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                  ],
                ),
              ),
              // Friend status icon
              _buildFriendStatusIcon(friendStatus),
            ],
            ),
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

    return SizedBox.expand(
      child: Stack(
        children: [
          // Full-screen tap detector to close when tapping outside
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                // Close search form when tapping outside
                _handleClose();
              },
              child: Container(
                color: Colors.transparent,
              ),
            ),
          ),
        // Search form - taps inside won't close the form
        Align(
          alignment: Alignment.topCenter,
          child: GestureDetector(
            onTap: () {
              // Prevent closing when tapping on the search form itself
            },
            behavior: HitTestBehavior.opaque,
            child: SearchForm(
              onClose: _handleClose,
              onSearch: (query) {
                final trimmedQuery = query.trim();
                // Only search if query has 3 or more characters
                if (trimmedQuery.length >= 3) {
                  _performSearch(trimmedQuery);
                } else {
                  setState(() {
                    _searchResults = [];
                    _searchQuery = null;
                    _isSearching = false;
                  });
                }
              },
              searchResults: _searchQuery != null && _searchQuery!.isNotEmpty ? _searchResults : null,
              isSearching: _isSearching,
            ),
          ),
        ),
      ],
      ),
    );
  }
}

