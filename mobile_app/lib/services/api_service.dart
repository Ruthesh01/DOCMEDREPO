import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../services/local_cache_service.dart';

/// Central API service. All HTTP calls in the app MUST go through this class.
/// Screen widgets never call http directly.
class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  static String get _baseUrl {
    const defined = String.fromEnvironment('API_BASE_URL');
    if (defined.isNotEmpty) return defined;
    return kIsWeb ? 'http://localhost:5000/api' : 'http://10.0.2.2:5000/api';
  }

  // ── Token management (stored via flutter_secure_storage) ─────────────────
  String? _accessToken;

  /// Loads the access token from secure storage into memory.
  Future<void> loadToken() async {
    _accessToken = await LocalCacheService.instance.getAccessToken();
  }

  /// Stores a new token pair (called after login or token refresh).
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    _accessToken = accessToken;
    await LocalCacheService.instance.saveTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
  }

  /// Clears all stored tokens (called on logout).
  Future<void> clearTokens() async {
    _accessToken = null;
    await LocalCacheService.instance.clearTokens();
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  Map<String, String> get _authHeaders => {
        'Content-Type': 'application/json',
        if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
      };

  /// Sends a request and automatically retries once with a refreshed token
  /// if the server returns 401.
  Future<http.Response> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool requiresAuth = true,
  }) async {
    final uri = Uri.parse('$_baseUrl$path');

    Future<http.Response> send() async {
      final headers = requiresAuth ? _authHeaders : {'Content-Type': 'application/json'};
      final encoded = body != null ? jsonEncode(body) : null;

      switch (method) {
        case 'GET':    return http.get(uri, headers: headers);
        case 'POST':   return http.post(uri, headers: headers, body: encoded);
        case 'PUT':    return http.put(uri, headers: headers, body: encoded);
        case 'DELETE': return http.delete(uri, headers: headers);
        default:       throw UnsupportedError('HTTP method $method not supported');
      }
    }

    var response = await send();

    // Auto-refresh on 401
    if (response.statusCode == 401 && requiresAuth) {
      final refreshed = await _tryRefreshToken();
      if (refreshed) {
        response = await send();
      }
    }

    return response;
  }

  /// Attempts to refresh the access token using the stored refresh token.
  /// Returns true on success.
  Future<bool> _tryRefreshToken() async {
    try {
      final storedRefresh = await LocalCacheService.instance.getRefreshToken();
      if (storedRefresh == null) return false;

      final res = await http.post(
        Uri.parse('$_baseUrl/auth/refresh-token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': storedRefresh}),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        await saveTokens(
          accessToken: data['accessToken'],
          refreshToken: data['refreshToken'],
        );
        return true;
      }
    } catch (e) {
      debugPrint('[ApiService] Token refresh failed: $e');
    }
    return false;
  }

  /// Parses an HTTP response. Throws [ApiException] on non-2xx status.
  Map<String, dynamic> _parse(http.Response res) {
    final Map<String, dynamic> data = jsonDecode(res.body);
    if (res.statusCode >= 200 && res.statusCode < 300) return data;
    final message = data['error'] ?? data['message'] ?? 'Unknown error';
    throw ApiException(message: message, statusCode: res.statusCode);
  }

  // ── Auth ──────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> registerPatient(Map<String, dynamic> body) async {
    final res = await _request('POST', '/auth/register/patient', body: body, requiresAuth: false);
    return _parse(res);
  }

  Future<Map<String, dynamic>> registerDoctor(Map<String, dynamic> body) async {
    final res = await _request('POST', '/auth/register/doctor', body: body, requiresAuth: false);
    return _parse(res);
  }

  Future<Map<String, dynamic>> login(Map<String, dynamic> body) async {
    final res = await _request('POST', '/auth/login', body: body, requiresAuth: false);
    return _parse(res);
  }

  Future<Map<String, dynamic>> verifyOtp(String doctorId, String otp) async {
    final res = await _request(
      'POST', '/auth/verify-otp',
      body: {'doctorId': doctorId, 'otp': otp},
      requiresAuth: false,
    );
    return _parse(res);
  }

  Future<void> logout() async {
    final refresh = await LocalCacheService.instance.getRefreshToken();
    await _request('POST', '/auth/logout', body: {'refreshToken': refresh});
    await clearTokens();
  }

  Future<void> changePassword(String current, String next) async {
    final res = await _request(
      'POST', '/auth/change-password',
      body: {'currentPassword': current, 'newPassword': next},
    );
    _parse(res);
  }

  // ── Patient ───────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getMyProfile() async {
    final res = await _request('GET', '/patients/me');
    return _parse(res);
  }

  Future<Map<String, dynamic>> updateMyProfile(Map<String, dynamic> body) async {
    final res = await _request('PUT', '/patients/me', body: body);
    return _parse(res);
  }

  Future<Map<String, dynamic>> getMyReports() async {
    final res = await _request('GET', '/patients/me/reports');
    return _parse(res);
  }

  Future<Map<String, dynamic>> getMyPrescriptions() async {
    final res = await _request('GET', '/patients/me/prescriptions');
    return _parse(res);
  }

  Future<Map<String, dynamic>> getMyHistory() async {
    final res = await _request('GET', '/patients/me/history');
    return _parse(res);
  }

  // ── Doctor ────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getDoctorProfile() async {
    final res = await _request('GET', '/doctors/me');
    return _parse(res);
  }

  Future<Map<String, dynamic>> getPatientByQr(
    String patientId,
    String token,
  ) async {
    final res = await _request('GET', '/doctors/patients/$patientId?token=$token');
    return _parse(res);
  }

  Future<Map<String, dynamic>> createPrescription(Map<String, dynamic> body) async {
    final res = await _request('POST', '/doctors/prescriptions', body: body);
    return _parse(res);
  }

  Future<Map<String, dynamic>> getDoctorPrescriptions() async {
    final res = await _request('GET', '/doctors/prescriptions');
    return _parse(res);
  }

  // ── Reports ───────────────────────────────────────────────────────────────

  /// Uploads a report file with a progress callback.
  Future<Map<String, dynamic>> uploadReport({
    String? filePath,
    Uint8List? fileBytes,
    required String fileName,
    required String description,
    void Function(double progress)? onProgress,
  }) async {
    final uri = Uri.parse('$_baseUrl/reports/upload');
    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $_accessToken';
    request.fields['description'] = description;

    final extension = fileName.split('.').last.toLowerCase();
    final mimeType = {
      'pdf': MediaType('application', 'pdf'),
      'jpg': MediaType('image', 'jpeg'),
      'jpeg': MediaType('image', 'jpeg'),
      'png': MediaType('image', 'png'),
    }[extension] ?? MediaType('application', 'octet-stream');

    if (kIsWeb && fileBytes != null) {
      final multipartFile = http.MultipartFile.fromBytes(
        'report',
        fileBytes,
        filename: fileName,
        contentType: mimeType,
      );
      request.files.add(multipartFile);
    } else if (filePath != null) {
      final multipartFile = await http.MultipartFile.fromPath(
        'report',
        filePath,
        contentType: mimeType,
      );
      request.files.add(multipartFile);
    } else {
      throw Exception('No file data provided for upload');
    }

    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    return _parse(res);
  }

  Future<Map<String, dynamic>> getReportUrl(String reportId) async {
    final res = await _request('GET', '/reports/$reportId/url');
    return _parse(res);
  }

  Future<void> deleteReport(String reportId) async {
    final res = await _request('DELETE', '/reports/$reportId');
    _parse(res);
  }

  // ── QR ────────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> generateQr() async {
    final res = await _request('POST', '/qr/generate');
    return _parse(res);
  }

  Future<Map<String, dynamic>> scanQr(String token) async {
    final res = await _request('POST', '/qr/scan', body: {'token': token});
    return _parse(res);
  }
}

/// Thrown when the API returns a non-2xx response.
class ApiException implements Exception {
  final String message;
  final int statusCode;

  const ApiException({required this.message, required this.statusCode});

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden    => statusCode == 403;
  bool get isNotFound     => statusCode == 404;
  bool get isConflict     => statusCode == 409;

  @override
  String toString() => 'ApiException($statusCode): $message';
}
