import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/session.dart';

class SessionStorage {
  static const _key = 'sems_session';

  Future<void> save(SemsSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(session.toJson()));
  }

  Future<SemsSession?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      return SemsSession.fromJson(
        // Stored as flat map, not the API response shape — re-map it
        _flatToApiShape(jsonDecode(raw) as Map<String, dynamic>),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  /// Converts the stored flat map back to the API response shape
  /// that SemsSession.fromJson expects.
  Map<String, dynamic> _flatToApiShape(Map<String, dynamic> flat) => {
        'data': {
          'uid': flat['uid'],
          'timestamp': flat['timestamp'],
          'token': flat['token'],
          'client': flat['client'],
          'version': flat['version'],
          'language': flat['language'],
        },
        'api': flat['apiBase'],
        'components': {'msgSocketAdr': flat['socketAddr']},
      };
}
