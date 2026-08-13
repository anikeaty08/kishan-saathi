import 'package:flutter/material.dart';
import 'package:krishisathi/core/config/app_config.dart';
import 'package:krishisathi/core/localization/app_strings.dart';
import 'package:krishisathi/core/network/api_client.dart';
import 'package:krishisathi/core/network/krishi_api.dart';
import 'package:krishisathi/core/network/token_store.dart';
import 'package:krishisathi/features/farm/data/farm_repository.dart';
import 'package:krishisathi/features/farm/data/location_repository.dart';
import 'package:krishisathi/features/farm/data/timeline_repository.dart';
import 'package:krishisathi/features/home/data/weather_repository.dart';
import 'package:krishisathi/features/profile/data/memory_repository.dart';
import 'package:krishisathi/features/profile/data/reminder_repository.dart';
import 'package:krishisathi/features/saathi/data/chat_repository.dart';
import 'package:krishisathi/features/saathi/data/chat_outbox_store.dart';
import 'package:krishisathi/features/saathi/data/voice_repository.dart';
import 'package:krishisathi/features/scan/data/diagnosis_repository.dart';
import 'package:krishisathi/features/scan/data/scan_queue_repository.dart';
import 'package:krishisathi/features/shared/presentation/app_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppController> createTestController({
  String locale = 'en',
  bool onboardingComplete = true,
  bool live = false,
  ChatRepository? chatRepository,
  ChatOutboxStore? chatOutboxStore,
}) async {
  SharedPreferences.setMockInitialValues({
    'onboarding_complete': onboardingComplete,
    'preview_mode': !live,
    'preferred_language': locale,
    'farmer_name': 'Test Farmer',
  });
  final preferences = await SharedPreferences.getInstance();
  final config = AppConfig(
    apiBaseUri: Uri.parse('http://localhost:8000'),
    awsRegion: 'ap-south-1',
    cognitoUserPoolId: live ? 'ap-south-1_test' : '',
    cognitoAppClientId: live ? 'test-client' : '',
    environment: 'test',
  );
  final tokenStore = SecureTokenStore();
  final apiClient = ApiClient(
    baseUri: config.apiBaseUri,
    tokenStore: tokenStore,
  );
  final api = KrishiApi(apiClient);
  final controller =
      AppController(
          config: config,
          preferences: preferences,
          tokenStore: tokenStore,
          apiClient: apiClient,
          farmRepository: FarmRepository(api),
          locationRepository: LocationRepository(api),
          chatRepository: chatRepository ?? ChatRepository(api),
          chatOutboxStore: chatOutboxStore ?? InMemoryChatOutboxStore(),
          voiceRepository: VoiceRepository(api),
          diagnosisRepository: DiagnosisRepository(api),
          weatherRepository: WeatherRepository(api),
          reminderRepository: ReminderRepository(api),
          memoryRepository: MemoryRepository(api),
          timelineRepository: TimelineRepository(api),
          scanQueueRepository: ScanQueueRepository(preferences),
        )
        ..initialized = true
        ..onboardingComplete = onboardingComplete
        ..previewMode = !live
        ..isAuthenticated = live
        ..farmerName = 'Test Farmer'
        ..locale = Locale(locale);
  await AppStrings.load(controller.locale);
  return controller;
}
