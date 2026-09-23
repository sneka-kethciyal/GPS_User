import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'database_helper.dart';
import '../models/expense.dart';

class SyncService {
  static final SyncService instance = SyncService._init();
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  bool _isSyncing = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  SyncService._init();

  void initialize() {
    // Monitor network changes to trigger sync when online
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        debugPrint('[SyncService] Network connected. Starting background sync...');
        syncAll();
      }
    });
  }

  void dispose() {
    _connectivitySubscription?.cancel();
  }

  Future<bool> hasInternetConnection() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.any((r) => r != ConnectivityResult.none);
    } catch (e) {
      return false;
    }
  }

  Future<void> syncAll([String? explicitUserId]) async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final isConnected = await hasInternetConnection();
      if (!isConnected) {
        debugPrint('[SyncService] Device is offline. Sync postponed.');
        return;
      }

      final userId = explicitUserId ??
          FirebaseAuth.instance.currentUser?.uid ??
          await _dbHelper.getSetting('current_user_id');

      if (userId == null || userId.isEmpty) {
        debugPrint('[SyncService] No active user ID found for sync.');
        return;
      }

      debugPrint('[SyncService] Starting sync for user: $userId');
      await _syncDeletedExpenses(userId);
      await _pullExpenses(userId);
      await _syncMonthlyCredits(userId);
      await _syncExpenses(userId);
      await _pullExpenses(userId);
      await _syncGeoLocations(userId);
      debugPrint('[SyncService] Sync completed successfully for user: $userId.');
    } catch (e, stack) {
      debugPrint('[SyncService] Sync error: $e\n$stack');
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _pullExpenses(String userId) async {
    try {
      final snapshot = await _firestore
          .collectionGroup('expenses')
          .where('user_id', isEqualTo: userId)
          .get();
      debugPrint('[SyncService] Firestore expenses fetched: ${snapshot.docs.length} '
          '(users/$userId/months/{YYYY-MM}/expenses; parent month document not required)');
      var imported = 0;
      for (final doc in snapshot.docs) {
        if (await _dbHelper.isExpenseDeleted(userId, doc.id)) continue;
        final month = doc.reference.parent.parent?.id ?? (doc.data()['month'] ?? '').toString();
        if (month.isEmpty) continue;
        final expense = Expense.fromFirestore(
          userId: userId,
          firebaseId: doc.id,
          data: doc.data(),
          monthFromPath: month,
        );
        await _dbHelper.upsertFirestoreExpense(expense);
        imported++;
        debugPrint('[SyncService] Imported expense ${doc.id}: '
            '${expense.timestamp.toIso8601String()} ₹${expense.expenseAmount}');
      }
      debugPrint('[SyncService] Firestore-to-SQLite expenses imported: $imported');
    } catch (e, stack) {
      debugPrint('[SyncService] Failed to pull Firestore expenses: $e\n$stack');
    }
  }

  Future<void> _syncDeletedExpenses(String userId) async {
    for (final deleted in await _dbHelper.getDeletedExpenses(userId)) {
      final firebaseId = deleted['firebase_id'] as String;
      try {
        final matches = await _firestore
            .collectionGroup('expenses')
            .where('user_id', isEqualTo: userId)
            .get();
        for (final doc in matches.docs.where((doc) => doc.id == firebaseId)) {
          await doc.reference.delete();
        }
        await _dbHelper.removeDeletedExpense(userId, firebaseId);
        debugPrint('[SyncService] Deleted Firestore expense $firebaseId');
      } catch (e) {
        debugPrint('[SyncService] Failed to delete Firestore expense $firebaseId: $e');
      }
    }
  }

  Future<void> _syncMonthlyCredits(String userId) async {
    final unsynced = await _dbHelper.getUnsyncedCredits(userId);
    if (unsynced.isEmpty) return;

    for (final credit in unsynced) {
      try {
        final docRef = _firestore
            .collection('users')
            .doc(userId)
            .collection('months')
            .doc(credit.month)
            .collection('credits')
            .doc('monthly_credit');
        await docRef.set({
          'user_id': userId,
          'month': credit.month,
          'credit_amount': credit.creditAmount,
          'transaction_date': Timestamp.fromDate(credit.createdAt),
          'updated_at': credit.createdAt.toIso8601String(),
          'app_name': 'Expense Tracker',
          'company': 'EBT Fusion Infotech',
        }, SetOptions(merge: true));

        if (credit.id != null) {
          await _dbHelper.markCreditSynced(credit.id!, userId, docRef.id);
        }
        debugPrint('[SyncService] Synced monthly credit for ${credit.month}');
      } catch (e) {
        debugPrint('[SyncService] Failed to sync monthly credit (${credit.month}): $e');
      }
    }
  }

  Future<void> _syncExpenses(String userId) async {
    final unsynced = await _dbHelper.getUnsyncedExpenses(userId);
    if (unsynced.isEmpty) return;

    for (final expense in unsynced) {
      try {
        final expenseCollection = _firestore
            .collection('users')
            .doc(userId)
            .collection('months')
            .doc(expense.month)
            .collection('expenses');
        final docRef = expense.firebaseId != null && expense.firebaseId!.isNotEmpty
          ? expenseCollection.doc(expense.firebaseId)
          : expenseCollection.doc('local_${expense.id ?? '${expense.timestamp.millisecondsSinceEpoch}_${expense.itemName.hashCode}'}');

        await docRef.set({
          'user_id': userId,
          'local_id': expense.id,
          'month': expense.month,
          'item_name': expense.itemName,
          'expense_amount': expense.expenseAmount,
          'transaction_date': Timestamp.fromDate(expense.timestamp),
          'timestamp': expense.timestamp.toIso8601String(),
          'app_name': 'Expense Tracker',
          'company': 'EBT Fusion Infotech',
        });

        if (expense.id != null) {
          await _dbHelper.markExpenseSynced(expense.id!, userId, docRef.id);
        }
        debugPrint('[SyncService] Synced expense "${expense.itemName}" (₹${expense.expenseAmount})');
      } catch (e) {
        debugPrint('[SyncService] Failed to sync expense (${expense.itemName}): $e');
      }
    }
  }

  Future<void> _syncGeoLocations(String userId) async {
    final unsynced = await _dbHelper.getUnsyncedGeoLocations(userId);
    if (unsynced.isEmpty) return;

    for (final location in unsynced) {
      try {
        if (location.syncId.isEmpty) {
          debugPrint(
            '[SyncService] Skipping location ${location.id}: missing sync_id',
          );
          continue;
        }

        final locationRef = _firestore
            .collection('users')
            .doc(userId)
            .collection('geo_locations')
            .doc(location.syncId);

        await locationRef.set({
          'user_id': userId,
          'local_id': location.id,
          'sync_id': location.syncId,
          'latitude': location.latitude,
          'longitude': location.longitude,
          'timestamp': location.timestamp.toIso8601String(),
          'captured_at_ms': location.timestamp.millisecondsSinceEpoch,
          'device_platform': defaultTargetPlatform.name,
          'app_name': 'Expense Tracker',
          'company': 'EBT Fusion Infotech',
        }, SetOptions(merge: true));

        if (location.id != null) {
          await _dbHelper.markGeoLocationSynced(location.id!, userId);
        }
        debugPrint(
          '[SyncService] Synced GPS ${location.syncId} (local_id=${location.id})',
        );
      } catch (e) {
        debugPrint(
          '[SyncService] Failed to sync location (${location.id}) for user $userId '
          'to users/$userId/geo_locations/${location.syncId}: $e',
        );
      }
    }

    // Clean up synced locations older than 30 days to keep local SQLite fast
    await _dbHelper.clearOldSyncedLocations(30);
  }
}
