import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import 'package:workmanager/workmanager.dart';
import '../firebase_options.dart';
import '../models/geo_location.dart';
import '../models/tracking_schedule.dart';
import 'database_helper.dart';
import 'sync_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────

const String geoTrackingTaskKey = "com.ebtfusion.expensetracker.geo_tracking";
const String geoTrackingUniqueName = "periodic-geo-tracking";
const Duration geoCaptureInterval = Duration(minutes: 15);
const Duration geoCaptureMinGap = Duration(minutes: 14);

// ─────────────────────────────────────────────────────────────────────────────
// Schedule helper used in ALL isolates (top-level so WorkManager can use it)
// ─────────────────────────────────────────────────────────────────────────────

Future<TrackingSchedule?> _loadSchedule(String userId) async {
  try {
    return await DatabaseHelper.instance.getTrackingSchedule(userId);
  } catch (e) {
    return null;
  }
}

Future<bool> isWithinScheduleForUser(String userId, [DateTime? checkTime]) async {
  final schedule = await _loadSchedule(userId);
  if (schedule == null) return false;
  return schedule.isWithinAllowedSchedule(checkTime);
}

// ─────────────────────────────────────────────────────────────────────────────
// WorkManager fallback (handles deep background, battery saver, post-reboot)
// ─────────────────────────────────────────────────────────────────────────────

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    debugPrint("[Workmanager] Background execution started: $taskName");
    try {
      // If foreground task is already running, skip to avoid engine collision
      if (await FlutterForegroundTask.isRunningService) {
        debugPrint("[Workmanager] Foreground service is active; skipping duplicate run.");
        return true;
      }

      await _ensureFirebaseInitialized();

      if (taskName == geoTrackingTaskKey ||
          taskName == Workmanager.iOSBackgroundTask) {
        final userId = inputData?['user_id'] as String? ??
            await LocationService.resolveUserId();
        if (userId == null || userId.isEmpty) {
          debugPrint("[Workmanager] No user ID available; completing task.");
          return true;
        }

        // ── STRICT SCHEDULE GATE ──────────────────────────────────────────
        final allowed = await isWithinScheduleForUser(userId);
        if (!allowed) {
          debugPrint("[Workmanager] Outside schedule – skipping location capture.");
          return true;
        }

        await LocationService.persistCurrentLocation(
          userId: userId,
          ignoreThrottle: false,
        );
        await SyncService.instance.syncAll(userId);
      }
      return true;
    } catch (e) {
      debugPrint("[Workmanager] Background location error: $e");
      return true; // Always true to avoid infinite RETRY loops
    }
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// flutter_foreground_task: background isolate entry point
// ─────────────────────────────────────────────────────────────────────────────

@pragma('vm:entry-point')
void startForegroundTask() {
  FlutterForegroundTask.setTaskHandler(_GpsTaskHandler());
}

class _GpsTaskHandler extends TaskHandler {
  Timer? _captureTimer;
  Timer? _endCheckTimer;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[ForegroundTask] Task isolate started with starter: $starter');
    await _ensureFirebaseInitialized();

    final userId = await LocationService.resolveUserId();
    debugPrint('[ForegroundTask] Resolved userId onStart: $userId');

    // ── STRICT SCHEDULE GATE ──────────────────────────────────────────────
    if (userId == null || !await isWithinScheduleForUser(userId)) {
      debugPrint('[ForegroundTask] Outside schedule at start – stopping service.');
      await FlutterForegroundTask.stopService();
      return;
    }

    // Capture immediately on confirmed schedule start
    await LocationService.persistCurrentLocation(
      userId: userId,
      ignoreThrottle: true,
    );

