/// Base class for all SEMS-related errors
sealed class SemsError implements Exception {
  final String message;
  const SemsError(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

/// Token expired or invalid — user must re-authenticate
class SemsAuthError extends SemsError {
  const SemsAuthError([super.message = 'Session expired. Please sign in again.']);
}

/// No internet connection or request timed out
class SemsNetworkError extends SemsError {
  const SemsNetworkError([super.message = 'No internet connection.']);
}

/// HTTP 5xx or unexpected server response
class SemsServerError extends SemsError {
  final int? statusCode;
  const SemsServerError(super.message, {this.statusCode});
}

/// API returned a non-zero business error code
class SemsApiError extends SemsError {
  final dynamic code;
  const SemsApiError(super.message, {this.code});
}
