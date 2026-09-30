import 'dart:async';

import 'package:flutter/foundation.dart';
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
import 'schedule_service.dart';
import 'sync_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────

const String geoTrackingTaskKey = "com.ebtfusion.expensetracker.geo_tracking";
const String geoScheduleStartTaskKey =
    "com.ebtfusion.expensetracker.schedule_start";
const String geoTrackingUniqueName = "periodic-geo-tracking";
const String geoScheduleStartUniqueName = "schedule-next-start";
const Duration geoCaptureInterval = Duration(minutes: 15);
const Duration geoCaptureMinGap = Duration(minutes: 14);
const Duration _scheduleStartMinimumDelay = Duration(minutes: 1);
const Duration _scheduleStartMaximumDelay = Duration(days: 7);

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

Future<bool> isWithinScheduleForUser(
  String userId, [
  DateTime? checkTime,
]) async {
  if (!await _isScheduledTrackingArmed()) return false;
  final accountStatus = await ScheduleService.instance.cachedAccountStatus(
    userId,
  );
  if (accountStatus == null ||
      !const {
        'active',
        'enabled',
        'approved',
      }.contains(accountStatus.trim().toLowerCase())) {
    return false;
  }
  final schedule =
      await _loadSchedule(userId) ?? TrackingSchedule.defaultSchedule();
  return schedule.isWithinAllowedSchedule(checkTime);
}

Future<bool> _isScheduledTrackingArmed() async {
  final pref = await DatabaseHelper.instance.getSetting('tracking_enabled');
  return pref == 'true';
}

Future<void> _logScheduleContext(
  String userId,
  TrackingSchedule schedule,
) async {
  final groupName = await DatabaseHelper.instance.getSetting(
    'schedule_group_name_$userId',
  );
  final groupId = await DatabaseHelper.instance.getSetting(
    'schedule_group_id_$userId',
  );
  schedule.debugLogSchedule(userId: userId, groupId: groupName ?? groupId);
}

Future<void> scheduleNextAutomaticStart(
  String userId, {
  bool replaceExisting = false,
}) async {
  final schedule = await _loadSchedule(userId);
  if (schedule == null || !schedule.isEnabled || !schedule.isValid) {
    debugPrint(
      '[ScheduleTracking] Cannot schedule next start for $userId (missing/disabled schedule).',
    );
    return;
  }

  await _logScheduleContext(userId, schedule);

  final localNow = TrackingSchedule.localNow();
  final nextStartLocal = schedule.nextScheduleWindowStart(localNow);
  if (nextStartLocal == null) {
    debugPrint('[ScheduleTracking] No upcoming start found for $userId.');
    return;
  }

  final nextStartUtc = TrackingSchedule.localWallClockToUtc(nextStartLocal);
  var delay = nextStartUtc.difference(DateTime.now().toUtc());
  if (delay.isNegative) delay = _scheduleStartMinimumDelay;
  if (delay < _scheduleStartMinimumDelay) delay = _scheduleStartMinimumDelay;
  if (delay > _scheduleStartMaximumDelay) delay = _scheduleStartMaximumDelay;

  final nextStopLocal = schedule.scheduleWindowEndForStart(nextStartLocal);
  debugPrint(
    '[ScheduleTracking] Calculated next local start: $nextStartLocal '
    'stop: $nextStopLocal delay: ${delay.inMinutes} min for $userId',
  );

  try {
    await Workmanager().registerOneOffTask(
      geoScheduleStartUniqueName,
      geoScheduleStartTaskKey,
      initialDelay: delay,
      existingWorkPolicy: replaceExisting
          ? ExistingWorkPolicy.replace
          : ExistingWorkPolicy.keep,
      inputData: {'user_id': userId},
      constraints: Constraints(networkType: NetworkType.notRequired),
    );
    debugPrint(
      '[ScheduleTracking] Registered WorkManager one-off for next Firestore start.',
    );
  } catch (e) {
    debugPrint('[ScheduleTracking] Failed to register next-start task: $e');
  }
}

