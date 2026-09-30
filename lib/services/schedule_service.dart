import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/tracking_schedule.dart';
import 'database_helper.dart';

/// Resolves a managed user's group schedule and keeps the last valid copy in
/// app_settings (the existing SQLite key/value table).
class ScheduleService {
  static final ScheduleService instance = ScheduleService._init();
  ScheduleService._init();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final List<StreamSubscription<dynamic>> _listeners = [];
  String? _activeUserId;

  String _metaKey(String key, String userId) => 'schedule_${key}_$userId';

  Future<QuerySnapshot<Map<String, dynamic>>?> _queryManagedUser(
    String userId, {
    Source source = Source.server,
  }) async {
    final username = await DatabaseHelper.instance.getSetting(
      'current_username',
    );
    if (username == null || username.trim().isEmpty) return null;
    final query = _firestore
        .collection('users')
        .where('username', isEqualTo: username.trim().toLowerCase())
        .limit(1);
    final result = await query.get(GetOptions(source: source));
    if (result.docs.isEmpty || result.docs.first.id != userId) return null;
    return result;
  }

  Future<String?> cachedAccountStatus(String userId) =>
      DatabaseHelper.instance.getSetting(_metaKey('account_status', userId));

  Future<TrackingSchedule> loadCachedSchedule(String userId) async =>
      DatabaseHelper.instance.getTrackingSchedule(userId);

  Future<bool> _clearMissingAssignment(
    String userId, {
    String groupId = '',
    String groupName = '',
    String scheduleId = '',
  }) async {
    final db = DatabaseHelper.instance;
    final local = await db.getTrackingSchedule(userId);
    final changed = local.isEnabled || local.isValid;
    if (changed) {
      await db.saveTrackingSchedule(userId, TrackingSchedule.defaultSchedule());
    }
    await db.setSetting(_metaKey('group_id', userId), groupId);
    await db.setSetting(_metaKey('group_name', userId), groupName);
    await db.setSetting(_metaKey('schedule_id', userId), scheduleId);
    await db.setSetting(
      _metaKey('last_schedule_sync_at', userId),
      DateTime.now().toUtc().toIso8601String(),
    );
    return changed;
  }

