import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/krishisathi_app.dart';
import 'core/config/app_config.dart';
import 'core/localization/app_strings.dart';
import 'core/network/api_client.dart';
import 'core/network/krishi_api.dart';
import 'core/network/token_store.dart';
import 'core/permissions/app_permission_service.dart';
import 'core/storage/private_local_store.dart';
import 'features/farm/data/farm_repository.dart';
import 'features/farm/data/location_repository.dart';
import 'features/farm/data/timeline_repository.dart';
import 'features/home/data/weather_repository.dart';
import 'features/profile/data/memory_repository.dart';
import 'features/profile/data/reminder_repository.dart';
import 'features/saathi/data/chat_repository.dart';
import 'features/saathi/data/voice_repository.dart';
import 'features/scan/data/diagnosis_repository.dart';
import 'features/scan/data/scan_queue_repository.dart';
import 'features/shared/presentation/app_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString('assets/fonts/Sora-OFL.txt');
    yield LicenseEntryWithLineBreaks(['Sora'], license);
  });
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final preferences = await SharedPreferences.getInstance();
  final config = AppConfig.fromEnvironment();
  final tokenStore = SecureTokenStore();
  final apiClient = ApiClient(
    baseUri: config.apiBaseUri,
    tokenStore: tokenStore,
  );
  final api = KrishiApi(apiClient);
  final privateLocalStore = SecurePrivateLocalStore();
  final controller = AppController(
    config: config,
    preferences: preferences,
    tokenStore: tokenStore,
    apiClient: apiClient,
    farmRepository: FarmRepository(api),
    locationRepository: LocationRepository(api),
    chatRepository: ChatRepository(api),
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
    permissionService: const DeviceAppPermissionService(),
  );
  await controller.initialize();
  await AppStrings.load(controller.locale);

  runApp(KrishiSathiApp(controller: controller));
}
