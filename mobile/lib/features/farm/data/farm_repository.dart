import '../../../core/models/app_models.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/krishi_api.dart';

class CreatePlotCommand {
  const CreatePlotCommand({
    required this.farmId,
    required this.name,
    required this.location,
    required this.cropName,
    required this.cropStage,
    this.cropVariety,
    this.sowingOrTransplantDate,
    this.area,
    this.areaUnit,
    this.soilNotes,
    this.irrigationDetails,
  });

  final String farmId;
  final String name;
  final LocationPoint location;
  final String cropName;
  final String cropStage;
  final String? cropVariety;
  final DateTime? sowingOrTransplantDate;
  final double? area;
  final String? areaUnit;
  final String? soilNotes;
  final String? irrigationDetails;
}

class FarmRepository {
  const FarmRepository(this._api);

  final KrishiApi _api;

  Future<List<FarmModel>> loadFarms() async {
    final responses = await Future.wait([_api.listFarms(), _api.listPlots()]);
    final farmRows = _list(responses[0], contract: 'farms');
    final plotRows = _list(responses[1], contract: 'plots');
    final plots = plotRows.map(_plot).toList(growable: false);

    return farmRows
        .map((row) {
          final id = _requiredString(row, 'id');
          final ownedPlots = plots
              .where((plot) => plot.farmId == id)
              .toList(growable: false);
          final latitude = ownedPlots.isEmpty
              ? null
              : ownedPlots.fold<double>(0, (sum, plot) => sum + plot.latitude) /
                    ownedPlots.length;
          final longitude = ownedPlots.isEmpty
              ? null
              : ownedPlots.fold<double>(
                      0,
                      (sum, plot) => sum + plot.longitude,
                    ) /
                    ownedPlots.length;
          final locationLabels = ownedPlots
              .map((plot) => plot.locationLabel?.trim())
              .whereType<String>()
              .where((label) => label.isNotEmpty)
              .toSet();
          return FarmModel(
            id: id,
            name: _requiredString(row, 'name'),
            location: locationLabels.length == 1
                ? locationLabels.single
                : ownedPlots.isEmpty
                ? null
                : '${ownedPlots.length} plot locations',
            latitude: latitude,
            longitude: longitude,
            plots: ownedPlots,
          );
        })
        .toList(growable: false);
  }

  Future<FarmModel> createFarm(String name) async {
    final payload = await _api.createFarm({'name': name.trim()});
    final row = _map(payload, contract: 'farm');
    return FarmModel(
      id: _requiredString(row, 'id'),
      name: _requiredString(row, 'name'),
      plots: const [],
    );
  }

  Future<FarmModel> updateFarm(FarmModel current, String name) async {
    final payload = await _api.updateFarm(current.id, {'name': name.trim()});
    final row = _map(payload, contract: 'farm');
    return current.copyWith(name: _requiredString(row, 'name'));
  }

  Future<DeletionImpact> farmDeletionImpact(String id) async {
    final payload = await _api.farmDeletionImpact(id);
    final row = _map(payload, contract: 'deletion impact');
    final rawLinked = row['linked_records'];
    final linked = <String, int>{};
    if (rawLinked is Map<String, dynamic>) {
      for (final entry in rawLinked.entries) {
        final value = entry.value;
        if (value is int) linked[entry.key] = value;
      }
    }
    return DeletionImpact(
      canDelete: row['can_delete'] as bool? ?? false,
      linkedRecords: linked,
    );
  }

  Future<void> deleteFarm(String id) => _api.deleteFarm(id);

  Future<PlotModel> createPlot(CreatePlotCommand command) async {
    final crop = <String, Object?>{
      'name': command.cropName.trim(),
      'stage': command.cropStage.trim(),
      if (_present(command.cropVariety)) 'variety': command.cropVariety!.trim(),
      if (command.sowingOrTransplantDate != null)
        'sowing_or_transplant_date': _date(command.sowingOrTransplantDate!),
    };
    final body = <String, Object?>{
      'farm_id': command.farmId,
      'name': command.name.trim(),
      'latitude': double.parse(command.location.latitude.toStringAsFixed(6)),
      'longitude': double.parse(command.location.longitude.toStringAsFixed(6)),
      'location_label': command.location.displayLabel,
      if (command.area != null) 'area_value': command.area,
      if (command.areaUnit != null) 'area_unit': command.areaUnit,
      if (_present(command.soilNotes)) 'soil_notes': command.soilNotes!.trim(),
      if (_present(command.irrigationDetails))
        'irrigation_details': command.irrigationDetails!.trim(),
      'crops': [crop],
    };
    final payload = await _api.createPlot(body);
    return _plot(_map(payload, contract: 'plot'));
  }

