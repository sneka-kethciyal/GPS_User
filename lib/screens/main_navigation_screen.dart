import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'expense_tracker_screen.dart';
import 'monthly_report_screen.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    ExpenseTrackerScreen(),
    MonthlyReportScreen(),
  ];

  Future<AppUserProfile?> _loadProfile() async {
    return AuthService().loadCurrentUserProfile();
  }

  Future<void> _showProfileSheet() async {
    final profile = await _loadProfile();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 52,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.textMuted.withAlpha(80),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Account',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              _ProfileRow(
                label: 'Username',
                value:
                    profile?.username ??
                    FirebaseAuth.instance.currentUser?.email ??
                    'Unknown',
              ),
              _ProfileRow(
                label: 'Role',
                value: profile?.role ?? 'Not assigned',
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Expense Tracker'),
        actions: [
          IconButton(
            tooltip: 'Account',
            icon: const Icon(Icons.account_circle_rounded),
            onPressed: _showProfileSheet,
          ),
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => AuthService().logout(),
          ),
        ],
      ),
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppTheme.cardBackground,
          border: const Border(
            top: BorderSide(color: AppTheme.cardBorder, width: 1.2),
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.pastelLavender.withAlpha(12),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            backgroundColor: AppTheme.cardBackground,
            indicatorColor: AppTheme.pastelLavenderLight,
            elevation: 0,
            destinations: const [
              NavigationDestination(
                icon: Icon(
                  Icons.receipt_long_outlined,
                  color: AppTheme.textMuted,
                ),
                selectedIcon: Icon(
                  Icons.receipt_long_rounded,
                  color: AppTheme.pastelLavender,
                ),
                label: 'Tracker',
              ),
              NavigationDestination(
                icon: Icon(Icons.bar_chart_outlined, color: AppTheme.textMuted),
                selectedIcon: Icon(
                  Icons.bar_chart_rounded,
                  color: AppTheme.pastelLavender,
                ),
                label: 'Monthly Report',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  final String label;
  final String value;

  const _ProfileRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
