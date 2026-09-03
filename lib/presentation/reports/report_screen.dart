import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../data/services/auth_service.dart';
import '../../data/repositories/tour_repository.dart';
import '../../data/repositories/expense_repository.dart';
import '../../data/repositories/settlement_repository.dart';
import '../../data/services/balance_service.dart';
import '../../data/models/expense_model.dart';
import '../expense/widgets/day_summary_table.dart';
import '../widgets/gradient_button.dart';

class ReportScreen extends ConsumerWidget {
  const ReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    if (user == null || user.activeTourId == null) {
      return const Scaffold(body: Center(child: Text('No active tour')));
    }
    final tourId = user.activeTourId!;

    final tourStream = ref.watch(tourStreamProvider(tourId));
    final membersStream = ref.watch(tourMembersStreamProvider(tourId));
    final expensesStream = ref.watch(approvedExpensesStreamProvider(tourId));
    final settlementsStream = ref.watch(tourSettlementsStreamProvider(tourId));

    return tourStream.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
      data: (tour) {
        if (tour == null) return const Scaffold();

        return membersStream.when(
          loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
          data: (members) => expensesStream.when(
            loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
            error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
            data: (expenses) => settlementsStream.when(
              loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
              error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
              data: (settlements) {
                final approvedSettlements =
                    settlements.where((s) => s.isApproved).toList();
                var balances = BalanceService.calculateBalances(members, expenses);
                balances = BalanceService.applySettlements(balances, approvedSettlements);
                final debts = BalanceService.simplifyDebts(balances, members);

                final totalSpent = expenses.fold(0.0, (sum, e) => sum + e.amount);

                // Group by category
                final byCategory = <String, double>{};
                for (final e in expenses) {
                  byCategory[e.category] =
                      (byCategory[e.category] ?? 0) + e.amount;
                }

                return Scaffold(
                  appBar: AppBar(
                    title: const Text('Tour Report'),
                    leading: IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      onPressed: () => context.pop(),
                    ),
                  ),
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Summary card
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: AppColors.primaryGradient,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(tour.name,
                                  style: const TextStyle(
                                      fontFamily: 'Outfit',
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white)),
                              const SizedBox(height: 4),
                              Text(
                                DateFormat('MMM d, y').format(tour.startDate) +
                                    (tour.endDate != null
                                        ? ' → ${DateFormat('MMM d, y').format(tour.endDate!)}'
                                        : ' → Present'),
                                style: const TextStyle(
                                    fontFamily: 'Outfit',
                                    color: Colors.white70,
                                    fontSize: 13),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  _StatChip(label: 'Total Spent',
                                      value: '${tour.currencySymbol} ${totalSpent.toStringAsFixed(0)}'),
                                  const SizedBox(width: 12),
                                  _StatChip(label: 'Expenses',
                                      value: '${expenses.length}'),
                                  const SizedBox(width: 12),
                                  _StatChip(label: 'Members',
                                      value: '${members.length}'),
                                ],
                              ),
                            ],
                          ),
                        ).animate().fadeIn().scale(),
                        const SizedBox(height: 24),

                        // By category
                        Text('By Category',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        ...byCategory.entries.map((e) {
                          final pct = totalSpent > 0
                              ? e.value / totalSpent
                              : 0.0;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              children: [
                                SizedBox(
                                    width: 120,
                                    child: Text(e.key,
                                        style: const TextStyle(
                                            fontFamily: 'Outfit',
                                            fontSize: 13))),
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: pct,
                                      minHeight: 8,
                                      backgroundColor: Theme.of(context)
                                          .dividerColor,
                                      valueColor:
                                          const AlwaysStoppedAnimation(
                                              AppColors.primaryBlue),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${tour.currencySymbol} ${e.value.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                      fontFamily: 'Outfit',
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13),
                                ),
                              ],
                            ),
                          );
                        }),
                        const SizedBox(height: 24),

                        // Daily Expense Ledger (Day 1, Day 2, etc.)
                        Text('Daily Expense Ledger',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700, fontFamily: 'Outfit')),
                        const SizedBox(height: 12),
                        ..._groupExpensesByDay(expenses, tour.startDate).map((g) {
                          return DaySummaryTable(
                            dayNumber: g.dayNumber,
                            date: g.date,
                            expenses: g.expenses,
                            currencySymbol: tour.currencySymbol,
                          );
                        }),
                        const SizedBox(height: 20),

                        // Final Balances
                        Text('Final Balances',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        ...members.map((m) {
                          final b = balances[m.userId] ?? 0.0;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text(m.displayName,
                                    style: const TextStyle(
                                        fontFamily: 'Outfit')),
                                Text(
                                  b == 0
                                      ? 'Settled'
                                      : '${b > 0 ? '+' : ''}${tour.currencySymbol} ${b.abs().toStringAsFixed(0)}',
                                  style: TextStyle(
                                    fontFamily: 'Outfit',
                                    fontWeight: FontWeight.w700,
                                    color: b > 0
                                        ? AppColors.positive
                                        : b < 0
                                            ? AppColors.negative
                                            : Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                        const SizedBox(height: 32),

                        GradientButton(
                          onPressed: () => _generateAndSharePdf(
                              context, tour.name, tour.startDate, expenses, members,
                              balances, debts, tour.currencySymbol,
                              byCategory, totalSpent),
                          label: 'Export PDF Report',
                          icon: Icons.picture_as_pdf_rounded,
                        ).animate().fadeIn(delay: 200.ms),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  static List<({int dayNumber, DateTime date, List<ExpenseModel> expenses})> _groupExpensesByDay(
      List<ExpenseModel> expenses, DateTime tourStartDate) {
    final baseDate = DateTime(tourStartDate.year, tourStartDate.month, tourStartDate.day);
    final map = <DateTime, List<ExpenseModel>>{};

    for (final exp in expenses) {
      final d = DateTime(exp.date.year, exp.date.month, exp.date.day);
      map.putIfAbsent(d, () => []).add(exp);
    }

    final sortedDates = map.keys.toList()..sort();
    final result = <({int dayNumber, DateTime date, List<ExpenseModel> expenses})>[];

    for (final date in sortedDates) {
      final diffDays = date.difference(baseDate).inDays;
      final dayNumber = diffDays >= 0 ? diffDays + 1 : 1;
      final dayExpenses = map[date]!..sort((a, b) => a.date.compareTo(b.date));

      result.add((dayNumber: dayNumber, date: date, expenses: dayExpenses));
    }

    return result;
  }

  Future<void> _generateAndSharePdf(
    BuildContext context,
    String tourName,
    DateTime tourStartDate,
    List<ExpenseModel> expenses,
    List members,
    Map<String, double> balances,
    List debts,
    String currencySymbol,
    Map<String, double> byCategory,
    double totalSpent,
  ) async {
    final pdf = pw.Document();
    final dayGroups = _groupExpensesByDay(expenses, tourStartDate);

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (ctx) => [
        pw.Text(tourName,
            style: pw.TextStyle(
                fontSize: 26, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        pw.Text('Tour Expense Report — Generated ${DateFormat('MMM d, y').format(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
        pw.SizedBox(height: 16),
        pw.Divider(),
        pw.SizedBox(height: 12),
        pw.Text('SUMMARY',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
        pw.SizedBox(height: 6),
        pw.Text('Total Spent: $currencySymbol ${totalSpent.toStringAsFixed(2)}'),
        pw.Text('Total Expenses: ${expenses.length}'),
        pw.Text('Members: ${members.length}'),
        pw.SizedBox(height: 16),
        pw.Text('EXPENSE BREAKDOWN BY CATEGORY',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
        pw.SizedBox(height: 6),
        ...byCategory.entries.map((e) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 3),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(e.key),
                  pw.Text('$currencySymbol ${e.value.toStringAsFixed(2)}'),
                ],
              ),
            )),
        pw.SizedBox(height: 16),
        pw.Text('FINAL BALANCES',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
        pw.SizedBox(height: 6),
        ...members.map((m) {
          final b = balances[m.userId] ?? 0.0;
          return pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 3),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(m.displayName),
                pw.Text(b == 0
                    ? 'Settled'
                    : '${b > 0 ? '+' : ''}$currencySymbol ${b.abs().toStringAsFixed(2)}'),
              ],
            ),
          );
        }),
        pw.SizedBox(height: 16),
        pw.Text('WHO OWES WHOM',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
        pw.SizedBox(height: 6),
        if (debts.isEmpty)
          pw.Text('All settled!')
        else
          ...debts.map((d) => pw.Text(
              '${d.fromUserName} → ${d.toUserName}: $currencySymbol ${d.amount.toStringAsFixed(2)}')),
        pw.SizedBox(height: 20),

        // SPREADSHEET DAY-BY-DAY TABLES
        pw.Text('DAILY EXPENSE LEDGER',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
        pw.SizedBox(height: 8),

        ...dayGroups.expand((g) {
          final dayTotal = g.expenses.fold(0.0, (s, e) => s + e.amount);
          return [
            pw.Container(
              color: PdfColor.fromHex('1E4E79'),
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Day ${g.dayNumber} (${DateFormat('EEEE, MMM d').format(g.date)})',
                    style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 11),
                  ),
                  pw.Text(
                    'Total: $currencySymbol ${dayTotal.toStringAsFixed(2)}',
                    style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 11),
                  ),
                ],
              ),
            ),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text('Expense Item', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text('Cost', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text('Payment Made by', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text('Notes', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    ),
                  ],
                ),
                ...g.expenses.map((e) {
                  final payer = e.paidByName.split(' ').first.toLowerCase();
                  final notes = e.description?.trim().isNotEmpty == true
                      ? e.description!.trim()
                      : (e.category != 'Other' ? e.category : '');
                  return pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(e.title, style: const pw.TextStyle(fontSize: 9)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text('$currencySymbol ${e.amount.toStringAsFixed(2)}', textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 9)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(payer, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 9)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(notes, style: const pw.TextStyle(fontSize: 9)),
                      ),
                    ],
                  );
                }),
              ],
            ),
            pw.SizedBox(height: 12),
          ];
        }),
      ],
    ));

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: '${tourName.replaceAll(' ', '_')}_report.pdf',
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;

  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: const TextStyle(
                fontFamily: 'Outfit',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white)),
        Text(label,
            style: const TextStyle(
                fontFamily: 'Outfit',
                fontSize: 11,
                color: Colors.white70)),
      ],
    );
  }
}
