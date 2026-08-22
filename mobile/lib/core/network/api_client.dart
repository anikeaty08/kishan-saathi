import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'api_exception.dart';
import 'token_store.dart';

class AuthenticatedResource {
  const AuthenticatedResource({required this.uri, required this.headers});

  final Uri uri;
  final Map<String, String> headers;
}

class ApiClient {
  ApiClient({
    required this.baseUri,
    required this.tokenStore,
    http.Client? client,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  final Uri baseUri;
  final SecureTokenStore tokenStore;
  final http.Client _client;
  final bool _ownsClient;
  Future<AuthTokens?> Function()? tokenRefresher;
  Future<AuthTokens?> Function()? tokenForceRefresher;
  Future<void> Function()? sessionExpiredHandler;
  static const _timeout = Duration(seconds: 20);
  static const _uploadTimeout = Duration(seconds: 60);
  static const _streamIdleTimeout = Duration(seconds: 90);

  Future<Object?> get(
    String path, {
    Map<String, Object?>? query,
    Map<String, String>? headers,
    bool auth = true,
  }) => _send('GET', path, query: query, headers: headers, auth: auth);

  Future<Object?> post(
    String path, {
    Object? body,
    Map<String, String>? headers,
    bool auth = true,
  }) => _send('POST', path, body: body, headers: headers, auth: auth);

  Future<Stream<String>> postStream(
    String path, {
    Object? body,
    Map<String, String>? headers,
    bool auth = true,
  }) => _withAuthRetry(auth, () async {
    try {
      final request = http.Request('POST', _resolve(path));
      request.headers.addAll(await _headers(auth: auth, extra: headers));
      if (body != null) request.body = jsonEncode(body);
      final streamed = await _client.send(request).timeout(_timeout);
      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        throw _exceptionFrom(await http.Response.fromStream(streamed));
      }
      final lines = streamed.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(
            _streamIdleTimeout,
            onTimeout: (sink) {
              sink.addError(
                const ApiException(
                  code: 'BACKEND_TIMEOUT',
                  message: 'The response stream timed out',
                ),
              );
              sink.close();
            },
          );
      return lines.transform(
        StreamTransformer<String, String>.fromHandlers(
          handleData: (line, sink) => sink.add(line),
          handleError: (error, stackTrace, sink) {
            if (error is ApiException) {
              sink.addError(error, stackTrace);
            } else if (error is TimeoutException) {
              sink.addError(
                const ApiException(
                  code: 'BACKEND_TIMEOUT',
                  message: 'The response stream timed out',
                ),
                stackTrace,
              );
            } else {
              sink.addError(
                const ApiException(
                  code: 'BACKEND_UNREACHABLE',
                  message: 'The response stream was interrupted',
                ),
                stackTrace,
              );
            }
          },
        ),
      );
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException(
        code: 'BACKEND_TIMEOUT',
        message: 'The response stream could not be opened in time',
      );
    } on http.ClientException {
      throw const ApiException(
        code: 'BACKEND_UNREACHABLE',
        message: 'The network request could not be completed',
      );
    } on IOException {
      throw const ApiException(
        code: 'BACKEND_UNREACHABLE',
        message: 'The backend could not be reached',
      );
    }
  });

  Future<Object?> patch(String path, {Object? body, bool auth = true}) =>
      _send('PATCH', path, body: body, auth: auth);

  Future<Object?> put(String path, {Object? body, bool auth = true}) =>
      _send('PUT', path, body: body, auth: auth);

  Future<void> delete(
    String path, {
    Map<String, Object?>? query,
    bool auth = true,
  }) async {
    await _send('DELETE', path, query: query, auth: auth);
  }

  Future<List<int>> getBytes(
    String path, {
    Map<String, String>? headers,
    bool auth = true,
  }) => _withAuthRetry(auth, () async {
    try {
      final response = await _client
          .get(
            _resolve(path),
            headers: await _headers(auth: auth, extra: headers),
          )
          .timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _exceptionFrom(response);
      }
      return response.bodyBytes;
    } on TimeoutException {
      throw const ApiException(
        code: 'BACKEND_TIMEOUT',
        message: 'Request timed out',
      );
    } on http.ClientException {
      throw const ApiException(
        code: 'BACKEND_UNREACHABLE',
        message: 'The network request could not be completed',
      );
    } on IOException {
      throw const ApiException(
        code: 'BACKEND_UNREACHABLE',
        message: 'The backend could not be reached',
      );
    }
  });

