import 'package:dio/dio.dart';
import '../models/session.dart';
import '../models/station_monitor.dart';
import '../models/monthly_energy.dart';
import '../../core/constants.dart';
import '../../core/exceptions.dart';
import 'api_logger.dart';

class SemsApi {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
  ));
  final ApiCallLogger? _logger;

  SemsApi({ApiCallLogger? logger}) : _logger = logger;

  // ── CrossLogin ──────────────────────────────────────────────────────────

  Future<SemsSession> crossLogin(String email, String password) async {
    const url = ApiConstants.crossLoginUrl;
    // Mask credentials in the log — never record the real password
    final loggedRequest = {'account': email, 'pwd': '●●●●●●●●'};
    Response? resp;
    try {
      resp = await _dio.post(
        url,
        data: {'account': email, 'pwd': password},
        options: Options(headers: {
          'Content-Type': 'application/json',
          'Token': ApiConstants.defaultTokenHeader,
        }),
      );
      final session = _parseSession(resp);
      _logSuccess('CrossLogin', url, resp, loggedRequest);
      return session;
    } on SemsError catch (e) {
      _logFailure('CrossLogin', url, resp, loggedRequest, e.message);
      rethrow;
    } on DioException catch (e) {
      _logDio('CrossLogin', url, e, loggedRequest);
      throw _translateDio(e);
    } catch (e) {
      throw SemsApiError('Unexpected error: $e');
    }
  }

  // ── GetMonitorDetailByPowerstationId ────────────────────────────────────

  Future<StationMonitor> getMonitorDetail(
    SemsSession session,
    String powerStationId,
  ) async {
    final url = '${session.apiBase}${ApiConstants.monitorEndpoint}';
    final requestBody = {'powerStationId': powerStationId};
    Response? resp;
    try {
      resp = await _dio.post(
        url,
        data: requestBody,
        options: Options(headers: {
          'Content-Type': 'application/json',
          'Token': session.tokenHeader,
        }),
      );
      final monitor = _parseMonitor(resp);
      _logSuccess('GetMonitorDetail', url, resp, requestBody);
      return monitor;
    } on SemsError catch (e) {
      _logFailure('GetMonitorDetail', url, resp, requestBody, e.message);
      rethrow;
    } on DioException catch (e) {
      _logDio('GetMonitorDetail', url, e, requestBody);
      throw _translateDio(e);
    } catch (e) {
      throw SemsApiError('Unexpected error: $e');
    }
  }

  // ── GetPowerStationPacByDayForApp ────────────────────────────────────────

  Future<List<PacSample>> getPacByDay(
    SemsSession session,
    String stationId,
    DateTime date,
  ) async {
    final dateStr =
        '${date.year}-${_pad(date.month)}-${_pad(date.day)}';
    final url =
        '${session.apiBase}v2/PowerStationMonitor/GetPowerStationPacByDayForApp';
    final reqBody = {'id': stationId, 'date': dateStr};
    Response? resp;
    try {
      resp = await _dio.post(
        url,
        data: reqBody,
        options: Options(headers: {
          'Content-Type': 'application/json',
          'Token': session.tokenHeader,
        }),
      );
      final samples = _parsePacSamples(resp);
      _logSuccess('GetPacByDay($dateStr)', url, resp, reqBody);
      return samples;
    } on SemsError catch (e) {
      _logFailure('GetPacByDay($dateStr)', url, resp, reqBody, e.message);
      rethrow;
    } on DioException catch (e) {
      _logDio('GetPacByDay($dateStr)', url, e, reqBody);
      throw _translateDio(e);
    } catch (e) {
      throw SemsApiError('Unexpected error: $e');
    }
  }

  // ── GetChartByPlant (monthly — range "3") ───────────────────────────────────
  //
  // Confirmed endpoint from SEMS web portal network inspection.
  // Same endpoint also serves daily (range 2) and yearly (range "4") charts.
  // The 'date' can be any date within the target month.

  Future<List<DailyEnergy>> getPacByMonth(
    SemsSession session,
    String stationId,
    DateTime month,
  ) async {
    final dateStr =
        '${month.year}-${_pad(month.month)}-${_pad(month.day)}';
    final url = '${session.apiBase}v2/Charts/GetChartByPlant';
    final reqBody = {
      'id':           stationId,
      'date':         dateStr,
      'range':        '3',   // "3" = monthly view (string, not int — matches web portal)
      'chartIndexId': '3',   // PV generation chart
      'isDetailFull': '',
    };
    Response? resp;
    try {
      resp = await _dio.post(
        url,
        data: reqBody,
        options: Options(headers: {
          'Content-Type': 'application/json',
          'Token': session.tokenHeader,
        }),
      );
      final entries = _parseChartByPlant(resp, month);
      _logSuccess(
          'GetChartByPlant(month:${month.year}-${_pad(month.month)})',
          url, resp, reqBody);
      return entries;
    } on SemsError catch (e) {
      _logFailure('GetChartByPlant(monthly)', url, resp, reqBody, e.message);
      rethrow;
    } on DioException catch (e) {
      _logDio('GetChartByPlant(monthly)', url, e, reqBody);
      throw _translateDio(e);
    } catch (e) {
      throw SemsApiError('Unexpected error: $e');
    }
  }

  /// Parse the GetChartByPlant response.
  ///
  /// Confirmed shape (from live SEMS network inspection):
  ///   data.lines[n] → { name, unit, xy: [{x:"YYYY-MM", y:kWh}, …] }
  ///
  /// We pick the first line whose unit is "kWh" (PV Generation).
  /// Earlier guessed shapes are kept as fallbacks.
  List<DailyEnergy> _parseChartByPlant(Response response, DateTime month) {
    final body = _requireBody(response);
    final code = body['code'];
    if (!_isSuccess(code)) {
      final msg = body['msg'] as String? ?? 'Failed to fetch chart data';
      if (_isAuthCode(code, msg)) throw const SemsAuthError();
      throw SemsApiError(msg, code: code);
    }

    final data = body['data'];
    if (data == null) return [];

    // ── Primary shape: {"lines": [{"name":"PVGeneration","xy":[…]}]} ────────
    if (data is Map && data.containsKey('lines')) {
      final lines = data['lines'] as List? ?? [];
      if (lines.isEmpty) return [];

      // Prefer the kWh / PVGeneration line; fall back to first line
      Map<String, dynamic>? pvLine;
      for (final line in lines) {
        final m = line as Map<String, dynamic>;
        final unit = (m['unit'] as String?)?.toLowerCase() ?? '';
        final name = (m['name'] as String?)?.toLowerCase() ?? '';
        if (unit == 'kwh' || name.contains('generation') || name.contains('pv')) {
          pvLine = m;
          break;
        }
      }
      pvLine ??= lines.first as Map<String, dynamic>;

      final xy = pvLine['xy'] as List? ?? [];
      return xy
          .map((pt) {
            final p   = pt as Map<String, dynamic>;
            final kwh = (p['y'] as num?)?.toDouble() ?? 0.0;
            final dt  = _parseXLabel(p['x']?.toString() ?? '');
            return dt != null ? DailyEnergy(date: dt, kwh: kwh) : null;
          })
          .whereType<DailyEnergy>()
          .toList();
    }

    // ── Fallback A: top-level list of {x, y} ─────────────────────────────────
    if (data is List) {
      return data
          .map((e) {
            final m   = e as Map<String, dynamic>;
            final kwh = (m['y'] as num?)?.toDouble() ?? 0.0;
            final dt  = _parseXLabel(m['x']?.toString() ?? '');
            return dt != null ? DailyEnergy(date: dt, kwh: kwh) : null;
          })
          .whereType<DailyEnergy>()
          .toList();
    }

    // ── Fallback B: {"pac"/"pacs"/"list": [{date, power}]} ───────────────────
    if (data is Map) {
      final list = data['pac']  as List? ??
                   data['pacs'] as List? ??
                   data['list'] as List? ?? [];
      if (list.isNotEmpty) {
        return list
            .map((e) => DailyEnergy.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    }

    return [];
  }

  /// Parse the chart x-axis label into a [DateTime].
  /// Handles: "YYYY-MM", "YYYY-MM-DD", "MM/DD/YYYY", "1"…"31".
  DateTime? _parseXLabel(String label) {
    try {
      final s = label.trim();
      final parts = s.split(RegExp(r'[/\-]'));

      // "YYYY-MM" → monthly entry (day=1)
      if (parts.length == 2 && parts[0].length == 4) {
        return DateTime(int.parse(parts[0]), int.parse(parts[1]), 1);
      }
      // "YYYY-MM-DD" or "YYYY/MM/DD"
      if (parts.length == 3 && parts[0].length == 4) {
        return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      }
      // "MM/DD/YYYY"
      if (parts.length == 3 && parts[2].length == 4) {
        return DateTime(int.parse(parts[2]), int.parse(parts[0]), int.parse(parts[1]));
      }
      // Plain day number "1"…"31" — caller should pass [month] hint (not available here)
      // We skip these; they're handled only in the monthly-daily parser path.
    } catch (_) {}
    return null;
  }

  // ── GetAlarmList ──────────────────────────────────────────────────────────

  Future<List<AlarmRecord>> getAlarmList(
    SemsSession session,
    String stationId, {
    int pageIndex = 0,
    int pageSize  = 50,
  }) async {
    // NOTE: Endpoint path is a best guess — confirm from SEMS web portal
    // Alarms tab → DevTools → Network.  Update this URL once confirmed.
    final url = '${session.apiBase}v2/Alarm/GetAlarmListForApp';
    final reqBody = {
      'powerStationId': stationId,
      'pageIndex': pageIndex,
      'pageSize': pageSize,
    };
    Response? resp;
    try {
      resp = await _dio.post(
        url,
        data: reqBody,
        options: Options(headers: {
          'Content-Type': 'application/json',
          'Token': session.tokenHeader,
        }),
      );
      final alarms = _parseAlarmList(resp);
      _logSuccess('GetAlarmList', url, resp, reqBody);
      return alarms;
    } on SemsError catch (e) {
      _logFailure('GetAlarmList', url, resp, reqBody, e.message);
      rethrow;
    } on DioException catch (e) {
      _logDio('GetAlarmList', url, e, reqBody);
      throw _translateDio(e);
    } catch (e) {
      throw SemsApiError('Unexpected error: $e');
    }
  }

  List<AlarmRecord> _parseAlarmList(Response response) {
    final body = _requireBody(response);
    final code = body['code'];
    if (!_isSuccess(code)) {
      final msg = body['msg'] as String? ?? 'Failed to fetch alarm history';
      if (_isAuthCode(code, msg)) throw const SemsAuthError();
      throw SemsApiError(msg, code: code);
    }
    final data = body['data'];
    final List list;
    if (data is Map) {
      list = data['list'] as List? ??
          data['alarms'] as List? ??
          data['records'] as List? ?? [];
    } else if (data is List) {
      list = data;
    } else {
      return [];
    }
    return list
        .map((e) => AlarmRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  List<PacSample> _parsePacSamples(Response response) {
    final body = _requireBody(response);
    final code = body['code'];
    if (!_isSuccess(code)) {
      final msg = body['msg'] as String? ?? 'Failed to fetch chart data';
      if (_isAuthCode(code, msg)) throw const SemsAuthError();
      throw SemsApiError(msg, code: code);
    }
    final data = body['data'] as Map<String, dynamic>;
    final pacs = data['pacs'] as List? ?? [];
    return pacs
        .map((e) => PacSample.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');

  // ── Logger helpers ───────────────────────────────────────────────────────

  Map<String, dynamic>? _responseBody(Response? resp) =>
      resp?.data is Map<String, dynamic>
          ? resp!.data as Map<String, dynamic>
          : null;

  void _logSuccess(String name, String url, Response resp,
      Map<String, dynamic> request) {
    _logger?.add(ApiCallRecord(
      name: name,
      url: url,
      timestamp: DateTime.now(),
      statusCode: resp.statusCode,
      requestBody: request,
      responseBody: _responseBody(resp),
    ));
  }

  void _logFailure(String name, String url, Response? resp,
      Map<String, dynamic> request, String error) {
    _logger?.add(ApiCallRecord(
      name: name,
      url: url,
      timestamp: DateTime.now(),
      statusCode: resp?.statusCode,
      requestBody: request,
      responseBody: _responseBody(resp),
      errorMessage: error,
    ));
  }

  void _logDio(String name, String url, DioException e,
      Map<String, dynamic> request) {
    _logger?.add(ApiCallRecord(
      name: name,
      url: url,
      timestamp: DateTime.now(),
      statusCode: e.response?.statusCode,
      requestBody: request,
      responseBody: _responseBody(e.response),
      errorMessage: e.message ?? e.type.name,
    ));
  }

  // ── Response parsers ────────────────────────────────────────────────────

  SemsSession _parseSession(Response response) {
    final body = _requireBody(response);
    final code = body['code'];
    if (!_isSuccess(code)) {
      final msg = body['msg'] as String? ?? 'Login failed';
      // A login failure is always an API error, not an auth error
      throw SemsApiError(msg, code: code);
    }
    return SemsSession.fromJson(body);
  }

  StationMonitor _parseMonitor(Response response) {
    final body = _requireBody(response);
    final code = body['code'];
    if (!_isSuccess(code)) {
      final msg = body['msg'] as String? ?? 'Failed to fetch data';
      if (_isAuthCode(code, msg)) throw const SemsAuthError();
      throw SemsApiError(msg, code: code);
    }
    return StationMonitor.fromJson(body);
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  Map<String, dynamic> _requireBody(Response response) {
    final statusCode = response.statusCode ?? 0;
    if (statusCode >= 500) {
      throw SemsServerError(
        'Server error ($statusCode). Try again later.',
        statusCode: statusCode,
      );
    }
    if (statusCode == 401 || statusCode == 403) {
      throw const SemsAuthError();
    }
    final body = response.data;
    if (body is! Map<String, dynamic>) {
      throw SemsServerError('Unexpected response format (HTTP $statusCode).');
    }
    return body;
  }

  bool _isSuccess(dynamic code) => code == 0 || code == '0';

  /// Known SEMS auth-failure response codes and message patterns
  bool _isAuthCode(dynamic code, String? message) {
    const authCodes = {100, 101, -100, -1};
    if (authCodes.contains(code)) return true;
    final msg = message?.toLowerCase() ?? '';
    return msg.contains('token') ||
        msg.contains('login') ||
        msg.contains('auth') ||
        msg.contains('expir') ||
        msg.contains('unauthorized') ||
        msg.contains('session');
  }

  /// Translate Dio transport errors into our error types
  SemsError _translateDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const SemsNetworkError('Request timed out. Check your connection.');
      case DioExceptionType.connectionError:
        return const SemsNetworkError('Could not reach the server. Check your internet.');
      case DioExceptionType.badResponse:
        final status = e.response?.statusCode ?? 0;
        if (status == 401 || status == 403) return const SemsAuthError();
        if (status >= 500) {
          return SemsServerError('Server error ($status). Try again later.',
              statusCode: status);
        }
        return SemsApiError('Unexpected response (HTTP $status).');
      case DioExceptionType.cancel:
        return const SemsNetworkError('Request was cancelled.');
      default:
        return SemsApiError(e.message ?? 'Network error.');
    }
  }
}
