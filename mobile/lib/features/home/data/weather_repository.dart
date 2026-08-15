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
    final currentFuture = _capture(() async {
      return _current(await _api.currentPlotWeather(plotId));
    });
    final forecastFuture = _capture(() async {
      final envelope = _map(await _api.plotForecast(plotId), 'plot forecast');
      final forecast = _map(envelope['forecast'], 'plot forecast details');
      final days = forecast['days'];
      if (days is! List<dynamic>) {
        throw const ApiException(
          code: 'INVALID_RESPONSE',
          message: 'The plot forecast days could not be read',
        );
      }
      final fetchedAt = _dateTime(
        envelope['fetched_at'],
        'forecast fetched_at',
      );
      return _ForecastResult(
        days: days
            .map((value) => _forecastDay(_map(value, 'forecast day')))
            .toList(growable: false),
        timezone: _requiredString(forecast['timezone'], 'forecast timezone'),
        fetchedAt: fetchedAt,
        isStale: _requiredBool(envelope['is_stale'], 'forecast is_stale'),
      );
    });
    final currentResult = await currentFuture;
    final forecastResult = await forecastFuture;
    if (currentResult.value == null && forecastResult.value == null) {
      throw currentResult.error ?? forecastResult.error!;
    }
    final current = currentResult.value;
    final forecast = forecastResult.value;
    return PlotWeatherModel(
      current: current,
      forecast: forecast?.days ?? const [],
      timezone: forecast?.timezone ?? 'local',
      fetchedAt: forecast?.fetchedAt ?? current!.fetchedAt,
      isStale: (current?.isStale ?? false) || (forecast?.isStale ?? false),
    );
  }

  WeatherSnapshot _current(Object? payload) {
    final envelope = _map(payload, 'current weather');
    final weather = _map(envelope['weather'], 'current weather details');
    return WeatherSnapshot(
      temperature: _double(weather['temperature_c'], 'temperature_c'),
      conditionCode: _conditionCode(weather['condition_code']),
      conditionLabel: _requiredString(weather['condition'], 'condition'),
      rainChance: 0,
      rainLastHourMm: _nullableDouble(
        weather['rain_last_hour_mm'],
        'rain_last_hour_mm',
        minimum: 0,
      ),
      humidity: _int(
        weather['humidity_percent'],
        'humidity_percent',
        minimum: 0,
        maximum: 100,
      ),
      windKph:
          _double(weather['wind_speed_mps'], 'wind_speed_mps', minimum: 0) *
          3.6,
      fetchedAt: _dateTime(envelope['fetched_at'], 'weather fetched_at'),
      isStale: _requiredBool(envelope['is_stale'], 'weather is_stale'),
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
      conditionCode: _conditionCode(row['condition_code']),
      minimumTemperature: _double(
        row['temperature_min_c'],
        'temperature_min_c',
      ),
      maximumTemperature: _double(
        row['temperature_max_c'],
        'temperature_max_c',
      ),
      precipitationMm: _double(
        row['precipitation_sum_mm'],
        'precipitation_sum_mm',
        minimum: 0,
      ),
      rainChance: _int(
        row['precipitation_probability_max_percent'],
        'precipitation_probability_max_percent',
        minimum: 0,
        maximum: 100,
      ),
      maximumWindKph: _double(
        row['wind_speed_max_kmh'],
        'wind_speed_max_kmh',
        minimum: 0,
      ),
    );
  }
}

class _Capture<T> {
  const _Capture({this.value, this.error});

  final T? value;
  final ApiException? error;
}

class _ForecastResult {
  const _ForecastResult({
    required this.days,
    required this.timezone,
    required this.fetchedAt,
    required this.isStale,
  });

  final List<ForecastDayModel> days;
  final String timezone;
  final DateTime fetchedAt;
  final bool isStale;
}

Future<_Capture<T>> _capture<T>(Future<T> Function() action) async {
  try {
    return _Capture(value: await action());
  } on ApiException catch (error) {
    return _Capture(error: error);
  }
}

DateTime _dateTime(Object? value, String contract) {
  final parsed = value is String ? DateTime.tryParse(value) : null;
  if (parsed == null || !parsed.isUtc) {
    throw ApiException(
      code: 'INVALID_RESPONSE',
      message: 'The $contract could not be read',
    );
  }
  return parsed;
}

Map<String, dynamic> _map(Object? value, String contract) {
  if (value is Map<String, dynamic>) return value;
  throw ApiException(
    code: 'INVALID_RESPONSE',
    message: 'The $contract response could not be read',
  );
}

double _double(Object? value, String contract, {double? minimum}) {
  if (value case final num number) {
    final resolved = number.toDouble();
    if (resolved.isFinite && (minimum == null || resolved >= minimum)) {
      return resolved;
    }
  }
  throw ApiException(
    code: 'INVALID_RESPONSE',
    message: 'The $contract value could not be read',
  );
}

double? _nullableDouble(Object? value, String contract, {double? minimum}) {
  if (value == null) return null;
  return _double(value, contract, minimum: minimum);
}

int _int(Object? value, String contract, {int? minimum, int? maximum}) {
  if (value case final num number) {
    final resolved = number.toInt();
    if (number.toDouble() == resolved.toDouble() &&
        (minimum == null || resolved >= minimum) &&
        (maximum == null || resolved <= maximum)) {
      return resolved;
    }
  }
  throw ApiException(
    code: 'INVALID_RESPONSE',
    message: 'The $contract value could not be read',
  );
}

String _requiredString(Object? value, String contract) {
  if (value case final String text when text.trim().isNotEmpty) {
    return text.trim();
  }
  throw ApiException(
    code: 'INVALID_RESPONSE',
    message: 'The $contract value could not be read',
  );
}

bool _requiredBool(Object? value, String contract) {
  if (value case final bool flag) return flag;
  throw ApiException(
    code: 'INVALID_RESPONSE',
    message: 'The $contract value could not be read',
  );
}

String _conditionCode(Object? value) {
  if (value case final num number) return '${number.toInt()}';
  if (value case final String text when text.trim().isNotEmpty) {
    return text.trim();
  }
  throw const ApiException(
    code: 'INVALID_RESPONSE',
    message: 'The condition code could not be read',
  );
}
