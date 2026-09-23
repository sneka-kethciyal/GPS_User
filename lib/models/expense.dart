import 'package:cloud_firestore/cloud_firestore.dart';

class Expense {
  final int? id;
  final String userId;
  final String month; // Format: 'yyyy-MM'
  final String itemName;
  final double expenseAmount;
  final DateTime timestamp;
  final bool isSynced;
  final String? firebaseId;

  Expense({
    this.id,
    required this.userId,
    required this.month,
    required this.itemName,
    required this.expenseAmount,
    required this.timestamp,
    this.isSynced = false,
    this.firebaseId,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'user_id': userId,
      'month': month,
      'item_name': itemName,
      'expense_amount': expenseAmount,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'is_synced': isSynced ? 1 : 0,
      'firebase_id': firebaseId,
    };
  }

  factory Expense.fromMap(Map<String, dynamic> map) {
    return Expense(
      id: map['id'] as int?,
      userId: map['user_id'] as String,
      month: map['month'] as String,
      itemName: map['item_name'] as String,
      expenseAmount: (map['expense_amount'] as num).toDouble(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      isSynced: (map['is_synced'] as int? ?? 0) == 1,
      firebaseId: map['firebase_id'] as String?,
    );
  }

  factory Expense.fromFirestore({
    required String userId,
    required String firebaseId,
    required Map<String, dynamic> data,
    required String monthFromPath,
  }) {
    final rawTimestamp = data['transaction_date'] ??
        data['timestamp'] ??
        data['date'] ??
        data['createdAt'] ??
        data['created_at'];
    final amount = data['expense_amount'] ?? data['amount'] ?? data['value'];
    return Expense(
      userId: userId,
      month: monthFromPath,
      itemName: (data['item_name'] ?? data['itemName'] ?? data['description'] ?? 'Expense').toString(),
      expenseAmount: amount is num ? amount.toDouble() : double.tryParse(amount.toString()) ?? 0.0,
      timestamp: _parseTimestamp(rawTimestamp),
      isSynced: true,
      firebaseId: firebaseId,
    );
  }

  static DateTime _parseTimestamp(dynamic value) {
    if (value is Timestamp) return value.toDate().toUtc();
    if (value is DateTime) return value;
    if (value is num) {
      final milliseconds = value > 100000000000 ? value.toInt() : value.toInt() * 1000;
      return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
    }
    if (value is String) {
      final dateOnly = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value.trim());
      if (dateOnly != null) {
        return DateTime.utc(
          int.parse(dateOnly.group(1)!),
          int.parse(dateOnly.group(2)!),
          int.parse(dateOnly.group(3)!),
        );
      }
      return DateTime.tryParse(value)?.toUtc() ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  Map<String, dynamic> toFirestore() {
    return {
      'user_id': userId,
      'month': month,
      'item_name': itemName,
      'expense_amount': expenseAmount,
      'transaction_date': Timestamp.fromDate(timestamp),
      'timestamp': timestamp.toIso8601String(),
    };
  }

  Expense copyWith({
    int? id,
    String? userId,
    String? month,
    String? itemName,
    double? expenseAmount,
    DateTime? timestamp,
    bool? isSynced,
    String? firebaseId,
  }) {
    return Expense(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      month: month ?? this.month,
      itemName: itemName ?? this.itemName,
      expenseAmount: expenseAmount ?? this.expenseAmount,
      timestamp: timestamp ?? this.timestamp,
      isSynced: isSynced ?? this.isSynced,
      firebaseId: firebaseId ?? this.firebaseId,
    );
  }
}
