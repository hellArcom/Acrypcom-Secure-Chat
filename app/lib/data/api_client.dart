import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../crypto/e2ee.dart';

class ApiClient {
  static final ApiClient instance = ApiClient._init();
  final _secureStorage = const FlutterSecureStorage();

  String _baseUrl = "http://10.0.2.2:8000";

  String? _token;
  int? _userId;
  String? _username;
  String? _publicKeyHex;
  String? _privateKeyHex;

  Timer? _keyRotationTimer;

  ApiClient._init();

  String get baseUrl => _baseUrl;
  int? get userId => _userId;
  String? get username => _username;
  String? get publicKeyHex => _publicKeyHex;
  String? get privateKeyHex => _privateKeyHex;
  String? get token => _token;

  void setBaseUrl(String url) {
    if (!url.startsWith("http://") && !url.startsWith("https://")) {
      url = "http://$url";
    }
    if (url.endsWith("/")) {
      url = url.substring(0, url.length - 1);
    }
    _baseUrl = url;
    _secureStorage.write(key: "server_url", value: _baseUrl);
    print("Base URL set to $_baseUrl");
  }

  Future<bool> initSession() async {
    try {
      _baseUrl = await _secureStorage.read(key: "server_url") ?? "http://10.0.2.2:8000";
      _token = await _secureStorage.read(key: "session_token");
      final userIdStr = await _secureStorage.read(key: "session_user_id");
      _username = await _secureStorage.read(key: "session_username");
      _publicKeyHex = await _secureStorage.read(key: "session_public_key");
      _privateKeyHex = await _secureStorage.read(key: "session_private_key");

      if (_token != null && userIdStr != null && _username != null && _publicKeyHex != null && _privateKeyHex != null) {
        _userId = int.parse(userIdStr);
        _startKeyRotation();
        return true;
      }
    } catch (e) {
      print("Secure storage init error: $e");
    }
    return false;
  }

  Future<void> saveSession({
    required String token,
    required int userId,
    required String username,
    required String publicKeyHex,
    required String privateKeyHex,
  }) async {
    _token = token;
    _userId = userId;
    _username = username;
    _publicKeyHex = publicKeyHex;
    _privateKeyHex = privateKeyHex;

    await _secureStorage.write(key: "session_token", value: token);
    await _secureStorage.write(key: "session_user_id", value: userId.toString());
    await _secureStorage.write(key: "session_username", value: username);
    await _secureStorage.write(key: "session_public_key", value: publicKeyHex);
    await _secureStorage.write(key: "session_private_key", value: privateKeyHex);

    _startKeyRotation();
  }

  Future<void> logout() async {
    _keyRotationTimer?.cancel();
    _keyRotationTimer = null;
    _token = null;
    _userId = null;
    _username = null;
    _publicKeyHex = null;
    _privateKeyHex = null;

    await _secureStorage.delete(key: "session_token");
    await _secureStorage.delete(key: "session_user_id");
    await _secureStorage.delete(key: "session_username");
    await _secureStorage.delete(key: "session_public_key");
    await _secureStorage.delete(key: "session_private_key");
  }

  /// Rotate X25519 key pair every 60 seconds.
  void _startKeyRotation() {
    _keyRotationTimer?.cancel();
    _keyRotationTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
      try {
        final newKeyPair = await E2EEManager.generateKeyPair();
        final newPrivateKeyHex = await E2EEManager.getPrivateKeyHex(newKeyPair);
        final newPublicKeyHex = await E2EEManager.getPublicKeyHex(newKeyPair);

        await updateProfile("", "", publicKeyHex: newPublicKeyHex);

        _publicKeyHex = newPublicKeyHex;
        _privateKeyHex = newPrivateKeyHex;
        await _secureStorage.write(key: "session_public_key", value: newPublicKeyHex);
        await _secureStorage.write(key: "session_private_key", value: newPrivateKeyHex);

        print("Key rotation completed");
      } catch (e) {
        print("Key rotation failed: $e");
      }
    });
  }

  Map<String, String> _headers() {
    final headers = {'Content-Type': 'application/json'};
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }
    return headers;
  }

  // --- REST Endpoints ---

  Future<Map<String, dynamic>> register(String username, String password, String publicKeyHex) async {
    final response = await http.post(
      Uri.parse("$_baseUrl/register"),
      headers: _headers(),
      body: jsonEncode({
        "username": username,
        "password": password,
        "public_key": publicKeyHex,
      }),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await http.post(
      Uri.parse("$_baseUrl/login"),
      headers: _headers(),
      body: jsonEncode({
        "username": username,
        "password": password,
      }),
    );
    return _handleResponse(response);
  }

  Future<List<dynamic>> searchUsers(String query) async {
    final response = await http.get(
      Uri.parse("$_baseUrl/users/search?query=${Uri.encodeComponent(query)}"),
      headers: _headers(),
    );
    final data = _handleResponse(response);
    return data as List<dynamic>;
  }

  Future<Map<String, dynamic>> getProfile(int userId) async {
    final response = await http.get(
      Uri.parse("$_baseUrl/users/$userId/profile"),
      headers: _headers(),
    );
    return _handleResponse(response) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateProfile(String bio, String profilePictureUrl, {String? publicKeyHex}) async {
    final response = await http.post(
      Uri.parse("$_baseUrl/profile/update"),
      headers: _headers(),
      body: jsonEncode({
        "bio": bio,
        "profile_picture_url": profilePictureUrl,
        if (publicKeyHex != null) "public_key": publicKeyHex,
      }),
    );
    return _handleResponse(response) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> publishNote(String content) async {
    final response = await http.post(
      Uri.parse("$_baseUrl/notes/publish"),
      headers: _headers(),
      body: jsonEncode({
        "content": content,
      }),
    );
    return _handleResponse(response) as Map<String, dynamic>;
  }

  Future<List<dynamic>> getNotesFeed() async {
    final response = await http.get(
      Uri.parse("$_baseUrl/notes/feed"),
      headers: _headers(),
    );
    final data = _handleResponse(response);
    return data as List<dynamic>;
  }

  Future<List<dynamic>> getOfflineMessages() async {
    final response = await http.get(
      Uri.parse("$_baseUrl/messages/offline"),
      headers: _headers(),
    );
    final data = _handleResponse(response);
    return data as List<dynamic>;
  }

  dynamic _handleResponse(http.Response response) {
    final body = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    } else {
      throw Exception(body['detail'] ?? "Server error code ${response.statusCode}");
    }
  }
}
