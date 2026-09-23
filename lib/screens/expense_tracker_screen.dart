import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/expense.dart';
import '../providers/expense_provider.dart';
import '../providers/location_provider.dart';
import '../theme/app_theme.dart';

class ExpenseTrackerScreen extends StatefulWidget {
  const ExpenseTrackerScreen({super.key});

  @override
  State<ExpenseTrackerScreen> createState() => _ExpenseTrackerScreenState();
}

class _ExpenseTrackerScreenState extends State<ExpenseTrackerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _itemNameController = TextEditingController();
  final _amountController = TextEditingController();
  final _creditController = TextEditingController();

  final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

  @override
  void dispose() {
    _itemNameController.dispose();
    _amountController.dispose();
    _creditController.dispose();
    super.dispose();
  }

  void _showSetCreditDialog(BuildContext context, double currentCredit) {
    _creditController.text = currentCredit > 0 ? currentCredit.toStringAsFixed(2) : '';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardBackground,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.pastelMintLight,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.account_balance_wallet_rounded, color: AppTheme.pastelMint, size: 24),
            ),
            const SizedBox(width: 12),
            const Text(
              'Set Monthly Credit',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppTheme.textPrimary),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the total allocated credit or budget for this month.',
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _creditController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 16),
              decoration: InputDecoration(
                labelText: 'Credit Amount (₹)',
                hintText: '0.00',
                prefixIcon: const Icon(Icons.attach_money_rounded, color: AppTheme.pastelMint),
                fillColor: AppTheme.surfaceMuted,
              ),
              autofocus: true,
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.textSecondary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final val = double.tryParse(_creditController.text);
              if (val != null && val >= 0) {
                Provider.of<ExpenseProvider>(context, listen: false).updateMonthlyCredit(val);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Updated credit to ${currencyFormat.format(val)}'),
                    backgroundColor: AppTheme.pastelMint,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.pastelLavender,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Save Credit'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitExpense(ExpenseProvider provider) async {
    if (_formKey.currentState!.validate()) {
      final itemName = _itemNameController.text.trim();
      final amount = double.parse(_amountController.text);

      final added = await provider.addExpense(
        itemName: itemName,
        amount: amount,
      );

      if (!added || !mounted) {
        if (mounted && !added) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not add expense. Please try again.')),
          );
        }
        return;
      }

      _itemNameController.clear();
      _amountController.clear();
      FocusScope.of(context).unfocus();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added expense: $itemName (${currencyFormat.format(amount)})'),
          backgroundColor: AppTheme.pastelLavender,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final expenseProvider = Provider.of<ExpenseProvider>(context);
    final locationProvider = Provider.of<LocationProvider>(context);

    final selectedDate = DateTime.tryParse('${expenseProvider.selectedMonth}-01') ?? DateTime.now();
    final monthLabel = DateFormat('MMMM yyyy').format(selectedDate);
    final todayExpenses = expenseProvider.todayExpenses;

    return Scaffold(
      backgroundColor: AppTheme.appBackground,
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.pastelLavenderLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Expense Tracker',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.pastelLavender,
                ),
              ),
            ),
            const SizedBox(height: 3),
            const Text(
              'Expense Tracker',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: expenseProvider.isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2, color: AppTheme.pastelLavender),
                  )
                : const Icon(Icons.sync_rounded, color: AppTheme.pastelLavender),
            tooltip: 'Sync with Firestore',
            onPressed: () => expenseProvider.triggerManualSync(),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppTheme.pastelLavender,
        backgroundColor: AppTheme.cardBackground,
        onRefresh: () => expenseProvider.triggerManualSync(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Month Header
              _buildMonthHeader(context, expenseProvider, monthLabel),
              const SizedBox(height: 12),

              // 2. Geo Tracking Status Banner
              _buildGeoStatusChip(context, locationProvider),
              const SizedBox(height: 16),

              // 3. Balance Summary Card (Pastel Gradient with dark readable typography)
              _buildBalanceSummaryCard(context, expenseProvider),
              const SizedBox(height: 20),

              _buildTodaySummary(expenseProvider),
              const SizedBox(height: 20),

              // 4. Add Expense Input Card
              _buildExpenseInputCard(context, expenseProvider),
              const SizedBox(height: 24),

              // 5. Monthly Expenses List Header
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Today · ${expenseProvider.todayLabel}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.pastelLavenderLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${todayExpenses.length} item(s)',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.pastelLavender,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 6. Expense Items List
              _buildExpenseList(expenseProvider, todayExpenses),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTodaySummary(ExpenseProvider provider) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.pastelBlueLight,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.pastelBlue.withAlpha(90)),
      ),
      child: Row(
        children: [
          const Icon(Icons.today_rounded, color: AppTheme.pastelBlue, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Today\'s expenses', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                Text(
                  currencyFormat.format(provider.todayTotalExpense),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                ),
              ],
            ),
          ),
          Text('${provider.todayExpenses.length} item(s)', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildMonthHeader(BuildContext context, ExpenseProvider provider, String monthLabel) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.cardBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: AppTheme.pastelLavender.withAlpha(10),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.pastelLavenderLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.calendar_month_rounded, color: AppTheme.pastelLavender, size: 20),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Active Period', style: TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w500)),
                  Text(
                    monthLabel,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                  ),
                ],
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.edit_calendar_rounded, color: AppTheme.pastelLavender, size: 22),
            tooltip: 'Change Month',
            onPressed: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: DateTime.tryParse('${provider.selectedMonth}-01') ?? now,
                firstDate: DateTime(2020),
                lastDate: DateTime(2035),
                initialDatePickerMode: DatePickerMode.year,
                builder: (ctx, child) {
                  return Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: const ColorScheme.light(
                        primary: AppTheme.pastelLavender,
                        onPrimary: Colors.white,
                        onSurface: AppTheme.textPrimary,
                      ),
                    ),
                    child: child!,
                  );
                },
              );
              if (picked != null) {
                final newMonth = DateFormat('yyyy-MM').format(picked);
                provider.setMonth(newMonth);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildGeoStatusChip(BuildContext context, LocationProvider locProvider) {
    final isEnabled = locProvider.isTrackingEnabled;
    final schedule = locProvider.schedule;
    final status = locProvider.scheduleStatus;
    final latest = locProvider.latestLocation;
    final isActivelyTracking = locProvider.isActivelyTracking;

    Color chipColor;
    Color borderColor;
    Color iconColor;
    IconData chipIcon;
    String titleText;
    String subtitleText;

    if (!isEnabled) {
      chipColor = AppTheme.pastelPeachLight;
      borderColor = AppTheme.pastelPeach.withAlpha(120);
      iconColor = const Color(0xFFD97706);
      chipIcon = Icons.location_off_rounded;
      titleText = 'GPS Tracking is Off';
      subtitleText = 'Enable tracking and configure your schedule.';
    } else if (isActivelyTracking) {
      chipColor = AppTheme.pastelMintLight;
      borderColor = AppTheme.pastelMint.withAlpha(120);
      iconColor = AppTheme.pastelMint;
      chipIcon = Icons.location_on_rounded;
      titleText = 'Tracking Active';
      subtitleText =
          'Every 15 min · ${schedule.formattedDaysSummary}, ${schedule.formattedTimeRange}';
    } else {
      // Enabled but outside schedule window
      chipColor = const Color(0xFFFFF7ED);
      borderColor = const Color(0xFFFBBF24).withAlpha(120);
      iconColor = const Color(0xFFD97706);
      chipIcon = Icons.schedule_rounded;
      titleText = status.statusMessage;
      subtitleText = status.unavailableReason ??
          '${schedule.formattedDaysSummary}, ${schedule.formattedTimeRange}';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: chipColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Row 1: icon + title + toggle ──────────────────────────────────
          Row(
            children: [
              Icon(chipIcon, size: 20, color: iconColor),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titleText,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isEnabled
                            ? AppTheme.textPrimary
                            : const Color(0xFF9A3412),
                      ),
                    ),
                    Text(
                      subtitleText,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: isEnabled,
                onChanged: (enable) async {
                  final error = await locProvider.toggleTracking(context, enable);
                  if (error != null && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(error),
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 4),
                        backgroundColor: const Color(0xFF9A3412),
                      ),
                    );
                  }
                },
              ),
            ],
          ),

          // ── Assigned schedule summary + Capture Now ────────────────────────
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.pastelBlueLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_clock_rounded, size: 14, color: AppTheme.pastelBlue),
                    const SizedBox(width: 6),
                    Text(
                      '${schedule.formattedDaysSummary} · ${schedule.formattedTimeRange}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.pastelBlue,
                      ),
                    ),
                  ],
                ),
              ),
              if (isEnabled && isActivelyTracking) ...[
                const Spacer(),
                TextButton.icon(
                  onPressed: locProvider.isCapturingNow
                      ? null
                      : () async {
                          await locProvider.captureNow();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Location captured and synced!'),
                                duration: Duration(seconds: 2),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: AppTheme.pastelBlue,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                  icon: locProvider.isCapturingNow
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location_rounded, size: 14),
                  label: Text(
                    locProvider.isCapturingNow ? 'Capturing...' : 'Capture Now',
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ],
          ),

          // ── Row 3: Latest location info ────────────────────────────────────
          if (isEnabled && latest != null) ...[
            const Divider(height: 14, thickness: 0.5),
            Row(
              children: [
                Icon(
                  latest.isSynced
                      ? Icons.cloud_done_rounded
                      : Icons.cloud_upload_outlined,
                  size: 13,
                  color: latest.isSynced ? AppTheme.pastelMint : Colors.orange,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    'Lat ${latest.latitude.toStringAsFixed(5)}, '
                    'Lng ${latest.longitude.toStringAsFixed(5)} · '
                    '${latest.isSynced ? 'Synced' : 'Pending sync'} · '
                    '${DateFormat('d MMM, h:mm a').format(latest.timestamp.toLocal())}',
                    style: TextStyle(
                      fontSize: 11,
                      color: latest.isSynced
                          ? AppTheme.textSecondary
                          : Colors.orange.shade800,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBalanceSummaryCard(BuildContext context, ExpenseProvider provider) {
    final isNegative = provider.isNegativeBalance;
    final totalCredit = provider.totalCredit;
    final totalDebit = provider.totalDebit;
    final remaining = provider.remainingBalance;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isNegative
              ? [const Color(0xFFFFF1F2), const Color(0xFFFEF2F2)]
              : [const Color(0xFFF5F3FF), const Color(0xFFEFF6FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isNegative ? AppTheme.pastelCoral.withAlpha(120) : AppTheme.pastelLavender.withAlpha(100),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (isNegative ? AppTheme.pastelCoral : AppTheme.pastelLavender).withAlpha(15),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Remaining Balance Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'REMAINING BALANCE',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                  color: isNegative ? const Color(0xFFE11D48) : AppTheme.pastelLavender,
                ),
              ),
              if (isNegative)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.pastelCoral.withAlpha(40),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.pastelCoral, width: 1),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 14),
                      SizedBox(width: 4),
                      Text(
                        'OVER BUDGET',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFDC2626)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Balance Amount (Dark, clear readable numbers)
          Text(
            currencyFormat.format(remaining),
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: isNegative ? const Color(0xFFDC2626) : const Color(0xFF059669),
            ),
          ),
          const SizedBox(height: 16),
          Divider(color: AppTheme.cardBorder.withAlpha(160), height: 1),
          const SizedBox(height: 16),

          // Total Credit & Total Debit Columns
          Row(
            children: [
              // Credit
              Expanded(
                child: InkWell(
                  onTap: () => _showSetCreditDialog(context, totalCredit),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.cardBackground,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.pastelMint.withAlpha(80)),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.pastelMint.withAlpha(10),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: AppTheme.pastelMintLight,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(Icons.arrow_downward_rounded, color: AppTheme.pastelMint, size: 14),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'Total Credit',
                              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.w600),
                            ),
                            const Spacer(),
                            const Icon(Icons.edit_rounded, size: 14, color: AppTheme.pastelLavender),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          currencyFormat.format(totalCredit),
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF059669)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Debit
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.cardBackground,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.pastelCoral.withAlpha(80)),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.pastelCoral.withAlpha(10),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: AppTheme.pastelCoralLight,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(Icons.arrow_upward_rounded, color: AppTheme.pastelCoral, size: 14),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Total Debit',
                            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        currencyFormat.format(totalDebit),
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFFDC2626)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseInputCard(BuildContext context, ExpenseProvider provider) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.cardBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: AppTheme.pastelLavender.withAlpha(10),
            blurRadius: 14,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.pastelLavenderLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.add_shopping_cart_rounded, color: AppTheme.pastelLavender, size: 18),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Add New Expense',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _itemNameController,
              style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w500),
              decoration: const InputDecoration(
                labelText: 'Item / Service Name',
                hintText: 'e.g. Fuel, Office Stationery, Lunch',
                prefixIcon: Icon(Icons.shopping_bag_outlined, color: AppTheme.pastelBlue),
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Please enter item name';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                labelText: 'Expense Amount (₹)',
                hintText: '0.00',
                prefixIcon: Icon(Icons.attach_money_rounded, color: AppTheme.pastelCoral),
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Please enter amount';
                }
                final parsed = double.tryParse(val);
                if (parsed == null || parsed <= 0) {
                  return 'Please enter a valid positive amount';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _submitExpense(provider),
                icon: const Icon(Icons.add_circle_outline_rounded, size: 19),
                label: const Text('Add Expense'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.pastelLavender,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpenseList(ExpenseProvider provider, List<Expense> expenses) {
    if (provider.isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: CircularProgressIndicator(color: AppTheme.pastelLavender),
        ),
      );
    }

    if (expenses.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppTheme.cardBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.cardBorder, width: 1.2),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.pastelLavenderLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.receipt_long_rounded, size: 36, color: AppTheme.pastelLavender),
            ),
            const SizedBox(height: 14),
            const Text(
              'No expenses recorded yet',
              style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary, fontSize: 15),
            ),
            const SizedBox(height: 4),
            const Text(
              'Add items above to start tracking today.',
              style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: expenses.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (ctx, idx) {
        final item = expenses[idx];
        final timeStr = DateFormat('dd MMM, hh:mm a').format(item.timestamp);

        // Soft pastel icon palette cycle
        final List<Color> pastelColors = [
          AppTheme.pastelLavender,
          AppTheme.pastelBlue,
          AppTheme.pastelPink,
          AppTheme.pastelPeach,
          AppTheme.pastelMint,
        ];
        final List<Color> pastelLightColors = [
          AppTheme.pastelLavenderLight,
          AppTheme.pastelBlueLight,
          AppTheme.pastelPinkLight,
          AppTheme.pastelPeachLight,
          AppTheme.pastelMintLight,
        ];

        final colorIndex = idx % pastelColors.length;
        final iconColor = pastelColors[colorIndex];
        final bgColor = pastelLightColors[colorIndex];

        return Dismissible(
          key: Key('expense_${item.id}'),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: AppTheme.pastelCoral,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
          ),
          onDismissed: (_) {
            if (item.id != null) {
              provider.deleteExpense(item.id!);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.cardBackground,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTheme.cardBorder, width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.pastelLavender.withAlpha(6),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.receipt_rounded, color: iconColor, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.itemName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            timeStr,
                            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            item.isSynced ? Icons.cloud_done_rounded : Icons.cloud_queue_rounded,
                            size: 14,
                            color: item.isSynced ? AppTheme.pastelMint : AppTheme.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            item.isSynced ? 'Synced' : 'SQLite',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: item.isSynced ? const Color(0xFF059669) : AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Text(
                  '-${currencyFormat.format(item.expenseAmount)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: Color(0xFFDC2626),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
