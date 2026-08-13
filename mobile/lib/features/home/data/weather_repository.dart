import '../../../core/models/app_models.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/krishi_api.dart';

class WeatherRepository {
  const WeatherRepository(this._api);

  final KrishiApi _api;

  Future<WeatherSnapshot> current({
    required double latitude,
    required double longitude,
  }) async {
    final payload = await _api.currentWeather({
      'latitude': latitude,
      'longitude': longitude,
    });
    return _current(payload);
  }

  Future<PlotWeatherModel> forPlot(String plotId) async {
    final responses = await Future.wait([
      _api.currentPlotWeather(plotId),
      _api.plotForecast(plotId),
    ]);
    final current = _current(responses[0]);
    final envelope = _map(responses[1], 'plot forecast');
    final forecast = _map(envelope['forecast'], 'plot forecast details');
    final days = forecast['days'];
    if (days is! List<dynamic>) {
      throw const ApiException(
        code: 'INVALID_RESPONSE',
        message: 'The plot forecast days could not be read',
      );
    }
    return PlotWeatherModel(
      current: current,
      forecast: days
          .map((value) => _forecastDay(_map(value, 'forecast day')))
          .toList(growable: false),
      timezone: forecast['timezone'] as String? ?? 'local',
      fetchedAt:
          DateTime.tryParse(envelope['fetched_at'] as String? ?? '') ??
          DateTime.now(),
      isStale: current.isStale || (envelope['is_stale'] as bool? ?? false),
    );
  }

  WeatherSnapshot _current(Object? payload) {
    final envelope = _map(payload, 'current weather');
    final weather = _map(envelope['weather'], 'current weather details');
    return WeatherSnapshot(
      temperature: _double(weather['temperature_c']),
      conditionCode: '${weather['condition_code'] ?? 'unknown'}',
      conditionLabel: weather['condition'] as String?,
      rainChance: 0,
      rainLastHourMm: _nullableDouble(weather['rain_last_hour_mm']),
      humidity: _int(weather['humidity_percent']),
      windKph: _double(weather['wind_speed_mps']) * 3.6,
      fetchedAt:
          DateTime.tryParse(envelope['fetched_at'] as String? ?? '') ??
          DateTime.now(),
      isStale: envelope['is_stale'] as bool? ?? false,
    );
  }

  ForecastDayModel _forecastDay(Map<String, dynamic> row) {
    final date = DateTime.tryParse(row['date'] as String? ?? '');
    if (date == null) {
      throw const ApiException(
        code: 'INVALID_RESPONSE',
        message: 'A forecast date could not be read',
      );
    }
    return ForecastDayModel(
      date: date,
      conditionCode: '${row['condition_code'] ?? 'unknown'}',
      minimumTemperature: _double(row['temperature_min_c']),
      maximumTemperature: _double(row['temperature_max_c']),
      precipitationMm: _double(row['precipitation_sum_mm']),
      rainChance: _int(row['precipitation_probability_max_percent']),
      maximumWindKph: _double(row['wind_speed_max_kmh']),
    );
  }
}

Map<String, dynamic> _map(Object? value, String contract) {
  if (value is Map<String, dynamic>) return value;
  throw ApiException(
    code: 'INVALID_RESPONSE',
    message: 'The $contract response could not be read',
  );
}

double _double(Object? value) => switch (value) {
  final num number => number.toDouble(),
  _ => 0,
};

double? _nullableDouble(Object? value) => switch (value) {
  final num number => number.toDouble(),
  _ => null,
};

int _int(Object? value) => switch (value) {
  final num number => number.toInt(),
  _ => 0,
};
