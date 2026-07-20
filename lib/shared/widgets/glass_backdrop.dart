import 'package:flutter/material.dart';

/// Soft, theme-tinted color wash behind a screen's content. Without this,
/// `GlassSurface`'s translucency has nothing but a flat scaffold color to
/// diffract, so the floating bars/capsules read as barely-visible flat
/// panels instead of glass. Two large, softly faded color blobs anchored
/// near the top give the blur something to catch.
class GlassBackdrop extends StatelessWidget {
  final Widget child;

  const GlassBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: scheme.surface),
        Positioned(
          top: -90,
          left: -70,
          child: _Blob(color: scheme.primary, size: 300),
        ),
        Positioned(
          top: -60,
          right: -90,
          child: _Blob(color: scheme.tertiary, size: 260),
        ),
        child,
      ],
    );
  }
}

class _Blob extends StatelessWidget {
  final Color color;
  final double size;

  const _Blob({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: 0.4), color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}
