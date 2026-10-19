import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/math_expression_evaluator.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/active_tour_cache_service.dart';
import '../../data/services/offline_expense_queue_service.dart';
import '../../data/services/offline_tour_queue_service.dart';
import '../../data/services/user_cache_service.dart';
import '../../data/repositories/tour_repository.dart';
import '../../data/repositories/expense_repository.dart';
import '../../data/models/expense_model.dart';
import '../../data/models/tour_model.dart';
import '../widgets/gradient_button.dart';
import '../widgets/loading_overlay.dart';
import '../widgets/member_avatar.dart';
import '../widgets/app_notification_sheet.dart';

class LastExpenseDateNotifier extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;

  void setDate(DateTime? date) {
    state = date;
  }
}

final lastExpenseDateProvider =
    NotifierProvider<LastExpenseDateNotifier, DateTime?>(
  LastExpenseDateNotifier.new,
);

class AddExpenseScreen extends ConsumerStatefulWidget {
  final String? tourId;
  final ExpenseModel? existingExpense;
  const AddExpenseScreen({super.key, this.tourId, this.existingExpense});

  @override
  ConsumerState<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends ConsumerState<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _amountFocusNode = FocusNode();

  bool _isLoading = false;
  bool _submitted = false;

  int _splitMode = 0;
  DateTime _selectedDateTime = DateTime.now();

  bool _isMultiContributor = false;
  final Map<String, TextEditingController> _contributorControllers = {};

  String? _paidByUserId;
  String? _paidByName;
  List<String> _selectedMemberIds = [];
  final Map<String, TextEditingController> _customSplitControllers = {};
  List<TourMemberModel> _members = [];

  double get _totalCustomSplit => _customSplitControllers.values.fold(
      0.0, (sum, c) => sum + (double.tryParse(c.text.trim()) ?? 0.0));

  @override
  void initState() {
    super.initState();
    _amountFocusNode.addListener(() {
      if (!_amountFocusNode.hasFocus) {
        _evaluateAmount();
      }
      setState(() {});
    });

    if (widget.existingExpense != null) {
      final exp = widget.existingExpense!;
      _titleCtrl.text = exp.title;
      _amountCtrl.text = exp.amount
          .toStringAsFixed(exp.amount.truncateToDouble() == exp.amount ? 0 : 2);
      _selectedDateTime = exp.date;

      if (exp.payers != null && exp.payers!.length > 1) {
        _isMultiContributor = true;
        for (final entry in exp.payers!.entries) {
          _contributorControllers[entry.key] = TextEditingController(
            text: entry.value.toStringAsFixed(
                entry.value.truncateToDouble() == entry.value ? 0 : 2),
          );
        }
      } else {
        _isMultiContributor = false;
        _paidByUserId = exp.paidByUserId;
        _paidByName = exp.paidByName;
      }

      if (exp.splitType == SplitType.custom && exp.customSplits != null) {
        _splitMode = 1;
        for (final entry in exp.customSplits!.entries) {
          _customSplitControllers[entry.key] = TextEditingController(
            text: entry.value.toStringAsFixed(
                entry.value.truncateToDouble() == entry.value ? 0 : 2),
          );
        }
      } else if (exp.splitType == SplitType.selected) {
        _splitMode = 0;
        _selectedMemberIds = List.from(exp.splitAmong);
      } else {
        _splitMode = 0;
        _selectedMemberIds = List.from(exp.splitAmong);
      }
    } else {
      final remembered = ref.read(lastExpenseDateProvider);
      if (remembered != null) {
        _selectedDateTime = remembered;
      }
    }
  }

  void _evaluateAmount() {
    final text = _amountCtrl.text.trim();
    if (text.isEmpty) return;
    final result = MathExpressionEvaluator.tryEvaluate(text);
    if (result != null && result > 0) {
      final formatted = MathExpressionEvaluator.formatResult(result);
      if (formatted != text) {
        _amountCtrl.text = formatted;
        _amountCtrl.selection =
            TextSelection.collapsed(offset: formatted.length);
        setState(() {});
      }
    }
  }

  void _insertOperator(String op) {
    if (op == '=') {
      _evaluateAmount();
      return;
    }

    final text = _amountCtrl.text;
    final selection = _amountCtrl.selection;
    final insertText = (op == '+' || op == '−' || op == '×' || op == '÷')
        ? ' ${op == '−' ? '-' : (op == '×' ? '*' : (op == '÷' ? '/' : op))} '
        : op;

    if (selection.isValid && selection.start >= 0 && selection.end <= text.length) {
      final newText = text.replaceRange(selection.start, selection.end, insertText);
      final newOffset = selection.start + insertText.length;
      _amountCtrl.text = newText;
      _amountCtrl.selection = TextSelection.collapsed(offset: newOffset);
    } else {
      _amountCtrl.text = '$text$insertText';
      _amountCtrl.selection =
          TextSelection.collapsed(offset: _amountCtrl.text.length);
    }
    setState(() {});
  }

  @override
  void dispose() {
    _amountFocusNode.dispose();
    _titleCtrl.dispose();
    _amountCtrl.dispose();
    for (final ctrl in _contributorControllers.values) {
      ctrl.dispose();
    }
    for (final ctrl in _customSplitControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDateTime,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (pickedDate == null || !mounted) return;

    final normalized = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      12,
      0,
    );

    setState(() {
      _selectedDateTime = normalized;
    });
    ref.read(lastExpenseDateProvider.notifier).setDate(normalized);
  }

  double get _totalContributions {
    double sum = 0.0;
    for (final ctrl in _contributorControllers.values) {
      final val = MathExpressionEvaluator.tryEvaluate(ctrl.text.trim()) ??
          (double.tryParse(ctrl.text.trim()) ?? 0.0);
      sum += val;
    }
    return (sum * 100).round() / 100;
  }

