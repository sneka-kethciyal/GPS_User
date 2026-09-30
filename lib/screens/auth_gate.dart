import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/database_helper.dart';
import '../providers/expense_provider.dart';
import 'auth_screen.dart';
import 'main_navigation_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _loading = true;
  String? _profileCacheSignature;
  Future<void>? _profileCacheFuture;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    await AuthService().restoreManagedUserSession();
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: AuthService.managedUserId,
      builder: (context, userId, _) {
        if (userId == null || userId.isEmpty) {
          if (_loading) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return const AuthScreen();
        }

        return FutureBuilder<AppUserProfile?>(
          future: AuthService().loadCurrentUserProfile(userId),
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final profile = profileSnapshot.data;
            if (profile == null ||
                !AuthService.isAccountActive({
                  'account_status': profile.accountStatus,
                })) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                AuthService().logout();
              });
              return const Scaffold(
                body: Center(
                  child: Text('Account inactive. Please contact admin.'),
                ),
              );
            }

            final signature =
                '$userId|${profile.accountStatus}|${profile.group}';
            if (_profileCacheSignature != signature) {
              _profileCacheSignature = signature;
              _profileCacheFuture = _cacheManagedProfile(userId, profile);
            }
            return FutureBuilder<void>(
              future: _profileCacheFuture,
              builder: (context, cacheSnapshot) {
                if (cacheSnapshot.connectionState != ConnectionState.done) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }
                return ChangeNotifierProvider(
                  create: (_) => ExpenseProvider(userId: userId),
                  child: const MainNavigationScreen(),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _cacheManagedProfile(
    String userId,
    AppUserProfile profile,
  ) async {
    final db = DatabaseHelper.instance;
    await db.setSetting('current_user_id', userId);
    await db.setSetting(
      'schedule_account_status_$userId',
      (profile.accountStatus ?? '').toLowerCase(),
    );
    if (profile.group != null && profile.group!.isNotEmpty) {
      await db.setSetting('schedule_group_id_$userId', profile.group!);
    }
  }
}
