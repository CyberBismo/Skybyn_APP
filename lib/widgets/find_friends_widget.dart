import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/http_client.dart';
import '../services/location_service.dart';
import '../services/auth_service.dart';

import '../widgets/translated_text.dart';
import '../services/translation_service.dart';
import '../config/constants.dart';
import '../screens/profile_screen.dart';
import '../utils/color_utils.dart';
import 'background_gradient.dart';

class FindFriendsWidget extends StatefulWidget {
  final VoidCallback? onFriendsFound;
  final VoidCallback? onLocationUpdated;
  final VoidCallback? onDismiss;

  const FindFriendsWidget({super.key, this.onFriendsFound, this.onLocationUpdated, this.onDismiss});

  @override
  State<FindFriendsWidget> createState() => _FindFriendsWidgetState();
}

class _FindFriendsWidgetState extends State<FindFriendsWidget> {
  final LocationService _locationService = LocationService();
  final AuthService _authService = AuthService();
  final TextEditingController _referralController = TextEditingController();
  bool _isLoading = false;
  bool _isAddingFriend = false;
  List<Map<String, dynamic>> _nearbyUsers = [];
  bool _hasSearched = false;
  String? _addFriendError;
  final Map<String, String> _friendshipStatus = {}; // userId -> status
  final Set<String> _loadingUsers = {};

