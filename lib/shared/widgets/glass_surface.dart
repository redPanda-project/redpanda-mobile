import 'dart:ui';

import 'package:flutter/material.dart';

/// Frosted-glass chrome for floating bars and capsules: a blurred,
/// translucent surface that lets scrolled content show through instead of
/// sitting on a flat, opaque Material container. Used for the top app bar
/// and floating action/composer capsules; not for list content itself.
class GlassSurface extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;
  final double blurSigma;
  final Color? tint;

  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(28)),
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    this.blurSigma = 20,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: (tint ?? scheme.surface).withValues(
              alpha: isDark ? 0.55 : 0.7,
            ),
            borderRadius: borderRadius,
            border: Border.all(color: scheme.outline.withValues(alpha: 0.2)),
          ),
          child: child,
        ),
      ),
    );
  }
}
