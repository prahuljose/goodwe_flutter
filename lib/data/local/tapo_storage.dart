import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/tapo_device.dart';

/// Persists the Tapo account credentials (shared across all plugs) and the
/// list of configured devices. Everything lives in secure storage.
class TapoStorage {
  static const _emailKey   = 'tapo_email';
  static const _passKey    = 'tapo_password';
  static const _devicesKey = 'tapo_devices';

  final FlutterSecureStorage _s;

  TapoStorage({FlutterSecureStorage? storage})
      : _s = storage ??
            const FlutterSecureStorage(
              // Hardware-backed EncryptedSharedPreferences on Android —
              // required for data to survive hot restart / app restart.
              // (Matches CredentialsStorage; the plain backend loses data.)
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  // ── Account ─────────────────────────────────────────────────────────────

  Future<void> saveAccount(String email, String password) async {
    await _s.write(key: _emailKey, value: email);
    await _s.write(key: _passKey, value: password);
  }

  Future<({String email, String password})?> loadAccount() async {
    final email = await _s.read(key: _emailKey);
    final pass = await _s.read(key: _passKey);
    if (email == null || pass == null) return null;
    return (email: email, password: pass);
  }

  Future<bool> hasAccount() async {
    final email = await _s.read(key: _emailKey);
    return email != null && email.isNotEmpty;
  }

  Future<void> clearAccount() async {
    await _s.delete(key: _emailKey);
    await _s.delete(key: _passKey);
  }

  // ── Devices ─────────────────────────────────────────────────────────────

  Future<void> saveDevices(List<TapoDevice> devices) async {
    final json = jsonEncode(devices.map((d) => d.toJson()).toList());
    await _s.write(key: _devicesKey, value: json);
  }

  Future<List<TapoDevice>> loadDevices() async {
    final raw = await _s.read(key: _devicesKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => TapoDevice.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
