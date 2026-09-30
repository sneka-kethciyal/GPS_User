import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Enum representing the state of schedule validation for user tracking.
enum ScheduleValidationCode {
  active,
  waitingForStartTime,
  trackingUnavailableToday,
  scheduledTrackingEnded,
  scheduleDisabled,
  invalidConfig,
}

class ScheduleValidationResult {
  final ScheduleValidationCode code;
  final bool isWithinSchedule;
  final String statusMessage;
  final String? unavailableReason;

  const ScheduleValidationResult({
    required this.code,
    required this.isWithinSchedule,
    required this.statusMessage,
    this.unavailableReason,
  });

  bool get isActive => isWithinSchedule;
}

class TrackingSchedule {
  final bool isEnabled;
  final List<int>
  selectedDays; // 1 = Monday, 7 = Sunday (matching DateTime.weekday)
  final int startHour;
  final int startMinute;
  final int endHour;
  final int endMinute;
  final DateTime? lastUpdated;

  const TrackingSchedule({
    this.isEnabled = false,
    this.selectedDays = const [],
    this.startHour = 0,
    this.startMinute = 0,
    this.endHour = 0,
    this.endMinute = 0,
    this.lastUpdated,
  });

  /// Represents the absence of an assigned Firestore schedule.
  factory TrackingSchedule.defaultSchedule() {
    return TrackingSchedule(isEnabled: false, selectedDays: const []);
  }

  int get startMinutesSinceMidnight => startHour * 60 + startMinute;
  int get endMinutesSinceMidnight => endHour * 60 + endMinute;

  /// Returns true if this schedule crosses midnight (e.g. 22:00 to 06:00)
  bool get isOvernight => startMinutesSinceMidnight > endMinutesSinceMidnight;

  /// Whether the configuration is valid (has at least 1 day and non-zero duration)
  bool get isValid {
    if (selectedDays.isEmpty) return false;
    if (startHour < 0 || startHour > 23 || startMinute < 0 || startMinute > 59)
      return false;
    if (endHour < 0 || endHour > 23 || endMinute < 0 || endMinute > 59)
      return false;
    if (startMinutesSinceMidnight == endMinutesSinceMidnight) return false;
    return true;
  }

  static DateTime localNow([DateTime? checkTime]) {
    return (checkTime ?? DateTime.now()).toLocal();
  }

  /// Legacy alias retained for callers from older app versions.
  static DateTime asiaKolkataNow([DateTime? checkTime]) => localNow(checkTime);

  /// Local wall-clock instant for the next schedule start strictly
  /// after [referenceKolkata]. Used to arm background restarts — never hardcoded hours.
  DateTime? nextScheduleWindowStart([DateTime? referenceLocal]) {
    if (!isEnabled || !isValid) return null;

    final from = referenceLocal?.toLocal() ?? DateTime.now();
    for (var dayOffset = 0; dayOffset <= 7; dayOffset++) {
      final dayBase = DateTime(
        from.year,
        from.month,
        from.day,
      ).add(Duration(days: dayOffset));
      if (!selectedDays.contains(dayBase.weekday)) continue;

      final candidateStart = DateTime(
        dayBase.year,
        dayBase.month,
        dayBase.day,
        startHour,
        startMinute,
      );
      if (candidateStart.isAfter(from)) {
        return candidateStart;
      }
    }
    return null;
  }

  /// Stop boundary for the window that begins at [windowStartLocal].
  DateTime? scheduleWindowEndForStart(DateTime windowStartLocal) {
    if (!isValid) return null;
    final start = windowStartLocal.toLocal();

    if (!isOvernight) {
      return DateTime(start.year, start.month, start.day, endHour, endMinute);
    }

    final endDay = start.add(const Duration(days: 1));
    return DateTime(endDay.year, endDay.month, endDay.day, endHour, endMinute);
  }

  /// Converts a local wall-clock instant to UTC for delays and alarms.
  static DateTime localWallClockToUtc(DateTime localWall) {
    return DateTime(
      localWall.year,
      localWall.month,
      localWall.day,
      localWall.hour,
      localWall.minute,
      localWall.second,
    ).toUtc();
  }

  /// Legacy alias retained for existing callers.
  static DateTime kolkataWallClockToUtc(DateTime localWall) =>
      localWallClockToUtc(localWall);

