import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../data/services/auth_service.dart';
import '../../data/repositories/tour_repository.dart';
import '../widgets/gradient_button.dart';
import '../widgets/loading_overlay.dart';

class CreateTourScreen extends ConsumerStatefulWidget {
  const CreateTourScreen({super.key});

  @override
  ConsumerState<CreateTourScreen> createState() => _CreateTourScreenState();
}

class _CreateTourScreenState extends ConsumerState<CreateTourScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _budgetCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  bool _isLoading = false;
  String _selectedCurrency = 'BDT';
  String _selectedCurrencySymbol = '৳';
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 4));
  String? _selectedCoverPreset;

  final List<Map<String, String>> _coverPresets = [
    {'name': 'Beach', 'emoji': '🏖️', 'desc': 'Coastal & Tropical'},
    {'name': 'Mountains', 'emoji': '🏔️', 'desc': 'Hiking & Peaks'},
    {'name': 'Road Trip', 'emoji': '🚗', 'desc': 'Highway Drive'},
    {'name': 'Camping', 'emoji': '🏕️', 'desc': 'Outdoors & Tents'},
    {'name': 'City Life', 'emoji': '🏙️', 'desc': 'Urban & Sights'},
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _budgetCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked;
        if (_endDate.isBefore(_startDate)) {
          _endDate = _startDate.add(const Duration(days: 3));
        }
      });
    }
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate.isAfter(_startDate) ? _endDate : _startDate,
      firstDate: _startDate,
      lastDate: DateTime(2035),
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  Future<void> _createTour() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final user = ref.read(currentUserProvider).valueOrNull;
      if (user == null) return;

      final budgetText = _budgetCtrl.text.trim();
      final budget = budgetText.isNotEmpty ? double.tryParse(budgetText) : null;

      final tourRepo = ref.read(tourRepositoryProvider);
      final tour = await tourRepo.createTour(
        name: _nameCtrl.text.trim(),
        description:
            _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        currency: _selectedCurrency,
        currencySymbol: _selectedCurrencySymbol,
        adminId: user.uid,
        startDate: _startDate,
        endDate: _endDate,
        budget: budget,
        coverImageUrl: _selectedCoverPreset,
      );

      await tourRepo.addAdminAsMember(tourId: tour.id, admin: user);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Tour "${tour.name}" created! Invite code: ${tour.inviteCode}'),
            backgroundColor: AppColors.accent,
            duration: const Duration(seconds: 4),
          ),
        );
        context.go('/home');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create tour: $e'),
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
    final user = ref.watch(currentUserProvider).valueOrNull;

    return LoadingOverlay(
      isLoading: _isLoading,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => context.pop(),
          ),
          title: const Text('New Tour'),
          centerTitle: true,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FieldLabel(label: 'Tour Name *'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    hintText: 'Tour name',
                    hintStyle: TextStyle(
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.lightTextSecondary,
                    ),
                    filled: true,
                    fillColor: isDark
                        ? AppColors.darkSurface
                        : const Color(0xFFF1F5F9),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: isDark
                            ? AppColors.darkBorder
                            : AppColors.lightBorder,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: isDark
                            ? AppColors.darkBorder
                            : AppColors.lightBorder,
                      ),
                    ),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Tour name required'
                      : null,
                ).animate().fadeIn(delay: 100.ms),
                const SizedBox(height: 20),
                _FieldLabel(label: 'Your Name (Admin) *'),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkSurface
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color:
                          isDark ? AppColors.darkBorder : AppColors.lightBorder,
                    ),
                  ),
                  child: Text(
                    user?.displayName ?? 'Tour Admin',
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 16,
                      color: isDark ? AppColors.darkText : AppColors.lightText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ).animate().fadeIn(delay: 150.ms),
                const SizedBox(height: 20),
                _FieldLabel(label: 'Tour Cover Theme (Optional)'),
                const SizedBox(height: 8),
                SizedBox(
                  height: 90,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _coverPresets.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (ctx, i) {
                      final item = _coverPresets[i];
                      final isSelected = _selectedCoverPreset == item['name'];
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedCoverPreset =
                                isSelected ? null : item['name'];
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 86,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primaryTeal.withValues(alpha: 0.15)
                                : (isDark
                                    ? AppColors.darkSurface
                                    : const Color(0xFFF1F5F9)),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.primaryTeal
                                  : (isDark
                                      ? AppColors.darkBorder
                                      : AppColors.lightBorder),
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(item['emoji']!,
                                  style: const TextStyle(fontSize: 28)),
                              const SizedBox(height: 4),
                              Text(
                                item['name']!,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: isSelected
                                      ? AppColors.primaryTeal
                                      : (isDark
                                          ? AppColors.darkText
                                          : AppColors.lightText),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ).animate().fadeIn(delay: 200.ms),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _FieldLabel(label: 'Start Date'),
                          const SizedBox(height: 8),
                          _DateSelectorBox(
                            date: _startDate,
                            onTap: _pickStartDate,
                            isDark: isDark,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _FieldLabel(label: 'End Date'),
                          const SizedBox(height: 8),
                          _DateSelectorBox(
                            date: _endDate,
                            onTap: _pickEndDate,
                            isDark: isDark,
                          ),
                        ],
                      ),
                    ),
                  ],
                ).animate().fadeIn(delay: 250.ms),
                const SizedBox(height: 20),
                _FieldLabel(label: 'Budget Limit (Optional)'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _budgetCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    hintText: '0',
                    prefixText: '$_selectedCurrencySymbol ',
                    prefixStyle: const TextStyle(fontWeight: FontWeight.bold),
                    filled: true,
                    fillColor: isDark
                        ? AppColors.darkSurface
                        : const Color(0xFFF1F5F9),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: isDark
                            ? AppColors.darkBorder
                            : AppColors.lightBorder,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: isDark
                            ? AppColors.darkBorder
                            : AppColors.lightBorder,
                      ),
                    ),
                  ),
                ).animate().fadeIn(delay: 300.ms),
                const SizedBox(height: 20),
                _FieldLabel(label: 'Currency'),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _selectedCurrency,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: isDark
                        ? AppColors.darkSurface
                        : const Color(0xFFF1F5F9),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: isDark
                            ? AppColors.darkBorder
                            : AppColors.lightBorder,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: isDark
                            ? AppColors.darkBorder
                            : AppColors.lightBorder,
                      ),
                    ),
                  ),
                  items: AppConstants.currencies.map((c) {
                    return DropdownMenuItem<String>(
                      value: c['code'],
                      child:
                          Text('${c['code']} - ${c['name']} (${c['symbol']})'),
                    );
                  }).toList(),
                  onChanged: (code) {
                    if (code != null) {
                      final found = AppConstants.currencies
                          .firstWhere((c) => c['code'] == code);
                      setState(() {
                        _selectedCurrency = code;
                        _selectedCurrencySymbol = found['symbol']!;
                      });
                    }
                  },
                ).animate().fadeIn(delay: 350.ms),
                const SizedBox(height: 32),
                GradientButton(
                  onPressed: _createTour,
                  label: 'Create Tour',
                  icon: Icons.add_rounded,
                  gradient: AppColors.primaryGradient,
                ).animate().fadeIn(delay: 400.ms),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  const _FieldLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontFamily: 'Outfit',
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
    );
  }
}

class _DateSelectorBox extends StatelessWidget {
  final DateTime date;
  final VoidCallback onTap;
  final bool isDark;

  const _DateSelectorBox({
    required this.date,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_rounded,
                size: 18, color: AppColors.primaryTeal),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                DateFormat('yyyy-MM-dd').format(date),
                style: const TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
