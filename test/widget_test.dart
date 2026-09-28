import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:expense_tracker/models/expense.dart';
import 'package:expense_tracker/models/monthly_credit.dart';
import 'package:expense_tracker/providers/expense_provider.dart';
import 'package:expense_tracker/services/auth_service.dart';

void main() {
  test('Monthly Credit and Expense Model unit tests', () {
    final credit = MonthlyCredit(
      userId: 'test-user',
      month: '2026-09',
      creditAmount: 5000.0,
      createdAt: DateTime.now(),
    );

    expect(credit.creditAmount, 5000.0);
    expect(credit.month, '2026-09');

    final expense = Expense(
      userId: 'test-user',
      month: '2026-09',
      itemName: 'Office Equipment',
      expenseAmount: 250.0,
      timestamp: DateTime.now(),
    );

    expect(expense.itemName, 'Office Equipment');
    expect(expense.expenseAmount, 250.0);
    expect(credit.creditAmount - expense.expenseAmount, 4750.0);
  });

  test('Adding 100000 and 200000 credits totals 300000', () {
    final credits = [
      MonthlyCredit(
        userId: 'test-user',
        month: '2026-09',
        creditAmount: 100000,
        createdAt: DateTime.utc(2026, 9, 1),
      ),
      MonthlyCredit(
        userId: 'test-user',
        month: '2026-09',
        creditAmount: 200000,
        createdAt: DateTime.utc(2026, 9, 2),
      ),
    ];

    expect(MonthlyCredit.totalForMonth(credits), 300000);
  });

  test('Expense parses the nested Firestore document fields', () {
    final expense = Expense.fromFirestore(
      userId: 'test-user',
      firebaseId: 'expense-1',
      monthFromPath: '2026-09',
      data: {
        'user_id': 'test-user',
        'item_name': 'Lunch',
        'expense_amount': '125.50',
        'transaction_date': Timestamp.fromDate(
          DateTime.utc(2026, 9, 23, 18, 29),
        ),
      },
    );

    expect(expense.firebaseId, 'expense-1');
    expect(expense.month, '2026-09');
    expect(expense.itemName, 'Lunch');
    expect(expense.expenseAmount, 125.50);
    expect(expense.timestamp, DateTime.utc(2026, 9, 23, 18, 29));
    expect(ExpenseProvider.kolkataDateKey(expense.timestamp), '2026-09-23');
  });

  test('successful login profile update uses a Firestore server timestamp', () {
    final update = AuthService.lastLoginUpdate();

    expect(update.keys, contains('last_login'));
    expect(update['last_login'], isA<FieldValue>());
  });

  test(
    'password reset request update contains only the admin request fields',
    () {
      final update = AuthService.passwordResetRequestUpdate();

      expect(update['password_reset_requested'], isTrue);
      expect(update['password_reset_status'], 'requested');
      expect(update['password_reset_requested_at'], isA<FieldValue>());
      expect(
        update.keys,
        containsAll([
          'password_reset_requested',
          'password_reset_status',
          'password_reset_requested_at',
        ]),
      );
      expect(update.keys, isNot(contains('password')));
    },
  );
}
