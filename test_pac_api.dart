/// Quick one-shot script to probe GetPowerStationPacByDayForApp.
/// Run with:  dart run test_pac_api.dart
///
/// Fill in your credentials below before running.

import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';

const _email       = 'pjacobjose@gmail.com';       // ← fill in
const _password    = 'Jj68351300';    // ← fill in
const _stationId   = 'e3c2c54c-c872-4fdb-8147-99381e685cff';

const _crossLoginUrl = 'https://www.semsportal.com/api/v1/Common/CrossLogin';
const _defaultToken  = '{"version":"v2.1.0","client":"ios","language":"en"}';

final _dio = Dio(BaseOptions(
  connectTimeout: const Duration(seconds: 15),
  receiveTimeout: const Duration(seconds: 20),
));

void main() async {
  // ── Step 1: CrossLogin ────────────────────────────────────────────────────
  print('\n[1] CrossLogin...');
  final loginRes = await _dio.post(
    _crossLoginUrl,
    data: {'account': _email, 'pwd': _password},
    options: Options(headers: {
      'Content-Type': 'application/json',
      'Token': _defaultToken,
    }),
  );

  final loginBody = loginRes.data as Map<String, dynamic>;
  _prettyPrint('CrossLogin response', loginBody);

  if (loginBody['code'] != 0 && loginBody['code'] != '0') {
    print('\n❌  Login failed: ${loginBody['msg']}');
    exit(1);
  }

  final data    = loginBody['data'] as Map<String, dynamic>;
  final apiBase = loginBody['api'] as String? ?? 'https://hk.semsportal.com/api/';
  final token   = jsonEncode({
    'uid'      : data['uid'],
    'timestamp': data['timestamp'],
    'token'    : data['token'],
    'client'   : data['client']   ?? 'ios',
    'version'  : data['version']  ?? 'v2.1.0',
    'language' : data['language'] ?? 'en',
  });

  print('\n✅  Logged in. API base: $apiBase');

  // ── Step 2: GetPowerStationPacByDayForApp ─────────────────────────────────
  final url = '${apiBase}v2/PowerStationMonitor/GetPowerStationPacByDayForApp';
  final headers = {
    'Content-Type': 'application/json',
    'Token': token,
  };

  // Try the last 3 days so we're guaranteed to hit a day with real data
  for (int daysAgo = 0; daysAgo <= 3; daysAgo++) {
    final day = DateTime.now().subtract(Duration(days: daysAgo));
    final dateStr =
        '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

    print('\n[2] $url  ($dateStr)');
    try {
      final res = await _dio.post(
        url,
        data: {'id': _stationId, 'date': dateStr},
        options: Options(headers: headers),
      );
      _prettyPrint('Response', res.data);

      final pacs = (res.data as Map)['data']?['pacs'];
      if (pacs != null && pacs is List && pacs.isNotEmpty) {
        print('\n✅  Got ${pacs.length} PAC samples — first entry structure:');
        _prettyPrint('pacs[0]', pacs.first);
        print('\n    Last entry:');
        _prettyPrint('pacs[last]', pacs.last);
        break; // found a day with real data
      } else {
        print('    ↩  No data for $dateStr, trying previous day...');
      }
    } on DioException catch (e) {
      print('    ❌ DioException: ${e.type} — ${e.message}');
      if (e.response != null) _prettyPrint('Error response', e.response!.data);
    }
  }
}

void _prettyPrint(String label, dynamic data) {
  const encoder = JsonEncoder.withIndent('  ');
  print('\n── $label ──');
  try {
    print(encoder.convert(data));
  } catch (_) {
    print(data.toString());
  }
}
