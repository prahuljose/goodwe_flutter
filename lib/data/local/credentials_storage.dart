import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists email + password in the platform's secure enclave
/// (Android Keystore / iOS Keychain).
/// Only written on a successful login; cleared on explicit logout.
class CredentialsStorage {
  static const _emailKey     = 'sems_email';
  static const _passwordKey  = 'sems_password';
  static const _stationIdKey = 'sems_station_id';

  static const defaultStationId = 'e3c2c54c-c872-4fdb-8147-99381e685cff';

  // Use EncryptedSharedPreferences on Android for hardware-backed encryption
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<void> save(String email, String password) async {
    await _storage.write(key: _emailKey, value: email);
    await _storage.write(key: _passwordKey, value: password);
  }

  Future<void> saveStationId(String stationId) async {
    await _storage.write(key: _stationIdKey, value: stationId);
  }

  Future<SavedCredentials?> load() async {
    final email = await _storage.read(key: _emailKey);
    final password = await _storage.read(key: _passwordKey);
    if (email == null || password == null) return null;
    final stationId =
        await _storage.read(key: _stationIdKey) ?? defaultStationId;
    return SavedCredentials(email: email, password: password, stationId: stationId);
  }

  Future<String> loadStationId() async {
    return await _storage.read(key: _stationIdKey) ?? defaultStationId;
  }

  Future<void> clear() async {
    await _storage.delete(key: _emailKey);
    await _storage.delete(key: _passwordKey);
    await _storage.delete(key: _stationIdKey);
  }
}

class SavedCredentials {
  final String email;
  final String password;
  final String stationId;
  const SavedCredentials({
    required this.email,
    required this.password,
    this.stationId = CredentialsStorage.defaultStationId,
  });
}