  Future<PlotModel> updatePlot({
    required PlotModel current,
    required String name,
    required LocationPoint location,
    double? area,
    String? areaUnit,
    String? soilNotes,
    String? irrigationDetails,
  }) async {
    final payload = await _api.updatePlot(current.id, {
      'name': name.trim(),
      'latitude': double.parse(location.latitude.toStringAsFixed(6)),
      'longitude': double.parse(location.longitude.toStringAsFixed(6)),
      'location_label': location.displayLabel,
      'area_value': area,
      'area_unit': areaUnit,
      'soil_notes': _nullableText(soilNotes),
      'irrigation_details': _nullableText(irrigationDetails),
    });
    final updated = _plot(_map(payload, contract: 'plot'));
    return updated.copyWith(activities: current.activities);
  }

  Future<ActivityCreationResult> createActivity({
    required String plotId,
    required String title,
    required String notes,
    required DateTime occurredAt,
    String? cropId,
    List<String> imagePaths = const [],
  }) async {
    final payload = await _api.createActivity(plotId, {
      'title': title.trim(),
      'notes': notes.trim().isEmpty ? null : notes.trim(),
      'occurred_at': occurredAt.toUtc().toIso8601String(),
      'crop_id': ?cropId,
    });
    final row = _map(payload, contract: 'activity');
    var activity = _activity(row);
    final photos = <ActivityPhotoModel>[];
    var failedPhotoCount = 0;
    for (final imagePath in imagePaths) {
      try {
        final uploaded = await _api.addActivityPhoto(activity.id, imagePath);
        photos.add(_activityPhoto(_map(uploaded, contract: 'activity photo')));
      } on ApiException {
        failedPhotoCount += 1;
      }
    }
    activity = activity.copyWith(photos: photos);
    return ActivityCreationResult(
      activity: activity,
      failedPhotoCount: failedPhotoCount,
    );
  }

  Future<List<FarmActivity>> loadActivities(String plotId) async {
    final payload = await _api.listActivities(plotId);
    return _list(
      payload,
      contract: 'activities',
    ).map(_activity).toList(growable: false);
  }

  Future<FarmActivity> loadActivity(String activityId) async {
    final responses = await Future.wait([
      _api.getActivity(activityId),
      _api.listActivityPhotos(activityId),
    ]);
    final activity = _activity(_map(responses[0], contract: 'activity'));
    final photos = _list(
      responses[1],
      contract: 'activity photos',
    ).map(_activityPhoto).toList(growable: false);
    return activity.copyWith(photos: photos);
  }

  Future<FarmActivity> updateActivity({
    required FarmActivity current,
    required String title,
    required String notes,
    required DateTime occurredAt,
  }) async {
    final payload = await _api.updateActivity(current.id, {
      'title': title.trim(),
      'notes': notes.trim().isEmpty ? null : notes.trim(),
      'occurred_at': occurredAt.toUtc().toIso8601String(),
    });
    return _activity(_map(payload, contract: 'activity'))
        .copyWith(photos: current.photos);
  }

  Future<ActivityPhotoModel> addActivityPhoto(
    String activityId,
    String imagePath,
  ) async {
    final payload = await _api.addActivityPhoto(activityId, imagePath);
    return _activityPhoto(_map(payload, contract: 'activity photo'));
  }

  Future<List<int>> loadActivityPhoto(String activityId, String photoId) =>
      _api.getActivityPhoto(activityId, photoId);

  Future<void> deleteActivityPhoto(String activityId, String photoId) =>
      _api.deleteActivityPhoto(activityId, photoId);

  Future<void> deleteActivity(String activityId) =>
      _api.deleteActivity(activityId);

  Future<CropModel> createCrop({
    required String plotId,
    required String name,
    required String stage,
    String? variety,
    DateTime? sowingOrTransplantDate,
  }) async {
    final payload = await _api.createCrop(plotId, {
      'name': name.trim(),
      'stage': stage.trim(),
      if (_present(variety)) 'variety': variety!.trim(),
      if (sowingOrTransplantDate != null)
        'sowing_or_transplant_date': _date(sowingOrTransplantDate),
    });
    return _crop(_map(payload, contract: 'crop'));
  }

  Future<CropModel> updateCrop({
    required CropModel current,
    required String name,
    String? variety,
    DateTime? sowingOrTransplantDate,
  }) async {
    final payload = await _api.updateCrop(current.id, {
      'name': name.trim(),
      'variety': _present(variety) ? variety!.trim() : null,
      'sowing_or_transplant_date': sowingOrTransplantDate == null
          ? null
          : _date(sowingOrTransplantDate),
    });
    return _crop(_map(payload, contract: 'crop'));
  }

  Future<CropModel> updateCropStage(CropModel current, String stage) async {
    final payload = await _api.updateCropStage(current.id, {
      'stage': stage.trim(),
    });
    return _crop(_map(payload, contract: 'crop'));
  }

