import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/math_expression_evaluator.dart';
import '../../data/services/auth_service.dart';
import '../../data/repositories/tour_repository.dart';
import '../../data/repositories/expense_repository.dart';
import '../../data/models/expense_model.dart';
import '../../data/models/tour_model.dart';
import '../widgets/gradient_button.dart';
import '../widgets/loading_overlay.dart';
import '../widgets/member_avatar.dart';

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
  final ExpenseModel? existingExpense;
  const AddExpenseScreen({super.key, this.existingExpense});

  @override
  ConsumerState<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends ConsumerState<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _amountFocusNode = FocusNode();

  bool _isLoading = false;

  int _splitMode = 0;
  DateTime _selectedDateTime = DateTime.now();

  bool _isMultiContributor = false;
  final Map<String, TextEditingController> _contributorControllers = {};

  String? _paidByUserId;
  String? _paidByName;
  List<String> _selectedMemberIds = [];
  final Map<String, TextEditingController> _customSplitControllers = {};
  List<TourMemberModel> _members = [];

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
      _descCtrl.text = exp.description ?? '';
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
        _splitMode = 2;
        for (final entry in exp.customSplits!.entries) {
          _customSplitControllers[entry.key] = TextEditingController(
            text: entry.value.toStringAsFixed(
                entry.value.truncateToDouble() == entry.value ? 0 : 2),
          );
        }
      } else if (exp.splitType == SplitType.selected) {
        _splitMode = 1;
        _selectedMemberIds = List.from(exp.splitAmong);
      } else {
        _splitMode = 0;
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
    _descCtrl.dispose();
    for (final ctrl in _customSplitControllers.values) {
      ctrl.dispose();
    }
    for (final ctrl in _contributorControllers.values) {
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

  double get _totalCustomSplit {
    double sum = 0.0;
    for (final ctrl in _customSplitControllers.values) {
      final val = MathExpressionEvaluator.tryEvaluate(ctrl.text.trim()) ??
          (double.tryParse(ctrl.text.trim()) ?? 0.0);
      sum += val;
    }
    return (sum * 100).round() / 100;
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

  Future<void> _submit(
      TourModel tour, String currentUserId, bool isAdmin) async {
    _evaluateAmount();
    if (!_formKey.currentState!.validate()) return;

    final eval = MathExpressionEvaluator.tryEvaluate(_amountCtrl.text.trim());
    final totalAmount = eval ?? (double.tryParse(_amountCtrl.text.trim()) ?? 0.0);
    if (totalAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount')),
      );
      return;
    }

    Map<String, double>? payersMap;
    String finalPaidByUserId = _paidByUserId ?? currentUserId;
    String finalPaidByName = _paidByName ?? 'Member';

    if (_isMultiContributor) {
      final currentContributedTotal = _totalContributions;
      if ((currentContributedTotal - totalAmount).abs() > 0.05) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Sum of contributions (${tour.currencySymbol}${currentContributedTotal.toStringAsFixed(0)}) must equal total expense (${tour.currencySymbol}${totalAmount.toStringAsFixed(0)})',
            ),
            backgroundColor: AppColors.danger,
          ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Please enter at least one contribution')),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select who paid')),
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
      splitType = SplitType.equal;
      splitMembers = _members.map((m) => m.userId).toList();
      customSplitsMap = null;
    } else if (_splitMode == 1) {
      splitType = SplitType.selected;
      splitMembers = _selectedMemberIds;
      customSplitsMap = null;
      if (splitMembers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Select at least one member to share this expense')),
        );
        return;
      }
    } else {
      splitType = SplitType.custom;
      final currentCustomTotal = _totalCustomSplit;
      if ((currentCustomTotal - totalAmount).abs() > 0.05) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Custom split sum (${tour.currencySymbol}${currentCustomTotal.toStringAsFixed(2)}) must equal total expense (${tour.currencySymbol}${totalAmount.toStringAsFixed(2)})'),
            backgroundColor: AppColors.danger,
          ),
        );
        return;
      }

      customSplitsMap = {};
      splitMembers = [];
      for (final entry in _customSplitControllers.entries) {
        final amt = MathExpressionEvaluator.tryEvaluate(entry.value.text.trim()) ??
            (double.tryParse(entry.value.text.trim()) ?? 0.0);
        final roundedAmt = (amt * 100).round() / 100;
        if (roundedAmt > 0) {
          customSplitsMap[entry.key] = roundedAmt;
          splitMembers.add(entry.key);
        }
      }
    }

    setState(() => _isLoading = true);
    try {
      if (widget.existingExpense != null) {
        final updateData = {
          'title': _titleCtrl.text.trim().isNotEmpty
              ? _titleCtrl.text.trim()
              : 'Expense',
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
          'description':
              _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
          if (isAdmin) 'status': 'approved',
        };

        await ref.read(expenseRepositoryProvider).updateExpense(
              tour.id,
              widget.existingExpense!.id,
              updateData,
            );
        ref.read(lastExpenseDateProvider.notifier).setDate(_selectedDateTime);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Expense updated successfully! ✨'),
              backgroundColor: AppColors.positive,
            ),
          );
          context.pop();
        }
        return;
      }

      final expense = ExpenseModel(
        id: '',
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
        createdAt: DateTime.now(),
        addedByUserId: currentUserId,
        status:
            isAdmin ? ExpenseStatus.approved : ExpenseStatus.pendingApproval,
        description:
            _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      );

      await ref.read(expenseRepositoryProvider).addExpense(expense);
      ref.read(lastExpenseDateProvider.notifier).setDate(_selectedDateTime);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isAdmin
                ? 'Expense saved successfully!'
                : 'Expense submitted for admin approval'),
            backgroundColor: AppColors.accent,
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add expense: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final user = ref.watch(currentUserProvider).value;

    if (user == null || user.activeTourId == null) {
      return const Scaffold(body: Center(child: Text('No active tour')));
    }

    final tourId = user.activeTourId!;
    final tourStream = ref.watch(tourStreamProvider(tourId));
    final membersStream = ref.watch(tourMembersStreamProvider(tourId));

    return tourStream.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
      data: (tour) {
        if (tour == null) return const Scaffold();
        final isAdmin = tour.isAdmin(user.uid);

        return membersStream.when(
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
          data: (members) {
            _members = members;
            if (_paidByUserId == null && members.isNotEmpty) {
              final defaultPayer = members.firstWhere(
                (m) => m.userId == user.uid,
                orElse: () => members.first,
              );
              _paidByUserId = defaultPayer.userId;
              _paidByName = defaultPayer.displayName;
              _selectedMemberIds = members.map((m) => m.userId).toList();
            }

            for (final m in members) {
              if (!_customSplitControllers.containsKey(m.userId)) {
                _customSplitControllers[m.userId] = TextEditingController();
              }
              if (!_contributorControllers.containsKey(m.userId)) {
                _contributorControllers[m.userId] = TextEditingController();
              }
            }

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
                  appBar: AppBar(
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
                    title: Text(widget.existingExpense != null
                        ? 'Edit Expense'
                        : 'Add Expense'),
                    centerTitle: true,
                  ),
                body: Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _SectionLabel(title: 'Amount *'),
                        const SizedBox(height: 8),
                        Builder(
                          builder: (context) {
                            final expressionText = _amountCtrl.text.trim();
                            final hasMath = MathExpressionEvaluator.hasMathOperators(expressionText);
                            final previewVal = hasMath ? MathExpressionEvaluator.tryEvaluate(expressionText) : null;
                            final currentAmountNum = previewVal ?? MathExpressionEvaluator.tryEvaluate(expressionText) ?? 0.0;
                            final isFocused = _amountFocusNode.hasFocus;

                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: isDark
                                      ? [
                                          const Color(0xFF1E293B),
                                          const Color(0xFF0F172A)
                                        ]
                                      : [
                                          const Color(0xFFFFFFFF),
                                          const Color(0xFFF8FAFC)
                                        ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isFocused
                                      ? AppColors.primaryTeal
                                      : (isDark
                                          ? const Color(0xFF334155)
                                          : const Color(0xFFCBD5E1)),
                                  width: isFocused ? 2.0 : 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: isFocused
                                        ? AppColors.primaryTeal.withValues(alpha: 0.25)
                                        : (isDark
                                            ? Colors.black.withValues(alpha: 0.3)
                                            : const Color(0xFF94A3B8)
                                                .withValues(alpha: 0.12)),
                                    blurRadius: isFocused ? 16 : 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: isDark
                                              ? const Color(0xFF0F2E28)
                                              : const Color(0xFFECFDF5),
                                          borderRadius: BorderRadius.circular(14),
                                          border: Border.all(
                                            color: isDark
                                                ? const Color(0xFF10B981)
                                                    .withValues(alpha: 0.5)
                                                : const Color(0xFFA7F3D0),
                                            width: 1.2,
                                          ),
                                        ),
                                        child: Text(
                                          tour.currencySymbol,
                                          style: TextStyle(
                                            fontFamily: 'Outfit',
                                            fontSize: 26,
                                            fontWeight: FontWeight.w800,
                                            color: isDark
                                                ? const Color(0xFF34D399)
                                                : const Color(0xFF065F46),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: TextFormField(
                                          controller: _amountCtrl,
                                          focusNode: _amountFocusNode,
                                          keyboardType: TextInputType.text,
                                          inputFormatters: [
                                            FilteringTextInputFormatter.allow(
                                                RegExp(r'[0-9\.\+\-\*\/\(\)\s\×\÷xX,]')),
                                          ],
                                          style: TextStyle(
                                            fontFamily: 'Outfit',
                                            fontSize: 30,
                                            fontWeight: FontWeight.w800,
                                            color: isDark
                                                ? Colors.white
                                                : const Color(0xFF0F172A),
                                            letterSpacing: -0.5,
                                          ),
                                          decoration: InputDecoration(
                                            hintText: '0.00',
                                            hintStyle: TextStyle(
                                              color: isDark
                                                  ? const Color(0xFF475569)
                                                  : const Color(0xFF94A3B8),
                                              fontSize: 30,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            border: InputBorder.none,
                                            isDense: true,
                                            contentPadding: EdgeInsets.zero,
                                          ),
                                          onChanged: (val) {
                                            setState(() {});
                                          },
                                          validator: (v) {
                                            if (v == null || v.trim().isEmpty) {
                                              return 'Enter amount';
                                            }
                                            final val = MathExpressionEvaluator.tryEvaluate(v);
                                            if (val == null || val <= 0) {
                                              return 'Invalid amount or expression';
                                            }
                                            return null;
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  // Quick Math Toolbar
                                  Row(
                                    children: [
                                      for (final op in ['+', '−', '×', '÷', '(', ')', '='])
                                        Expanded(
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 2),
                                            child: InkWell(
                                              onTap: () => _insertOperator(op),
                                              borderRadius: BorderRadius.circular(8),
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(vertical: 6),
                                                decoration: BoxDecoration(
                                                  color: op == '='
                                                      ? AppColors.primaryTeal
                                                      : (isDark
                                                          ? const Color(0xFF334155).withValues(alpha: 0.5)
                                                          : const Color(0xFFF1F5F9)),
                                                  borderRadius: BorderRadius.circular(8),
                                                  border: Border.all(
                                                    color: op == '='
                                                        ? AppColors.primaryTeal
                                                        : (isDark
                                                            ? const Color(0xFF475569)
                                                            : const Color(0xFFE2E8F0)),
                                                    width: 1,
                                                  ),
                                                ),
                                                alignment: Alignment.center,
                                                child: Text(
                                                  op,
                                                  style: TextStyle(
                                                    fontFamily: 'Outfit',
                                                    fontSize: op == '=' ? 14 : 15,
                                                    fontWeight: FontWeight.w800,
                                                    color: op == '='
                                                        ? Colors.white
                                                        : (isDark ? Colors.white70 : const Color(0xFF334155)),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  if (hasMath && previewVal != null) ...[
                                    const SizedBox(height: 8),
                                    InkWell(
                                      onTap: _evaluateAmount,
                                      borderRadius: BorderRadius.circular(10),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: AppColors.primaryTeal.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                            color: AppColors.primaryTeal.withValues(alpha: 0.4),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.calculate_rounded,
                                                size: 15, color: AppColors.primaryTeal),
                                            const SizedBox(width: 5),
                                            Text(
                                              '= ${tour.currencySymbol}${MathExpressionEvaluator.formatResult(previewVal)}',
                                              style: const TextStyle(
                                                fontFamily: 'Outfit',
                                                fontSize: 13,
                                                fontWeight: FontWeight.w800,
                                                color: AppColors.primaryTeal,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            const Text(
                                              '• tap to apply',
                                              style: TextStyle(
                                                fontFamily: 'Outfit',
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: AppColors.primaryTeal,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (currentAmountNum > 0 && members.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppColors.primaryTeal
                                            .withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '≈ ${tour.currencySymbol}${(currentAmountNum / members.length).toStringAsFixed(2)} / person',
                                        style: TextStyle(
                                          fontFamily: 'Outfit',
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: isDark
                                              ? const Color(0xFF5EEAD4)
                                              : const Color(0xFF0D9488),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 20),
                        _SectionLabel(title: 'Expense Item *'),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _titleCtrl,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText: 'Title (e.g. Lunch)',
                            filled: true,
                            fillColor: isDark
                                ? AppColors.darkSurface
                                : const Color(0xFFF1F5F9),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                  color: isDark
                                      ? AppColors.darkBorder
                                      : AppColors.lightBorder),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                  color: isDark
                                      ? AppColors.darkBorder
                                      : AppColors.lightBorder),
                            ),
                          ),
                          validator: (val) => val == null || val.trim().isEmpty
                              ? 'Enter item name'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        _SectionLabel(title: 'Notes (Optional)'),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _descCtrl,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText: 'Add note',
                            filled: true,
                            fillColor: isDark
                                ? AppColors.darkSurface
                                : const Color(0xFFF1F5F9),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                  color: isDark
                                      ? AppColors.darkBorder
                                      : AppColors.lightBorder),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                  color: isDark
                                      ? AppColors.darkBorder
                                      : AppColors.lightBorder),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        _SectionLabel(title: 'Expense Date *'),
                        const SizedBox(height: 8),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _pickDate,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? AppColors.darkSurface
                                  : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: isDark
                                      ? AppColors.darkBorder
                                      : AppColors.lightBorder),
                            ),
                            child: Builder(
                              builder: (context) {
                                final baseDate = DateTime(tour.startDate.year,
                                    tour.startDate.month, tour.startDate.day);
                                final expDate = DateTime(
                                    _selectedDateTime.year,
                                    _selectedDateTime.month,
                                    _selectedDateTime.day);
                                final diffDays =
                                    expDate.difference(baseDate).inDays;
                                final dayNumber =
                                    diffDays >= 0 ? diffDays + 1 : 1;

                                return Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppColors.primaryTeal,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'Day $dayNumber',
                                        style: const TextStyle(
                                          fontFamily: 'Outfit',
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    const Icon(Icons.calendar_month_rounded,
                                        size: 18, color: AppColors.primaryTeal),
                                    const SizedBox(width: 8),
                                    Text(
                                      DateFormat('EEE, MMM d, yyyy')
                                          .format(_selectedDateTime),
                                      style: const TextStyle(
                                          fontFamily: 'Outfit',
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14),
                                    ),
                                    const Spacer(),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? Colors.white.withValues(alpha: 0.08)
                                            : Colors.black.withValues(alpha: 0.05),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.edit_calendar_rounded,
                                              size: 14,
                                              color: AppColors.primaryTeal),
                                          SizedBox(width: 4),
                                          Text(
                                            'Change',
                                            style: TextStyle(
                                              fontFamily: 'Outfit',
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.primaryTeal,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _SectionLabel(title: 'Paid By *'),
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? AppColors.darkSurface
                                    : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isDark
                                      ? AppColors.darkBorder
                                      : AppColors.lightBorder,
                                ),
                              ),
                              child: Row(
                                children: [
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => setState(
                                        () => _isMultiContributor = false),
                                    child: AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 150),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 7),
                                      decoration: BoxDecoration(
                                        color: !_isMultiContributor
                                            ? AppColors.primaryTeal
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(9),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.person_rounded,
                                            size: 14.5,
                                            color: !_isMultiContributor
                                                ? Colors.white
                                                : (isDark
                                                    ? Colors.white60
                                                    : Colors.black54),
                                          ),
                                          const SizedBox(width: 5),
                                          Text(
                                            'Single',
                                            style: TextStyle(
                                              fontFamily: 'Outfit',
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: !_isMultiContributor
                                                  ? Colors.white
                                                  : (isDark
                                                      ? Colors.white60
                                                      : Colors.black54),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      setState(() {
                                        _isMultiContributor = true;
                                        if (_totalContributions <= 0 &&
                                            _paidByUserId != null) {
                                          _contributorControllers[
                                                  _paidByUserId!]
                                              ?.text = _amountCtrl.text.trim();
                                        }
                                      });
                                    },
                                    child: AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 150),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 7),
                                      decoration: BoxDecoration(
                                        color: _isMultiContributor
                                            ? AppColors.primaryTeal
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(9),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.group_rounded,
                                            size: 14.5,
                                            color: _isMultiContributor
                                                ? Colors.white
                                                : (isDark
                                                    ? Colors.white60
                                                    : Colors.black54),
                                          ),
                                          const SizedBox(width: 5),
                                          Text(
                                            'Multiple',
                                            style: TextStyle(
                                              fontFamily: 'Outfit',
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: _isMultiContributor
                                                  ? Colors.white
                                                  : (isDark
                                                      ? Colors.white60
                                                      : Colors.black54),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (!_isMultiContributor) ...[
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: members.map((m) {
                              final isSelected = _paidByUserId == m.userId;
                              return ChoiceChip(
                                avatar: CircleAvatar(
                                  backgroundColor: isSelected
                                      ? Colors.white
                                      : AppColors.primaryTeal,
                                  child: Text(
                                    m.initials,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isSelected
                                          ? AppColors.primaryTeal
                                          : Colors.white,
                                    ),
                                  ),
                                ),
                                label: Text(
                                    '${m.displayName}${m.isOffline ? ' (Offline)' : ''}'),
                                selected: isSelected,
                                selectedColor: AppColors.primaryTeal,
                                backgroundColor: isDark
                                    ? AppColors.darkSurface
                                    : const Color(0xFFF1F5F9),
                                labelStyle: TextStyle(
                                  fontFamily: 'Outfit',
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: isSelected
                                      ? Colors.white
                                      : (isDark
                                          ? AppColors.darkText
                                          : AppColors.lightText),
                                ),
                                onSelected: (selected) {
                                  if (selected) {
                                    setState(() {
                                      _paidByUserId = m.userId;
                                      _paidByName = m.displayName;
                                    });
                                  }
                                },
                              );
                            }).toList(),
                          ),
                        ] else ...[
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color:
                                  isDark ? AppColors.darkSurface : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: isDark
                                      ? AppColors.darkBorder
                                      : AppColors.lightBorder),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Contributed Amounts',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13)),
                                    Text(
                                      '${tour.currencySymbol}${_totalContributions.toStringAsFixed(0)} / ${tour.currencySymbol}${_amountCtrl.text.trim().isEmpty ? '0' : _amountCtrl.text.trim()}',
                                      style: TextStyle(
                                        fontFamily: 'Outfit',
                                        fontWeight: FontWeight.w700,
                                        color: (_totalContributions -
                                                        (double.tryParse(
                                                                _amountCtrl.text
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
                                const Divider(height: 16),
                                ...members.map((m) {
                                  final ctrl =
                                      _contributorControllers[m.userId]!;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      children: [
                                        MemberAvatar(
                                          initials: m.initials,
                                          photoUrl: m.photoUrl,
                                          radius: 14,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            '${m.displayName}${m.isOffline ? ' (Offline)' : ''}',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () {
                                            final totalAmt = double.tryParse(
                                                    _amountCtrl.text.trim()) ??
                                                0.0;
                                            double othersSum = 0.0;
                                            for (final entry
                                                in _contributorControllers
                                                    .entries) {
                                              if (entry.key != m.userId) {
                                                othersSum += double.tryParse(
                                                        entry.value.text
                                                            .trim()) ??
                                                    0.0;
                                              }
                                            }
                                            final rest = totalAmt - othersSum;
                                            setState(() {
                                              ctrl.text = rest > 0
                                                  ? (rest % 1 == 0
                                                      ? rest.toStringAsFixed(0)
                                                      : rest.toStringAsFixed(2))
                                                  : '0';
                                            });
                                          },
                                          style: TextButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8),
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                          child: const Text('Fill Rest',
                                              style: TextStyle(fontSize: 11)),
                                        ),
                                        SizedBox(
                                          width: 100,
                                          height: 40,
                                          child: TextFormField(
                                            controller: ctrl,
                                            keyboardType: const TextInputType
                                                .numberWithOptions(
                                                decimal: true),
                                            textAlign: TextAlign.right,
                                            decoration: InputDecoration(
                                              prefixText:
                                                  '${tour.currencySymbol} ',
                                              isDense: true,
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 8),
                                              border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          10)),
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
                        ],
                        const SizedBox(height: 24),
                        _SectionLabel(title: 'Split Options'),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.darkSurface
                                : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              _SplitModeTab(
                                label: 'Equally (All)',
                                isSelected: _splitMode == 0,
                                onTap: () => setState(() => _splitMode = 0),
                              ),
                              _SplitModeTab(
                                label: 'Specific Members',
                                isSelected: _splitMode == 1,
                                onTap: () => setState(() => _splitMode = 1),
                              ),
                              _SplitModeTab(
                                label: 'Custom Split',
                                isSelected: _splitMode == 2,
                                onTap: () => setState(() => _splitMode = 2),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_splitMode == 0) ...[
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color:
                                  isDark ? AppColors.darkSurface : Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: isDark
                                      ? AppColors.darkBorder
                                      : AppColors.lightBorder),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.people_outline,
                                    color: AppColors.primaryTeal, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    members.isNotEmpty
                                        ? 'Split equally among all ${members.length} members (~${tour.currencySymbol}${((double.tryParse(_amountCtrl.text.trim()) ?? 0.0) / members.length).toStringAsFixed(0)} each)'
                                        : 'All members',
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else if (_splitMode == 1) ...[
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: members.map((m) {
                              final isIncluded =
                                  _selectedMemberIds.contains(m.userId);
                              return FilterChip(
                                label: Text(
                                    '${m.displayName}${m.isOffline ? ' (Offline)' : ''}'),
                                selected: isIncluded,
                                selectedColor: AppColors.primaryTeal
                                    .withValues(alpha: 0.2),
                                checkmarkColor: AppColors.primaryTeal,
                                onSelected: (selected) {
                                  setState(() {
                                    if (selected) {
                                      _selectedMemberIds.add(m.userId);
                                    } else if (_selectedMemberIds.length > 1) {
                                      _selectedMemberIds.remove(m.userId);
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          ),
                          if (_selectedMemberIds.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              '${_selectedMemberIds.length} members selected (~${tour.currencySymbol}${((double.tryParse(_amountCtrl.text.trim()) ?? 0.0) / _selectedMemberIds.length).toStringAsFixed(0)} each)',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? AppColors.darkTextSecondary
                                      : AppColors.lightTextSecondary),
                            ),
                          ],
                        ] else ...[
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color:
                                  isDark ? AppColors.darkSurface : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: isDark
                                      ? AppColors.darkBorder
                                      : AppColors.lightBorder),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Assign Exact Amounts',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13)),
                                    Text(
                                      '${tour.currencySymbol}$_totalCustomSplit / ${tour.currencySymbol}${_amountCtrl.text.trim().isEmpty ? '0' : _amountCtrl.text.trim()}',
                                      style: TextStyle(
                                        fontFamily: 'Outfit',
                                        fontWeight: FontWeight.w700,
                                        color: (_totalCustomSplit -
                                                        (double.tryParse(
                                                                _amountCtrl.text
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
                                const Divider(height: 16),
                                ...members.map((m) {
                                  final ctrl =
                                      _customSplitControllers[m.userId]!;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                              '${m.displayName}${m.isOffline ? ' (Offline)' : ''}',
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13)),
                                        ),
                                        SizedBox(
                                          width: 110,
                                          height: 42,
                                          child: TextFormField(
                                            controller: ctrl,
                                            keyboardType: const TextInputType
                                                .numberWithOptions(
                                                decimal: true),
                                            textAlign: TextAlign.right,
                                            decoration: InputDecoration(
                                              prefixText:
                                                  '${tour.currencySymbol} ',
                                              isDense: true,
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 10),
                                              border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          10)),
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
                        ],
                        const SizedBox(height: 32),
                        GradientButton(
                          onPressed: () => _submit(tour, user.uid, isAdmin),
                          label: widget.existingExpense != null
                              ? 'Update Expense'
                              : 'Save Expense',
                          icon: Icons.check_circle_rounded,
                          gradient: AppColors.primaryGradient,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          },
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String title;
  const _SectionLabel({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontFamily: 'Outfit',
        fontWeight: FontWeight.w700,
        fontSize: 14,
      ),
    );
  }
}

class _SplitModeTab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SplitModeTab({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          onTap();
          HapticFeedback.selectionClick();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10.5, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryTeal : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Outfit',
              fontSize: 12.5,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
              color: isSelected
                  ? Colors.white
                  : (isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary),
            ),
          ),
        ),
      ),
    );
  }
}
