import 'dart:convert';

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
  static const Duration _kolkataOffset = Duration(hours: 5, minutes: 30);

  final bool isEnabled;
  final List<int> selectedDays; // 1 = Monday, 7 = Sunday (matching DateTime.weekday)
  final int startHour;
  final int startMinute;
  final int endHour;
  final int endMinute;
  final DateTime? lastUpdated;

  const TrackingSchedule({
    this.isEnabled = true,
    this.selectedDays = const [1, 2, 3, 4, 5], // Default: Mon-Fri
    this.startHour = 9,
    this.startMinute = 0,
    this.endHour = 18,
    this.endMinute = 0,
    this.lastUpdated,
  });

  /// Factory for a default schedule: Mon-Fri, 9:00 AM - 6:00 PM
  factory TrackingSchedule.defaultSchedule() {
    return TrackingSchedule(
      isEnabled: true,
      selectedDays: const [1, 2, 3, 4, 5],
      startHour: 9,
      startMinute: 0,
      endHour: 18,
      endMinute: 0,
      lastUpdated: DateTime.now().toUtc(),
    );
  }

  int get startMinutesSinceMidnight => startHour * 60 + startMinute;
  int get endMinutesSinceMidnight => endHour * 60 + endMinute;

  /// Returns true if this schedule crosses midnight (e.g. 22:00 to 06:00)
  bool get isOvernight => startMinutesSinceMidnight > endMinutesSinceMidnight;

  /// Whether the configuration is valid (has at least 1 day and non-zero duration)
  bool get isValid {
    if (selectedDays.isEmpty) return false;
    if (startHour < 0 || startHour > 23 || startMinute < 0 || startMinute > 59) return false;
    if (endHour < 0 || endHour > 23 || endMinute < 0 || endMinute > 59) return false;
    if (startMinutesSinceMidnight == endMinutesSinceMidnight) return false;
    return true;
  }

  static DateTime _asiaKolkataNow([DateTime? checkTime]) {
    final base = checkTime ?? DateTime.now();
    final utc = base.toUtc();
    return utc.add(_kolkataOffset);
  }

  /// Centralized validation function checking whether a given local DateTime falls
  /// strictly within the allowed schedule window.
  ScheduleValidationResult validateSchedule([DateTime? checkTime]) {
    final now = _asiaKolkataNow(checkTime);

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
          unavailableReason: 'Tracking starts at ${_formatTime(startHour, startMinute)}.',
        );
      } else if (currentMinutes >= endMinutesSinceMidnight) {
        return ScheduleValidationResult(
          code: ScheduleValidationCode.scheduledTrackingEnded,
          isWithinSchedule: false,
          statusMessage: 'Scheduled tracking ended',
          unavailableReason: 'Scheduled tracking ended at ${_formatTime(endHour, endMinute)}.',
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
      final isEveningLeg = selectedDays.contains(currentWeekday) &&
          currentMinutes >= startMinutesSinceMidnight;

      // Window 2: Started yesterday in the evening, ending this morning (currentMinutes < endMinutes)
      final yesterdayWeekday = currentWeekday == 1 ? 7 : currentWeekday - 1;
      final isMorningLeg = selectedDays.contains(yesterdayWeekday) &&
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
            unavailableReason: 'Tracking starts at ${_formatTime(startHour, startMinute)}.',
          );
        } else {
          return ScheduleValidationResult(
            code: ScheduleValidationCode.scheduledTrackingEnded,
            isWithinSchedule: false,
            statusMessage: 'Scheduled tracking ended',
            unavailableReason: 'Scheduled tracking ended at ${_formatTime(endHour, endMinute)}.',
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
      'last_updated': (lastUpdated ?? DateTime.now().toUtc()).toIso8601String(),
    };
  }

  factory TrackingSchedule.fromMap(Map<String, dynamic> map) {
    List<int> parseDays(dynamic value) {
      if (value == null) return [1, 2, 3, 4, 5];
      if (value is List) {
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
        return value.map((e) {
          final numeric = int.tryParse(e.toString());
          return numeric ?? dayNumbers[e.toString().trim().toLowerCase()] ?? 0;
        }).where((day) => day >= 1 && day <= 7).toList();
      }
      final str = value.toString().trim();
      if (str.isEmpty) return [];
      return str
          .split(',')
          .map((s) => int.tryParse(s.trim()) ?? 0)
          .where((d) => d >= 1 && d <= 7)
          .toList();
    }

    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      try {
        if (value is DateTime) return value.toUtc();
        return DateTime.parse(value.toString());
      } catch (_) {
        return null;
      }
    }

    (int, int) parseTime(dynamic value, int fallbackHour, int fallbackMinute) {
      if (value == null) return (fallbackHour, fallbackMinute);
      final parts = value.toString().trim().split(':');
      if (parts.length != 2) return (fallbackHour, fallbackMinute);
      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      if (hour == null || minute == null || hour < 0 || hour > 23 || minute < 0 || minute > 59) {
        return (fallbackHour, fallbackMinute);
      }
      return (hour, minute);
    }

    final isEnabledVal = map['is_enabled'];
    final status = map['status']?.toString().trim().toLowerCase();
    final isEnabled = isEnabledVal == null && status != null
        ? status == 'active' || status == 'enabled' || status == 'approved'
        : isEnabledVal is bool
        ? isEnabledVal
        : (isEnabledVal == 1 || isEnabledVal == '1' || isEnabledVal == 'true');
    final startTime = parseTime(map['start_time'], 9, 0);
    final endTime = parseTime(map['end_time'], 18, 0);

    return TrackingSchedule(
      isEnabled: isEnabled,
      selectedDays: parseDays(map['selected_days'] ?? map['active_days']),
      startHour: int.tryParse(map['start_hour']?.toString() ?? '') ?? startTime.$1,
      startMinute: int.tryParse(map['start_minute']?.toString() ?? '') ?? startTime.$2,
      endHour: int.tryParse(map['end_hour']?.toString() ?? '') ?? endTime.$1,
      endMinute: int.tryParse(map['end_minute']?.toString() ?? '') ?? endTime.$2,
      lastUpdated: parseDate(map['last_updated'] ?? map['created_at']),
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
      'updated_at_ms': (lastUpdated ?? DateTime.now().toUtc()).millisecondsSinceEpoch,
    };
  }

  factory TrackingSchedule.fromFirestore(Map<String, dynamic> map) {
    return TrackingSchedule.fromMap(map);
  }
}
