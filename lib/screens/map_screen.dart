import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:ui' as ui;
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
  GoogleMapController? _mapController;
  String? _currentUserId;
  Position? _currentPosition;
  List<Friend> _friendsWithLocations = [];
  bool _isLoading = true;
  Timer? _refreshTimer;
  final Map<String, BitmapDescriptor> _customMarkers = {};
  final GlobalKey _notificationButtonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _initializeMap();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _mapController?.dispose();
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

    setState(() {
      _currentUserId = userId;
    });

    // Get current user location
    final position = await _locationService.getCurrentLocation();
    if (position != null) {
      setState(() {
        _currentPosition = position;
      });
    }

    // Load friends locations
    await _loadFriendsLocations();

    // Set up periodic refresh for live locations
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _loadFriendsLocations();
    });
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

          // Create custom markers for friends
          await _createCustomMarkers();
          
          // Update map markers after creating custom markers
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
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _createCustomMarkers() async {
    for (final friend in _friendsWithLocations) {
      if (friend.latitude == null || friend.longitude == null) continue;
      
      final markerId = friend.id;
      if (_customMarkers.containsKey(markerId)) continue;

      try {
        // Create custom marker with avatar
        final marker = await _createFriendMarker(friend);
        setState(() {
          _customMarkers[markerId] = marker;
        });
      } catch (e) {
        // If custom marker creation fails, use default marker
      }
    }
  }

  Future<BitmapDescriptor> _createFriendMarker(Friend friend) async {
    // Create a picture recorder
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const size = 80.0;
    const avatarSize = 60.0;
    const padding = 10.0;

    // Draw white circle background
    final backgroundPaint = Paint()..color = Colors.white;
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
      final avatarRect = Rect.fromLTWH(
        padding,
        padding,
        avatarSize,
        avatarSize,
      );
      final avatarPath = Path()
        ..addOval(avatarRect);
      canvas.save();
      canvas.clipPath(avatarPath);
      canvas.drawImageRect(
        avatarImage,
        Rect.fromLTWH(0, 0, avatarImage.width.toDouble(), avatarImage.height.toDouble()),
        avatarRect,
        Paint(),
      );
      canvas.restore();
    } catch (e) {
      // If avatar loading fails, draw a placeholder
      final placeholderPaint = Paint()..color = Colors.grey[300]!;
      canvas.drawCircle(
        const Offset(size / 2, size / 2),
        avatarSize / 2,
        placeholderPaint,
      );
    }

    // Draw private mode icon if enabled
    if (friend.locationPrivateMode == true) {
      final privateIconPaint = Paint()
        ..color = Colors.orange
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        const Offset(size - 15, 15),
        8,
        privateIconPaint,
      );
      // Draw lock icon (simplified as a small circle with line)
      final lockPaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(
        const Offset(size - 15, 15),
        5,
        lockPaint,
      );
    }

    // Draw border
    final borderPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(
      const Offset(size / 2, size / 2),
      size / 2,
      borderPaint,
    );

    // Convert to image
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final uint8List = byteData!.buffer.asUint8List();

    return BitmapDescriptor.fromBytes(uint8List);
  }

  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};

    // Add current user marker
    if (_currentPosition != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('current_user'),
          position: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: InfoWindow(
            title: TranslationService().translate(TranslationKeys.you),
          ),
        ),
      );
    }

    // Add friends markers
    for (final friend in _friendsWithLocations) {
      if (friend.latitude == null || friend.longitude == null) continue;

      final markerId = MarkerId(friend.id);
      final position = LatLng(friend.latitude!, friend.longitude!);
      
      // Use custom marker if available, otherwise use default
      BitmapDescriptor icon;
      if (_customMarkers.containsKey(friend.id)) {
        icon = _customMarkers[friend.id]!;
      } else {
        icon = BitmapDescriptor.defaultMarkerWithHue(
          friend.locationPrivateMode == true 
            ? BitmapDescriptor.hueOrange 
            : BitmapDescriptor.hueGreen,
        );
      }

      markers.add(
        Marker(
          markerId: markerId,
          position: position,
          icon: icon,
          infoWindow: InfoWindow(
            title: friend.nickname,
            snippet: friend.isLive == true 
              ? TranslationService().translate(TranslationKeys.liveLocation)
              : TranslationService().translate(TranslationKeys.lastActiveLocation),
          ),
        ),
      );
    }

    return markers;
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    
    // Move camera to show all friends or current location
    if (_friendsWithLocations.isNotEmpty || _currentPosition != null) {
      _fitBounds();
    }
  }

  void _fitBounds() {
    if (_mapController == null) return;

    final positions = <LatLng>[];
    
    if (_currentPosition != null) {
      positions.add(LatLng(_currentPosition!.latitude, _currentPosition!.longitude));
    }

    for (final friend in _friendsWithLocations) {
      if (friend.latitude != null && friend.longitude != null) {
        positions.add(LatLng(friend.latitude!, friend.longitude!));
      }
    }

    if (positions.isEmpty) return;

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

    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        100.0, // padding
      ),
    );
  }

  void _centerOnCurrentLocation() async {
    final position = await _locationService.getCurrentLocation();
    if (position != null && _mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(position.latitude, position.longitude),
          15.0,
        ),
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
          else if (_currentPosition == null && _friendsWithLocations.isEmpty)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.location_off, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  TranslatedText(
                    TranslationKeys.noLocationsAvailable,
                    style: TextStyle(color: AppColors.getTextColor(context)),
                  ),
                ],
              ),
            )
          else
            GoogleMap(
              onMapCreated: _onMapCreated,
              initialCameraPosition: CameraPosition(
                target: _currentPosition != null
                    ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
                    : _friendsWithLocations.isNotEmpty && _friendsWithLocations.first.latitude != null
                        ? LatLng(_friendsWithLocations.first.latitude!, _friendsWithLocations.first.longitude!)
                        : const LatLng(59.9139, 10.7522), // Default to Oslo, Norway instead of (0,0)
                zoom: 12.0,
              ),
              markers: _buildMarkers(),
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              mapType: MapType.normal,
            ),
          // Floating action button to center on current location
          Positioned(
            bottom: 100,
            right: 16,
            child: FloatingActionButton(
              onPressed: _centerOnCurrentLocation,
              backgroundColor: Colors.blue,
              child: const Icon(Icons.my_location, color: Colors.white),
            ),
          ),
          // Legend
          Positioned(
            top: 100,
            left: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 16,
                        height: 16,
                        decoration: const BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      TranslatedText(
                        TranslationKeys.you,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        width: 16,
                        height: 16,
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      TranslatedText(
                        TranslationKeys.friends,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        width: 16,
                        height: 16,
                        decoration: const BoxDecoration(
                          color: Colors.orange,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      TranslatedText(
                        TranslationKeys.locationPrivateMode,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

