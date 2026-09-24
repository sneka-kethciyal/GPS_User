import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/tracking_schedule.dart';

class AppUserProfile {
  final String username;
  final String? group;
  final String? accountStatus;
  final TrackingSchedule? schedule;

  const AppUserProfile({
    required this.username,
    this.group,
    this.accountStatus,
    this.schedule,
  });
}

class AuthService {
  AuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    this.lastLoginWriter,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final Future<void> Function(String uid)? lastLoginWriter;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<UserCredential> login({
    required String username,
    required String password,
  }) async {
    final email = await resolveLoginEmail(username);
    final credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = credential.user;
    if (user != null) {
      try {
        await (lastLoginWriter ?? _writeLastLogin)(user.uid);
      } catch (error) {
        // A profile timestamp failure must not log the authenticated user out.
        debugPrint('[AuthService] Could not update last_login: $error');
      }
    }
    return credential;
  }

  static Map<String, dynamic> lastLoginUpdate() {
    return {'last_login': FieldValue.serverTimestamp()};
  }

  Future<void> _writeLastLogin(String uid) {
    return _firestore
        .collection('users')
        .doc(uid)
        .set(lastLoginUpdate(), SetOptions(merge: true));
  }

  Future<void> sendPasswordResetEmail(String username) async {
    final email = await resolveLoginEmail(username);
    return _auth.sendPasswordResetEmail(email: email);
  }

  Future<void> logout() => _auth.signOut();

  Future<User?> reloadCurrentUser() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return null;
    await currentUser.reload();
    return _auth.currentUser;
  }

  Future<AppUserProfile?> loadCurrentUserProfile([String? uid]) async {
    final userId = uid ?? _auth.currentUser?.uid;
    if (userId == null || userId.isEmpty) return null;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .get();
    if (!doc.exists || doc.data() == null) return null;
    return profileFromMap(doc.data()!);
  }

  Future<bool> isCurrentUserActive() async {
    final profile = await loadCurrentUserProfile();
    if (profile == null) return false;
    return isAccountActive({
      'account_status': profile.accountStatus ?? 'active',
    });
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'No logged-in user found.',
      );
    }

    final trimmedNewPassword = newPassword.trim();
    if (trimmedNewPassword.isEmpty) {
      throw FirebaseAuthException(
        code: 'invalid-password',
        message: 'Enter a new password.',
      );
    }
    if (trimmedNewPassword.length < 6) {
      throw FirebaseAuthException(
        code: 'weak-password',
        message: 'Password must be at least 6 characters long.',
      );
    }
    if (trimmedNewPassword != confirmPassword.trim()) {
      throw FirebaseAuthException(
        code: 'invalid-password',
        message: 'New password and confirmation do not match.',
      );
    }

    final email = user.email;
    if (email == null || email.isEmpty) {
      throw FirebaseAuthException(
        code: 'invalid-email',
        message: 'User email is unavailable for password reset.',
      );
    }

    final credential = EmailAuthProvider.credential(
      email: email,
      password: currentPassword,
    );

    await user.reauthenticateWithCredential(credential);
    await user.updatePassword(trimmedNewPassword);
  }

  Future<String> resolveLoginEmail(String username) async {
    final trimmedUsername = username.trim();
    if (trimmedUsername.isEmpty) return usernameToEmail(trimmedUsername);

    try {
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('username', isEqualTo: trimmedUsername)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        final email = query.docs.first.data()['email']?.toString();
        if (email != null && email.trim().isNotEmpty) return email.trim();
      }
    } catch (_) {
      // Fall back to the legacy username-to-email mapping below.
    }

    return usernameToEmail(trimmedUsername);
  }

  static String usernameToEmail(String username) {
    return '${username.trim().toLowerCase()}@ebtfusion.com';
  }

  static AppUserProfile profileFromMap(Map<String, dynamic> data) {
    final username =
        (data['username'] ?? data['login_id'] ?? data['email'] ?? '')
            .toString()
            .trim();
    final groupValue =
        data['group_id'] ??
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

    return AppUserProfile(
      username: username.isNotEmpty ? username : 'Unknown user',
      group: groupValue?.toString(),
      accountStatus: statusValue?.toString(),
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
    return true;
  }

  Future<void> updateUserProfilePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    await changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
      confirmPassword: confirmPassword,
    );
  }

  static String? validateUsername(String? value) {
    final username = value?.trim() ?? '';
    if (username.isEmpty) return 'Enter a username';
    if (!RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(username)) {
      return 'Use letters, numbers, dots, underscores, or hyphens';
    }
    return null;
  }

  static String? validatePassword(String? value) {
    if ((value ?? '').length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }
}
