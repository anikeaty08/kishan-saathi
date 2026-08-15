import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:krishisathi/core/network/account_auth_service.dart';
import 'package:krishisathi/core/network/api_client.dart';
import 'package:krishisathi/core/network/api_exception.dart';
import 'package:krishisathi/core/network/token_store.dart';

void main() {
  test('sign-in uses FastAPI and stores the returned session', () async {
    final store = _FakeTokenStore(null);
    final client = ApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      tokenStore: store,
      client: MockClient((request) async {
        expect(request.url.path, '/api/v1/auth/sign-in');
        expect(request.headers, isNot(contains('Authorization')));
        return http.Response(jsonEncode(_tokenPayload()), 200);
      }),
    );
    final service = AccountAuthService(apiClient: client, tokenStore: store);

    await service.signIn(
      email: 'farmer@example.com',
      password: 'valid-password',
    );

    expect(store.tokens?.accessToken, 'fresh-access');
    client.dispose();
  });

  test('sign-up sends the farmer name through FastAPI', () async {
    final store = _FakeTokenStore(null);
    final client = ApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      tokenStore: store,
      client: MockClient((request) async {
        expect(request.url.path, '/api/v1/auth/sign-up');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['name'], 'Nikhil Kumar');
        expect(body['email'], 'farmer@example.com');
        expect(request.headers, isNot(contains('Authorization')));
        return http.Response(jsonEncode({'confirmed': false}), 201);
      }),
    );
    final service = AccountAuthService(apiClient: client, tokenStore: store);

    final confirmed = await service.signUp(
      name: 'Nikhil Kumar',
      email: 'farmer@example.com',
      password: 'valid-password',
    );

    expect(confirmed, isFalse);
    client.dispose();
  });

  test('coalesces simultaneous refresh requests through FastAPI', () async {
    final store = _FakeTokenStore(_expiredTokens());
    var calls = 0;
    final client = ApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      tokenStore: store,
      client: MockClient((request) async {
        calls += 1;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return http.Response(jsonEncode(_tokenPayload()), 200);
      }),
    );
    final service = AccountAuthService(apiClient: client, tokenStore: store);

    final refreshed = await Future.wait([
      service.refreshIfNeeded(),
      service.refreshIfNeeded(),
      service.refreshIfNeeded(),
    ]);

    expect(calls, 1);
    expect(refreshed.map((tokens) => tokens?.accessToken).toSet(), {
      'fresh-access',
    });
    client.dispose();
  });

  test('normalizes a non-object authentication response', () async {
    final store = _FakeTokenStore(null);
    final client = ApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      tokenStore: store,
      client: MockClient((_) async => http.Response('[]', 200)),
    );
    final service = AccountAuthService(apiClient: client, tokenStore: store);

    await expectLater(
      service.signIn(email: 'farmer@example.com', password: 'valid-password'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.code,
          'code',
          'AUTH_INVALID_RESPONSE',
        ),
      ),
    );
    client.dispose();
  });

  test('resend confirmation calls the backend recovery endpoint', () async {
    final store = _FakeTokenStore(null);
    final client = ApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      tokenStore: store,
      client: MockClient((request) async {
        expect(request.url.path, '/api/v1/auth/resend');
        return http.Response('', 204);
      }),
    );
    final service = AccountAuthService(apiClient: client, tokenStore: store);

    await service.resendSignUpCode(email: 'farmer@example.com');
    client.dispose();
  });
}

Map<String, Object?> _tokenPayload() => {
  'access_token': 'fresh-access',
  'refresh_token': 'refresh-token',
  'id_token': 'id-token',
  'expires_in': 3600,
};

AuthTokens _expiredTokens() => AuthTokens(
  accessToken: 'expired-access',
  refreshToken: 'refresh-token',
  expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
);

class _FakeTokenStore extends SecureTokenStore {
  _FakeTokenStore(this.tokens);

  AuthTokens? tokens;

  @override
  Future<AuthTokens?> read() async => tokens;

  @override
  Future<void> write(AuthTokens tokens) async {
    this.tokens = tokens;
  }

  @override
  Future<void> clear() async {
    tokens = null;
  }
}
