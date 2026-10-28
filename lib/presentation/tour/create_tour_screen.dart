import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../data/services/auth_service.dart';
import '../../data/models/tour_model.dart';
import '../../data/repositories/tour_repository.dart';
import '../../data/services/offline_tour_queue_service.dart';
import '../../data/services/active_tour_cache_service.dart';
import '../widgets/gradient_button.dart';
import '../widgets/loading_overlay.dart';
import 'widgets/tour_created_dialog.dart';
import '../widgets/app_notification_sheet.dart';

class CreateTourScreen extends ConsumerStatefulWidget {
  const CreateTourScreen({super.key});

  @override
  ConsumerState<CreateTourScreen> createState() => _CreateTourScreenState();
}

class _CreateTourScreenState extends ConsumerState<CreateTourScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _budgetCtrl = TextEditingController();

  bool _isLoading = false;
  String _selectedCurrency = 'BDT';
  String _selectedCurrencySymbol = '৳';
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 4));

  @override
  void initState() {
    super.initState();
    _budgetCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _budgetCtrl.dispose();
    super.dispose();
  }

  int get _tripDays {
    final diff = _endDate.difference(_startDate).inDays + 1;
    return diff.clamp(1, 999);
  }

  double? get _budgetAmount {
    final clean = _budgetCtrl.text.replaceAll(',', '').trim();
    if (clean.isEmpty) return null;
    return double.tryParse(clean);
  }

  double? get _dailyEstimate {
    final b = _budgetAmount;
    if (b == null || b <= 0) return null;
    return b / _tripDays;
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      initialDateRange: DateTimeRange(
        start: _startDate,
        end: _endDate.isBefore(_startDate)
            ? _startDate.add(const Duration(days: 3))
            : _endDate,
      ),
      builder: (context, child) {
        final theme = Theme.of(context);
        return Theme(
          data: theme.copyWith(
            colorScheme: theme.colorScheme.copyWith(
              primary: AppColors.primaryTeal,
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  Future<bool> _isOffline() async {
    final result = await Connectivity().checkConnectivity();
    return result.every((r) => r == ConnectivityResult.none);
  }

  Future<void> _createTour() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final user = ref.read(currentUserProvider).value;
      if (user == null) return;

      final offline = await _isOffline();

      if (offline) {
        // ── Offline path: save locally ────────────────────────────────────
        final queueService = ref.read(offlineTourQueueProvider);
        final tour = await queueService.createTourLocally(
          name: _nameCtrl.text.trim(),
          currency: _selectedCurrency,
          currencySymbol: _selectedCurrencySymbol,
          adminId: user.uid,
          startDate: _startDate,
          endDate: _endDate,
          budget: _budgetAmount,
          adminName: user.displayName,
          adminEmail: user.email,
        );

        final adminMember = TourMemberModel(
          userId: user.uid,
          displayName: user.displayName.isNotEmpty ? user.displayName : 'Admin',
          email: user.email,
          role: 'admin',
          status: 'active',
          joinedAt: DateTime.now(),
        );

        // Cache locally so the rest of the app can read it
        await ActiveTourCacheService.setActiveTourId(tour.id);
        await ActiveTourCacheService.cacheActiveTour(
          tour: tour,
          members: [adminMember],
        );
        ref.read(activeTourIdOverrideProvider.notifier).state = tour.id;

        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.cloud_off_rounded, color: Colors.white, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tour saved offline — will sync when connected',
                      style: TextStyle(
                        fontFamily: 'Outfit',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              backgroundColor: AppColors.warning,
              duration: Duration(seconds: 4),
            ),
          );
          await TourCreatedDialog.show(
            context,
            tourName: tour.name,
            inviteCode: tour.inviteCode,
            onDone: () {
              Navigator.of(context).pop();
              context.go('/home');
            },
          );
          if (mounted) context.go('/home');
        }
        return;
      }

      // ── Online path ────────────────────────────────────────────────────
      final tourRepo = ref.read(tourRepositoryProvider);
      final tour = await tourRepo.createTour(
        name: _nameCtrl.text.trim(),
        description: null,
        currency: _selectedCurrency,
        currencySymbol: _selectedCurrencySymbol,
        adminId: user.uid,
        startDate: _startDate,
        endDate: _endDate,
        budget: _budgetAmount,
        coverImageUrl: null,
      );

      await tourRepo.addAdminAsMember(tourId: tour.id, admin: user);
      await tourRepo.switchActiveTour(user.uid, tour.id, tour: tour);
      ref.read(activeTourIdOverrideProvider.notifier).state = tour.id;

      if (mounted) {
        setState(() => _isLoading = false);
        await TourCreatedDialog.show(
          context,
          tourName: tour.name,
          inviteCode: tour.inviteCode,
          onDone: () {
            Navigator.of(context).pop();
            context.go('/home');
          },
        );
        if (mounted) {
          context.go('/home');
        }
        return;
      }
    } catch (e) {
      if (mounted) {
        showAppNotificationSheet(
          context,
          icon: Icons.error_outline_rounded,
          iconColor: AppColors.danger,
          title: 'Tour Creation Failed',
          message: 'Failed to create tour: $e',
          primaryButtonText: 'Dismiss',
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

    final fieldBg = isDark ? AppColors.darkSurface : const Color(0xFFF8FAFC);
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final hintColor = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/tours');
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
                  context.go('/tours');
                }
              },
            ),
            title: const Text(
              'New Tour',
              style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold),
            ),
            centerTitle: true,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. TOUR NAME
                  _FieldLabel(label: 'Tour Name', isRequired: true),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    style: const TextStyle(
                      fontFamily: 'Outfit',
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                    decoration: InputDecoration(
                      hintText: "e.g. Cox's Bazar Trip",
                      hintStyle: TextStyle(
                        fontFamily: 'Outfit',
                        fontWeight: FontWeight.normal,
                        color: hintColor,
                      ),
                      prefixIcon: const Icon(
                        Icons.explore_outlined,
                        color: AppColors.primaryTeal,
                        size: 20,
                      ),
                      filled: true,
                      fillColor: fieldBg,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: borderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: borderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: AppColors.primaryTeal,
                          width: 1.5,
                        ),
                      ),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Tour name is required'
                        : null,
                  ).animate().fadeIn(duration: 200.ms),

                  const SizedBox(height: 22),

                  // 2. CONNECTED DATE RANGE CARD
                  _FieldLabel(label: 'Date Range'),
                  const SizedBox(height: 8),
                  _DateRangePickerCard(
                    startDate: _startDate,
                    endDate: _endDate,
                    tripDays: _tripDays,
                    isDark: isDark,
                    onTap: _pickDateRange,
                  ).animate().fadeIn(delay: 60.ms, duration: 200.ms),

                  const SizedBox(height: 22),

                  // 3. CURRENCY SELECTOR
                  _FieldLabel(label: 'Currency'),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: _selectedCurrency,
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: isDark ? Colors.white : AppColors.lightText,
                    ),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(
                        Icons.payments_outlined,
                        color: AppColors.primaryTeal,
                        size: 20,
                      ),
                      filled: true,
                      fillColor: fieldBg,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: borderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: borderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: AppColors.primaryTeal,
                          width: 1.5,
                        ),
                      ),
                    ),
                    items: AppConstants.currencies.map((c) {
                      return DropdownMenuItem<String>(
                        value: c['code'],
                        child: Text(
                          '${c['code']} - ${c['name']} (${c['symbol']})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (code) {
                      if (code != null) {
                        final found = AppConstants.currencies.firstWhere(
                          (c) => c['code'] == code,
                        );
                        setState(() {
                          _selectedCurrency = code;
                          _selectedCurrencySymbol = found['symbol']!;
                        });
                      }
                    },
                  ).animate().fadeIn(delay: 120.ms, duration: 200.ms),

                  const SizedBox(height: 22),

                  // 4. TARGET BUDGET (OPTIONAL)
                  _FieldLabel(label: 'Target Budget', isOptional: true),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _budgetCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: const TextStyle(
                      fontFamily: 'Outfit',
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                    decoration: InputDecoration(
                      hintText: '0.00',
                      hintStyle: TextStyle(
                        fontFamily: 'Outfit',
                        fontWeight: FontWeight.normal,
                        color: hintColor,
                      ),
                      prefixIcon: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        child: Text(
                          _selectedCurrencySymbol,
                          style: const TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryTeal,
                          ),
                        ),
                      ),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 0,
                      ),
                      filled: true,
                      fillColor: fieldBg,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: borderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: borderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: AppColors.primaryTeal,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ).animate().fadeIn(delay: 180.ms, duration: 200.ms),

                  const SizedBox(height: 8),

                  // Live Daily Estimate or Hint Note
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: _dailyEstimate != null
                        ? Container(
                            key: const ValueKey('estimate'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primaryTeal.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.insights_rounded,
                                  size: 16,
                                  color: AppColors.primaryTeal,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '~$_selectedCurrencySymbol${NumberFormat('#,##0').format(_dailyEstimate)} / day estimated for $_tripDays ${_tripDays == 1 ? "day" : "days"}',
                                    style: const TextStyle(
                                      fontFamily: 'Outfit',
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.primaryTeal,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Padding(
                            key: const ValueKey('hint'),
                            padding: const EdgeInsets.only(left: 4),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline_rounded,
                                  size: 14,
                                  color: hintColor,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Optional • Set a budget limit to track your spending',
                                  style: TextStyle(
                                    fontFamily: 'Outfit',
                                    fontSize: 12,
                                    color: hintColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),

                  const SizedBox(height: 36),

                  // 5. CTA BUTTON
                  GradientButton(
                    onPressed: _createTour,
                    label: 'Create Tour',
                    icon: Icons.arrow_forward_rounded,
                    gradient: AppColors.primaryGradient,
                  ).animate().fadeIn(delay: 240.ms, duration: 200.ms),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  final bool isRequired;
  final bool isOptional;

  const _FieldLabel({
    required this.label,
    this.isRequired = false,
    this.isOptional = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Outfit',
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        if (isRequired)
          const Text(
            ' *',
            style: TextStyle(
              color: AppColors.danger,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        if (isOptional)
          Text(
            ' (Optional)',
            style: TextStyle(
              fontFamily: 'Outfit',
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
      ],
    );
  }
}

class _DateRangePickerCard extends StatelessWidget {
  final DateTime startDate;
  final DateTime endDate;
  final int tripDays;
  final bool isDark;
  final VoidCallback onTap;

  const _DateRangePickerCard({
    required this.startDate,
    required this.endDate,
    required this.tripDays,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final startFmt = DateFormat('EEE, MMM d').format(startDate);
    final endFmt = DateFormat('EEE, MMM d').format(endDate);
    final yearFmt = startDate.year == endDate.year
        ? '${startDate.year}'
        : '${startDate.year} - ${endDate.year}';

    final fieldBg = isDark ? AppColors.darkSurface : const Color(0xFFF8FAFC);
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final subColor = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: fieldBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryTeal.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.calendar_month_rounded,
                      color: AppColors.primaryTeal,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                startFmt,
                                style: const TextStyle(
                                  fontFamily: 'Outfit',
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                child: Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 14,
                                  color: subColor,
                                ),
                              ),
                              Text(
                                endFmt,
                                style: const TextStyle(
                                  fontFamily: 'Outfit',
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          yearFmt,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 12,
                            color: subColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryTeal.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.primaryTeal.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      '$tripDays ${tripDays == 1 ? "Day" : "Days"}',
                      style: const TextStyle(
                        fontFamily: 'Outfit',
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: AppColors.primaryTeal,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
