import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_theme.dart';
import '../../data/services/auth_service.dart';
import '../../data/repositories/tour_repository.dart';
import '../../data/repositories/expense_repository.dart';
import '../../data/repositories/settlement_repository.dart';
import '../../data/services/balance_service.dart';
import '../../data/models/expense_model.dart';
import '../../data/models/settlement_model.dart';
import '../../data/models/tour_model.dart';
import '../../data/services/active_tour_cache_service.dart';
import '../../data/services/offline_expense_queue_service.dart';
import '../../data/services/user_cache_service.dart';
import '../expense/widgets/day_summary_table.dart';
import '../widgets/gradient_button.dart';
import '../widgets/app_bottom_nav_bar.dart';
import '../widgets/app_notification_sheet.dart';

class ReportScreen extends ConsumerWidget {
  final String? tourId;
  const ReportScreen({super.key, this.tourId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);
    final user = userAsync.value;
    final cachedTour = ActiveTourCacheService.getCachedActiveTour();
    final activeTourId = ref.watch(activeTourIdProvider);
    final effectiveTourId = tourId ??
        activeTourId ??
        user?.activeTourId ??
        cachedTour?.id ??
        ActiveTourCacheService.getActiveTourId();

    if (effectiveTourId == null) {
      if (userAsync.isLoading) {
        return const Scaffold(
            body: Center(child: CircularProgressIndicator()));
      }
      return const Scaffold(body: Center(child: Text('No active tour')));
    }

    final currentUserId =
        user?.uid ?? ref.watch(authStateProvider).value?.uid ?? '';
    final tourStream = ref.watch(tourStreamProvider(effectiveTourId));
    final membersStream = ref.watch(tourMembersStreamProvider(effectiveTourId));
    final expensesStream =
        ref.watch(approvedExpensesStreamProvider(effectiveTourId));
    final settlementsStream =
        ref.watch(tourSettlementsStreamProvider(effectiveTourId));

    final effectiveTour = tourStream.value ?? (cachedTour?.id == effectiveTourId ? cachedTour : null) ?? cachedTour;
    if (effectiveTour == null && tourStream.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final tour = effectiveTour ?? tourStream.value;
    if (tour == null) {
      if (tourStream.isLoading) {
        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: const Center(child: CircularProgressIndicator()),
        );
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/home');
          }
        }
      });
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final cachedMembers = ActiveTourCacheService.getCachedMembers(effectiveTourId);
    final rawMembers = membersStream.value ?? cachedMembers;
    final List<TourMemberModel> members;
    if (rawMembers.isNotEmpty) {
      members = rawMembers;
    } else {
      members = [];
      final ids = tour.memberIds.isNotEmpty
          ? tour.memberIds
          : (user?.uid.isNotEmpty == true ? [user!.uid] : <String>[]);
      for (final uid in ids) {
        final cached = UserCacheService.getUser(uid);
        members.add(
          TourMemberModel(
            userId: uid,
            displayName: cached?.displayName ??
                (uid == user?.uid ? (user?.displayName ?? 'You') : 'Member'),
            username: cached?.username ?? '',
            email: uid == user?.uid ? (user?.email ?? '') : '',
            photoUrl: cached?.photoUrl ??
                (uid == user?.uid ? user?.photoUrl : null),
            role: tour.isAdmin(uid) ? 'admin' : 'member',
            status: 'active',
            joinedAt: tour.createdAt,
            balance: 0.0,
            isOffline: uid.startsWith('offline_'),
          ),
        );
      }
    }

    ref.watch(localExpensesRefreshProvider);
    final cachedExpenses = ActiveTourCacheService.getCachedExpenses(effectiveTourId);
    final queuedExpenses = ref.watch(offlineExpenseQueueProvider).getQueuedExpenses(tourId: effectiveTourId);
    final deletedIds = ref.watch(offlineExpenseQueueProvider).getQueuedDeletedExpenseIds(tourId: effectiveTourId);
    final streamExpenses = expensesStream.value ?? [];

    final Map<String, ExpenseModel> allExpensesMap = {};
    for (final e in queuedExpenses) {
      if (!deletedIds.contains(e.id)) allExpensesMap[e.id] = e;
    }
    for (final e in cachedExpenses) {
      if (!deletedIds.contains(e.id)) {
        allExpensesMap.putIfAbsent(e.id, () => e);
      }
    }
    for (final e in streamExpenses) {
      if (!deletedIds.contains(e.id)) {
        allExpensesMap[e.id] = e;
      }
    }
    final expenses = allExpensesMap.values.where((e) => e.isApproved).toList();

    ref.watch(localSettlementsRefreshProvider);
    final cachedSettlements = ActiveTourCacheService.getCachedSettlements(effectiveTourId);
    final streamSettlements = settlementsStream.value ?? [];
    final Map<String, SettlementModel> settlementsMap = {};
    for (final s in streamSettlements) {
      settlementsMap[s.id] = s;
    }
    for (final s in cachedSettlements) {
      settlementsMap[s.id] = s;
    }
    final settlements = settlementsMap.values.toList();
    final approvedSettlements = settlements.where((s) => s.isApproved).toList();
    var balances = BalanceService.calculateBalances(members, expenses);
    balances = BalanceService.applySettlements(balances, approvedSettlements);
    final debts = BalanceService.simplifyDebts(balances, members);

    final totalSpent = expenses.fold(0.0, (sum, e) => sum + e.amount);

                return PopScope(
                  canPop: false,
                  onPopInvokedWithResult: (didPop, _) {
                    if (didPop) return;
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/home');
                    }
                  },
                  child: Scaffold(
                    appBar: AppBar(
                      automaticallyImplyLeading: false,
                      toolbarHeight: 64,
                      titleSpacing: 20,
                      title: const Text(
                        'Tour Report',
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                          color: AppColors.primaryTeal,
                        ),
                      ),
                      actions: [
                        IconButton(
                          tooltip: 'Share Report',
                          icon: const Icon(Icons.share_rounded,
                              color: AppColors.primaryTeal),
                          onPressed: () => _generateAndDownloadPdf(
                            context,
                            tour.name,
                            tour.startDate,
                            expenses,
                            members,
                            balances,
                            debts,
                            tour.currencySymbol,
                            totalSpent,
                            autoShare: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                                  _StatChip(
                                      label: 'Total Spent',
                                      value:
                                          '${tour.currencySymbol} ${totalSpent.toStringAsFixed(0)}'),
                                  const SizedBox(width: 12),
                                  _StatChip(
                                      label: 'Expenses',
                                      value: '${expenses.length}'),
                                  const SizedBox(width: 12),
                                  _StatChip(
                                      label: 'Members',
                                      value: '${members.length}'),
                                ],
                              ),
                            ],
                          ),
                        ).animate().fadeIn().scale(),

                        const SizedBox(height: 24),
                        Text('Expenses',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'Outfit')),
                        const SizedBox(height: 12),
                        ..._groupExpensesByDay(expenses, tour.startDate)
                            .map((g) {
                          return DaySummaryTable(
                            dayNumber: g.dayNumber,
                            date: g.date,
                            expenses: g.expenses,
                            currencySymbol: tour.currencySymbol,
                          );
                        }),
                        const SizedBox(height: 32),
                        GradientButton(
                          onPressed: () => _generateAndDownloadPdf(
                            context,
                            tour.name,
                            tour.startDate,
                            expenses,
                            members,
                            balances,
                            debts,
                            tour.currencySymbol,
                            totalSpent,
                          ),
                          label: 'Download PDF Report',
                          icon: Icons.download_rounded,
                        ).animate().fadeIn(delay: 200.ms),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                  bottomNavigationBar: TourBottomNavigationBar(
                    tour: tour,
                    isAdmin: tour.isAdmin(currentUserId),
                    currentUser: user,
                    membersCount: tour.memberIds.length,
                    currentIndex: -1,
                    onToursTap: () => context.push('/tours'),
                    onDashboardTap: () {
                      ref.read(activeTourIdOverrideProvider.notifier).state =
                          tour.id;
                      ActiveTourCacheService.setActiveTourId(tour.id);
                      context.go('/home');
                    },
                    onMembersTap: () =>
                        context.push('/tour/members?tourId=${tour.id}'),
                    onSettingsTap: tour.isAdmin(currentUserId)
                        ? () => context.push('/tour/settings?tourId=${tour.id}')
                        : null,
                  ),
                ),
              );
  }

  static List<({int dayNumber, DateTime date, List<ExpenseModel> expenses})>
      _groupExpensesByDay(List<ExpenseModel> expenses, DateTime tourStartDate) {
    final baseDate =
        DateTime(tourStartDate.year, tourStartDate.month, tourStartDate.day);
    final map = <DateTime, List<ExpenseModel>>{};

    for (final exp in expenses) {
      final d = DateTime(exp.date.year, exp.date.month, exp.date.day);
      map.putIfAbsent(d, () => []).add(exp);
    }

    final sortedDates = map.keys.toList()..sort();
    final result =
        <({int dayNumber, DateTime date, List<ExpenseModel> expenses})>[];

    for (final date in sortedDates) {
      final diffDays = date.difference(baseDate).inDays;
      final dayNumber = diffDays >= 0 ? diffDays + 1 : 1;
      final dayExpenses = map[date]!..sort((a, b) => a.date.compareTo(b.date));

      result.add((dayNumber: dayNumber, date: date, expenses: dayExpenses));
    }

    return result;
  }

  Future<void> _generateAndDownloadPdf(
    BuildContext context,
    String tourName,
    DateTime tourStartDate,
    List<ExpenseModel> expenses,
    List members,
    Map<String, double> balances,
    List debts,
    String currencySymbol,
    double totalSpent, {
    bool customLocation = false,
    bool autoShare = false,
  }) async {
    final pdf = pw.Document();
    final dayGroups = _groupExpensesByDay(expenses, tourStartDate);
    final pdfCurrency =
        (currencySymbol == '৳' || currencySymbol.contains('৳'))
            ? 'BDT'
            : currencySymbol;
    final multiPayerExpenses = expenses.where((e) => e.isMultiPayer).toList();
    final memberMap = {for (final m in members) m.userId: m.displayName};

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (ctx) => [
        pw.Text(tourName,
            style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        pw.Text(
            'Tour Expense Report — Generated ${DateFormat('MMM d, y').format(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
        pw.SizedBox(height: 16),
        pw.Divider(),
        pw.SizedBox(height: 12),
        pw.Text('SUMMARY',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
        pw.SizedBox(height: 6),
        pw.Text(
            'Total Spent: $pdfCurrency ${totalSpent.toStringAsFixed(2)}'),
        pw.Text('Total Expenses: ${expenses.length}'),
        pw.Text('Members: ${members.length}'),
        if (multiPayerExpenses.isNotEmpty) ...[
          pw.SizedBox(height: 10),
          pw.Text('MULTI-PAYER EXPENSE BREAKDOWN',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
          pw.SizedBox(height: 4),
          ...multiPayerExpenses.map((e) {
            final contribs = e.contributions.entries.map((entry) {
              final name = memberMap[entry.key] ?? entry.key;
              return '$name ($pdfCurrency ${entry.value.toStringAsFixed(2)})';
            }).join(', ');
            return pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 2),
              child: pw.Text('• ${e.title}: $contribs',
                  style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey800)),
            );
          }),
        ],

        pw.SizedBox(height: 16),
        pw.Text('WHO OWES WHOM',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
        pw.SizedBox(height: 6),
        if (debts.isEmpty)
          pw.Text('All settled!')
        else
          ...debts.map((d) => pw.Text(
              '${d.fromUserName} -> ${d.toUserName}: $pdfCurrency ${d.amount.toStringAsFixed(2)}')),
        pw.SizedBox(height: 20),
        pw.Text('EXPENSES',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
        pw.SizedBox(height: 8),
        ...dayGroups.expand((g) {
          final dayTotal = g.expenses.fold(0.0, (s, e) => s + e.amount);
          return [
            pw.Container(
              color: PdfColor.fromHex('00897B'),
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Day ${g.dayNumber} (${DateFormat('EEEE, MMM d').format(g.date)})',
                    style: pw.TextStyle(
                        color: PdfColors.white,
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 11),
                  ),
                  pw.Text(
                    'Total: $pdfCurrency ${dayTotal.toStringAsFixed(2)}',
                    style: pw.TextStyle(
                        color: PdfColors.white,
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 11),
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
                      child: pw.Text('Expense Item',
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text('Cost',
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text('Payment Made by',
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text('Added by',
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    ),
                  ],
                ),
                ...g.expenses.map((e) {
                  final payer = e.isMultiPayer
                      ? 'Multi (${e.paidByName})'
                      : e.paidByName.split(' ').first.toLowerCase();
                  final adder = e
                      .resolveAddedByName(memberMap[e.addedByUserId] ??
                          UserCacheService.getUser(e.addedByUserId)?.displayName)
                      .split(' ')
                      .first
                      .toLowerCase();
                  return pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(e.title,
                                style: const pw.TextStyle(fontSize: 9)),
                            if (e.isMultiPayer)
                              pw.Text(
                                e.contributions.entries
                                    .map((entry) =>
                                        '${memberMap[entry.key] ?? entry.key}: $pdfCurrency ${entry.value.toStringAsFixed(0)}')
                                    .join(', '),
                                style: const pw.TextStyle(
                                    fontSize: 7.5, color: PdfColors.grey700),
                              ),
                          ],
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(
                            '$pdfCurrency ${e.amount.toStringAsFixed(2)}',
                            textAlign: pw.TextAlign.right,
                            style: const pw.TextStyle(fontSize: 9)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(payer,
                            textAlign: pw.TextAlign.center,
                            style: const pw.TextStyle(fontSize: 9)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(adder,
                            textAlign: pw.TextAlign.center,
                            style: const pw.TextStyle(fontSize: 9)),
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

    final bytes = await pdf.save();
    final cleanName = tourName
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    final dateStr = DateFormat('yyyyMMdd').format(DateTime.now());
    final filename =
        '${cleanName.isNotEmpty ? cleanName : 'tour'}_report_$dateStr.pdf';

    File? tempFile;
    try {
      final tempDir = await getTemporaryDirectory();
      tempFile = File('${tempDir.path}/$filename');
      await tempFile.writeAsBytes(bytes, flush: true);
    } catch (e) {
      debugPrint('[PDF_EXPORT] Error writing temp file for share: $e');
    }

    if (autoShare) {
      if (tempFile != null && await tempFile.exists()) {
        try {
          await Share.shareXFiles(
            [XFile(tempFile.path, mimeType: 'application/pdf', name: filename)],
            subject: '$tourName Expense Report',
            text: 'Tour Expense Report: $tourName',
          );
          return;
        } catch (_) {}
      }
      await Printing.sharePdf(
        bytes: bytes,
        filename: filename,
        subject: '$tourName Expense Report',
      );
      return;
    }

    if (customLocation) {
      await Printing.layoutPdf(
        onLayout: (format) async => bytes,
        name: filename,
      );
      return;
    }

    try {
      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        final downloadsDir = await getDownloadsDirectory();
        if (downloadsDir != null) {
          final publicFile = File('${downloadsDir.path}/$filename');
          await publicFile.writeAsBytes(bytes, flush: true);
        }
      }
    } catch (e) {
      debugPrint('[PDF_EXPORT] Direct storage write failed: $e');
    }

    if (context.mounted) {
      showAppNotificationSheet(
        context,
        icon: Icons.picture_as_pdf_rounded,
        iconColor: AppColors.primaryTeal,
        title: 'PDF Report Ready',
        message:
            'Your tour expense report is ready.\n\nTap Download to save the PDF to your device, or Share to send it directly via WhatsApp or other apps.',
        primaryButtonText: 'Download',
        onPrimaryPressed: () async {
          await Printing.layoutPdf(
            onLayout: (format) async => bytes,
            name: filename,
          );
        },
        secondaryButtonText: 'Share',
        secondaryButtonTextColor: AppColors.primaryTeal,
        onSecondaryPressed: () async {
          final localTemp = tempFile;
          if (localTemp != null && await localTemp.exists()) {
            try {
              await Share.shareXFiles(
                [XFile(localTemp.path, mimeType: 'application/pdf', name: filename)],
                subject: '$tourName Expense Report',
                text: 'Tour Expense Report: $tourName',
              );
              return;
            } catch (_) {}
          }
          await Printing.sharePdf(
            bytes: bytes,
            filename: filename,
            subject: '$tourName Expense Report',
          );
        },
      );
    }
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
                fontFamily: 'Outfit', fontSize: 11, color: Colors.white70)),
      ],
    );
  }
}
