import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:ui' as ui show Image, ImageByteFormat, instantiateImageCodec, PictureRecorder, Canvas, Paint, Path, Rect, Offset, PaintingStyle, ImageFilter;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'dart:typed_data';
import '../widgets/background_gradient.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/custom_bottom_navigation_bar.dart';
import '../widgets/app_colors.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../config/constants.dart';
import '../models/friend.dart';
import '../widgets/translated_text.dart';
import '../utils/translation_keys.dart';
import '../services/translation_service.dart';
import 'package:cached_network_image/cached_network_image.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final AuthService _authService = AuthService();
  final LocationService _locationService = LocationService();
  final MapController _mapController = MapController();
  final Distance _distance = const Distance();
  String? _currentUserId;
  Position? _currentPosition;
  String? _currentUserAvatar;
  List<Friend> _friendsWithLocations = [];
  bool _isLoading = true;
  Timer? _refreshTimer;
  final Map<String, ui.Image> _customMarkerImages = {};
  ui.Image? _currentUserMarkerImage;
  final GlobalKey _notificationButtonKey = GlobalKey();
  LatLng _center = const LatLng(59.9139, 10.7522); // Default to Oslo, Norway
  double _zoom = 10.0;
  
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
    _initializeMap();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _initializeMap() async {
    final userId = await _authService.getStoredUserId();
    if (userId == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    // Get current user profile for avatar
    final userProfile = await _authService.getStoredUserProfile();
    String? avatarUrl;
    if (userProfile != null && userProfile.avatar.isNotEmpty) {
      avatarUrl = userProfile.avatar;
      if (!avatarUrl.startsWith('http')) {
        avatarUrl = 'https://skybyn.no$avatarUrl';
      }
    }
    if (avatarUrl == null || avatarUrl.isEmpty) {
      avatarUrl = 'https://skybyn.no/assets/images/logo.png';
    }

    print('Current user avatar URL: $avatarUrl');

    setState(() {
      _currentUserId = userId;
      _currentUserAvatar = avatarUrl;
    });

    // Create current user marker image
    if (_currentUserAvatar != null) {
      await _createCurrentUserMarker();
    }

    // Get current user location
    final position = await _locationService.getCurrentLocation();
    if (position != null) {
      setState(() {
        _currentPosition = position;
        _center = LatLng(position.latitude, position.longitude);
        _zoom = 15.0;
      });
    }

    // Load friends locations
    await _loadFriendsLocations();

    // Set up periodic refresh for live locations
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _loadFriendsLocations();
    });

    // Fit bounds after initial load
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fitBounds();
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
          
          setState(() {
            _friendsWithLocations = friends;
            _isLoading = false;
          });

          // Create custom marker images for friends
          await _createCustomMarkerImages();
          
          // Update map after creating markers
          if (mounted) {
            setState(() {});
            _fitBounds();
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

  Future<void> _createCustomMarkerImages() async {
    for (final friend in _friendsWithLocations) {
      if (friend.latitude == null || friend.longitude == null) continue;
      
      final markerId = friend.id;
      if (_customMarkerImages.containsKey(markerId)) continue;

      try {
        // Create custom marker image with avatar
        final image = await _createFriendMarkerImage(friend);
        setState(() {
          _customMarkerImages[markerId] = image;
        });
      } catch (e) {
        print('Error creating marker for ${friend.nickname}: $e');
      }
    }
  }

  Future<ui.Image> _createFriendMarkerImage(Friend friend) async {
    // Create a picture recorder
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    const size = 50.0;
    const avatarSize = 38.0;
    const padding = 6.0;

    // Draw white circle background
    final backgroundPaint = ui.Paint()..color = Colors.white;
    canvas.drawCircle(
      const Offset(size / 2, size / 2),
      size / 2,
      backgroundPaint,
    );

    // Draw avatar
    try {
      final imageProvider = CachedNetworkImageProvider(friend.avatar);
      final completer = Completer<ui.Image>();
      final imageStream = imageProvider.resolve(const ImageConfiguration());
      
      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (ImageInfo info, bool synchronousCall) {
          imageStream.removeListener(listener);
          completer.complete(info.image);
        },
        onError: (exception, stackTrace) {
          imageStream.removeListener(listener);
          completer.completeError(exception);
        },
      );
      
      imageStream.addListener(listener);
      
      final loadedImage = await completer.future;
      
      // Resize image if needed
      ui.Image avatarImage = loadedImage;
      if (loadedImage.width != avatarSize.toInt() || loadedImage.height != avatarSize.toInt()) {
        final byteData = await loadedImage.toByteData(format: ui.ImageByteFormat.png);
        if (byteData != null) {
          final codec = await ui.instantiateImageCodec(
            byteData.buffer.asUint8List(),
            targetWidth: avatarSize.toInt(),
            targetHeight: avatarSize.toInt(),
          );
          final frame = await codec.getNextFrame();
          avatarImage = frame.image;
        }
      }

      // Draw avatar as circle
      final avatarRect = ui.Rect.fromLTWH(
        padding,
        padding,
        avatarSize,
        avatarSize,
      );
      final avatarPath = ui.Path()
        ..addOval(avatarRect);
      canvas.save();
      canvas.clipPath(avatarPath);
      canvas.drawImageRect(
        avatarImage,
        ui.Rect.fromLTWH(0, 0, avatarImage.width.toDouble(), avatarImage.height.toDouble()),
        avatarRect,
        ui.Paint(),
      );
      canvas.restore();
    } catch (e) {
      // If avatar loading fails, draw a placeholder
      final placeholderPaint = ui.Paint()..color = Colors.grey[300]!;
      canvas.drawCircle(
        const Offset(size / 2, size / 2),
        avatarSize / 2,
        placeholderPaint,
      );
    }

    // Draw private mode icon if enabled
    if (friend.locationPrivateMode == true) {
      final privateIconPaint = ui.Paint()
        ..color = Colors.orange
        ..style = ui.PaintingStyle.fill;
      canvas.drawCircle(
        const ui.Offset(size - 9, 9),
        5,
        privateIconPaint,
      );
      // Draw lock icon (simplified as a small circle with line)
      final lockPaint = ui.Paint()
        ..color = Colors.white
        ..strokeWidth = 1.5
        ..style = ui.PaintingStyle.stroke;
      canvas.drawCircle(
        const ui.Offset(size - 9, 9),
        3,
        lockPaint,
      );
    }

    // Draw border
    final borderPaint = ui.Paint()
      ..color = Colors.blue
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(
      const ui.Offset(size / 2, size / 2),
      size / 2,
      borderPaint,
    );

    // Convert to image
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    return image;
  }

  Future<void> _createCurrentUserMarker() async {
    if (_currentUserAvatar == null) {
      print('Cannot create marker: _currentUserAvatar is null');
      return;
    }
    
    print('Creating current user marker with avatar: $_currentUserAvatar');
    try {
      final image = await _createUserMarkerImage(_currentUserAvatar!);
      print('Successfully created current user marker image: ${image.width}x${image.height}');
      if (mounted) {
        setState(() {
          _currentUserMarkerImage = image;
        });
      }
    } catch (e, stackTrace) {
      print('Error creating current user marker: $e');
      print('Stack trace: $stackTrace');
    }
  }

  Future<ui.Image> _createUserMarkerImage(String avatarUrl) async {
    // Create a picture recorder
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    const size = 50.0;
    const avatarSize = 38.0;
    const padding = 6.0;

    // Draw white circle background
    final backgroundPaint = ui.Paint()..color = Colors.white;
    canvas.drawCircle(
      const ui.Offset(size / 2, size / 2),
      size / 2,
      backgroundPaint,
    );

    // Draw avatar
    try {
      print('Loading avatar image from: $avatarUrl');
      final imageProvider = CachedNetworkImageProvider(avatarUrl);
      final completer = Completer<ui.Image>();
      final imageStream = imageProvider.resolve(const ImageConfiguration());
      
      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (ImageInfo info, bool synchronousCall) {
          imageStream.removeListener(listener);
          print('Avatar image loaded: ${info.image.width}x${info.image.height}');
          completer.complete(info.image);
        },
        onError: (exception, stackTrace) {
          imageStream.removeListener(listener);
          print('Error loading avatar image: $exception');
          completer.completeError(exception);
        },
      );
      
      imageStream.addListener(listener);
      
      final loadedImage = await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Avatar image load timeout');
        },
      );
      
      // Resize image if needed
      ui.Image avatarImage = loadedImage;
      if (loadedImage.width != avatarSize.toInt() || loadedImage.height != avatarSize.toInt()) {
        final byteData = await loadedImage.toByteData(format: ui.ImageByteFormat.png);
        if (byteData != null) {
          final codec = await ui.instantiateImageCodec(
            byteData.buffer.asUint8List(),
            targetWidth: avatarSize.toInt(),
            targetHeight: avatarSize.toInt(),
          );
          final frame = await codec.getNextFrame();
          avatarImage = frame.image;
        }
      }

      // Draw avatar as circle
      final avatarRect = ui.Rect.fromLTWH(
        padding,
        padding,
        avatarSize,
        avatarSize,
      );
      final avatarPath = ui.Path()
        ..addOval(avatarRect);
      canvas.save();
      canvas.clipPath(avatarPath);
      canvas.drawImageRect(
        avatarImage,
        ui.Rect.fromLTWH(0, 0, avatarImage.width.toDouble(), avatarImage.height.toDouble()),
        avatarRect,
        ui.Paint(),
      );
      canvas.restore();
    } catch (e) {
      // If avatar loading fails, draw a placeholder
      final placeholderPaint = ui.Paint()..color = Colors.grey[300]!;
      canvas.drawCircle(
        const ui.Offset(size / 2, size / 2),
        avatarSize / 2,
        placeholderPaint,
      );
    }

    // Draw border (blue for current user)
    final borderPaint = ui.Paint()
      ..color = Colors.blue
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(
      const ui.Offset(size / 2, size / 2),
      size / 2,
      borderPaint,
    );

    // Convert to image
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    return image;
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    // Add current user marker with avatar
    if (_currentPosition != null) {
      if (_currentUserMarkerImage != null) {
        // Use custom avatar marker with "Me" label
        markers.add(
          Marker(
            point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
            width: 50,
            height: 70,
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 50,
                  height: 50,
                  child: CustomPaint(
                    painter: _ImageMarkerPainter(_currentUserMarkerImage!),
                    size: const Size(50, 50),
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
                    'Me',
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
      } else {
        // Fallback to default marker while avatar loads
        markers.add(
          Marker(
            point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
            width: 40,
            height: 60,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.person, color: Colors.white, size: 24),
                ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Me',
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
    }

    // Add friends markers
    for (final friend in _friendsWithLocations) {
      if (friend.latitude == null || friend.longitude == null) continue;

      final position = LatLng(friend.latitude!, friend.longitude!);
      
      // Get display name (nickname or username)
      final displayName = friend.nickname.isNotEmpty ? friend.nickname : friend.username;
      
      // Use custom marker image if available
      if (_customMarkerImages.containsKey(friend.id)) {
        final image = _customMarkerImages[friend.id]!;
        markers.add(
          Marker(
            point: position,
            width: 50,
            height: 70,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CustomPaint(
                  painter: _ImageMarkerPainter(image),
                  size: const Size(50, 50),
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
      } else {
        // Use default marker
        markers.add(
          Marker(
            point: position,
            width: 40,
            height: 60,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: friend.locationPrivateMode == true ? Colors.orange : Colors.green,
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.person, color: Colors.white, size: 24),
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
    final position = await _locationService.getCurrentLocation();
    if (position != null) {
      _mapController.move(
        LatLng(position.latitude, position.longitude),
        15.0,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
        ),
      ),
      body: Stack(
        children: [
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(),
            )
          else
            Stack(
              children: [
                FlutterMap(
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
                  ),
                  children: [
                    // OpenStreetMap tile layer - switches between light and dark based on theme
                    Builder(
                      builder: (context) {
                        final isDark = Theme.of(context).brightness == Brightness.dark;
                        return TileLayer(
                          urlTemplate: isDark
                              ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png' // CartoDB Dark Matter (dark mode)
                              : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', // Standard OSM (light mode)
                          userAgentPackageName: 'no.skybyn.app',
                          maxZoom: 19,
                          subdomains: isDark ? const ['a', 'b', 'c', 'd'] : const [],
                          // Enable tile caching using custom provider
                          tileProvider: _CachedTileProvider(_tileCacheManager),
                        );
                      },
                    ),
                    // Markers layer
                    MarkerLayer(
                      markers: _buildMarkers(),
                    ),
                  ],
                ),
                // Show message overlay if no locations available
                if (_currentPosition == null && _friendsWithLocations.isEmpty)
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
              ],
            ),
          // Floating action button to center on current location
          Positioned(
            bottom: 100,
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
        ],
      ),
    );
  }
}

// Custom painter for drawing marker images
class _ImageMarkerPainter extends CustomPainter {
  final ui.Image image;

  _ImageMarkerPainter(this.image);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(0, 0, size.width, size.height),
      paint,
    );
  }

  @override
  bool shouldRepaint(_ImageMarkerPainter oldDelegate) {
    return oldDelegate.image != image;
  }
}

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
