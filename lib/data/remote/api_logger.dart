import 'dart:convert';

class ApiCallRecord {
  final String name;
  final String url;
  final DateTime timestamp;
  final int? statusCode;
  final Map<String, dynamic>? requestBody;
  final Map<String, dynamic>? responseBody;
  final String? errorMessage;

  ApiCallRecord({
    required this.name,
    required this.url,
    required this.timestamp,
    this.statusCode,
    this.requestBody,
    this.responseBody,
    this.errorMessage,
  });

  bool get isError =>
      errorMessage != null || (statusCode != null && statusCode! >= 400);

  String get prettyRequest => requestBody != null
      ? const JsonEncoder.withIndent('  ').convert(requestBody)
      : '';

  String get prettyResponse => responseBody != null
      ? const JsonEncoder.withIndent('  ').convert(responseBody)
      : errorMessage ?? '(no response body)';
}

class ApiCallLogger {
  final List<ApiCallRecord> _records = [];

  List<ApiCallRecord> get records => List.unmodifiable(_records);
  bool get isEmpty => _records.isEmpty;

  void add(ApiCallRecord record) => _records.add(record);
  void clear() => _records.clear();
}
