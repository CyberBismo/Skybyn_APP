import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/location_service.dart';
import '../services/auth_service.dart';
import '../widgets/app_colors.dart';
import '../utils/translation_keys.dart';
import '../widgets/translated_text.dart';
import '../services/translation_service.dart';
import '../config/constants.dart';

class FindFriendsWidget extends StatefulWidget {
  final VoidCallback? onFriendsFound;
  final VoidCallback? onLocationUpdated;

  const FindFriendsWidget({super.key, this.onFriendsFound, this.onLocationUpdated});

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
        print('⚠️ [FindFriendsWidget] Failed to update location, but continuing search...');
      }

      // Find nearby users
      final nearbyUsers = await _locationService.findNearbyUsers(
        userId,
        position.latitude,
        position.longitude,
        radiusKm: 5.0, // 5km radius
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasSearched = true;
          _nearbyUsers = nearbyUsers;
        });

        if (nearbyUsers.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(TranslationService().translate('no_nearby_users')),
              backgroundColor: Colors.orange,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Found ${nearbyUsers.length} user${nearbyUsers.length == 1 ? '' : 's'} nearby'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      print('❌ [FindFriendsWidget] Error finding friends: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasSearched = true;
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

  Future<Map<String, dynamic>?> _searchUserByUsername(String username) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.apiBase}/search.php'),
        body: {
          'userID': await _authService.getStoredUserId() ?? '',
          'keyword': username,
        },
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List && data.isNotEmpty) {
          // Find exact username match (case-insensitive)
          for (var user in data) {
            if (user['username']?.toString().toLowerCase() == username.toLowerCase()) {
              return user as Map<String, dynamic>;
            }
          }
          // If no exact match, return first result
          return data[0] as Map<String, dynamic>;
        }
      }
      return null;
    } catch (e) {
      print('❌ [FindFriendsWidget] Error searching user: $e');
      return null;
    }
  }

  Future<bool> _sendFriendRequest(String friendId) async {
    try {
      final userId = await _authService.getStoredUserId();
      if (userId == null) return false;

      final response = await http.post(
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
      print('❌ [FindFriendsWidget] Error sending friend request: $e');
      return false;
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
      // Search for user by username
      final user = await _searchUserByUsername(username);
      
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

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
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
                      color: Colors.white,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TranslatedText(
                        TranslationKeys.findFriendsInArea,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TranslatedText(
                  TranslationKeys.findFriendsDescription,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _findFriendsInArea,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.2),
                      foregroundColor: Colors.white,
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
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.search, size: 20),
                              const SizedBox(width: 8),
                              TranslatedText(
                                TranslationKeys.findFriendsButton,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                if (_hasSearched && _nearbyUsers.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Divider(color: Colors.white30),
                  const SizedBox(height: 16),
                  TranslatedText(
                    TranslationKeys.nearbyUsers,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ..._nearbyUsers.take(5).map((user) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: Colors.white.withOpacity(0.2),
                              backgroundImage: user['avatar'] != null && user['avatar'].toString().isNotEmpty
                                  ? NetworkImage(user['avatar'].toString())
                                  : null,
                              child: user['avatar'] == null || user['avatar'].toString().isEmpty
                                  ? const Icon(Icons.person, color: Colors.white)
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    user['nickname']?.toString() ?? user['username']?.toString() ?? 'Unknown',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (user['online'] == 1 || user['online'] == true)
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
                      )),
                ],
                if (_hasSearched && _nearbyUsers.isEmpty) ...[
                  const SizedBox(height: 20),
                  const Divider(color: Colors.white30),
                  const SizedBox(height: 16),
                  TranslatedText(
                    TranslationKeys.noNearbyUsers,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TranslatedText(
                    TranslationKeys.addFriendByUsername,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _referralController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: TranslationService().translate(TranslationKeys.enterUsernameOrCode),
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.1),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.5)),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                    onSubmitted: (_) => _addFriendByUsername(),
                  ),
                  if (_addFriendError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _addFriendError!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isAddingFriend ? null : _addFriendByUsername,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryColor,
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
                          : TranslatedText(
                              TranslationKeys.sendFriendRequest,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

