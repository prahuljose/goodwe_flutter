import 'dart:convert';

class SemsSession {
  final String uid;
  final int timestamp;
  final String token;
  final String client;
  final String version;
  final String language;
  final String apiBase;
  final String? socketAddr;

  const SemsSession({
    required this.uid,
    required this.timestamp,
    required this.token,
    required this.client,
    required this.version,
    required this.language,
    required this.apiBase,
    this.socketAddr,
  });

  factory SemsSession.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>;
    final components = json['components'] as Map<String, dynamic>?;
    return SemsSession(
      uid: data['uid'] as String,
      timestamp: data['timestamp'] as int,
      token: data['token'] as String,
      client: data['client'] as String,
      version: data['version'] as String,
      language: data['language'] as String,
      apiBase: json['api'] as String,
      socketAddr: components?['msgSocketAdr'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'timestamp': timestamp,
        'token': token,
        'client': client,
        'version': version,
        'language': language,
        'apiBase': apiBase,
        'socketAddr': socketAddr,
      };

  // Builds the Token header value for all authenticated API calls
  String get tokenHeader => jsonEncode({
        'version': version,
        'client': client,
        'language': language,
        'timestamp': timestamp.toString(),
        'uid': uid,
        'token': token,
      });
}