  Future<List<int>> postBytes(
    String path, {
    Map<String, String>? headers,
    bool auth = true,
  }) => _withAuthRetry(auth, () async {
    try {
      final response = await _client
          .post(
            _resolve(path),
            headers: await _headers(auth: auth, extra: headers),
          )
          .timeout(_uploadTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _exceptionFrom(response);
      }
      return response.bodyBytes;
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException(
        code: 'BACKEND_TIMEOUT',
        message: 'Audio generation timed out',
      );
    } on http.ClientException {
      throw const ApiException(
        code: 'BACKEND_UNREACHABLE',
        message: 'The network request could not be completed',
      );
    } on IOException {
      throw const ApiException(
        code: 'BACKEND_UNREACHABLE',
        message: 'The backend could not be reached',
      );
    }
  });

  Future<AuthenticatedResource> authenticatedResource(
    String path, {
    Map<String, String>? headers,
  }) async {
    final resolvedHeaders = await _headers(auth: true, extra: headers);
    return AuthenticatedResource(
      uri: _resolve(path),
      headers: Map.unmodifiable(resolvedHeaders),
    );
  }

  Future<Object?> multipart(
    String path, {
    required Map<String, String> fields,
    required List<String> filePaths,
    String fileField = 'images',
  }) => _withAuthRetry(true, () async {
    try {
      final request = http.MultipartRequest('POST', _resolve(path));
      request.headers.addAll(await _headers(auth: true));
      request.fields.addAll(fields);
      for (final filePath in filePaths) {
        request.files.add(
          await http.MultipartFile.fromPath(fileField, filePath),
        );
      }
      final streamed = await _client.send(request).timeout(_uploadTimeout);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _exceptionFrom(response);
      }
      return _decode(response);
    } on TimeoutException {
      throw const ApiException(
        code: 'BACKEND_TIMEOUT',
        message: 'Upload timed out',
      );
    } on http.ClientException {
      throw const ApiException(
        code: 'BACKEND_UNREACHABLE',
        message: 'The network request could not be completed',
      );
    } on FileSystemException {
      throw const ApiException(
        code: 'UPLOAD_FILE_UNAVAILABLE',
        message: 'A selected file is no longer available',
      );
    } on IOException {
      throw const ApiException(
        code: 'BACKEND_UNREACHABLE',
        message: 'The backend could not be reached',
      );
    } on FormatException {
      throw const ApiException(
        code: 'INVALID_RESPONSE',
        message: 'The server response could not be read',
      );
    } on TypeError {
      throw const ApiException(
        code: 'INVALID_RESPONSE',
        message: 'The server response could not be read',
      );
    }
  });

  Future<Object?> _send(
    String method,
    String path, {
    Map<String, Object?>? query,
    Object? body,
    Map<String, String>? headers,
    required bool auth,
  }) => _withAuthRetry(auth, () async {
    try {
      final request = http.Request(method, _resolve(path, query));
      request.headers.addAll(await _headers(auth: auth, extra: headers));
      if (body != null) {
        request.body = jsonEncode(body);
      }
      final streamed = await _client.send(request).timeout(_timeout);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _exceptionFrom(response);
      }
      return _decode(response);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException(
        code: 'BACKEND_TIMEOUT',
        message: 'Request timed out',
      );
    } on http.ClientException {
      throw const ApiException(
        code: 'BACKEND_UNREACHABLE',
        message: 'The network request could not be completed',
      );
    } on IOException {
      throw const ApiException(
        code: 'BACKEND_UNREACHABLE',
        message: 'The backend could not be reached',
      );
    } on FormatException {
      throw const ApiException(
        code: 'INVALID_RESPONSE',
        message: 'The server response could not be read',
      );
    } on TypeError {
      throw const ApiException(
        code: 'INVALID_RESPONSE',
        message: 'The server response could not be read',
      );
    }
  });

  Future<T> _withAuthRetry<T>(bool auth, Future<T> Function() request) async {
    try {
      return await request();
    } on ApiException catch (error) {
      if (!auth || !error.isUnauthorized || tokenForceRefresher == null) {
        rethrow;
      }
      AuthTokens? refreshed;
      try {
        refreshed = await tokenForceRefresher!();
      } on ApiException {
        await sessionExpiredHandler?.call();
        throw const ApiException(
          code: 'AUTH_SESSION_EXPIRED',
          message: 'Sign in again to continue',
          statusCode: 401,
        );
      }
      if (refreshed == null) {
        await sessionExpiredHandler?.call();
        throw const ApiException(
          code: 'AUTH_REQUIRED',
          message: 'Authentication is required',
          statusCode: 401,
        );
      }
      try {
        return await request();
      } on ApiException catch (retryError) {
        if (retryError.isUnauthorized) {
          await sessionExpiredHandler?.call();
          throw const ApiException(
            code: 'AUTH_SESSION_EXPIRED',
            message: 'Sign in again to continue',
            statusCode: 401,
          );
        }
        rethrow;
      }
    }
  }

  Future<Map<String, String>> _headers({
    required bool auth,
    Map<String, String>? extra,
  }) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json; charset=utf-8',
      ...?extra,
    };
    if (auth) {
      var tokens = await tokenStore.read();
      if (tokens == null) {
        throw const ApiException(
          code: 'AUTH_REQUIRED',
          message: 'Authentication is required',
          statusCode: 401,
        );
      }
      if (tokens.needsRefresh && tokenRefresher != null) {
        tokens = await tokenRefresher!();
        if (tokens == null) {
          throw const ApiException(
            code: 'AUTH_REQUIRED',
            message: 'Authentication is required',
            statusCode: 401,
          );
        }
      }
      headers['Authorization'] = 'Bearer ${tokens.accessToken}';
    }
    return headers;
  }

  Uri _resolve(String path, [Map<String, Object?>? query]) {
    final basePath = baseUri.path == '/'
        ? ''
        : baseUri.path.replaceFirst(RegExp(r'/$'), '');
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return baseUri.replace(
      path: '$basePath$normalizedPath',
      queryParameters: query,
    );
  }

  Object? _decode(http.Response response) {
    if (response.statusCode == 204 || response.bodyBytes.isEmpty) return null;
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  ApiException _exceptionFrom(http.Response response) {
    String code = 'HTTP_${response.statusCode}';
    String message = response.reasonPhrase ?? 'Request failed';
    String? requestId;
    final details = <ApiFieldError>[];
    try {
      final payload = jsonDecode(utf8.decode(response.bodyBytes));
      if (payload case {'error': final Map<String, dynamic> error}) {
        code = error['code'] as String? ?? code;
        message = error['message'] as String? ?? message;
        requestId = error['request_id'] as String?;
        final rawDetails = error['details'];
        if (rawDetails is List) {
          for (final item in rawDetails.whereType<Map<String, dynamic>>()) {
            details.add(
              ApiFieldError(
                field: item['field'] as String?,
                message:
                    item['message'] as String? ??
                    item['code'] as String? ??
                    code,
              ),
            );
          }
        }
      }
    } on FormatException {
      // Preserve the status-derived error for non-JSON provider responses.
    } on TypeError {
      // Preserve the status-derived error for non-JSON provider responses.
    }
    return ApiException(
      code: code,
      message: message,
      statusCode: response.statusCode,
      requestId: requestId,
      details: details,
    );
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
