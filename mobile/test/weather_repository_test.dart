import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:krishisathi/core/network/api_client.dart';
import 'package:krishisathi/core/network/api_exception.dart';
import 'package:krishisathi/core/network/krishi_api.dart';
import 'package:krishisathi/core/network/token_store.dart';
import 'package:krishisathi/features/home/data/weather_repository.dart';

void main() {
  test('plot weather keeps forecast when current conditions fail', () async {
    final repository = WeatherRepository(
      _FakeWeatherApi(
        currentError: const ApiException(
          code: 'CURRENT_WEATHER_UNAVAILABLE',
          message: 'unavailable',
        ),
        forecastPayload: _forecastEnvelope(),
      ),
    );

    final result = await repository.forPlot('plot-1');

    expect(result.current, isNull);
    expect(result.forecast, hasLength(1));
    expect(result.timezone, 'Asia/Kolkata');
  });

  test('plot weather keeps current conditions when forecast fails', () async {
    final repository = WeatherRepository(
      _FakeWeatherApi(
        currentPayload: _currentEnvelope(),
        forecastError: const ApiException(
          code: 'FORECAST_UNAVAILABLE',
          message: 'unavailable',
        ),
      ),
    );

    final result = await repository.forPlot('plot-1');

    expect(result.current?.temperature, 27.5);
    expect(result.forecast, isEmpty);
  });

  test('malformed provider timestamps are never replaced with now', () async {
    final malformed = _currentEnvelope()..['fetched_at'] = 'not-a-date';
    final repository = WeatherRepository(
      _FakeWeatherApi(
        currentPayload: malformed,
        forecastError: const ApiException(
          code: 'FORECAST_UNAVAILABLE',
          message: 'unavailable',
        ),
      ),
    );

    await expectLater(
      repository.forPlot('plot-1'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.code,
          'code',
          'INVALID_RESPONSE',
        ),
      ),
    );
  });

  test(
    'missing numeric weather fields are rejected, not coerced to zero',
    () async {
      final malformed = _currentEnvelope();
      (malformed['weather']! as Map<String, Object?>).remove('temperature_c');
      final repository = WeatherRepository(
        _FakeWeatherApi(
          currentPayload: malformed,
          forecastError: const ApiException(
            code: 'FORECAST_UNAVAILABLE',
            message: 'unavailable',
          ),
        ),
      );

      await expectLater(
        repository.forPlot('plot-1'),
        throwsA(isA<ApiException>()),
      );
    },
  );
}

Map<String, Object?> _currentEnvelope() => {
  'weather': <String, Object?>{
    'temperature_c': 27.5,
    'condition_code': 801,
    'condition': 'Clouds',
    'humidity_percent': 68,
    'wind_speed_mps': 3.2,
    'rain_last_hour_mm': 0.0,
  },
  'fetched_at': '2026-08-15T10:00:00Z',
  'is_stale': false,
};

Map<String, Object?> _forecastEnvelope() => {
  'forecast': <String, Object?>{
    'timezone': 'Asia/Kolkata',
    'days': <Object?>[
      <String, Object?>{
        'date': '2026-08-16',
        'condition_code': 61,
        'temperature_min_c': 23.0,
        'temperature_max_c': 31.0,
        'precipitation_sum_mm': 5.5,
        'precipitation_probability_max_percent': 70,
        'wind_speed_max_kmh': 18.0,
      },
    ],
  },
  'fetched_at': '2026-08-15T10:00:00Z',
  'is_stale': false,
};

class _FakeWeatherApi extends KrishiApi {
  _FakeWeatherApi({
    this.currentPayload,
    this.currentError,
    this.forecastPayload,
    this.forecastError,
  }) : super(
         ApiClient(
           baseUri: Uri.parse('https://api.example.test'),
           tokenStore: SecureTokenStore(),
           client: MockClient((_) async => throw StateError('unused')),
         ),
       );

  final Object? currentPayload;
  final ApiException? currentError;
  final Object? forecastPayload;
  final ApiException? forecastError;

  @override
  Future<Object?> currentPlotWeather(String id) async {
    if (currentError case final error?) throw error;
    return currentPayload;
  }

  @override
  Future<Object?> plotForecast(String id) async {
    if (forecastError case final error?) throw error;
    return forecastPayload;
  }
}
