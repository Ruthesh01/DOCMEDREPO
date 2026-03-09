import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Manages all local persistence:
///   - JWT tokens via flutter_secure_storage (encrypted on-device)
///   - Cached app data via Hive (profile, reports, prescriptions)
class LocalCacheService {
  LocalCacheService._();
  static final LocalCacheService instance = LocalCacheService._();

  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  // ── Hive box names ────────────────────────────────────────────────────────
  static const _profileBox       = 'profile';
  static const _reportsBox       = 'reports';
  static const _prescriptionsBox = 'prescriptions';
  static const _metaBox          = 'meta';

  // ── Secure storage keys ───────────────────────────────────────────────────
  static const _kAccessToken  = 'access_token';
  static const _kRefreshToken = 'refresh_token';

  // ── Initialisation ────────────────────────────────────────────────────────

  /// Must be called once at app startup before using any cache methods.
  static Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox(_profileBox);
    await Hive.openBox(_reportsBox);
    await Hive.openBox(_prescriptionsBox);
    await Hive.openBox(_metaBox);
  }

  // ── Token management (secure storage) ────────────────────────────────────

  /// Saves JWT token pair to encrypted secure storage.
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _secureStorage.write(key: _kAccessToken,  value: accessToken);
    await _secureStorage.write(key: _kRefreshToken, value: refreshToken);
  }

  Future<String?> getAccessToken()  async =>
      _secureStorage.read(key: _kAccessToken);

  Future<String?> getRefreshToken() async =>
      _secureStorage.read(key: _kRefreshToken);

  Future<void> clearTokens() async {
    await _secureStorage.delete(key: _kAccessToken);
    await _secureStorage.delete(key: _kRefreshToken);
  }

  // ── Profile cache ─────────────────────────────────────────────────────────

  /// Saves the latest patient/doctor profile to Hive.
  Future<void> saveProfile(Map<String, dynamic> profile) async {
    final box = Hive.box(_profileBox);
    await box.put('data', profile);
    await _saveTimestamp('profile');
  }

  /// Returns the cached profile, or null if not cached.
  Map<String, dynamic>? getCachedProfile() {
    final box = Hive.box(_profileBox);
    return box.get('data') != null
        ? Map<String, dynamic>.from(box.get('data') as Map)
        : null;
  }

  // ── Reports cache (last 10) ───────────────────────────────────────────────

  Future<void> saveReports(List<dynamic> reports) async {
    final box = Hive.box(_reportsBox);
    final trimmed = reports.take(10).toList();
    await box.put('list', trimmed);
    await _saveTimestamp('reports');
  }

  List<Map<String, dynamic>>? getCachedReports() {
    final box  = Hive.box(_reportsBox);
    final raw  = box.get('list');
    if (raw == null) return null;
    return (raw as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  // ── Prescriptions cache (last 20) ─────────────────────────────────────────

  Future<void> savePrescriptions(List<dynamic> prescriptions) async {
    final box     = Hive.box(_prescriptionsBox);
    final trimmed = prescriptions.take(20).toList();
    await box.put('list', trimmed);
    await _saveTimestamp('prescriptions');
  }

  List<Map<String, dynamic>>? getCachedPrescriptions() {
    final box = Hive.box(_prescriptionsBox);
    final raw = box.get('list');
    if (raw == null) return null;
    return (raw as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  // ── Timestamp helpers ─────────────────────────────────────────────────────

  Future<void> _saveTimestamp(String key) async {
    final box = Hive.box(_metaBox);
    await box.put('${key}_updated_at', DateTime.now().toIso8601String());
  }

  /// Returns a human-readable "Last updated X mins ago" string,
  /// or null if no timestamp is stored for this key.
  String? getLastUpdatedLabel(String key) {
    final box = Hive.box(_metaBox);
    final raw = box.get('${key}_updated_at');
    if (raw == null) return null;

    final updated = DateTime.parse(raw as String);
    final diff    = DateTime.now().difference(updated);

    if (diff.inMinutes < 1)  return 'Last updated just now';
    if (diff.inMinutes < 60) return 'Last updated ${diff.inMinutes}m ago';
    if (diff.inHours   < 24) return 'Last updated ${diff.inHours}h ago';
    return 'Last updated ${diff.inDays}d ago';
  }

  // ── Biometric preference ──────────────────────────────────────────────────

  Future<void> setBiometricEnabled(bool value) async {
    final box = Hive.box(_metaBox);
    await box.put('biometric_enabled', value);
  }

  bool isBiometricEnabled() {
    final box = Hive.box(_metaBox);
    return box.get('biometric_enabled', defaultValue: false) as bool;
  }

  // ── Full clear (logout) ───────────────────────────────────────────────────

  /// Clears all cached data and tokens. Call on logout.
  Future<void> clearAll() async {
    await clearTokens();
    await Hive.box(_profileBox).clear();
    await Hive.box(_reportsBox).clear();
    await Hive.box(_prescriptionsBox).clear();
    await Hive.box(_metaBox).clear();
  }
}