Future<void> _registerPeriodicScheduleMonitor(String userId) async {
  try {
    await Workmanager().registerPeriodicTask(
      geoTrackingUniqueName,
      geoTrackingTaskKey,
      frequency: geoCaptureInterval,
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      inputData: {'user_id': userId},
      constraints: Constraints(networkType: NetworkType.notRequired),
    );
    debugPrint(
      '[ScheduleTracking] Registered 15-min WorkManager monitor for $userId.',
    );
  } catch (e) {
    debugPrint('[ScheduleTracking] Failed to register periodic monitor: $e');
  }
}

Future<void> _cancelScheduledWork() async {
  try {
    await Workmanager().cancelByUniqueName(geoTrackingUniqueName);
    await Workmanager().cancelByUniqueName(geoScheduleStartUniqueName);
    debugPrint('[ScheduleTracking] Cancelled background schedule tasks.');
  } catch (e) {
    debugPrint('[ScheduleTracking] Failed to cancel background tasks: $e');
  }
}

Future<void> _startForegroundService(String userId) async {
  if (await FlutterForegroundTask.isRunningService) return;
  LocationService.configureForegroundTask();
  final result = await FlutterForegroundTask.startService(
    serviceId: 1001,
    serviceTypes: [ForegroundServiceTypes.location],
    notificationTitle: 'GPS Tracking Active',
    notificationText: 'Location tracking is running.',
    callback: startForegroundTask,
  );
  debugPrint('[GPS] Scheduled tracking started for $userId result=$result');
}

Future<void> syncScheduledTracking(String userId) async {
  if (userId.isEmpty) return;

  if (!await _isScheduledTrackingArmed()) {
    debugPrint(
      '[ScheduleTracking] Tracking not armed; skipping sync for $userId.',
    );
    return;
  }

  await LocationService.instance.initializeBackgroundService();

  // Keep monitoring even while disabled so an Admin change is picked up later.
  await _registerPeriodicScheduleMonitor(userId);
  final scheduleChanged = await ScheduleService.instance.syncAssignedSchedule(
    userId,
  );
  final schedule =
      await _loadSchedule(userId) ?? TrackingSchedule.defaultSchedule();
  final accountStatus = await ScheduleService.instance.cachedAccountStatus(
    userId,
  );
  if (accountStatus == null ||
      !const {
        'active',
        'enabled',
        'approved',
      }.contains(accountStatus.trim().toLowerCase())) {
    debugPrint(
      '[GPS] Tracking blocked because the cached account is inactive.',
    );
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
    return;
  }

  await _logScheduleContext(userId, schedule);

  if (!schedule.isEnabled || !schedule.isValid) {
    debugPrint(
      '[ScheduleTracking] Schedule disabled/invalid — stopping GPS for $userId.',
    );
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
    return;
  }

  final within = schedule.isWithinAllowedSchedule();
  final foregroundRunning = await FlutterForegroundTask.isRunningService;

  if (within) {
    debugPrint(
      '[GPS] Scheduled tracking start/reconcile: inside current group schedule.',
    );
    if (!foregroundRunning) {
      await _startForegroundService(userId);
    }
    await SyncService.instance.syncAll(userId);
  } else {
    debugPrint(
      '[GPS] Scheduled tracking stopped/reconciled: outside group schedule.',
    );
    debugPrint('[SCHEDULE] Waiting for next scheduled window.');
    await scheduleNextAutomaticStart(userId, replaceExisting: scheduleChanged);
    if (foregroundRunning) {
      await FlutterForegroundTask.stopService();
    }
  }
}

Future<void> stopForegroundForScheduleEnd(String userId) async {
  debugPrint(
    '[ScheduleTracking] Schedule end reached — stopping GPS collection only for $userId.',
  );
  if (await _isScheduledTrackingArmed()) {
    await scheduleNextAutomaticStart(userId);
    await _registerPeriodicScheduleMonitor(userId);
  }
  await FlutterForegroundTask.stopService();
}

