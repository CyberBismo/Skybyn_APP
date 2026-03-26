import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/constants.dart';

const _secureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);

/// Plain HTTP client — no auth header. Use for login/register requests.
http.Client createHttpClient() {
  final httpClient = HttpClient();
  return IOClient(httpClient);
}

/// Authenticated HTTP client — automatically adds Authorization: Bearer <token>
/// to every request. Use for all endpoints that require the user to be logged in.
http.Client createAuthenticatedHttpClient() {
  final inner = IOClient(HttpClient());
  return _AuthenticatedClient(inner);
}

/// Wraps an inner client and injects the session token header on every request.
class _AuthenticatedClient extends http.BaseClient {
  final http.Client _inner;
  _AuthenticatedClient(this._inner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final token = await _secureStorage.read(key: StorageKeys.sessionToken);
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
