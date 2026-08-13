import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'api_exception.dart';
import 'token_store.dart';

class CognitoAuthService {
  CognitoAuthService({
    required this.config,
    required this.tokenStore,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final AppConfig config;
  final SecureTokenStore tokenStore;
  final http.Client _client;

  Uri get _endpoint =>
      Uri.parse('https://cognito-idp.${config.awsRegion}.amazonaws.com/');

  Future<void> signIn({required String email, required String password}) async {
    _ensureConfigured();
    final payload = await _call('InitiateAuth', {
      'AuthFlow': 'USER_PASSWORD_AUTH',
      'ClientId': config.cognitoAppClientId,
      'AuthParameters': {'USERNAME': email.trim(), 'PASSWORD': password},
    });
    await _storeAuthenticationResult(payload['AuthenticationResult']);
  }

  Future<bool> signUp({required String email, required String password}) async {
    _ensureConfigured();
    final payload = await _call('SignUp', {
      'ClientId': config.cognitoAppClientId,
      'Username': email.trim(),
      'Password': password,
      'UserAttributes': [
        {'Name': 'email', 'Value': email.trim()},
      ],
    });
    return payload['UserConfirmed'] as bool? ?? false;
  }

  Future<void> confirmSignUp({
    required String email,
    required String code,
  }) async {
    await _call('ConfirmSignUp', {
      'ClientId': config.cognitoAppClientId,
      'Username': email.trim(),
      'ConfirmationCode': code.trim(),
    });
  }

  Future<void> forgotPassword({required String email}) async {
    _ensureConfigured();
    await _call('ForgotPassword', {
      'ClientId': config.cognitoAppClientId,
      'Username': email.trim(),
    });
  }

  Future<void> confirmForgotPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    _ensureConfigured();
    await _call('ConfirmForgotPassword', {
      'ClientId': config.cognitoAppClientId,
      'Username': email.trim(),
      'ConfirmationCode': code.trim(),
      'Password': newPassword,
    });
  }

  Future<AuthTokens?> refreshIfNeeded() async {
    final current = await tokenStore.read();
    if (current == null || !current.needsRefresh) return current;
    final payload = await _call('InitiateAuth', {
      'AuthFlow': 'REFRESH_TOKEN_AUTH',
      'ClientId': config.cognitoAppClientId,
      'AuthParameters': {'REFRESH_TOKEN': current.refreshToken},
    });
    final result = payload['AuthenticationResult'];
    if (result is! Map<String, dynamic>) {
      throw const ApiException(
        code: 'AUTH_INVALID_RESPONSE',
        message: 'Invalid sign-in response',
      );
    }
    final refreshed = AuthTokens(
      accessToken: result['AccessToken'] as String,
      refreshToken: current.refreshToken,
      idToken: result['IdToken'] as String? ?? current.idToken,
      expiresAt: DateTime.now().add(
        Duration(seconds: result['ExpiresIn'] as int? ?? 3600),
      ),
    );
    await tokenStore.write(refreshed);
    return refreshed;
  }

  Future<void> _storeAuthenticationResult(Object? raw) async {
    if (raw is! Map<String, dynamic>) {
      throw const ApiException(
        code: 'AUTH_INVALID_RESPONSE',
        message: 'Invalid sign-in response',
      );
    }
    final accessToken = raw['AccessToken'] as String?;
    final refreshToken = raw['RefreshToken'] as String?;
    if (accessToken == null || refreshToken == null) {
      throw const ApiException(
        code: 'AUTH_CHALLENGE_REQUIRED',
        message: 'Additional sign-in step required',
      );
    }
    await tokenStore.write(
      AuthTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
        idToken: raw['IdToken'] as String?,
        expiresAt: DateTime.now().add(
          Duration(seconds: raw['ExpiresIn'] as int? ?? 3600),
        ),
      ),
    );
  }

  Future<Map<String, dynamic>> _call(
    String operation,
    Map<String, Object?> body,
  ) async {
    try {
      final response = await _client
          .post(
            _endpoint,
            headers: {
              'Content-Type': 'application/x-amz-json-1.1',
              'X-Amz-Target': 'AWSCognitoIdentityProviderService.$operation',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));
      final payload = response.bodyBytes.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final providerCode = (payload['__type'] as String? ?? 'AUTH_FAILED')
            .split('#')
            .last;
        throw ApiException(
          code: providerCode.toUpperCase(),
          message: payload['message'] as String? ?? 'Authentication failed',
          statusCode: response.statusCode,
        );
      }
      return payload;
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException(
        code: 'REQUEST_TIMEOUT',
        message: 'Sign-in timed out',
      );
    } on SocketException {
      throw const ApiException(
        code: 'NETWORK_UNAVAILABLE',
        message: 'No network connection',
      );
    } on FormatException {
      throw const ApiException(
        code: 'AUTH_INVALID_RESPONSE',
        message: 'Invalid sign-in response',
      );
    }
  }

  void _ensureConfigured() {
    if (!config.isCognitoConfigured) {
      throw const ApiException(
        code: 'AUTH_NOT_CONFIGURED',
        message: 'Cognito has not been configured for this build',
      );
    }
  }
}
