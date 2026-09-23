import 'package:permission_handler/permission_handler.dart';

enum BackgroundLocationPermissionStatus {
  granted,
  denied,
  permanentlyDenied,
  needsSettings,
}

class PermissionService {
  static final PermissionService instance = PermissionService._();

  PermissionService._();

  Future<BackgroundLocationPermissionStatus> requestBackgroundLocation() async {
    var foregroundStatus = await Permission.locationWhenInUse.status;

    if (foregroundStatus.isDenied) {
      foregroundStatus = await Permission.locationWhenInUse.request();
    }

    if (foregroundStatus.isPermanentlyDenied) {
      return BackgroundLocationPermissionStatus.permanentlyDenied;
    }
    if (!foregroundStatus.isGranted) {
      return BackgroundLocationPermissionStatus.denied;
    }

    var backgroundStatus = await Permission.locationAlways.status;
    if (backgroundStatus.isGranted) {
      return BackgroundLocationPermissionStatus.granted;
    }
    if (backgroundStatus.isPermanentlyDenied) {
      return BackgroundLocationPermissionStatus.permanentlyDenied;
    }

    backgroundStatus = await Permission.locationAlways.request();
    if (backgroundStatus.isGranted) {
      return BackgroundLocationPermissionStatus.granted;
    }
    if (backgroundStatus.isPermanentlyDenied) {
      return BackgroundLocationPermissionStatus.permanentlyDenied;
    }

    return BackgroundLocationPermissionStatus.needsSettings;
  }

  Future<bool> requestNotificationPermission() async {
    final status = await Permission.notification.status;
    if (status.isDenied) {
      final result = await Permission.notification.request();
      return result.isGranted;
    }
    return status.isGranted;
  }

  Future<bool> openSettings() => openAppSettings();
}
