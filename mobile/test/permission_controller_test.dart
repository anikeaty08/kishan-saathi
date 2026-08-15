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
}
