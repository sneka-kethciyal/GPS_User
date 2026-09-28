import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

import '../models/geo_location.dart';
import '../models/tracking_schedule.dart';
import '../services/database_helper.dart';
import '../services/location_service.dart';
import '../services/permission_service.dart';
import '../services/schedule_service.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';

class LocationProvider extends ChangeNotifier with WidgetsBindingObserver {
  final LocationService _service = LocationService.instance;
  final PermissionService _permissionService = PermissionService.instance;

  bool _isTrackingEnabled = false;
  bool _hasPermission = false;
  bool _hasShownDisclosure = false;
  GeoLocationRecord? _latestLocation;
  int _unsyncedLocationCount = 0;
  bool _isCapturingNow = false;
  TrackingSchedule _schedule = TrackingSchedule.defaultSchedule();
  bool _scheduleLoaded = false;
  bool? _lastReportedTrackingEnabled;
  bool? _lastReportedActive;
  final List<String> _trackingNotifications = [];

  bool get isTrackingEnabled => _isTrackingEnabled;
  bool get hasPermission => _hasPermission;
  bool get hasShownDisclosure => _hasShownDisclosure;
  GeoLocationRecord? get latestLocation => _latestLocation;
  int get unsyncedLocationCount => _unsyncedLocationCount;
  bool get isCapturingNow => _isCapturingNow;
  TrackingSchedule get schedule => _schedule;
  bool get scheduleLoaded => _scheduleLoaded;

  /// Whether tracking is active AND within the schedule right now.
  bool get isActivelyTracking =>
      _isTrackingEnabled && _schedule.isWithinAllowedSchedule();

  /// Current validation result for the live schedule.
  ScheduleValidationResult get scheduleStatus => _schedule.validateSchedule();

  String? consumeTrackingNotification() {
    if (_trackingNotifications.isEmpty) return null;
    return _trackingNotifications.removeAt(0);
  }

  LocationProvider() {
    WidgetsBinding.instance.addObserver(this);
    _checkInitialStatus();
  }

  Future<void> initializeForCurrentUser() async {
    final userId = await LocationService.resolveUserId();
    if (userId == null || userId.isEmpty) {
      return;
    }

    // Re-check permissions and bind the background service to the current login.
    _hasShownDisclosure = false;
    _isTrackingEnabled = false;
    await _service.stopTracking();
    await _checkInitialStatus(userId);
  }

