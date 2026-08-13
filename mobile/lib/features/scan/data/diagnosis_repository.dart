import '../../../core/models/app_models.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/krishi_api.dart';

class DiagnosisReportShare {
  const DiagnosisReportShare({
    required this.id,
    required this.token,
    required this.expiresAt,
  });

  final String id;
  final String token;
  final DateTime expiresAt;
}

class ProgressionComparisonModel {
  const ProgressionComparisonModel({
    required this.trend,
    required this.confidence,
    required this.evidence,
    required this.limitations,
    required this.recommendations,
    required this.earlierImageIds,
    required this.laterImageIds,
    required this.earlierCapturedAt,
    required this.laterCapturedAt,
  });

  final String trend;
  final double confidence;
  final List<String> evidence;
  final List<String> limitations;
  final List<String> recommendations;
  final List<String> earlierImageIds;
  final List<String> laterImageIds;
  final DateTime earlierCapturedAt;
  final DateTime laterCapturedAt;
}

class DiagnosisRepository {
  const DiagnosisRepository(this._api);

  final KrishiApi _api;

  Future<List<DiagnosisCaseModel>> loadDiagnoses({
    int limit = 20,
    int offset = 0,
  }) async {
    final payload = await _api.listDiagnoses(
      filters: {'limit': '$limit', 'offset': '$offset'},
    );
    final rows = _list(payload, contract: 'diagnosis list');
    return rows
        .map((row) => _diagnosis(_map(row, contract: 'diagnosis')))
        .toList(growable: false);
  }

  Future<DiagnosisCaseModel> loadDiagnosis(String caseId) async {
    final payload = await _api.getDiagnosis(caseId);
    return _diagnosis(_map(payload, contract: 'diagnosis'));
  }

  Future<DiagnosisCaseModel> createDiagnosis({
    required List<String> imagePaths,
    String? plantName,
    String? farmId,
    String? plotId,
    String? cropId,
    String? plotName,
  }) async {
    final fields = <String, String>{
      'plant_name': ?_text(plantName),
      'farm_id': ?farmId,
      'plot_id': ?plotId,
      'crop_id': ?cropId,
    };
    final payload = await _api.createDiagnosis(
      imagePaths: imagePaths,
      fields: fields,
    );
    return _diagnosis(
      _map(payload, contract: 'diagnosis'),
      imagePath: imagePaths.firstOrNull,
      plotName: plotName,
    );
  }

  Future<DiagnosisCaseModel> addRetake({
    required String caseId,
    required List<String> imagePaths,
    String? plotName,
  }) async {
    final payload = await _api.createRetake(caseId, imagePaths: imagePaths);
    return _diagnosis(
      _map(payload, contract: 'diagnosis retake'),
      imagePath: imagePaths.firstOrNull,
      plotName: plotName,
    );
  }

  Future<List<int>> loadImage(String caseId, String imageId) =>
      _api.diagnosisImage(caseId, imageId);

  Future<List<DiagnosisAssessmentModel>> loadAssessmentHistory(
    String caseId,
  ) async {
    final payload = await _api.diagnosisAssessments(caseId);
    return _list(payload, contract: 'diagnosis history')
        .map((value) => _assessment(_map(value, contract: 'assessment')))
        .toList(growable: false);
  }

  Future<ProgressionComparisonModel> compareProgression({
    required String caseId,
    required String responseLanguage,
  }) async {
    final payload = await _api.compareDiagnosisProgression(
      caseId,
      responseLanguage: responseLanguage,
    );
    final row = _map(payload, contract: 'progression comparison');
    final earlierCapturedAt = DateTime.tryParse(
      row['earlier_captured_at'] as String? ?? '',
    );
    final laterCapturedAt = DateTime.tryParse(
      row['later_captured_at'] as String? ?? '',
    );
    final confidence = row['confidence'];
    if (earlierCapturedAt == null ||
        laterCapturedAt == null ||
        confidence is! num) {
      throw const ApiException(
        code: 'INVALID_RESPONSE',
        message: 'The progression comparison response is incomplete',
      );
    }
    return ProgressionComparisonModel(
      trend: row['trend'] as String? ?? 'unclear',
      confidence: confidence.toDouble(),
      evidence: _strings(row['evidence']).toList(growable: false),
      limitations: _strings(row['limitations']).toList(growable: false),
      recommendations: _strings(row['recommendations']).toList(growable: false),
      earlierImageIds: _strings(row['earlier_image_ids'])
          .toList(growable: false),
      laterImageIds: _strings(row['later_image_ids']).toList(growable: false),
      earlierCapturedAt: earlierCapturedAt,
      laterCapturedAt: laterCapturedAt,
    );
  }