  /// Reads the managed user and assigned group's existing schedule documents
  /// from the Firestore server. A failed server read leaves SQLite untouched.
  Future<bool> syncAssignedSchedule(String userId) async {
    if (userId.isEmpty) return false;
    debugPrint('[SCHEDULE SYNC] Checking Firestore schedule for $userId');

    try {
      final userSnapshot = await _queryManagedUser(userId);
      final userData = userSnapshot?.docs.first.data();
      if (userData == null) return false;

      final statusValue =
          userData['account_status'] ??
          userData['status'] ??
          userData['accountStatus'];
      final accountStatus = statusValue is bool
          ? (statusValue ? 'active' : 'inactive')
          : (statusValue ?? '').toString().trim().toLowerCase();
      await DatabaseHelper.instance.setSetting(
        _metaKey('account_status', userId),
        accountStatus,
      );

      final groupValue =
          userData['group_id'] ??
          userData['groupId'] ??
          userData['group'] ??
          userData['user_group'] ??
          userData['group_name'];
      final groupId = groupValue is Map
          ? (groupValue['id'] ?? groupValue['group_id'] ?? groupValue['name'])
                ?.toString()
                .trim()
          : groupValue?.toString().trim();
      if (groupId == null || groupId.isEmpty) {
        debugPrint('[SCHEDULE SYNC] No assigned group for $userId');
        return await _clearMissingAssignment(userId);
      }

      final groupSnapshot = await _firestore
          .collection('groups')
          .doc(groupId)
          .get(const GetOptions(source: Source.server));
      final groupData = groupSnapshot.data();
      if (groupData == null) {
        debugPrint('[SCHEDULE SYNC] Assigned group $groupId was not found');
        return await _clearMissingAssignment(userId, groupId: groupId);
      }

      final groupName =
          (groupData['name'] ??
                  groupData['group_name'] ??
                  (groupValue is Map ? groupValue['name'] : null) ??
                  groupId)
              .toString();
      final scheduleId =
          (groupData['default_schedule_id'] ??
                  groupData['schedule_id'] ??
                  groupData['tracking_schedule_id'])
              ?.toString()
              .trim();

      Map<String, dynamic>? scheduleData;
      if (scheduleId != null && scheduleId.isNotEmpty) {
        final scheduleSnapshot = await _firestore
            .collection('schedules')
            .doc(scheduleId)
            .get(const GetOptions(source: Source.server));
        scheduleData = scheduleSnapshot.data();
      }

      // Some existing group documents carry the schedule fields directly.
      scheduleData ??= _embeddedSchedule(groupData);
      if (scheduleData == null) {
        debugPrint('[SCHEDULE SYNC] Group $groupId has no schedule');
        return await _clearMissingAssignment(
          userId,
          groupId: groupId,
          groupName: groupName,
          scheduleId: scheduleId ?? '',
        );
      }

      var remote = TrackingSchedule.fromFirestore(scheduleData);
      remote = remote.copyWith(
        lastUpdated:
            remote.lastUpdated ??
            TrackingSchedule.fromFirestore(groupData).lastUpdated,
      );

      final db = DatabaseHelper.instance;
      final local = await db.getTrackingSchedule(userId);
      final cachedGroupId = await db.getSetting(_metaKey('group_id', userId));
      final cachedScheduleId = await db.getSetting(
        _metaKey('schedule_id', userId),
      );
      final assignmentChanged =
          cachedGroupId != groupId || cachedScheduleId != (scheduleId ?? '');
      final remoteVersion = remote.lastUpdated;
      final localVersion = local.lastUpdated;
      final versionIsNewer =
          remoteVersion != null &&
          (localVersion == null || remoteVersion.isAfter(localVersion));
      final valuesChanged = !_sameSchedule(local, remote);
      final firstCache = localVersion == null && !local.isValid;
      final rawEnabled = scheduleData['is_enabled'] ?? scheduleData['enabled'];
      final rawStatus =
          (scheduleData['schedule_status'] ?? scheduleData['status'])
              ?.toString()
              .trim()
              .toLowerCase();
      final explicitlyDisabled =
          rawEnabled == false ||
          rawEnabled == 0 ||
          rawEnabled == '0' ||
          rawEnabled == 'false' ||
          (rawStatus != null &&
              !const {'active', 'enabled', 'approved'}.contains(rawStatus));
      final shouldReplace =
          (remote.isValid || explicitlyDisabled || versionIsNewer) &&
          (assignmentChanged ||
              versionIsNewer ||
              firstCache ||
              (remoteVersion == null && valuesChanged));

      debugPrint(
        '[SCHEDULE SYNC] Firestore version: ${remoteVersion ?? 'unversioned'}; '
        'SQLite version: ${localVersion ?? 'unversioned'}',
      );
      if (shouldReplace) {
        final effective = remote.isValid
            ? remote
            : TrackingSchedule(
                isEnabled: false,
                selectedDays: const [],
                lastUpdated: remoteVersion,
              );
        await db.saveTrackingSchedule(userId, effective);
        debugPrint('[SCHEDULE SYNC] SQLite schedule updated');
      } else {
        debugPrint('[SCHEDULE SYNC] SQLite schedule is current');
      }

      await db.setSetting(_metaKey('group_id', userId), groupId);
      await db.setSetting(_metaKey('group_name', userId), groupName);
      await db.setSetting(_metaKey('schedule_id', userId), scheduleId ?? '');
      await db.setSetting(
        _metaKey('last_schedule_sync_at', userId),
        DateTime.now().toUtc().toIso8601String(),
      );
      return shouldReplace;
    } on FirebaseException catch (error) {
      debugPrint(
        '[SCHEDULE SYNC] Firestore unavailable (${error.code}); keeping SQLite schedule',
      );
      return false;
    } catch (error) {
      debugPrint(
        '[SCHEDULE SYNC] Schedule refresh failed; keeping SQLite schedule: $error',
      );
      return false;
    }
  }

