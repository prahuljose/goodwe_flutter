import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:encrypt/encrypt.dart' as enc;
import '../local/tapo_storage.dart';
import '../models/tapo_device.dart';
import '../models/tapo_reading.dart';

/// Multi-device Tapo P110 integration over the local KLAP v2 protocol (port 80).
///
/// One Tapo account (email/password) is shared across all plugs. Each plug is
/// addressed by its LAN IP and identified by its stable KLAP `device_id`.
///
/// Protocol verified against python-kasa KlapTransportV2.
class TapoLocalRepository {
  final TapoStorage _storage;

  String? _email;
  String? _password;
  List<TapoDevice> _devices = [];

  // One live session per device IP, with a TTL so we re-handshake periodically.
  final Map<String, _KlapSession> _sessions = {};
  final Map<String, DateTime> _sessionTimes = {};
  static const _sessionTtl = Duration(minutes: 10);

  TapoLocalRepository({TapoStorage? storage})
      : _storage = storage ?? TapoStorage();

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> init() async {
    final account = await _storage.loadAccount();
    _email = account?.email;
    _password = account?.password;
    _devices = await _storage.loadDevices();
  }

  // ── Account ─────────────────────────────────────────────────────────────

  Future<void> setAccount(String email, String password) async {
    await _storage.saveAccount(email, password);
    _email = email;
    _password = password;
    _closeAllSessions(); // credentials changed — drop cached sessions
  }

  Future<bool> hasAccount() => _storage.hasAccount();
  bool get hasAccountSync => _email != null && _email!.isNotEmpty;

  // ── Devices ───────────────────────────────────────────────────────────────

  List<TapoDevice> get devices => List.unmodifiable(_devices);

  /// Connect to a plug at [ip], confirm credentials, and read its identity
  /// (device_id, nickname, model). Does NOT persist — the caller decides.
  Future<TapoDevice> probe(String ip) async {
    if (_email == null || _password == null) {
      throw TapoLocalException('Set your Tapo account first.');
    }
    final session = _KlapSession(ip: ip, email: _email!, password: _password!);
    await session.handshake();
    try {
      final info = await session.request('get_device_info', null);
      final id = info['device_id'] as String? ?? ip;
      final model = info['model'] as String? ?? 'P110';
      String nickname = 'Tapo Plug';
      final nickB64 = info['nickname'] as String? ?? '';
      try {
        final decoded = utf8.decode(base64.decode(nickB64));
        if (decoded.isNotEmpty) nickname = decoded;
      } catch (_) {}
      return TapoDevice(id: id, ip: ip, name: nickname, model: model);
    } finally {
      session.close();
    }
  }

  Future<void> addDevice(TapoDevice device) async {
    // Replace if a device with the same id already exists (e.g. IP changed)
    _devices = [
      ..._devices.where((d) => d.id != device.id),
      device,
    ];
    await _storage.saveDevices(_devices);
  }

  Future<void> removeDevice(String id) async {
    _devices = _devices.where((d) => d.id != id).toList();
    _sessions.remove(id)?.close();
    _sessionTimes.remove(id);
    await _storage.saveDevices(_devices);
  }

  Future<void> renameDevice(String id, String name) async {
    _devices = _devices
        .map((d) => d.id == id ? d.copyWith(name: name) : d)
        .toList();
    await _storage.saveDevices(_devices);
  }

  // ── Readings ──────────────────────────────────────────────────────────────

  /// Read one device. Never throws — returns an offline reading on failure.
  Future<TapoReading> read(TapoDevice device) async {
    try {
      final session = await _ensureSession(device);
      final data = await session.request('get_energy_usage', null);
      return TapoReading(
        device: device,
        liveW: ((data['current_power'] as num?)?.toDouble() ?? 0) / 1000.0,
        todayKwh: ((data['today_energy'] as num?)?.toDouble() ?? 0) / 1000.0,
        monthKwh: ((data['month_energy'] as num?)?.toDouble() ?? 0) / 1000.0,
        online: true,
      );
    } on TapoLocalException catch (e) {
      // Drop the session so the next attempt re-handshakes
      _sessions.remove(device.id)?.close();
      _sessionTimes.remove(device.id);
      return TapoReading.offline(device, e.message);
    } catch (e) {
      _sessions.remove(device.id)?.close();
      _sessionTimes.remove(device.id);
      return TapoReading.offline(device, e.toString());
    }
  }

