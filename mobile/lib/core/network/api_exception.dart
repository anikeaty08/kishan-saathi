class ApiFieldError {
  const ApiFieldError({this.field, required this.message});

  final String? field;
  final String message;
}

class ApiException implements Exception {
  const ApiException({
    required this.code,
    required this.message,
    this.statusCode,
    this.requestId,
    this.details = const [],
  });

  final String code;
  final String message;
  final int? statusCode;
  final String? requestId;
  final List<ApiFieldError> details;

  bool get isOffline =>
      code == 'NETWORK_UNAVAILABLE' || code == 'REQUEST_TIMEOUT';
  bool get isUnauthorized => statusCode == 401;
  bool get isModelUnavailable => code == 'LEAF_MODEL_NOT_CONFIGURED';

  @override
  String toString() => 'ApiException($code, status: $statusCode)';
}
