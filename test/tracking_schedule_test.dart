import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/models/tracking_schedule.dart';
import 'package:expense_tracker/providers/expense_provider.dart';
import 'package:expense_tracker/services/auth_service.dart';

void main() {
  group('TrackingSchedule Unit Tests', () {
    test(
      'Standard daytime schedule validation (09:00 to 18:00 on Mon, Wed, Fri)',
      () {
        final schedule = TrackingSchedule(
          isEnabled: true,
          selectedDays: const [1, 3, 5], // Mon, Wed, Fri
          startHour: 9,
          startMinute: 0,
          endHour: 18,
          endMinute: 0,
        );

        // Monday (1)
        // Exactly at start time (09:00): active
        expect(
          schedule.isWithinAllowedSchedule(DateTime(2026, 9, 21, 9, 0)),
          isTrue,
        );
        // Within schedule (12:30): active
        expect(
          schedule.isWithinAllowedSchedule(DateTime(2026, 9, 21, 12, 30)),
          isTrue,
        );
        // Just before end time (17:59): active
        expect(
          schedule.isWithinAllowedSchedule(DateTime(2026, 9, 21, 17, 59)),
          isTrue,
        );
        // Exactly at end time (18:00): STOP tracking (rule 7: at exactly end time, stop)
        expect(
          schedule.isWithinAllowedSchedule(DateTime(2026, 9, 21, 18, 0)),
          isFalse,
        );
        expect(
          schedule.validateSchedule(DateTime(2026, 9, 21, 18, 0)).code,
          equals(ScheduleValidationCode.scheduledTrackingEnded),
        );
        // After end time (18:01): false
        expect(
          schedule.isWithinAllowedSchedule(DateTime(2026, 9, 21, 18, 1)),
          isFalse,
        );
        // Before start time (08:59): false, waiting
        expect(
          schedule.isWithinAllowedSchedule(DateTime(2026, 9, 21, 8, 59)),
          isFalse,
        );
        expect(
          schedule.validateSchedule(DateTime(2026, 9, 21, 8, 59)).code,
          equals(ScheduleValidationCode.waitingForStartTime),
        );

        // Tuesday (2) - unselected day
        // 12:00 PM on Tuesday: false, tracking unavailable today
        expect(
          schedule.isWithinAllowedSchedule(DateTime(2026, 9, 22, 12, 0)),
          isFalse,
        );
        expect(
          schedule.validateSchedule(DateTime(2026, 9, 22, 12, 0)).code,
          equals(ScheduleValidationCode.trackingUnavailableToday),
        );

        // Wednesday (3) - selected day
        expect(
          schedule.isWithinAllowedSchedule(DateTime(2026, 9, 23, 14, 0)),
          isTrue,
        );
      },
    );

    test('Overnight schedule crossing midnight (22:00 to 06:00 on Monday)', () {
      final schedule = TrackingSchedule(
        isEnabled: true,
        selectedDays: const [1], // Monday only
        startHour: 22,
        startMinute: 0,
        endHour: 6,
        endMinute: 0,
      );

      expect(schedule.isOvernight, isTrue);

      // Monday night (2026-09-21):
      // 21:59 (before 22:00): false
      expect(
        schedule.isWithinAllowedSchedule(DateTime(2026, 9, 21, 21, 59)),
        isFalse,
      );
      // 22:00 (start): true
      expect(
        schedule.isWithinAllowedSchedule(DateTime(2026, 9, 21, 22, 0)),
        isTrue,
      );
      // 23:30: true
      expect(
        schedule.isWithinAllowedSchedule(DateTime(2026, 9, 21, 23, 30)),
        isTrue,
      );

      // Tuesday morning (2026-09-22):
      // 02:00 AM (overnight leg from Monday): true
      expect(
        schedule.isWithinAllowedSchedule(DateTime(2026, 9, 22, 2, 0)),
        isTrue,
      );
      // 05:59 AM: true
      expect(
        schedule.isWithinAllowedSchedule(DateTime(2026, 9, 22, 5, 59)),
        isTrue,
      );
      // 06:00 AM (exactly end time): false
      expect(
        schedule.isWithinAllowedSchedule(DateTime(2026, 9, 22, 6, 0)),
        isFalse,
      );
      // 07:00 AM: false (Tuesday is not a selected day)
      expect(
        schedule.isWithinAllowedSchedule(DateTime(2026, 9, 22, 7, 0)),
        isFalse,
      );
      // Tuesday night 22:30 (Tuesday not selected): false
      expect(
        schedule.isWithinAllowedSchedule(DateTime(2026, 9, 22, 22, 30)),
        isFalse,
      );
    });

    test('Schedule disabled enforces strict OFF state', () {
      final schedule = TrackingSchedule(
        isEnabled: false,
        selectedDays: const [1, 2, 3, 4, 5, 6, 7],
        startHour: 0,
        startMinute: 0,
        endHour: 23,
        endMinute: 59,
      );

      expect(
        schedule.isWithinAllowedSchedule(DateTime(2026, 9, 21, 12, 0)),
        isFalse,
      );
      expect(
        schedule.validateSchedule(DateTime(2026, 9, 21, 12, 0)).code,
        equals(ScheduleValidationCode.scheduleDisabled),
      );
    });

    test('Serialization to/from Map, JSON, and Firestore', () {
      final original = TrackingSchedule(
        isEnabled: true,
        selectedDays: const [1, 3, 5],
        startHour: 8,
        startMinute: 30,
        endHour: 17,
        endMinute: 45,
        lastUpdated: DateTime.utc(2026, 9, 22, 10, 0),
      );

      final jsonStr = original.toJson();
      final fromJson = TrackingSchedule.fromJson(jsonStr);

      expect(fromJson.isEnabled, isTrue);
      expect(fromJson.selectedDays, equals([1, 3, 5]));
      expect(fromJson.startHour, equals(8));
      expect(fromJson.startMinute, equals(30));
      expect(fromJson.endHour, equals(17));
      expect(fromJson.endMinute, equals(45));

      final firestoreMap = original.toFirestore();
      final fromFirestore = TrackingSchedule.fromFirestore(firestoreMap);
      expect(fromFirestore.selectedDays, equals([1, 3, 5]));
      expect(fromFirestore.startHour, equals(8));
    });

    test(
      'Parses admin schedule fields with string times and active status',
      () {
        final schedule = TrackingSchedule.fromFirestore({
          'created_at': '2026-09-23T11:48:48.000Z',
          'end_time': '22:00',
          'start_time': '09:00',
          'status': 'Active',
          'timezone': 'Asia/Kolkata',
        });

        expect(schedule.isEnabled, isTrue);
        expect(schedule.startHour, equals(9));
        expect(schedule.startMinute, equals(0));
        expect(schedule.endHour, equals(22));
        expect(schedule.endMinute, equals(0));
        expect(schedule.formattedTimeRange, equals('9:00 AM – 10:00 PM'));
      },
    );

    test('Parses admin active day names', () {
      final schedule = TrackingSchedule.fromFirestore({
        'active_days': ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'],
        'end_time': '22:00',
        'start_time': '09:00',
        'status': 'Active',
      });

      expect(schedule.selectedDays, equals([1, 2, 3, 4, 5]));
    });

    test('Expense date keys use the Asia/Kolkata calendar day', () {
      expect(
        ExpenseProvider.kolkataDateKey(DateTime.utc(2026, 9, 23, 18, 29)),
        equals('2026-09-23'),
      );
      expect(
        ExpenseProvider.kolkataDateKey(DateTime.utc(2026, 9, 23, 18, 30)),
        equals('2026-09-24'),
      );
    });

    test('Admin profile parsing reads active status and admin-controlled role info', () {
      final profile = AuthService.profileFromMap({
        'username': 'john.doe',
        'role': 'Field Worker',
        'account_status': 'active',
        'assigned_schedule': {
          'is_enabled': true,
          'selected_days': [1, 2, 3, 4, 5],
          'start_hour': 9,
          'start_minute': 0,
          'end_hour': 18,
          'end_minute': 0,
        },
      });

      expect(profile.username, 'john.doe');
      expect(profile.role, 'Field Worker');
      expect(profile.accountStatus, 'active');
      expect(profile.schedule != null, isTrue);
      expect(
        AuthService.isAccountActive({'account_status': 'inactive'}),
        isFalse,
      );
    });
  });
}
