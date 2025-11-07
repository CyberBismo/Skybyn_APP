import 'package:flutter/material.dart';
import 'dart:ui';
import '../services/location_service.dart';
import '../services/auth_service.dart';
import '../widgets/app_colors.dart';
import '../utils/translation_keys.dart';
import '../widgets/translated_text.dart';
import '../services/translation_service.dart';

class FindFriendsWidget extends StatefulWidget {
  final VoidCallback? onFriendsFound;

  const FindFriendsWidget({super.key, this.onFriendsFound});

  @override
  State<FindFriendsWidget> createState() => _FindFriendsWidgetState();
}

class _FindFriendsWidgetState extends State<FindFriendsWidget> {
  final LocationService _locationService = LocationService();
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  List<Map<String, dynamic>> _nearbyUsers = [];
  bool _hasSearched = false;

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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

