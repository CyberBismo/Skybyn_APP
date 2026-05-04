import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';

const _secureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);

/// Plain HTTP client — no auth header. Use for login/register requests.
http.Client createHttpClient({String? userAgent}) {
  final httpClient = HttpClient();
  if (userAgent != null) httpClient.userAgent = userAgent;
  return IOClient(httpClient);
}

/// Authenticated HTTP client — automatically adds Authorization: Bearer <token>
/// to every request. Safe to use before login too: if no token is stored, the
/// header is simply omitted.
http.Client createAuthenticatedHttpClient({String? userAgent}) {
  final httpClient = HttpClient();
  if (userAgent != null) httpClient.userAgent = userAgent;
  httpClient.connectionTimeout = const Duration(seconds: 30);
  httpClient.idleTimeout = const Duration(seconds: 30);
  httpClient.autoUncompress = true;
  return AuthenticatedClient(IOClient(httpClient));
}

/// Global singleton — import and use directly in services/screens instead of
/// creating bare http.post() calls.
final globalAuthClient = createAuthenticatedHttpClient(
  userAgent: 'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/91.0.4472.120 Mobile Safari/537.36 Skybyn-App/1.0',
);

/// In-memory session token cache — set by AuthService on login/logout.
/// Checked first to avoid SecureStorage reads on every request.
String? cachedSessionToken;

/// Wraps an inner client and injects the session token header on every request.
class AuthenticatedClient extends http.BaseClient {
  final http.Client _inner;
  AuthenticatedClient(this._inner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Use in-memory cache first (set by AuthService on login)
    String? token = cachedSessionToken;

    if (token == null || token.isEmpty) {
      try {
        token = await _secureStorage.read(key: StorageKeys.sessionToken)
            .timeout(const Duration(seconds: 3));
      } catch (e) {
        debugPrint('[AuthClient] Secure storage read failed: $e');
      }
    }
    // Fall back to SharedPreferences if secure storage returned nothing
    if (token == null || token.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      token = prefs.getString(StorageKeys.sessionToken);
    }
    // Populate cache for next call
    if (token != null && token.isNotEmpty) {
      cachedSessionToken = token;
      request.headers['Authorization'] = 'Bearer $token';
    } else {
      debugPrint('[AuthClient] WARNING: No session token found — request will be unauthenticated');
    }
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
