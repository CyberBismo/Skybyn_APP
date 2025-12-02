import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:ui' as ui show ImageFilter;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import '../widgets/header.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/background_gradient.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../config/constants.dart';
import '../models/friend.dart';
import '../widgets/translated_text.dart';
import '../utils/translation_keys.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MapScreen extends StatefulWidget {
  final VoidCallback? onReturnToHome;
  
  const MapScreen({super.key, this.onReturnToHome});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final AuthService _authService = AuthService();
  final LocationService _locationService = LocationService();
  final MapController _mapController = MapController();
  String? _currentUserId;
  Position? _currentPosition;
  String? _currentUserAvatar;
  List<Friend> _friendsWithLocations = [];
  bool _isLoading = true;
  Timer? _refreshTimer;
  // Only cache avatar URLs, not entire marker images
  final Map<String, String> _friendAvatarUrls = {};
  final GlobalKey _notificationButtonKey = GlobalKey();
  LatLng _center = const LatLng(59.9139, 10.7522); // Default to Oslo, Norway
  double _zoom = 3.0;
  
  // Menu state
  bool _locationPrivateMode = false;
  String _locationShareMode = 'off'; // 'off', 'last_active', 'live'
  bool _useSatelliteView = false; // Toggle between roadmap and satellite view
  static const String _mapLayerPreferenceKey = 'map_use_satellite_view';
  
  // Cache manager for map tiles (30 days cache, 200MB max size)
  static final CacheManager _tileCacheManager = CacheManager(
    Config(
      'map_tiles_cache',
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 10000,
      repo: JsonCacheInfoRepository(databaseName: 'map_tiles_cache'),
    ),
  );

  @override
  void initState() {
    super.initState();
    // Request location permission when navigating to map screen
    _requestLocationPermission();
    // Start preloading location immediately (non-blocking)
    _preloadLocation();
    _initializeMap();
  }

  Future<void> _requestLocationPermission() async {
    try {
      final hasPermission = await _locationService.requestLocationPermission();
      if (hasPermission) {
        print('Location permission granted');
      } else {
        print('Location permission denied');
      }
    } catch (e) {
      print('Error requesting location permission: $e');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Load saved preference when dependencies change (e.g., theme changes)
    // This ensures the saved preference is respected
    _loadMapLayerPreference();
  }
  
  /// Load the saved map layer preference
  Future<void> _loadMapLayerPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedPreference = prefs.getBool(_mapLayerPreferenceKey);
      if (savedPreference != null) {
        setState(() {
          _useSatelliteView = savedPreference;
        });
      }
    } catch (e) {
      // Silently fail if loading preference fails
      print('Error loading map layer preference: $e');
    }
  }
  
  /// Save the current map layer preference
  Future<void> _saveMapLayerPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_mapLayerPreferenceKey, _useSatelliteView);
    } catch (e) {
      // Silently fail if saving preference fails
      print('Error saving map layer preference: $e');
    }
  }

  Future<void> _preloadLocation() async {
    // Preload location in background to speed up map loading
    try {
      await _locationService.getCurrentLocation();
      print('Location preloaded');
    } catch (e) {
      print('Error preloading location: $e');
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _initializeMap() async {
    print('=== Initializing map ===');
    
    // Load saved map layer preference
    await _loadMapLayerPreference();
    
    final userId = await _authService.getStoredUserId();
    if (userId == null) {
      print('No user ID found, stopping initialization');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }
    print('User ID: $userId');

    // Get current user profile for avatar
    final userProfile = await _authService.getStoredUserProfile();
    String? avatarUrl;
    if (userProfile != null && userProfile.avatar.isNotEmpty) {
      avatarUrl = userProfile.avatar;
      if (!avatarUrl.startsWith('http')) {
        avatarUrl = 'https://skybyn.no$avatarUrl';
      } else {
        // Fix domain if it's skybyn.com instead of skybyn.no
        avatarUrl = avatarUrl.replaceAll('skybyn.com', 'skybyn.no');
      }
      
      // Check if avatar URL is a known invalid/default URL that should use local asset
      if (avatarUrl.contains('logo_faded_clean.png') || 
          avatarUrl.contains('logo.png') ||
          avatarUrl.endsWith('/assets/images/logo.png') ||
          avatarUrl.endsWith('/assets/images/logo_faded_clean.png')) {
        print('Avatar URL is a default/logo URL, using local asset instead');
        avatarUrl = null; // Will use local logo.png asset
      }
    }
    if (avatarUrl == null || avatarUrl.isEmpty) {
      // Use local asset instead of URL for default
      avatarUrl = null; // Will use local logo.png asset
    }

    print('Current user avatar URL: $avatarUrl');
    
    // Preload avatar image to cache (non-blocking) - only if it's a valid URL
    if (avatarUrl != null && avatarUrl.isNotEmpty && avatarUrl.startsWith('http')) {
      try {
        final imageProvider = CachedNetworkImageProvider(avatarUrl);
        imageProvider.resolve(const ImageConfiguration());
        print('Avatar image preloaded to cache');
      } catch (e) {
        print('Error preloading avatar: $e');
      }
    }

    // Load privacy mode and location share mode from user profile
    bool locationPrivateMode = false;
    String locationShareMode = 'off';
    if (userProfile != null) {
      try {
        final response = await http.post(
          Uri.parse(ApiConstants.profile),
          body: {'userID': userId},
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['responseCode'] == '1' || data['success'] == true) {
            final userData = data['data'] ?? data;
            locationPrivateMode = userData['location_private_mode']?.toString() == '1' || 
                                 userData['location_private_mode'] == true;
            locationShareMode = userData['location_share_mode']?.toString() ?? 'off';
          }
        }
      } catch (e) {
        // Silently handle errors
      }
    }

    if (mounted) {
      setState(() {
        _currentUserId = userId;
        _currentUserAvatar = avatarUrl;
        _locationPrivateMode = locationPrivateMode;
        _locationShareMode = locationShareMode;
      });
    }

    // Start getting location early (in parallel with other operations)
    print('Getting current user location...');
    final locationFuture = _locationService.getCurrentLocation();

    // Create current user marker image (will be recreated after position is set)
    // Avatar is cached via CachedNetworkImageProvider, markers built dynamically
    if (_currentUserAvatar != null) {
      print('Current user avatar URL: $_currentUserAvatar');
    } else {
      print('No avatar URL available');
    }

    // Wait for location (may already be ready if preloaded)
    final position = await locationFuture;
    if (position != null && mounted) {
      print('Location obtained: ${position.latitude}, ${position.longitude}');
      setState(() {
        _currentPosition = position;
        _center = LatLng(position.latitude, position.longitude);
        _zoom = 15.0;
      });
      // Recreate marker after position is set
      // Avatar is cached via CachedNetworkImageProvider, markers built dynamically
    } else {
      print('No location obtained');
    }

    // Ensure loading is set to false so map can render
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }

    // Load friends locations
    print('Loading friends locations...');
    await _loadFriendsLocations();

    // Set up periodic refresh for live locations
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _loadFriendsLocations();
    });

    // Fit bounds after initial load - only once after all data is loaded
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fitBounds();
        // Force rebuild to show markers
        setState(() {});
      });
    }
  }

  Future<void> _loadFriendsLocations() async {
    if (_currentUserId == null) return;

    try {
      final response = await http.post(
        Uri.parse(ApiConstants.friendsLocations),
        body: {
          'userID': _currentUserId!,
        },
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['responseCode'] == '1' || data['success'] == true) {
          final friendsList = data['data']?['friends'] ?? data['friends'] ?? [];
          final friends = friendsList.map<Friend>((json) => Friend.fromJson(json)).toList();
          
          if (mounted) {
            setState(() {
              _friendsWithLocations = friends;
              // _isLoading already set to false earlier
            });
          }

          // Cache friend avatar URLs
          await _cacheFriendAvatars();
          
          // Update map after creating markers (don't call fitBounds here, it's called in _initializeMap)
          if (mounted) {
            setState(() {});
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      print('Error loading friends locations: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _cacheFriendAvatars() async {
    // Cache friend avatar URLs for marker building
    for (final friend in _friendsWithLocations) {
      if (friend.latitude == null || friend.longitude == null) continue;
      
      final markerId = friend.id;
      if (_friendAvatarUrls.containsKey(markerId)) continue;

      // Store avatar URL for marker building
      String avatarUrl = friend.avatar;
      if (avatarUrl.isNotEmpty && !avatarUrl.startsWith('http')) {
        avatarUrl = 'https://skybyn.no$avatarUrl';
      } else if (avatarUrl.contains('skybyn.com')) {
        avatarUrl = avatarUrl.replaceAll('skybyn.com', 'skybyn.no');
      }
      
      // Preload avatar to cache
      if (avatarUrl.isNotEmpty && avatarUrl.startsWith('http') &&
          !avatarUrl.contains('logo_faded_clean.png') &&
          !avatarUrl.contains('logo.png')) {
        try {
          final imageProvider = CachedNetworkImageProvider(avatarUrl);
          imageProvider.resolve(const ImageConfiguration());
        } catch (e) {
          // Silently handle errors
        }
      }
      
      _friendAvatarUrls[markerId] = avatarUrl;
    }
  }

  // Marker image creation functions removed - markers are now built dynamically with Flutter widgets
  // Only avatar images are cached via CachedNetworkImageProvider

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];
    print('Building markers - position: $_currentPosition');

    // Add current user marker with avatar (built dynamically with widgets)
    if (_currentPosition != null) {
      markers.add(
        Marker(
          point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          width: 50,
          height: 80,
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Marker with black background and avatar
              Container(
                width: 50,
                height: 50,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black,
                ),
                child: Center(
                  child: SizedBox(
                    width: 45,
                    height: 45,
                    child: ClipOval(
                      child: Padding(
                        padding: const EdgeInsets.all(2.0),
                        child: _currentUserAvatar != null && 
                            _currentUserAvatar!.startsWith('http') &&
                            !_currentUserAvatar!.contains('logo_faded_clean.png') &&
                            !_currentUserAvatar!.contains('logo.png') &&
                            !_currentUserAvatar!.endsWith('/assets/images/logo.png') &&
                            !_currentUserAvatar!.endsWith('/assets/images/logo_faded_clean.png')
                            ? CachedNetworkImage(
                                imageUrl: _currentUserAvatar!.replaceAll('skybyn.com', 'skybyn.no'),
                                width: 45,
                                height: 45,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Image.asset(
                                  'assets/images/logo.png',
                                  width: 45,
                                  height: 45,
                                  fit: BoxFit.cover,
                                ),
                                errorWidget: (context, url, error) => Image.asset(
                                  'assets/images/logo.png',
                                  width: 45,
                                  height: 45,
                                  fit: BoxFit.cover,
                                ),
                              )
                            : Image.asset(
                                'assets/images/logo.png',
                                width: 45,
                                height: 45,
                                fit: BoxFit.cover,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'You',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Add friends markers
    for (final friend in _friendsWithLocations) {
      if (friend.latitude == null || friend.longitude == null) continue;

      final position = LatLng(friend.latitude!, friend.longitude!);
      
      // Get display name (nickname or username)
      final displayName = friend.nickname.isNotEmpty ? friend.nickname : friend.username;
      
      // Get avatar URL (cached separately)
      final avatarUrl = _friendAvatarUrls[friend.id] ?? friend.avatar;
      final finalAvatarUrl = avatarUrl.isNotEmpty && !avatarUrl.startsWith('http')
          ? 'https://skybyn.no$avatarUrl'
          : avatarUrl.replaceAll('skybyn.com', 'skybyn.no');
      
      // Build marker dynamically with widgets (only avatar is cached)
      final hasValidAvatar = finalAvatarUrl.isNotEmpty && 
          finalAvatarUrl.startsWith('http') &&
          !finalAvatarUrl.contains('logo_faded_clean.png') &&
          !finalAvatarUrl.contains('logo.png');
      
      markers.add(
        Marker(
          point: position,
          width: 50,
          height: 80,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Marker with black background and avatar
              Container(
                width: 50,
                height: 50,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black,
                ),
                child: Center(
                  child: SizedBox(
                    width: 45,
                    height: 45,
                    child: ClipOval(
                      child: Padding(
                        padding: const EdgeInsets.all(2.0),
                        child: hasValidAvatar
                            ? CachedNetworkImage(
                                imageUrl: finalAvatarUrl,
                                width: 45,
                                height: 45,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Image.asset(
                                  'assets/images/logo.png',
                                  width: 45,
                                  height: 45,
                                  fit: BoxFit.cover,
                                ),
                                errorWidget: (context, url, error) => Image.asset(
                                  'assets/images/logo.png',
                                  width: 45,
                                  height: 45,
                                  fit: BoxFit.cover,
                                ),
                              )
                            : Image.asset(
                                'assets/images/logo.png',
                                width: 45,
                                height: 45,
                                fit: BoxFit.cover,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
      
    }

    return markers;
  }

  void _fitBounds() {
    final positions = <LatLng>[];
    
    if (_currentPosition != null) {
      positions.add(LatLng(_currentPosition!.latitude, _currentPosition!.longitude));
    }

    for (final friend in _friendsWithLocations) {
      if (friend.latitude != null && friend.longitude != null) {
        positions.add(LatLng(friend.latitude!, friend.longitude!));
      }
    }

    if (positions.isEmpty) {
      // Default to Oslo if no positions
      _mapController.move(_center, _zoom);
      return;
    }

    // Calculate bounds
    double minLat = positions.first.latitude;
    double maxLat = positions.first.latitude;
    double minLng = positions.first.longitude;
    double maxLng = positions.first.longitude;

    for (final pos in positions) {
      minLat = minLat < pos.latitude ? minLat : pos.latitude;
      maxLat = maxLat > pos.latitude ? maxLat : pos.latitude;
      minLng = minLng < pos.longitude ? minLng : pos.longitude;
      maxLng = maxLng > pos.longitude ? maxLng : pos.longitude;
    }

    // If all positions are the same (single point), add a small offset for bounds
    if (minLat == maxLat && minLng == maxLng) {
      const offset = 0.01; // ~1km offset
      minLat -= offset;
      maxLat += offset;
      minLng -= offset;
      maxLng += offset;
    }

    // Calculate center and zoom
    final center = LatLng(
      (minLat + maxLat) / 2,
      (minLng + maxLng) / 2,
    );
    
    // Calculate appropriate zoom level based on bounds
    final latDiff = maxLat - minLat;
    final lngDiff = maxLng - minLng;
    final maxDiff = latDiff > lngDiff ? latDiff : lngDiff;
    
    double zoom = 10.0;
    if (maxDiff > 0.1) {
      zoom = 8.0;
    } else if (maxDiff > 0.05) {
      zoom = 9.0;
    } else if (maxDiff > 0.02) {
      zoom = 10.0;
    } else if (maxDiff > 0.01) {
      zoom = 11.0;
    } else if (maxDiff > 0.005) {
      zoom = 12.0;
    } else {
      zoom = 13.0;
    }

    _mapController.move(center, zoom);
  }

  void _centerOnCurrentLocation() async {
    // Use cached position for instant response, fallback to getting new location
    if (_currentPosition != null) {
      // Move immediately using cached position
      _mapController.move(
        LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        15.0,
      );
    }
    
    // Optionally update location in background for next time
    _locationService.getCurrentLocation().then((position) {
      if (position != null && mounted) {
        setState(() {
          _currentPosition = position;
        });
      }
    }).catchError((e) {
      // Silently handle errors - we already moved to cached position
    });
  }

  Future<void> _togglePrivacyMode() async {
    if (_currentUserId == null) return;

    final newValue = !_locationPrivateMode;
    setState(() {
      _locationPrivateMode = newValue;
    });

    try {
      final response = await http.post(
        Uri.parse(ApiConstants.updateLocationSettings),
        body: {
          'userID': _currentUserId!,
          'location_share_mode': _locationShareMode, // Preserve existing mode
          'location_private_mode': newValue ? '1' : '0',
        },
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['responseCode'] != '1' && data['success'] != true) {
          // Revert on failure
          setState(() {
            _locationPrivateMode = !newValue;
          });
        }
      }
    } catch (e) {
      // Revert on error
      setState(() {
        _locationPrivateMode = !newValue;
      });
    }
  }

  String _getTileUrl() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    // Use satellite view if toggled on
    if (_useSatelliteView) {
      return 'https://mt{s}.google.com/vt/lyrs=s&x={x}&y={y}&z={z}'; // Satellite view
    }
    
    // Default to street map (roadmap)
    // Use dark street map in dark mode, regular street map in light mode
    if (isDarkMode) {
      // Dark street map for dark mode
      return 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';
    } else {
      // Regular street map for light mode
      return 'https://mt{s}.google.com/vt/lyrs=m&x={x}&y={y}&z={z}'; // Roadmap view
    }
  }

  List<String> _getSubdomains() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    // CartoDB uses subdomains a, b, c, d for dark street map
    // Use CartoDB subdomains when in dark mode and not using satellite (using dark street map)
    if (isDarkMode && !_useSatelliteView) {
      return const ['a', 'b', 'c', 'd'];
    }
    
    // Google Maps uses subdomains 0-3 for satellite and regular maps
    return const ['0', '1', '2', '3'];
  }

  Widget _buildMapMenu(BuildContext context) {
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final headerHeight = statusBarHeight;
    
    return Positioned(
      top: headerHeight + 8, // Position just below the header with 8px spacing
      left: 0,
      right: 0,
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.2),
                borderRadius: BorderRadius.circular(32),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Satellite/Roadmap toggle
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _useSatelliteView = !_useSatelliteView;
                        });
                        // Save the preference when user toggles
                        _saveMapLayerPreference();
                      },
                      borderRadius: BorderRadius.circular(24),
                      child: Container(
                        width: 30,
                        height: 30,
                        child: Icon(
                          _useSatelliteView ? Icons.satellite : Icons.map,
                          color: _useSatelliteView ? Colors.green : Colors.white,
                          size: 30,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 30),
                  // Privacy mode button
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _togglePrivacyMode,
                      borderRadius: BorderRadius.circular(24),
                      child: Container(
                        width: 30,
                        height: 30,
                        child: Center(
                          child: FaIcon(
                            _locationPrivateMode ? FontAwesomeIcons.userSecret : FontAwesomeIcons.eye,
                            color: _locationPrivateMode ? Colors.orange : Colors.white,
                            size: 30,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('MapScreen'),
      child: Scaffold(
        extendBodyBehindAppBar: true,
        extendBody: true,
        appBar: CustomAppBar(
        logoPath: 'assets/images/logo.png',
        onLogoPressed: () {
          Navigator.of(context).pushReplacementNamed('/home');
        },
        onSearchFormToggle: null,
        isSearchFormVisible: false,
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.only(
          bottom: Theme.of(context).platform == TargetPlatform.iOS ? 8.0 : 8.0 + MediaQuery.of(context).padding.bottom,
        ),
        child: CustomBottomNavigationBar(
          onAddPressed: () {},
          notificationButtonKey: _notificationButtonKey,
          showReturnButton: true,
          onReturnPressed: () {
            // Use callback if provided (when used in HomeScreen), otherwise use Navigator
            if (widget.onReturnToHome != null) {
              widget.onReturnToHome!();
            } else {
              Navigator.of(context).pushReplacementNamed('/home');
            }
          },
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Calculate app bar height for background overlay
          final statusBarHeight = MediaQuery.of(context).padding.top;
          final headerHeight = statusBarHeight;
          const bottomNavBarHeight = 85.0;
          
          return FutureBuilder<String?>(
            future: _authService.getStoredUserId(),
            builder: (context, snapshot) {
              final isLoggedIn = snapshot.hasData && snapshot.data != null;
              
              return Stack(
                children: [
                  // Background gradient with clouds (only when logged in)
                  Positioned.fill(
                    child: BackgroundGradient(showClouds: isLoggedIn),
                  ),
                  // Full screen map
                  SizedBox.expand(
                child: FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: _center,
                          initialZoom: _zoom,
                          minZoom: 3.0,
                          maxZoom: 18.0,
                          interactionOptions: const InteractionOptions(
                            flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag | InteractiveFlag.scrollWheelZoom,
                          ),
                          onTap: (tapPosition, point) {
                            print('Map tapped at: ${point.latitude}, ${point.longitude}');
                          },
                          onMapReady: () {
                            print('Map is ready');
                            // Force map to render
                            if (mounted && _currentPosition != null) {
                              _mapController.move(
                                LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                                _zoom,
                              );
                            }
                          },
                        ),
                        children: [
                          // Google Maps tile layer - switches between roadmap and satellite
                          TileLayer(
                            urlTemplate: _getTileUrl(),
                            userAgentPackageName: 'no.skybyn.app',
                            maxZoom: 19,
                            subdomains: _getSubdomains(),
                            // Enable tile caching using custom provider
                            tileProvider: _CachedTileProvider(_tileCacheManager),
                          ),
                          // Markers layer
                          MarkerLayer(
                            markers: _buildMarkers(),
                          ),
                        ],
                      ),
                    ),
          // Show loading message while fetching location
          if (_isLoading || (_currentPosition == null && _currentUserAvatar != null))
            Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Show cached avatar if available, otherwise show logo
                          if (_currentUserAvatar != null && 
                              _currentUserAvatar!.startsWith('http') &&
                              !_currentUserAvatar!.contains('logo_faded_clean.png') &&
                              !_currentUserAvatar!.contains('logo.png') &&
                              !_currentUserAvatar!.endsWith('/assets/images/logo.png') &&
                              !_currentUserAvatar!.endsWith('/assets/images/logo_faded_clean.png'))
                            ClipOval(
                              child: CachedNetworkImage(
                                imageUrl: _currentUserAvatar!.replaceAll('skybyn.com', 'skybyn.no'),
                                width: 45,
                                height: 45,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => ClipOval(
                                  child: Image.asset(
                                    'assets/images/logo.png',
                                    width: 45,
                                    height: 45,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                errorWidget: (context, url, error) {
                                  print('Error loading avatar in loading message: $error');
                                  return ClipOval(
                                    child: Image.asset(
                                      'assets/images/logo.png',
                                      width: 45,
                                      height: 45,
                                      fit: BoxFit.cover,
                                    ),
                                  );
                                },
                              ),
                            )
                          else
                            ClipOval(
                              child: Image.asset(
                                'assets/images/logo.png',
                                width: 45,
                                height: 45,
                                fit: BoxFit.cover,
                              ),
                            ),
                          const SizedBox(height: 12),
                          const Text(
                            'Loading location...',
                            style: TextStyle(color: Colors.white, fontSize: 16),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
          // Show message overlay if no locations available (only after loading is complete)
          if (!_isLoading && _currentPosition == null && _friendsWithLocations.isEmpty && _currentUserAvatar == null)
            Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.location_off, size: 48, color: Colors.white),
                          const SizedBox(height: 12),
                          TranslatedText(
                            TranslationKeys.noLocationsAvailable,
                            style: const TextStyle(color: Colors.white, fontSize: 16),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
          // Loading indicator overlay
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),
          // Floating action button to center on current location
          Positioned(
                bottom: 140,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _centerOnCurrentLocation,
                            borderRadius: BorderRadius.circular(30),
                            child: Container(
                              width: 56,
                              height: 56,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.my_location,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          // Map menu on the right side
          if (!_isLoading) _buildMapMenu(context),
          // Header background overlay (between map and app bar)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: headerHeight,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: Theme.of(context).brightness == Brightness.dark
                      ? [
                          const Color.fromRGBO(11, 19, 43, 1.0), // Midnight navy (matches BackgroundGradient)
                          const Color.fromRGBO(0, 8, 20, 1.0), // Near-black midnight blue
                        ]
                      : [
                          const Color.fromRGBO(72, 198, 239, 1.0), // Light blue (webLightPrimary)
                          const Color.fromRGBO(111, 134, 214, 1.0), // Blue (webLightSecondary)
                        ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              width: double.infinity,
            ),
          ),
          // Bottom nav background overlay (between map and bottom nav)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: bottomNavBarHeight,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: Theme.of(context).brightness == Brightness.dark
                      ? [
                          const Color.fromRGBO(11, 19, 43, 1.0), // Midnight navy (matches BackgroundGradient)
                          const Color.fromRGBO(0, 8, 20, 1.0), // Near-black midnight blue
                        ]
                      : [
                          const Color.fromRGBO(72, 198, 239, 1.0), // Light blue (webLightPrimary)
                          const Color.fromRGBO(111, 134, 214, 1.0), // Blue (webLightSecondary)
                        ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              width: double.infinity,
            ),
          ),
                ],
              );
            },
          );
        },
      ),
      ),
    );
  }
}

/// Preload map screen data when app opens
/// This can be called from main.dart to preload map data on app startup
Future<void> preloadMapScreen() async {
  try {
    final authService = AuthService();
    final userId = await authService.getStoredUserId();
    
    if (userId == null) {
      return; // User not logged in
    }
    
    // Preload location
    final locationService = LocationService();
    await locationService.getCurrentLocation().catchError((e) {
      return null; // Return null on error
    });
    
    // Preload user profile and avatar
    final userProfile = await authService.getStoredUserProfile();
    if (userProfile != null && userProfile.avatar.isNotEmpty) {
      String avatarUrl = userProfile.avatar;
      if (!avatarUrl.startsWith('http')) {
        avatarUrl = 'https://skybyn.no$avatarUrl';
      } else {
        avatarUrl = avatarUrl.replaceAll('skybyn.com', 'skybyn.no');
      }
      
      // Preload avatar image to cache
      if (avatarUrl.isNotEmpty && 
          avatarUrl.startsWith('http') &&
          !avatarUrl.contains('logo_faded_clean.png') &&
          !avatarUrl.contains('logo.png')) {
        try {
          final imageProvider = CachedNetworkImageProvider(avatarUrl);
          imageProvider.resolve(const ImageConfiguration());
        } catch (e) {
          // Silently handle errors
        }
      }
    }
    
    // Preload friends locations
    Future.delayed(const Duration(seconds: 1), () async {
      try {
        final response = await http.post(
          Uri.parse(ApiConstants.friendsLocations),
          body: {'userID': userId},
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        ).timeout(const Duration(seconds: 10));
        
        if (response.statusCode == 200) {
          print('Map screen data preloaded on app startup');
        }
      } catch (e) {
        // Silently handle errors
      }
    });
  } catch (e) {
    // Silently handle errors - preloading is optional
  }
}

// _ImageMarkerPainter removed - markers are now built dynamically with Flutter widgets

// Custom tile provider with caching support
class _CachedTileProvider extends TileProvider {
  final CacheManager cacheManager;

  _CachedTileProvider(this.cacheManager);

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final url = getTileUrl(coordinates, options);
    return CachedNetworkImageProvider(
      url,
      cacheManager: cacheManager,
    );
  }
}

