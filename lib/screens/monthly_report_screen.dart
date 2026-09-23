import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/expense.dart';
import '../providers/expense_provider.dart';
import '../theme/app_theme.dart';

class MonthlyReportScreen extends StatefulWidget {
  const MonthlyReportScreen({super.key});

  @override
  State<MonthlyReportScreen> createState() => _MonthlyReportScreenState();
}

class _MonthlyReportScreenState extends State<MonthlyReportScreen> {
  final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
  @override
  Widget build(BuildContext context) {
    final expenseProvider = Provider.of<ExpenseProvider>(context);
    final monthTitle = expenseProvider.reportDate != null
      ? DateFormat('d MMMM yyyy').format(expenseProvider.reportDate!)
      : expenseProvider.reportMonth != null
        ? DateFormat('MMMM yyyy').format(DateTime.parse('${expenseProvider.reportMonth}-01'))
        : 'Year ${expenseProvider.reportYear}';

    final totalDebit = expenseProvider.reportTotalExpense;
    final totalCredit = expenseProvider.totalCredit;
    final remaining = expenseProvider.remainingBalance;
    final isNegative = expenseProvider.isNegativeBalance;

    return Scaffold(
      backgroundColor: AppTheme.appBackground,
      appBar: AppBar(
        title: const Text(
          'Monthly Analytics & Report',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month_rounded, color: AppTheme.pastelLavender),
            tooltip: 'Select Month',
            onPressed: () => _pickMonth(context, expenseProvider),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Month Selector Pill Header
            _buildMonthSelector(context, expenseProvider, monthTitle),
            const SizedBox(height: 16),

            _buildReportFilters(context, expenseProvider),
            const SizedBox(height: 20),

            // 2. Financial Metrics Grid
            _buildMetricsGrid(context, totalCredit, totalDebit, remaining, isNegative),
            const SizedBox(height: 20),

            // Filtered expenses
            if (expenseProvider.isReportLoading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator(color: AppTheme.pastelLavender)),
              )
            else if (expenseProvider.reportExpenses.isEmpty)
              _buildEmptyState(monthTitle)
            else
              _buildTransactionAudit(context, expenseProvider.reportExpenses),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildReportFilters(BuildContext context, ExpenseProvider provider) {
    final currentYear = ExpenseProvider.kolkataNow.year;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        DropdownButton<int>(
          value: provider.reportYear,
          items: List.generate(16, (index) => currentYear - 10 + index)
              .map((year) => DropdownMenuItem(value: year, child: Text('$year')))
              .toList(),
          onChanged: (year) {
            if (year != null) provider.setReportYear(year);
          },
        ),
        DropdownButton<String>(
          value: provider.reportMonth,
          hint: const Text('All months'),
          items: List.generate(12, (index) {
            final month = '${provider.reportYear.toString().padLeft(4, '0')}-${(index + 1).toString().padLeft(2, '0')}';
            return DropdownMenuItem(
              value: month,
              child: Text(DateFormat('MMM').format(DateTime(provider.reportYear, index + 1))),
            );
          }),
          onChanged: (month) {
            if (month != null) provider.setReportMonth(month);
          },
        ),
        OutlinedButton.icon(
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: provider.reportDate ?? ExpenseProvider.kolkataNow,
              firstDate: DateTime(2020),
              lastDate: DateTime(2035),
            );
            if (picked != null) provider.setReportDate(picked);
          },
          icon: const Icon(Icons.event_rounded, size: 16),
          label: Text(provider.reportDate == null ? 'Specific date' : DateFormat('d MMM').format(provider.reportDate!)),
        ),
        if (provider.reportDate != null)
          IconButton(
            tooltip: 'Clear date filter',
            onPressed: provider.clearReportDate,
            icon: const Icon(Icons.clear_rounded),
          ),
      ],
    );
  }

  Widget _buildEmptyState(String period) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        children: [
          const Icon(Icons.receipt_long_rounded, size: 38, color: AppTheme.pastelLavender),
          const SizedBox(height: 12),
          Text('No expenses for $period', style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
          const SizedBox(height: 4),
          const Text('Try another date, month, or year.', style: TextStyle(color: AppTheme.textMuted)),
        ],
      ),
    );
  }

  Future<void> _pickMonth(BuildContext context, ExpenseProvider provider) async {
    final availableMonths = await provider.getAvailableMonths();
    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
                  child: const Icon(Icons.date_range_rounded, color: AppTheme.pastelLavender, size: 20),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Select Report Month',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ListView.builder(
              shrinkWrap: true,
              itemCount: availableMonths.length,
              itemBuilder: (context, idx) {
                final m = availableMonths[idx];
                final date = DateTime.tryParse('$m-01') ?? DateTime.now();
                final label = DateFormat('MMMM yyyy').format(date);
                final isSelected = m == provider.selectedMonth;

                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    color: isSelected ? AppTheme.pastelLavenderLight : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ListTile(
                    leading: Icon(
                      Icons.calendar_today_rounded,
                      color: isSelected ? AppTheme.pastelLavender : AppTheme.textMuted,
                      size: 20,
                    ),
                    title: Text(
                      label,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected ? AppTheme.pastelLavender : AppTheme.textPrimary,
                      ),
                    ),
                    trailing: isSelected ? const Icon(Icons.check_circle_rounded, color: AppTheme.pastelLavender) : null,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    onTap: () {
                      provider.setReportMonth(m);
                      Navigator.pop(ctx);
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthSelector(BuildContext context, ExpenseProvider provider, String title) {
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
                  color: AppTheme.pastelBlueLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.analytics_rounded, color: AppTheme.pastelBlue, size: 22),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Report for Period', style: TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w500)),
                  Text(
                    title,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                  ),
                ],
              ),
            ],
          ),
          OutlinedButton.icon(
            onPressed: () => _pickMonth(context, provider),
            icon: const Icon(Icons.filter_list_rounded, size: 16, color: AppTheme.pastelLavender),
            label: const Text('Change', style: TextStyle(fontSize: 13, color: AppTheme.pastelLavender, fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppTheme.pastelLavenderLight, width: 1.5),
              backgroundColor: AppTheme.pastelLavenderLight.withAlpha(120),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsGrid(
    BuildContext context,
    double totalCredit,
    double totalDebit,
    double remaining,
    bool isNegative,
  ) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                title: 'Total Credit',
                value: currencyFormat.format(totalCredit),
                icon: Icons.account_balance_wallet_rounded,
                accentColor: const Color(0xFF059669),
                bgColor: AppTheme.pastelMintLight,
                borderColor: AppTheme.pastelMint.withAlpha(80),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricTile(
                title: 'Total Debit',
                value: currencyFormat.format(totalDebit),
                icon: Icons.payments_outlined,
                accentColor: const Color(0xFFDC2626),
                bgColor: AppTheme.pastelCoralLight,
                borderColor: AppTheme.pastelCoral.withAlpha(80),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: isNegative ? const Color(0xFFFFF1F2) : const Color(0xFFECFDF5),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isNegative ? AppTheme.pastelCoral.withAlpha(140) : AppTheme.pastelMint.withAlpha(140),
              width: 1.4,
            ),
            boxShadow: [
              BoxShadow(
                color: (isNegative ? AppTheme.pastelCoral : AppTheme.pastelMint).withAlpha(12),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isNegative ? 'NET DEFICIT / OVER BUDGET' : 'NET REMAINING BALANCE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      color: isNegative ? const Color(0xFFE11D48) : const Color(0xFF059669),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    currencyFormat.format(remaining),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: isNegative ? const Color(0xFFDC2626) : const Color(0xFF059669),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isNegative ? AppTheme.pastelCoral.withAlpha(40) : AppTheme.pastelMint.withAlpha(40),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isNegative ? Icons.trending_down_rounded : Icons.trending_up_rounded,
                  color: isNegative ? const Color(0xFFDC2626) : const Color(0xFF059669),
                  size: 26,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetricTile({
    required String title,
    required String value,
    required IconData icon,
    required Color accentColor,
    required Color bgColor,
    required Color borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: accentColor.withAlpha(8),
            blurRadius: 10,
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
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: accentColor),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: accentColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionAudit(BuildContext context, List<Expense> expenses) {
    if (expenses.isEmpty) return const SizedBox();

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.pastelPinkLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.history_rounded, color: AppTheme.pastelPink, size: 18),
              ),
              const SizedBox(width: 8),
              const Text(
                'Expenses',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: expenses.length,
            separatorBuilder: (context, index) => const Divider(color: AppTheme.cardBorder, height: 14),
            itemBuilder: (ctx, idx) {
              final exp = expenses[idx];
              final dateStr = DateFormat('MMM dd, yyyy • hh:mm a').format(exp.timestamp);

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exp.itemName,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppTheme.textPrimary),
                      ),
                      const SizedBox(height: 3),
                      Text(dateStr, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                    ],
                  ),
                  Text(
                    '-${currencyFormat.format(exp.expenseAmount)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFDC2626),
                      fontSize: 14,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
