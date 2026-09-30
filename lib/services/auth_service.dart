import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../models/tracking_schedule.dart';
import 'database_helper.dart';

class ManagedAuthException implements Exception {
  const ManagedAuthException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

class ManagedUserSession {
  const ManagedUserSession({required this.userId, required this.username});

  final String userId;
  final String username;
}

class AppUserProfile {
  final String username;
  final String? role;
  final String? group;
  final String? accountStatus;
  final TrackingSchedule? schedule;

  const AppUserProfile({
    required this.username,
    this.role,
    this.group,
    this.accountStatus,
    this.schedule,
  });
}

enum PasswordResetRequestOutcome { created, alreadyPending }

class PasswordResetRequestStatus {
  final String status;
  final DateTime? updatedAt;

  const PasswordResetRequestStatus({required this.status, this.updatedAt});

  bool get isPending => status.toUpperCase() == 'PENDING';
  bool get isCompleted => status.toUpperCase() == 'COMPLETED';
  bool get isRejected => status.toUpperCase() == 'REJECTED';
}

class AuthService {
  AuthService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  static const int _pbkdf2Iterations = 310000;
  static const String _pbkdf2Algorithm = 'PBKDF2-SHA256-310000';
  static final ValueNotifier<String?> managedUserId = ValueNotifier(null);

  final FirebaseFirestore _firestore;
  static const _sessionUserIdKey = 'current_user_id';
  static const _sessionUsernameKey = 'current_username';

  Future<ManagedUserSession> login({
    required String username,
    required String password,
  }) async {
    final trimmedUsername = username.trim().toLowerCase();
    if (trimmedUsername.isEmpty || password.isEmpty) {
      throw const ManagedAuthException(
        'invalid-credential',
        'Invalid username or password.',
      );
    }

    try {
      final users = await _firestore
          .collection('users')
          .where('username', isEqualTo: trimmedUsername)
          .limit(1)
          .get();
      if (users.docs.isEmpty) {
        debugPrint('[ManagedLogin] username lookup failed');
        throw const ManagedAuthException(
          'invalid-credential',
          'Invalid username or password.',
        );
      }

      final userDocument = users.docs.first;
      final userData = userDocument.data();
      debugPrint('[ManagedLogin] username lookup succeeded');
      debugPrint('[ManagedLogin] userId=${userDocument.id}');

      final passwordHash = userData['password_hash']?.toString() ?? '';
      final saltHex = userData['salt']?.toString() ?? '';
      final algorithm = userData['hash_algorithm']?.toString() ?? '';
      final salt = _decodeHex(saltHex);
      debugPrint(
        '[ManagedLogin] algorithm=$algorithm salt_length=${salt.length}',
      );

      if (algorithm != _pbkdf2Algorithm || salt.length != 16) {
        debugPrint('[ManagedLogin] password hash comparison=false');
        throw const ManagedAuthException(
          'invalid-credential',
          'Invalid username or password.',
        );
      }

      final generatedHash = await derivePasswordHash(password, salt);
      debugPrint(
        '[ManagedLogin] generated_hash_length=${generatedHash.length}',
      );
      final matches = _constantTimeEqualsHex(generatedHash, passwordHash);
      debugPrint('[ManagedLogin] password hash comparison=$matches');
      if (!matches) {
        throw const ManagedAuthException(
          'invalid-credential',
          'Invalid username or password.',
        );
      }

      if (!isAccountActive(userData)) {
        throw const ManagedAuthException(
          'user-disabled',
          'This account is inactive. Please contact your admin.',
        );
      }

      await userDocument.reference.update(lastLoginUpdate());

      final session = ManagedUserSession(
        userId: userDocument.id,
        username: userData['username']?.toString() ?? trimmedUsername,
      );
      await _saveSession(session);
      managedUserId.value = session.userId;
      return session;
    } on ManagedAuthException {
      rethrow;
    } on FirebaseException catch (error) {
      debugPrint('[ManagedLogin] Firestore login failed: ${error.code}');
      throw const ManagedAuthException(
        'network-request-failed',
        'Could not sign in. Check your connection and try again.',
      );
    }
  }

  static Future<String> derivePasswordHash(
    String password,
    List<int> salt,
  ) async {
    final key = await Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _pbkdf2Iterations,
      bits: 256,
    ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
    return _encodeHex(await key.extractBytes());
  }

  static List<int> _decodeHex(String value) {
    if (value.isEmpty ||
        value.length.isOdd ||
        !RegExp(r'^[0-9a-fA-F]+$').hasMatch(value)) {
      return const [];
    }
    return [
      for (var index = 0; index < value.length; index += 2)
        int.parse(value.substring(index, index + 2), radix: 16),
    ];
  }

