import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// Placeholder — routes to login/register
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.go('/login');
    });
    return const Scaffold(body: SizedBox());
  }
}
