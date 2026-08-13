import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/app_config.dart';
import '../../../core/localization/app_language.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/models/app_models.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/cognito_auth_service.dart';
import '../../../core/network/token_store.dart';
import '../../farm/data/farm_repository.dart';
import '../../farm/data/location_repository.dart';
import '../../farm/data/timeline_repository.dart';
import '../../home/data/weather_repository.dart';
import '../../profile/data/memory_repository.dart';
import '../../profile/data/reminder_repository.dart';
import '../../saathi/data/chat_repository.dart';
import '../../saathi/data/chat_outbox_store.dart';
import '../../scan/data/diagnosis_repository.dart';
import '../../scan/data/scan_queue_repository.dart';

class AppController extends ChangeNotifier {
  AppController({
    required this.config,
    required this.preferences,
    required this.tokenStore,
    required this.apiClient,
    required this.farmRepository,
    required this.locationRepository,
    required this.chatRepository,
    required this.chatOutboxStore,
    required this.diagnosisRepository,
    required this.weatherRepository,
    required this.reminderRepository,
    required this.memoryRepository,
    required this.timelineRepository,
    required this.scanQueueRepository,
  }) : authService = CognitoAuthService(config: config, tokenStore: tokenStore);

  static const _localeKey = 'preferred_language';
  static const _nameKey = 'farmer_name';
  static const _onboardingKey = 'onboarding_complete';
  static const _previewKey = 'preview_mode';
  static const _themeKey = 'theme_mode';
  static const _notificationsKey = 'notifications_enabled';
  static const _locationKey = 'location_enabled';
  static const _cameraKey = 'camera_enabled';
  static const _areaUnitKey = 'preferred_area_unit';
  static const _chatDraftPrefix = 'chat_draft_';

  final AppConfig config;
  final SharedPreferences preferences;
  final SecureTokenStore tokenStore;
  final ApiClient apiClient;
  final FarmRepository farmRepository;
  final LocationRepository locationRepository;
  final ChatRepository chatRepository;
  final ChatOutboxStore chatOutboxStore;
  final DiagnosisRepository diagnosisRepository;
  final WeatherRepository weatherRepository;
  final ReminderRepository reminderRepository;
  final MemoryRepository memoryRepository;
  final TimelineRepository timelineRepository;
  final ScanQueueRepository scanQueueRepository;
  final CognitoAuthService authService;
  final _uuid = const Uuid();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _processingQueuedScans = false;

  bool initialized = false;
  bool onboardingComplete = false;
  bool previewMode = false;
  bool isAuthenticated = false;
  bool notificationsEnabled = true;
  bool locationEnabled = true;
  bool cameraEnabled = true;
  bool busy = false;
  ThemeMode themeMode = ThemeMode.system;
  String preferredAreaUnit = 'acre';
  Locale locale = const Locale('en');
  String farmerName = 'Anike';
  ApiException? lastError;

  WeatherSnapshot? weather = WeatherSnapshot(
    temperature: 26,
    conditionCode: 'partly_cloudy',
    rainChance: 42,
    humidity: 71,
    windKph: 12,
    fetchedAt: DateTime.now().subtract(const Duration(minutes: 18)),
  );
  List<FarmModel> farms = List.of(DemoData.farms);
  List<FarmReminder> reminders = List.of(DemoData.reminders);
  List<ReminderProposalModel> reminderProposals = const [];
  List<DiagnosisCaseModel> diagnoses = List.of(DemoData.diagnoses);
  List<ChatThreadModel> chats = List.of(DemoData.chats);
  final Map<String, Set<String>> _activeChatTurnIds = {};
  final Map<String, Timer> _chatTurnPollers = {};
  final Set<String> _refreshingChatTurns = {};
  List<MemoryFactModel> memories = List.of(DemoData.memories);
  List<DiagnosisReportModel> diagnosisReports = const [];
  List<QueuedScanModel> queuedScans = const [];
  final Map<String, List<TimelineEventModel>> plotTimelines = {};
  final Map<String, PlotWeatherModel> plotWeather = {};

  AppLanguage get selectedLanguage => AppLanguage.byCode(locale.languageCode);
  bool get canUseLiveServices => isAuthenticated && config.isCognitoConfigured;
  FarmModel? farmById(String id) => farms.cast<FarmModel?>().firstWhere(
    (farm) => farm?.id == id,
    orElse: () => null,
  );
  PlotModel? plotById(String id) {
    for (final farm in farms) {
      for (final plot in farm.plots) {
        if (plot.id == id) return plot;
      }
    }
    return null;
  }