  static String _encodeHex(List<int> bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  static bool _constantTimeEqualsHex(String actual, String expected) {
    final actualBytes = _decodeHex(actual);
    final expectedBytes = _decodeHex(expected);
    if (actualBytes.isEmpty || actualBytes.length != expectedBytes.length) {
      return false;
    }
    var difference = 0;
    for (var index = 0; index < actualBytes.length; index++) {
      difference |= actualBytes[index] ^ expectedBytes[index];
    }
    return difference == 0;
  }

  static Map<String, dynamic> lastLoginUpdate() {
    return {'last_login': FieldValue.serverTimestamp()};
  }

  Future<void> _saveSession(ManagedUserSession session) async {
    await DatabaseHelper.instance.setSetting(_sessionUserIdKey, session.userId);
    await DatabaseHelper.instance.setSetting(
      _sessionUsernameKey,
      session.username,
    );
  }

  Future<bool> isManagedUserLoggedIn() async {
    final userId = await DatabaseHelper.instance.getSetting(_sessionUserIdKey);
    return userId != null && userId.isNotEmpty;
  }

  Future<ManagedUserSession?> getCurrentManagedUser() async {
    final userId = await DatabaseHelper.instance.getSetting(_sessionUserIdKey);
    final username = await DatabaseHelper.instance.getSetting(
      _sessionUsernameKey,
    );
    if (userId == null ||
        userId.isEmpty ||
        username == null ||
        username.isEmpty) {
      return null;
    }
    return ManagedUserSession(userId: userId, username: username);
  }

  Future<ManagedUserSession?> restoreManagedUserSession() async {
    final session = await getCurrentManagedUser();
    if (session == null) {
      managedUserId.value = null;
      return null;
    }
    try {
      final users = await _firestore
          .collection('users')
          .where('username', isEqualTo: session.username.toLowerCase())
          .limit(1)
          .get();
      if (users.docs.isEmpty ||
          users.docs.first.id != session.userId ||
          !isAccountActive(users.docs.first.data())) {
        await logout();
        return null;
      }
      managedUserId.value = session.userId;
      return session;
    } on FirebaseException {
      await logout();
      return null;
    }
  }

  Future<void> logout() async {
    await DatabaseHelper.instance.setSetting(_sessionUserIdKey, '');
    await DatabaseHelper.instance.setSetting(_sessionUsernameKey, '');
    managedUserId.value = null;
  }

  static Map<String, dynamic> passwordResetRequestDocument({
    required String userId,
    required String username,
  }) {
    return {
      'userId': userId,
      'username': username.trim().toLowerCase(),
      'status': 'PENDING',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Future<PasswordResetRequestOutcome> requestPasswordReset(
    String username,
  ) async {
    final trimmedUsername = username.trim();
    if (trimmedUsername.isEmpty) {
      throw const ManagedAuthException('invalid-username', 'Enter a username.');
    }

    final user = await getUserByUsername(trimmedUsername);
    if (user == null) {
      throw const ManagedAuthException(
        'invalid-credential',
        'Invalid username or password.',
      );
    }

    final resolvedUserId = user['id'] as String;
    final profileUsername = (user['username'] ?? trimmedUsername).toString();
    final requestReference = _firestore
        .collection('password_reset_requests')
        .doc(resolvedUserId);
    await requestReference.set(
      passwordResetRequestDocument(
        userId: resolvedUserId,
        username: profileUsername,
      ),
    );
    return PasswordResetRequestOutcome.created;
  }

  Future<PasswordResetRequestStatus?> loadPasswordResetRequestStatus([
    String? uid,
  ]) async {
    final userId = uid ?? managedUserId.value ?? await getManagedUserId();
    if (userId == null || userId.isEmpty) return null;

    try {
      final doc = await _firestore
          .collection('password_reset_requests')
          .doc(userId)
          .get();
      if (!doc.exists || doc.data() == null) return null;

      final data = doc.data()!;
      final status = data['status']?.toString() ?? '';
      if (status.isEmpty) return null;

      final updatedAtRaw = data['updatedAt'];
      DateTime? updatedAt;
      if (updatedAtRaw is Timestamp) {
        updatedAt = updatedAtRaw.toDate();
      }

      return PasswordResetRequestStatus(status: status, updatedAt: updatedAt);
    } on FirebaseException catch (error) {
      debugPrint('[ManagedLogin] reset status unavailable: ${error.code}');
      return null;
    }
  }

  Future<String?> getManagedUserId() async {
    final userId = await DatabaseHelper.instance.getSetting(_sessionUserIdKey);
    return userId == null || userId.isEmpty ? null : userId;
  }

  Future<AppUserProfile?> loadCurrentUserProfile([String? uid]) async {
    final session = await getCurrentManagedUser();
    final userId = uid ?? session?.userId;
    final username = session?.username;
    if (userId == null || userId.isEmpty || username == null) return null;

    final users = await _firestore
        .collection('users')
        .where('username', isEqualTo: username.toLowerCase())
        .limit(1)
        .get();
    if (users.docs.isEmpty || users.docs.first.id != userId) return null;
    return profileFromMap(users.docs.first.data());
  }

  Future<bool> isCurrentUserActive() async {
    final session = await getCurrentManagedUser();
    if (session == null) return false;
    final users = await _firestore
        .collection('users')
        .where('username', isEqualTo: session.username.toLowerCase())
        .limit(1)
        .get();
    return users.docs.isNotEmpty &&
        users.docs.first.id == session.userId &&
        isAccountActive(users.docs.first.data());
  }

  Future<void> changeManagedPassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    final session = await getCurrentManagedUser();
    if (session == null) {
      throw const ManagedAuthException(
        'not-logged-in',
        'No logged-in user found.',
      );
    }

    final trimmedNewPassword = newPassword.trim();
    if (trimmedNewPassword.isEmpty) {
      throw const ManagedAuthException(
        'invalid-password',
        'Enter a new password.',
      );
    }
    if (trimmedNewPassword.length < 6) {
      throw const ManagedAuthException(
        'weak-password',
        'Password must be at least 6 characters long.',
      );
    }
    if (trimmedNewPassword != confirmPassword.trim()) {
      throw const ManagedAuthException(
        'invalid-password',
        'New password and confirmation do not match.',
      );
    }

    try {
      final users = await _firestore
          .collection('users')
          .where('username', isEqualTo: session.username.toLowerCase())
          .limit(1)
          .get();
      if (users.docs.isEmpty || users.docs.first.id != session.userId) {
        throw const ManagedAuthException(
          'invalid-credential',
          'Current password could not be verified.',
        );
      }

      final userData = users.docs.first.data();
      final currentSalt = _decodeHex(userData['salt']?.toString() ?? '');
      final currentHash = userData['password_hash']?.toString() ?? '';
      final currentMatches =
          userData['hash_algorithm'] == _pbkdf2Algorithm &&
          currentSalt.length == 16 &&
          _constantTimeEqualsHex(
            await derivePasswordHash(currentPassword, currentSalt),
            currentHash,
          );
      if (!currentMatches) {
        throw const ManagedAuthException(
          'invalid-credential',
          'Current password is incorrect.',
        );
      }

      final random = Random.secure();
      final newSalt = List<int>.generate(16, (_) => random.nextInt(256));
      final newHash = await derivePasswordHash(trimmedNewPassword, newSalt);
      await _firestore.collection('users').doc(session.userId).update({
        'password_hash': newHash,
        'salt': _encodeHex(newSalt),
        'hash_algorithm': _pbkdf2Algorithm,
        'passwordChangedAt': FieldValue.serverTimestamp(),
        'password_changed_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });
    } on ManagedAuthException {
      rethrow;
    } on FirebaseException catch (error) {
      debugPrint('[ManagedLogin] password update failed: ${error.code}');
      throw const ManagedAuthException(
        'permission-denied',
        'Password could not be changed. Firestore permissions may not allow this update.',
      );
    }
  }

  Future<Map<String, dynamic>?> getUserByUsername(String username) async {
    final normalized = username.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    final users = await _firestore
        .collection('users')
        .where('username', isEqualTo: normalized)
        .limit(1)
        .get();
    if (users.docs.isEmpty) return null;
    return {...users.docs.first.data(), 'id': users.docs.first.id};
  }

  static AppUserProfile profileFromMap(Map<String, dynamic> data) {
    final username =
        (data['username'] ?? data['login_id'] ?? data['email'] ?? '')
            .toString()
            .trim();
    final groupValue =
        data['group_id'] ??
        data['groupId'] ??
        data['group'] ??
        data['user_group'] ??
        data['group_name'];
    final statusValue =
        data['account_status'] ?? data['status'] ?? data['accountStatus'];
    final rawSchedule =
        data['assigned_schedule'] ??
        data['tracking_schedule'] ??
        data['schedule'] ??
        data['user_schedule'];
    final group = groupValue is Map
        ? (groupValue['group_id'] ?? groupValue['id'] ?? groupValue['name'])
              ?.toString()
        : groupValue?.toString();
    final accountStatus = statusValue is bool
        ? (statusValue ? 'active' : 'inactive')
        : statusValue?.toString();

    return AppUserProfile(
      username: username.isNotEmpty ? username : 'Unknown user',
      role: data['role']?.toString(),
      group: group,
      accountStatus: accountStatus,
      schedule: rawSchedule is Map<String, dynamic>
          ? TrackingSchedule.fromFirestore(rawSchedule)
          : rawSchedule is Map
          ? TrackingSchedule.fromFirestore(
              Map<String, dynamic>.from(rawSchedule),
            )
          : null,
    );
  }

  static bool isAccountActive(Map<String, dynamic> data) {
    final value =
        data['account_status'] ?? data['status'] ?? data['accountStatus'];
    if (value is bool) return value;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'active' ||
          normalized == 'enabled' ||
          normalized == 'approved';
    }
    return false;
  }

  static String? validateUsername(String? value) {
    final username = value?.trim() ?? '';
    if (username.isEmpty) return 'Enter a username';
    if (!RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(username)) {
      return 'Use letters, numbers, dots, underscores, or hyphens';
    }
    return null;
  }

  static String? validateLoginPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Enter a password';
    }
    return null;
  }

  static String? validateNewPassword(String? value) {
    if ((value ?? '').trim().length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }
}
