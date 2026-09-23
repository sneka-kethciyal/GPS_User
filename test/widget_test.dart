import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:expense_tracker/models/expense.dart';
import 'package:expense_tracker/models/monthly_credit.dart';
import 'package:expense_tracker/providers/expense_provider.dart';

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

  test('Expense parses the nested Firestore document fields', () {
    final expense = Expense.fromFirestore(
      userId: 'test-user',
      firebaseId: 'expense-1',
      monthFromPath: '2026-09',
      data: {
        'user_id': 'test-user',
        'item_name': 'Lunch',
        'expense_amount': '125.50',
        'transaction_date': Timestamp.fromDate(DateTime.utc(2026, 9, 23, 18, 29)),
      },
    );

    expect(expense.firebaseId, 'expense-1');
    expect(expense.month, '2026-09');
    expect(expense.itemName, 'Lunch');
    expect(expense.expenseAmount, 125.50);
    expect(expense.timestamp, DateTime.utc(2026, 9, 23, 18, 29));
    expect(ExpenseProvider.kolkataDateKey(expense.timestamp), '2026-09-23');
  });
}
