class WeatherSnapshot {
  const WeatherSnapshot({
    required this.temperature,
    required this.conditionCode,
    required this.rainChance,
    required this.humidity,
    required this.windKph,
    required this.fetchedAt,
    this.isStale = false,
    this.conditionLabel,
    this.rainLastHourMm,
  });

  final double temperature;
  final String conditionCode;
  final int rainChance;
  final int humidity;
  final double windKph;
  final DateTime fetchedAt;
  final bool isStale;
  final String? conditionLabel;
  final double? rainLastHourMm;
}

class ForecastDayModel {
  const ForecastDayModel({
    required this.date,
    required this.conditionCode,
    required this.minimumTemperature,
    required this.maximumTemperature,
    required this.precipitationMm,
    required this.rainChance,
    required this.maximumWindKph,
  });

  final DateTime date;
  final String conditionCode;
  final double minimumTemperature;
  final double maximumTemperature;
  final double precipitationMm;
  final int rainChance;
  final double maximumWindKph;
}

class PlotWeatherModel {
  const PlotWeatherModel({
    this.current,
    required this.forecast,
    required this.timezone,
    required this.fetchedAt,
    this.isStale = false,
  });

  final WeatherSnapshot? current;
  final List<ForecastDayModel> forecast;
  final String timezone;
  final DateTime fetchedAt;
  final bool isStale;
}

class ActivityCreationResult {
  const ActivityCreationResult({
    required this.activity,
    this.failedPhotoCount = 0,
  });

  final FarmActivity activity;
  final int failedPhotoCount;
}

class LocationPoint {
  const LocationPoint({
    required this.latitude,
    required this.longitude,
    this.label,
    this.country,
  });

  final double latitude;
  final double longitude;
  final String? label;
  final String? country;

  String get displayLabel =>
      label?.trim().isNotEmpty ?? false ? label!.trim() : 'Selected map point';

  LocationPoint copyWith({
    double? latitude,
    double? longitude,
    String? label,
    String? country,
  }) => LocationPoint(
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    label: label ?? this.label,
    country: country ?? this.country,
  );
}

class DeletionImpact {
  const DeletionImpact({required this.canDelete, required this.linkedRecords});

  final bool canDelete;
  final Map<String, int> linkedRecords;

  int get linkedRecordCount =>
      linkedRecords.values.fold(0, (total, value) => total + value);
}

class CropModel {
  const CropModel({
    required this.id,
    required this.name,
    this.variety,
    required this.stage,
    this.sownOn,
    this.isActive = true,
  });

  final String id;
  final String name;
  final String? variety;
  final String stage;
  final DateTime? sownOn;
  final bool isActive;
}

class FarmActivity {
  const FarmActivity({
    required this.id,
    required this.type,
    required this.title,
    required this.occurredAt,
    this.notes,
    this.cropId,
    this.photos = const [],
  });

  final String id;
  final String type;
  final String title;
  final DateTime occurredAt;
  final String? notes;
  final String? cropId;
  final List<ActivityPhotoModel> photos;

  FarmActivity copyWith({
    String? type,
    String? title,
    DateTime? occurredAt,
    String? notes,
    String? cropId,
    List<ActivityPhotoModel>? photos,
  }) => FarmActivity(
    id: id,
    type: type ?? this.type,
    title: title ?? this.title,
    occurredAt: occurredAt ?? this.occurredAt,
    notes: notes ?? this.notes,
    cropId: cropId ?? this.cropId,
    photos: photos ?? this.photos,
  );
}

class ActivityPhotoModel {
  const ActivityPhotoModel({
    required this.id,
    required this.activityId,
    required this.width,
    required this.height,
    required this.sizeBytes,
    required this.createdAt,
  });

  final String id;
  final String activityId;
  final int width;
  final int height;
  final int sizeBytes;
  final DateTime createdAt;
}

class TimelineEventModel {
  const TimelineEventModel({
    required this.id,
    required this.category,
    required this.eventCode,
    required this.occurredAt,
    required this.referenceId,
    required this.data,
  });

  final String id;
  final String category;
  final String eventCode;
  final DateTime occurredAt;
  final String referenceId;
  final Map<String, dynamic> data;

