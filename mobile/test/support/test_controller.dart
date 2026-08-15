import 'package:flutter/material.dart';
import 'package:krishisathi/core/config/app_config.dart';
import 'package:krishisathi/core/localization/app_strings.dart';
import 'package:krishisathi/core/models/app_models.dart';
import 'package:krishisathi/core/network/api_client.dart';
import 'package:krishisathi/core/network/krishi_api.dart';
import 'package:krishisathi/core/network/token_store.dart';
import 'package:krishisathi/core/permissions/app_permission_service.dart';
import 'package:krishisathi/core/storage/private_local_store.dart';
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
  String farmerName = 'Test Farmer',
  ChatRepository? chatRepository,
  ChatOutboxStore? chatOutboxStore,
  AppPermissionService? permissionService,
  SecureTokenStore? tokenStore,
}) async {
  SharedPreferences.setMockInitialValues({
    'onboarding_complete': onboardingComplete,
    'preview_mode': !live,
    'preferred_language': locale,
    'farmer_name': farmerName,
    'notifications_enabled': false,
    'location_enabled': false,
    'camera_enabled': false,
  });
  final preferences = await SharedPreferences.getInstance();
  final config = AppConfig(
    apiBaseUri: Uri.parse('http://localhost:8000'),
    awsRegion: 'ap-south-1',
    environment: 'test',
  );
  final resolvedTokenStore = tokenStore ?? SecureTokenStore();
  final apiClient = ApiClient(
    baseUri: config.apiBaseUri,
    tokenStore: resolvedTokenStore,
  );
  final api = KrishiApi(apiClient);
  final privateLocalStore = InMemoryPrivateLocalStore();
  final controller =
      AppController(
          config: config,
          preferences: preferences,
          tokenStore: resolvedTokenStore,
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
          scanQueueRepository: ScanQueueRepository(
            preferences,
            privateLocalStore: privateLocalStore,
          ),
          privateLocalStore: privateLocalStore,
          permissionService: permissionService ?? const TestPermissionService(),
        )
        ..initialized = true
        ..onboardingComplete = onboardingComplete
        ..previewMode = !live
        ..isAuthenticated = live
        ..farmerName = farmerName
        ..locale = Locale(locale);
  await AppStrings.load(controller.locale);
  return controller;
}

class TestPermissionService implements AppPermissionService {
  const TestPermissionService({this.response = AppPermissionState.granted});

  final AppPermissionState response;

  @override
  Future<bool> openSettings() async => true;

  @override
  Future<AppPermissionState> request(AppPermissionKind kind) async => response;

  @override
  Future<AppPermissionState> status(AppPermissionKind kind) async =>
      AppPermissionState.denied;
}

void seedTestFarmData(AppController controller) {
  controller
    ..farms = DemoData.farms
    ..diagnoses = DemoData.diagnoses
    ..reminders = DemoData.reminders;
}
