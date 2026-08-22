class AppConfig {
  const AppConfig({
    required this.apiBaseUri,
    required this.awsRegion,
    required this.environment,
    this.enablePreviewMode = false,
    this.mapTileUrlTemplate = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  });

  factory AppConfig.fromEnvironment() {
    const apiBaseUrl = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://10.0.2.2:8000',
    );
    final config = AppConfig(
      apiBaseUri: Uri.parse(apiBaseUrl),
      awsRegion: const String.fromEnvironment(
        'AWS_REGION',
        defaultValue: 'ap-northeast-1',
      ),
      environment: const String.fromEnvironment(
        'APP_ENV',
        defaultValue: 'development',
      ),
      enablePreviewMode: const bool.fromEnvironment(
        'ENABLE_PREVIEW_MODE',
        defaultValue: false,
      ),
      mapTileUrlTemplate: const String.fromEnvironment(
        'MAP_TILE_URL_TEMPLATE',
        defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      ),
    );
    config.validateForStartup();
    return config;
  }

  final Uri apiBaseUri;
  final String awsRegion;
  final String environment;
  final bool enablePreviewMode;
  final String mapTileUrlTemplate;

  bool get isProduction => environment.trim().toLowerCase() == 'production';

  void validateForStartup() {
    if (!apiBaseUri.hasScheme || apiBaseUri.host.isEmpty) {
      throw StateError('API_BASE_URL must be an absolute network URL.');
    }
    if (apiBaseUri.userInfo.isNotEmpty ||
        apiBaseUri.hasQuery ||
        apiBaseUri.hasFragment) {
      throw StateError(
        'API_BASE_URL must not contain credentials, a query, or a fragment.',
      );
    }
    if (!const {'http', 'https'}.contains(apiBaseUri.scheme.toLowerCase())) {
      throw StateError('API_BASE_URL must use HTTP or HTTPS.');
    }
    if (!isProduction) return;

    if (apiBaseUri.scheme.toLowerCase() != 'https' ||
        _isLocalDevelopmentHost(apiBaseUri.host)) {
      throw StateError(
        'Production API_BASE_URL must be a non-local HTTPS endpoint.',
      );
    }
    if (enablePreviewMode) {
      throw StateError('Preview mode cannot be enabled in production.');
    }
    final mapUri = Uri.tryParse(mapTileUrlTemplate);
    if (mapUri == null || mapUri.scheme.toLowerCase() != 'https') {
      throw StateError('Production map tiles must use HTTPS.');
    }
    if (mapUri.host.toLowerCase() == 'tile.openstreetmap.org') {
      throw StateError(
        'Production must use an approved map tile provider, not the public '
        'OpenStreetMap tile endpoint.',
      );
    }
  }
}

bool _isLocalDevelopmentHost(String host) {
  final normalized = host.toLowerCase();
  if (normalized == 'localhost' ||
      normalized.endsWith('.localhost') ||
      normalized.endsWith('.local') ||
      normalized == '::' ||
      normalized == '::1' ||
      normalized.startsWith('fc') ||
      normalized.startsWith('fd') ||
      normalized.startsWith('fe8') ||
      normalized.startsWith('fe9') ||
      normalized.startsWith('fea') ||
      normalized.startsWith('feb')) {
    return true;
  }

  final octets = normalized.split('.').map(int.tryParse).toList();
  if (octets.length != 4 || octets.any((octet) => octet == null)) {
    return false;
  }
  final values = octets.cast<int>();
  if (values.any((octet) => octet < 0 || octet > 255)) return false;

  return values[0] == 0 ||
      values[0] == 10 ||
      values[0] == 127 ||
      (values[0] == 100 && values[1] >= 64 && values[1] <= 127) ||
      (values[0] == 169 && values[1] == 254) ||
      (values[0] == 172 && values[1] >= 16 && values[1] <= 31) ||
      (values[0] == 192 && values[1] == 168);
}
