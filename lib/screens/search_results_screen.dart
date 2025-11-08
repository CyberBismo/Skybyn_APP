import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../widgets/background_gradient.dart';
import '../widgets/custom_app_bar.dart';
import '../services/auth_service.dart';
import '../config/constants.dart';
import '../utils/translation_keys.dart';
import '../widgets/translated_text.dart';
import '../services/translation_service.dart';
import 'profile_screen.dart';

class SearchResultsScreen extends StatefulWidget {
  final String query;

  const SearchResultsScreen({super.key, required this.query});

  @override
  State<SearchResultsScreen> createState() => _SearchResultsScreenState();
}

class _SearchResultsScreenState extends State<SearchResultsScreen> {
  List<Map<String, dynamic>> _searchResults = [];
  bool _isLoading = true;
  String? _errorMessage;
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _performSearch();
  }

  Future<void> _performSearch() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final userId = await _authService.getStoredUserId();
      if (userId == null) {
        setState(() {
          _errorMessage = 'User not authenticated';
          _isLoading = false;
        });
        return;
      }

      final response = await http.post(
        Uri.parse('${ApiConstants.apiBase}/search.php'),
        body: {
          'userID': userId,
          'keyword': widget.query,
        },
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data is List) {
          setState(() {
            _searchResults = List<Map<String, dynamic>>.from(data);
            _isLoading = false;
          });
        } else if (data is Map && data['responseCode'] == '0') {
          setState(() {
            _searchResults = [];
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage = 'Invalid response format';
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _errorMessage = 'Search failed: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error performing search: ${e.toString()}';
        _isLoading = false;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BackgroundGradient(
        child: SafeArea(
          child: Column(
            children: [
              CustomAppBar(
                onSearchFormToggle: () {
                  Navigator.pop(context);
                },
                isSearchFormVisible: false,
              ),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(),
                      )
                    : _errorMessage != null
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  size: 64,
                                  color: Colors.red.withOpacity(0.7),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _errorMessage!,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.8),
                                    fontSize: 16,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: _performSearch,
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          )
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
                            : ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: _searchResults.length,
                                itemBuilder: (context, index) {
                                  final user = _searchResults[index];
                                  return _buildUserCard(user);
                                },
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
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
        return Icon(
          Icons.check_circle,
          color: Colors.green,
          size: 24,
        );
      case '2': // Received request
        return Icon(
          Icons.person_add_alt_1,
          color: Colors.blue,
          size: 24,
        );
      case '3': // Sent request
        return Icon(
          Icons.hourglass_empty,
          color: Colors.orange,
          size: 24,
        );
      case '4': // Blocked
        return Icon(
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
}

