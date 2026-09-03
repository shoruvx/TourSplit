import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_theme.dart';
import '../../data/services/auth_service.dart';
import '../../data/repositories/tour_repository.dart';
import '../widgets/app_text_field.dart';
import '../widgets/gradient_button.dart';
import '../widgets/loading_overlay.dart';

class TourSettingsScreen extends ConsumerStatefulWidget {
  const TourSettingsScreen({super.key});

  @override
  ConsumerState<TourSettingsScreen> createState() => _TourSettingsScreenState();
}

class _TourSettingsScreenState extends ConsumerState<TourSettingsScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _isLoading = false;
  bool _initialized = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveChanges(String tourId) async {
    setState(() => _isLoading = true);
    try {
      await ref.read(tourRepositoryProvider).updateTour(tourId, {
        'name': _nameCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Tour updated!'),
              backgroundColor: AppColors.accent),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _endTour(BuildContext context, String tourId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End Tour?'),
        content: const Text(
            'This will mark the tour as completed. Members won\'t be able to add new expenses.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('End Tour'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await ref.read(tourRepositoryProvider).completeTour(tourId);
      if (mounted) context.go('/home');
    }
  }

  Future<void> _deleteTour(
      BuildContext context, String tourId, String tourName) async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.delete_forever_rounded, color: AppColors.danger),
            const SizedBox(width: 8),
            const Text('Delete Tour?',
                style: TextStyle(color: AppColors.danger)),
          ],
        ),
        content: Text(
          'This will permanently delete "$tourName" including ALL expenses, settlements, and member data.\n\nThis CANNOT be undone!',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Proceed'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;

    final confirmCtrl = TextEditingController();
    final typed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Confirm Deletion',
              style: TextStyle(color: AppColors.danger)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Type the tour name "$tourName" to confirm:',
                  style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              TextField(
                controller: confirmCtrl,
                onChanged: (_) => setS(() {}),
                decoration: InputDecoration(
                  hintText: tourName,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: confirmCtrl.text.trim() == tourName
                    ? AppColors.danger
                    : Colors.grey,
              ),
              onPressed: confirmCtrl.text.trim() == tourName
                  ? () => Navigator.pop(ctx, true)
                  : null,
              child: const Text('Delete Forever'),
            ),
          ],
        ),
      ),
    );

    if (typed != true || !mounted) return;

    setState(() => _isLoading = true);
    try {
      await ref.read(tourRepositoryProvider).deleteTour(tourId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tour deleted permanently.'),
            backgroundColor: AppColors.danger,
          ),
        );
        context.go('/home');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    if (user == null || user.activeTourId == null) {
      return const Scaffold(body: Center(child: Text('No active tour')));
    }
    final tourId = user.activeTourId!;

    final tourStream = ref.watch(tourStreamProvider(tourId));

    return tourStream.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
      data: (tour) {
        if (tour == null) return const Scaffold();

        if (!_initialized) {
          _nameCtrl.text = tour.name;
          _descCtrl.text = tour.description ?? '';
          _initialized = true;
        }

        return LoadingOverlay(
          isLoading: _isLoading,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Tour Settings'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                onPressed: () => context.pop(),
              ),
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppTextField(
                    controller: _nameCtrl,
                    label: 'Tour Name',
                    prefixIcon: Icons.map_rounded,
                    textCapitalization: TextCapitalization.words,
                  ).animate().fadeIn(delay: 100.ms),
                  const SizedBox(height: 16),
                  AppTextField(
                    controller: _descCtrl,
                    label: 'Description',
                    prefixIcon: Icons.description_outlined,
                    maxLines: 3,
                  ).animate().fadeIn(delay: 150.ms),
                  const SizedBox(height: 24),
                  GradientButton(
                    onPressed: () => _saveChanges(tourId),
                    label: 'Save Changes',
                    icon: Icons.save_rounded,
                  ).animate().fadeIn(delay: 200.ms),
                  const SizedBox(height: 32),
                  const Divider(),
                  const SizedBox(height: 16),
                  Text('Danger Zone',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppColors.danger,
                          fontWeight: FontWeight.w700)),
                  if (!tour.isActive)
                    OutlinedButton.icon(
                      onPressed: () async {
                        await ref
                            .read(tourRepositoryProvider)
                            .reopenTour(tourId);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Tour reactivated!'),
                              backgroundColor: AppColors.accent,
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.refresh_rounded,
                          color: AppColors.accent),
                      label: const Text('Reactivate Tour',
                          style: TextStyle(color: AppColors.accent)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.accent),
                      ),
                    ).animate().fadeIn(delay: 250.ms)
                  else
                    OutlinedButton.icon(
                      onPressed: () => _endTour(context, tourId),
                      icon: const Icon(Icons.flag_rounded,
                          color: AppColors.danger),
                      label: const Text('End Tour',
                          style: TextStyle(color: AppColors.danger)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.danger),
                      ),
                    ).animate().fadeIn(delay: 250.ms),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _deleteTour(context, tourId, tour.name),
                    icon: const Icon(Icons.delete_forever_rounded,
                        color: AppColors.danger),
                    label: const Text('Delete Tour Permanently',
                        style: TextStyle(color: AppColors.danger)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.danger),
                    ),
                  ).animate().fadeIn(delay: 300.ms),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
