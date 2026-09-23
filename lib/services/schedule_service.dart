import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/tracking_schedule.dart';
import 'database_helper.dart';

/// Service responsible for persisting and synchronising the user's
/// TrackingSchedule between local SQLite and Firebase Firestore.
class ScheduleService {
  static final ScheduleService instance = ScheduleService._init();
  ScheduleService._init();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final List<StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>> _listeners = [];
  String? _activeUserId;

  DocumentReference<Map<String, dynamic>> _scheduleRef(String userId) =>
      _firestore.collection('users').doc(userId).collection('settings').doc('tracking_schedule');

  DocumentReference<Map<String, dynamic>> _userRef(String userId) =>
      _firestore.collection('users').doc(userId);

  Map<String, dynamic>? _scheduleMapFromUser(Map<String, dynamic> userData) {
    final nested = userData['assigned_schedule'] ??
        userData['tracking_schedule'] ??
        userData['schedule'];
    if (nested is Map) return Map<String, dynamic>.from(nested);

    if (userData.containsKey('start_time') || userData.containsKey('end_time') ||
        userData.containsKey('start_hour') || userData.containsKey('end_hour')) {
      return userData;
    }
    return null;
  }

  Future<Map<String, dynamic>?> _loadAssignedSchedule(String userId) async {
    final userSnapshot = await _userRef(userId).get();
    final userData = userSnapshot.data();
    if (userData == null) return null;

    final direct = _scheduleMapFromUser(userData);
    if (direct != null) return direct;

    final groupId = (userData['group_id'] ?? userData['group'] ?? userData['user_group'])
        ?.toString()
        .trim();
    if (groupId == null || groupId.isEmpty) return null;

    final groupSnapshot = await _firestore.collection('groups').doc(groupId).get();
    final groupData = groupSnapshot.data();
    final scheduleId = groupData?['default_schedule_id']?.toString().trim();
    if (scheduleId == null || scheduleId.isEmpty) return null;

    final scheduleSnapshot = await _firestore.collection('schedules').doc(scheduleId).get();
    return scheduleSnapshot.data();
  }

  Future<void> _emitAssignedSchedule(
    String userId,
    void Function(TrackingSchedule schedule) onChanged,
  ) async {
    try {
      final data = await _loadAssignedSchedule(userId);
      if (data == null) {
        debugPrint('[ScheduleService] No assigned schedule found for $userId.');
        return;
      }
      final schedule = TrackingSchedule.fromFirestore(data);
      await DatabaseHelper.instance.saveTrackingSchedule(userId, schedule);
      debugPrint('[ScheduleService] Loaded assigned schedule for $userId -> ${schedule.formattedTimeRange}');
      onChanged(schedule);
    } catch (e) {
      debugPrint('[ScheduleService] Assigned schedule lookup failed: $e');
    }
  }

  Future<void> listenForScheduleUpdates(
    String userId, {
    required void Function(TrackingSchedule schedule) onChanged,
  }) async {
    if (_activeUserId == userId && _listeners.isNotEmpty) {
      debugPrint('[ScheduleService] Reusing existing Firestore listener for $userId');
      return;
    }

    stopListening();
    _activeUserId = userId;

    _listeners.add(_userRef(userId).snapshots().listen((_) {
      _emitAssignedSchedule(userId, onChanged);
    }, onError: (Object error) {
      debugPrint('[ScheduleService] Firestore user listener error: $error');
    }));

    _emitAssignedSchedule(userId, onChanged);

    try {
      final userSnapshot = await _userRef(userId).get();
      final userData = userSnapshot.data();
      final groupId = (userData?['group_id'] ?? userData?['group'] ?? userData?['user_group'])
          ?.toString()
          .trim();
      final groupSnapshot = groupId == null || groupId.isEmpty
          ? null
          : await _firestore.collection('groups').doc(groupId).get();
      final scheduleId = groupSnapshot?.data()?['default_schedule_id']?.toString().trim();
      if (scheduleId != null && scheduleId.isNotEmpty) {
        _listeners.add(_firestore.collection('schedules').doc(scheduleId).snapshots().listen((snapshot) {
          final data = snapshot.data();
          if (data != null) {
            final schedule = TrackingSchedule.fromFirestore(data);
            DatabaseHelper.instance.saveTrackingSchedule(userId, schedule);
            onChanged(schedule);
          }
        }, onError: (Object error) {
          debugPrint('[ScheduleService] Firestore schedule listener error: $error');
        }));
      }
    } catch (e) {
      debugPrint('[ScheduleService] Could not attach assigned schedule listener: $e');
    }
  }

  void stopListening() {
    for (final listener in _listeners) {
      listener.cancel();
    }
    _listeners.clear();
    _activeUserId = null;
  }

  /// Load schedule from the admin-assigned user profile first, then the legacy
  /// per-user settings document, and finally fall back to SQLite.
  Future<TrackingSchedule> loadSchedule(String userId) async {
    TrackingSchedule? remote;
    try {
      final userDoc = await _userRef(userId).get(const GetOptions(source: Source.serverAndCache));
      final userData = userDoc.data();
      if (userData != null) {
        final scheduleMap = _scheduleMapFromUser(userData);
        if (scheduleMap != null) {
          remote = TrackingSchedule.fromFirestore(scheduleMap);
        } else {
          final assigned = await _loadAssignedSchedule(userId);
          if (assigned != null) remote = TrackingSchedule.fromFirestore(assigned);
        }
      }

      if (remote == null) {
        final settingsDoc = await _scheduleRef(userId).get(const GetOptions(source: Source.serverAndCache));
        if (settingsDoc.exists && settingsDoc.data() != null) {
          remote = TrackingSchedule.fromFirestore(settingsDoc.data()!);
        }
      }

      if (remote != null) {
        await DatabaseHelper.instance.saveTrackingSchedule(userId, remote);
        debugPrint('[ScheduleService] Loaded schedule from Firestore for $userId');
        return remote;
      }
    } catch (e) {
      debugPrint('[ScheduleService] Firestore load failed (using local): $e');
    }

    final local = await DatabaseHelper.instance.getTrackingSchedule(userId);
    debugPrint('[ScheduleService] Loaded schedule from SQLite for $userId');
    return local;
  }

  /// Save schedule: persists to SQLite immediately, then syncs to Firestore.
  Future<void> saveSchedule(String userId, TrackingSchedule schedule) async {
    final updated = schedule.copyWith(lastUpdated: DateTime.now().toUtc());

    await DatabaseHelper.instance.saveTrackingSchedule(userId, updated);
    debugPrint('[ScheduleService] Schedule saved locally for $userId');

    try {
      await _userRef(userId).set(
        {'assigned_schedule': updated.toFirestore()},
        SetOptions(merge: true),
      );
      await _scheduleRef(userId).set(
        updated.toFirestore(),
        SetOptions(merge: true),
      );
      debugPrint('[ScheduleService] Schedule synced to Firestore for $userId');
    } catch (e) {
      debugPrint('[ScheduleService] Firestore sync failed (saved locally only): $e');
    }
  }
}
