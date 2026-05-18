import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_colors.dart';
import 'auth_controller.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _textFade;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _logoScale = Tween<double>(begin: 0.7, end: 1.0).animate(CurvedAnimation(
        parent: _ac,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOutBack)));
    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
        parent: _ac, curve: const Interval(0.0, 0.5, curve: Curves.easeOut)));
    _textFade = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
        parent: _ac, curve: const Interval(0.4, 1.0, curve: Curves.easeOut)));
    _ac.forward();
    _navigate();
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  Future<void> _navigate() async {
    if (!mounted) return;
    final session = await ref.read(authControllerProvider.future);
    if (!mounted) return;
    if (session != null && session.isValid) {
      final hasPin = await ref.read(secureStorageServiceProvider).hasPin();
      if (!mounted) return;
      context.go(hasPin ? '/pin-entry' : '/pin-setup');
    } else {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final logoSize =
              (constraints.maxWidth * 0.38).clamp(120.0, 180.0).toDouble();
          final glowSize = logoSize * 2.0;
          final textSize =
              (constraints.maxWidth * 0.055).clamp(18.0, 22.0).toDouble();

          return Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  'assets/images/imagesplash.png',
                  fit: BoxFit.cover,
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.primary.withValues(alpha: 0.75),
                      AppColors.primaryDarker.withValues(alpha: 0.9),
                    ],
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _SplashWavePainter(),
                  ),
                ),
              ),
              SafeArea(
                child: Stack(
                  children: [
                    Align(
                      alignment: Alignment.center,
                      child: AnimatedBuilder(
                        animation: _ac,
                        builder: (context, child) => FadeTransition(
                          opacity: _logoFade,
                          child: ScaleTransition(
                            scale: _logoScale,
                            child: child,
                          ),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: glowSize,
                              height: glowSize,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    AppColors.secondary.withValues(alpha: 0.25),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                            Container(
                              width: glowSize * 0.7,
                              height: glowSize * 0.7,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    AppColors.secondary.withValues(alpha: 0.14),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                            Container(
                              width: logoSize,
                              height: logoSize,
                              padding: EdgeInsets.all(logoSize * 0.18),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius:
                                    BorderRadius.circular(logoSize * 0.25),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.secondary
                                        .withValues(alpha: 0.45),
                                    blurRadius: 40,
                                    offset: const Offset(0, 16),
                                  ),
                                  BoxShadow(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.25),
                                    blurRadius: 30,
                                    offset: const Offset(0, 20),
                                  ),
                                ],
                              ),
                              child: Image.asset(
                                'assets/images/logo.png',
                                fit: BoxFit.contain,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: FadeTransition(
                        opacity: _textFade,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 36),
                          child: Text.rich(
                            TextSpan(
                              text: 'Mais um ',
                              style: TextStyle(
                                color: AppColors.secondary,
                                fontSize: textSize,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                              ),
                              children: [
                                TextSpan(
                                  text: 'cliente que volta.',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: textSize,
                                  ),
                                ),
                              ],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SplashWavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stroke1 = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..shader = const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          AppColors.secondary,
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final stroke2 = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          AppColors.secondary.withValues(alpha: 0.55),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final baseY = size.height * 0.78;
    final path1 = Path()
      ..moveTo(-20, baseY)
      ..cubicTo(
        size.width * 0.35,
        baseY - 40,
        size.width * 0.65,
        baseY + 40,
        size.width + 20,
        baseY - 12,
      );

    final path2 = Path()
      ..moveTo(-20, baseY + 26)
      ..cubicTo(
        size.width * 0.35,
        baseY - 12,
        size.width * 0.7,
        baseY + 64,
        size.width + 20,
        baseY + 10,
      );

    canvas.drawPath(path1, stroke1);
    canvas.drawPath(path2, stroke2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