  String get title => switch (eventCode) {
    'diagnosis.case_created' =>
      data['title'] as String? ?? 'Leaf check created',
    'diagnosis.assessment_created' =>
      data['primary_disease'] as String? ?? 'Leaf result updated',
    'chat.session_created' =>
      data['title'] as String? ?? 'Conversation started',
    'activity.recorded' => data['title'] as String? ?? 'Field activity',
    'crop.stage_updated' => 'Crop stage: ${data['stage'] ?? 'updated'}',
    final value when value.startsWith('crop.cycle_') => 'Crop cycle updated',
    final value when value.startsWith('reminder.') =>
      'Reminder ${value.split('.').last.replaceAll('_', ' ')}',
    _ => eventCode.replaceAll('.', ' ').replaceAll('_', ' '),
  };
}

class TimelinePageModel {
  const TimelinePageModel({
    required this.items,
    required this.hasMore,
    required this.limit,
    required this.offset,
  });

  final List<TimelineEventModel> items;
  final bool hasMore;
  final int limit;
  final int offset;
}

class PlotModel {
  const PlotModel({
    required this.id,
    required this.farmId,
    required this.name,
    this.area,
    this.areaUnit,
    this.soilType,
    this.irrigation,
    this.locationLabel,
    required this.latitude,
    required this.longitude,
    required this.crops,
    required this.activities,
  });

  final String id;
  final String farmId;
  final String name;
  final double? area;
  final String? areaUnit;
  final String? soilType;
  final String? irrigation;
  final String? locationLabel;
  final double latitude;
  final double longitude;
  final List<CropModel> crops;
  final List<FarmActivity> activities;

  PlotModel copyWith({
    String? name,
    double? area,
    String? areaUnit,
    String? soilType,
    String? irrigation,
    bool clearArea = false,
    bool clearSoilType = false,
    bool clearIrrigation = false,
    double? latitude,
    double? longitude,
    String? locationLabel,
    List<CropModel>? crops,
    List<FarmActivity>? activities,
  }) => PlotModel(
    id: id,
    farmId: farmId,
    name: name ?? this.name,
    area: clearArea ? null : area ?? this.area,
    areaUnit: clearArea ? null : areaUnit ?? this.areaUnit,
    soilType: clearSoilType ? null : soilType ?? this.soilType,
    irrigation: clearIrrigation ? null : irrigation ?? this.irrigation,
    locationLabel: locationLabel ?? this.locationLabel,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    crops: crops ?? this.crops,
    activities: activities ?? this.activities,
  );
}

class FarmModel {
  const FarmModel({
    required this.id,
    required this.name,
    this.location,
    this.latitude,
    this.longitude,
    required this.plots,
    this.imageAsset = 'assets/images/hero_farm_bg.jpg',
  });

  final String id;
  final String name;
  final String? location;
  final double? latitude;
  final double? longitude;
  final List<PlotModel> plots;
  final String imageAsset;

  double get totalArea =>
      plots.fold(0, (total, plot) => total + (plot.area ?? 0));

  String? get displayLocation =>
      location ?? (plots.isEmpty ? null : plots.first.locationLabel);
  double? get mapLatitude =>
      latitude ?? (plots.isEmpty ? null : plots.first.latitude);
  double? get mapLongitude =>
      longitude ?? (plots.isEmpty ? null : plots.first.longitude);

  FarmModel copyWith({String? name, List<PlotModel>? plots}) => FarmModel(
    id: id,
    name: name ?? this.name,
    location: location,
    latitude: latitude,
    longitude: longitude,
    plots: plots ?? this.plots,
    imageAsset: imageAsset,
  );
}

enum ReminderStatus { pending, done, skipped, cancelled }

class FarmReminder {
  const FarmReminder({
    required this.id,
    required this.title,
    required this.dueAt,
    required this.plotName,
    this.status = ReminderStatus.pending,
    this.plotId,
    this.notes,
    this.recurrenceDays,
  });

  final String id;
  final String title;
  final DateTime dueAt;
  final String plotName;
  final ReminderStatus status;
  final String? plotId;
  final String? notes;
  final int? recurrenceDays;

