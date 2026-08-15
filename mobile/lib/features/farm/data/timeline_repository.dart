import '../../../core/models/app_models.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/krishi_api.dart';

class TimelineRepository {
  const TimelineRepository(this._api);

  final KrishiApi _api;

  Future<TimelinePageModel> loadPlotTimeline(
    String plotId, {
    String? cropId,
    Set<String> categories = const {},
    DateTime? dateFrom,
    DateTime? dateTo,
    int limit = 30,
    int offset = 0,
  }) async {
    final payload = await _api.plotTimeline(
      plotId,
      filters: {
        'crop_id': ?cropId,
        if (categories.isNotEmpty) 'category': categories.toList(),
        if (dateFrom != null) 'date_from': dateFrom.toUtc().toIso8601String(),
        if (dateTo != null) 'date_to': dateTo.toUtc().toIso8601String(),
        'limit': '$limit',
        'offset': '$offset',
      },
    );
    final envelope = _map(payload, 'plot timeline');
    final items = envelope['items'];
    if (items is! List<dynamic>) {
      throw const ApiException(
        code: 'INVALID_RESPONSE',
        message: 'The plot timeline could not be read',
      );
    }
    return TimelinePageModel(
      items: items
          .map((item) => _event(_map(item, 'timeline event')))
          .toList(growable: false),
      hasMore: envelope['has_more'] as bool? ?? false,
      limit: (envelope['limit'] as num?)?.toInt() ?? limit,
      offset: (envelope['offset'] as num?)?.toInt() ?? offset,
    );
  }
}

TimelineEventModel _event(Map<String, dynamic> row) {
  final id = row['id'] as String?;
  final referenceId = row['reference_id'] as String?;
  final occurredAt = DateTime.tryParse(row['occurred_at'] as String? ?? '');
  if (id == null || referenceId == null || occurredAt == null) {
    throw const ApiException(
      code: 'INVALID_RESPONSE',
      message: 'A plot timeline event is incomplete',
    );
  }
  return TimelineEventModel(
    id: id,
    category: row['category'] as String? ?? 'activity',
    eventCode: row['event_code'] as String? ?? 'activity.recorded',
    occurredAt: occurredAt,
    referenceId: referenceId,
    data: row['data'] is Map<String, dynamic>
        ? row['data'] as Map<String, dynamic>
        : const {},
  );
}

Map<String, dynamic> _map(Object? value, String contract) {
  if (value is Map<String, dynamic>) return value;
  throw ApiException(
    code: 'INVALID_RESPONSE',
    message: 'The $contract response could not be read',
  );
}
