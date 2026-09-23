import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/database_helper.dart';
import '../providers/expense_provider.dart';
import 'auth_screen.dart';
import 'main_navigation_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService().authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;
        if (user == null) return const AuthScreen();

        return FutureBuilder<bool>(
          future: AuthService().isCurrentUserActive(),
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final isActive = profileSnapshot.data ?? false;
            if (!isActive) {
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                await AuthService().logout();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('This account is inactive. Please contact your admin.'),
                    ),
                  );
                }
              });
              return const Scaffold(
                body: Center(
                  child: Text('Account inactive. Please contact admin.'),
                ),
              );
            }

            DatabaseHelper.instance.setSetting('current_user_id', user.uid);
            return ChangeNotifierProvider(
              create: (_) => ExpenseProvider(userId: user.uid),
              child: const MainNavigationScreen(),
            );
          },
        );
      },
    );
  }
}
