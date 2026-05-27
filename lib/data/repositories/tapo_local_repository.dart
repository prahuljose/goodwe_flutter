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

  /// Scan the local network for Tapo plugs.
  ///
  /// Scans every candidate /24 subnet — derived from all of the phone's
  /// private network interfaces AND the subnets of any already-added plugs
  /// (known-good). Returns the plugs that aren't already configured, plus a
  /// count of detected-but-already-added plugs (so the UI can explain an empty
  /// result). [onProgress] fires as hosts are scanned (scanned, total).
  Future<({List<TapoDevice> found, int alreadyAdded})> discover({
    void Function(int scanned, int total)? onProgress,
  }) async {
    if (_email == null || _password == null) {
      throw TapoLocalException('Set your Tapo account first.');
    }
    final subnets =
        await _candidateSubnets(knownIps: _devices.map((d) => d.ip));
    if (subnets.isEmpty) {
      throw TapoLocalException(
          'Could not determine your Wi-Fi network. Are you connected?');
    }

    // Phase 1 — fast detection across all candidate subnets.
    const batch = 20; // gentle on mobile sockets
    const probeTimeout = Duration(milliseconds: 1200);
    final total = subnets.length * 254;
    final hits = <String>[];
    var scanned = 0;

    for (final subnet in subnets) {
      for (var start = 1; start <= 254; start += batch) {
        final end = (start + batch - 1).clamp(1, 254);
        await Future.wait([
          for (var i = start; i <= end; i++)
            _looksLikeTapo('$subnet.$i', probeTimeout).then((isTapo) {
              if (isTapo) hits.add('$subnet.$i');
              onProgress?.call(++scanned, total);
            }),
        ]);
      }
    }

    // Phase 2 — identify each hit (handshake + get_device_info).
    final existingIds = _devices.map((d) => d.id).toSet();
    final existingIps = _devices.map((d) => d.ip).toSet();
    final found = <TapoDevice>[];
    var alreadyAdded = 0;
    for (final ip in hits) {
      if (existingIps.contains(ip)) {
        alreadyAdded++;
        continue;
      }
      try {
        final device = await probe(ip);
        if (existingIds.contains(device.id)) {
          alreadyAdded++;
        } else {
          found.add(device);
        }
      } catch (_) {
        // Credentials mismatch or transient error — skip silently
      }
    }
    return (found: found, alreadyAdded: alreadyAdded);
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
  ///
  /// The P110 closes idle keep-alive sockets after a few seconds, so a cached
  /// session can be stale. We attempt with the cached session; on any failure
  /// we drop it, re-handshake, and retry once. This makes a dead socket
  /// self-heal within a single read instead of surfacing a transient error.
  Future<TapoReading> read(TapoDevice device) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      // On the retry, force a fresh handshake
      final forceNew = attempt == 1;
      try {
        final session = await _ensureSession(device, forceNew: forceNew);
        final data = await session.request('get_energy_usage', null);
        return TapoReading(
          device: device,
          liveW: ((data['current_power'] as num?)?.toDouble() ?? 0) / 1000.0,
          todayKwh: ((data['today_energy'] as num?)?.toDouble() ?? 0) / 1000.0,
          monthKwh: ((data['month_energy'] as num?)?.toDouble() ?? 0) / 1000.0,
          online: true,
        );
      } catch (e) {
        // Drop the (possibly stale) session before retrying / giving up
        _sessions.remove(device.id)?.close();
        _sessionTimes.remove(device.id);
        if (attempt == 1) {
          final msg = e is TapoLocalException ? e.message : e.toString();
          return TapoReading.offline(device, msg);
        }
        // else: loop again with a fresh handshake
      }
    }
    return TapoReading.offline(device, 'Unreachable.');
  }

  /// Read all configured devices concurrently.
  Future<List<TapoReading>> readAll() async {
    if (_devices.isEmpty) return [];
    return Future.wait(_devices.map(read));
  }

  // ── Session management ──────────────────────────────────────────────────

  Future<_KlapSession> _ensureSession(TapoDevice device,
      {bool forceNew = false}) async {
    final existing = _sessions[device.id];
    final ts = _sessionTimes[device.id];
    final fresh = !forceNew &&
        existing != null &&
        existing.isAlive &&
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

  /// True while the underlying socket is still open.
  bool get isAlive => _conn?.isAlive ?? false;

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
  bool _closed = false;

  _TapoConnection(this.ip);

  /// False once the device (or network) has closed the socket.
  bool get isAlive => !_closed;

  Future<void> connect() async {
    _socket = await Socket.connect(ip, 80, timeout: const Duration(seconds: 5));
    _socket.listen(
      _onData,
      onError: (e) {
        _closed = true;
        _pending?.completeError(e);
      },
      onDone: () {
        // Device closed the keep-alive connection — mark dead so the next
        // request fast-fails and triggers a fresh handshake.
        _closed = true;
        final p = _pending;
        if (p != null && !p.isCompleted) {
          p.completeError(const TapoLocalException('Connection closed.'));
        }
      },
      cancelOnError: false,
    );
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
    // Fast-fail if the socket is already dead — avoids an 8s timeout wait on a
    // stale keep-alive connection. The caller re-handshakes on failure.
    if (_closed) {
      throw const TapoLocalException('Connection closed (stale session).');
    }

    _pending = Completer<(int, Uint8List, String?)>();
    _headerEnd = -1;
    _contentLength = -1;

    final headerLines = [
      'POST $path HTTP/1.1',
      'Host: $ip',
      'Accept: */*',
      'Content-Type: application/octet-stream',
      'Content-Length: ${body.length}',
      'Connection: keep-alive',
      if (cookie != null) 'Cookie: $cookie',
    ];
    try {
      _socket.add(utf8.encode('${headerLines.join('\r\n')}\r\n\r\n'));
      _socket.add(body);
      await _socket.flush();
    } catch (e) {
      _closed = true;
      throw const TapoLocalException('Socket write failed (stale session).');
    }

    return _pending!.future.timeout(const Duration(seconds: 6),
        onTimeout: () {
      _closed = true; // treat a hung request as a dead connection
      return (0, Uint8List(0), null);
    });
  }

  void close() {
    try {
      _socket.destroy();
    } catch (_) {}
  }
}