  FarmReminder copyWith({ReminderStatus? status, DateTime? dueAt}) =>
      FarmReminder(
        id: id,
        title: title,
        dueAt: dueAt ?? this.dueAt,
        plotName: plotName,
        status: status ?? this.status,
        plotId: plotId,
        notes: notes,
        recurrenceDays: recurrenceDays,
      );
}

class ReminderProposalModel {
  const ReminderProposalModel({
    required this.id,
    required this.title,
    required this.dueAt,
    required this.status,
    this.chatId,
    this.plotId,
    this.recurrenceDays,
  });

  final String id;
  final String title;
  final DateTime dueAt;
  final String status;
  final String? chatId;
  final String? plotId;
  final int? recurrenceDays;
}

class DiagnosisPrediction {
  const DiagnosisPrediction({
    required this.code,
    required this.name,
    required this.confidenceLabel,
    required this.summary,
  });

  final String code;
  final String name;
  final String confidenceLabel;
  final String summary;
}

class DiagnosisAssessmentModel {
  const DiagnosisAssessmentModel({
    required this.id,
    required this.cropName,
    required this.diseaseName,
    required this.confidenceLabel,
    required this.createdAt,
    required this.isActive,
    this.imageIds = const [],
  });

  final String id;
  final String cropName;
  final String diseaseName;
  final String confidenceLabel;
  final DateTime createdAt;
  final bool isActive;
  final List<String> imageIds;
}

class DiagnosisFeedbackModel {
  const DiagnosisFeedbackModel({
    required this.isIncorrect,
    this.correctedCrop,
    this.correctedDisease,
    this.notes,
  });

  final bool isIncorrect;
  final String? correctedCrop;
  final String? correctedDisease;
  final String? notes;
}

class DiagnosisCaseModel {
  const DiagnosisCaseModel({
    required this.id,
    required this.cropName,
    required this.createdAt,
    required this.imageAsset,
    required this.predictions,
    required this.qualityFlags,
    required this.isSample,
    this.plotName,
    this.farmId,
    this.plotId,
    this.cropId,
    this.imagePath,
    this.imageIds = const [],
    this.confidenceLabel = 'low',
    this.retakeRecommended = false,
  });

  final String id;
  final String cropName;
  final String? plotName;
  final String? farmId;
  final String? plotId;
  final String? cropId;
  final DateTime createdAt;
  final String imageAsset;
  final String? imagePath;
  final List<String> imageIds;
  final List<DiagnosisPrediction> predictions;
  final List<String> qualityFlags;
  final bool isSample;
  final String confidenceLabel;
  final bool retakeRecommended;
}

class QueuedScanModel {
  const QueuedScanModel({
    required this.id,
    required this.imagePaths,
    required this.createdAt,
    this.cropName,
    this.plotId,
  });

  final String id;
  final List<String> imagePaths;
  final DateTime createdAt;
  final String? cropName;
  final String? plotId;
}

enum ChatAuthor { farmer, assistant, system }

enum ChatDelivery { sending, sent, failed }

class ChatAnswerSectionModel {
  const ChatAnswerSectionModel({required this.title, required this.body});

  final String title;
  final String body;
}

class ChatRetakeAdviceModel {
  const ChatRetakeAdviceModel({
    required this.reasonCodes,
    required this.instructions,
  });

  final List<String> reasonCodes;
  final List<String> instructions;
}

class ChatAssistantReplyModel {
  const ChatAssistantReplyModel({
    required this.shortAnswer,
    required this.disposition,
    required this.certainty,
    required this.answerSections,
    required this.explanationPoints,
    required this.nextSteps,
    required this.followUpQuestions,
    required this.generalPrecautions,
    required this.consultLocalExpert,
    this.details,
    this.retakeAdvice,
  });

  final String shortAnswer;
  final String disposition;
  final String certainty;
  final List<ChatAnswerSectionModel> answerSections;
  final List<String> explanationPoints;
  final List<String> nextSteps;
  final List<String> followUpQuestions;
  final List<String> generalPrecautions;
  final bool consultLocalExpert;
  final String? details;
  final ChatRetakeAdviceModel? retakeAdvice;
}