// ─────────────────────────────────────────────────────────────────────────────
// WorkManager fallback (handles deep background, battery saver, post-reboot)
// ─────────────────────────────────────────────────────────────────────────────

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    debugPrint("[Workmanager] Background execution started: $taskName");
    try {
      await _ensureFirebaseInitialized();

      if (taskName == geoTrackingTaskKey ||
          taskName == geoScheduleStartTaskKey ||
          taskName == Workmanager.iOSBackgroundTask) {
        final userId =
            inputData?['user_id'] as String? ??
            await LocationService.resolveUserId();
        if (userId == null || userId.isEmpty) {
          debugPrint("[Workmanager] No user ID available; completing task.");
          return true;
        }

        debugPrint(
          "[Workmanager] Running schedule sync task=$taskName userId=$userId",
        );
        await syncScheduledTracking(userId);
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
  Timer? _endCheckTimer;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[ForegroundTask] Task isolate started with starter: $starter');
    await _ensureFirebaseInitialized();

    final userId = await LocationService.resolveUserId();
    debugPrint('[ForegroundTask] Resolved userId onStart: $userId');
    if (userId != null && userId.isNotEmpty) {
      // Boot and service restarts also reconcile the group schedule before
      // allowing a location capture.
      await ScheduleService.instance.syncAssignedSchedule(userId);
    }

    // ── STRICT SCHEDULE GATE ──────────────────────────────────────────────
    if (userId == null || !await isWithinScheduleForUser(userId)) {
      debugPrint(
        '[ForegroundTask] Outside schedule at start – stopping service.',
      );
      if (userId != null) {
        await stopForegroundForScheduleEnd(userId);
      } else {
        await FlutterForegroundTask.stopService();
      }
      return;
    }

    // Capture immediately on confirmed schedule start
    await LocationService.persistCurrentLocation(
      userId: userId,
      ignoreThrottle: false,
    );

    _scheduleEndCheck(userId);
  }

  void _scheduleEndCheck(String userId) {
    // Check every minute whether the schedule has ended so we stop promptly
    _endCheckTimer?.cancel();
    _endCheckTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      final uId = await LocationService.resolveUserId() ?? userId;
      if (!await isWithinScheduleForUser(uId)) {
        debugPrint(
          '[ForegroundTask] Schedule ended (end-check timer) – stopping service.',
        );
        _endCheckTimer?.cancel();
        await stopForegroundForScheduleEnd(uId);
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
      debugPrint(
        '[ForegroundTask] onRepeatEvent outside schedule – stopping service.',
      );
      await stopForegroundForScheduleEnd(uId);
      return;
    }

    await LocationService.persistCurrentLocation(
      userId: uId,
      ignoreThrottle: false,
    );
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint(
      '[ForegroundTask] Task isolate destroyed (isTimeout: $isTimeout).',
    );
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
    if (explicitUserId != null && explicitUserId.isNotEmpty)
      return explicitUserId;
    final storedUid = await DatabaseHelper.instance.getSetting(
      'current_user_id',
    );
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

  static void configureForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'gps_tracking_channel',
        channelName: 'GPS Tracking',
        channelDescription:
            'Tracks your location during your configured schedule.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        enableVibration: false,
        playSound: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(
          geoCaptureInterval.inMilliseconds,
        ),
        autoRunOnBoot: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  // ── Permission check ───────────────────────────────────────────────────────

  Future<bool> checkPermission() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always;
  }

  // ── Start tracking ─────────────────────────────────────────────────────────
  // Returns null on success, or a user-facing error string.

  /// Arms background schedule monitoring and starts GPS when inside the Firestore window.
  /// Returns a user-facing message when the schedule is disabled/invalid, otherwise null.
  Future<String?> activateScheduledTracking([String? explicitUserId]) =>
      _activateScheduledTracking(explicitUserId);

  Future<String?> _activateScheduledTracking(
    String? explicitUserId, {
    bool requestSystemPrompts = false,
  }) async {
    final userId =
        explicitUserId ??
        await DatabaseHelper.instance.getSetting('current_user_id');

    if (userId == null || userId.isEmpty) {
      return 'No logged-in user found for GPS tracking.';
    }

    await initializeBackgroundService();
    if (requestSystemPrompts) {
      await _requestNotificationPermission();
      await _requestBatteryOptimizationExemption();
    }

    await DatabaseHelper.instance.setSetting('current_user_id', userId);
    await DatabaseHelper.instance.setSetting('tracking_enabled', 'true');
    _isTracking = true;

    await syncScheduledTracking(userId);

    return null;
  }

  Future<String?> startTracking([String? explicitUserId]) async {
    return _activateScheduledTracking(
      explicitUserId,
      requestSystemPrompts: true,
    );
  }

  // ── Ensure foreground service still running ────────────────────────────────

  Future<void> ensureForegroundTracking() async {
    if (!_isTracking && !await _isScheduledTrackingArmed()) return;

    final userId = await resolveUserId();
    if (userId == null) return;
    await syncScheduledTracking(userId);
  }

  // ── Stop tracking ──────────────────────────────────────────────────────────

  /// User-initiated stop — disables automatic restarts until tracking is enabled again.
  Future<void> stopTracking() async {
    _isTracking = false;
    await DatabaseHelper.instance.setSetting('tracking_enabled', 'false');
    debugPrint(
      '[ScheduleTracking] GPS stopped reason: user disabled tracking.',
    );
    await FlutterForegroundTask.stopService();
    await _cancelScheduledWork();
  }

  /// Stops collection at schedule end but keeps automatic next-start armed.
  Future<void> stopForScheduleBoundary(String userId) async {
    await stopForegroundForScheduleEnd(userId);
  }

  // ── Notification permission ────────────────────────────────────────────────

  Future<void> _requestNotificationPermission() async {
    try {
      final status = await Permission.notification.status;
      if (status.isDenied) await Permission.notification.request();
    } catch (e) {
      debugPrint(
        '[LocationService] Notification permission request failed: $e',
      );
    }
  }

  // ── Battery optimization exemption ────────────────────────────────────────

  Future<void> _requestBatteryOptimizationExemption() async {
    try {
      final isIgnoring =
          await FlutterForegroundTask.isIgnoringBatteryOptimizations;
      if (!isIgnoring)
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
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
        debugPrint(
          '[LocationService] Cannot capture location: no resolved userId.',
        );
        return;
      }

      // ── STRICT SCHEDULE GATE ──────────────────────────────────────────────
      if (!await isWithinScheduleForUser(resolvedUserId)) {
        debugPrint(
          '[LocationService] persistCurrentLocation: outside schedule – skipping.',
        );
        return;
      }

      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always) {
        debugPrint(
          '[LocationService] No location permission – skipping capture.',
        );
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
        debugPrint(
          '[LocationService] Cannot persist position: no resolved userId.',
        );
        return;
      }

      // ── STRICT SCHEDULE GATE ──────────────────────────────────────────────
      if (!await isWithinScheduleForUser(resolvedUserId)) {
        debugPrint(
          '[LocationService] persistPosition: outside schedule – discarding.',
        );
        return;
      }

      final captureTime = (timestamp ?? DateTime.now()).toUtc();

      // ── Duplicate / throttle prevention ──────────────────────────────────
      final lastRecord = await DatabaseHelper.instance.getLatestGeoLocation(
        resolvedUserId,
      );
      if (lastRecord != null) {
        final timeDiff = captureTime
            .difference(lastRecord.timestamp.toUtc())
            .abs();

        if (timeDiff < const Duration(seconds: 30) &&
            (lastRecord.latitude - latitude).abs() < 0.00001 &&
            (lastRecord.longitude - longitude).abs() < 0.00001) {
          debugPrint(
            '[LocationService] Skipping identical duplicate location.',
          );
          return;
        }

        if (!ignoreThrottle && timeDiff < geoCaptureMinGap) {
          debugPrint(
            '[LocationService] Throttle: last point was ${timeDiff.inMinutes} min ago.',
          );
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
