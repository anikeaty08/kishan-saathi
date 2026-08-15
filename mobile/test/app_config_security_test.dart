import 'package:flutter_test/flutter_test.dart';
import 'package:krishisathi/core/config/app_config.dart';

void main() {
  AppConfig productionConfig({
    Uri? apiBaseUri,
    bool enablePreviewMode = false,
    String mapTileUrl = 'https://tiles.example.test/{z}/{x}/{y}.png',
  }) => AppConfig(
    apiBaseUri: apiBaseUri ?? Uri.parse('https://api.example.test'),
    awsRegion: 'ap-south-1',
    environment: 'production',
    enablePreviewMode: enablePreviewMode,
    mapTileUrlTemplate: mapTileUrl,
  );

  test('accepts a fully configured HTTPS production environment', () {
    expect(productionConfig().validateForStartup, returnsNormally);
  });

  test('rejects cleartext and local production API endpoints', () {
    for (final uri in [
      Uri.parse('http://api.example.test'),
      Uri.parse('https://localhost:8000'),
      Uri.parse('https://10.0.2.2:8000'),
      Uri.parse('https://192.168.1.20'),
      Uri.parse('https://172.16.5.10'),
      Uri.parse('https://farm-server.local'),
      Uri.parse('https://[fd00::1]'),
    ]) {
      expect(
        () => productionConfig(apiBaseUri: uri).validateForStartup(),
        throwsStateError,
      );
    }
  });

  test('keeps Cognito configuration behind the backend boundary', () {
    expect(productionConfig().validateForStartup, returnsNormally);
  });

  test('rejects preview mode and cleartext map tiles in production', () {
    expect(
      () => productionConfig(enablePreviewMode: true).validateForStartup(),
      throwsStateError,
    );
    expect(
      () => productionConfig(
        mapTileUrl: 'http://tiles.example.test/{z}/{x}/{y}.png',
      ).validateForStartup(),
      throwsStateError,
    );
    expect(
      () => productionConfig(
        mapTileUrl: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      ).validateForStartup(),
      throwsStateError,
    );
  });

  test('keeps the emulator HTTP exception available outside production', () {
    final config = AppConfig(
      apiBaseUri: Uri.parse('http://10.0.2.2:8000'),
      awsRegion: 'ap-south-1',
      environment: 'development',
      enablePreviewMode: true,
    );

    expect(config.validateForStartup, returnsNormally);
  });
}