class ChatMessageModel {
  const ChatMessageModel({
    required this.id,
    required this.author,
    required this.text,
    required this.sentAt,
    this.failed = false,
    this.delivery = ChatDelivery.sent,
    this.idempotencyKey,
    this.structuredReply,
    this.sequence,
  });

  final String id;
  final ChatAuthor author;
  final String text;
  final DateTime sentAt;
  final bool failed;
  final ChatDelivery delivery;
  final String? idempotencyKey;
  final ChatAssistantReplyModel? structuredReply;
  final int? sequence;

  ChatMessageModel copyWith({
    String? text,
    ChatDelivery? delivery,
    bool? failed,
    String? idempotencyKey,
    int? sequence,
  }) => ChatMessageModel(
    id: id,
    author: author,
    text: text ?? this.text,
    sentAt: sentAt,
    failed: failed ?? this.failed,
    delivery: delivery ?? this.delivery,
    idempotencyKey: idempotencyKey ?? this.idempotencyKey,
    structuredReply: structuredReply,
    sequence: sequence ?? this.sequence,
  );
}

class ChatMessagePageModel {
  const ChatMessagePageModel({
    required this.items,
    required this.nextBeforeSequence,
  });

  final List<ChatMessageModel> items;
  final int? nextBeforeSequence;
}

class ChatThreadModel {
  const ChatThreadModel({
    required this.id,
    required this.title,
    required this.scope,
    required this.messages,
    this.scopeLabel,
    this.farmId,
    this.plotId,
    this.diagnosisCaseId,
    this.effectiveFarmId,
    this.effectivePlotId,
    this.archived = false,
  });

  final String id;
  final String title;
  final String scope;
  final String? scopeLabel;
  final String? farmId;
  final String? plotId;
  final String? diagnosisCaseId;
  final String? effectiveFarmId;
  final String? effectivePlotId;
  final bool archived;
  final List<ChatMessageModel> messages;

  String get contextScope {
    if (scope == 'scan') return 'scan';
    if (effectivePlotId != null) return 'plot';
    if (effectiveFarmId != null) return 'farm';
    return scope;
  }

  ChatThreadModel copyWith({
    String? title,
    List<ChatMessageModel>? messages,
    bool? archived,
    String? scopeLabel,
    bool clearScopeLabel = false,
    String? effectiveFarmId,
    String? effectivePlotId,
    bool replaceEffectiveScope = false,
  }) => ChatThreadModel(
    id: id,
    title: title ?? this.title,
    scope: scope,
    scopeLabel: clearScopeLabel ? null : scopeLabel ?? this.scopeLabel,
    farmId: farmId,
    plotId: plotId,
    diagnosisCaseId: diagnosisCaseId,
    effectiveFarmId: replaceEffectiveScope
        ? effectiveFarmId
        : effectiveFarmId ?? this.effectiveFarmId,
    effectivePlotId: replaceEffectiveScope
        ? effectivePlotId
        : effectivePlotId ?? this.effectivePlotId,
    archived: archived ?? this.archived,
    messages: messages ?? this.messages,
  );
}

class MemoryFactModel {
  const MemoryFactModel({
    required this.id,
    required this.text,
    required this.scope,
    required this.status,
  });

  final String id;
  final String text;
  final String scope;
  final String status;
}

class DiagnosisReportModel {
  const DiagnosisReportModel({
    required this.id,
    required this.diagnosisCaseId,
    required this.title,
    required this.status,
    required this.expiresAt,
    required this.createdAt,
    this.revokedAt,
  });

  final String id;
  final String diagnosisCaseId;
  final String title;
  final String status;
  final DateTime expiresAt;
  final DateTime createdAt;
  final DateTime? revokedAt;

  bool get isActive =>
      revokedAt == null &&
      status != 'revoked' &&
      expiresAt.isAfter(DateTime.now());
}

