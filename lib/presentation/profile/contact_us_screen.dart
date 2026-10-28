import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../core/theme/app_theme.dart';
import '../widgets/app_notification_sheet.dart';
import '../widgets/member_avatar.dart';

class _CategoryItem {
  final String label;
  final IconData icon;
  final String hint;

  const _CategoryItem({
    required this.label,
    required this.icon,
    required this.hint,
  });
}

class ContactUsScreen extends StatefulWidget {
  const ContactUsScreen({super.key});

  @override
  State<ContactUsScreen> createState() => _ContactUsScreenState();
}

class _ContactUsScreenState extends State<ContactUsScreen> {
  final _suggestionCtrl = TextEditingController();
  bool _isSubmitting = false;
  int _selectedCategoryIndex = 0;

  /// Formspree endpoint Form ID.
  static const String _formspreeFormId = 'xbgggrej';

  static const List<_CategoryItem> _categoryItems = [
    _CategoryItem(
      label: 'Feature Idea',
      icon: Icons.lightbulb_outline_rounded,
      hint: 'Describe your idea or what feature you would love to see in TourSplit...',
    ),
    _CategoryItem(
      label: 'Bug Report',
      icon: Icons.shield_outlined,
      hint: 'Describe what happened, any error message, or which screen you were on...',
    ),
    _CategoryItem(
      label: 'Feedback',
      icon: Icons.chat_bubble_outline_rounded,
      hint: 'Tell us what you love or how we can make TourSplit better for you...',
    ),
    _CategoryItem(
      label: 'Question',
      icon: Icons.explore_outlined,
      hint: 'What can we help clarify about your trips, split math, or settings?',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _suggestionCtrl.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _suggestionCtrl.removeListener(_onTextChanged);
    _suggestionCtrl.dispose();
    super.dispose();
  }

  String _getUserInitials(User? user) {
    final name = user?.displayName?.trim() ?? '';
    if (name.isEmpty) return 'GT';
    final parts = name.split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  Future<void> _sendFeedback() async {
    final text = _suggestionCtrl.text.trim();

    if (text.isEmpty) {
      showAppNotificationSheet(
        context,
        icon: Icons.edit_note_rounded,
        iconColor: AppColors.warning,
        title: 'Empty Message',
        message:
            'Please write your feedback, idea, or issue description before sending.',
        primaryButtonText: 'Got It',
      );
      return;
    }

    setState(() => _isSubmitting = true);
    HapticFeedback.lightImpact();

    final category = _categoryItems[_selectedCategoryIndex].label;
    final user = FirebaseAuth.instance.currentUser;
    final name =
        (user?.displayName != null && user!.displayName!.trim().isNotEmpty)
            ? user.displayName!.trim()
            : 'TourSplit Traveler';
    final email = (user?.email != null && user!.email!.trim().isNotEmpty)
        ? user.email!.trim()
        : '';
    bool sentViaFormspree = false;

    // 1. Send via Formspree
    try {
      final formspreeUrl = Uri.parse(
        _formspreeFormId.startsWith('http')
            ? _formspreeFormId
            : 'https://formspree.io/f/$_formspreeFormId',
      );

      final response = await http.post(
        formspreeUrl,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'name': name,
          'email': email.isNotEmpty ? email : 'no-reply@toursplit.app',
          'category': category,
          'message': text,
          '_subject': '[$category] TourSplit Feedback${name.isNotEmpty ? ' from $name' : ''}',
          'userId': user?.uid ?? 'guest',
          'submittedAt': DateTime.now().toIso8601String(),
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        sentViaFormspree = true;
      } else {
        debugPrint(
            '[FORMSPREE] Submission returned status ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('[FORMSPREE] HTTP post error: $e');
    }

    // 2. Save directly to Cloud Firestore as guaranteed backup
    try {
      await FirebaseFirestore.instance.collection('suggestions').add({
        'name': name,
        'email': email,
        'category': category,
        'suggestion': text,
        'userId': user?.uid,
        'userEmail': user?.email,
        'userName': user?.displayName,
        'sentViaFormspree': sentViaFormspree,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[SUGGESTION] Cloud save error: $e');
    }

    if (mounted) {
      setState(() => _isSubmitting = false);
      _suggestionCtrl.clear();

      if (sentViaFormspree) {
        showAppNotificationSheet(
          context,
          icon: Icons.mark_email_read_rounded,
          iconColor: AppColors.primaryTeal,
          title: 'Feedback Sent!',
          message:
              'Thank you for reaching out! Your $category has been sent directly to the TourSplit team. We review every message carefully.',
          primaryButtonText: 'Done',
        );
      } else {
        showAppNotificationSheet(
          context,
          icon: Icons.task_alt_rounded,
          iconColor: AppColors.primaryTeal,
          title: 'Feedback Received',
          message:
              'Thank you! Your feedback has been safely recorded and submitted to the team.',
          primaryButtonText: 'Done',
        );
      }
    }
  }

  Widget _buildCategoryCard(int index, bool isDark) {
    final item = _categoryItems[index];
    final isSelected = _selectedCategoryIndex == index;

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedCategoryIndex = index);
      },
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xFF0D2522) : const Color(0xFFE6F5F2))
              : (isDark ? AppColors.darkCard : const Color(0xFFF8FAFC)),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? AppColors.primaryTeal
                : (isDark ? AppColors.darkBorder : const Color(0xFFE2E8F0)),
            width: isSelected ? 1.8 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primaryTeal
                        .withValues(alpha: isDark ? 0.35 : 0.20),
                    blurRadius: 14,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              item.icon,
              size: 28,
              color: isSelected
                  ? AppColors.primaryTeal
                  : (isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary),
            ),
            const SizedBox(height: 10),
            Text(
              item.label,
              style: TextStyle(
                fontFamily: 'Outfit',
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected
                    ? (isDark ? Colors.white : AppColors.primaryTeal)
                    : (isDark ? AppColors.darkText : AppColors.lightText),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = FirebaseAuth.instance.currentUser;
    final initials = _getUserInitials(user);

    final displayName =
        (user?.displayName != null && user!.displayName!.trim().isNotEmpty)
            ? user.displayName!.trim()
            : 'Guest Traveler';
    final displayEmail =
        (user?.email != null && user!.email!.trim().isNotEmpty)
            ? user.email!.trim()
            : '';

    final currentHint = _categoryItems[_selectedCategoryIndex].hint;

    return PopScope(
      canPop: true,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).maybePop();
            },
          ),
          toolbarHeight: 60,
          titleSpacing: 0,
          title: const Text(
            'Contact Support',
            style: TextStyle(
              fontFamily: 'Outfit',
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              color: AppColors.primaryTeal,
            ),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Sender Identity Pill
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF131A19)
                      : const Color(0xFFF1F8F6),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.primaryTeal
                        .withValues(alpha: isDark ? 0.35 : 0.25),
                    width: 1.1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.primaryTeal,
                          width: 1.5,
                        ),
                      ),
                      child: MemberAvatar(
                        initials: initials,
                        photoUrl: user?.photoURL,
                        radius: 20,
                        enableTap: false,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Submitting as',
                            style: TextStyle(
                              fontFamily: 'Outfit',
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.lightTextSecondary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            displayEmail.isNotEmpty
                                ? '$displayName ($displayEmail)'
                                : displayName,
                            style: TextStyle(
                              fontFamily: 'Outfit',
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? AppColors.darkText
                                  : AppColors.lightText,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 2. 2x2 Category Cards Grid
              Row(
                children: [
                  Expanded(child: _buildCategoryCard(0, isDark)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildCategoryCard(1, isDark)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _buildCategoryCard(2, isDark)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildCategoryCard(3, isDark)),
                ],
              ),

              const SizedBox(height: 22),

              // 3. Message Input Box with live Character Counter
              Stack(
                children: [
                  TextField(
                    controller: _suggestionCtrl,
                    maxLines: 7,
                    minLines: 5,
                    maxLength: 500,
                    textCapitalization: TextCapitalization.sentences,
                    buildCounter: (
                      context, {
                      required currentLength,
                      required isFocused,
                      maxLength,
                    }) {
                      return const SizedBox.shrink();
                    },
                    decoration: InputDecoration(
                      hintText: currentHint,
                      hintStyle: TextStyle(
                        fontFamily: 'Outfit',
                        fontSize: 13.5,
                        height: 1.4,
                        color: isDark
                            ? AppColors.darkTextSecondary.withValues(alpha: 0.6)
                            : AppColors.lightTextSecondary
                                .withValues(alpha: 0.7),
                      ),
                      filled: true,
                      fillColor: isDark
                          ? AppColors.darkCard
                          : const Color(0xFFFAFAFA),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: isDark
                              ? AppColors.darkBorder
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: isDark
                              ? AppColors.darkBorder
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: AppColors.primaryTeal,
                          width: 1.8,
                        ),
                      ),
                      contentPadding:
                          const EdgeInsets.fromLTRB(16, 16, 16, 36),
                    ),
                  ),
                  Positioned(
                    bottom: 12,
                    right: 16,
                    child: Text(
                      '${_suggestionCtrl.text.length}/500',
                      style: TextStyle(
                        fontFamily: 'Outfit',
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppColors.darkTextSecondary.withValues(alpha: 0.7)
                            : AppColors.lightTextSecondary
                                .withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 22),

              // 4. Send Message Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(AppRadius.button),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryTeal.withValues(alpha: 0.35),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _sendFeedback,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.button),
                      ),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.white,
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.near_me_rounded,
                                size: 19,
                                color: Colors.white,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Send Message',
                                style: TextStyle(
                                  fontFamily: 'Outfit',
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15.5,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