  Future<void> _confirmDeleteExpense(
      String tourId, ExpenseModel expense) async {
    final confirm = await showAppConfirmationSheet(
      context,
      icon: Icons.delete_outline_rounded,
      iconColor: AppColors.danger,
      title: 'Delete Expense?',
      message:
          'Are you sure you want to delete "${expense.title}"? This cannot be undone.',
      confirmText: 'Delete',
      confirmColor: AppColors.danger,
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        await ref
            .read(expenseRepositoryProvider)
            .deleteExpense(tourId, expense.id);
        ref.invalidate(tourExpensesStreamProvider(tourId));
        ref.invalidate(approvedExpensesStreamProvider(tourId));
        ref.invalidate(singleExpenseStreamProvider((tourId: tourId, expenseId: expense.id)));
        ref.read(localExpensesRefreshProvider.notifier).bump();
        if (mounted) {
          await showAppNotificationSheet(
            context,
            icon: Icons.check_circle_outline_rounded,
            iconColor: AppColors.positive,
            title: 'Expense Deleted',
            message: 'Expense "${expense.title}" was deleted successfully.',
            primaryButtonText: 'Done',
          );
          if (mounted) {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          }
        }
      } catch (e) {
        if (mounted) {
          showAppNotificationSheet(
            context,
            icon: Icons.error_outline_rounded,
            iconColor: AppColors.danger,
            title: 'Delete Failed',
            message: 'Failed to delete expense: $e',
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  Future<void> _submit(
      TourModel tour, String currentUserId, String currentUserName, bool isAdmin) async {
    if (tour.isLockedForDeletion) {
      showAppNotificationSheet(
        context,
        icon: Icons.timer_outlined,
        iconColor: AppColors.danger,
        title: 'Tour Scheduled for Deletion',
        message:
            'This tour has been inactive and is scheduled for automatic permanent deletion. Adding expenses is strictly disabled.',
        primaryButtonText: 'Download PDF',
        onPrimaryPressed: () => context.push('/reports?tourId=${tour.id}'),
        secondaryButtonText: 'Close',
      );
      return;
    }
    _evaluateAmount();
    setState(() => _submitted = true);
    if (!_formKey.currentState!.validate()) return;

    final eval = MathExpressionEvaluator.tryEvaluate(_amountCtrl.text.trim());
    final totalAmount = eval ?? (double.tryParse(_amountCtrl.text.trim()) ?? 0.0);
    if (totalAmount <= 0) {
      showAppNotificationSheet(
        context,
        icon: Icons.warning_amber_rounded,
        iconColor: AppColors.warning,
        title: 'Invalid Amount',
        message: 'Please enter a valid expense amount.',
      );
      return;
    }

    Map<String, double>? payersMap;
    String finalPaidByUserId = _paidByUserId ?? currentUserId;
    String finalPaidByName = _paidByName ?? 'Member';

    if (_isMultiContributor) {
      final currentContributedTotal = _totalContributions;
      if ((currentContributedTotal - totalAmount).abs() > 0.05) {
        showAppNotificationSheet(
          context,
          icon: Icons.warning_amber_rounded,
          iconColor: AppColors.warning,
          title: 'Contribution Mismatch',
          message:
              'Sum of contributions (${tour.currencySymbol}${currentContributedTotal.toStringAsFixed(0)}) must equal total expense (${tour.currencySymbol}${totalAmount.toStringAsFixed(0)}).',
        );
        return;
      }

      payersMap = {};
      for (final entry in _contributorControllers.entries) {
        final amt = MathExpressionEvaluator.tryEvaluate(entry.value.text.trim()) ??
            (double.tryParse(entry.value.text.trim()) ?? 0.0);
        if (amt > 0) {
          payersMap[entry.key] = amt;
        }
      }

      if (payersMap.isEmpty) {
        showAppNotificationSheet(
          context,
          icon: Icons.warning_amber_rounded,
          iconColor: AppColors.warning,
          title: 'No Contributions',
          message: 'Please enter at least one contribution.',
        );
        return;
      }

      final highestEntry =
          payersMap.entries.reduce((a, b) => a.value > b.value ? a : b);
      finalPaidByUserId = highestEntry.key;

      final contributorNames = payersMap.keys.map((uid) {
        final match = _members.firstWhere((m) => m.userId == uid,
            orElse: () => _members.first);
        return match.displayName;
      }).toList();

      if (contributorNames.length == 1) {
        finalPaidByName = contributorNames.first;
      } else if (contributorNames.length == 2) {
        finalPaidByName = '${contributorNames[0]} & ${contributorNames[1]}';
      } else {
        finalPaidByName =
            '${contributorNames[0]} + ${contributorNames.length - 1} others';
      }
    } else {
      if (_paidByUserId == null) {
        showAppNotificationSheet(
          context,
          icon: Icons.warning_amber_rounded,
          iconColor: AppColors.warning,
          title: 'Select Payer',
          message: 'Please select who paid for this expense.',
        );
        return;
      }
      finalPaidByUserId = _paidByUserId!;
      finalPaidByName = _paidByName!;
      payersMap = {_paidByUserId!: totalAmount};
    }

    final category = widget.existingExpense?.category ?? 'General';

    List<String> splitMembers;
    Map<String, double>? customSplitsMap;
    SplitType splitType;

    if (_splitMode == 0) {
      if (_selectedMemberIds.length < _members.length && _selectedMemberIds.isNotEmpty) {
        splitType = SplitType.selected;
        splitMembers = _selectedMemberIds;
      } else {
        splitType = SplitType.equal;
        splitMembers = _members.map((m) => m.userId).toList();
      }
      customSplitsMap = null;
      if (splitMembers.isEmpty) {
        showAppNotificationSheet(
          context,
          icon: Icons.warning_amber_rounded,
          iconColor: AppColors.warning,
          title: 'Select Members',
          message: 'Select at least one member to share this expense.',
        );
        return;
      }
    } else {
      splitType = SplitType.custom;
      final parsedSplits = <String, double>{};
      for (final m in _members) {
        final val =
            double.tryParse(_customSplitControllers[m.userId]?.text.trim() ?? '');
        if (val != null && val > 0) {
          parsedSplits[m.userId] = val;
        }
      }
      final totalCustom =
          parsedSplits.values.fold<double>(0.0, (sum, v) => sum + v);
      if ((totalCustom - totalAmount).abs() > 0.05) {
        showAppNotificationSheet(
          context,
          icon: Icons.warning_amber_rounded,
          iconColor: AppColors.warning,
          title: 'Split Mismatch',
          message:
              'Custom split total (${tour.currencySymbol}${totalCustom.toStringAsFixed(2)}) must equal expense amount (${tour.currencySymbol}${totalAmount.toStringAsFixed(2)}).',
        );
        return;
      }
      splitMembers = parsedSplits.keys.toList();
      customSplitsMap = parsedSplits;
    }

    setState(() => _isLoading = true);
    try {
      if (widget.existingExpense != null) {
        final updatedExpense = widget.existingExpense!.copyWith(
          title: _titleCtrl.text.trim().isNotEmpty
              ? _titleCtrl.text.trim()
              : 'Expense',
          amount: totalAmount,
          category: category,
          paidByUserId: finalPaidByUserId,
          paidByName: finalPaidByName,
          payers: payersMap,
          splitType: splitType,
          splitAmong: splitMembers,
          customSplits: customSplitsMap,
          date: _selectedDateTime,
          status: isAdmin ? ExpenseStatus.approved : ExpenseStatus.pendingApproval,
        );

        // 1. Immediately cache and queue offline for instant UI updates
        await ref.read(offlineExpenseQueueProvider).queueExpense(updatedExpense);
        await ActiveTourCacheService.appendCachedExpense(tour.id, updatedExpense);
        ref.read(localExpensesRefreshProvider.notifier).bump();

        final updateData = {
          'title': updatedExpense.title,
          'amount': totalAmount,
          'category': category,
          'paidBy': finalPaidByUserId,
          'paidByUserId': finalPaidByUserId,
          'paidByName': finalPaidByName,
          'payers': payersMap,
          'splitType': splitType.name,
          'splitAmong': splitMembers,
          'customSplits': customSplitsMap,
          'date': _selectedDateTime,
          'description': null,
          'status': 'approved',
        };

        // 2. If online and not a local tour, attempt immediate Firestore update
        if (!tour.id.startsWith('local_')) {
          try {
            await ref.read(expenseRepositoryProvider).updateExpense(
                  tour.id,
                  widget.existingExpense!.id,
                  updateData,
                ).timeout(const Duration(milliseconds: 1500));
            // Succeeded online immediately, clean up local queue entry
            await ref.read(offlineExpenseQueueProvider).deleteQueuedExpense(widget.existingExpense!.id);
          } catch (err) {
            debugPrint('[UPDATE_EXPENSE] Firestore update timed out/offline (queued offline): $err');
          }
        }
        ref.read(lastExpenseDateProvider.notifier).setDate(_selectedDateTime);

        if (mounted) {
          await showAppNotificationSheet(
            context,
            icon: Icons.check_circle_outline_rounded,
            iconColor: AppColors.positive,
            title: 'Expense Updated',
            message: 'Expense "${_titleCtrl.text.trim().isNotEmpty ? _titleCtrl.text.trim() : 'Expense'}" updated successfully.',
            primaryButtonText: 'Done',
          );
          if (mounted) context.pop();
        }
        return;
      }

      final expenseRepo = ref.read(expenseRepositoryProvider);
      final expenseId = widget.existingExpense?.id ?? expenseRepo.generateExpenseId(tour.id);

      // Immutable addedBy tracking: original creator cannot be changed when editing an expense
      final originalAddedByUserId = widget.existingExpense?.addedByUserId;
      final effectiveAddedByUserId = (originalAddedByUserId != null && originalAddedByUserId.isNotEmpty)
          ? originalAddedByUserId
          : currentUserId;

      final originalAddedByName = widget.existingExpense?.addedByName;
      final effectiveAddedByName = (originalAddedByName != null && originalAddedByName.isNotEmpty)
          ? originalAddedByName
          : (widget.existingExpense != null
              ? widget.existingExpense!.resolveAddedByName(
                  UserCacheService.getUser(effectiveAddedByUserId)?.displayName ??
                  (effectiveAddedByUserId == currentUserId ? currentUserName : null))
              : (currentUserName.isNotEmpty ? currentUserName : 'Member'));

      final expense = ExpenseModel(
        id: expenseId,
        tourId: tour.id,
        title: _titleCtrl.text.trim().isNotEmpty
            ? _titleCtrl.text.trim()
            : 'Expense',
        amount: totalAmount,
        currency: tour.currency,
        category: category,
        paidByUserId: finalPaidByUserId,
        paidByName: finalPaidByName,
        payers: payersMap,
        splitType: splitType,
        splitAmong: splitMembers,
        customSplits: customSplitsMap,
        date: _selectedDateTime,
        createdAt: widget.existingExpense?.createdAt ?? DateTime.now(),
        addedByUserId: effectiveAddedByUserId,
        addedByName: effectiveAddedByName,
        status: isAdmin ? ExpenseStatus.approved : ExpenseStatus.pendingApproval,
        description: null,
      );

      bool savedOfflineLocally = false;
      try {
        await expenseRepo.addExpense(expense).timeout(const Duration(milliseconds: 1500));
      } catch (err) {
        debugPrint('[ADD_EXPENSE] Firestore write halted/timed out/offline: $err, queueing locally...');
        await ref.read(offlineExpenseQueueProvider).queueExpense(expense);
        savedOfflineLocally = true;
      }
      await ActiveTourCacheService.appendCachedExpense(tour.id, expense);
      ref.read(localExpensesRefreshProvider.notifier).bump();
      ref.read(lastExpenseDateProvider.notifier).setDate(_selectedDateTime);

      if (mounted) {
        final message = savedOfflineLocally
            ? 'Offline: Expense saved and will sync automatically when back online!'
            : (isAdmin
                ? 'Expense saved successfully!'
                : 'Expense submitted for admin approval');
        await showAppNotificationSheet(
          context,
          icon: Icons.check_circle_outline_rounded,
          iconColor: AppColors.positive,
          title: isAdmin ? 'Expense Saved!' : 'Expense Submitted',
          message: message,
          primaryButtonText: 'Done',
        );
        if (mounted) context.pop();
      }
    } catch (e) {
      if (mounted) {
        showAppNotificationSheet(
          context,
          icon: Icons.error_outline_rounded,
          iconColor: AppColors.danger,
          title: 'Expense Failed',
          message: 'Failed to add expense: $e',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  void _showPayerPickerSheet(
      BuildContext context, List<TourMemberModel> members, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? Colors.black : Colors.white,
      barrierColor: Colors.black54,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        side: isDark
            ? const BorderSide(color: AppColors.darkBorder, width: 1)
            : BorderSide.none,
      ),
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.black : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Select Payer',
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : AppColors.lightText,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                  ),
                  Flexible(
                    child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: members.length,
                    itemBuilder: (ctx, i) {
                      final m = members[i];
                      final isSelected = m.userId == _paidByUserId;
                      return ListTile(
                        leading: MemberAvatar(
                          initials: m.initials,
                          photoUrl: m.photoUrl,
                          userId: m.userId,
                          tourMember: m,
                          radius: 18,
                          enableTap: false,
                        ),
                        title: Text(
                          '${m.displayName}${m.isOffline ? ' (Offline)' : ''}',
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isDark ? Colors.white : AppColors.lightText,
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle_rounded,
                                color: AppColors.primaryTeal)
                            : null,
                        onTap: () {
                          setState(() {
                            _paidByUserId = m.userId;
                            _paidByName = m.displayName;
                          });
                          Navigator.pop(ctx);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final userAsync = ref.watch(currentUserProvider);
    final user = userAsync.value;
    final cachedTour = ActiveTourCacheService.getCachedActiveTour();
    final activeTourId = ref.watch(activeTourIdProvider);
    final tourId = widget.tourId ??
        widget.existingExpense?.tourId ??
        activeTourId ??
        user?.activeTourId ??
        cachedTour?.id ??
        ActiveTourCacheService.getActiveTourId();

    if (tourId == null) {
      if (userAsync.isLoading) {
        return const Scaffold(
            body: Center(child: CircularProgressIndicator()));
      }
      return const Scaffold(body: Center(child: Text('No active tour')));
    }

    final currentUserId = user?.uid ?? ref.watch(authServiceProvider).currentUser?.uid ?? '';
    final currentUserName = user?.displayName ??
        UserCacheService.getUser(currentUserId)?.displayName ??
        ref.watch(authServiceProvider).currentUser?.displayName ??
        'Member';
    final tourStream = ref.watch(tourStreamProvider(tourId));
    final membersStream = ref.watch(tourMembersStreamProvider(tourId));

    final effectiveTour = tourStream.value ??
        (cachedTour?.id == tourId ? cachedTour : null) ??
        cachedTour ??
        TourModel(
          id: tourId,
          name: 'Tour',
          currency: 'BDT',
          currencySymbol: '৳',
          adminId: currentUserId,
          inviteCode: '',
          status: TourStatus.active,
          startDate: DateTime.now(),
          createdAt: DateTime.now(),
          memberIds: currentUserId.isNotEmpty ? [currentUserId] : [],
          adminIds: currentUserId.isNotEmpty ? [currentUserId] : [],
        );

    final tour = effectiveTour;
    final isAdmin = tour.isAdmin(currentUserId);

    ref.watch(localMembersRefreshProvider);

    final cachedMembers = ActiveTourCacheService.getCachedMembers(tourId);
    final streamMembers = membersStream.value ?? [];
    final localMembers = tourId.startsWith('local_')
        ? ref.read(tourRepositoryProvider).getLocalTourMembers(tourId)
        : <TourMemberModel>[];
    final queuedMembers = ref.read(offlineTourQueueProvider).getQueuedMembersForTour(tourId);

    final Map<String, TourMemberModel> membersMap = {};
    for (final m in streamMembers) {
      membersMap[m.userId] = m;
    }
    for (final m in cachedMembers) {
      membersMap.putIfAbsent(m.userId, () => m);
    }
    for (final m in localMembers) {
      membersMap.putIfAbsent(m.userId, () => m);
    }
    for (final m in queuedMembers) {
      membersMap.putIfAbsent(m.userId, () => m);
    }

    if (currentUserId.isNotEmpty && !membersMap.containsKey(currentUserId)) {
      membersMap[currentUserId] = TourMemberModel(
        userId: currentUserId,
        displayName: user?.displayName ?? 'You',
        username: user?.username ?? '',
        email: user?.email ?? '',
        photoUrl: user?.photoUrl,
        role: 'admin',
        status: 'active',
        joinedAt: DateTime.now(),
      );
    }

    final ids = tour.memberIds.isNotEmpty
        ? tour.memberIds
        : (currentUserId.isNotEmpty ? [currentUserId] : <String>[]);
    for (final uid in ids) {
      if (!membersMap.containsKey(uid)) {
        final cachedUser = UserCacheService.getUser(uid);
        membersMap[uid] = TourMemberModel(
          userId: uid,
          displayName: cachedUser?.displayName ??
              (uid == currentUserId ? (user?.displayName ?? 'You') : 'Member'),
          username: cachedUser?.username ?? '',
          email: uid == currentUserId ? (user?.email ?? '') : '',
          photoUrl: cachedUser?.photoUrl ?? (uid == currentUserId ? user?.photoUrl : null),
          role: tour.isAdmin(uid) ? 'admin' : 'member',
          status: 'active',
          joinedAt: tour.createdAt,
          balance: 0.0,
          isOffline: uid.startsWith('offline_'),
        );
      }
    }

    final resolvedMembers = membersMap.values.toList();

    if (cachedMembers.isEmpty && resolvedMembers.isNotEmpty) {
      ActiveTourCacheService.cacheActiveTour(
        tour: tour,
        members: resolvedMembers,
      );
    }

    final members = resolvedMembers;
    _members = members;
    if (members.isNotEmpty) {
      if (_paidByUserId == null || !members.any((m) => m.userId == _paidByUserId)) {
        final defaultPayer = members.firstWhere(
          (m) => m.userId == currentUserId,
          orElse: () => members.first,
        );
        _paidByUserId = defaultPayer.userId;
        _paidByName = defaultPayer.displayName;
      }
      if (_selectedMemberIds.isEmpty) {
        _selectedMemberIds = members.map((m) => m.userId).toList();
      }
    }

    for (final m in members) {
      if (!_contributorControllers.containsKey(m.userId)) {
        _contributorControllers[m.userId] = TextEditingController();
      }
      if (!_customSplitControllers.containsKey(m.userId)) {
        _customSplitControllers[m.userId] = TextEditingController();
      }
    }

    final currentPayerMember = members.firstWhereOrNull((m) => m.userId == _paidByUserId) ??
        (members.isNotEmpty ? members.first : null);

    final canDelete = widget.existingExpense != null &&
        (isAdmin ||
            widget.existingExpense!.addedByUserId == currentUserId ||
            widget.existingExpense!.paidByUserId == currentUserId);

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
      child: LoadingOverlay(
        isLoading: _isLoading,
        child: Scaffold(
          backgroundColor: isDark ? Colors.black : const Color(0xFFF8FAFC),
          appBar: AppBar(
            backgroundColor: isDark ? Colors.black : const Color(0xFFF8FAFC),
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.close_rounded),
              tooltip: 'Cancel',
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/home');
                }
              },
            ),
            title: Text(
              widget.existingExpense != null ? 'Edit Expense' : 'Add Expense',
              style: TextStyle(
                fontFamily: 'Outfit',
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : AppColors.lightText,
              ),
            ),
            centerTitle: true,
            actions: [
              if (canDelete)
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: AppColors.negative),
                  tooltip: 'Delete Expense',
                  onPressed: () => _confirmDeleteExpense(tour.id, widget.existingExpense!),
                ),
            ],
          ),
          body: Form(
            key: _formKey,
            autovalidateMode: _submitted
                ? AutovalidateMode.onUserInteraction
                : AutovalidateMode.disabled,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (tour.isLockedForDeletion) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.danger.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.timer_outlined,
                              color: AppColors.danger, size: 24),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Tour Auto-Deletes in ${tour.daysUntilAutoDeletion} days',
                                  style: const TextStyle(
                                    fontFamily: 'Outfit',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5,
                                    color: AppColors.danger,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'This tour is inactive and scheduled for deletion. Adding or editing expenses is disabled.',
                                  style: TextStyle(
                                    fontFamily: 'Outfit',
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  // --- HERO AMOUNT & MATH & DATE SECTION ---
                  Center(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              tour.currencySymbol,
                              style: const TextStyle(
                                fontFamily: 'Outfit',
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                                color: AppColors.primaryTeal,
                              ),
                            ),
                            const SizedBox(width: 6),
                            IntrinsicWidth(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                    minWidth: 80, maxWidth: 260),
                                child: TextFormField(
                                  controller: _amountCtrl,
                                  focusNode: _amountFocusNode,
                                  keyboardType: TextInputType.text,
                                  textAlign: TextAlign.center,
                                  autovalidateMode: _submitted
                                      ? AutovalidateMode.onUserInteraction
                                      : AutovalidateMode.disabled,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                        RegExp(r'[0-9\.\+\-\*\/\(\)\s\×\÷xX,]')),
                                  ],
                                  style: TextStyle(
                                    fontFamily: 'Outfit',
                                    fontSize: 44,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -1.0,
                                    color: isDark
                                        ? Colors.white
                                        : const Color(0xFF0F172A),
                                  ),
                                  decoration: InputDecoration(
                                    hintText: '0',
                                    hintStyle: TextStyle(
                                      fontFamily: 'Outfit',
                                      fontSize: 44,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -1.0,
                                      color: isDark
                                          ? const Color(0xFF334155)
                                          : const Color(0xFFCBD5E1),
                                    ),
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    errorBorder: InputBorder.none,
                                    focusedErrorBorder: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                  onChanged: (_) {
                                    if (_submitted) {
                                      _formKey.currentState?.validate();
                                    }
                                    setState(() {});
                                  },
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return 'Enter amount';
                                    }
                                    final val =
                                        MathExpressionEvaluator.tryEvaluate(v);
                                    if (val == null || val <= 0) {
                                      return 'Invalid amount';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Quick Math Bar: [ + ] [ − ] [ × ] [ ÷ ] [ = ]
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final op in ['+', '−', '×', '÷', '=']) ...[
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                child: InkWell(
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    _insertOperator(op);
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    width: 36,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: op == '='
                                          ? AppColors.primaryTeal
                                          : (isDark
                                              ? Colors.black
                                              : const Color(0xFFF1F5F9)),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: op == '='
                                            ? AppColors.primaryTeal
                                            : (isDark
                                                ? AppColors.darkBorder
                                                : AppColors.lightBorder),
                                        width: 1,
                                      ),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      op,
                                      style: TextStyle(
                                        fontFamily: 'Outfit',
                                        fontSize: op == '=' ? 14 : 15,
                                        fontWeight: FontWeight.w700,
                                        color: op == '='
                                            ? Colors.white
                                            : (isDark
                                                ? Colors.white70
                                                : AppColors.lightText),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Date Pill with clean vector outline icon
                        InkWell(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            _pickDate();
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.black : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isDark
                                    ? AppColors.darkBorder
                                    : AppColors.lightBorder,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.calendar_today_outlined,
                                  size: 13,
                                  color: isDark
                                      ? const Color(0xFF94A3B8)
                                      : const Color(0xFF64748B),
                                ),
                                const SizedBox(width: 7),
                                Text(
                                  _isToday(_selectedDateTime)
                                      ? 'Today, ${DateFormat('MMM d').format(_selectedDateTime)}'
                                      : DateFormat('EEE, MMM d')
                                          .format(_selectedDateTime),
                                  style: TextStyle(
                                    fontFamily: 'Outfit',
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? Colors.white
                                        : AppColors.lightText,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 16,
                                  color: isDark
                                      ? const Color(0xFF94A3B8)
                                      : const Color(0xFF64748B),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 22),

                  // --- EXPENSE ITEM TITLE ---
                  TextFormField(
                    controller: _titleCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    autovalidateMode: _submitted
                        ? AutovalidateMode.onUserInteraction
                        : AutovalidateMode.disabled,
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white : AppColors.lightText,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Expense description (e.g. Lunch at Sea Gull)',
                      hintStyle: TextStyle(
                        fontFamily: 'Outfit',
                        fontSize: 14,
                        color: isDark
                            ? const Color(0xFF64748B)
                            : const Color(0xFF94A3B8),
                      ),
                      filled: true,
                      fillColor: isDark ? Colors.black : Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: isDark
                              ? AppColors.darkBorder
                              : AppColors.lightBorder,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: isDark
                              ? AppColors.darkBorder
                              : AppColors.lightBorder,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: AppColors.primaryTeal,
                          width: 1.5,
                        ),
                      ),
                    ),
                    onChanged: (_) {
                      if (_submitted) {
                        _formKey.currentState?.validate();
                      }
                      setState(() {});
                    },
                    validator: (val) =>
                        val == null || val.trim().isEmpty ? 'Enter description' : null,
                  ),

                  const SizedBox(height: 20),

                  // --- PAID BY SECTION ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'PAID BY',
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF475569),
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            _isMultiContributor = !_isMultiContributor;
                            if (_isMultiContributor &&
                                _totalContributions <= 0 &&
                                _paidByUserId != null) {
                              _contributorControllers[_paidByUserId!]?.text =
                                  _amountCtrl.text.trim();
                            }
                          });
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          child: Text(
                            _isMultiContributor
                                ? 'Single Payer'
                                : '+ Multiple Payers',
                            style: const TextStyle(
                              fontFamily: 'Outfit',
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primaryTeal,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.black : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark
                            ? AppColors.darkBorder
                            : AppColors.lightBorder,
                        width: 1.0,
                      ),
                    ),
                    child: !_isMultiContributor
                        ? InkWell(
                            onTap: () => _showPayerPickerSheet(
                                context, members, isDark),
                            borderRadius: BorderRadius.circular(12),
                            child: Row(
                              children: [
                                MemberAvatar(
                                  initials: currentPayerMember?.initials ?? '?',
                                  photoUrl: currentPayerMember?.photoUrl,
                                  userId: currentPayerMember?.userId ?? '',
                                  tourMember: currentPayerMember,
                                  radius: 20,
                                  enableTap: false,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${currentPayerMember?.displayName ?? 'Select Payer'}${currentPayerMember?.isOffline ?? false ? ' (Offline)' : ''}',
                                        style: TextStyle(
                                          fontFamily: 'Outfit',
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w700,
                                          color: isDark
                                              ? Colors.white
                                              : AppColors.lightText,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Paid 100% of the bill',
                                        style: TextStyle(
                                          fontFamily: 'Outfit',
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: isDark
                                              ? const Color(0xFF94A3B8)
                                              : const Color(0xFF64748B),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  color: AppColors.primaryTeal,
                                  size: 22,
                                ),
                              ],
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Member Contributions',
                                    style: TextStyle(
                                      fontFamily: 'Outfit',
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: isDark
                                          ? Colors.white70
                                          : AppColors.lightText,
                                    ),
                                  ),
                                  Text(
                                    '${tour.currencySymbol}${_totalContributions.toStringAsFixed(0)} / ${tour.currencySymbol}${_amountCtrl.text.trim().isEmpty ? '0' : _amountCtrl.text.trim()}',
                                    style: TextStyle(
                                      fontFamily: 'Outfit',
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800,
                                      color: (_totalContributions -
                                                      (double.tryParse(_amountCtrl
                                                              .text
                                                              .trim()) ??
                                                          0.0))
                                                  .abs() <
                                              0.05
                                          ? AppColors.positive
                                          : AppColors.danger,
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(height: 18),
                              ...members.map((m) {
                                final ctrl =
                                    _contributorControllers[m.userId]!;
                                final totalAmt = double.tryParse(
                                        _amountCtrl.text.trim()) ??
                                    0.0;
                                final otherSum = _contributorControllers.entries
                                    .where((e) => e.key != m.userId)
                                    .fold<double>(
                                        0.0,
                                        (sum, e) =>
                                            sum +
                                            (double.tryParse(
                                                    e.value.text.trim()) ??
                                                0.0));
                                final remainingForMember = totalAmt - otherSum;

                                return Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 6),
                                  child: Row(
                                    children: [
                                      MemberAvatar(
                                        initials: m.initials,
                                        photoUrl: m.photoUrl,
                                        userId: m.userId,
                                        tourMember: m,
                                        radius: 16,
                                        enableTap: false,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${m.displayName}${m.isOffline ? ' (Offline)' : ''}',
                                              style: TextStyle(
                                                fontFamily: 'Outfit',
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: isDark
                                                    ? Colors.white
                                                    : AppColors.lightText,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            if (remainingForMember > 0.01) ...[
                                              const SizedBox(height: 2),
                                              InkWell(
                                                onTap: () {
                                                  HapticFeedback.lightImpact();
                                                  setState(() {
                                                    ctrl.text = remainingForMember %
                                                                1 ==
                                                            0
                                                        ? remainingForMember
                                                            .toStringAsFixed(0)
                                                        : remainingForMember
                                                            .toStringAsFixed(2);
                                                  });
                                                },
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                child: Text(
                                                  '+ Fill Rest (${tour.currencySymbol}${remainingForMember.toStringAsFixed(remainingForMember % 1 == 0 ? 0 : 2)})',
                                                  style: const TextStyle(
                                                    fontFamily: 'Outfit',
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                    color: AppColors.primaryTeal,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: 95,
                                        height: 38,
                                        child: TextFormField(
                                          controller: ctrl,
                                          keyboardType: const TextInputType
                                              .numberWithOptions(
                                              decimal: true),
                                          textAlign: TextAlign.right,
                                          style: TextStyle(
                                            fontFamily: 'Outfit',
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w700,
                                            color: isDark
                                                ? Colors.white
                                                : AppColors.lightText,
                                          ),
                                          decoration: InputDecoration(
                                            prefixText:
                                                '${tour.currencySymbol} ',
                                            prefixStyle: const TextStyle(
                                              fontFamily: 'Outfit',
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.primaryTeal,
                                            ),
                                            filled: true,
                                            fillColor: isDark
                                                ? const Color(0xFF0F172A)
                                                : const Color(0xFFF8FAFC),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 8, vertical: 8),
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              borderSide: BorderSide(
                                                color: isDark
                                                    ? AppColors.darkBorder
                                                    : AppColors.lightBorder,
                                              ),
                                            ),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              borderSide: BorderSide(
                                                color: isDark
                                                    ? AppColors.darkBorder
                                                    : AppColors.lightBorder,
                                              ),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              borderSide: const BorderSide(
                                                color: AppColors.primaryTeal,
                                                width: 1.5,
                                              ),
                                            ),
                                          ),
                                          onChanged: (_) => setState(() {}),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                  ),

                  const SizedBox(height: 20),

                  // --- SPLIT WITH SECTION ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'SPLIT WITH',
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF475569),
                        ),
                      ),
                      if (_splitMode == 0 &&
                          _selectedMemberIds.length < members.length)
                        InkWell(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _selectedMemberIds =
                                  members.map((m) => m.userId).toList();
                            });
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            child: Text(
                              'Select All',
                              style: TextStyle(
                                fontFamily: 'Outfit',
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primaryTeal,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Split Mode Toggle Buttons (Teal solid background with white text when selected)
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _splitMode = 0);
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            decoration: BoxDecoration(
                              color: _splitMode == 0
                                  ? AppColors.primaryTeal
                                  : (isDark ? Colors.black : Colors.white),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _splitMode == 0
                                    ? AppColors.primaryTeal
                                    : (isDark
                                        ? AppColors.darkBorder
                                        : AppColors.lightBorder),
                                width: 1.0,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              'Split Equally (All)',
                              style: TextStyle(
                                fontFamily: 'Outfit',
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: _splitMode == 0
                                    ? Colors.white
                                    : (isDark
                                        ? const Color(0xFF94A3B8)
                                        : const Color(0xFF64748B)),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _splitMode = 1;
                              for (final m in members) {
                                _customSplitControllers.putIfAbsent(
                                    m.userId, () => TextEditingController());
                              }
                            });
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            decoration: BoxDecoration(
                              color: _splitMode == 1
                                  ? AppColors.primaryTeal
                                  : (isDark ? Colors.black : Colors.white),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _splitMode == 1
                                    ? AppColors.primaryTeal
                                    : (isDark
                                        ? AppColors.darkBorder
                                        : AppColors.lightBorder),
                                width: 1.0,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              'Custom Split',
                              style: TextStyle(
                                fontFamily: 'Outfit',
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: _splitMode == 1
                                    ? Colors.white
                                    : (isDark
                                        ? const Color(0xFF94A3B8)
                                        : const Color(0xFF64748B)),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.black : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark
                            ? AppColors.darkBorder
                            : AppColors.lightBorder,
                        width: 1.0,
                      ),
                    ),
                    child: _splitMode == 0
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.people_alt_outlined,
                                    size: 15,
                                    color: AppColors.primaryTeal,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Builder(
                                      builder: (context) {
                                        final expVal =
                                            MathExpressionEvaluator.tryEvaluate(
                                                    _amountCtrl.text.trim()) ??
                                                0.0;
                                        final count = _selectedMemberIds.isEmpty
                                            ? members.length
                                            : _selectedMemberIds.length;
                                        final perPerson = count > 0
                                            ? (expVal / count)
                                            : 0.0;
                                        return Text(
                                          '≈ ${tour.currencySymbol}${perPerson.toStringAsFixed(perPerson % 1 == 0 ? 0 : 2)} / person  (${_selectedMemberIds.length} of ${members.length} members)',
                                          style: TextStyle(
                                            fontFamily: 'Outfit',
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                            color: isDark
                                                ? const Color(0xFFCBD5E1)
                                                : const Color(0xFF334155),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              // Avatar Grid/Wrap for Selecting/Deselecting members
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: members.map((m) {
                                  final isSelected =
                                      _selectedMemberIds.contains(m.userId);
                                  return InkWell(
                                    onTap: () {
                                      HapticFeedback.selectionClick();
                                      setState(() {
                                        if (isSelected) {
                                          if (_selectedMemberIds.length > 1) {
                                            _selectedMemberIds.remove(m.userId);
                                          }
                                        } else {
                                          _selectedMemberIds.add(m.userId);
                                        }
                                      });
                                    },
                                    borderRadius: BorderRadius.circular(24),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            Opacity(
                                              opacity: isSelected ? 1.0 : 0.35,
                                              child: MemberAvatar(
                                                initials: m.initials,
                                                photoUrl: m.photoUrl,
                                                userId: m.userId,
                                                tourMember: m,
                                                radius: 20,
                                                enableTap: false,
                                              ),
                                            ),
                                            if (isSelected)
                                              Positioned(
                                                right: -2,
                                                bottom: -2,
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.all(2),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.primaryTeal,
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                      color: isDark
                                                          ? Colors.black
                                                          : Colors.white,
                                                      width: 1.5,
                                                    ),
                                                  ),
                                                  child: const Icon(
                                                    Icons.check,
                                                    size: 10,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 5),
                                        SizedBox(
                                          width: 52,
                                          child: Text(
                                            m.displayName.split(' ').first,
                                            textAlign: TextAlign.center,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontFamily: 'Outfit',
                                              fontSize: 11,
                                              fontWeight: isSelected
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                              color: isSelected
                                                  ? (isDark
                                                      ? Colors.white
                                                      : AppColors.lightText)
                                                  : (isDark
                                                      ? const Color(0xFF64748B)
                                                      : const Color(
                                                          0xFF94A3B8)),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Assign Custom Amounts',
                                    style: TextStyle(
                                      fontFamily: 'Outfit',
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: isDark
                                          ? Colors.white70
                                          : AppColors.lightText,
                                    ),
                                  ),
                                  Text(
                                    '${tour.currencySymbol}$_totalCustomSplit / ${tour.currencySymbol}${_amountCtrl.text.trim().isEmpty ? '0' : _amountCtrl.text.trim()}',
                                    style: TextStyle(
                                      fontFamily: 'Outfit',
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800,
                                      color: (_totalCustomSplit -
                                                      (double.tryParse(_amountCtrl
                                                              .text
                                                              .trim()) ??
                                                          0.0))
                                                  .abs() <
                                              0.05
                                          ? AppColors.positive
                                          : AppColors.danger,
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(height: 18),
                              ...members.map((m) {
                                final ctrl =
                                    _customSplitControllers[m.userId]!;
                                final totalAmt = double.tryParse(
                                        _amountCtrl.text.trim()) ??
                                    0.0;
                                final otherSum = _customSplitControllers.entries
                                    .where((e) => e.key != m.userId)
                                    .fold<double>(
                                        0.0,
                                        (sum, e) =>
                                            sum +
                                            (double.tryParse(
                                                    e.value.text.trim()) ??
                                                0.0));
                                final remainingForMember = totalAmt - otherSum;

                                return Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 6),
                                  child: Row(
                                    children: [
                                      MemberAvatar(
                                        initials: m.initials,
                                        photoUrl: m.photoUrl,
                                        userId: m.userId,
                                        tourMember: m,
                                        radius: 16,
                                        enableTap: false,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${m.displayName}${m.isOffline ? ' (Offline)' : ''}',
                                              style: TextStyle(
                                                fontFamily: 'Outfit',
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: isDark
                                                    ? Colors.white
                                                    : AppColors.lightText,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            if (remainingForMember > 0.01) ...[
                                              const SizedBox(height: 2),
                                              InkWell(
                                                onTap: () {
                                                  HapticFeedback.lightImpact();
                                                  setState(() {
                                                    ctrl.text = remainingForMember %
                                                                1 ==
                                                            0
                                                        ? remainingForMember
                                                            .toStringAsFixed(0)
                                                        : remainingForMember
                                                            .toStringAsFixed(2);
                                                  });
                                                },
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                child: Text(
                                                  '+ Fill Rest (${tour.currencySymbol}${remainingForMember.toStringAsFixed(remainingForMember % 1 == 0 ? 0 : 2)})',
                                                  style: const TextStyle(
                                                    fontFamily: 'Outfit',
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                    color: AppColors.primaryTeal,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: 95,
                                        height: 38,
                                        child: TextFormField(
                                          controller: ctrl,
                                          keyboardType: const TextInputType
                                              .numberWithOptions(
                                              decimal: true),
                                          textAlign: TextAlign.right,
                                          style: TextStyle(
                                            fontFamily: 'Outfit',
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w700,
                                            color: isDark
                                                ? Colors.white
                                                : AppColors.lightText,
                                          ),
                                          decoration: InputDecoration(
                                            prefixText:
                                                '${tour.currencySymbol} ',
                                            prefixStyle: const TextStyle(
                                              fontFamily: 'Outfit',
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.primaryTeal,
                                            ),
                                            filled: true,
                                            fillColor: isDark
                                                ? const Color(0xFF0F172A)
                                                : const Color(0xFFF8FAFC),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 8, vertical: 8),
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              borderSide: BorderSide(
                                                color: isDark
                                                    ? AppColors.darkBorder
                                                    : AppColors.lightBorder,
                                              ),
                                            ),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              borderSide: BorderSide(
                                                color: isDark
                                                    ? AppColors.darkBorder
                                                    : AppColors.lightBorder,
                                              ),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              borderSide: const BorderSide(
                                                color: AppColors.primaryTeal,
                                                width: 1.5,
                                              ),
                                            ),
                                          ),
                                          onChanged: (_) => setState(() {}),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                  ),

                  const SizedBox(height: 28),

                  // --- BOTTOM ACTION BUTTON ---
                  Builder(
                    builder: (context) {
                      final amtText = _amountCtrl.text.trim();
                      final amt = MathExpressionEvaluator.tryEvaluate(amtText);
                      final displayAmt = (amt != null && amt > 0)
                          ? ' • ${tour.currencySymbol}${MathExpressionEvaluator.formatResult(amt)}'
                          : (amtText.isNotEmpty
                              ? ' • ${tour.currencySymbol}$amtText'
                              : '');

                      return GradientButton(
                        onPressed: tour.isLockedForDeletion
                            ? () {
                                showAppNotificationSheet(
                                  context,
                                  icon: Icons.timer_outlined,
                                  iconColor: AppColors.danger,
                                  title: 'Tour Scheduled for Deletion',
                                  message:
                                      'This tour is scheduled for deletion due to inactivity. Adding or editing expenses is disabled.',
                                  primaryButtonText: 'Download PDF',
                                  onPrimaryPressed: () => context
                                      .push('/reports?tourId=${tour.id}'),
                                  secondaryButtonText: 'Close',
                                );
                              }
                            : () => _submit(
                                tour, currentUserId, currentUserName, isAdmin),
                        label: tour.isLockedForDeletion
                            ? 'Tour Locked (Pending Deletion)'
                            : (widget.existingExpense != null
                                ? 'Update Expense$displayAmt'
                                : 'Save Expense$displayAmt'),
                        icon: tour.isLockedForDeletion
                            ? Icons.lock_clock_rounded
                            : Icons.check_circle_rounded,
                        gradient: tour.isLockedForDeletion
                            ? const LinearGradient(
                                colors: [Color(0xFF64748B), Color(0xFF475569)])
                            : AppColors.primaryGradient,
                      );
                    },
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
