import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../utils/http_client.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../config/constants.dart';
import '../models/friend.dart';

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

class _MapViewState extends State<MapView> with TickerProviderStateMixin {
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
  AnimationController? _moveAnimationController;
  final Map<String, String> _friendAvatarUrls = {};

  LatLng _center = const LatLng(59.9139, 10.7522); // Default to Oslo
  double _zoom = 3.0;
  bool _useSatelliteView = false;
  bool _isGhostMode = false;

  static const String _mapLayerPreferenceKey = 'map_use_satellite_view';
  static const String _lastMapLatKey = 'last_map_latitude';
  static const String _lastMapLngKey = 'last_map_longitude';
  static const String _lastMapZoomKey = 'last_map_zoom';

  @override
  void initState() {
    super.initState();
    _mapController = widget.mapController ?? MapController();
    _initializeMap();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _moveAnimationController?.dispose();
    if (widget.mapController == null) {
      _mapController.dispose();
    }
    super.dispose();
  }

  Future<void> _initializeMap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _useSatelliteView = prefs.getBool(_mapLayerPreferenceKey) ?? false;

      final userId = await _authService.getStoredUserId();
      if (userId == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final userProfile = await _authService.getStoredUserProfile();
      String? avatarUrl;
      if (userProfile != null && userProfile.avatar.isNotEmpty) {
        avatarUrl = userProfile.avatar;
        if (!avatarUrl.startsWith('http')) {
          avatarUrl = 'https://skybyn.no$avatarUrl';
        }
        avatarUrl = avatarUrl.replaceAll('skybyn.com', 'skybyn.no');
      }

      if (mounted) {
        setState(() {
          _currentUserId = userId;
          _currentUserAvatar = avatarUrl;
          _isGhostMode = userProfile?.locationPrivateMode == '1' ||
              userProfile?.locationPrivateMode == true;
        });
      }

      // Load cached position
      final cachedPosition = await _locationService.getLastKnownLocation();
      if (mounted) {
        setState(() {
          if (cachedPosition != null) {
            _currentPosition = cachedPosition;
            _center = LatLng(cachedPosition.latitude, cachedPosition.longitude);
          }
          final savedZoom = prefs.getDouble(_lastMapZoomKey);
          _zoom = savedZoom ?? 15.0;
          _isLoading = false;
        });
      }

      // Accurate location in background
      _locationService.getCurrentLocation().then((position) {
        if (position != null && mounted) {
          setState(() {
            _currentPosition = position;
            // Only move map if we haven't already set a center from cache/move
            if (prefs.getDouble(_lastMapLatKey) == null) {
              _center = LatLng(position.latitude, position.longitude);
              _zoom = 15.0;
              _animatedMapMove(_center, _zoom);
            }
          });
        }
      });

      await _loadFriendsLocations();
      _refreshTimer = Timer.periodic(
          const Duration(seconds: 10), (_) => _loadFriendsLocations());
    } catch (e) {
      debugPrint('Error initializing map: $e');
      if (mounted) setState(() => _isLoading = false);
    }
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
          // Revert if failed
          if (mounted) setState(() => _isGhostMode = !newMode);
        }
      } else {
        if (mounted) setState(() => _isGhostMode = !newMode);
      }
    } catch (e) {
      if (mounted) setState(() => _isGhostMode = !newMode);
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
      String url = friend.avatar;
      if (url.isNotEmpty && !url.startsWith('http')) {
        url = 'https://skybyn.no$url';
      }
      _friendAvatarUrls[friend.id] = url.replaceAll('skybyn.com', 'skybyn.no');
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
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(50),
      ),
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
            _friendAvatarUrls[friend.id] ?? friend.avatar,
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
    String? finalAvatarUrl = avatar;
    if (finalAvatarUrl != null && !finalAvatarUrl.startsWith('http')) {
      finalAvatarUrl = 'https://skybyn.no$finalAvatarUrl';
    }
    finalAvatarUrl = finalAvatarUrl?.replaceAll('skybyn.com', 'skybyn.no');

    return Marker(
      point: markerPoint,
      width: 50,
      height: 80,
      alignment: const Alignment(
          0, -0.375), // Center the circular avatar on the coordinate
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
                            child: Icon(
                              Icons.visibility_off,
                              color: Colors.white,
                              size: 24,
                            ),
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
    // Show bar if at least the user is available
    if (_currentPosition == null && _friendsWithLocations.isEmpty) {
      return const SizedBox.shrink();
    }

    final allItems = <Map<String, dynamic>>[];
    // Add self
    if (_currentPosition != null) {
      allItems.add({
        'id': _currentUserId,
        'name': 'You',
        'avatar': _currentUserAvatar,
        'latitude': _currentPosition!.latitude,
        'longitude': _currentPosition!.longitude,
        'isSelf': true,
      });
    }
    // Add friends
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
              border: Border.all(
                color: Colors.white.withOpacity(0),
                width: 1,
              ),
            ),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              itemCount: allItems.length,
              itemBuilder: (context, index) {
                final item = allItems[index];
                final avatarUrl = item['avatar'] as String?;
                final hasValidAvatar =
                    avatarUrl != null && avatarUrl.isNotEmpty;

                return GestureDetector(
                  onTap: () {
                    _animatedMapMove(
                      LatLng(item['latitude'] as double,
                          item['longitude'] as double),
                      15.0,
                    );
                  },
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(shape: BoxShape.circle),
                    child: ClipOval(
                      child: hasValidAvatar
                          ? CachedNetworkImage(
                              imageUrl: avatarUrl.startsWith('http')
                                  ? avatarUrl
                                  : 'https://skybyn.no${avatarUrl.startsWith('/') ? '' : '/'}$avatarUrl'
                                      .replaceAll('skybyn.com', 'skybyn.no'),
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color: Colors.grey[300]!.withOpacity(0.5),
                                child: const Icon(Icons.person,
                                    color: Colors.white, size: 16),
                              ),
                              errorWidget: (context, url, error) => Container(
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

    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    String tileUrl;
    if (_useSatelliteView) {
      tileUrl =
          'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
    } else {
      tileUrl = isDarkMode
          ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
          : 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png';
    }

    return Stack(
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
              if (hasGesture) {
                final center = camera.center;
                final zoom = camera.zoom;
                SharedPreferences.getInstance().then((prefs) {
                  prefs.setDouble(_lastMapLatKey, center.latitude);
                  prefs.setDouble(_lastMapLngKey, center.longitude);
                  prefs.setDouble(_lastMapZoomKey, zoom);
                });
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
                            style: const TextStyle(color: Colors.white))),
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
                  icon: _useSatelliteView
                      ? Icons.map_outlined
                      : Icons.satellite_alt_outlined,
                  onPressed: () {
                    setState(() {
                      _useSatelliteView = !_useSatelliteView;
                    });
                    SharedPreferences.getInstance().then((prefs) => prefs
                        .setBool(_mapLayerPreferenceKey, _useSatelliteView));
                  },
                  tooltip: _useSatelliteView
                      ? 'Switch to Street'
                      : 'Switch to Satellite',
                ),
                _buildMapFab(
                  icon: _isGhostMode ? Icons.visibility_off : Icons.visibility,
                  onPressed: _toggleGhostMode,
                  tooltip:
                      _isGhostMode ? 'Ghost Mode Active' : 'Ghost Mode Off',
                  color: _isGhostMode
                      ? Colors.purple.withOpacity(0.8)
                      : Colors.black.withOpacity(0.6),
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
          Positioned(
            bottom: 145,
            left: 0,
            right: 0,
            child: Center(
              child: _buildMapFab(
                icon: Icons.my_location,
                onPressed: () {
                  if (_currentPosition != null) {
                    _animatedMapMove(
                        LatLng(_currentPosition!.latitude,
                            _currentPosition!.longitude),
                        15.0);
                  }
                },
                tooltip: 'My Location',
              ),
            ),
          ),
          Positioned(
            bottom: 85,
            left: 0,
            right: 0,
            child: _buildFriendAvatarBar(),
          ),
        ],
      ],
    );
  }
}
