import 'dart:convert';
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
      if (storedRefresh == null) {
        await clearTokens();
        return false;
      }

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
      } else {
        await clearTokens();
      }
    } catch (e) {
      debugPrint('[ApiService] Token refresh failed: $e');
      await clearTokens();
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

  // ── Push Notifications ────────────────────────────────────────────────────

  Future<void> updateFcmToken(String role, String fcmToken) async {
    final endpoint = role == 'doctor' ? '/doctors/me/fcm-token' : '/patients/me/fcm-token';
    final res = await _request('POST', endpoint, body: {'fcmToken': fcmToken});
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

  Future<Map<String, dynamic>> getMyReports({
    int page = 1,
    int limit = 20,
    String? status,
    String? fileType,
    String? search,
    String? startDate,
    String? endDate,
  }) async {
    final Map<String, String> q = {
      'page': page.toString(),
      'limit': limit.toString(),
      if (status != null && status.isNotEmpty) 'status': status,
      if (fileType != null && fileType.isNotEmpty) 'fileType': fileType,
      if (search != null && search.isNotEmpty) 'search': search,
      if (startDate != null && startDate.isNotEmpty) 'startDate': startDate,
      if (endDate != null && endDate.isNotEmpty) 'endDate': endDate,
    };
    final qs = Uri(queryParameters: q).query;
    final res = await _request('GET', '/patients/me/reports?$qs');
    return _parse(res);
  }

  Future<Map<String, dynamic>> getMyPrescriptions({int page = 1, int limit = 20}) async {
    final res = await _request('GET', '/patients/me/prescriptions?page=$page&limit=$limit');
    return _parse(res);
  }

  Future<Map<String, dynamic>> getMyHistory() async {
    final res = await _request('GET', '/patients/me/history');
    return _parse(res);
  }

  Future<void> deleteAccount(String password) async {
    final res = await _request('DELETE', '/patients/me', body: {'password': password});
    _parse(res);
  }

  // ── Doctor ────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getDoctorProfile() async {
    final res = await _request('GET', '/doctors/me');
    return _parse(res);
  }

  Future<Map<String, dynamic>> updateDoctorProfile(Map<String, dynamic> body) async {
    final res = await _request('PUT', '/doctors/me', body: body);
    return _parse(res);
  }

  Future<Map<String, dynamic>> getPatientByQr(
    String patientId,
    String token,
  ) async {
    final res = await _request('GET', '/doctors/patients/$patientId?token=$token');
    return _parse(res);
  }

  Future<Map<String, dynamic>> getPatientReports(String patientId, String qrToken) async {
    final res = await _request('GET', '/doctors/patients/$patientId/reports?token=$qrToken');
    return _parse(res);
  }

  Future<Map<String, dynamic>> createPrescription(Map<String, dynamic> body) async {
    final res = await _request('POST', '/doctors/prescriptions', body: body);
    return _parse(res);
  }

  Future<Map<String, dynamic>> getDoctorPrescriptions({int page = 1, int limit = 20}) async {
    final res = await _request('GET', '/doctors/prescriptions?page=$page&limit=$limit');
    return _parse(res);
  }

  Future<void> cancelPrescription(String id) async {
    final res = await _request('DELETE', '/doctors/prescriptions/$id');
    _parse(res);
  }

  // ── Reports ───────────────────────────────────────────────────────────────

  /// Uploads a report file.
  ///
  /// M-03 FIX: The previous code set Authorization: 'Bearer $_accessToken'
  /// directly on the MultipartRequest. If _accessToken was null (e.g. token
  /// had expired between app init and the moment the user tapped upload) this
  /// sent the literal string "Bearer null", which the server rejected with a
  /// confusing 401. The auto-refresh logic in _request() was also bypassed
  /// because MultipartRequest doesn't go through that method.
  ///
  /// Fix: always call loadToken() first to ensure _accessToken is current,
  /// then attempt the upload. On 401, try one token refresh and retry — the
  /// same pattern _request() uses for all other endpoints.
  Future<Map<String, dynamic>> uploadReport({
    String? filePath,
    Uint8List? fileBytes,
    required String fileName,
    required String description,
    void Function(double progress)? onProgress,
  }) async {
    // M-03: ensure token is fresh before building the request
    await loadToken();

    // M-03: if still null after loading, attempt a refresh before giving up
    if (_accessToken == null) {
      final refreshed = await _tryRefreshToken();
      if (!refreshed) {
        throw const ApiException(message: 'Session expired. Please log in again.', statusCode: 401);
      }
    }

    final uri = Uri.parse('$_baseUrl/reports/upload');

    Future<http.StreamedResponse> buildAndSend() async {
      final request = http.MultipartRequest('POST', uri);
      // M-03: _accessToken is guaranteed non-null at this point
      request.headers['Authorization'] = 'Bearer $_accessToken';
      request.fields['description'] = description;

      final extension = fileName.split('.').last.toLowerCase();
      final mimeType = {
        'pdf':  MediaType('application', 'pdf'),
        'jpg':  MediaType('image', 'jpeg'),
        'jpeg': MediaType('image', 'jpeg'),
        'png':  MediaType('image', 'png'),
      }[extension] ?? MediaType('application', 'octet-stream');

      if (kIsWeb && fileBytes != null) {
        request.files.add(http.MultipartFile.fromBytes(
          'report', fileBytes, filename: fileName, contentType: mimeType,
        ));
      } else if (filePath != null) {
        request.files.add(await http.MultipartFile.fromPath(
          'report', filePath, contentType: mimeType,
        ));
      } else {
        throw Exception('No file data provided for upload');
      }
      return request.send();
    }

    var streamed = await buildAndSend();
    var res = await http.Response.fromStream(streamed);

    // M-03: on 401, refresh and retry once (same pattern as _request)
    if (res.statusCode == 401) {
      final refreshed = await _tryRefreshToken();
      if (refreshed) {
        streamed = await buildAndSend();
        res = await http.Response.fromStream(streamed);
      }
    }

    return _parse(res);
  }

  Future<Map<String, dynamic>> getReport(String reportId, {String? qrToken}) async {
    final qs = qrToken != null ? '?token=$qrToken' : '';
    final res = await _request('GET', '/reports/$reportId$qs');
    return _parse(res);
  }

  Future<Map<String, dynamic>> getReportStatus(String reportId, {String? qrToken}) async {
    final qs = qrToken != null ? '?token=$qrToken' : '';
    final res = await _request('GET', '/reports/$reportId/status$qs');
    return _parse(res);
  }

  Future<Map<String, dynamic>> getReportUrl(String reportId, {String? qrToken}) async {
    final qs = qrToken != null ? '?token=$qrToken' : '';
    final res = await _request('GET', '/reports/$reportId/url$qs');
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
