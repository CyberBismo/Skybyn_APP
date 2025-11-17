import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Creates an HTTP client with standard SSL certificate validation
http.Client createHttpClient() {
  final httpClient = HttpClient();
  
  // Use default SSL validation (secure)
  
  return IOClient(httpClient);
}

