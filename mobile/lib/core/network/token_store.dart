import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    this.idToken,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final String? idToken;

  bool get needsRefresh =>
      !expiresAt.isAfter(DateTime.now().add(const Duration(minutes: 2)));
}

class SecureTokenStore {
  SecureTokenStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(resetOnError: true),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.unlocked_this_device,
            ),
          );

  static const _accessKey = 'cognito_access_token';
  static const _refreshKey = 'cognito_refresh_token';
  static const _idKey = 'cognito_id_token';
  static const _expiryKey = 'cognito_token_expiry';

  final FlutterSecureStorage _storage;

  Future<AuthTokens?> read() async {
    final values = await _storage.readAll();
    final accessToken = values[_accessKey];
    final refreshToken = values[_refreshKey];
    final expiryValue = values[_expiryKey];
    if (accessToken == null || refreshToken == null || expiryValue == null) {
      return null;
    }
    final expiresAt = DateTime.tryParse(expiryValue);
    if (expiresAt == null) {
      await clear();
      return null;
    }
    return AuthTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: expiresAt,
      idToken: values[_idKey],
    );
  }

  Future<void> write(AuthTokens tokens) async {
    await Future.wait([
      _storage.write(key: _accessKey, value: tokens.accessToken),
      _storage.write(key: _refreshKey, value: tokens.refreshToken),
      _storage.write(
        key: _expiryKey,
        value: tokens.expiresAt.toIso8601String(),
      ),
      if (tokens.idToken != null)
        _storage.write(key: _idKey, value: tokens.idToken),
    ]);
  }

  Future<void> clear() => Future.wait([
    _storage.delete(key: _accessKey),
    _storage.delete(key: _refreshKey),
    _storage.delete(key: _idKey),
    _storage.delete(key: _expiryKey),
  ]);
}