  Future<CropModel> closeCropCycle(CropModel current, DateTime endedOn) async {
    final payload = await _api.closeCropCycle(current.id, {
      'ended_on': _date(endedOn),
    });
    return _crop(_map(payload, contract: 'crop'));
  }

  Future<DeletionImpact> cropDeletionImpact(String cropId) async {
    final payload = await _api.cropDeletionImpact(cropId);
    final row = _map(payload, contract: 'crop deletion impact');
    final linked = <String, int>{};
    if (row['linked_records'] case final Map<String, dynamic> values) {
      for (final entry in values.entries) {
        if (entry.value case final int count) linked[entry.key] = count;
      }
    }
    return DeletionImpact(
      canDelete: row['can_delete'] as bool? ?? false,
      linkedRecords: linked,
    );
  }

  Future<void> deleteCrop(String cropId, {required bool confirmHistoryLoss}) =>
      _api.deleteCrop(cropId, confirmHistoryLoss: confirmHistoryLoss);

  PlotModel _plot(Map<String, dynamic> row) {
    final cropRows = switch (row['crops']) {
      final List<dynamic> values => values.whereType<Map<String, dynamic>>(),
      _ => const Iterable<Map<String, dynamic>>.empty(),
    };
    return PlotModel(
      id: _requiredString(row, 'id'),
      farmId: row['farm_id'] as String? ?? '',
      name: _requiredString(row, 'name'),
      area: _number(row['area_value']),
      areaUnit: row['area_unit'] as String?,
      soilType: row['soil_notes'] as String?,
      irrigation: row['irrigation_details'] as String?,
      latitude: _requiredNumber(row, 'latitude'),
      longitude: _requiredNumber(row, 'longitude'),
      locationLabel: row['location_label'] as String?,
      crops: cropRows.map(_crop).toList(growable: false),
      activities: const [],
    );
  }

  CropModel _crop(Map<String, dynamic> row) {
    final endedOn = _optionalDateTime(row['cycle_ended_on']);
    return CropModel(
      id: _requiredString(row, 'id'),
      name: _requiredString(row, 'name'),
      stage: _requiredString(row, 'stage'),
      variety: row['variety'] as String?,
      sownOn: _optionalDateTime(row['sowing_or_transplant_date']),
      isActive: endedOn == null,
    );
  }

  FarmActivity _activity(Map<String, dynamic> row) => FarmActivity(
    id: _requiredString(row, 'id'),
    type: _requiredString(row, 'title').toLowerCase(),
    title: _requiredString(row, 'title'),
    occurredAt: _requiredDateTime(row, 'occurred_at'),
    notes: row['notes'] as String?,
    cropId: row['crop_id'] as String?,
  );

  ActivityPhotoModel _activityPhoto(Map<String, dynamic> row) =>
      ActivityPhotoModel(
        id: _requiredString(row, 'id'),
        activityId: _requiredString(row, 'activity_id'),
        width: (row['width'] as num?)?.toInt() ?? 0,
        height: (row['height'] as num?)?.toInt() ?? 0,
        sizeBytes: (row['size_bytes'] as num?)?.toInt() ?? 0,
        createdAt: _requiredDateTime(row, 'created_at'),
      );
}

Map<String, dynamic> _map(Object? value, {required String contract}) {
  if (value is Map<String, dynamic>) return value;
  throw ApiException(
    code: 'INVALID_RESPONSE',
    message: 'The $contract response could not be read',
  );
}

List<Map<String, dynamic>> _list(Object? value, {required String contract}) {
  if (value is List<dynamic>) {
    return value.whereType<Map<String, dynamic>>().toList(growable: false);
  }
  throw ApiException(
    code: 'INVALID_RESPONSE',
    message: 'The $contract response could not be read',
  );
}

String _requiredString(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is String && value.trim().isNotEmpty) return value;
  throw ApiException(
    code: 'INVALID_RESPONSE',
    message: 'The response is missing $key',
  );
}

double _requiredNumber(Map<String, dynamic> row, String key) {
  final value = _number(row[key]);
  if (value != null) return value;
  throw ApiException(
    code: 'INVALID_RESPONSE',
    message: 'The response is missing $key',
  );
}

double? _number(Object? value) => switch (value) {
  final num number => number.toDouble(),
  final String text => double.tryParse(text),
  _ => null,
};

DateTime _requiredDateTime(Map<String, dynamic> row, String key) {
  final parsed = _optionalDateTime(row[key]);
  if (parsed != null) return parsed;
  throw ApiException(
    code: 'INVALID_RESPONSE',
    message: 'The response is missing $key',
  );
}

DateTime? _optionalDateTime(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

bool _present(String? value) => value?.trim().isNotEmpty ?? false;

String? _nullableText(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