  Future<DiagnosisCaseModel> linkDiagnosis({
    required String caseId,
    String? farmId,
    String? plotId,
    String? cropId,
    String? plotName,
  }) async {
    final payload = await _api.linkDiagnosis(caseId, {
      'farm_id': farmId,
      'plot_id': plotId,
      'crop_id': cropId,
    });
    return _diagnosis(
      _map(payload, contract: 'diagnosis link'),
      plotName: plotName,
    );
  }

  Future<void> deleteDiagnosis(String caseId) => _api.deleteDiagnosis(caseId);

  Future<void> saveFeedback({
    required String caseId,
    required bool isIncorrect,
    String? correctedCrop,
    String? correctedDisease,
    String? notes,
  }) async {
    await _api.upsertDiagnosisFeedback(caseId, {
      'is_incorrect': isIncorrect,
      'corrected_crop': _text(correctedCrop),
      'corrected_disease': _text(correctedDisease),
      'notes': _text(notes),
    });
  }

  Future<DiagnosisFeedbackModel?> loadFeedback(String caseId) async {
    final payload = await _api.getDiagnosisFeedback(caseId);
    if (payload == null) return null;
    final row = _map(payload, contract: 'diagnosis feedback');
    return DiagnosisFeedbackModel(
      isIncorrect: row['is_incorrect'] as bool? ?? false,
      correctedCrop: row['corrected_crop'] as String?,
      correctedDisease: row['corrected_disease'] as String?,
      notes: row['notes'] as String?,
    );
  }

  Future<DiagnosisReportShare> createReport({
    required String caseId,
    required String title,
    required List<String> imageIds,
    required bool includeAlternatives,
    required bool includeFeedback,
    required bool includePlotName,
    required bool includePlotLocation,
    required DateTime expiresAt,
  }) async {
    final payload = await _api.createDiagnosisReport(caseId, {
      'title': title.trim(),
      'include_alternatives': includeAlternatives,
      'include_feedback': includeFeedback,
      'include_plot_name': includePlotName,
      'include_plot_location': includePlotLocation,
      'image_ids': imageIds,
      'expires_at': expiresAt.toUtc().toIso8601String(),
    });
    final row = _map(payload, contract: 'diagnosis report');
    final id = row['id'] as String?;
    final token = row['share_token'] as String?;
    final expiry = DateTime.tryParse(row['expires_at'] as String? ?? '');
    if (id == null || token == null || expiry == null) {
      throw const ApiException(
        code: 'INVALID_RESPONSE',
        message: 'The report link response is incomplete',
      );
    }
    return DiagnosisReportShare(id: id, token: token, expiresAt: expiry);
  }

  Future<List<DiagnosisReportModel>> loadReports(String caseId) async {
    final payload = await _api.listDiagnosisReports(caseId);
    return _list(payload, contract: 'diagnosis reports')
        .map((value) => _report(_map(value, contract: 'diagnosis report')))
        .toList(growable: false);
  }

  Future<void> revokeReport(String reportId) =>
      _api.revokeDiagnosisReport(reportId).then((_) {});

  Future<void> retryObjectDeletions() =>
      _api.retryObjectDeletions().then((_) {});
}

DiagnosisReportModel _report(Map<String, dynamic> row) {
  final id = row['id'] as String?;
  final caseId = row['diagnosis_case_id'] as String?;
  final expiresAt = DateTime.tryParse(row['expires_at'] as String? ?? '');
  final createdAt = DateTime.tryParse(row['created_at'] as String? ?? '');
  if (id == null || caseId == null || expiresAt == null || createdAt == null) {
    throw const ApiException(
      code: 'INVALID_RESPONSE',
      message: 'A diagnosis report response is incomplete',
    );
  }
  return DiagnosisReportModel(
    id: id,
    diagnosisCaseId: caseId,
    title: row['title'] as String? ?? 'Leaf report',
    status: row['status'] as String? ?? 'active',
    expiresAt: expiresAt,
    createdAt: createdAt,
    revokedAt: DateTime.tryParse(row['revoked_at'] as String? ?? ''),
  );
}

