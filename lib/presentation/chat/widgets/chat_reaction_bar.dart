import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/app_theme.dart';

class ChatReactionBar extends StatelessWidget {
  static const List<String> defaultEmojis = ['❤️', '👍', '😆', '😮', '😢', '😡'];

  final String? currentReaction;
  final ValueChanged<String> onSelectEmoji;

  const ChatReactionBar({
    super.key,
    this.currentReaction,
    required this.onSelectEmoji,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: defaultEmojis.asMap().entries.map((entry) {
          final index = entry.key;
          final emoji = entry.value;
          final isSelected = currentReaction == emoji;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () {
                  HapticFeedback.mediumImpact();
                  onSelectEmoji(emoji);
                },
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primaryTeal.withValues(alpha: 0.25)
                        : Colors.transparent,
                    shape: BoxShape.circle,
                    border: isSelected
                        ? Border.all(color: AppColors.primaryTeal, width: 1.5)
                        : null,
                  ),
                  child: Text(
                    emoji,
                    style: TextStyle(
                      fontSize: isSelected ? 26 : 24,
                    ),
                  ),
                ),
              ),
            ),
          )
              .animate()
              .scale(
                duration: 200.ms,
                delay: Duration(milliseconds: index * 30),
                curve: Curves.easeOutBack,
              );
        }).toList(),
      ),
    );
  }
}
