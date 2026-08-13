import '../../../core/models/app_models.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/krishi_api.dart';

class MemoryRepository {
  const MemoryRepository(this._api);

  final KrishiApi _api;

  Future<List<MemoryFactModel>> loadAll({
    required Iterable<FarmModel> farms,
  }) async {
    final facts = <String, MemoryFactModel>{};
    for (final farm in farms) {
      final farmPayload = await _api.listFarmMemories(
        farm.id,
        paging: {'limit': '100', 'offset': '0'},
      );
      for (final row in _list(farmPayload, 'farm memories')) {
        final fact = _fact(_map(row, 'memory'), scope: farm.name);
        facts[fact.id] = fact;
      }
      for (final plot in farm.plots) {
        final plotPayload = await _api.listPlotMemories(
          plot.id,
          paging: {'limit': '100', 'offset': '0'},
        );
        for (final row in _list(plotPayload, 'plot memories')) {
          final fact = _fact(_map(row, 'memory'), scope: plot.name);
          facts[fact.id] = fact;
        }
      }
    }
    return facts.values.toList(growable: false);
  }

  Future<void> delete(String id) => _api.deleteMemory(id);
}

MemoryFactModel _fact(Map<String, dynamic> row, {required String scope}) =>
    MemoryFactModel(
      id: row['id'] as String,
      text: row['text'] as String? ?? 'Saved farm fact',
      scope: scope,
      status: row['index_status'] as String? ?? 'pending',
    );

Map<String, dynamic> _map(Object? value, String contract) {
  if (value is Map<String, dynamic>) return value;
  throw ApiException(
    code: 'INVALID_RESPONSE',
    message: 'The $contract response could not be read',
  );
}

List<dynamic> _list(Object? value, String contract) {
  if (value is List<dynamic>) return value;
  throw ApiException(
    code: 'INVALID_RESPONSE',
    message: 'The $contract response could not be read',
  );
}
