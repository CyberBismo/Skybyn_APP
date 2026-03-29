import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/http_client.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../config/constants.dart';
import '../models/friend.dart';
import '../screens/chat_screen.dart';

class MapView extends StatefulWidget {
  final MapController? mapController;
  final bool showControls;

  const MapView({
    super.key,
    this.mapController,
    this.showControls = true,
  });

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final AuthService _authService = AuthService();
  final LocationService _locationService = LocationService();
  late final MapController _mapController;
  final Completer<void> _mapReadyCompleter = Completer<void>();

  String? _currentUserId;
  Position? _currentPosition;
  String? _currentUserAvatar;
  List<Friend> _friendsWithLocations = [];
  bool _isLoading = true;
  Timer? _refreshTimer;
  Timer? _locationUploadTimer;
  StreamSubscription<Position>? _positionStream;
  AnimationController? _moveAnimationController;
  final Map<String, String> _friendAvatarUrls = {};
  SharedPreferences? _prefs;

  LatLng _center = const LatLng(59.9139, 10.7522);
  double _zoom = 3.0;
  String _mapStyle = 'street'; // 'street', 'dark', 'satellite'
  bool _isGhostMode = false;
  String _locationShareMode = 'off';
  String? _selectedFriendId; // which friend card is expanded

  static const String _mapStylePreferenceKey = 'map_style';
  static const String _lastMapLatKey = 'last_map_latitude';
  static const String _lastMapLngKey = 'last_map_longitude';
  static const String _lastMapZoomKey = 'last_map_zoom';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _mapController = widget.mapController ?? MapController();
    _initializeMap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _locationUploadTimer?.cancel();
    _positionStream?.cancel();
    _moveAnimationController?.dispose();
    if (widget.mapController == null) {
      _mapController.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _refreshTimer?.cancel();
      _locationUploadTimer?.cancel();
      _positionStream?.pause();
    } else if (state == AppLifecycleState.resumed) {
      _positionStream?.resume();
      _startTimers();
    }
  }

  void _startTimers() {
    _refreshTimer?.cancel();
    _locationUploadTimer?.cancel();
    _refreshTimer = Timer.periodic(
        const Duration(seconds: 10), (_) => _loadFriendsLocations());
    _locationUploadTimer = Timer.periodic(
        const Duration(seconds: 60), (_) => _uploadCurrentLocation());
  }

  Future<void> _initializeMap() async {
    try {
      _prefs = await SharedPreferences.getInstance();

      // Migrate old bool satellite preference to new string style
      final oldSatellite = _prefs!.getBool('map_use_satellite_view');
      if (oldSatellite != null) {
        await _prefs!.setString(
            _mapStylePreferenceKey, oldSatellite ? 'satellite' : 'street');
        await _prefs!.remove('map_use_satellite_view');
      }
      _mapStyle = _prefs!.getString(_mapStylePreferenceKey) ?? 'street';

      final userId = await _authService.getStoredUserId();
      if (userId == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final userProfile = await _authService.getStoredUserProfile();
      if (mounted) {
        setState(() {
          _currentUserId = userId;
          _currentUserAvatar = _normalizeAvatarUrl(userProfile?.avatar);
          _isGhostMode = userProfile?.locationPrivateMode == '1' ||
              userProfile?.locationPrivateMode == true;
          _locationShareMode = userProfile?.locationShareMode ?? 'off';
        });
      }

      // Request permission on first map visit only
      if (mounted) {
        await _locationService.checkAndRequestLocationPermission(
            context, isStartup: true);
      }

      final cachedPosition = await _locationService.getLastKnownLocation();
      if (mounted) {
        setState(() {
          if (cachedPosition != null) {
            _currentPosition = cachedPosition;
            _center = LatLng(cachedPosition.latitude, cachedPosition.longitude);
          }
          final savedZoom = _prefs!.getDouble(_lastMapZoomKey);
          _zoom = savedZoom ?? 15.0;
          _isLoading = false;
        });
      }

      _locationService.getCurrentLocation().then((position) {
        if (position != null && mounted) {
          setState(() {
            _currentPosition = position;
            if (_prefs!.getDouble(_lastMapLatKey) == null) {
              _center = LatLng(position.latitude, position.longitude);
              _zoom = 15.0;
              _animatedMapMove(_center, _zoom);
            }
          });
          if (_currentUserId != null && _locationShareMode != 'off') {
            _locationService.updateUserLocation(
                _currentUserId!, position.latitude, position.longitude);
          }
        }
      });

      final hasPermission = await _locationService.hasLocationPermission();
      if (hasPermission) {
        _positionStream = Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
          ),
        ).listen((position) {
          if (mounted) {
            setState(() => _currentPosition = position);
            _locationService.saveLastKnownLocation(position);
          }
        });
      }

      await _loadFriendsLocations();
      _startTimers();
    } catch (e) {
      debugPrint('Error initializing map: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _uploadCurrentLocation() async {
    if (_currentUserId == null || _locationShareMode == 'off') return;
    final position = await _locationService.getCurrentLocation();
    if (position != null && mounted) {
      setState(() => _currentPosition = position);
      await _locationService.updateUserLocation(
          _currentUserId!, position.latitude, position.longitude);
    }
  }

  String? _normalizeAvatarUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    if (!url.startsWith('http')) url = 'https://skybyn.no$url';
    return url.replaceAll('skybyn.com', 'skybyn.no');
  }

  Future<void> _toggleGhostMode() async {
    if (_currentUserId == null) return;
    final newMode = !_isGhostMode;
    setState(() => _isGhostMode = newMode);
    try {
      final response = await globalAuthClient.post(
        Uri.parse(ApiConstants.updateLocationSettings),
        body: {
          'userID': _currentUserId!,
          'location_private_mode': newMode ? '1' : '0',
        },
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['responseCode'] != '1' && data['success'] != true) {
          if (mounted) setState(() => _isGhostMode = !newMode);
        }
      } else {
        if (mounted) setState(() => _isGhostMode = !newMode);
      }
    } catch (e) {
      if (mounted) setState(() => _isGhostMode = !newMode);
    }
  }

  Future<void> _setLocationShareMode(String mode) async {
    if (_currentUserId == null) return;
    final prev = _locationShareMode;
    setState(() => _locationShareMode = mode);
    try {
      final response = await globalAuthClient.post(
        Uri.parse(ApiConstants.updateLocationSettings),
        body: {
          'userID': _currentUserId!,
          'location_share_mode': mode,
        },
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['responseCode'] == '1' || data['success'] == true) {
          if (mode == 'live') {
            await _locationService.startLiveLocationTracking(_currentUserId!);
          } else {
            _locationService.stopLiveLocationTracking();
          }
        } else {
          if (mounted) setState(() => _locationShareMode = prev);
        }
      } else {
        if (mounted) setState(() => _locationShareMode = prev);
      }
    } catch (e) {
      if (mounted) setState(() => _locationShareMode = prev);
    }
  }

  Future<void> _loadFriendsLocations() async {
    if (_currentUserId == null) return;
    try {
      final response = await globalAuthClient.post(
        Uri.parse(ApiConstants.friendsLocations),
        body: {'userID': _currentUserId!},
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['responseCode'] == '1' || data['success'] == true) {
          final friendsList = data['data']?['friends'] ?? data['friends'] ?? [];
          final friends =
              friendsList.map<Friend>((js) => Friend.fromJson(js)).toList();
          if (mounted) {
            setState(() => _friendsWithLocations = friends);
            _cacheFriendAvatars();
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading friends locations: $e');
    }
  }

  Future<void> _cacheFriendAvatars() async {
    for (final friend in _friendsWithLocations) {
      if (friend.latitude == null || _friendAvatarUrls.containsKey(friend.id)) {
        continue;
      }
      _friendAvatarUrls[friend.id] =
          _normalizeAvatarUrl(friend.avatar) ?? friend.avatar;
    }
  }

  Future<void> _animatedMapMove(LatLng destLocation, double destZoom) async {
    if (!mounted) return;
    await _mapReadyCompleter.future;
    if (!mounted) return;
    _moveAnimationController?.dispose();
    final latTween = Tween<double>(
        begin: _mapController.camera.center.latitude,
        end: destLocation.latitude);
    final lngTween = Tween<double>(
        begin: _mapController.camera.center.longitude,
        end: destLocation.longitude);
    final zoomTween =
        Tween<double>(begin: _mapController.camera.zoom, end: destZoom);
    final controller = AnimationController(
        duration: const Duration(milliseconds: 1000), vsync: this);
    _moveAnimationController = controller;
    final Animation<double> animation =
        CurvedAnimation(parent: controller, curve: Curves.fastOutSlowIn);
    controller.addListener(() {
      if (!mounted) return;
      _mapController.move(
        LatLng(latTween.evaluate(animation), lngTween.evaluate(animation)),
        zoomTween.evaluate(animation),
      );
    });
    animation.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        controller.dispose();
        if (_moveAnimationController == controller) {
          _moveAnimationController = null;
        }
      }
    });
    controller.forward();
  }

  void _fitBounds() {
    final positions = <LatLng>[];
    if (_currentPosition != null) {
      positions
          .add(LatLng(_currentPosition!.latitude, _currentPosition!.longitude));
    }
    for (final friend in _friendsWithLocations) {
      if (friend.latitude != null && friend.longitude != null) {
        positions.add(LatLng(friend.latitude!, friend.longitude!));
      }
    }
    if (positions.isEmpty) return;
    if (positions.length == 1) {
      _animatedMapMove(positions.first, 15.0);
      return;
    }
    final bounds = LatLngBounds.fromPoints(positions);
    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50)),
    );
  }

  Future<void> _navigateToFriend(Friend friend) async {
    if (friend.latitude == null || friend.longitude == null) return;
    final lat = friend.latitude!;
    final lng = friend.longitude!;
    final uri = Platform.isIOS
        ? Uri.parse('maps://maps.apple.com/?daddr=$lat,$lng')
        : Uri.parse('google.navigation:q=$lat,$lng');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      // Fallback to browser maps
      await launchUrl(
          Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng'));
    }
  }

  void _openChat(Friend friend) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChatScreen(friend: friend)),
    );
  }

  void _showMapSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF1E1E1E)
                  : Colors.white,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Map Settings',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                // Map Style
                Text('Map Style',
                    style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildStyleChip(context, setSheetState, 'street',
                        Icons.map_outlined, 'Street'),
                    const SizedBox(width: 8),
                    _buildStyleChip(context, setSheetState, 'dark',
                        Icons.nights_stay_outlined, 'Dark'),
                    const SizedBox(width: 8),
                    _buildStyleChip(context, setSheetState, 'satellite',
                        Icons.satellite_alt_outlined, 'Satellite'),
                  ],
                ),
                const SizedBox(height: 20),
                // Location Sharing
                Text('Location Sharing',
                    style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                _buildRadioTile(context, setSheetState, 'off',
                    Icons.location_off_outlined, 'Off', 'Not visible to friends'),
                _buildRadioTile(
                    context,
                    setSheetState,
                    'last_active',
                    Icons.location_on_outlined,
                    'Last active',
                    'Share your last known location'),
                _buildRadioTile(
                    context,
                    setSheetState,
                    'live',
                    Icons.my_location,
                    'Live',
                    'Share your real-time location'),
                const SizedBox(height: 8),
                // Ghost Mode
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ghost Mode'),
                  subtitle: const Text('Hide your marker from friends'),
                  value: _isGhostMode,
                  onChanged: (_) async {
                    await _toggleGhostMode();
                    setSheetState(() {});
                  },
                  activeColor: Colors.purple,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStyleChip(BuildContext context, StateSetter setSheetState,
      String style, IconData icon, String label) {
    final selected = _mapStyle == style;
    return GestureDetector(
      onTap: () {
        setState(() => _mapStyle = style);
        setSheetState(() {});
        _prefs?.setString(_mapStylePreferenceKey, style);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.blue : Colors.grey.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? Colors.blue : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: selected ? Colors.white : null),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: selected ? Colors.white : null,
                    fontWeight: selected ? FontWeight.bold : null)),
          ],
        ),
      ),
    );
  }

  Widget _buildRadioTile(BuildContext context, StateSetter setSheetState,
      String value, IconData icon, String title, String subtitle) {
    return RadioListTile<String>(
      contentPadding: EdgeInsets.zero,
      value: value,
      groupValue: _locationShareMode,
      title: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(title),
        ],
      ),
      subtitle: Text(subtitle,
          style: Theme.of(context).textTheme.bodySmall),
      onChanged: (v) async {
        if (v != null) {
          await _setLocationShareMode(v);
          setSheetState(() {});
        }
      },
    );
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];
    if (_currentPosition != null) {
      markers.add(
          _buildUserMarker(_currentUserId!, 'You', _currentUserAvatar, true));
    }
    for (final friend in _friendsWithLocations) {
      if (friend.latitude != null) {
        markers.add(_buildUserMarker(
            friend.id,
            friend.nickname.isNotEmpty ? friend.nickname : friend.username,
            _friendAvatarUrls[friend.id] ?? _normalizeAvatarUrl(friend.avatar),
            false,
            LatLng(friend.latitude!, friend.longitude!)));
      }
    }
    return markers;
  }

  Marker _buildUserMarker(String id, String name, String? avatar, bool isSelf,
      [LatLng? point]) {
    final markerPoint = point ??
        LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    final finalAvatarUrl = _normalizeAvatarUrl(avatar);

    return Marker(
      point: markerPoint,
      width: 50,
      height: 80,
      alignment: const Alignment(0, -0.375),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pushNamed('/profile',
                arguments: {'userId': id, 'username': name}),
            child: Container(
              width: 50,
              height: 50,
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: Colors.black),
              child: Padding(
                padding: const EdgeInsets.all(2.0),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ClipOval(
                        child: finalAvatarUrl != null &&
                                finalAvatarUrl.contains('.')
                            ? CachedNetworkImage(
                                imageUrl: finalAvatarUrl,
                                fit: BoxFit.cover,
                                placeholder: (_, __) =>
                                    Image.asset('assets/images/logo.png'),
                                errorWidget: (_, __, ___) =>
                                    Image.asset('assets/images/logo.png'),
                              )
                            : Image.asset('assets/images/logo.png'),
                      ),
                    ),
                    if (isSelf && _isGhostMode)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.purple.withOpacity(0.7),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Icon(Icons.visibility_off,
                                color: Colors.white, size: 24),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(8)),
            child: Text(name,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Widget _buildFriendAvatarBar() {
    if (_currentPosition == null && _friendsWithLocations.isEmpty) {
      return const SizedBox.shrink();
    }

    final allItems = <Map<String, dynamic>>[];
    if (_currentPosition != null) {
      allItems.add({
        'id': _currentUserId,
        'name': 'You',
        'avatar': _currentUserAvatar,
        'latitude': _currentPosition!.latitude,
        'longitude': _currentPosition!.longitude,
        'isSelf': true,
        'friend': null,
      });
    }
    for (final friend in _friendsWithLocations) {
      if (friend.latitude != null && friend.longitude != null) {
        allItems.add({
          'id': friend.id,
          'name':
              friend.nickname.isNotEmpty ? friend.nickname : friend.username,
          'avatar': _friendAvatarUrls[friend.id] ?? friend.avatar,
          'latitude': friend.latitude,
          'longitude': friend.longitude,
          'isSelf': false,
          'friend': friend,
        });
      }
    }

    return Container(
      height: 52,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: Colors.white.withOpacity(0), width: 1),
            ),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              itemCount: allItems.length,
              itemBuilder: (context, index) {
                final item = allItems[index];
                final avatarUrl = _normalizeAvatarUrl(item['avatar'] as String?);
                final isSelected = _selectedFriendId == item['id'];

                return GestureDetector(
                  onTap: () {
                    _animatedMapMove(
                      LatLng(item['latitude'] as double,
                          item['longitude'] as double),
                      15.0,
                    );
                    if (item['isSelf'] == true) {
                      setState(() => _selectedFriendId = null);
                    } else {
                      setState(() => _selectedFriendId =
                          isSelected ? null : item['id'] as String);
                    }
                  },
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: isSelected
                          ? Border.all(color: Colors.blue, width: 2)
                          : null,
                    ),
                    child: ClipOval(
                      child: avatarUrl != null && avatarUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: avatarUrl,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(
                                color: Colors.grey[300]!.withOpacity(0.5),
                                child: const Icon(Icons.person,
                                    color: Colors.white, size: 16),
                              ),
                              errorWidget: (_, __, ___) => Container(
                                color: Colors.grey[300]!.withOpacity(0.5),
                                child: const Icon(Icons.person,
                                    color: Colors.white, size: 16),
                              ),
                            )
                          : Container(
                              color: Colors.grey[300]!.withOpacity(0.5),
                              child: const Icon(Icons.person,
                                  color: Colors.white, size: 16),
                            ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFriendCard() {
    if (_selectedFriendId == null) return const SizedBox.shrink();
    final friend = _friendsWithLocations
        .where((f) => f.id == _selectedFriendId)
        .firstOrNull;
    if (friend == null) return const SizedBox.shrink();

    final avatarUrl = _normalizeAvatarUrl(
        _friendAvatarUrls[friend.id] ?? friend.avatar);
    String? distanceText;
    if (_currentPosition != null &&
        friend.latitude != null &&
        friend.longitude != null) {
      final km = _locationService.calculateDistance(_currentPosition!.latitude,
          _currentPosition!.longitude, friend.latitude!, friend.longitude!);
      distanceText = km < 1
          ? '${(km * 1000).toStringAsFixed(0)} m away'
          : '${km.toStringAsFixed(1)} km away';
    }

    final name =
        friend.nickname.isNotEmpty ? friend.nickname : friend.username;

    return GestureDetector(
      onTap: () {}, // absorb taps so map doesn't dismiss it
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.black.withOpacity(0.85)
              : Colors.white.withOpacity(0.92),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 10,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              radius: 22,
              backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                  ? NetworkImage(avatarUrl)
                  : null,
              child: avatarUrl == null || avatarUrl.isEmpty
                  ? const Icon(Icons.person)
                  : null,
            ),
            const SizedBox(width: 12),
            // Name + distance
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis),
                  if (distanceText != null)
                    Text(distanceText,
                        style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Action buttons
            _buildCardAction(Icons.chat_bubble_outline, 'Chat',
                () => _openChat(friend)),
            _buildCardAction(Icons.navigation_outlined, 'Navigate',
                () => _navigateToFriend(friend)),
            _buildCardAction(Icons.person_outline, 'Profile', () {
              Navigator.of(context).pushNamed('/profile',
                  arguments: {'userId': friend.id, 'username': friend.username});
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildCardAction(
      IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Icon(icon, size: 22),
        ),
      ),
    );
  }

  Widget _buildMapFab({
    required IconData icon,
    required VoidCallback onPressed,
    required String tooltip,
    Color? color,
  }) {
    return Container(
      width: 45,
      height: 45,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: color ?? Colors.black.withOpacity(0.6),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22.5),
          onTap: onPressed,
          child: Tooltip(
            message: tooltip,
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white));
    }

    String tileUrl;
    switch (_mapStyle) {
      case 'satellite':
        tileUrl =
            'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
        break;
      case 'dark':
        tileUrl =
            'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';
        break;
      default:
        tileUrl = 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png';
    }

    return GestureDetector(
      onTap: () {
        if (_selectedFriendId != null) {
          setState(() => _selectedFriendId = null);
        }
      },
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: _zoom,
              onMapReady: () {
                if (!_mapReadyCompleter.isCompleted) {
                  _mapReadyCompleter.complete();
                }
              },
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture && _prefs != null) {
                  _prefs!.setDouble(_lastMapLatKey, camera.center.latitude);
                  _prefs!.setDouble(_lastMapLngKey, camera.center.longitude);
                  _prefs!.setDouble(_lastMapZoomKey, camera.zoom);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: tileUrl,
                subdomains: const ['a', 'b', 'c'],
                tileProvider: NetworkTileProvider(),
                userAgentPackageName: 'no.skybyn.app',
              ),
              MarkerClusterLayerWidget(
                options: MarkerClusterLayerOptions(
                  maxClusterRadius: 45,
                  size: const Size(40, 40),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(50),
                  markers: _buildMarkers(),
                  builder: (context, markers) {
                    return Container(
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          color: Colors.blue,
                          border: Border.all(color: Colors.white, width: 2)),
                      child: Center(
                          child: Text(markers.length.toString(),
                              style:
                                  const TextStyle(color: Colors.white))),
                    );
                  },
                ),
              ),
            ],
          ),
          if (widget.showControls) ...[
            Positioned(
              top: MediaQuery.of(context).padding.top + 80,
              right: 15,
              child: Column(
                children: [
                  _buildMapFab(
                    icon: Icons.settings_outlined,
                    onPressed: _showMapSettings,
                    tooltip: 'Map Settings',
                  ),
                  _buildMapFab(
                    icon: _mapStyle == 'satellite'
                        ? Icons.map_outlined
                        : Icons.satellite_alt_outlined,
                    onPressed: () {
                      final next =
                          _mapStyle == 'satellite' ? 'street' : 'satellite';
                      setState(() => _mapStyle = next);
                      _prefs?.setString(_mapStylePreferenceKey, next);
                    },
                    tooltip: _mapStyle == 'satellite'
                        ? 'Switch to Street'
                        : 'Switch to Satellite',
                  ),
                  if (_friendsWithLocations.isNotEmpty)
                    _buildMapFab(
                      icon: Icons.people,
                      onPressed: _fitBounds,
                      tooltip: 'Show All Friends',
                    ),
                ],
              ),
            ),
            // Friend expanded card
            Positioned(
              bottom: 192.0,
              left: 0,
              right: 0,
              child: _buildFriendCard(),
            ),
            // Avatar bar
            Positioned(
              bottom: 130.0,
              left: 0,
              right: 0,
              child: _buildFriendAvatarBar(),
            ),
          ],
        ],
      ),
    );
  }
}