  /// Read all configured devices concurrently.
  Future<List<TapoReading>> readAll() async {
    if (_devices.isEmpty) return [];
    return Future.wait(_devices.map(read));
  }

  // ── Session management ──────────────────────────────────────────────────

  Future<_KlapSession> _ensureSession(TapoDevice device) async {
    final existing = _sessions[device.id];
    final ts = _sessionTimes[device.id];
    final fresh = existing != null &&
        ts != null &&
        DateTime.now().difference(ts) < _sessionTtl;
    if (fresh) return existing;

    existing?.close();
    if (_email == null || _password == null) {
      throw TapoLocalException('Tapo account not configured.');
    }
    final session =
        _KlapSession(ip: device.ip, email: _email!, password: _password!);
    await session.handshake();
    _sessions[device.id] = session;
    _sessionTimes[device.id] = DateTime.now();
    return session;
  }

  void _closeAllSessions() {
    for (final s in _sessions.values) {
      s.close();
    }
    _sessions.clear();
    _sessionTimes.clear();
  }

  void dispose() => _closeAllSessions();
}

// ─── KLAP v2 session (one per device) ────────────────────────────────────────

class _KlapSession {
  final String ip;
  final String email;
  final String password;

  late final Uint8List _key;
  late final Uint8List _ivBase;
  late final Uint8List _sigKey;
  late int _seq;

  _TapoConnection? _conn;

  _KlapSession({required this.ip, required this.email, required this.password});

  Future<void> handshake() async {
    final authHash = Uint8List.fromList(crypto.sha256.convert([
      ...crypto.sha1.convert(utf8.encode(email)).bytes,
      ...crypto.sha1.convert(utf8.encode(password)).bytes,
    ]).bytes);

    final conn = _TapoConnection(ip);
    await conn.connect();
    _conn = conn;

    final localSeed = _randomBytes(16);
    final (s1, body1, _) = await conn.post('/app/handshake1', localSeed);
    if (s1 != 200 || body1.length < 48) {
      conn.close();
      throw TapoLocalException('Handshake 1 failed (status $s1).');
    }
    final remoteSeed = body1.sublist(0, 16);
    final serverHash = body1.sublist(16, 48);

    final expected =
        crypto.sha256.convert([...localSeed, ...remoteSeed, ...authHash]).bytes;
    if (!_bytesEqual(serverHash, expected)) {
      conn.close();
      throw TapoLocalException('Credentials rejected by plug.');
    }

    final h2 = Uint8List.fromList(
        crypto.sha256.convert([...remoteSeed, ...localSeed, ...authHash]).bytes);
    final (s2, _, _) = await conn.post('/app/handshake2', h2);
    if (s2 != 200) {
      conn.close();
      throw TapoLocalException('Handshake 2 failed (status $s2).');
    }

    _key = Uint8List.fromList(crypto.sha256
        .convert([...utf8.encode('lsk'), ...localSeed, ...remoteSeed, ...authHash])
        .bytes
        .sublist(0, 16));
    final ivFull = crypto.sha256
        .convert([...utf8.encode('iv'), ...localSeed, ...remoteSeed, ...authHash])
        .bytes;
    _ivBase = Uint8List.fromList(ivFull.sublist(0, 12));
    _seq = ByteData.sublistView(Uint8List.fromList(ivFull.sublist(28, 32)))
        .getInt32(0, Endian.big);
    _sigKey = Uint8List.fromList(crypto.sha256
        .convert([...utf8.encode('ldk'), ...localSeed, ...remoteSeed, ...authHash])
        .bytes
        .sublist(0, 28));
  }

  Future<Map<String, dynamic>> request(
      String method, Map<String, dynamic>? params) async {
    final conn = _conn;
    if (conn == null) throw TapoLocalException('Session not established.');

    _seq += 1;
    final seqBytes = _int32BigEndian(_seq);
    final iv = Uint8List.fromList([..._ivBase, ...seqBytes]);

    final payload = jsonEncode({'method': method, 'params': params});
    final encrypter = enc.Encrypter(enc.AES(enc.Key(_key), mode: enc.AESMode.cbc));
    final ciphertext = encrypter.encrypt(payload, iv: enc.IV(iv)).bytes;

    final sig = Uint8List.fromList(
        crypto.sha256.convert([..._sigKey, ...seqBytes, ...ciphertext]).bytes);
    final reqBody = Uint8List.fromList([...sig, ...ciphertext]);

    final (status, respBytes, _) =
        await conn.post('/app/request?seq=$_seq', reqBody);

    if (status != 200 || respBytes.length < 48) {
      throw TapoLocalException(
          'Request "$method" failed (status $status, ${respBytes.length}b).');
    }

    final decrypted =
        encrypter.decrypt(enc.Encrypted(respBytes.sublist(32)), iv: enc.IV(iv));
    final result = jsonDecode(decrypted) as Map<String, dynamic>;
    if (result['error_code'] != 0) {
      throw TapoLocalException('Device error ${result['error_code']}.');
    }
    return (result['result'] as Map<String, dynamic>?) ?? {};
  }

