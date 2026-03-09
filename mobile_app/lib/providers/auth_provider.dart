import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../services/local_cache_service.dart';

class AuthProvider extends ChangeNotifier {
  String? _role;
  bool _initialised = false;

  String? get role        => _role;
  bool    get isPatient   => _role == 'patient';
  bool    get isDoctor    => _role == 'doctor';
  bool    get isLoggedIn  => _role != null;
  bool    get initialised => _initialised;

  Future<void> init() async {
    await ApiService.instance.loadToken();
    final token = await LocalCacheService.instance.getAccessToken();
    if (token != null) _role = _decodeRoleFromJwt(token);
    _initialised = true;
    notifyListeners();
  }

  Future<String?> loginPatient({required String email, required String password}) async {
    try {
      final data = await ApiService.instance.login({'email': email, 'password': password, 'role': 'patient'});
      await ApiService.instance.saveTokens(accessToken: data['accessToken'] as String, refreshToken: data['refreshToken'] as String);
      _role = 'patient';
      notifyListeners();
      return null;
    } on ApiException catch (e) { return e.message; }
  }

  Future<bool> biometricLogin() async {
    final token = await LocalCacheService.instance.getAccessToken();
    if (token == null) return false;
    final decoded = _decodeRoleFromJwt(token);
    if (decoded == null) return false;
    _role = decoded;
    notifyListeners();
    return true;
  }

  Future<String?> registerPatient({required String name, required String email, required String password, String? bloodGroup, required Map<String, String> emergencyContact}) async {
    try {
      await ApiService.instance.registerPatient({'name': name, 'email': email, 'password': password, if (bloodGroup != null) 'bloodGroup': bloodGroup, 'emergencyContact': emergencyContact});
      return loginPatient(email: email, password: password);
    } on ApiException catch (e) { return e.message; }
  }

  Future<Map<String, dynamic>> loginDoctorStep1({required String email, required String password}) async {
    try {
      final data = await ApiService.instance.login({'email': email, 'password': password, 'role': 'doctor'});
      if (data.containsKey('accessToken')) {
        await ApiService.instance.saveTokens(
          accessToken: data['accessToken'] as String, 
          refreshToken: data['refreshToken'] as String
        );
        _role = 'doctor';
        notifyListeners();
        return {'doctorId': null, 'completed': true};
      }
      return {'doctorId': data['doctorId'], 'completed': false};
    } on ApiException catch (e) { return {'error': e.message}; }
  }

  Future<String?> loginDoctorStep2({required String doctorId, required String otp}) async {
    try {
      final data = await ApiService.instance.verifyOtp(doctorId, otp);
      await ApiService.instance.saveTokens(accessToken: data['accessToken'] as String, refreshToken: data['refreshToken'] as String);
      _role = data['role'] as String? ?? 'doctor';
      notifyListeners();
      return null;
    } on ApiException catch (e) { return e.message; }
  }

  Future<String?> registerDoctor({required String name, required String email, required String password, required String specialization, required String licenseNumber}) async {
    try {
      await ApiService.instance.registerDoctor({'name': name, 'email': email, 'password': password, 'specialization': specialization, 'licenseNumber': licenseNumber});
      return null;
    } on ApiException catch (e) { return e.message; }
  }

  Future<void> logout() async {
    try { await ApiService.instance.logout(); } catch (_) {}
    await LocalCacheService.instance.clearAll();
    _role = null;
    notifyListeners();
  }

  String? _decodeRoleFromJwt(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
      switch (payload.length % 4) {
        case 2: payload += '=='; break;
        case 3: payload += '=';  break;
      }
      final decoded = utf8.decode(base64.decode(payload));
      final map = jsonDecode(decoded) as Map<String, dynamic>;
      return map['role'] as String?;
    } catch (_) { return null; }
  }
}
