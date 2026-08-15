import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

class AppLaunchReveal extends StatefulWidget {
  const AppLaunchReveal({super.key, required this.child});

  final Widget child;

  @override
  State<AppLaunchReveal> createState() => _AppLaunchRevealState();
}

class _AppLaunchRevealState extends State<AppLaunchReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _glowPulse;
  late final Animation<double> _fieldProgress;
  late final Animation<double> _taglineOpacity;
  late final Animation<Offset> _taglineOffset;
  late final Animation<double> _exitOpacity;
  bool _started = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..addStatusListener(_handleStatus);

    _logoScale = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.55, curve: Curves.easeOutBack),
      ),
    );
    _logoOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.35, curve: Curves.easeOut),
    );
    _glowPulse = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.15, 0.65, curve: Curves.easeOutCubic),
      ),
    );
    _fieldProgress = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.18, 0.72, curve: Curves.easeOutCubic),
    );
    _taglineOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.48, 0.85, curve: Curves.easeOut),
    );
    _taglineOffset =
        Tween<Offset>(begin: const Offset(0, 0.22), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.48, 0.85, curve: Curves.easeOutCubic),
          ),
        );
    _exitOpacity = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.88, 1.0, curve: Curves.easeIn),
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _finished = true);
      });
    } else {
      unawaited(_controller.forward());
    }
  }

  void _handleStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    setState(() => _finished = true);
  }

  @override
  void dispose() {
    _controller
      ..removeStatusListener(_handleStatus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (!_finished)
          AnimatedBuilder(
            key: const ValueKey('app-launch-reveal'),
            animation: _controller,
            builder: (context, _) {
              final dark = Theme.of(context).brightness == Brightness.dark;
              return Opacity(
                opacity: _exitOpacity.value,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: dark
                          ? const [
                              Color(0xFF070F0A),
                              Color(0xFF0D1F16),
                              Color(0xFF0A1A12),
                            ]
                          : const [
                              Color(0xFF1A3D28),
                              Color(0xFF173B2C),
                              Color(0xFF0F2A1E),
                            ],
                    ),
                  ),
                  child: SafeArea(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Glow orb behind logo
                          SizedBox(
                            width: 200,
                            height: 200,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // Amber glow pulse
                                Opacity(
                                  opacity: _glowPulse.value * 0.35,
                                  child: Container(
                                    width: 160 + (_glowPulse.value * 30),
                                    height: 160 + (_glowPulse.value * 30),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: RadialGradient(
                                        colors: [
                                          const Color(0xFFD5A43B)
                                              .withValues(alpha: 0.6),
                                          const Color(0xFFD5A43B)
                                              .withValues(alpha: 0),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                // Green soft glow
                                Opacity(
                                  opacity: _glowPulse.value * 0.45,
                                  child: Container(
                                    width: 130,
                                    height: 130,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: RadialGradient(
                                        colors: [
                                          AppColors.leaf.withValues(alpha: 0.5),
                                          AppColors.leaf.withValues(alpha: 0),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                // Logo
                                Opacity(
                                  opacity: _logoOpacity.value,
                                  child: Transform.scale(
                                    scale: _logoScale.value,
                                    child: Container(
                                      width: 100,
                                      height: 100,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(26),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.35,
                                            ),
                                            blurRadius: 32,
                                            offset: const Offset(0, 16),
                                          ),
                                          BoxShadow(
                                            color: AppColors.leaf.withValues(
                                              alpha: 0.3,
                                            ),
                                            blurRadius: 24,
                                            offset: const Offset(0, 8),
                                          ),
                                        ],
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(26),
                                        child: Image.asset(
                                          'assets/branding/app_icon.png',
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          // Animated field landscape line
                          SizedBox(
                            width: 160,
                            height: 24,
                            child: CustomPaint(
                              painter: _FieldRevealPainter(
                                progress: _fieldProgress.value,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          // App name
                          Opacity(
                            opacity: _logoOpacity.value,
                            child: Text(
                              'KrishiSathi',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.8,
                                fontFamilyFallback: const [
                                  'Noto Sans',
                                  'Noto Sans Devanagari',
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          // Tagline
                          FadeTransition(
                            opacity: _taglineOpacity,
                            child: SlideTransition(
                              position: _taglineOffset,
                              child: Text(
                                'हर खेत का साथी',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.65),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0.2,
                                  fontFamilyFallback: const [
                                    'Noto Sans Devanagari',
                                    'Noto Sans',
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _FieldRevealPainter extends CustomPainter {
  const _FieldRevealPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    // Field horizon line
    final line = Path()
      ..moveTo(0, size.height * 0.75)
      ..quadraticBezierTo(
        size.width * 0.22,
        size.height * 0.1,
        size.width * 0.48,
        size.height * 0.65,
      )
      ..quadraticBezierTo(
        size.width * 0.72,
        size.height * 1.1,
        size.width,
        size.height * 0.3,
      );
    final metric = line.computeMetrics().first;
    final visible = metric.extractPath(0, metric.length * progress);
    canvas.drawPath(
      visible,
      Paint()
        ..color = AppColors.leaf.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round,
    );

    // Sun / amber spark dot
    final sunOpacity = (progress - 0.4).clamp(0.0, 0.6) / 0.6;
    if (sunOpacity > 0) {
      final angle = math.pi * 0.18;
      final cx = size.width * 0.72;
      final cy = size.height * 0.18;
      canvas.drawCircle(
        Offset(cx, cy),
        4.5 * sunOpacity,
        Paint()..color = const Color(0xFFE1A82B).withValues(alpha: sunOpacity),
      );
      // Rays
      for (var i = 0; i < 4; i++) {
        final a = angle + (i * math.pi / 2);
        final rayOpacity = sunOpacity * 0.5;
        canvas.drawLine(
          Offset(cx + math.cos(a) * 7, cy + math.sin(a) * 7),
          Offset(cx + math.cos(a) * 11, cy + math.sin(a) * 11),
          Paint()
            ..color = const Color(0xFFE1A82B).withValues(alpha: rayOpacity)
            ..strokeWidth = 1.5
            ..strokeCap = StrokeCap.round,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_FieldRevealPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
