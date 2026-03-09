import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'local_cache_service.dart';

/// Handles fingerprint / Face ID authentication.
/// Wraps the local_auth package with clean error handling.
class BiometricService {
  BiometricService._();
  static final BiometricService instance = BiometricService._();

  final _auth = LocalAuthentication();

  /// Returns true if the device supports biometric authentication AND
  /// the user has at least one enrolled biometric (fingerprint/face).
  Future<bool> isAvailable() async {
    try {
      final canCheck  = await _auth.canCheckBiometrics;
      final isDevice  = await _auth.isDeviceSupported();
      if (!canCheck || !isDevice) return false;

      final biometrics = await _auth.getAvailableBiometrics();
      return biometrics.isNotEmpty;
    } on PlatformException catch (e) {
      _log('isAvailable error: $e');
      return false;
    }
  }

  /// Returns true if the user has previously opted-in to biometric login.
  bool isEnabled() => LocalCacheService.instance.isBiometricEnabled();

  /// Prompts the user to authenticate via biometrics.
  ///
  /// Returns true on success, false if the user cancels or fails.
  Future<bool> authenticate({
    String reason = 'Authenticate to access your medical records',
  }) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false, // allow PIN fallback
          stickyAuth: true,
        ),
      );
    } on PlatformException catch (e) {
      _log('authenticate error: $e');
      return false;
    }
  }

  /// Enables biometric login after a successful password login.
  Future<void> enable() async {
    await LocalCacheService.instance.setBiometricEnabled(true);
  }

  /// Disables biometric login (e.g. user turned it off in settings).
  Future<void> disable() async {
    await LocalCacheService.instance.setBiometricEnabled(false);
  }

  void _log(String msg) {
    // ignore: avoid_print
    print('[BiometricService] $msg');
  }
}
