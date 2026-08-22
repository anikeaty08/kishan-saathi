import 'package:flutter_test/flutter_test.dart';
import 'package:krishisathi/core/permissions/app_permission_service.dart';

import 'support/test_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('denied device permission never enables the app feature', () async {
    final controller = await createTestController(
      permissionService: const TestPermissionService(
        response: AppPermissionState.denied,
      ),
    );
    addTearDown(controller.dispose);

    final status = await controller.setCameraEnabled(true);

    expect(status, AppPermissionState.denied);
    expect(controller.cameraEnabled, isFalse);
    expect(controller.preferences.getBool('camera_enabled'), isFalse);
  });

  test('granted device permissions enable their requested features', () async {
    final controller = await createTestController(
      permissionService: const TestPermissionService(),
    );
    addTearDown(controller.dispose);

    expect(
      await controller.setLocationEnabled(true),
      AppPermissionState.granted,
    );
    expect(await controller.setNotifications(true), AppPermissionState.granted);

    expect(controller.locationEnabled, isTrue);
    expect(controller.notificationsEnabled, isTrue);
  });

  test('farm reminders and weather alerts remain independent', () async {
    final controller = await createTestController(
      permissionService: const TestPermissionService(),
    );
    addTearDown(controller.dispose);
    controller
      ..notificationPermission = AppPermissionState.denied
      ..notificationsEnabled = false
      ..farmReminderNotificationsEnabled = false
      ..weatherAlertNotificationsEnabled = false;

    await controller.setFarmReminderNotifications(true);

    expect(controller.farmReminderNotificationsEnabled, isTrue);
    expect(controller.weatherAlertNotificationsEnabled, isFalse);

    await controller.setWeatherAlertNotifications(true);
    await controller.setFarmReminderNotifications(false);

    expect(controller.farmReminderNotificationsEnabled, isFalse);
    expect(controller.weatherAlertNotificationsEnabled, isTrue);
  });

  test(
    'permission state is reconciled after returning from settings',
    () async {
      final permissions = MutablePermissionService();
      final controller = await createTestController(
        permissionService: permissions,
      );
      addTearDown(controller.dispose);
      controller.preferences
        ..setBool('location_enabled', true)
        ..setBool('camera_enabled', true)
        ..setBool('notifications_enabled', true)
        ..setBool('farm_reminder_notifications_enabled', true)
        ..setBool('weather_alert_notifications_enabled', false);

      permissions.states
        ..[AppPermissionKind.location] = AppPermissionState.granted
        ..[AppPermissionKind.camera] = AppPermissionState.granted
        ..[AppPermissionKind.microphone] = AppPermissionState.granted
        ..[AppPermissionKind.notifications] = AppPermissionState.granted;
      await controller.refreshPermissionStates();

      expect(controller.locationEnabled, isTrue);
      expect(controller.cameraEnabled, isTrue);
      expect(controller.microphonePermission, AppPermissionState.granted);
      expect(controller.farmReminderNotificationsEnabled, isTrue);
      expect(controller.weatherAlertNotificationsEnabled, isFalse);

      permissions.states[AppPermissionKind.location] =
          AppPermissionState.permanentlyDenied;
      await controller.refreshPermissionStates();

      expect(controller.locationEnabled, isFalse);
      expect(controller.locationPermission.requiresSettings, isTrue);
    },
  );
}

class MutablePermissionService implements AppPermissionService {
  final states = <AppPermissionKind, AppPermissionState>{};

  @override
  Future<bool> openSettings() async => true;

  @override
  Future<AppPermissionState> request(AppPermissionKind kind) async =>
      states[kind] ?? AppPermissionState.denied;

  @override
  Future<AppPermissionState> status(AppPermissionKind kind) async =>
      states[kind] ?? AppPermissionState.denied;
}
