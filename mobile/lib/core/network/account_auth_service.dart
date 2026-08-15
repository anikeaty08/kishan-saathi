import 'api_client.dart';
import 'api_endpoints.dart';
import 'api_exception.dart';
import 'token_store.dart';

/// Account lifecycle client. Cognito is intentionally hidden behind FastAPI.
class AccountAuthService {
  AccountAuthService({required this.apiClient, required this.tokenStore});

  final ApiClient apiClient;
  final SecureTokenStore tokenStore;
  Future<AuthTokens?>? _refreshInFlight;

  Future<void> signIn({required String email, required String password}) async {
    final payload = await apiClient.post(
      ApiEndpoints.authSignIn,
      auth: false,
      body: {'email': email.trim(), 'password': password},
    );
    await tokenStore.write(_tokens(payload));
  }

  Future<bool> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final payload = _map(
      await apiClient.post(
        ApiEndpoints.authSignUp,
        auth: false,
        body: {
          'name': name.trim(),
          'email': email.trim(),
          'password': password,
        },
      ),
    );
    final confirmed = payload['confirmed'];
    if (confirmed is! bool) {
      throw const ApiException(
        code: 'AUTH_INVALID_RESPONSE',
        message: 'The authentication response was incomplete',
      );
    }
    return confirmed;
  }

  Future<void> confirmSignUp({
    required String email,
    required String code,
  }) async {
    await apiClient.post(
      ApiEndpoints.authConfirm,
      auth: false,
      body: {'email': email.trim(), 'code': code.trim()},
    );
  }

  Future<void> resendSignUpCode({required String email}) async {
    await apiClient.post(
      ApiEndpoints.authResend,
      auth: false,
      body: {'email': email.trim()},
    );
  }

  Future<void> forgotPassword({required String email}) async {
    await apiClient.post(
      ApiEndpoints.authPasswordReset,
      auth: false,
      body: {'email': email.trim()},
    );
  }

  Future<void> confirmForgotPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    await apiClient.post(
      ApiEndpoints.authPasswordResetConfirm,
      auth: false,
      body: {
        'email': email.trim(),
        'code': code.trim(),
        'new_password': newPassword,
      },
    );
  }

  Future<AuthTokens?> refreshIfNeeded() async {
    final current = await tokenStore.read();
    if (current == null || !current.needsRefresh) return current;
    return _coalescedRefresh(current);
  }

  Future<AuthTokens?> refreshSession() async {
    final current = await tokenStore.read();
    if (current == null) return null;
    return _coalescedRefresh(current);
  }

  Future<AuthTokens?> _coalescedRefresh(AuthTokens current) async {
    final active = _refreshInFlight;
    if (active != null) return active;
    final refresh = _refresh(current);
    _refreshInFlight = refresh;
    try {
      return await refresh;
    } finally {
      if (identical(_refreshInFlight, refresh)) _refreshInFlight = null;
    }
  }

  Future<AuthTokens> _refresh(AuthTokens current) async {
    final payload = await apiClient.post(
      ApiEndpoints.authRefresh,
      auth: false,
      body: {'refresh_token': current.refreshToken},
    );
    final refreshed = _tokens(payload);
    await tokenStore.write(refreshed);
    return refreshed;
  }

  AuthTokens _tokens(Object? value) {
    final payload = _map(value);
    final accessToken = payload['access_token'];
    final refreshToken = payload['refresh_token'];
    final expiresIn = payload['expires_in'];
    final idToken = payload['id_token'];
    if (accessToken is! String ||
        refreshToken is! String ||
        expiresIn is! int ||
        (idToken != null && idToken is! String)) {
      throw const ApiException(
        code: 'AUTH_INVALID_RESPONSE',
        message: 'The authentication response was incomplete',
      );
    }
    return AuthTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      idToken: idToken as String?,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
    );
  }

  Map<String, dynamic> _map(Object? value) {
    if (value is Map<String, dynamic>) return value;
    throw const ApiException(
      code: 'AUTH_INVALID_RESPONSE',
      message: 'The authentication response could not be read',
    );
  }
}