DiagnosisAssessmentModel _assessment(Map<String, dynamic> row) {
  final id = row['id'] as String?;
  final createdAt = DateTime.tryParse(row['created_at'] as String? ?? '');
  if (id == null || createdAt == null) {
    throw const ApiException(
      code: 'INVALID_RESPONSE',
      message: 'A diagnosis history entry is incomplete',
    );
  }
  return DiagnosisAssessmentModel(
    id: id,
    cropName: row['predicted_crop'] as String? ?? 'Unknown crop',
    diseaseName: row['primary_disease'] as String? ?? 'No clear match',
    confidenceLabel: row['confidence_label'] as String? ?? 'low',
    createdAt: createdAt,
    isActive: row['is_active'] as bool? ?? false,
    imageIds: _strings(row['image_ids']).toList(growable: false),
  );
}

DiagnosisCaseModel _diagnosis(
  Map<String, dynamic> row, {
  String? imagePath,
  String? plotName,
}) {
  final id = row['id'] as String?;
  if (id == null) {
    throw const ApiException(
      code: 'INVALID_RESPONSE',
      message: 'The diagnosis response has no case identifier',
    );
  }
  final assessment = row['active_assessment'] is Map<String, dynamic>
      ? row['active_assessment'] as Map<String, dynamic>
      : null;
  final predictedCrop = assessment?['predicted_crop'] as String?;
  final primaryDisease = assessment?['primary_disease'] as String?;
  final alternatives = _maps(assessment?['alternatives']);
  final images = _maps(row['images']);
  final confidence = assessment?['confidence_label'] as String? ?? 'low';
  final predictions = <DiagnosisPrediction>[
    if (primaryDisease != null)
      DiagnosisPrediction(
        code: _code(primaryDisease),
        name: primaryDisease,
        confidenceLabel: confidence,
        summary: 'Possible match based on all submitted leaf images.',
      ),
    ...alternatives.map((alternative) {
      final disease =
          alternative['disease_name'] as String? ?? 'Unknown possibility';
      final crop =
          alternative['crop_name'] as String? ?? predictedCrop ?? 'Crop';
      return DiagnosisPrediction(
        code: _code(disease),
        name: disease,
        confidenceLabel: 'alternative',
        summary: '$crop · possibility ${alternative['rank'] ?? '—'}',
      );
    }),
  ];
  return DiagnosisCaseModel(
    id: id,
    cropName: predictedCrop ?? row['plant_name'] as String? ?? 'Unknown crop',
    plotName: plotName,
    farmId: row['farm_id'] as String?,
    plotId: row['plot_id'] as String?,
    cropId: row['crop_id'] as String?,
    createdAt:
        DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now(),
    imageAsset: 'assets/images/leaf_healthy.jpg',
    imagePath: imagePath,
    imageIds: images
        .map((image) => image['id'])
        .whereType<String>()
        .toList(growable: false),
    predictions: predictions,
    qualityFlags: images
        .expand((image) => _strings(image['quality_flags']))
        .toSet()
        .toList(growable: false),
    confidenceLabel: confidence,
    retakeRecommended: row['retake_recommended'] as bool? ?? false,
    isSample: false,
  );
}

Map<String, dynamic> _map(Object? value, {required String contract}) {
  if (value is Map<String, dynamic>) return value;
  throw ApiException(
    code: 'INVALID_RESPONSE',
    message: 'The $contract response could not be read',
  );
}

List<dynamic> _list(Object? value, {required String contract}) {
  if (value is List<dynamic>) return value;
  throw ApiException(
    code: 'INVALID_RESPONSE',
    message: 'The $contract response could not be read',
  );
}

Iterable<Map<String, dynamic>> _maps(Object? value) => switch (value) {
  final List<dynamic> values => values.whereType<Map<String, dynamic>>(),
  _ => const Iterable<Map<String, dynamic>>.empty(),
};

Iterable<String> _strings(Object? value) => switch (value) {
  final List<dynamic> values => values.whereType<String>(),
  _ => const Iterable<String>.empty(),
};

String _code(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
    .replaceAll(RegExp(r'^_|_$'), '');

String? _text(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
