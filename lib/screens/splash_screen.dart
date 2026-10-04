import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive_flutter/hive_flutter.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _tentCtrl;
  late AnimationController _seamCtrl;
  late AnimationController _warmCtrl;
  late AnimationController _wordCtrl;

  late Animation<Offset> _tentL;
  late Animation<Offset> _tentR;
  late Animation<double> _tentOpacity;
  late Animation<double> _seamOpacity;
  late Animation<double> _warmOpacity;
  late Animation<double> _wordOpacity;
  late Animation<Offset> _wordSlide;

  @override
  void initState() {
    super.initState();

    _tentCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
    _seamCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _warmCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 5000));
    _wordCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));

    _tentL = Tween<Offset>(
      begin: const Offset(-0.15, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _tentCtrl, curve: Curves.easeOutCubic));

    _tentR = Tween<Offset>(
      begin: const Offset(0.15, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _tentCtrl, curve: Curves.easeOutCubic));

    _tentOpacity = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _tentCtrl, curve: const Interval(0, 0.4)));

    _seamOpacity = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _seamCtrl, curve: Curves.easeOut));

    _warmOpacity = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 0.0, end: 0.55)
              .chain(CurveTween(curve: Curves.easeInOut)),
          weight: 50),
      TweenSequenceItem(
          tween: Tween(begin: 0.55, end: 0.0)
              .chain(CurveTween(curve: Curves.easeInOut)),
          weight: 50),
    ]).animate(_warmCtrl);

    _wordOpacity = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _wordCtrl, curve: Curves.easeOut));
    _wordSlide = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _wordCtrl, curve: Curves.easeOutCubic));

    _runSequence();
  }

  bool _navigated = false;

  void _proceedToApp() {
    if (_navigated || !mounted) return;
    _navigated = true;

    try {
      final seenGuide = Hive.isBoxOpen('app_preferences')
          ? (Hive.box('app_preferences')
                  .get('has_completed_onboarding_guide', defaultValue: false)
              as bool)
          : false;
      final isLoggedIn = FirebaseAuth.instance.currentUser != null;

      if (!seenGuide) {
        context.go('/onboarding');
      } else if (isLoggedIn) {
        context.go('/home');
      } else {
        context.go('/login');
      }
    } catch (_) {
      try {
        Navigator.of(context).pushReplacementNamed('/home');
      } catch (_) {}
    }
  }

  Future<void> _runSequence() async {
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;
    _tentCtrl.forward();

    await Future.delayed(const Duration(milliseconds: 1050));
    if (!mounted) return;
    _seamCtrl.forward();

    await Future.delayed(const Duration(milliseconds: 650));
    if (!mounted) return;
    _warmCtrl.repeat();

    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    _wordCtrl.forward();

    await Future.delayed(const Duration(milliseconds: 2500));
    if (!mounted) return;
    _proceedToApp();
  }

  @override
  void dispose() {
    _tentCtrl.dispose();
    _seamCtrl.dispose();
    _warmCtrl.dispose();
    _wordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final skipToEnd = reduceMotion;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _proceedToApp,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            SizedBox(
              width: 380,
              height: 380,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _warmCtrl,
                    builder: (context, _) {
                      final v = skipToEnd ? 0.4 : _warmOpacity.value;
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          Opacity(
                            opacity: v * 0.55,
                            child: Container(
                              width: 380,
                              height: 380,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(colors: [
                                  Color(0x80F59E0B),
                                  Color(0x00000000),
                                ]),
                              ),
                            ),
                          ),
                          Opacity(
                            opacity: v,
                            child: Transform.translate(
                              offset: const Offset(-40, -30),
                              child: Container(
                                width: 240,
                                height: 240,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(colors: [
                                    Color(0xF2FCD34D),
                                    Color(0x00000000),
                                  ]),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  AnimatedBuilder(
                    animation:
                        Listenable.merge([_tentCtrl, _seamCtrl]),
                    builder: (context, _) {
                      final tl = skipToEnd ? Offset.zero : _tentL.value;
                      final tr = skipToEnd ? Offset.zero : _tentR.value;
                      final to = skipToEnd ? 1.0 : _tentOpacity.value;
                      final so = skipToEnd ? 1.0 : _seamOpacity.value;

                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          FractionalTranslation(
                            translation: tl,
                            child: Opacity(
                              opacity: to,
                              child: CustomPaint(
                                size: const Size(380, 380),
                                painter: _TentPainter(
                                    side: _Side.left,
                                    seamOpacity: so),
                              ),
                            ),
                          ),
                          FractionalTranslation(
                            translation: tr,
                            child: Opacity(
                              opacity: to,
                              child: CustomPaint(
                                size: const Size(380, 380),
                                painter: _TentPainter(
                                    side: _Side.right,
                                    seamOpacity: so),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 0),
            AnimatedBuilder(
              animation: _wordCtrl,
              builder: (context, _) {
                final o = skipToEnd ? 1.0 : _wordOpacity.value;
                final s = skipToEnd ? Offset.zero : _wordSlide.value;
                return FractionalTranslation(
                  translation: s,
                  child: Opacity(
                    opacity: o,
                    child: Column(
                      children: [
                        RichText(
                          text: const TextSpan(
                            style: TextStyle(
                              fontFamily: 'Outfit',
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.24,
                              color: Color(0xFFF8FAFC),
                            ),
                            children: [
                              TextSpan(text: 'Tour'),
                              TextSpan(
                                  text: 'Split',
                                  style: TextStyle(color: Color(0xFF0D9488))),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Split the costs, keep the memories',
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 12,
                            letterSpacing: 0.24,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
  }
}

enum _Side { left, right }

class _TentPainter extends CustomPainter {
  final _Side side;
  final double seamOpacity;
  _TentPainter({required this.side, required this.seamOpacity});

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 512;
    final sy = size.height / 512;

    Path buildPath() {
      final p = Path();
      if (side == _Side.left) {
        p.moveTo(256 * sx, 96 * sy);
        p.cubicTo(216 * sx, 170 * sy, 150 * sx, 310 * sy, 100 * sx, 420 * sy);
        p.lineTo(244 * sx, 420 * sy);
        p.cubicTo(244 * sx, 320 * sy, 250 * sx, 200 * sy, 256 * sx, 96 * sy);
      } else {
        p.moveTo(256 * sx, 96 * sy);
        p.cubicTo(296 * sx, 170 * sy, 362 * sx, 310 * sy, 412 * sx, 420 * sy);
        p.lineTo(268 * sx, 420 * sy);
        p.cubicTo(268 * sx, 320 * sy, 262 * sx, 200 * sy, 256 * sx, 96 * sy);
      }
      p.close();
      return p;
    }

    final path = buildPath();

    final rect = Rect.fromLTWH(100 * sx, 96 * sy, 312 * sx, 324 * sy);
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: side == _Side.left
          ? const [
              Color(0xFF26C6B6),
              Color(0xFF0D9488),
              Color(0xFF0A7E74),
            ]
          : const [
              Color(0xFF0A5F55),
              Color(0xFF004D40),
              Color(0xFF003830),
            ],
      stops: const [0.0, 0.6, 1.0],
    );

    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.fill;

    canvas.drawShadow(path, Colors.black.withValues(alpha: 0.5), 6, false);
    canvas.drawPath(path, paint);

    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    if (side == _Side.left) {
      edge.color = Colors.white.withValues(alpha: 0.25);
    } else {
      edge.color = Colors.black.withValues(alpha: 0.35);
    }
    canvas.drawPath(path, edge);
  }

  @override
  bool shouldRepaint(covariant _TentPainter old) =>
      old.side != side || old.seamOpacity != seamOpacity;
}
