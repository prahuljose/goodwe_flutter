import '../data/remote/sems_api.dart';
import '../data/local/session_storage.dart';
import '../data/local/credentials_storage.dart';
import '../data/models/session.dart';

class AuthRepository {
  final SemsApi _api;
  final SessionStorage _storage;
  final CredentialsStorage _credStorage;

  SemsSession? _session;
  bool _isDemoMode = false;

  AuthRepository(this._api, this._storage, this._credStorage);

  SemsSession? get currentSession => _session;
  bool get isLoggedIn => _session != null;
  bool get isDemoMode => _isDemoMode;

  /// Enters demo mode — no credentials needed, no API calls made.
  void demoLogin() => _isDemoMode = true;

  Future<SemsSession> login(String email, String password) async {
    final session = await _api.crossLogin(email, password);
    _session = session;
    await _storage.save(session);
    // Save credentials for silent re-login on token expiry
    await _credStorage.save(email, password);
    return session;
  }

  Future<bool> tryRestoreSession() async {
    final saved = await _storage.load();
    if (saved != null) {
      _session = saved;
      return true;
    }
    return false;
  }

  /// Silently re-authenticates using saved credentials.
  /// Returns true and restores the session if successful.
  /// Returns false if no credentials are saved or the login fails
  /// (wrong password, network error, etc.).
  Future<bool> tryRelogin() async {
    final creds = await _credStorage.load();
    if (creds == null) return false;
    try {
      final session = await _api.crossLogin(creds.email, creds.password);
      _session = session;
      await _storage.save(session);
      return true;
    } catch (_) {
      // Network down, password changed, account disabled — caller decides what to do
      return false;
    }
  }

  /// Called when a token expiry is detected mid-session.
  /// Clears the session token but keeps saved credentials so
  /// tryRelogin() can recover automatically.
  Future<void> invalidateSession() async {
    _session = null;
    await _storage.clear();
  }

  /// User-initiated logout — clears everything including saved credentials.
  Future<void> logout() async {
    _session = null;
    _isDemoMode = false;
    await _storage.clear();
    await _credStorage.clear();
  }
}