class DemoData {
  static final farms = <FarmModel>[
    FarmModel(
      id: 'farm-1',
      name: 'Anand Fields',
      location: 'Hesaraghatta, Karnataka',
      latitude: 13.1377,
      longitude: 77.4786,
      plots: [
        PlotModel(
          id: 'plot-1',
          farmId: 'farm-1',
          name: 'North Plot',
          area: 2.4,
          areaUnit: 'acre',
          soilType: 'Red loam',
          irrigation: 'Drip',
          latitude: 13.1381,
          longitude: 77.4791,
          crops: [
            CropModel(
              id: 'crop-1',
              name: 'Tomato',
              variety: 'Arka Rakshak',
              stage: 'Flowering',
              sownOn: DateTime.now().subtract(const Duration(days: 52)),
            ),
          ],
          activities: [
            FarmActivity(
              id: 'activity-1',
              type: 'irrigation',
              title: 'Drip irrigation',
              occurredAt: DateTime.now().subtract(const Duration(hours: 20)),
              notes: '45 minute cycle',
            ),
            FarmActivity(
              id: 'activity-2',
              type: 'nutrition',
              title: 'Compost application',
              occurredAt: DateTime.now().subtract(const Duration(days: 4)),
            ),
          ],
        ),
        PlotModel(
          id: 'plot-2',
          farmId: 'farm-1',
          name: 'Lower Terrace',
          area: 1.8,
          areaUnit: 'acre',
          soilType: 'Clay loam',
          irrigation: 'Rain-fed',
          latitude: 13.1369,
          longitude: 77.4780,
          crops: [
            CropModel(
              id: 'crop-2',
              name: 'Finger millet',
              variety: 'GPU 28',
              stage: 'Tillering',
              sownOn: DateTime.now().subtract(const Duration(days: 35)),
            ),
          ],
          activities: const [],
        ),
      ],
    ),
  ];

  static final reminders = <FarmReminder>[
    FarmReminder(
      id: 'reminder-1',
      title: 'Inspect lower leaves',
      dueAt: DateTime.now().add(const Duration(hours: 2)),
      plotName: 'North Plot',
    ),
    FarmReminder(
      id: 'reminder-2',
      title: 'Check drip filter',
      dueAt: DateTime.now().add(const Duration(hours: 6)),
      plotName: 'North Plot',
    ),
  ];

  static final diagnoses = <DiagnosisCaseModel>[
    DiagnosisCaseModel(
      id: 'sample-diagnosis-1',
      cropName: 'Tomato',
      plotName: 'North Plot',
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
      imageAsset: 'assets/images/disease_blight.jpg',
      predictions: const [
        DiagnosisPrediction(
          code: 'tomato_early_blight',
          name: 'Early blight',
          confidenceLabel: 'medium',
          summary: 'The visible spotting pattern can match early blight, but a closer image is needed.',
        ),
        DiagnosisPrediction(
          code: 'leaf_spot_other',
          name: 'Other leaf spot',
          confidenceLabel: 'low',
          summary: 'Other fungal or bacterial leaf spots remain possible.',
        ),
      ],
      qualityFlags: const ['retake_recommended'],
      isSample: true,
    ),
  ];

  static final chats = <ChatThreadModel>[
    ChatThreadModel(
      id: 'chat-1',
      title: 'Tomato flowering care',
      scope: 'plot',
      scopeLabel: 'North Plot',
      messages: [
        ChatMessageModel(
          id: 'message-1',
          author: ChatAuthor.farmer,
          text: 'What should I watch for during tomato flowering?',
          sentAt: DateTime.now().subtract(const Duration(hours: 5)),
        ),
        ChatMessageModel(
          id: 'message-2',
          author: ChatAuthor.assistant,
          text: 'Keep moisture steady, avoid heavy nitrogen, and inspect flowers and lower leaves twice a week. Your North Plot uses drip irrigation, so check that emitters are flowing evenly.',
          sentAt: DateTime.now().subtract(const Duration(hours: 5)),
        ),
      ],
    ),
  ];

  static const memories = <MemoryFactModel>[
    MemoryFactModel(
      id: 'memory-1',
      text: 'North Plot uses drip irrigation.',
      scope: 'North Plot',
      status: 'indexed',
    ),
    MemoryFactModel(
      id: 'memory-2',
      text: 'Prefers area measurements in acres.',
      scope: 'Profile',
      status: 'indexed',
    ),
  ];
}
