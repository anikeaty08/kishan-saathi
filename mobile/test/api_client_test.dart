import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:krishisathi/core/network/api_client.dart';
import 'package:krishisathi/core/network/api_exception.dart';
import 'package:krishisathi/core/network/token_store.dart';

void main() {
  test('normalizes ClientException from JSON requests', () async {
    final client = ApiClient(
      baseUri: Uri.parse('https://example.test'),
      tokenStore: SecureTokenStore(),
      client: MockClient((_) async {
        throw http.ClientException('connection closed');
      }),
    );
    addTearDown(client.dispose);

    await expectLater(
      client.get('/health', auth: false),
      throwsA(
        isA<ApiException>().having(
          (error) => error.code,
          'code',
          'BACKEND_UNREACHABLE',
        ),
      ),
    );
  });

  test('normalizes ClientException from byte downloads', () async {
    final client = ApiClient(
      baseUri: Uri.parse('https://example.test'),
      tokenStore: SecureTokenStore(),
      client: MockClient((_) async {
        throw http.ClientException('response terminated');
      }),
    );
    addTearDown(client.dispose);

    await expectLater(
      client.getBytes('/image', auth: false),
      throwsA(
        isA<ApiException>().having(
          (error) => error.code,
          'code',
          'BACKEND_UNREACHABLE',
        ),
      ),
    );
  });

  test(
    'refreshes an expiring access token before an authenticated request',
    () async {
      final tokenStore = _FakeTokenStore(
        AuthTokens(
          accessToken: 'expired-access',
          refreshToken: 'refresh-token',
          expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
        ),
      );
      var refreshCalls = 0;
      final client =
          ApiClient(
              baseUri: Uri.parse('https://example.test'),
              tokenStore: tokenStore,
              client: MockClient((request) async {
                expect(request.headers['Authorization'], 'Bearer fresh-access');
                return http.Response('{}', 200);
              }),
            )
            ..tokenRefresher = () async {
              refreshCalls += 1;
              final refreshed = AuthTokens(
                accessToken: 'fresh-access',
                refreshToken: 'refresh-token',
                expiresAt: DateTime.now().add(const Duration(hours: 1)),
              );
              await tokenStore.write(refreshed);
              return refreshed;
            };
      addTearDown(client.dispose);

      await client.get('/api/v1/me');

      expect(refreshCalls, 1);
    },
  );

  test('refreshes once and retries after a backend 401', () async {
    final tokenStore = _FakeTokenStore(
      AuthTokens(
        accessToken: 'revoked-access',
        refreshToken: 'refresh-token',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    var requests = 0;
    var refreshes = 0;
    final client =
        ApiClient(
            baseUri: Uri.parse('https://example.test'),
            tokenStore: tokenStore,
            client: MockClient((request) async {
              requests += 1;
              if (requests == 1) return http.Response('{}', 401);
              expect(request.headers['Authorization'], 'Bearer fresh-access');
              return http.Response('{"ok":true}', 200);
            }),
          )
          ..tokenForceRefresher = () async {
            refreshes += 1;
            final refreshed = AuthTokens(
              accessToken: 'fresh-access',
              refreshToken: 'refresh-token',
              expiresAt: DateTime.now().add(const Duration(hours: 1)),
            );
            await tokenStore.write(refreshed);
            return refreshed;
          };
    addTearDown(client.dispose);

    expect(await client.get('/api/v1/me'), {'ok': true});
    expect(requests, 2);
    expect(refreshes, 1);
  });

  test('expires the session when a refreshed token is also rejected', () async {
    final tokenStore = _FakeTokenStore(
      AuthTokens(
        accessToken: 'revoked-access',
        refreshToken: 'refresh-token',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    var expiredCalls = 0;
    final client = ApiClient(
      baseUri: Uri.parse('https://example.test'),
      tokenStore: tokenStore,
      client: MockClient((_) async => http.Response('{}', 401)),
    );
    client.tokenForceRefresher = () async => tokenStore.tokens;
    client.sessionExpiredHandler = () async {
      expiredCalls += 1;
      await tokenStore.clear();
    };
    addTearDown(client.dispose);

    await expectLater(
      client.get('/api/v1/me'),
      throwsA(
        isA<ApiException>()
            .having((error) => error.code, 'code', 'AUTH_SESSION_EXPIRED')
            .having((error) => error.statusCode, 'status', 401),
      ),
    );
    expect(expiredCalls, 1);
    expect(tokenStore.tokens, isNull);
  });

  test(
    'malformed error JSON is normalized instead of leaking TypeError',
    () async {
      final client = ApiClient(
        baseUri: Uri.parse('https://example.test'),
        tokenStore: _FakeTokenStore(null),
        client: MockClient(
          (_) async => http.Response('{"error":{"code":42}}', 400),
        ),
      );
      addTearDown(client.dispose);

      await expectLater(
        client.get('/bad', auth: false),
        throwsA(
          isA<ApiException>()
              .having((error) => error.code, 'code', 'HTTP_400')
              .having((error) => error.statusCode, 'status', 400),
        ),
      );
    },
  );

  test('missing multipart file is returned as a typed upload error', () async {
    final tokenStore = _FakeTokenStore(
      AuthTokens(
        accessToken: 'access',
        refreshToken: 'refresh',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    final client = ApiClient(
      baseUri: Uri.parse('https://example.test'),
      tokenStore: tokenStore,
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    addTearDown(client.dispose);

    await expectLater(
      client.multipart(
        '/upload',
        fields: const {},
        filePaths: const ['definitely-missing-leaf-image.jpg'],
      ),
      throwsA(
        isA<ApiException>().having(
          (error) => error.code,
          'code',
          'UPLOAD_FILE_UNAVAILABLE',
        ),
      ),
    );
  });
}

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