/// Collect every candidate /24 subnet base (e.g. "192.168.0") to scan —
/// from all private network interfaces plus the subnets of already-added
/// plugs (known-good, in case interface enumeration misses the Wi-Fi one).
Future<Set<String>> _candidateSubnets({Iterable<String> knownIps = const []}) async {
  final subnets = <String>{};
  for (final ip in knownIps) {
    final p = ip.split('.');
    if (p.length == 4) subnets.add('${p[0]}.${p[1]}.${p[2]}');
  }
  final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4, includeLinkLocal: false);
  for (final iface in interfaces) {
    for (final addr in iface.addresses) {
      if (_isPrivateIp(addr.address)) {
        final p = addr.address.split('.');
        subnets.add('${p[0]}.${p[1]}.${p[2]}');
      }
    }
  }
  return subnets;
}

bool _isPrivateIp(String ip) {
  return ip.startsWith('192.168.') ||
      ip.startsWith('10.') ||
      RegExp(r'^172\.(1[6-9]|2[0-9]|3[01])\.').hasMatch(ip);
}

/// Lightweight one-shot probe: does [ip] answer the KLAP handshake1 with the
/// tell-tale HTTP 200 + 48-byte body? Never throws — returns false on anything.
Future<bool> _looksLikeTapo(String ip, Duration timeout) async {
  Socket? socket;
  try {
    socket = await Socket.connect(ip, 80, timeout: timeout);
    final seed = _randomBytes(16);
    final head = 'POST /app/handshake1 HTTP/1.1\r\n'
        'Host: $ip\r\n'
        'Accept: */*\r\n'
        'Content-Type: application/octet-stream\r\n'
        'Content-Length: 16\r\n\r\n';
    socket.add(utf8.encode(head));
    socket.add(seed);
    await socket.flush();

    final completer = Completer<bool>();
    final buf = BytesBuilder();
    late StreamSubscription sub;
    sub = socket.listen(
      (chunk) {
        buf.add(chunk);
        final raw = buf.toBytes();
        final he = _findHeaderEnd(raw);
        if (he >= raw.length) return; // headers incomplete
        final headerText = latin1.decode(raw.sublist(0, he));
        final status =
            int.tryParse(headerText.split('\r\n').first.split(' ')[1]) ?? 0;
        var cl = -1;
        for (final line in headerText.split('\r\n')) {
          if (line.toLowerCase().startsWith('content-length:')) {
            cl = int.tryParse(line.split(':')[1].trim()) ?? -1;
          }
        }
        if (!completer.isCompleted) {
          completer.complete(status == 200 && cl == 48);
        }
      },
      onError: (_) {
        if (!completer.isCompleted) completer.complete(false);
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete(false);
      },
      cancelOnError: false,
    );

    final result =
        await completer.future.timeout(timeout, onTimeout: () => false);
    await sub.cancel();
    return result;
  } catch (_) {
    return false;
  } finally {
    socket?.destroy();
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
