import 'package:permission_handler/permission_handler.dart';

enum AppPermissionKind { location, camera, notifications }

enum AppPermissionState {
  granted,
  limited,
  provisional,
  denied,
  permanentlyDenied,
  restricted;

  bool get isAllowed =>
      this == granted || this == limited || this == provisional;

  bool get requiresSettings => this == permanentlyDenied || this == restricted;
}

abstract interface class AppPermissionService {
  Future<AppPermissionState> status(AppPermissionKind kind);

  Future<AppPermissionState> request(AppPermissionKind kind);

  Future<bool> openSettings();
}

class DeviceAppPermissionService implements AppPermissionService {
  const DeviceAppPermissionService();

  @override
  Future<AppPermissionState> status(AppPermissionKind kind) async =>
      _map(await _permission(kind).status);

  @override
  Future<AppPermissionState> request(AppPermissionKind kind) async =>
      _map(await _permission(kind).request());

  @override
  Future<bool> openSettings() => openAppSettings();

  Permission _permission(AppPermissionKind kind) => switch (kind) {
    AppPermissionKind.location => Permission.locationWhenInUse,
    AppPermissionKind.camera => Permission.camera,
    AppPermissionKind.notifications => Permission.notification,
  };

  AppPermissionState _map(PermissionStatus status) => switch (status) {
    PermissionStatus.granted => AppPermissionState.granted,
    PermissionStatus.limited => AppPermissionState.limited,
    PermissionStatus.provisional => AppPermissionState.provisional,
    PermissionStatus.permanentlyDenied => AppPermissionState.permanentlyDenied,
    PermissionStatus.restricted => AppPermissionState.restricted,
    PermissionStatus.denied => AppPermissionState.denied,
  };
}