  Future<void> initialize() async {
    locale = Locale(preferences.getString(_localeKey) ?? 'en');
    farmerName = preferences.getString(_nameKey) ?? 'Anike';
    onboardingComplete = preferences.getBool(_onboardingKey) ?? false;
    previewMode = preferences.getBool(_previewKey) ?? false;
    themeMode = switch (preferences.getString(_themeKey)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    notificationsEnabled = preferences.getBool(_notificationsKey) ?? true;
    locationEnabled = preferences.getBool(_locationKey) ?? true;
    cameraEnabled = preferences.getBool(_cameraKey) ?? true;
    preferredAreaUnit = switch (preferences.getString(_areaUnitKey)) {
      'hectare' => 'hectare',
      _ => 'acre',
    };
    queuedScans = await scanQueueRepository.load();
    final tokens = await tokenStore.read();
    isAuthenticated = tokens != null;
    if (tokens?.needsRefresh ?? false) {
      try {
        await authService.refreshIfNeeded();
      } on ApiException {
        await tokenStore.clear();
        isAuthenticated = false;
      }
    }
    if (!previewMode) {
      weather = null;
      farms = const [];
      reminders = const [];
      diagnoses = const [];
      chats = const [];
      memories = const [];
    }
    if (isAuthenticated) {
      try {
        await refreshProfile();
        await refreshFarms();
        await refreshDiagnoses();
        await refreshDiagnosisReports();
        await refreshChats();
        await refreshReminders();
        await refreshMemories();
        await refreshCurrentWeather(requestPermission: false);
      } on ApiException catch (error) {
        lastError = error;
      }
    }
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      if (results.any((result) => result != ConnectivityResult.none)) {
        unawaited(_submitQueuedScansWhenOnline());
      }
    });
    if (isAuthenticated && queuedScans.isNotEmpty) {
      unawaited(_submitQueuedScansWhenOnline());
    }
    initialized = true;
    notifyListeners();
  }

  Future<void> setLocale(String code) async {
    final nextLocale = AppLanguage.byCode(code).locale;
    await AppStrings.load(nextLocale);
    locale = nextLocale;
    await preferences.setString(_localeKey, code);
    notifyListeners();
    if (canUseLiveServices) {
      unawaited(_patchProfile({'preferred_language': code}));
    }
  }

  Future<void> setFarmerName(String value) async {
    final normalized = value.trim();
    if (normalized.isEmpty) return;
    farmerName = normalized;
    await preferences.setString(_nameKey, normalized);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode value) async {
    themeMode = value;
    await preferences.setString(_themeKey, value.name);
    notifyListeners();
  }

  Future<void> setPreferredAreaUnit(String value) async {
    if (value != 'acre' && value != 'hectare') return;
    preferredAreaUnit = value;
    await preferences.setString(_areaUnitKey, value);
    notifyListeners();
  }

  String formatArea(double area, String? sourceUnit, {bool compact = false}) {
    final normalizedSource = sourceUnit == 'hectare' ? 'hectare' : 'acre';
    final converted = switch ((normalizedSource, preferredAreaUnit)) {
      ('acre', 'hectare') => area / 2.47105381,
      ('hectare', 'acre') => area * 2.47105381,
      _ => area,
    };
    final unit = switch ((preferredAreaUnit, compact)) {
      ('hectare', true) => 'ha',
      ('hectare', false) => converted == 1 ? 'hectare' : 'hectares',
      ('acre', true) => 'ac',
      _ => converted == 1 ? 'acre' : 'acres',
    };
    return '${converted.toStringAsFixed(converted < 10 ? 1 : 0)} $unit';
  }

  String formatFarmArea(FarmModel farm, {bool compact = false}) {
    final total = farm.plots.fold<double>(0, (sum, plot) {
      final area = plot.area;
      if (area == null) return sum;
      if (preferredAreaUnit == 'hectare') {
        return sum + (plot.areaUnit == 'hectare' ? area : area / 2.47105381);
      }
      return sum + (plot.areaUnit == 'hectare' ? area * 2.47105381 : area);
    });
    return formatArea(total, preferredAreaUnit, compact: compact);
  }

  Future<void> completeOnboarding({bool preview = false}) async {
    onboardingComplete = true;
    previewMode = preview;
    await Future.wait([
      preferences.setBool(_onboardingKey, true),
      preferences.setBool(_previewKey, preview),
    ]);
    notifyListeners();
    if (!preview && canUseLiveServices && locationEnabled) {
      try {
        await refreshCurrentWeather();
      } on ApiException catch (error) {
        lastError = error;
      }
    }
  }

  Future<void> signIn(String email, String password) async {
    await _guard(() async {
      await authService.signIn(email: email, password: password);
      isAuthenticated = true;
      previewMode = false;
      onboardingComplete = true;
      await Future.wait([
        preferences.setBool(_previewKey, false),
        preferences.setBool(_onboardingKey, true),
      ]);
      await refreshProfile();
      await refreshFarms();
      await refreshDiagnoses();
      await refreshDiagnosisReports();
      await refreshChats();
      await refreshReminders();
      await refreshMemories();
      await refreshCurrentWeather(requestPermission: false);
    });
  }

  Future<bool> signUp(String email, String password) async {
    return _guardValue(
      () => authService.signUp(email: email, password: password),
    );
  }

  Future<void> confirmSignUp(String email, String code) async {
    await _guard(() => authService.confirmSignUp(email: email, code: code));
  }

  Future<void> requestPasswordReset(String email) async {
    await _guard(() => authService.forgotPassword(email: email));
  }

  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    await _guard(
      () => authService.confirmForgotPassword(
        email: email,
        code: code,
        newPassword: newPassword,
      ),
    );
  }

  Future<void> signOut() async {
    await tokenStore.clear();
    isAuthenticated = false;
    previewMode = false;
    onboardingComplete = false;
    farms = const [];
    reminders = const [];
    reminderProposals = const [];
    diagnoses = const [];
    diagnosisReports = const [];
    chats = const [];
    memories = const [];
    weather = null;
    await Future.wait([
      preferences.setBool(_previewKey, false),
      preferences.setBool(_onboardingKey, false),
    ]);
    notifyListeners();
  }

  Future<void> refreshProfile() async {
    if (!canUseLiveServices) return;
    await _guard(() async {
      final payload = await apiClient.get(ApiEndpoints.me);
      if (payload is Map<String, dynamic>) {
        final name = payload['name'] as String?;
        final language = payload['preferred_language'] as String?;
        if (name != null && name.isNotEmpty) farmerName = name;
        if (language != null) locale = AppLanguage.byCode(language).locale;
      }
    });
  }

  Future<void> _patchProfile(Map<String, Object?> values) async {
    try {
      await apiClient.patch(ApiEndpoints.me, body: values);
    } on ApiException catch (error) {
      lastError = error;
      notifyListeners();
    }
  }

  Future<void> refreshFarms() async {
    if (!canUseLiveServices) return;
    final loaded = await farmRepository.loadFarms();
    farms = loaded;
    notifyListeners();
  }

  Future<void> refreshChats() async {
    if (!canUseLiveServices) return;
    final loaded = await chatRepository.loadChats();
    chats = loaded
        .map(
          (chat) => ChatThreadModel(
            id: chat.id,
            title: chat.title,
            scope: chat.scope,
            scopeLabel: _chatScopeLabel(
              chat.scope,
              chat.farmId ?? chat.plotId ?? chat.diagnosisCaseId,
            ),
            farmId: chat.farmId,
            plotId: chat.plotId,
            diagnosisCaseId: chat.diagnosisCaseId,
            archived: chat.archived,
            messages: chat.messages,
          ),
        )
        .toList(growable: false);
    notifyListeners();
  }

  Future<FarmModel> addFarm({required String name}) async {
    return _guardValue(() async {
      final farm = canUseLiveServices
          ? await farmRepository.createFarm(name)
          : FarmModel(id: _uuid.v4(), name: name.trim(), plots: const []);
      farms = [...farms, farm];
      notifyListeners();
      return farm;
    });
  }

  Future<FarmModel> updateFarm({
    required String farmId,
    required String name,
  }) async {
    return _guardValue(() async {
      final index = farms.indexWhere((farm) => farm.id == farmId);
      if (index < 0) {
        throw const ApiException(
          code: 'FARM_NOT_FOUND',
          message: 'The farm could not be found',
          statusCode: 404,
        );
      }
      final current = farms[index];
      final updated = canUseLiveServices
          ? await farmRepository.updateFarm(current, name)
          : current.copyWith(name: name.trim());
      farms = [...farms]..[index] = updated;
      notifyListeners();
      return updated;
    });
  }

  Future<DeletionImpact> farmDeletionImpact(String farmId) async {
    final farm = farmById(farmId);
    if (farm == null) {
      throw const ApiException(
        code: 'FARM_NOT_FOUND',
        message: 'The farm could not be found',
        statusCode: 404,
      );
    }
    if (!canUseLiveServices) {
      return DeletionImpact(
        canDelete: farm.plots.isEmpty,
        linkedRecords: {'plots': farm.plots.length},
      );
    }
    return farmRepository.farmDeletionImpact(farmId);
  }

  Future<void> deleteFarm(String farmId) async {
    await _guard(() async {
      if (canUseLiveServices) await farmRepository.deleteFarm(farmId);
      farms = farms.where((farm) => farm.id != farmId).toList();
      notifyListeners();
    });
  }

  Future<PlotModel> addPlot({
    required String farmId,
    required String name,
    required LocationPoint location,
    required String cropName,
    required String cropStage,
    String? cropVariety,
    DateTime? sowingOrTransplantDate,
    double? area,
    String? areaUnit,
    String? soilNotes,
    String? irrigationDetails,
  }) async {
    return _guardValue(() async {
      final farmIndex = farms.indexWhere((farm) => farm.id == farmId);
      if (farmIndex < 0) {
        throw const ApiException(
          code: 'FARM_NOT_FOUND',
          message: 'The selected farm could not be found',
          statusCode: 404,
        );
      }
      final command = CreatePlotCommand(
        farmId: farmId,
        name: name,
        location: location,
        cropName: cropName,
        cropStage: cropStage,
        cropVariety: cropVariety,
        sowingOrTransplantDate: sowingOrTransplantDate,
        area: area,
        areaUnit: areaUnit,
        soilNotes: soilNotes,
        irrigationDetails: irrigationDetails,
      );
      final plot = canUseLiveServices
          ? await farmRepository.createPlot(command)
          : PlotModel(
              id: _uuid.v4(),
              farmId: farmId,
              name: name.trim(),
              area: area,
              areaUnit: areaUnit,
              soilType: _nullableText(soilNotes),
              irrigation: _nullableText(irrigationDetails),
              latitude: location.latitude,
              longitude: location.longitude,
              locationLabel: location.displayLabel,
              crops: [
                CropModel(
                  id: _uuid.v4(),
                  name: cropName.trim(),
                  variety: _nullableText(cropVariety),
                  stage: cropStage.trim(),
                  sownOn: sowingOrTransplantDate,
                ),
              ],
              activities: const [],
            );
      final farm = farms[farmIndex];
      farms = [...farms]
        ..[farmIndex] = farm.copyWith(plots: [...farm.plots, plot]);
      notifyListeners();
      return plot;
    });
  }

  Future<PlotModel> updatePlot({
    required String plotId,
    required String name,
    required LocationPoint location,
    double? area,
    String? areaUnit,
    String? soilNotes,
    String? irrigationDetails,
  }) async {
    return _guardValue(() async {
      for (var farmIndex = 0; farmIndex < farms.length; farmIndex++) {
        final farm = farms[farmIndex];
        final plotIndex = farm.plots.indexWhere((plot) => plot.id == plotId);
        if (plotIndex < 0) continue;
        final current = farm.plots[plotIndex];
        final updated = canUseLiveServices
            ? await farmRepository.updatePlot(
                current: current,
                name: name,
                location: location,
                area: area,
                areaUnit: areaUnit,
                soilNotes: soilNotes,
                irrigationDetails: irrigationDetails,
              )
            : current.copyWith(
                name: name.trim(),
                latitude: location.latitude,
                longitude: location.longitude,
                locationLabel: location.displayLabel,
                area: area,
                areaUnit: areaUnit,
                soilType: _nullableText(soilNotes),
                irrigation: _nullableText(irrigationDetails),
              );
        final plots = [...farm.plots]..[plotIndex] = updated;
        farms = [...farms]..[farmIndex] = farm.copyWith(plots: plots);
        notifyListeners();
        return updated;
      }
      throw const ApiException(
        code: 'PLOT_NOT_FOUND',
        message: 'The plot could not be found',
        statusCode: 404,
      );
    });
  }

  Future<ActivityCreationResult> addActivity({
    required String plotId,
    required String type,
    required String notes,
    required DateTime occurredAt,
    String? cropId,
    List<String> imagePaths = const [],
  }) async {
    for (var farmIndex = 0; farmIndex < farms.length; farmIndex++) {
      final farm = farms[farmIndex];
      final plotIndex = farm.plots.indexWhere((plot) => plot.id == plotId);
      if (plotIndex < 0) continue;
      final plot = farm.plots[plotIndex];
      final result = canUseLiveServices
          ? await farmRepository.createActivity(
              plotId: plotId,
              title: type,
              notes: notes,
              occurredAt: occurredAt,
              cropId: cropId,
              imagePaths: imagePaths,
            )
          : ActivityCreationResult(
              activity: FarmActivity(
                id: _uuid.v4(),
                type: type,
                title: type,
                occurredAt: occurredAt,
                notes: _nullableText(notes),
                cropId: cropId,
              ),
            );
      final updatedPlot = plot.copyWith(
        activities: [result.activity, ...plot.activities],
      );
      final updatedPlots = [...farm.plots]..[plotIndex] = updatedPlot;
      farms = [...farms]..[farmIndex] = farm.copyWith(plots: updatedPlots);
      notifyListeners();
      if (canUseLiveServices) unawaited(loadPlotTimeline(plotId));
      return result;
    }
    throw const ApiException(
      code: 'PLOT_NOT_FOUND',
      message: 'The plot could not be found',
      statusCode: 404,
    );
  }

  Future<void> loadPlotActivities(String plotId) async {
    if (!canUseLiveServices) return;
    final activities = await farmRepository.loadActivities(plotId);
    _replacePlotActivities(plotId, activities);
  }

  Future<FarmActivity> loadActivity({
    required String plotId,
    required String activityId,
  }) async {
    if (!canUseLiveServices) {
      final activity = plotById(plotId)?.activities
          .cast<FarmActivity?>()
          .firstWhere((item) => item?.id == activityId, orElse: () => null);
      if (activity != null) return activity;
      throw const ApiException(
        code: 'ACTIVITY_NOT_FOUND',
        message: 'The field activity could not be found',
        statusCode: 404,
      );
    }
    final activity = await farmRepository.loadActivity(activityId);
    _replaceActivity(plotId, activity);
    return activity;
  }

  Future<FarmActivity> updateActivity({
    required String plotId,
    required FarmActivity activity,
    required String title,
    required String notes,
    required DateTime occurredAt,
  }) async {
    final updated = canUseLiveServices
        ? await farmRepository.updateActivity(
            current: activity,
            title: title,
            notes: notes,
            occurredAt: occurredAt,
          )
        : activity.copyWith(
            type: title.toLowerCase(),
            title: title.trim(),
            notes: _nullableText(notes),
            occurredAt: occurredAt,
          );
    _replaceActivity(plotId, updated);
    unawaited(loadPlotTimeline(plotId));
    return updated;
  }

  Future<FarmActivity> addActivityPhoto({
    required String plotId,
    required FarmActivity activity,
    required String imagePath,
  }) async {
    if (!canUseLiveServices) return activity;
    final photo = await farmRepository.addActivityPhoto(activity.id, imagePath);
    final updated = activity.copyWith(photos: [...activity.photos, photo]);
    _replaceActivity(plotId, updated);
    return updated;
  }

  Future<void> deleteActivityPhoto({
    required String plotId,
    required FarmActivity activity,
    required String photoId,
  }) async {
    if (canUseLiveServices) {
      await farmRepository.deleteActivityPhoto(activity.id, photoId);
    }
    _replaceActivity(
      plotId,
      activity.copyWith(
        photos: activity.photos
            .where((photo) => photo.id != photoId)
            .toList(growable: false),
      ),
    );
  }

  Future<List<int>> loadActivityPhoto(String activityId, String photoId) =>
      farmRepository.loadActivityPhoto(activityId, photoId);

  Future<void> deleteActivity({
    required String plotId,
    required String activityId,
  }) async {
    if (canUseLiveServices) await farmRepository.deleteActivity(activityId);
    final plot = plotById(plotId);
    if (plot == null) return;
    _replacePlotActivities(
      plotId,
      plot.activities
          .where((activity) => activity.id != activityId)
          .toList(growable: false),
    );
    unawaited(loadPlotTimeline(plotId));
  }

  void _replaceActivity(String plotId, FarmActivity activity) {
    final plot = plotById(plotId);
    if (plot == null) return;
    final index = plot.activities.indexWhere((item) => item.id == activity.id);
    final activities = index < 0
        ? [activity, ...plot.activities]
        : ([...plot.activities]..[index] = activity);
    _replacePlotActivities(plotId, activities);
  }

  void _replacePlotActivities(String plotId, List<FarmActivity> activities) {
    for (var farmIndex = 0; farmIndex < farms.length; farmIndex++) {
      final farm = farms[farmIndex];
      final plotIndex = farm.plots.indexWhere((plot) => plot.id == plotId);
      if (plotIndex < 0) continue;
      final plots = [...farm.plots]
        ..[plotIndex] = farm.plots[plotIndex].copyWith(activities: activities);
      farms = [...farms]..[farmIndex] = farm.copyWith(plots: plots);
      notifyListeners();
      return;
    }
  }

  Future<void> addCrop({
    required String plotId,
    required String name,
    required String stage,
    String? variety,
    DateTime? sowingOrTransplantDate,
  }) async {
    final crop = canUseLiveServices
        ? await farmRepository.createCrop(
            plotId: plotId,
            name: name,
            stage: stage,
            variety: variety,
            sowingOrTransplantDate: sowingOrTransplantDate,
          )
        : CropModel(
            id: _uuid.v4(),
            name: name.trim(),
            stage: stage.trim(),
            variety: _nullableText(variety),
            sownOn: sowingOrTransplantDate,
          );
    _replaceCrop(plotId, crop, addIfMissing: true);
  }

  Future<void> editCrop({
    required String plotId,
    required CropModel crop,
    required String name,
    String? variety,
    DateTime? sowingOrTransplantDate,
  }) async {
    final updated = canUseLiveServices
        ? await farmRepository.updateCrop(
            current: crop,
            name: name,
            variety: variety,
            sowingOrTransplantDate: sowingOrTransplantDate,
          )
        : CropModel(
            id: crop.id,
            name: name.trim(),
            stage: crop.stage,
            variety: _nullableText(variety),
            sownOn: sowingOrTransplantDate,
            isActive: crop.isActive,
          );
    _replaceCrop(plotId, updated);
  }

  Future<void> updateCropStage({
    required String plotId,
    required CropModel crop,
    required String stage,
  }) async {
    final updated = canUseLiveServices
        ? await farmRepository.updateCropStage(crop, stage)
        : CropModel(
            id: crop.id,
            name: crop.name,
            stage: stage.trim(),
            variety: crop.variety,
            sownOn: crop.sownOn,
            isActive: crop.isActive,
          );
    _replaceCrop(plotId, updated);
    unawaited(loadPlotTimeline(plotId));
  }

  Future<void> closeCropCycle({
    required String plotId,
    required CropModel crop,
    required DateTime endedOn,
  }) async {
    final updated = canUseLiveServices
        ? await farmRepository.closeCropCycle(crop, endedOn)
        : CropModel(
            id: crop.id,
            name: crop.name,
            stage: crop.stage,
            variety: crop.variety,
            sownOn: crop.sownOn,
            isActive: false,
          );
    _replaceCrop(plotId, updated);
    unawaited(loadPlotTimeline(plotId));
  }

  Future<DeletionImpact> cropDeletionImpact(String cropId) async {
    if (!canUseLiveServices) {
      return const DeletionImpact(canDelete: true, linkedRecords: {});
    }
    return farmRepository.cropDeletionImpact(cropId);
  }

  Future<void> deleteCrop({
    required String plotId,
    required String cropId,
    required bool confirmHistoryLoss,
  }) async {
    if (canUseLiveServices) {
      await farmRepository.deleteCrop(
        cropId,
        confirmHistoryLoss: confirmHistoryLoss,
      );
    }
    final plot = plotById(plotId);
    if (plot == null) return;
    for (var farmIndex = 0; farmIndex < farms.length; farmIndex++) {
      final farm = farms[farmIndex];
      final plotIndex = farm.plots.indexWhere((item) => item.id == plotId);
      if (plotIndex < 0) continue;
      final plots = [...farm.plots]
        ..[plotIndex] = plot.copyWith(
          crops: plot.crops
              .where((crop) => crop.id != cropId)
              .toList(growable: false),
        );
      farms = [...farms]..[farmIndex] = farm.copyWith(plots: plots);
      notifyListeners();
      unawaited(loadPlotTimeline(plotId));
      return;
    }
  }

  void _replaceCrop(
    String plotId,
    CropModel crop, {
    bool addIfMissing = false,
  }) {
    for (var farmIndex = 0; farmIndex < farms.length; farmIndex++) {
      final farm = farms[farmIndex];
      final plotIndex = farm.plots.indexWhere((plot) => plot.id == plotId);
      if (plotIndex < 0) continue;
      final plot = farm.plots[plotIndex];
      final cropIndex = plot.crops.indexWhere((item) => item.id == crop.id);
      if (cropIndex < 0 && !addIfMissing) return;
      final crops = cropIndex < 0
          ? [crop, ...plot.crops]
          : ([...plot.crops]..[cropIndex] = crop);
      final plots = [...farm.plots]..[plotIndex] = plot.copyWith(crops: crops);
      farms = [...farms]..[farmIndex] = farm.copyWith(plots: plots);
      notifyListeners();
      return;
    }
  }

  Future<List<LocationPoint>> searchLocations(String query) async {
    if (!canUseLiveServices) {
      final normalized = query.trim().toLowerCase();
      return const [
            LocationPoint(
              latitude: 13.1377,
              longitude: 77.4786,
              label: 'Hesaraghatta, Karnataka',
              country: 'India',
            ),
            LocationPoint(
              latitude: 18.5204,
              longitude: 73.8567,
              label: 'Pune, Maharashtra',
              country: 'India',
            ),
            LocationPoint(
              latitude: 17.385,
              longitude: 78.4867,
              label: 'Hyderabad, Telangana',
              country: 'India',
            ),
          ]
          .where((item) => item.displayLabel.toLowerCase().contains(normalized))
          .toList();
    }
    return locationRepository.search(query, language: locale.languageCode);
  }

  Future<LocationPoint> currentDeviceLocation() =>
      locationRepository.currentDeviceLocation();

  Future<void> loadPlotTimeline(String plotId) async {
    if (!canUseLiveServices) {
      final plot = plotById(plotId);
      plotTimelines[plotId] = [
        for (final activity in plot?.activities ?? const <FarmActivity>[])
          TimelineEventModel(
            id: activity.id,
            category: 'activity',
            eventCode: 'activity.recorded',
            occurredAt: activity.occurredAt,
            referenceId: activity.id,
            data: {'title': activity.title, 'notes': activity.notes},
          ),
      ];
      notifyListeners();
      return;
    }
    plotTimelines[plotId] = (await timelineRepository.loadPlotTimeline(plotId))
        .items;
    notifyListeners();
  }

  Future<TimelinePageModel> fetchPlotTimeline(
    String plotId, {
    String? cropId,
    Set<String> categories = const {},
    DateTime? dateFrom,
    DateTime? dateTo,
    int limit = 30,
    int offset = 0,
  }) async {
    if (!canUseLiveServices) {
      final all = plotTimelines[plotId] ?? const <TimelineEventModel>[];
      final filtered = all
          .where((event) {
            if (categories.isNotEmpty && !categories.contains(event.category)) {
              return false;
            }
            if (cropId != null && event.data['crop_id'] != cropId) return false;
            if (dateFrom != null && event.occurredAt.isBefore(dateFrom)) {
              return false;
            }
            if (dateTo != null && event.occurredAt.isAfter(dateTo)) {
              return false;
            }
            return true;
          })
          .toList(growable: false);
      final page = filtered.skip(offset).take(limit).toList(growable: false);
      return TimelinePageModel(
        items: page,
        hasMore: offset + page.length < filtered.length,
        limit: limit,
        offset: offset,
      );
    }
    return timelineRepository.loadPlotTimeline(
      plotId,
      cropId: cropId,
      categories: categories,
      dateFrom: dateFrom,
      dateTo: dateTo,
      limit: limit,
      offset: offset,
    );
  }

  Future<void> refreshCurrentWeather({bool requestPermission = true}) async {
    if (!canUseLiveServices || !locationEnabled) return;
    try {
      final location = await locationRepository.currentDeviceLocation(
        requestPermission: requestPermission,
      );
      weather = await weatherRepository.current(
        latitude: location.latitude,
        longitude: location.longitude,
      );
      notifyListeners();
    } on ApiException catch (error) {
      if (requestPermission) rethrow;
      lastError = error;
    }
  }

  Future<PlotWeatherModel> loadPlotWeather(String plotId) async {
    if (!canUseLiveServices) {
      final current =
          weather ??
          WeatherSnapshot(
            temperature: 26,
            conditionCode: '2',
            rainChance: 20,
            humidity: 70,
            windKph: 12,
            fetchedAt: DateTime.now(),
          );
      final result = PlotWeatherModel(
        current: current,
        timezone: 'Asia/Kolkata',
        fetchedAt: current.fetchedAt,
        forecast: List.generate(
          7,
          (index) => ForecastDayModel(
            date: DateTime.now().add(Duration(days: index)),
            conditionCode: index == 2 ? '61' : '2',
            minimumTemperature: 20 + (index % 2),
            maximumTemperature: 29 + (index % 3),
            precipitationMm: index == 2 ? 8.4 : 0.8,
            rainChance: index == 2 ? 76 : 22,
            maximumWindKph: 14 + index.toDouble(),
          ),
        ),
      );
      plotWeather[plotId] = result;
      notifyListeners();
      return result;
    }
    final result = await weatherRepository.forPlot(plotId);
    plotWeather[plotId] = result;
    notifyListeners();
    return result;
  }

  Future<void> refreshReminders() async {
    if (!canUseLiveServices) return;
    final loaded = await reminderRepository.loadReminders();
    reminders = loaded
        .map(
          (item) => FarmReminder(
            id: item.id,
            title: item.title,
            dueAt: item.dueAt,
            plotName: item.plotId == null
                ? 'Farm task'
                : plotById(item.plotId!)?.name ?? 'Plot task',
            status: item.status,
            plotId: item.plotId,
            notes: item.notes,
            recurrenceDays: item.recurrenceDays,
          ),
        )
        .toList(growable: false);
    reminderProposals = await reminderRepository.loadProposals();
    notifyListeners();
  }

  Future<void> completeReminder(String id) async {
    if (!canUseLiveServices) {
      reminders = reminders
          .map(
            (item) => item.id == id
                ? item.copyWith(status: ReminderStatus.done)
                : item,
          )
          .toList();
      notifyListeners();
      return;
    }
    await _guard(() async {
      await reminderRepository.complete(id);
      await refreshReminders();
    });
  }

  Future<void> actOnReminder(
    String id, {
    required String action,
    DateTime? dueAt,
  }) async {
    if (!canUseLiveServices) {
      final status = switch (action) {
        'done' => ReminderStatus.done,
        'skip' => ReminderStatus.skipped,
        'cancel' => ReminderStatus.cancelled,
        _ => ReminderStatus.pending,
      };
      reminders = reminders
          .map(
            (item) => item.id == id
                ? item.copyWith(status: status, dueAt: dueAt)
                : item,
          )
          .toList(growable: false);
      notifyListeners();
      return;
    }
    await _guard(() async {
      await reminderRepository.act(id, action: action, dueAt: dueAt);
      await refreshReminders();
    });
  }

  Future<void> decideReminderProposal(
    String proposalId, {
    required bool accepted,
  }) async {
    await _guard(() async {
      await reminderRepository.decide(proposalId, accepted: accepted);
      await refreshReminders();
    });
  }

  Future<void> createReminder({
    required String title,
    required DateTime dueAt,
    String? notes,
    String? plotId,
    int? recurrenceDays,
  }) async {
    if (!canUseLiveServices) {
      reminders = [
        FarmReminder(
          id: _uuid.v4(),
          title: title.trim(),
          dueAt: dueAt,
          plotName: plotId == null
              ? 'Farm task'
              : plotById(plotId)?.name ?? 'Plot task',
          plotId: plotId,
          notes: _nullableText(notes),
          recurrenceDays: recurrenceDays,
        ),
        ...reminders,
      ];
      notifyListeners();
      return;
    }
    await _guard(() async {
      await reminderRepository.create(
        title: title,
        dueAt: dueAt,
        notes: notes,
        plotId: plotId,
        recurrenceDays: recurrenceDays,
      );
      await refreshReminders();
    });
  }

  Future<void> refreshMemories() async {
    if (!canUseLiveServices) return;
    memories = await memoryRepository.loadAll(farms: farms);
    notifyListeners();
  }

  Future<void> queueScan(
    List<String> paths, {
    String? cropName,
    String? plotId,
  }) async {
    final scan = await scanQueueRepository.enqueue(
      sourcePaths: paths,
      cropName: cropName,
      plotId: plotId,
    );
    queuedScans = [scan, ...queuedScans];
    notifyListeners();
  }

  Future<void> removeQueuedScan(String id) async {
    await scanQueueRepository.remove(id);
    queuedScans = queuedScans.where((scan) => scan.id != id).toList();
    notifyListeners();
  }

  Future<DiagnosisCaseModel> submitQueuedScan(QueuedScanModel scan) async {
    final diagnosis = await submitDiagnosis(
      imagePaths: scan.imagePaths,
      cropName: scan.cropName,
      plotId: scan.plotId,
    );
    await removeQueuedScan(scan.id);
    return diagnosis;
  }

  Future<void> _submitQueuedScansWhenOnline() async {
    if (_processingQueuedScans || !canUseLiveServices || queuedScans.isEmpty) {
      return;
    }
    _processingQueuedScans = true;
    try {
      for (final scan in List<QueuedScanModel>.of(queuedScans).reversed) {
        try {
          await submitQueuedScan(scan);
        } on ApiException catch (error) {
          lastError = error;
          notifyListeners();
          break;
        }
      }
    } finally {
      _processingQueuedScans = false;
    }
  }

  Future<DiagnosisCaseModel> submitDiagnosis({
    required List<String> imagePaths,
    String? cropName,
    String? plotId,
  }) async {
    if (!canUseLiveServices) {
      throw const ApiException(
        code: 'LEAF_MODEL_NOT_CONFIGURED',
        message: 'Leaf diagnosis is not connected for this build',
        statusCode: 503,
      );
    }
    final plot = plotId == null ? null : plotById(plotId);
    final farm = plotId == null
        ? null
        : farms.cast<FarmModel?>().firstWhere(
            (item) =>
                item?.plots.any((candidate) => candidate.id == plotId) ?? false,
            orElse: () => null,
          );
    final result = await diagnosisRepository.createDiagnosis(
      imagePaths: imagePaths,
      plantName: cropName,
      farmId: farm?.id,
      plotId: plotId,
      plotName: plot?.name,
    );
    diagnoses = [result, ...diagnoses];
    notifyListeners();
    return result;
  }

  Future<void> refreshDiagnoses() async {
    if (!canUseLiveServices) return;
    final loaded = await diagnosisRepository.loadDiagnoses();
    diagnoses = loaded.map(_withDiagnosisPlotName).toList(growable: false);
    notifyListeners();
  }

  Future<void> loadDiagnosis(String caseId) async {
    if (!canUseLiveServices) return;
    final loaded = _withDiagnosisPlotName(
      await diagnosisRepository.loadDiagnosis(caseId),
    );
    _replaceDiagnosis(loaded);
  }

  Future<DiagnosisCaseModel> addDiagnosisRetake({
    required String caseId,
    required List<String> imagePaths,
  }) async {
    final existing = diagnoses.cast<DiagnosisCaseModel?>().firstWhere(
      (item) => item?.id == caseId,
      orElse: () => null,
    );
    if (existing == null) {
      throw const ApiException(
        code: 'DIAGNOSIS_NOT_FOUND',
        message: 'The earlier leaf check could not be found',
        statusCode: 404,
      );
    }
    final updated = await diagnosisRepository.addRetake(
      caseId: caseId,
      imagePaths: imagePaths,
      plotName: existing.plotName,
    );
    _replaceDiagnosis(updated);
    return updated;
  }

  Future<List<int>> loadDiagnosisImage(String caseId, String imageId) =>
      diagnosisRepository.loadImage(caseId, imageId);

  Future<List<DiagnosisAssessmentModel>> loadDiagnosisHistory(
    String caseId,
  ) async {
    if (!canUseLiveServices) return const [];
    return diagnosisRepository.loadAssessmentHistory(caseId);
  }

  Future<DiagnosisCaseModel> linkDiagnosis({
    required DiagnosisCaseModel diagnosis,
    String? plotId,
    String? cropId,
  }) async {
    FarmModel? farm;
    final plot = plotId == null ? null : plotById(plotId);
    if (plot != null) farm = farmById(plot.farmId);
    final updated = canUseLiveServices
        ? await diagnosisRepository.linkDiagnosis(
            caseId: diagnosis.id,
            farmId: farm?.id,
            plotId: plot?.id,
            cropId: cropId,
            plotName: plot?.name,
          )
        : DiagnosisCaseModel(
            id: diagnosis.id,
            cropName: diagnosis.cropName,
            plotName: plot?.name,
            farmId: farm?.id,
            plotId: plot?.id,
            cropId: cropId,
            createdAt: diagnosis.createdAt,
            imageAsset: diagnosis.imageAsset,
            imagePath: diagnosis.imagePath,
            imageIds: diagnosis.imageIds,
            predictions: diagnosis.predictions,
            qualityFlags: diagnosis.qualityFlags,
            isSample: diagnosis.isSample,
            confidenceLabel: diagnosis.confidenceLabel,
            retakeRecommended: diagnosis.retakeRecommended,
          );
    _replaceDiagnosis(updated);
    return updated;
  }

  Future<void> deleteDiagnosis(String caseId) async {
    if (canUseLiveServices) await diagnosisRepository.deleteDiagnosis(caseId);
    diagnoses = diagnoses
        .where((diagnosis) => diagnosis.id != caseId)
        .toList(growable: false);
    diagnosisReports = diagnosisReports
        .where((report) => report.diagnosisCaseId != caseId)
        .toList(growable: false);
    chats = chats
        .where((chat) => chat.diagnosisCaseId != caseId)
        .toList(growable: false);
    notifyListeners();
  }

  Future<void> saveDiagnosisFeedback({
    required String caseId,
    required bool isIncorrect,
    String? correctedCrop,
    String? correctedDisease,
    String? notes,
  }) => _guard(
    () => diagnosisRepository.saveFeedback(
      caseId: caseId,
      isIncorrect: isIncorrect,
      correctedCrop: correctedCrop,
      correctedDisease: correctedDisease,
      notes: notes,
    ),
  );

  Future<DiagnosisReportShare> createDiagnosisReport({
    required DiagnosisCaseModel diagnosis,
    required bool includeImage,
    required bool includeAlternatives,
    required bool includeFeedback,
    required bool includePlotName,
    required bool includePlotLocation,
    required DateTime expiresAt,
  }) => _guardValue(() async {
    final share = await diagnosisRepository.createReport(
      caseId: diagnosis.id,
      title: '${diagnosis.cropName} leaf check',
      imageIds: includeImage ? diagnosis.imageIds.take(10).toList() : const [],
      includeAlternatives: includeAlternatives,
      includeFeedback: includeFeedback,
      includePlotName: includePlotName,
      includePlotLocation: includePlotLocation,
      expiresAt: expiresAt,
    );
    await refreshDiagnosisReports();
    return share;
  });

  Future<void> refreshDiagnosisReports() async {
    if (!canUseLiveServices) return;
    final reports = <DiagnosisReportModel>[];
    for (final diagnosis in diagnoses) {
      reports.addAll(await diagnosisRepository.loadReports(diagnosis.id));
    }
    diagnosisReports = reports;
    notifyListeners();
  }

  Future<DiagnosisFeedbackModel?> loadDiagnosisFeedback(String caseId) {
    if (!canUseLiveServices) return Future.value(null);
    return diagnosisRepository.loadFeedback(caseId);
  }

  Future<void> revokeDiagnosisReport(String reportId) async {
    await _guard(() async {
      await diagnosisRepository.revokeReport(reportId);
      await refreshDiagnosisReports();
    });
  }

  Future<void> retryObjectDeletions() =>
      _guard(diagnosisRepository.retryObjectDeletions);

  DiagnosisCaseModel _withDiagnosisPlotName(DiagnosisCaseModel diagnosis) {
    if (diagnosis.plotName != null || diagnosis.plotId == null) {
      return diagnosis;
    }
    return DiagnosisCaseModel(
      id: diagnosis.id,
      cropName: diagnosis.cropName,
      plotName: plotById(diagnosis.plotId!)?.name,
      farmId: diagnosis.farmId,
      plotId: diagnosis.plotId,
      cropId: diagnosis.cropId,
      createdAt: diagnosis.createdAt,
      imageAsset: diagnosis.imageAsset,
      imagePath: diagnosis.imagePath,
      imageIds: diagnosis.imageIds,
      predictions: diagnosis.predictions,
      qualityFlags: diagnosis.qualityFlags,
      confidenceLabel: diagnosis.confidenceLabel,
      retakeRecommended: diagnosis.retakeRecommended,
      isSample: diagnosis.isSample,
    );
  }

  void _replaceDiagnosis(DiagnosisCaseModel diagnosis) {
    final index = diagnoses.indexWhere((item) => item.id == diagnosis.id);
    diagnoses = index < 0
        ? [diagnosis, ...diagnoses]
        : ([...diagnoses]..[index] = diagnosis);
    notifyListeners();
  }

  Future<ChatThreadModel> createChat({
    required String scope,
    String? contextId,
  }) async {
    return _guardValue(() async {
      final command = CreateChatCommand(
        scope: scope,
        farmId: scope == 'farm' ? contextId : null,
        plotId: scope == 'plot' ? contextId : null,
        diagnosisCaseId: scope == 'scan' ? contextId : null,
      );
      final label = _chatScopeLabel(scope, contextId);
      final chat = canUseLiveServices
          ? await chatRepository.createChat(command)
          : ChatThreadModel(
              id: _uuid.v4(),
              title: 'New ${scope == 'general' ? '' : '$scope '}conversation',
              scope: scope,
              scopeLabel: label,
              farmId: command.farmId,
              plotId: command.plotId,
              diagnosisCaseId: command.diagnosisCaseId,
              messages: const [],
            );
      final hydrated = chat.scopeLabel == null && label != null
          ? ChatThreadModel(
              id: chat.id,
              title: chat.title,
              scope: chat.scope,
              scopeLabel: label,
              farmId: chat.farmId,
              plotId: chat.plotId,
              diagnosisCaseId: chat.diagnosisCaseId,
              archived: chat.archived,
              messages: chat.messages,
            )
          : chat;
      chats = [hydrated, ...chats];
      notifyListeners();
      return hydrated;
    });
  }

  Future<void> loadChat(String chatId) async {
    if (!canUseLiveServices) return;
    final loaded = await _guardValue(() => chatRepository.loadChat(chatId));
    final index = chats.indexWhere((item) => item.id == chatId);
    final pending = index < 0
        ? const <ChatMessageModel>[]
        : chats[index].messages
              .where((message) => message.delivery != ChatDelivery.sent)
              .toList(growable: false);
    final hydrated = loaded.copyWith(
      messages: [...loaded.messages, ...pending],
    );
    chats = index < 0 ? [hydrated, ...chats] : ([...chats]..[index] = hydrated);
    notifyListeners();
    await _restoreChatOutbox(chatId);
    await _restoreActiveChatTurns(chatId);
  }

  Future<void> sendMessage(String threadId, String text) async {
    final normalized = text.trim();
    if (normalized.isEmpty) return;
    if (!canUseLiveServices) {
      sendPreviewMessage(threadId, normalized);
      return;
    }
    final index = chats.indexWhere((chat) => chat.id == threadId);
    if (index < 0) {
      throw const ApiException(
        code: 'CHAT_NOT_FOUND',
        message: 'The conversation could not be found',
        statusCode: 404,
      );
    }
    final localMessageId = _uuid.v4();
    final idempotencyKey = _uuid.v4();
    final optimistic = ChatMessageModel(
      id: localMessageId,
      author: ChatAuthor.farmer,
      text: normalized,
      sentAt: DateTime.now(),
      delivery: ChatDelivery.queued,
      idempotencyKey: idempotencyKey,
    );
    var envelope = PendingChatEnvelope(
      localId: localMessageId,
      chatId: threadId,
      content: normalized,
      idempotencyKey: idempotencyKey,
      createdAt: optimistic.sentAt,
    );
    await _persistChatEnvelope(envelope);
    _appendChatMessage(threadId, optimistic);
    try {
      final turn = await chatRepository.enqueueMessage(
        threadId,
        normalized,
        idempotencyKey: idempotencyKey,
      );
      _updateLocalChatMessage(
        threadId,
        localMessageId,
        (message) => message.copyWith(
          turnId: turn.id,
          delivery: _deliveryForTurn(turn.status),
        ),
      );
      envelope = envelope.copyWith(turnId: turn.id);
      await _persistChatEnvelope(envelope);
      _activeChatTurnIds.putIfAbsent(threadId, () => <String>{}).add(turn.id);
      _startChatTurnPolling(threadId);
      await _applyChatTurn(turn);
    } on ApiException {
      _updateLocalChatMessage(
        threadId,
        localMessageId,
        (message) =>
            message.copyWith(delivery: ChatDelivery.failed, failed: true),
      );
      rethrow;
    }
  }

  bool isChatResponding(String chatId) =>
      _activeChatTurnIds[chatId]?.isNotEmpty ?? false;

  int queuedChatTurns(String chatId) {
    final index = chats.indexWhere((chat) => chat.id == chatId);
    if (index < 0) return 0;
    return chats[index].messages
        .where((message) => message.delivery == ChatDelivery.queued)
        .length;
  }

  Future<void> retryChatMessage(String chatId, String messageId) async {
    final chatIndex = chats.indexWhere((chat) => chat.id == chatId);
    if (chatIndex < 0) return;
    final message = chats[chatIndex].messages
        .cast<ChatMessageModel?>()
        .firstWhere((item) => item?.id == messageId, orElse: () => null);
    if (message == null || message.delivery != ChatDelivery.failed) return;
    final idempotencyKey = message.idempotencyKey ?? _uuid.v4();
    _updateLocalChatMessage(
      chatId,
      messageId,
      (value) => value.copyWith(
        delivery: ChatDelivery.queued,
        failed: false,
        idempotencyKey: idempotencyKey,
      ),
    );
    try {
      final turn = message.turnId == null
          ? await chatRepository.enqueueMessage(
              chatId,
              message.text,
              idempotencyKey: idempotencyKey,
            )
          : await chatRepository.retryTurn(chatId, message.turnId!);
      await _persistChatEnvelope(
        PendingChatEnvelope(
          localId: message.id,
          chatId: chatId,
          content: message.text,
          idempotencyKey: idempotencyKey,
          createdAt: message.sentAt,
          turnId: turn.id,
        ),
      );
      _updateLocalChatMessage(
        chatId,
        messageId,
        (value) => value.copyWith(
          turnId: turn.id,
          delivery: _deliveryForTurn(turn.status),
        ),
      );
      _activeChatTurnIds.putIfAbsent(chatId, () => <String>{}).add(turn.id);
      _startChatTurnPolling(chatId);
      await _applyChatTurn(turn);
    } on ApiException {
      _updateLocalChatMessage(
        chatId,
        messageId,
        (value) => value.copyWith(delivery: ChatDelivery.failed, failed: true),
      );
      rethrow;
    }
  }

  Future<void> _restoreActiveChatTurns(String chatId) async {
    try {
      final turns = await chatRepository.recentTurns(chatId);
      for (final turn in turns) {
        final index = chats.indexWhere((chat) => chat.id == chatId);
        if (index < 0) break;
        final persisted = await _outboxEnvelope(
          chatId,
          idempotencyKey: turn.idempotencyKey,
        );
        final exists = chats[index].messages.any(
          (message) => message.turnId == turn.id,
        );
        if (!exists && turn.status != 'completed') {
          _appendChatMessage(
            chatId,
            ChatMessageModel(
              id: persisted?.localId ?? 'turn-${turn.id}',
              author: ChatAuthor.farmer,
              text: turn.content,
              sentAt: turn.createdAt,
              delivery: _deliveryForTurn(turn.status),
              turnId: turn.id,
              idempotencyKey: turn.idempotencyKey,
            ),
          );
        }
        if (persisted != null && persisted.turnId != turn.id) {
          await _persistChatEnvelope(persisted.copyWith(turnId: turn.id));
        }
        if (turn.status == 'queued' || turn.status == 'processing') {
          _activeChatTurnIds.putIfAbsent(chatId, () => <String>{}).add(turn.id);
        }
        await _applyChatTurn(turn);
      }
      if (_activeChatTurnIds[chatId]?.isNotEmpty ?? false) {
        _startChatTurnPolling(chatId);
      }
    } on ApiException catch (error) {
      lastError = error;
      notifyListeners();
    }
  }

  void _startChatTurnPolling(String chatId) {
    if (_chatTurnPollers.containsKey(chatId)) return;
    _chatTurnPollers[chatId] = Timer.periodic(
      const Duration(milliseconds: 900),
      (_) => unawaited(_refreshChatTurns(chatId)),
    );
    unawaited(_refreshChatTurns(chatId));
  }

  Future<void> _refreshChatTurns(String chatId) async {
    if (!_refreshingChatTurns.add(chatId)) return;
    try {
      final turnIds = List<String>.of(
        _activeChatTurnIds[chatId] ?? const <String>{},
      );
      for (final turnId in turnIds) {
        final turn = await chatRepository.getTurn(chatId, turnId);
        await _applyChatTurn(turn);
      }
    } on ApiException catch (error) {
      lastError = error;
      notifyListeners();
    } finally {
      _refreshingChatTurns.remove(chatId);
      if (_activeChatTurnIds[chatId]?.isEmpty ?? true) {
        _chatTurnPollers.remove(chatId)?.cancel();
      }
    }
  }

  Future<void> _applyChatTurn(ChatTurnModel turn) async {
    final chatIndex = chats.indexWhere((chat) => chat.id == turn.chatId);
    if (chatIndex < 0) return;
    final messageIndex = chats[chatIndex].messages.indexWhere(
      (message) => message.turnId == turn.id,
    );
    if (turn.status == 'completed' && turn.messages.isNotEmpty) {
      final messages = List<ChatMessageModel>.of(chats[chatIndex].messages);
      String? completedLocalId;
      if (messageIndex >= 0) {
        completedLocalId = messages[messageIndex].id;
        messages.replaceRange(messageIndex, messageIndex + 1, turn.messages);
      } else {
        final knownIds = messages.map((message) => message.id).toSet();
        messages.addAll(
          turn.messages.where((message) => !knownIds.contains(message.id)),
        );
      }
      chats = [...chats]
        ..[chatIndex] = chats[chatIndex].copyWith(messages: messages);
      final persisted = await _outboxEnvelope(
        turn.chatId,
        idempotencyKey: turn.idempotencyKey,
      );
      await _removeChatEnvelope(persisted?.localId ?? completedLocalId ?? '');
      _activeChatTurnIds[turn.chatId]?.remove(turn.id);
    } else if (turn.status == 'failed') {
      if (messageIndex >= 0) {
        _updateLocalChatMessage(
          turn.chatId,
          chats[chatIndex].messages[messageIndex].id,
          (message) =>
              message.copyWith(delivery: ChatDelivery.failed, failed: true),
        );
      }
      _activeChatTurnIds[turn.chatId]?.remove(turn.id);
    } else if (messageIndex >= 0) {
      _updateLocalChatMessage(
        turn.chatId,
        chats[chatIndex].messages[messageIndex].id,
        (message) => message.copyWith(delivery: _deliveryForTurn(turn.status)),
      );
    }
    notifyListeners();
  }

  Future<void> _restoreChatOutbox(String chatId) async {
    final values = await chatOutboxStore.readAll();
    final chatIndex = chats.indexWhere((chat) => chat.id == chatId);
    if (chatIndex < 0) return;
    for (final value in values.where((item) => item.chatId == chatId)) {
      final exists = chats[chatIndex].messages.any(
        (message) =>
            message.id == value.localId ||
            message.idempotencyKey == value.idempotencyKey,
      );
      if (!exists) {
        _appendChatMessage(
          chatId,
          ChatMessageModel(
            id: value.localId,
            author: ChatAuthor.farmer,
            text: value.content,
            sentAt: value.createdAt,
            delivery: ChatDelivery.queued,
            turnId: value.turnId,
            idempotencyKey: value.idempotencyKey,
          ),
        );
      }
    }
  }

  Future<PendingChatEnvelope?> _outboxEnvelope(
    String chatId, {
    required String idempotencyKey,
  }) async {
    final values = await chatOutboxStore.readAll();
    return values.cast<PendingChatEnvelope?>().firstWhere(
      (item) =>
          item?.chatId == chatId && item?.idempotencyKey == idempotencyKey,
      orElse: () => null,
    );
  }

  Future<void> _persistChatEnvelope(PendingChatEnvelope value) async {
    try {
      await chatOutboxStore.upsert(value);
    } catch (_) {
      throw const ApiException(
        code: 'CHAT_OUTBOX_UNAVAILABLE',
        message: 'The pending message could not be stored securely',
      );
    }
  }

  Future<void> _removeChatEnvelope(String localId) async {
    try {
      await chatOutboxStore.remove(localId);
    } catch (_) {
      throw const ApiException(
        code: 'CHAT_OUTBOX_UNAVAILABLE',
        message: 'The pending message state could not be updated securely',
      );
    }
  }

  ChatDelivery _deliveryForTurn(String status) => switch (status) {
    'processing' => ChatDelivery.sending,
    'failed' => ChatDelivery.failed,
    'completed' => ChatDelivery.sent,
    _ => ChatDelivery.queued,
  };

  void _appendChatMessage(String chatId, ChatMessageModel message) {
    final index = chats.indexWhere((chat) => chat.id == chatId);
    if (index < 0) return;
    chats = [...chats]
      ..[index] = chats[index].copyWith(
        messages: [...chats[index].messages, message],
      );
    notifyListeners();
  }

  void _updateLocalChatMessage(
    String chatId,
    String messageId,
    ChatMessageModel Function(ChatMessageModel) update,
  ) {
    final chatIndex = chats.indexWhere((chat) => chat.id == chatId);
    if (chatIndex < 0) return;
    final messages = List<ChatMessageModel>.of(chats[chatIndex].messages);
    final messageIndex = messages.indexWhere(
      (message) => message.id == messageId,
    );
    if (messageIndex < 0) return;
    messages[messageIndex] = update(messages[messageIndex]);
    chats = [...chats]
      ..[chatIndex] = chats[chatIndex].copyWith(messages: messages);
    notifyListeners();
  }

  Future<void> renameChat(String chatId, String title) async {
    await _updateChat(chatId, title: title);
  }

  Future<void> archiveChat(String chatId) async {
    await _updateChat(chatId, archived: true);
  }

  Future<void> deleteChat(String chatId) async {
    await _guard(() async {
      if (canUseLiveServices) await chatRepository.deleteChat(chatId);
      chats = chats.where((chat) => chat.id != chatId).toList();
      notifyListeners();
    });
  }

  Future<void> connectChatMemory({
    required String chatId,
    required String targetType,
    required String targetId,
  }) async {
    await _guard(() async {
      if (canUseLiveServices) {
        await chatRepository.connectMemory(
          chatId: chatId,
          targetType: targetType,
          targetId: targetId,
        );
      }
      final index = chats.indexWhere((chat) => chat.id == chatId);
      if (index < 0) return;
      final label = targetType == 'farm'
          ? farmById(targetId)?.name
          : plotById(targetId)?.name;
      chats = [...chats]
        ..[index] = chats[index].copyWith(scopeLabel: label ?? targetType);
      notifyListeners();
      await refreshMemories();
    });
  }

  Future<void> disconnectChatMemory(String chatId) async {
    await _guard(() async {
      if (canUseLiveServices) {
        await chatRepository.disconnectMemory(chatId);
      }
      final index = chats.indexWhere((chat) => chat.id == chatId);
      if (index < 0) return;
      chats = [...chats]
        ..[index] = chats[index].copyWith(clearScopeLabel: true);
      notifyListeners();
      await refreshMemories();
    });
  }

  void sendPreviewMessage(String threadId, String text) {
    final index = chats.indexWhere((chat) => chat.id == threadId);
    if (index < 0 || text.trim().isEmpty) return;
    final thread = chats[index];
    final messages = [
      ...thread.messages,
      ChatMessageModel(
        id: _uuid.v4(),
        author: ChatAuthor.farmer,
        text: text.trim(),
        sentAt: DateTime.now(),
        failed: !canUseLiveServices,
      ),
      if (!canUseLiveServices)
        ChatMessageModel(
          id: _uuid.v4(),
          author: ChatAuthor.system,
          text: 'Live Saathi is not connected in preview mode. This message was not sent.',
          sentAt: DateTime.now(),
          failed: true,
        ),
    ];
    chats = [...chats]..[index] = thread.copyWith(messages: messages);
    notifyListeners();
  }

  Future<void> _updateChat(
    String chatId, {
    String? title,
    bool? archived,
  }) async {
    await _guard(() async {
      final index = chats.indexWhere((chat) => chat.id == chatId);
      if (index < 0) {
        throw const ApiException(
          code: 'CHAT_NOT_FOUND',
          message: 'The conversation could not be found',
          statusCode: 404,
        );
      }
      final current = chats[index];
      final updated = canUseLiveServices
          ? await chatRepository.updateChat(
              current,
              title: title,
              archived: archived,
            )
          : current.copyWith(title: title, archived: archived);
      chats = [...chats]..[index] = updated;
      notifyListeners();
    });
  }

  String? _chatScopeLabel(String scope, String? contextId) {
    if (contextId == null) return null;
    return switch (scope) {
      'farm' => farmById(contextId)?.name,
      'plot' => plotById(contextId)?.name,
      'scan' =>
        diagnoses
            .cast<DiagnosisCaseModel?>()
            .firstWhere((item) => item?.id == contextId, orElse: () => null)
            ?.cropName,
      _ => null,
    };
  }

  Future<void> deleteMemory(String id) async {
    if (canUseLiveServices) await memoryRepository.delete(id);
    memories = memories.where((memory) => memory.id != id).toList();
    notifyListeners();
  }

  void setNotifications(bool value) {
    notificationsEnabled = value;
    unawaited(preferences.setBool(_notificationsKey, value));
    notifyListeners();
  }

  void setLocationEnabled(bool value) {
    locationEnabled = value;
    unawaited(preferences.setBool(_locationKey, value));
    if (!value) {
      weather = null;
    } else if (canUseLiveServices) {
      unawaited(_refreshWeatherSilently());
    }
    notifyListeners();
  }

  void setCameraEnabled(bool value) {
    cameraEnabled = value;
    unawaited(preferences.setBool(_cameraKey, value));
    notifyListeners();
  }

  String chatDraft(String chatId) =>
      preferences.getString('$_chatDraftPrefix$chatId') ?? '';

  Future<void> saveChatDraft(String chatId, String value) async {
    final key = '$_chatDraftPrefix$chatId';
    if (value.trim().isEmpty) {
      await preferences.remove(key);
    } else {
      await preferences.setString(key, value);
    }
  }

  Future<void> _refreshWeatherSilently() async {
    try {
      await refreshCurrentWeather();
    } on ApiException catch (error) {
      lastError = error;
      notifyListeners();
    }
  }

  Future<void> _guard(Future<void> Function() action) async {
    busy = true;
    lastError = null;
    notifyListeners();
    try {
      await action();
    } on ApiException catch (error) {
      lastError = error;
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<T> _guardValue<T>(Future<T> Function() action) async {
    busy = true;
    lastError = null;
    notifyListeners();
    try {
      return await action();
    } on ApiException catch (error) {
      lastError = error;
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    for (final timer in _chatTurnPollers.values) {
      timer.cancel();
    }
    _chatTurnPollers.clear();
    unawaited(_connectivitySubscription?.cancel());
    apiClient.dispose();
    super.dispose();
  }
}

String? _nullableText(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
