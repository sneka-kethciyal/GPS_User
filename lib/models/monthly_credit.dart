import 'package:cloud_firestore/cloud_firestore.dart';

class MonthlyCredit {
  final int? id;
  final String userId;
  final String month; // Format: 'yyyy-MM' (e.g., '2026-09')
  final double creditAmount;
  final DateTime createdAt;
  final bool isSynced;
  final String? firebaseId;

  MonthlyCredit({
    this.id,
    required this.userId,
    required this.month,
    required this.creditAmount,
    required this.createdAt,
    this.isSynced = false,
    this.firebaseId,
  });

  static double totalForMonth(Iterable<MonthlyCredit> credits) {
    return credits.fold<double>(
      0,
      (total, credit) => total + credit.creditAmount,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'user_id': userId,
      'month': month,
      'credit_amount': creditAmount,
      'created_at': createdAt.millisecondsSinceEpoch,
      'is_synced': isSynced ? 1 : 0,
      'firebase_id': firebaseId,
    };
  }

  factory MonthlyCredit.fromMap(Map<String, dynamic> map) {
    return MonthlyCredit(
      id: map['id'] as int?,
      userId: map['user_id'] as String,
      month: map['month'] as String,
      creditAmount: (map['credit_amount'] as num).toDouble(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      isSynced: (map['is_synced'] as int? ?? 0) == 1,
      firebaseId: map['firebase_id'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'user_id': userId,
      'month': month,
      'credit_amount': creditAmount,
      'transaction_date': Timestamp.fromDate(createdAt),
      'updated_at': createdAt.toIso8601String(),
    };
  }

  MonthlyCredit copyWith({
    int? id,
    String? userId,
    String? month,
    double? creditAmount,
    DateTime? createdAt,
    bool? isSynced,
    String? firebaseId,
  }) {
    return MonthlyCredit(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      month: month ?? this.month,
      creditAmount: creditAmount ?? this.creditAmount,
      createdAt: createdAt ?? this.createdAt,
      isSynced: isSynced ?? this.isSynced,
      firebaseId: firebaseId ?? this.firebaseId,
    );
  }
}
