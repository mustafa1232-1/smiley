import 'package:flutter/material.dart';

/// One-shot entrance that fades and slides its [child] upward. Built on
/// [TweenAnimationBuilder] so it starts immediately and settles with no pending
/// timers — safe to use on screens driven by `pumpAndSettle` in tests.
class FadeSlideIn extends StatelessWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 450),
    this.curve = Curves.easeOutCubic,
    this.beginOffset = 18,
  });

  final Widget child;
  final Duration duration;
  final Curve curve;
  final double beginOffset;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: duration,
      curve: curve,
      builder: (context, value, child) {
        return Opacity(
          opacity: value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - value) * beginOffset),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// One-shot pop-in: scales its [child] up from [beginScale] with a springy
/// curve while fading in. Finite and timer-free.
class PopIn extends StatelessWidget {
  const PopIn({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 500),
    this.beginScale = 0.7,
  });

  final Widget child;
  final Duration duration;
  final double beginScale;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: duration,
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        final scale = beginScale + (1 - beginScale) * value;
        return Opacity(
          opacity: value.clamp(0.0, 1.0),
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: child,
    );
  }
}