  void debugLogSchedule({String? userId, String? groupId}) {
    final nowLocal = DateTime.now();
    final nextStart = nextScheduleWindowStart(nowLocal);
    final nextStop = nextStart == null
        ? null
        : scheduleWindowEndForStart(nextStart);
    const dayNames = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final day = dayNames[nowLocal.weekday - 1];
    final currentTime =
        '${nowLocal.hour.toString().padLeft(2, '0')}:${nowLocal.minute.toString().padLeft(2, '0')}';
    final start =
        '${startHour.toString().padLeft(2, '0')}:${startMinute.toString().padLeft(2, '0')}';
    final end =
        '${endHour.toString().padLeft(2, '0')}:${endMinute.toString().padLeft(2, '0')}';
    debugPrint(
      '[SCHEDULE] User: ${userId ?? 'unknown'} Group: ${groupId ?? 'unknown'} '
      'Day: $day Current time: $currentTime Start: $start End: $end '
      'Enabled days: $selectedDays Day enabled: ${selectedDays.contains(nowLocal.weekday)} '
      'Inside schedule: ${isWithinAllowedSchedule(nowLocal)} '
      'Schedule enabled: $isEnabled Next start: $nextStart Next stop: $nextStop',
    );
  }

  /// Centralized validation function checking whether a given local DateTime falls
  /// strictly within the allowed schedule window.
  ScheduleValidationResult validateSchedule([DateTime? checkTime]) {
    final now = localNow(checkTime);

    if (!isEnabled) {
      return const ScheduleValidationResult(
        code: ScheduleValidationCode.scheduleDisabled,
        isWithinSchedule: false,
        statusMessage: 'Tracking unavailable (schedule disabled)',
        unavailableReason: 'Schedule is currently disabled.',
      );
    }

    if (!isValid) {
      return const ScheduleValidationResult(
        code: ScheduleValidationCode.invalidConfig,
        isWithinSchedule: false,
        statusMessage: 'Invalid schedule configuration',
        unavailableReason: 'Schedule configuration is missing or invalid.',
      );
    }

    final currentWeekday = now.weekday; // 1 = Monday, 7 = Sunday
    final currentMinutes = now.hour * 60 + now.minute;

    if (!isOvernight) {
      // ── Standard daytime schedule (e.g., 09:00 to 18:00) ──────────────────
      if (!selectedDays.contains(currentWeekday)) {
        return const ScheduleValidationResult(
          code: ScheduleValidationCode.trackingUnavailableToday,
          isWithinSchedule: false,
          statusMessage: 'Tracking unavailable today',
          unavailableReason: 'Today is not a scheduled tracking day.',
        );
      }

      // Rule 7 boundary rules:
      // - current < start: waiting for start time
      // - current >= start && current < end: active
      // - current >= end: scheduled tracking ended
      if (currentMinutes < startMinutesSinceMidnight) {
        return ScheduleValidationResult(
          code: ScheduleValidationCode.waitingForStartTime,
          isWithinSchedule: false,
          statusMessage: 'Waiting for scheduled start time',
          unavailableReason:
              'Tracking starts at ${_formatTime(startHour, startMinute)}.',
        );
      } else if (currentMinutes >= endMinutesSinceMidnight) {
        return ScheduleValidationResult(
          code: ScheduleValidationCode.scheduledTrackingEnded,
          isWithinSchedule: false,
          statusMessage: 'Scheduled tracking ended',
          unavailableReason:
              'Scheduled tracking ended at ${_formatTime(endHour, endMinute)}.',
        );
      } else {
        return const ScheduleValidationResult(
          code: ScheduleValidationCode.active,
          isWithinSchedule: true,
          statusMessage: 'Scheduled tracking active',
        );
      }
    } else {
      // ── Overnight schedule crossing midnight (e.g., 22:00 to 06:00) ───────
      // Window 1: Started today in the evening (currentMinutes >= startMinutes)
      final isEveningLeg =
          selectedDays.contains(currentWeekday) &&
          currentMinutes >= startMinutesSinceMidnight;

      // Window 2: Started yesterday in the evening, ending this morning (currentMinutes < endMinutes)
      final yesterdayWeekday = currentWeekday == 1 ? 7 : currentWeekday - 1;
      final isMorningLeg =
          selectedDays.contains(yesterdayWeekday) &&
          currentMinutes < endMinutesSinceMidnight;

      if (isEveningLeg || isMorningLeg) {
        return const ScheduleValidationResult(
          code: ScheduleValidationCode.active,
          isWithinSchedule: true,
          statusMessage: 'Scheduled tracking active',
        );
      }

      // Outside active window: Determine if waiting or ended
      if (selectedDays.contains(currentWeekday)) {
        if (currentMinutes < startMinutesSinceMidnight) {
          return ScheduleValidationResult(
            code: ScheduleValidationCode.waitingForStartTime,
            isWithinSchedule: false,
            statusMessage: 'Waiting for scheduled start time',
            unavailableReason:
                'Tracking starts at ${_formatTime(startHour, startMinute)}.',
          );
        } else {
          return ScheduleValidationResult(
            code: ScheduleValidationCode.scheduledTrackingEnded,
            isWithinSchedule: false,
            statusMessage: 'Scheduled tracking ended',
            unavailableReason:
                'Scheduled tracking ended at ${_formatTime(endHour, endMinute)}.',
          );
        }
      } else {
        // Today is not selected and not in yesterday's morning leg
        return const ScheduleValidationResult(
          code: ScheduleValidationCode.trackingUnavailableToday,
          isWithinSchedule: false,
          statusMessage: 'Tracking unavailable today',
          unavailableReason: 'Today is not a scheduled tracking day.',
        );
      }
    }
  }