  Map<String, dynamic>? _embeddedSchedule(Map<String, dynamic> groupData) {
    final nested =
        groupData['schedule'] ??
        groupData['tracking_schedule'] ??
        groupData['assigned_schedule'];
    if (nested is Map) return Map<String, dynamic>.from(nested);
    if (groupData.containsKey('start_time') ||
        groupData.containsKey('start_hour')) {
      return groupData;
    }
    return null;
  }

  bool _sameSchedule(TrackingSchedule a, TrackingSchedule b) =>
      a.isEnabled == b.isEnabled &&
      a.startHour == b.startHour &&
      a.startMinute == b.startMinute &&
      a.endHour == b.endHour &&
      a.endMinute == b.endMinute &&
      listEquals(a.selectedDays, b.selectedDays);

  Future<TrackingSchedule> loadSchedule(String userId) async {
    await syncAssignedSchedule(userId);
    return loadCachedSchedule(userId);
  }

  Future<void> listenForScheduleUpdates(
    String userId, {
    required void Function(TrackingSchedule schedule) onChanged,
  }) async {
    if (_activeUserId == userId && _listeners.isNotEmpty) return;
    stopListening();
    _activeUserId = userId;
    try {
      final userSnapshot = await _queryManagedUser(
        userId,
        source: Source.serverAndCache,
      );
      final userData = userSnapshot?.docs.first.data();
      final groupValue =
          userData?['group_id'] ??
          userData?['groupId'] ??
          userData?['group'] ??
          userData?['user_group'] ??
          userData?['group_name'];
      final groupId = groupValue is Map
          ? (groupValue['id'] ?? groupValue['group_id'] ?? groupValue['name'])
                ?.toString()
                .trim()
          : groupValue?.toString().trim();

      Future<void> refresh() async {
        final changed = await syncAssignedSchedule(userId);
        if (changed) onChanged(await loadCachedSchedule(userId));
      }

      _listeners.add(
        _firestore
            .collection('users')
            .where(
              'username',
              isEqualTo: (await DatabaseHelper.instance.getSetting(
                'current_username',
              ))?.toLowerCase(),
            )
            .limit(1)
            .snapshots()
            .listen((_) => refresh()),
      );
      if (groupId != null && groupId.isNotEmpty) {
        final groupRef = _firestore.collection('groups').doc(groupId);
        _listeners.add(groupRef.snapshots().listen((_) => refresh()));
        final group = await groupRef.get(
          const GetOptions(source: Source.serverAndCache),
        );
        final scheduleId = group.data()?['default_schedule_id']?.toString();
        if (scheduleId != null && scheduleId.isNotEmpty) {
          _listeners.add(
            _firestore
                .collection('schedules')
                .doc(scheduleId)
                .snapshots()
                .listen((_) => refresh()),
          );
        }
      }
    } catch (error) {
      debugPrint(
        '[SCHEDULE SYNC] Could not attach foreground listeners: $error',
      );
    }
  }

  void stopListening() {
    for (final listener in _listeners) {
      listener.cancel();
    }
    _listeners.clear();
    _activeUserId = null;
  }

  /// Kept for callers that save a local schedule; Admin remains the Firestore
  /// authority, so this method does not write a user-level Firestore override.
  Future<void> saveSchedule(String userId, TrackingSchedule schedule) async {
    await DatabaseHelper.instance.saveTrackingSchedule(
      userId,
      schedule.copyWith(lastUpdated: DateTime.now().toUtc()),
    );
  }
}