  Future<void> _findFriendsInArea() async {
    setState(() {
      _isLoading = true;
      _hasSearched = false;
      _nearbyUsers = [];
    });

    try {
      // Get user ID
      final userId = await _authService.getStoredUserId();
      if (userId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please log in to find friends'),
              backgroundColor: Colors.red,
            ),
          );
        }
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // Get current location
      final position = await _locationService.getCurrentLocation();
      if (position == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Unable to get your location. Please enable location services.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // Update user's location on server
      final locationUpdated = await _locationService.updateUserLocation(
        userId,
        position.latitude,
        position.longitude,
      );

      if (locationUpdated && widget.onLocationUpdated != null) {
        widget.onLocationUpdated!();
      }

      if (!locationUpdated) {
      }

      // Find nearby users
      final nearbyUsers = await _locationService.findNearbyUsers(
        userId,
        position.latitude,
        position.longitude,
        radiusKm: 5.0, // 5km radius
      );
      // Update state immediately if mounted, otherwise use post-frame callback
      final users = nearbyUsers ?? [];
      final statusMap = <String, String>{};
      for (final u in users) {
        final id = u['id']?.toString() ?? '';
        final status = u['friendship_status']?.toString() ?? 'none';
        if (id.isNotEmpty) statusMap[id] = status;
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasSearched = true;
          _nearbyUsers = users;
          _friendshipStatus.addAll(statusMap);
        });
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _isLoading = false;
            _hasSearched = true;
            _nearbyUsers = users;
            _friendshipStatus.addAll(statusMap);
          });
        });
      }

      // Only show snackbar if users were found (input field will show if none found)
      if (nearbyUsers.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Found ${nearbyUsers.length} user${nearbyUsers.length == 1 ? '' : 's'} nearby'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasSearched = true;
          _nearbyUsers = [];
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error finding friends: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<Map<String, dynamic>?> _searchUserByUsernameOrCode(String input) async {
    try {
      final response = await globalAuthClient.post(
        Uri.parse('${ApiConstants.apiBase}/search.php'),
        body: {
          'userID': await _authService.getStoredUserId() ?? '',
          'keyword': input,
        },
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List && data.isNotEmpty) {
          // If it's a referral code (8-11 alphanumeric chars), return first result (referral code match is prioritized)
          if (RegExp(r'^[a-zA-Z0-9]{8,11}$').hasMatch(input)) {
            return data[0] as Map<String, dynamic>;
          }
          
          // Otherwise, find exact username match (case-insensitive)
          for (var user in data) {
            if (user['username']?.toString().toLowerCase() == input.toLowerCase()) {
              return user as Map<String, dynamic>;
            }
          }
          // If no exact match, return first result
          return data[0] as Map<String, dynamic>;
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<bool> _sendFriendRequest(String friendId) async {
    try {
      final userId = await _authService.getStoredUserId();
      if (userId == null) return false;

      final response = await globalAuthClient.post(
        Uri.parse(ApiConstants.friend),
        body: {
          'userID': userId,
          'friendID': friendId,
          'action': 'add',
        },
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['responseCode'] == '1' || data['responseCode'] == 1;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> _acceptFriendRequest(String friendId) async {
    try {
      final userId = await _authService.getStoredUserId();
      if (userId == null) return false;

      final response = await globalAuthClient.post(
        Uri.parse(ApiConstants.friend),
        body: {
          'userID': userId,
          'friendID': friendId,
          'action': 'accept',
        },
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['responseCode'] == '1' || data['responseCode'] == 1;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<void> _handleFriendAction(String userId) async {
    final status = _friendshipStatus[userId] ?? 'none';
    setState(() => _loadingUsers.add(userId));

    try {
      if (status == 'received') {
        final success = await _acceptFriendRequest(userId);
        if (success && mounted) {
          setState(() => _friendshipStatus[userId] = 'friends');
        }
      } else if (status == 'none') {
        final success = await _sendFriendRequest(userId);
        if (success && mounted) {
          setState(() => _friendshipStatus[userId] = 'sent');
        }
      }
    } finally {
      if (mounted) setState(() => _loadingUsers.remove(userId));
    }
  }

  Future<void> _addFriendByUsername() async {
    final username = _referralController.text.trim();
    if (username.isEmpty) {
      setState(() {
        _addFriendError = TranslationService().translate(TranslationKeys.enterUsernameOrCode);
      });
      return;
    }

    setState(() {
      _isAddingFriend = true;
      _addFriendError = null;
    });

    try {
      // Search for user by username or referral code
      final user = await _searchUserByUsernameOrCode(username);
      
      if (user == null) {
        setState(() {
          _addFriendError = TranslationService().translate(TranslationKeys.userNotFound);
          _isAddingFriend = false;
        });
        return;
      }

      // Check if user is public (visible = 1)
      // Note: The search API might not return visible status, so we'll try to send the request anyway
      // The friend API will reject if the user is not visible

      // Send friend request
      final success = await _sendFriendRequest(user['id'].toString());
      
      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(TranslationService().translate(TranslationKeys.friendRequestSent)),
              backgroundColor: Colors.green,
            ),
          );
          _referralController.clear();
          widget.onFriendsFound?.call();
        } else {
          setState(() {
            _addFriendError = TranslationService().translate(TranslationKeys.failedToAddFriend);
          });
        }
        setState(() {
          _isAddingFriend = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _addFriendError = TranslationService().translate(TranslationKeys.errorOccurred);
          _isAddingFriend = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _referralController.dispose();
    super.dispose();
  }

  Widget _buildFriendButton({
    required String? userId,
    required String status,
    required bool isLoading,
    required Color contentColor,
  }) {
    if (userId == null) return const SizedBox.shrink();

    if (isLoading) {
      return SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(contentColor),
        ),
      );
    }

    if (status == 'friends') {
      return Icon(Icons.check_circle, color: Colors.green, size: 22);
    }

    if (status == 'sent') {
      return Text(
        'Pending',
        style: TextStyle(color: contentColor.withOpacity(0.5), fontSize: 12),
      );
    }

    final isAccept = status == 'received';
    return SizedBox(
      height: 32,
      child: ElevatedButton(
        onPressed: () => _handleFriendAction(userId),
        style: ElevatedButton.styleFrom(
          backgroundColor: isAccept ? Colors.green.shade600 : Colors.blue.shade600,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
        child: Text(
          isAccept ? 'Accept' : 'Add',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bgTheme = BackgroundTheme.of(context);
    final isDarkBackground = bgTheme?.isDark ?? Theme.of(context).brightness == Brightness.dark;
    final contentColor = bgTheme != null 
        ? ColorUtils.getContrastingColor(bgTheme.topColor)
        : (Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black);
    final panelBgColor = isDarkBackground
        ? Colors.white.withOpacity(0.12)
        : Colors.black.withOpacity(0.12);
    final borderColor = isDarkBackground
        ? Colors.white.withOpacity(0.2)
        : Colors.black.withOpacity(0.2);

    return RepaintBoundary(
      child: Container(
      margin: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: panelBgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: borderColor,
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.location_on,
                      color: contentColor,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TranslatedText(
                        TranslationKeys.findFriendsInArea,
                        fallback: 'Find friends in the area',
                        style: TextStyle(
                          color: contentColor,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                    if (widget.onDismiss != null)
                      IconButton(
                        icon: Icon(Icons.close, color: contentColor),
                        onPressed: widget.onDismiss,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        iconSize: 24,
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                TranslatedText(
                  TranslationKeys.findFriendsDescription,
                  fallback: 'Discover and connect with users nearby using your location',
                  style: TextStyle(
                    color: contentColor.withOpacity(0.8),
                    fontSize: 14,
                    decoration: TextDecoration.none,
                  ),
                ),
                // Show search button if not searched yet, or show input if no results found
                if (!_hasSearched) ...[
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _findFriendsInArea,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: contentColor.withOpacity(0.2),
                        foregroundColor: contentColor,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.search, size: 20),
                                SizedBox(width: 8),
                                TranslatedText(
                                  TranslationKeys.findFriendsButton,
                                  fallback: 'Find Friends',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ] else if (_hasSearched && (_nearbyUsers.isEmpty || _nearbyUsers.isEmpty)) ...[
                  // Replace button with input when no results found
                  // Debug output to verify this condition is being met
                  Builder(
                    builder: (context) {
                      return const SizedBox.shrink();
                    },
                  ),
                  const SizedBox(height: 20),
                  const Divider(color: Colors.white30),
                  const SizedBox(height: 16),
                  TranslatedText(
                    TranslationKeys.noNearbyUsers,
                    fallback: 'No users found nearby.',
                    style: TextStyle(
                      color: contentColor.withOpacity(0.8),
                      fontSize: 14,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TranslatedText(
                    TranslationKeys.addFriendByUsername,
                    fallback: 'Add Friend by Username',
                    style: TextStyle(
                      color: contentColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Material(
                    color: Colors.transparent,
                    child: TextField(
                      controller: _referralController,
                      style: TextStyle(color: contentColor),
                      decoration: InputDecoration(
                        hintText: TranslationService().translate(TranslationKeys.enterUsernameOrCode),
                        hintStyle: TextStyle(color: contentColor.withOpacity(0.6)),
                        filled: true,
                        fillColor: contentColor.withOpacity(0.1),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: contentColor.withOpacity(0.3)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: contentColor.withOpacity(0.3)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: contentColor.withOpacity(0.5)),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                      onSubmitted: (_) => _addFriendByUsername(),
                    ),
                  ),
                  if (_addFriendError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _addFriendError!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isAddingFriend ? null : _addFriendByUsername,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isAddingFriend
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Text(
                              TranslationService().translate(TranslationKeys.sendFriendRequest),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isDarkBackground ? Colors.white : Colors.white, // Keep white for filled button
                                decoration: TextDecoration.none,
                              ),
                            ),
                    ),
                  ),
                ],
                if (_hasSearched && _nearbyUsers.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Divider(color: Colors.white30),
                  const SizedBox(height: 16),
                  TranslatedText(
                    TranslationKeys.nearbyUsers,
                    fallback: 'Nearby Users',
                    style: TextStyle(
                      color: contentColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ..._nearbyUsers.take(5).map((user) {
                    final userId = user['id']?.toString() ?? user['userID']?.toString();
                    final username = user['username']?.toString() ?? '';
                    final nickname = user['nickname']?.toString() ?? '';
                    final displayName = (nickname.isNotEmpty ? nickname : username)
                        .replaceAll('__', '_');
                    final status = userId != null ? (_friendshipStatus[userId] ?? 'none') : 'none';
                    final isLoadingUser = userId != null && _loadingUsers.contains(userId);

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          InkWell(
                            onTap: () {
                              if (userId != null && userId.isNotEmpty) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ProfileScreen(
                                      userId: userId,
                                      username: username.isNotEmpty ? username : null,
                                    ),
                                  ),
                                );
                              }
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: contentColor.withOpacity(0.2),
                                    backgroundImage: user['avatar'] != null && user['avatar'].toString().isNotEmpty
                                        ? NetworkImage(UrlHelper.convertUrl(user['avatar'].toString()))
                                        : null,
                                    child: user['avatar'] == null || user['avatar'].toString().isEmpty
                                        ? Icon(Icons.person, color: contentColor)
                                        : null,
                                  ),
                                  const SizedBox(width: 12),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        displayName.isNotEmpty ? displayName : 'Unknown',
                                        style: TextStyle(
                                          color: contentColor,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      if (user['distance'] != null)
                                        Text(
                                          '${user['distance']} km away',
                                          style: TextStyle(
                                            color: contentColor.withOpacity(0.6),
                                            fontSize: 12,
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const Spacer(),
                          if (user['online'] == 1 || user['online'] == true)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          _buildFriendButton(
                            userId: userId,
                            status: status,
                            isLoading: isLoadingUser,
                            contentColor: contentColor,
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}

