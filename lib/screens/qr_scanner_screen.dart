import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'dart:ui';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/auth_service.dart';
import 'dart:async'; // Required for OverlayEntry
import '../widgets/background_gradient.dart';
import '../services/translation_service.dart';
import '../utils/translation_keys.dart';
import '../widgets/translated_text.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  MobileScannerController cameraController = MobileScannerController();
  final AuthService _authService = AuthService();
  String? _userId;
  OverlayEntry? _overlayEntry;
  String? _lastScannedCode;
  bool _showSuccessOverlay = false;
  bool _isCameraInitialized = false;
  String? _cameraError;

  @override
  void initState() {
    super.initState();
    _loadUserId();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      await cameraController.start();
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cameraError = 'Camera initialization failed: $e';
        });
      }
    }
  }

  Future<void> _loadUserId() async {
    _userId = await _authService.getStoredUserId();
    setState(() {}); // Trigger rebuild to ensure _userId is available if needed immediately
  }

  Future<void> _sendQrCodeToServer(String qrCode) async {
    if (_userId == null) {
      return;
    }

    try {
      final response = await http.post(
        Uri.parse('https://api.skybyn.no/qr_check.php'),
        body: {'user': _userId!, 'code': qrCode},
      );

      final Map<String, dynamic> data = json.decode(response.body);

      if (data['responseCode'] == '1') {
        if (!mounted) return;
        setState(() {
          _showSuccessOverlay = true;
          _lastScannedCode = 'VALID';
        });
      } else {
        setState(() {
          _lastScannedCode = data['message'] ?? 'Failed to check QR code.';
        });
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted && _lastScannedCode != 'VALID') {
            setState(() {
              _lastScannedCode = null;
            });
          }
        });
      }
    } catch (e) {
      _showOverlayToast('Error communicating with server: $e');
    }
  }

  void _showOverlayToast(String message) {
    if (_overlayEntry != null) {
      _overlayEntry!.remove();
      _overlayEntry = null;
    }

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        bottom: MediaQuery.of(context).padding.bottom + kBottomNavigationBarHeight + 8.0,
        left: 16.0,
        right: 16.0,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              message,
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);

    Future.delayed(const Duration(seconds: 3), () {
      if (_overlayEntry != null) {
        _overlayEntry!.remove();
        _overlayEntry = null;
      }
    });
  }

  @override
  void dispose() {
    try {
      cameraController.dispose();
    } catch (e) {
      print('Error disposing camera controller: $e');
    }
    if (_overlayEntry != null) {
      _overlayEntry!.remove();
      _overlayEntry = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          TranslationKeys.scanQrCode.tr,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Stack(
        children: [
          const BackgroundGradient(),
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20.0), // Adjust border radius as needed
              child: SizedBox(
                width: MediaQuery.of(context).size.width * 0.7, // 70% of screen width
                height: MediaQuery.of(context).size.width * 0.7, // Maintain aspect ratio for a square
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_isCameraInitialized && _cameraError == null)
                      MobileScanner(
                        controller: cameraController,
                        onDetect: (capture) async {
                          final List<Barcode> barcodes = capture.barcodes;
                          for (final barcode in barcodes) {
                            final scannedCode = barcode.rawValue;
                            if (scannedCode != null) {
                              if (scannedCode.length == 10) {
                                debugPrint('Valid QR code found: $scannedCode');
                                await _sendQrCodeToServer(scannedCode);
                              } else {
                                debugPrint('Invalid QR code length: $scannedCode');
                                _showOverlayToast('QR code must be exactly 10 characters long.');
                              }
                            }
                          }
                        },
                      )
                    else if (_cameraError != null)
                      Container(
                        color: Colors.black.withOpacity(0.8),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: Colors.white,
                                size: 64,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Camera Error',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 32),
                                child: Text(
                                  _cameraError!,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              const SizedBox(height: 24),
                              ElevatedButton(
                                onPressed: () {
                                  setState(() {
                                    _cameraError = null;
                                  });
                                  _initializeCamera();
                                },
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      const Center(
                        child: CircularProgressIndicator(
                          color: Colors.white,
                        ),
                      ),
                    if (_showSuccessOverlay)
                      Positioned.fill(
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                          child: Container(
                            color: Colors.black.withOpacity(0.3),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.check_circle, color: Colors.green, size: 120),
                                const SizedBox(height: 24),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _showSuccessOverlay = false;
                                    });
                                    Navigator.of(context).pop();
                                  },
                                  child: const Text('Done', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 32 + MediaQuery.of(context).padding.bottom,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: _showSuccessOverlay
                  ? ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      onPressed: () {
                        setState(() {
                          _showSuccessOverlay = false;
                          _lastScannedCode = null;
                        });
                        cameraController.start();
                      },
                      child: const Text('Scan Again', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    )
                  : Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _lastScannedCode == 'VALID' ? 'VALID' : (_lastScannedCode ?? 'Scanning..'),
                        style: const TextStyle(color: Colors.white, fontSize: 18),
                        textAlign: TextAlign.center,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