  void close() => _conn?.close();
}

// ─── Persistent keep-alive HTTP/1.1 connection over a raw socket ──────────────

class _TapoConnection {
  final String ip;
  late final Socket _socket;
  final _incoming = BytesBuilder();
  Completer<(int, Uint8List, String?)>? _pending;
  int _headerEnd = -1;
  int _contentLength = -1;
  String? cookie;

  _TapoConnection(this.ip);

  Future<void> connect() async {
    _socket = await Socket.connect(ip, 80, timeout: const Duration(seconds: 5));
    _socket.listen(_onData,
        onError: (e) => _pending?.completeError(e), cancelOnError: false);
  }

  void _onData(List<int> chunk) {
    _incoming.add(chunk);
    _tryComplete();
  }

  void _tryComplete() {
    final p = _pending;
    if (p == null || p.isCompleted) return;
    final raw = _incoming.toBytes();

    if (_headerEnd < 0) {
      final he = _findHeaderEnd(raw);
      if (he >= raw.length) return;
      _headerEnd = he;
      final headerText = latin1.decode(raw.sublist(0, _headerEnd));
      for (final line in headerText.split('\r\n')) {
        final lower = line.toLowerCase();
        if (lower.startsWith('content-length:')) {
          _contentLength = int.tryParse(line.split(':')[1].trim()) ?? 0;
        }
        if (lower.startsWith('set-cookie:')) {
          cookie = line.substring(line.indexOf(':') + 1).trim().split(';').first;
        }
      }
    }

    final bodyStart = _headerEnd + 4;
    if (_contentLength >= 0 && raw.length - bodyStart >= _contentLength) {
      final headerText = latin1.decode(raw.sublist(0, _headerEnd));
      final statusCode =
          int.tryParse(headerText.split('\r\n').first.split(' ')[1]) ?? 0;
      final bodyBytes =
          Uint8List.fromList(raw.sublist(bodyStart, bodyStart + _contentLength));
      final leftover = raw.sublist(bodyStart + _contentLength);
      _incoming.clear();
      _incoming.add(leftover);
      _headerEnd = -1;
      _contentLength = -1;
      p.complete((statusCode, bodyBytes, cookie));
    }
  }

  Future<(int, Uint8List, String?)> post(String path, Uint8List body) async {
    _pending = Completer<(int, Uint8List, String?)>();
    final headerLines = [
      'POST $path HTTP/1.1',
      'Host: $ip',
      'Accept: */*',
      'Content-Type: application/octet-stream',
      'Content-Length: ${body.length}',
      'Connection: keep-alive',
      if (cookie != null) 'Cookie: $cookie',
    ];
    _socket.add(utf8.encode('${headerLines.join('\r\n')}\r\n\r\n'));
    _socket.add(body);
    await _socket.flush();

    return _pending!.future.timeout(const Duration(seconds: 8),
        onTimeout: () => (0, Uint8List(0), null));
  }

  void close() {
    try {
      _socket.destroy();
    } catch (_) {}
  }
}

int _findHeaderEnd(Uint8List bytes) {
  for (var i = 0; i < bytes.length - 3; i++) {
    if (bytes[i] == 0x0D && bytes[i + 1] == 0x0A &&
        bytes[i + 2] == 0x0D && bytes[i + 3] == 0x0A) {
      return i;
    }
  }
  return bytes.length;
}

Uint8List _randomBytes(int n) {
  final rng = Random.secure();
  return Uint8List.fromList(List.generate(n, (_) => rng.nextInt(256)));
}

Uint8List _int32BigEndian(int value) {
  final b = ByteData(4)..setInt32(0, value, Endian.big);
  return b.buffer.asUint8List();
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class TapoLocalException implements Exception {
  final String message;
  const TapoLocalException(this.message);
  @override
  String toString() => 'TapoLocalException: $message';
}