    _startPeriodicCapture(userId);
    _scheduleEndCheck(userId);
  }

  void _startPeriodicCapture(String userId) {
    _captureTimer?.cancel();
    _captureTimer = Timer.periodic(geoCaptureInterval, (_) async {
      debugPrint('[ForegroundTask] Periodic timer fired.');
      final uId = await LocationService.resolveUserId() ?? userId;

      // ── STRICT SCHEDULE GATE every capture ──────────────────────────────
      if (!await isWithinScheduleForUser(uId)) {
        debugPrint('[ForegroundTask] Schedule ended – stopping service from timer.');
        _captureTimer?.cancel();
        _endCheckTimer?.cancel();
        await FlutterForegroundTask.stopService();
        return;
      }

      await LocationService.persistCurrentLocation(
        userId: uId,
        ignoreThrottle: false,
      );
    });
  }

  void _scheduleEndCheck(String userId) {
    // Check every minute whether the schedule has ended so we stop promptly
    _endCheckTimer?.cancel();
    _endCheckTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      final uId = await LocationService.resolveUserId() ?? userId;
      if (!await isWithinScheduleForUser(uId)) {
        debugPrint('[ForegroundTask] Schedule ended (end-check timer) – stopping service.');
        _captureTimer?.cancel();
        _endCheckTimer?.cancel();
        await FlutterForegroundTask.stopService();
      }
    });
  }

  @override
  void onRepeatEvent(DateTime timestamp) async {
    debugPrint('[ForegroundTask] onRepeatEvent triggered at $timestamp');
    final uId = await LocationService.resolveUserId();
    if (uId == null) return;

    // ── STRICT SCHEDULE GATE ──────────────────────────────────────────────
    if (!await isWithinScheduleForUser(uId)) {
      debugPrint('[ForegroundTask] onRepeatEvent outside schedule – stopping service.');
      await FlutterForegroundTask.stopService();
      return;
    }

    await LocationService.persistCurrentLocation(
      userId: uId,
      ignoreThrottle: false,
    );
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('[ForegroundTask] Task isolate destroyed (isTimeout: $isTimeout).');
    _captureTimer?.cancel();
    _captureTimer = null;
    _endCheckTimer?.cancel();
    _endCheckTimer = null;
  }
}

