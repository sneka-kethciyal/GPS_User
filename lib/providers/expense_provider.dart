import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../models/monthly_credit.dart';
import '../models/expense.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';

class ExpenseProvider extends ChangeNotifier {
  ExpenseProvider({required this.userId}) {
    _initializeData();
    _lastTodayKey = kolkataDateKey(kolkataNow);
    _dayChangeTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      final currentMonth = currentKolkataMonth;
      final currentTodayKey = kolkataDateKey(kolkataNow);
      if (_selectedMonth != currentMonth || _lastTodayKey != currentTodayKey) {
        _selectedMonth = currentMonth;
        _lastTodayKey = currentTodayKey;
        loadDataForSelectedMonth();
        loadReportData();
      } else {
        notifyListeners();
      }
    });
  }

  Future<void> _initializeData() async {
    await _syncService.syncAll(userId);
    await loadDataForSelectedMonth();
    await loadReportData();
  }

  static const Duration _kolkataOffset = Duration(hours: 5, minutes: 30);

  final String userId;
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final SyncService _syncService = SyncService.instance;

  String _selectedMonth = currentKolkataMonth;
  MonthlyCredit? _currentCredit;
  List<Expense> _expenses = [];
  List<Expense> _todayExpenses = [];
  bool _isLoading = false;
  bool _isSyncing = false;
  List<Expense> _reportExpenses = [];
  bool _isReportLoading = false;
  int _reportYear = kolkataNow.year;
  String? _reportMonth = currentKolkataMonth;
  DateTime? _reportDate;
  Timer? _dayChangeTimer;
  int _dataLoadVersion = 0;
  String _lastTodayKey = '';

  String get selectedMonth => _selectedMonth;
  MonthlyCredit? get currentCredit => _currentCredit;
  List<Expense> get expenses => _expenses;
  bool get isLoading => _isLoading;
  bool get isSyncing => _isSyncing;
  bool get isReportLoading => _isReportLoading;
  int get reportYear => _reportYear;
  String? get reportMonth => _reportMonth;
  DateTime? get reportDate => _reportDate;

  static DateTime get kolkataNow => DateTime.now().toUtc().add(_kolkataOffset);

  static String kolkataDateKey(DateTime value) {
    final date = value.toUtc().add(_kolkataOffset);
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  static String get currentKolkataMonth {
    final date = kolkataNow;
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}';
  }

  String get todayLabel => DateFormat('EEEE, d MMMM yyyy').format(kolkataNow);

  List<Expense> get todayExpenses {
    final today = kolkataDateKey(kolkataNow);
    return _todayExpenses.where((expense) => kolkataDateKey(expense.timestamp) == today).toList();
  }

  double get todayTotalExpense =>
      todayExpenses.fold(0.0, (sum, item) => sum + item.expenseAmount);

  List<Expense> get reportExpenses => _reportExpenses;

  double get reportTotalExpense =>
      _reportExpenses.fold(0.0, (sum, item) => sum + item.expenseAmount);

  double get totalCredit => _currentCredit?.creditAmount ?? 0.0;

  double get totalDebit {
    return _expenses.fold(0.0, (sum, item) => sum + item.expenseAmount);
  }

  double get remainingBalance => totalCredit - totalDebit;

  bool get isNegativeBalance => remainingBalance < 0;

  void setMonth(String month) {
    if (_selectedMonth != month) {
      _selectedMonth = month;
      loadDataForSelectedMonth();
    }
  }

  void setReportYear(int year) {
    if (_reportYear == year && _reportDate == null && _reportMonth == null) return;
    _reportYear = year;
    _reportMonth = null;
    _reportDate = null;
    loadReportData();
  }

  void setReportMonth(String month) {
    if (_reportMonth == month && _reportDate == null) return;
    _reportYear = int.tryParse(month.split('-').first) ?? _reportYear;
    _reportMonth = month;
    _reportDate = null;
    loadReportData();
  }

  void setReportDate(DateTime date) {
    _reportYear = date.year;
    _reportMonth = '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}';
    _reportDate = DateTime.utc(date.year, date.month, date.day);
    loadReportData();
  }

  void clearReportDate() {
    if (_reportDate == null) return;
    _reportDate = null;
    loadReportData();
  }

  Future<void> loadDataForSelectedMonth() async {
    final loadVersion = ++_dataLoadVersion;
    _isLoading = true;
    notifyListeners();

    try {
      final credit = await _dbHelper.getMonthlyCredit(userId, _selectedMonth);
      final expenses = await _dbHelper.getExpensesForMonth(userId, _selectedMonth);
      final currentMonthExpenses = await _dbHelper.getExpensesForMonth(userId, currentKolkataMonth);
        debugPrint('[ExpenseProvider] SQLite expenses fetched: ${expenses.length} for $userId/$_selectedMonth; '
          'today source: ${currentMonthExpenses.length}');
      final today = kolkataDateKey(kolkataNow);
      final todayExpenses = currentMonthExpenses
          .where((expense) => kolkataDateKey(expense.timestamp) == today)
          .toList();
      if (loadVersion == _dataLoadVersion) {
        _currentCredit = credit;
        _expenses = expenses;
        _todayExpenses = todayExpenses;
        debugPrint('[ExpenseProvider] Kolkata date: $today; today matches: ${todayExpenses.length}; '
          'total: ${todayExpenses.fold<double>(0, (sum, item) => sum + item.expenseAmount)}');
      }
    } catch (e) {
      debugPrint('[ExpenseProvider] Error loading month data: $e');
    } finally {
      if (loadVersion == _dataLoadVersion) _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadReportData() async {
    _isReportLoading = true;
    notifyListeners();

    try {
      final source = _reportMonth == null
          ? await _dbHelper.getExpensesForYear(userId, _reportYear)
          : await _dbHelper.getExpensesForMonth(userId, _reportMonth!);
      if (_reportDate != null) {
        final dateKey = kolkataDateKey(_reportDate!);
        _reportExpenses = source
            .where((expense) => kolkataDateKey(expense.timestamp) == dateKey)
            .toList();
      } else {
        _reportExpenses = source;
      }
    } catch (e) {
      debugPrint('[ExpenseProvider] Error loading report data: $e');
      _reportExpenses = [];
    } finally {
      _isReportLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateMonthlyCredit(double amount) async {
    try {
      await _dbHelper.setMonthlyCredit(userId, _selectedMonth, amount);
      _currentCredit = await _dbHelper.getMonthlyCredit(userId, _selectedMonth);
      notifyListeners();
      
      // Attempt background sync to Firestore
      _syncService.syncAll();
    } catch (e) {
      debugPrint('[ExpenseProvider] Error updating credit: $e');
    }
  }

  Future<bool> addExpense({
    required String itemName,
    required double amount,
    DateTime? timestamp,
  }) async {
    try {
      final now = (timestamp ?? DateTime.now()).toUtc();
      final expenseMonth = _monthForKolkataDate(now);
      if (_selectedMonth != expenseMonth) {
        _selectedMonth = expenseMonth;
      }
      final newExpense = Expense(
        userId: userId,
        month: expenseMonth,
        itemName: itemName.trim(),
        expenseAmount: amount,
        timestamp: now,
        isSynced: false,
      );

      final rowId = await _dbHelper.insertExpense(newExpense);
      final savedExpense = newExpense.copyWith(id: rowId);
        debugPrint('[ExpenseProvider] Saved expense locally: id=$rowId user=$userId '
          'date=${savedExpense.timestamp.toIso8601String()} amount=${savedExpense.expenseAmount}');
      if (kolkataDateKey(savedExpense.timestamp) == kolkataDateKey(kolkataNow)) {
        _todayExpenses = [savedExpense, ..._todayExpenses];
        notifyListeners();
      }
      await loadDataForSelectedMonth();
      await loadReportData();
      notifyListeners();

      await _syncService.syncAll(userId);
      await loadDataForSelectedMonth();
      await loadReportData();
      return true;
    } catch (e) {
      debugPrint('[ExpenseProvider] Error adding expense: $e');
      return false;
    }
  }

  Future<bool> deleteExpense(int id) async {
    try {
      final expense = await _dbHelper.getExpense(id, userId);
      if (expense == null) return false;
      await _dbHelper.deleteExpense(id, userId);
      if (expense.firebaseId != null && expense.firebaseId!.isNotEmpty) {
        await _dbHelper.addDeletedExpense(userId, expense.firebaseId!);
      }
      debugPrint('[ExpenseProvider] Deleted expense locally: id=$id user=$userId '
          'firebaseId=${expense.firebaseId ?? 'pending'}');
      await loadDataForSelectedMonth();
      await loadReportData();
      await _syncService.syncAll(userId);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[ExpenseProvider] Error deleting expense: $e');
      return false;
    }
  }

  Future<void> triggerManualSync() async {
    _isSyncing = true;
    notifyListeners();

    await _syncService.syncAll();
    await loadDataForSelectedMonth();
    await loadReportData();

    _isSyncing = false;
    notifyListeners();
  }

  // Returns item-wise aggregated amounts for the selected month
  Map<String, double> getItemWiseTotals() {
    final Map<String, double> map = {};
    for (final expense in _expenses) {
      final item = expense.itemName;
      map[item] = (map[item] ?? 0.0) + expense.expenseAmount;
    }
    return map;
  }

  Future<List<String>> getAvailableMonths() async {
    final allCredits = await _dbHelper.getAllMonthlyCredits(userId);
    final allExpenses = await _dbHelper.getAllExpenses(userId);

    final Set<String> months = {currentKolkataMonth};
    for (final c in allCredits) {
      months.add(c.month);
    }
    for (final e in allExpenses) {
      months.add(e.month);
    }

    final list = months.toList();
    list.sort((a, b) => b.compareTo(a)); // Newest first
    return list;
  }

  String _monthForKolkataDate(DateTime value) {
    final date = value.toUtc().add(_kolkataOffset);
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _dayChangeTimer?.cancel();
    super.dispose();
  }
}
