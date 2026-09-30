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

  Future<void> _showChangePasswordDialog() async {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final formKey = GlobalKey<FormState>();
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    var obscureNew = true;
    var obscureConfirm = true;
    var isSubmitting = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              if (!(formKey.currentState?.validate() ?? false)) return;
              setDialogState(() => isSubmitting = true);
              try {
                await AuthService().changeManagedPassword(
                  currentPassword: currentPasswordController.text,
                  newPassword: newPasswordController.text,
                  confirmPassword: confirmPasswordController.text,
                );
                if (!context.mounted) return;
                Navigator.of(context).pop();
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Password updated successfully.'),
                  ),
                );
              } on ManagedAuthException catch (error) {
                if (!context.mounted) return;
                messenger.showSnackBar(SnackBar(content: Text(error.message)));
              } catch (_) {
                if (!context.mounted) return;
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Could not update password. Please try again.',
                    ),
                  ),
                );
              } finally {
                newPasswordController.clear();
                confirmPasswordController.clear();
                currentPasswordController.clear();
                if (context.mounted) {
                  setDialogState(() => isSubmitting = false);
                }
              }
            }

            return AlertDialog(
              title: const Text('Change password'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: currentPasswordController,
                      enabled: !isSubmitting,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      validator: AuthService.validateLoginPassword,
                      decoration: const InputDecoration(
                        labelText: 'Current password',
                        prefixIcon: Icon(Icons.lock_outline_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: newPasswordController,
                      enabled: !isSubmitting,
                      obscureText: obscureNew,
                      autofillHints: const [AutofillHints.newPassword],
                      validator: AuthService.validateNewPassword,
                      decoration: InputDecoration(
                        labelText: 'New password',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          onPressed: () =>
                              setDialogState(() => obscureNew = !obscureNew),
                          icon: Icon(
                            obscureNew
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: confirmPasswordController,
                      enabled: !isSubmitting,
                      obscureText: obscureConfirm,
                      autofillHints: const [AutofillHints.newPassword],
                      validator: (value) {
                        if ((value ?? '').trim().isEmpty) {
                          return 'Confirm your new password';
                        }
                        if (value!.trim() !=
                            newPasswordController.text.trim()) {
                          return 'Passwords do not match';
                        }
                        return null;
                      },
                      onFieldSubmitted: (_) => submit(),
                      decoration: InputDecoration(
                        labelText: 'Confirm password',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          onPressed: () => setDialogState(
                            () => obscureConfirm = !obscureConfirm,
                          ),
                          icon: Icon(
                            obscureConfirm
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: isSubmitting ? null : submit,
                  child: isSubmitting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Update password'),
                ),
              ],
            );
          },
        );
      },
    );

    newPasswordController.dispose();
    confirmPasswordController.dispose();
    currentPasswordController.dispose();
  }

  String? _passwordResetStatusMessage(PasswordResetRequestStatus? status) {
    if (status == null) return null;
    if (status.isPending) {
      return 'Password reset pending admin review.';
    }
    if (status.isCompleted) {
      return 'Your password reset was completed by an administrator.';
    }
    if (status.isRejected) {
      return 'Your password reset request was rejected. Contact your administrator.';
    }
    return null;
  }

  Future<void> _showProfileSheet() async {
    final profile = await _loadProfile();
    final resetStatus = await AuthService().loadPasswordResetRequestStatus();
    if (!mounted) return;

    final resetMessage = _passwordResetStatusMessage(resetStatus);

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
                value: profile?.username ?? 'Unknown',
              ),
              _ProfileRow(
                label: 'Role',
                value: profile?.role ?? 'Not assigned',
              ),
              if (resetMessage != null) ...[
                const SizedBox(height: 4),
                Text(
                  resetMessage,
                  style: TextStyle(
                    fontSize: 13,
                    color: resetStatus!.isRejected
                        ? Colors.red.shade700
                        : resetStatus.isCompleted
                        ? Colors.green.shade700
                        : AppTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    _showChangePasswordDialog();
                  },
                  icon: const Icon(Icons.password_rounded),
                  label: const Text('Change password'),
                ),
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