Future<void> _ensureFirebaseInitialized() async {
  if (Firebase.apps.isNotEmpty) return;
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

// ─────────────────────────────────────────────────────────────────────────────
// LocationService
// ─────────────────────────────────────────────────────────────────────────────

class LocationService {
  static final LocationService instance = LocationService._init();
  static const _uuid = Uuid();

  bool _isWorkmanagerInitialized = false;
  bool _isTracking = false;

  LocationService._init();

  bool get isTracking => _isTracking;

  // ── Resolve user ID across isolates ────────────────────────────────────────

  static Future<String?> resolveUserId([String? explicitUserId]) async {
    if (explicitUserId != null && explicitUserId.isNotEmpty) return explicitUserId;
    final authUid = FirebaseAuth.instance.currentUser?.uid;
    if (authUid != null && authUid.isNotEmpty) return authUid;
    final storedUid = await DatabaseHelper.instance.getSetting('current_user_id');
    if (storedUid != null && storedUid.isNotEmpty) return storedUid;
    return null;
  }

  // ── WorkManager init ──────────────────────────────────────────────────────

  Future<void> initializeBackgroundService() async {
    if (_isWorkmanagerInitialized) return;
    try {
      await Workmanager().initialize(callbackDispatcher);
      _isWorkmanagerInitialized = true;
      debugPrint('[LocationService] Workmanager initialized.');
    } catch (e) {
      debugPrint('[LocationService] Workmanager initialization error: $e');
    }
  }

  // ── Configure flutter_foreground_task ─────────────────────────────────────

  static void _configureForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'gps_tracking_channel',
        channelName: 'GPS Tracking',
        channelDescription: 'Tracks your location during your configured schedule.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        enableVibration: false,
        playSound: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(geoCaptureInterval.inMilliseconds),
        autoRunOnBoot: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  // ── Permission check ───────────────────────────────────────────────────────

  Future<bool> checkPermission() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  // ── Start tracking ─────────────────────────────────────────────────────────
  // Returns null on success, or a user-facing error string.

  Future<String?> startTracking([String? explicitUserId]) async {
    if (_isTracking) return null;

    final userId = explicitUserId ??
        FirebaseAuth.instance.currentUser?.uid ??
        await DatabaseHelper.instance.getSetting('current_user_id');

    // ── STRICT SCHEDULE GATE ──────────────────────────────────────────────
    if (userId != null && userId.isNotEmpty) {
      final schedule = await DatabaseHelper.instance.getTrackingSchedule(userId);
      final result = schedule.validateSchedule();
      if (!result.isWithinSchedule) {
        debugPrint('[LocationService] Start refused: ${result.statusMessage}');
        return 'Location tracking is available only during your selected schedule.';
      }
    }

    await initializeBackgroundService();
    await _requestNotificationPermission();
    await _requestBatteryOptimizationExemption();
    _configureForegroundTask();

    if (userId != null && userId.isNotEmpty) {
      await DatabaseHelper.instance.setSetting('current_user_id', userId);
    }
    _isTracking = true;

    // Start flutter_foreground_task (dedicated Dart isolate)
    final result = await FlutterForegroundTask.startService(
      serviceId: 1001,
      serviceTypes: [ForegroundServiceTypes.location],
      notificationTitle: 'GPS Tracking Active',
      notificationText: 'Location tracking is running.',
      callback: startForegroundTask,
    );
    debugPrint('[LocationService] ForegroundTask start result: $result');

    // Immediate capture from main thread (after schedule check)
    if (userId != null && userId.isNotEmpty) {
      await persistCurrentLocation(userId: userId, ignoreThrottle: true);
    }

    // WorkManager fallback
    try {
      await Workmanager().registerPeriodicTask(
        geoTrackingUniqueName,
        geoTrackingTaskKey,
        frequency: geoCaptureInterval,
        existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
        inputData: userId != null ? {'user_id': userId} : null,
        constraints: Constraints(networkType: NetworkType.notRequired),
      );
      debugPrint('[LocationService] Registered WorkManager 15-min fallback task.');
    } catch (e) {
      debugPrint('[LocationService] Failed to register WorkManager task: $e');
    }

    return null; // success
  }

  // ── Ensure foreground service still running ────────────────────────────────

  Future<void> ensureForegroundTracking() async {
    if (!_isTracking) return;

    // Schedule gate before restarting
    final userId = await resolveUserId();
    if (userId == null) return;
    final allowed = await isWithinScheduleForUser(userId);
    if (!allowed) {
      debugPrint('[LocationService] ensureForegroundTracking: outside schedule, stopping.');
      await stopTracking();
      return;
    }

    final isRunning = await FlutterForegroundTask.isRunningService;
    if (!isRunning) {
      debugPrint('[LocationService] Foreground service stopped – restarting.');
      _configureForegroundTask();
      await FlutterForegroundTask.startService(
        serviceId: 1001,
        serviceTypes: [ForegroundServiceTypes.location],
        notificationTitle: 'GPS Tracking Active',
        notificationText: 'Location tracking is running.',
        callback: startForegroundTask,
      );
    }
  }

  // ── Stop tracking ──────────────────────────────────────────────────────────

  Future<void> stopTracking() async {
    _isTracking = false;
    await FlutterForegroundTask.stopService();
    try {
      await Workmanager().cancelByUniqueName(geoTrackingUniqueName);
      debugPrint('[LocationService] Cancelled WorkManager geo tracking task.');
    } catch (e) {
      debugPrint('[LocationService] Failed to cancel WorkManager task: $e');
    }
  }

  // ── Notification permission ────────────────────────────────────────────────

  Future<void> _requestNotificationPermission() async {
    try {
      final status = await Permission.notification.status;
      if (status.isDenied) await Permission.notification.request();
    } catch (e) {
      debugPrint('[LocationService] Notification permission request failed: $e');
    }
  }

  // ── Battery optimization exemption ────────────────────────────────────────

  Future<void> _requestBatteryOptimizationExemption() async {
    try {
      final isIgnoring = await FlutterForegroundTask.isIgnoringBatteryOptimizations;
      if (!isIgnoring) await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    } catch (e) {
      debugPrint('[LocationService] Battery optimization request failed: $e');
    }
  }

  // ── Capture current GPS position and store to SQLite ──────────────────────

  static Future<void> persistCurrentLocation({
    String? userId,
    bool ignoreThrottle = false,
  }) async {
    try {
      final resolvedUserId = await resolveUserId(userId);
      if (resolvedUserId == null || resolvedUserId.isEmpty) {
        debugPrint('[LocationService] Cannot capture location: no resolved userId.');
        return;
      }

      // ── STRICT SCHEDULE GATE ──────────────────────────────────────────────
      if (!await isWithinScheduleForUser(resolvedUserId)) {
        debugPrint('[LocationService] persistCurrentLocation: outside schedule – skipping.');
        return;
      }

      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        debugPrint('[LocationService] No location permission – skipping capture.');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 20),
        ),
      );

      await persistPosition(
        userId: resolvedUserId,
        latitude: position.latitude,
        longitude: position.longitude,
        timestamp: position.timestamp,
        ignoreThrottle: ignoreThrottle,
      );
    } catch (e) {
      debugPrint('[LocationService] Error capturing location: $e');
    }
  }

  // ── Store a position record in SQLite and trigger Firestore sync ───────────

  static Future<void> persistPosition({
    String? userId,
    required double latitude,
    required double longitude,
    DateTime? timestamp,
    bool ignoreThrottle = false,
  }) async {
    try {
      final resolvedUserId = await resolveUserId(userId);
      if (resolvedUserId == null || resolvedUserId.isEmpty) {
        debugPrint('[LocationService] Cannot persist position: no resolved userId.');
        return;
      }

      // ── STRICT SCHEDULE GATE ──────────────────────────────────────────────
      if (!await isWithinScheduleForUser(resolvedUserId)) {
        debugPrint('[LocationService] persistPosition: outside schedule – discarding.');
        return;
      }

      final captureTime = (timestamp ?? DateTime.now()).toUtc();

      // ── Duplicate / throttle prevention ──────────────────────────────────
      final lastRecord = await DatabaseHelper.instance.getLatestGeoLocation(resolvedUserId);
      if (lastRecord != null) {
        final timeDiff = captureTime.difference(lastRecord.timestamp.toUtc()).abs();

        if (timeDiff < const Duration(seconds: 30) &&
            (lastRecord.latitude - latitude).abs() < 0.00001 &&
            (lastRecord.longitude - longitude).abs() < 0.00001) {
          debugPrint('[LocationService] Skipping identical duplicate location.');
          return;
        }

        if (!ignoreThrottle && timeDiff < geoCaptureMinGap) {
          debugPrint('[LocationService] Throttle: last point was ${timeDiff.inMinutes} min ago.');
          return;
        }
      }

      // ── Save to SQLite ────────────────────────────────────────────────────
      final record = GeoLocationRecord(
        userId: resolvedUserId,
        syncId: _uuid.v4(),
        latitude: latitude,
        longitude: longitude,
        timestamp: captureTime,
        isSynced: false,
      );

      final rowId = await DatabaseHelper.instance.insertGeoLocation(record);
      debugPrint(
        '[LocationService] ✓ Saved GPS to SQLite (row: $rowId, '
        'lat: ${latitude.toStringAsFixed(6)}, lng: ${longitude.toStringAsFixed(6)})',
      );

      // ── Trigger Firestore sync ────────────────────────────────────────────
      await SyncService.instance.syncAll(resolvedUserId);
    } catch (e) {
      debugPrint('[LocationService] Error storing location: $e');
    }
  }
}