  /// Single boolean answer: is tracking allowed right now?
  bool isWithinAllowedSchedule([DateTime? checkTime]) {
    return validateSchedule(checkTime).isWithinSchedule;
  }

  /// Formats formatted start and end strings (e.g. "09:00 AM – 06:00 PM")
  String get formattedTimeRange =>
      '${_formatTime(startHour, startMinute)} – ${_formatTime(endHour, endMinute)}';

  /// Returns localized day abbreviations (e.g. "Mon, Wed, Fri")
  String get formattedDaysSummary {
    if (selectedDays.length == 7) return 'Every day';
    if (selectedDays.length == 5 &&
        selectedDays.contains(1) &&
        selectedDays.contains(2) &&
        selectedDays.contains(3) &&
        selectedDays.contains(4) &&
        selectedDays.contains(5)) {
      return 'Mon – Fri';
    }
    if (selectedDays.isEmpty) return 'No days selected';

    const dayNames = {
      1: 'Mon',
      2: 'Tue',
      3: 'Wed',
      4: 'Thu',
      5: 'Fri',
      6: 'Sat',
      7: 'Sun',
    };
    final sorted = List<int>.from(selectedDays)..sort();
    return sorted.map((d) => dayNames[d] ?? '').join(', ');
  }

  static String _formatTime(int hour, int minute) {
    final period = hour >= 12 ? 'PM' : 'AM';
    final h = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final m = minute.toString().padLeft(2, '0');
    return '$h:$m $period';
  }

  TrackingSchedule copyWith({
    bool? isEnabled,
    List<int>? selectedDays,
    int? startHour,
    int? startMinute,
    int? endHour,
    int? endMinute,
    DateTime? lastUpdated,
  }) {
    return TrackingSchedule(
      isEnabled: isEnabled ?? this.isEnabled,
      selectedDays: selectedDays != null
          ? List<int>.unmodifiable(selectedDays)
          : this.selectedDays,
      startHour: startHour ?? this.startHour,
      startMinute: startMinute ?? this.startMinute,
      endHour: endHour ?? this.endHour,
      endMinute: endMinute ?? this.endMinute,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'is_enabled': isEnabled ? 1 : 0,
      'selected_days': selectedDays.join(','),
      'start_hour': startHour,
      'start_minute': startMinute,
      'end_hour': endHour,
      'end_minute': endMinute,
      'last_updated': lastUpdated?.toUtc().toIso8601String(),
    };
  }

