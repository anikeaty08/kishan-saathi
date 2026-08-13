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
          'NETWORK_UNAVAILABLE',
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
          'NETWORK_UNAVAILABLE',
        ),
      ),
    );
  });
}
