import 'package:dio/dio.dart';
import '../models/session.dart';
import '../models/station_monitor.dart';
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