  factory TrackingSchedule.fromMap(Map<String, dynamic> map) {
    List<int> parseDays(dynamic value) {
      const dayNumbers = {
        'mon': 1,
        'monday': 1,
        'tue': 2,
        'tuesday': 2,
        'wed': 3,
        'wednesday': 3,
        'thu': 4,
        'thursday': 4,
        'fri': 5,
        'friday': 5,
        'sat': 6,
        'saturday': 6,
        'sun': 7,
        'sunday': 7,
      };
      if (value == null) return [];
      if (value is Map) {
        return value.entries
            .where((entry) => entry.value == true || entry.value == 1)
            .map((entry) => entry.key)
            .expand((key) => parseDays([key]))
            .toSet()
            .toList()
          ..sort();
      }
      if (value is List) {
        return value
            .map((e) {
              final numeric = int.tryParse(e.toString());
              return numeric ??
                  dayNumbers[e.toString().trim().toLowerCase()] ??
                  0;
            })
            .where((day) => day >= 1 && day <= 7)
            .toList();
      }
      final str = value.toString().trim();
      if (str.isEmpty) return [];
      return str
          .split(',')
          .map(
            (s) =>
                int.tryParse(s.trim()) ??
                dayNumbers[s.trim().toLowerCase()] ??
                0,
          )
          .where((d) => d >= 1 && d <= 7)
          .toList();
    }

    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      try {
        if (value is DateTime) return value.toUtc();
        if (value is num) {
          return DateTime.fromMillisecondsSinceEpoch(
            value.toInt(),
            isUtc: true,
          );
        }
        try {
          final date = (value as dynamic).toDate();
          if (date is DateTime) return date.toUtc();
        } catch (_) {}
        return DateTime.parse(value.toString()).toUtc();
      } catch (_) {
        return null;
      }
    }

    (int, int)? parseTime(dynamic value) {
      if (value == null) return null;
      final parts = value.toString().trim().split(':');
      if (parts.length != 2) return null;
      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      if (hour == null ||
          minute == null ||
          hour < 0 ||
          hour > 23 ||
          minute < 0 ||
          minute > 59) {
        return null;
      }
      return (hour, minute);
    }

    final isEnabledVal = map['is_enabled'];
    final status = (map['schedule_status'] ?? map['status'])
        ?.toString()
        .trim()
        .toLowerCase();
    final enabledValue = isEnabledVal ?? map['enabled'];
    final isEnabled = enabledValue == null && status != null
        ? status == 'active' || status == 'enabled' || status == 'approved'
        : enabledValue is bool
        ? enabledValue
        : (enabledValue == 1 || enabledValue == '1' || enabledValue == 'true');
    final startTime = parseTime(map['start_time'] ?? map['startTime']);
    final endTime = parseTime(map['end_time'] ?? map['endTime']);
    final startHour =
        int.tryParse(map['start_hour']?.toString() ?? '') ?? startTime?.$1;
    final startMinute =
        int.tryParse(map['start_minute']?.toString() ?? '') ?? startTime?.$2;
    final endHour =
        int.tryParse(map['end_hour']?.toString() ?? '') ?? endTime?.$1;
    final endMinute =
        int.tryParse(map['end_minute']?.toString() ?? '') ?? endTime?.$2;
    final hasCompleteTimes =
        startHour != null &&
        startMinute != null &&
        endHour != null &&
        endMinute != null;

    return TrackingSchedule(
      isEnabled: isEnabled && hasCompleteTimes,
      selectedDays: parseDays(
        map['selected_days'] ??
            map['enabled_days'] ??
            map['active_days'] ??
            map['days'] ??
            map['weekdays'],
      ),
      startHour: startHour ?? 0,
      startMinute: startMinute ?? 0,
      endHour: endHour ?? 0,
      endMinute: endMinute ?? 0,
      lastUpdated: parseDate(
        map['schedule_updated_at'] ??
            map['updated_at'] ??
            map['modified_at'] ??
            map['last_updated'] ??
            map['updated_at_ms'] ??
            map['created_at'],
      ),
    );
  }

  String toJson() => jsonEncode(toMap());

  factory TrackingSchedule.fromJson(String jsonStr) {
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return TrackingSchedule.fromMap(map);
    } catch (_) {
      return TrackingSchedule.defaultSchedule();
    }
  }

  Map<String, dynamic> toFirestore() {
    return {
      'is_enabled': isEnabled,
      'selected_days': selectedDays,
      'start_hour': startHour,
      'start_minute': startMinute,
      'end_hour': endHour,
      'end_minute': endMinute,
      'last_updated': (lastUpdated ?? DateTime.now().toUtc()).toIso8601String(),
      'updated_at_ms':
          (lastUpdated ?? DateTime.now().toUtc()).millisecondsSinceEpoch,
    };
  }

  factory TrackingSchedule.fromFirestore(Map<String, dynamic> map) {
    return TrackingSchedule.fromMap(map);
  }
}