  Future<void> requestBackgroundTrackingPermission(BuildContext context) async {
    if (!context.mounted) return;

    _hasPermission = await _service.checkPermission();
    if (_hasShownDisclosure) return;

    if (!_hasPermission) {
      await enableTrackingWithDisclosure(context);
    } else if (!_isTrackingEnabled) {
      final userId = await LocationService.resolveUserId();
      if (userId == null || userId.isEmpty) return;

      _isTrackingEnabled = true;
      await DatabaseHelper.instance.setSetting('tracking_enabled', 'true');
      final error = await _service.startTracking(userId);
      if (error != null) {
        _enqueueTrackingNotification('Tracking failed: $error');
      }
    }

    _reportTrackingState();
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      final userId = await LocationService.resolveUserId();
      if (userId != null && userId.isNotEmpty) {
        await loadSchedule(userId);
      }
      if (_isTrackingEnabled) {
        _service.ensureForegroundTracking();
        SyncService.instance.syncAll();
      }
      await refreshLocationStatus();
    }
  }

  // ── Schedule CRUD ──────────────────────────────────────────────────────────

  Future<void> loadSchedule([String? userId]) async {
    final uid = userId ?? await LocationService.resolveUserId();
    if (uid == null || uid.isEmpty) return;

    _schedule = await ScheduleService.instance.loadSchedule(uid);
    _scheduleLoaded = true;
    debugPrint(
      '[LocationProvider] Loaded schedule for $uid -> ${_schedule.formattedDaysSummary} ${_schedule.formattedTimeRange}',
    );
    notifyListeners();

    ScheduleService.instance.listenForScheduleUpdates(
      uid,
      onChanged: (updatedSchedule) async {
        _schedule = updatedSchedule;
        _scheduleLoaded = true;
        debugPrint(
          '[LocationProvider] Firestore schedule update received for $uid: ${updatedSchedule.formattedDaysSummary} ${updatedSchedule.formattedTimeRange}',
        );
        notifyListeners();

        final nowWithinSchedule = updatedSchedule.isWithinAllowedSchedule();
        debugPrint(
          '[LocationProvider] Current time in schedule for $uid: $nowWithinSchedule',
        );

        if (_isTrackingEnabled) {
          if (nowWithinSchedule) {
            final error = await _service.startTracking(uid);
            if (error != null) {
              debugPrint(
                '[LocationProvider] Re-start tracking after Firestore update denied: $error',
              );
            }
          } else {
            await _service.stopTracking();
            debugPrint(
              '[LocationProvider] Tracking stopped because schedule update moved outside allowed window.',
            );
          }
        }
      },
    );
  }

  Future<void> saveSchedule(
    TrackingSchedule newSchedule, [
    String? userId,
  ]) async {
    final uid =
        userId ??
        FirebaseAuth.instance.currentUser?.uid ??
        await DatabaseHelper.instance.getSetting('current_user_id');
    if (uid == null || uid.isEmpty) return;
    await ScheduleService.instance.saveSchedule(uid, newSchedule);
    _schedule = newSchedule;
    notifyListeners();
  }

  // ── GPS data ───────────────────────────────────────────────────────────────

  Future<void> refreshLocationStatus() async {
    final userId = await LocationService.resolveUserId();
    if (userId != null && userId.isNotEmpty) {
      _latestLocation = await DatabaseHelper.instance.getLatestGeoLocation(
        userId,
      );
      final unsynced = await DatabaseHelper.instance.getUnsyncedGeoLocations(
        userId,
      );
      _unsyncedLocationCount = unsynced.length;
      notifyListeners();
    }
  }

  Future<void> captureNow() async {
    if (_isCapturingNow) return;

    // Schedule gate: refuse capture outside schedule
    if (!_schedule.isWithinAllowedSchedule()) return;

    _isCapturingNow = true;
    notifyListeners();

    try {
      final userId = await LocationService.resolveUserId();
      if (userId != null && userId.isNotEmpty) {
        await LocationService.persistCurrentLocation(
          userId: userId,
          ignoreThrottle: true,
        );
        await refreshLocationStatus();
      }
    } finally {
      _isCapturingNow = false;
      notifyListeners();
    }
  }

  Future<void> _checkInitialStatus([String? requestedUserId]) async {
    final userId = requestedUserId ?? await LocationService.resolveUserId();
    if (userId == null || userId.isEmpty) return;

    await _permissionService.requestNotificationPermission();
    final trackingPref = await DatabaseHelper.instance.getSetting(
      'tracking_enabled',
    );
    final isTrackingSaved = trackingPref == 'true';
    _hasPermission = await _service.checkPermission();

    // Load schedule first so gates are live immediately
    await loadSchedule(userId);

    if (_hasPermission && isTrackingSaved) {
      _isTrackingEnabled = true;
      // startTracking internally checks the schedule
      final error = await _service.startTracking(userId);
      if (error != null) {
        // Outside schedule at boot – keep toggle ON but service dormant
        debugPrint('[LocationProvider] Startup outside schedule: $error');
        _enqueueTrackingNotification('Tracking stopped: $error');
      }
    } else {
      _isTrackingEnabled = false;
      await _service.stopTracking();
    }

    if (!_hasPermission) {
      _enqueueTrackingNotification('Location permission denied');
    } else if (!await Geolocator.isLocationServiceEnabled()) {
      _enqueueTrackingNotification('Location services disabled');
    }
    _reportTrackingState();
    await refreshLocationStatus();
    notifyListeners();
  }

  void _enqueueTrackingNotification(String message) {
    if (_trackingNotifications.isNotEmpty &&
        _trackingNotifications.last == message) {
      return;
    }
    _trackingNotifications.add(message);
    notifyListeners();
  }

  void _reportTrackingState() {
    if (_lastReportedTrackingEnabled != _isTrackingEnabled) {
      _lastReportedTrackingEnabled = _isTrackingEnabled;
      _enqueueTrackingNotification(
        _isTrackingEnabled ? 'GPS tracking enabled' : 'GPS tracking disabled',
      );
    }

    final isActive = isActivelyTracking;
    if (_lastReportedActive != null && _lastReportedActive != isActive) {
      _enqueueTrackingNotification(
        isActive ? 'Tracking started' : 'Tracking stopped',
      );
    }
    _lastReportedActive = isActive;
  }

  // ── Enable tracking with disclosure ───────────────────────────────────────

  /// Returns null on success, or an error string if refused (e.g. outside schedule).
  Future<String?> enableTrackingWithDisclosure(BuildContext context) async {
    // Show clear disclosure dialog required by Google Play & app specifications
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardBackground,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.pastelBlueLight,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.location_on_rounded,
                color: AppTheme.pastelBlue,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Location Disclosure',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'EBT Fusion Infotech Expense Tracker collects background location data approximately every 15 minutes to log verified regional expense context.',
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: AppTheme.textSecondary,
              ),
            ),
            SizedBox(height: 14),
            Text(
              '• Data is saved locally in SQLite when offline.\n• Data is securely synchronized to the company Firestore database.\n• Location is only collected during your configured schedule.\n• No map or personal route history is shown inside the application.',
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: AppTheme.textMuted,
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.textSecondary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Decline'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.pastelLavender,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            child: const Text('Accept & Allow'),
          ),
        ],
      ),
    );

    if (confirmed != true) return null;

    _hasShownDisclosure = true;
    await _permissionService.requestNotificationPermission();
    final permissionStatus = await _permissionService
        .requestBackgroundLocation();

    if (permissionStatus == BackgroundLocationPermissionStatus.granted) {
      _hasPermission = true;
      _isTrackingEnabled = true;
      await DatabaseHelper.instance.setSetting('tracking_enabled', 'true');
      final userId = FirebaseAuth.instance.currentUser?.uid;

      // ── STRICT SCHEDULE GATE ──────────────────────────────────────────────
      final error = await _service.startTracking(userId);
      if (error != null) {
        // Service refused to start outside schedule – toggle stays enabled
        // but inform the caller so UI can show the schedule message
        await refreshLocationStatus();
        _enqueueTrackingNotification('Tracking failed: $error');
        notifyListeners();
        return error;
      }

      await refreshLocationStatus();
      notifyListeners();
      return null; // success
    }

    _hasPermission = false;
    _isTrackingEnabled = false;
    _enqueueTrackingNotification('Location permission denied');

    if (!context.mounted) {
      notifyListeners();
      return null;
    }

    if (permissionStatus ==
        BackgroundLocationPermissionStatus.permanentlyDenied) {
      await _permissionService.openSettings();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Location permission is blocked. Enable Allow all the time in app settings to start tracking.',
            ),
          ),
        );
      }
    } else {
      await _showPermissionError(context, permissionStatus);
    }

    notifyListeners();
    return null;
  }

  Future<void> _showPermissionError(
    BuildContext context,
    BackgroundLocationPermissionStatus status,
  ) async {
    if (!context.mounted) return;

    final needsSettings =
        status == BackgroundLocationPermissionStatus.needsSettings;
    final retry = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          needsSettings
              ? 'Background location required'
              : 'Location permission denied',
        ),
        content: Text(
          needsSettings
              ? 'Android did not show Allow all the time. Background tracking requires Settings > App > Permissions > Location > Allow all the time.'
              : 'Location permission is required to start tracking. Please allow location access and try again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          if (needsSettings)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Open Settings'),
            )
          else
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Try again'),
            ),
        ],
      ),
    );

    if (retry == true && needsSettings) {
      await _permissionService.openSettings();
    } else if (retry == true && context.mounted) {
      await enableTrackingWithDisclosure(context);
    }
  }

  // ── Toggle ─────────────────────────────────────────────────────────────────

  /// Returns null on success, or a schedule-block message to show to the user.
  Future<String?> toggleTracking(BuildContext context, bool enable) async {
    if (enable) {
      return enableTrackingWithDisclosure(context);
    } else {
      await DatabaseHelper.instance.setSetting('tracking_enabled', 'false');
      await _service.stopTracking();
      _isTrackingEnabled = false;
      _reportTrackingState();
      notifyListeners();
      return null;
    }
  }
}
