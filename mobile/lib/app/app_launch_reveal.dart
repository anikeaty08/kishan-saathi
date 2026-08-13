import 'dart:async';

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
  late final Animation<double> _markScale;
  late final Animation<double> _markOpacity;
  late final Animation<double> _fieldProgress;
  late final Animation<double> _nameOpacity;
  late final Animation<Offset> _nameOffset;
  bool _started = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 760),
    )..addStatusListener(_handleStatus);
    _markScale = Tween<double>(begin: 0.92, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.72, curve: Curves.easeOutCubic),
      ),
    );
    _markOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.36, curve: Curves.easeOut),
    );
    _fieldProgress = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.12, 0.74, curve: Curves.easeOutCubic),
    );
    _nameOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.36, 1, curve: Curves.easeOut),
    );
    _nameOffset = Tween<Offset>(begin: const Offset(0, 0.16), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.36, 1, curve: Curves.easeOutCubic),
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
          ColoredBox(
            key: const ValueKey('app-launch-reveal'),
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF102017)
                : const Color(0xFFF6F2E8),
            child: Center(
              child: AnimatedBuilder(
                animation: _controller,
                child: Image.asset(
                  'assets/branding/app_icon.png',
                  width: 108,
                  height: 108,
                  fit: BoxFit.contain,
                ),
                builder: (context, mark) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Opacity(
                      opacity: _markOpacity.value,
                      child: Transform.scale(
                        scale: _markScale.value,
                        child: mark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    SizedBox(
                      width: 126,
                      height: 18,
                      child: CustomPaint(
                        painter: _FieldRevealPainter(
                          progress: _fieldProgress.value,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FadeTransition(
                      opacity: _nameOpacity,
                      child: SlideTransition(
                        position: _nameOffset,
                        child: Text(
                          'KrishiSathi',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color:
                                    Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? const Color(0xFFF4EFE2)
                                    : AppColors.forest,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.7,
                              ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
    final line = Path()
      ..moveTo(3, size.height * 0.72)
      ..quadraticBezierTo(
        size.width * 0.26,
        size.height * 0.12,
        size.width * 0.51,
        size.height * 0.7,
      )
      ..quadraticBezierTo(
        size.width * 0.73,
        size.height * 1.06,
        size.width - 3,
        size.height * 0.32,
      );
    final metric = line.computeMetrics().first;
    final visible = metric.extractPath(0, metric.length * progress);
    canvas.drawPath(
      visible,
      Paint()
        ..color = AppColors.leaf
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round,
    );
    final sunPaint = Paint()
      ..color = const Color(0xFFE1A82B).withValues(alpha: progress);
    canvas.drawCircle(
      Offset(size.width * 0.73, size.height * 0.22),
      3.5 * progress,
      sunPaint,
    );
  }

  @override
  bool shouldRepaint(_FieldRevealPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
