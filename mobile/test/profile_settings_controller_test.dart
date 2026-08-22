import 'package:flutter_test/flutter_test.dart';
import 'package:krishisathi/core/network/api_client.dart';
import 'package:krishisathi/core/network/api_endpoints.dart';
import 'package:krishisathi/core/network/api_exception.dart';
import 'package:krishisathi/core/network/token_store.dart';
import 'package:krishisathi/core/permissions/app_permission_service.dart';

import 'support/test_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a missing farmer name never falls back to the email prefix', () async {
    final api = ProfileApiClient(
      profile: _profile(name: null, language: null, onboarding: false),
    );
    final controller = await createTestController(
      live: true,
      farmerName: 'Old local name',
      apiClient: api,
    );
    addTearDown(controller.dispose);

    await controller.refreshProfile();

    expect(controller.farmerName, isEmpty);
    expect(controller.hasFarmerName, isFalse);
    expect(controller.onboardingComplete, isFalse);
  });

  test(
    'profile hydration keeps server settings and local cache aligned',
    () async {
      final api = ProfileApiClient(
        profile: _profile(
          name: 'Kishan Kumar',
          language: 'hi',
          areaUnit: 'hectare',
          notifications: true,
          onboarding: true,
        ),
      );
      final controller = await createTestController(live: true, apiClient: api);
      addTearDown(controller.dispose);
      controller.notificationPermission = AppPermissionState.granted;

      await controller.refreshProfile();

      expect(controller.farmerName, 'Kishan Kumar');
      expect(controller.locale.languageCode, 'hi');
      expect(controller.preferredAreaUnit, 'hectare');
      expect(controller.notificationsEnabled, isTrue);
      expect(controller.farmReminderNotificationsEnabled, isTrue);
      expect(controller.weatherAlertNotificationsEnabled, isTrue);
      expect(controller.onboardingComplete, isTrue);
      expect(controller.preferences.getString('preferred_language'), 'hi');
      expect(
        controller.preferences.getString('preferred_area_unit'),
        'hectare',
      );
      expect(controller.preferences.getBool('notifications_enabled'), isTrue);
    },
  );

  test(
    'name, language, area, and notifications are persisted through me',
    () async {
      final api = ProfileApiClient(
        profile: _profile(name: 'Old Name', language: 'en', onboarding: true),
      );
      final controller = await createTestController(
        live: true,
        apiClient: api,
        permissionService: const TestPermissionService(),
      );
      addTearDown(controller.dispose);
      controller.notificationPermission = AppPermissionState.granted;

      await controller.setFarmerName('  New Name  ');
      await controller.setLocale('hi');
      await controller.setPreferredAreaUnit('hectare');
      await controller.setNotifications(true);

      expect(api.patches, [
        {'name': 'New Name'},
        {'preferred_language': 'hi'},
        {'area_unit': 'hectare'},
        {'notifications_enabled': true},
      ]);
      expect(controller.farmerName, 'New Name');
      expect(controller.locale.languageCode, 'hi');
      expect(controller.preferredAreaUnit, 'hectare');
      expect(controller.notificationsEnabled, isTrue);
    },
  );

  test(
    'blank profile names fail locally instead of silently closing',
    () async {
      final controller = await createTestController();
      addTearDown(controller.dispose);

      await expectLater(
        controller.setFarmerName('   '),
        throwsA(
          isA<ApiException>().having(
            (error) => error.code,
            'code',
            'PROFILE_NAME_REQUIRED',
          ),
        ),
      );
    },
  );
}

Map<String, Object?> _profile({
  required String? name,
  required String? language,
  String areaUnit = 'acre',
  bool notifications = false,
  required bool onboarding,
}) => {
  'name': name,
  'email': 'farmer@example.com',
  'preferred_language': language,
  'area_unit': areaUnit,
  'notifications_enabled': notifications,
  'onboarding_complete': onboarding,
};

class ProfileApiClient extends ApiClient {
  ProfileApiClient({required this.profile})
    : super(
        baseUri: Uri.parse('http://localhost:8000'),
        tokenStore: SecureTokenStore(),
      );

  final Map<String, Object?> profile;
  final List<Map<String, Object?>> patches = [];

  @override
  Future<Object?> get(
    String path, {
    Map<String, Object?>? query,
    Map<String, String>? headers,
    bool auth = true,
  }) async {
    expect(path, ApiEndpoints.me);
    return Map<String, Object?>.from(profile);
  }

  @override
  Future<Object?> patch(String path, {Object? body, bool auth = true}) async {
    expect(path, ApiEndpoints.me);
    final changes = Map<String, Object?>.from(body! as Map);
    patches.add(changes);
    profile.addAll(changes);
    profile['onboarding_complete'] =
        (profile['name'] as String?)?.trim().isNotEmpty == true &&
        profile['preferred_language'] != null;
    return Map<String, Object?>.from(profile);
  }
}
