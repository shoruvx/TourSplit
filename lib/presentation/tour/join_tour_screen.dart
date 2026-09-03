import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../data/services/auth_service.dart';
import '../../data/repositories/tour_repository.dart';
import '../widgets/gradient_button.dart';
import '../widgets/loading_overlay.dart';
import 'widgets/tour_qr_scanner_view.dart';

class JoinTourScreen extends ConsumerStatefulWidget {
  const JoinTourScreen({super.key});

  @override
  ConsumerState<JoinTourScreen> createState() => _JoinTourScreenState();
}

class _JoinTourScreenState extends ConsumerState<JoinTourScreen> {
  int _selectedTab = 0; // 0 = Enter Code, 1 = Scan QR
  final List<TextEditingController> _codeControllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    for (final c in _codeControllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _enteredCode =>
      _codeControllers.map((c) => c.text.trim().toUpperCase()).join();

  Future<void> _submitCode(String code) async {
    if (code.length != 6) {
      setState(() => _errorMessage = 'Please enter all 6 characters');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = ref.read(currentUserProvider).valueOrNull;
      if (user == null) return;

      final tourRepo = ref.read(tourRepositoryProvider);
      final tour = await tourRepo.getTourByInviteCode(code);

      if (tour == null) {
        setState(() {
          _selectedTab = 0;
          _errorMessage = 'No tour found with this code. Please check and try again.';
        });
        return;
      }

      // If already a full member, switch active tour immediately
      if (tour.memberIds.contains(user.uid)) {
        await tourRepo.switchActiveTour(user.uid, tour.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Switched to "${tour.name}"'),
              backgroundColor: AppColors.primaryTeal,
            ),
          );
          context.go('/home');
        }
        return;
      }

      // Join tour directly and set active tour immediately
      await tourRepo.joinTour(
        tourId: tour.id,
        user: user,
      );
      await tourRepo.switchActiveTour(user.uid, tour.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Joined "${tour.name}"! 🎉'),
            backgroundColor: AppColors.positive,
          ),
        );
        context.go('/home');
      }
      return;
    } catch (e, st) {
      debugPrint('[JOIN_ERROR] Error joining tour: $e\n$st');
      setState(() {
        _selectedTab = 0;
        _errorMessage = 'Failed to join tour. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return LoadingOverlay(
      isLoading: _isLoading,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Join Tour'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () => context.pop(),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              // Segmented Tab Selector (Code / QR)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkSurface : const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _TabSelectorButton(
                          label: 'Enter Code',
                          icon: Icons.pin_rounded,
                          isSelected: _selectedTab == 0,
                          onTap: () => setState(() => _selectedTab = 0),
                        ),
                      ),
                      Expanded(
                        child: _TabSelectorButton(
                          label: 'Scan QR',
                          icon: Icons.qr_code_scanner_rounded,
                          isSelected: _selectedTab == 1,
                          onTap: () => setState(() => _selectedTab = 1),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Tab Body
              Expanded(
                child: _selectedTab == 0
                    ? _buildCodeInputView(theme, isDark)
                    : _buildQrScannerView(theme, isDark),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCodeInputView(ThemeData theme, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Text(
            'Enter 6-character tour code',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 32),

          // 6 PIN boxes
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (i) {
                return Container(
                  width: 46,
                  height: 56,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                child: TextFormField(
                  controller: _codeControllers[i],
                  focusNode: _focusNodes[i],
                  textAlign: TextAlign.center,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryTeal,
                  ),
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(1),
                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                  ],
                  decoration: InputDecoration(
                    contentPadding: EdgeInsets.zero,
                    filled: true,
                    fillColor: isDark ? AppColors.darkSurface : Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: AppColors.primaryTeal,
                        width: 2,
                      ),
                    ),
                  ),
                  onChanged: (val) {
                    if (val.isNotEmpty) {
                      _codeControllers[i].text = val.toUpperCase();
                      if (i < 5) {
                        _focusNodes[i + 1].requestFocus();
                      } else {
                        _focusNodes[i].unfocus();
                        _submitCode(_enteredCode);
                      }
                    } else if (i > 0) {
                      _focusNodes[i - 1].requestFocus();
                    }
                  },
                ),
              );
            }),
            ),
          ),

          if (_errorMessage != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: AppColors.danger, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: AppColors.danger, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 40),
          GradientButton(
            onPressed: () => _submitCode(_enteredCode),
            label: 'Request to Join',
            icon: Icons.login_rounded,
            gradient: AppColors.primaryGradient,
          ),
        ],
      ),
    );
  }

  Widget _buildQrScannerView(ThemeData theme, bool isDark) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Point your camera at the Tour QR Code',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: TourQrScannerView(
            onScanned: (code) {
              for (int i = 0; i < 6 && i < code.length; i++) {
                _codeControllers[i].text = code[i];
              }
              _submitCode(code);
            },
            onCancel: () => setState(() => _selectedTab = 0),
          ),
        ),
      ],
    );
  }
}

class _TabSelectorButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _TabSelectorButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        onTap();
        HapticFeedback.selectionClick();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryTeal : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? Colors.white : Colors.grey.shade600,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Outfit',
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? Colors.white : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
