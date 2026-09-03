import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_theme.dart';
import '../../data/services/auth_service.dart';
import '../widgets/gradient_button.dart';
import '../widgets/app_text_field.dart';
import '../widgets/loading_overlay.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  bool _isLoading = false;
  bool _emailSent = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendReset() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(authServiceProvider)
          .sendPasswordResetEmail(_emailCtrl.text.trim());
      if (mounted) setState(() => _emailSent = true);
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage =
            'Could not send reset email. Please check your email address.');
      }
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
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () => context.pop(),
          ),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _emailSent
                ? _buildSuccessState(theme)
                : _buildForm(theme, isDark),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.primaryBlue.withOpacity(0.12),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.lock_reset_rounded,
              color: AppColors.primaryBlue, size: 32),
        ).animate().fadeIn().scale(),
        const SizedBox(height: 24),
        Text(
          'Reset Password',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ).animate().fadeIn(delay: 100.ms),
        const SizedBox(height: 8),
        Text(
          'Enter your email and we\'ll send you a link to reset your password.',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: isDark
                ? AppColors.darkTextSecondary
                : AppColors.lightTextSecondary,
          ),
        ).animate().fadeIn(delay: 150.ms),
        const SizedBox(height: 32),
        Form(
          key: _formKey,
          child: Column(
            children: [
              AppTextField(
                controller: _emailCtrl,
                label: 'Email',
                hint: 'you@example.com',
                keyboardType: TextInputType.emailAddress,
                prefixIcon: Icons.email_outlined,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Email is required';
                  if (!v.contains('@')) return 'Enter a valid email';
                  return null;
                },
              ).animate().fadeIn(delay: 200.ms),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(_errorMessage!,
                      style: const TextStyle(color: AppColors.danger)),
                ).animate().fadeIn(),
              ],
              const SizedBox(height: 24),
              GradientButton(
                onPressed: _sendReset,
                label: 'Send Reset Link',
                icon: Icons.send_rounded,
              ).animate().fadeIn(delay: 250.ms),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              gradient: AppColors.successGradient,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.mark_email_read_rounded,
                color: Colors.white, size: 48),
          ).animate().fadeIn().scale(),
          const SizedBox(height: 24),
          Text(
            'Email Sent!',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ).animate().fadeIn(delay: 200.ms),
          const SizedBox(height: 12),
          Text(
            'We\'ve sent a password reset link to\n${_emailCtrl.text.trim()}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ).animate().fadeIn(delay: 300.ms),
          const SizedBox(height: 32),
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('Back to Sign In'),
          ).animate().fadeIn(delay: 400.ms),
        ],
      ),
    );
  }
}
