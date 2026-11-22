import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:redpanda/services/field_diagnostics.dart';

/// T180: visible while field diagnostics send this device's identifiers to
/// Sentry. Nothing at all while they are off (or unavailable on this
/// network). Tapping opens the screen with the switch.
class FieldDiagnosticsIndicator extends ConsumerWidget {
  const FieldDiagnosticsIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only the on/off edge: the provider also changes with every upload
    // count, and the home app bar must not rebuild for those.
    final on = ref.watch(
      fieldDiagnosticsProvider.select((s) => s.available && s.enabled),
    );
    if (!on) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Diagnostics to Sentry are on',
      child: InkWell(
        key: const Key('field-diagnostics-indicator'),
        borderRadius: BorderRadius.circular(999),
        onTap: () => context.push('/debug-stats'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: scheme.errorContainer,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bug_report, size: 16, color: scheme.onErrorContainer),
              const SizedBox(width: 4),
              Text(
                'DIAG',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: scheme.onErrorContainer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
