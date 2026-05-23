import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists email + password in the platform's secure enclave
/// (Android Keystore / iOS Keychain).
/// Only written on a successful login; cleared on explicit logout.
class CredentialsStorage {
  static const _emailKey = 'sems_email';
  static const _passwordKey = 'sems_password';

  // Use EncryptedSharedPreferences on Android for hardware-backed encryption
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<void> save(String email, String password) async {
    await _storage.write(key: _emailKey, value: email);
    await _storage.write(key: _passwordKey, value: password);
  }

  Future<SavedCredentials?> load() async {
    final email = await _storage.read(key: _emailKey);
    final password = await _storage.read(key: _passwordKey);
    if (email == null || password == null) return null;
    return SavedCredentials(email: email, password: password);
  }

  Future<void> clear() async {
    await _storage.delete(key: _emailKey);
    await _storage.delete(key: _passwordKey);
  }
}

class SavedCredentials {
  final String email;
  final String password;
  const SavedCredentials({required this.email, required this.password});
}
