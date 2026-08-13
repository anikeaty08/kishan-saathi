import 'package:geolocator/geolocator.dart';

import '../../../core/models/app_models.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/krishi_api.dart';

class LocationRepository {
  const LocationRepository(this._api);

  final KrishiApi _api;

  Future<List<LocationPoint>> search(
    String query, {
    required String language,
  }) async {
    final normalized = query.trim();
    if (normalized.length < 2) return const [];
    final payload = await _api.searchLocations(normalized, language: language);
    if (payload is! List<dynamic>) {
      throw const ApiException(
        code: 'INVALID_RESPONSE',
        message: 'Location search could not be read',
      );
    }
    return payload
        .map((item) {
          if (item is! Map<String, dynamic>) {
            throw const ApiException(
              code: 'INVALID_RESPONSE',
              message: 'A location result could not be read',
            );
          }
          final name = item['name'] as String?;
          final latitude = _number(item['latitude']);
          final longitude = _number(item['longitude']);
          if (name == null || latitude == null || longitude == null) {
            throw const ApiException(
              code: 'INVALID_RESPONSE',
              message: 'A location result is incomplete',
            );
          }
          final detail = [
            name,
            item['admin2'] as String?,
            item['admin1'] as String?,
          ].whereType<String>().where((part) => part.trim().isNotEmpty).toSet();
          return LocationPoint(
            latitude: latitude,
            longitude: longitude,
            label: detail.join(', '),
            country: item['country'] as String?,
          );
        })
        .toList(growable: false);
  }

  Future<LocationPoint> currentDeviceLocation({
    bool requestPermission = true,
  }) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const ApiException(
        code: 'LOCATION_SERVICE_DISABLED',
        message: 'Turn on location services to use your current position',
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && requestPermission) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const ApiException(
        code: 'LOCATION_PERMISSION_DENIED',
        message: 'Location permission was not granted',
      );
    }
    if (permission == LocationPermission.deniedForever) {
      throw const ApiException(
        code: 'LOCATION_PERMISSION_DENIED_FOREVER',
        message: 'Allow location access from device settings',
      );
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 15),
      ),
    );
    return LocationPoint(
      latitude: position.latitude,
      longitude: position.longitude,
      label: 'Current location',
    );
  }
}

double? _number(Object? value) => switch (value) {
  final num number => number.toDouble(),
  final String text => double.tryParse(text),
  _ => null,
};
