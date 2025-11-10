import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Creates an HTTP client that respects HttpOverrides for SSL certificate handling
/// In debug mode, this will accept self-signed certificates
/// In release mode, standard SSL validation is used
http.Client createHttpClient() {
  final httpClient = HttpClient();
  
  // Only bypass SSL certificate validation in debug mode
  if (kDebugMode) {
    httpClient.badCertificateCallback = (X509Certificate cert, String host, int port) {
      print('⚠️ [HTTP] Accepting certificate for $host:$port in debug mode');
      return true; // Accept all certificates in debug mode
    };
  }
  // In release mode, use default SSL validation (secure)
  
  return IOClient(httpClient);
}

