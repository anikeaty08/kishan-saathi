class AppConfig {
  const AppConfig({
    required this.apiBaseUri,
    required this.awsRegion,
    required this.cognitoUserPoolId,
    required this.cognitoAppClientId,
    required this.environment,
  });

  factory AppConfig.fromEnvironment() {
    const apiBaseUrl = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://10.0.2.2:8000',
    );
    return AppConfig(
      apiBaseUri: Uri.parse(apiBaseUrl),
      awsRegion: const String.fromEnvironment(
        'AWS_REGION',
        defaultValue: 'ap-south-1',
      ),
      cognitoUserPoolId: const String.fromEnvironment('COGNITO_USER_POOL_ID'),
      cognitoAppClientId: const String.fromEnvironment('COGNITO_APP_CLIENT_ID'),
      environment: const String.fromEnvironment(
        'APP_ENV',
        defaultValue: 'development',
      ),
    );
  }

  final Uri apiBaseUri;
  final String awsRegion;
  final String cognitoUserPoolId;
  final String cognitoAppClientId;
  final String environment;

  bool get isCognitoConfigured =>
      cognitoUserPoolId.isNotEmpty && cognitoAppClientId.isNotEmpty;
  bool get isProduction => environment == 'production';
}
