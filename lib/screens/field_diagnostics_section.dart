import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:redpanda/services/field_diagnostics.dart';

/// T180: the "Diagnostics to Sentry" switch and the device name, for the
/// Peer Network Status screen. Renders nothing when the network gate is
/// closed (any network other than the testnet).
class FieldDiagnosticsSection extends ConsumerStatefulWidget {
  const FieldDiagnosticsSection({super.key});

  @override
  ConsumerState<FieldDiagnosticsSection> createState() =>
      _FieldDiagnosticsSectionState();
}

class _FieldDiagnosticsSectionState
    extends ConsumerState<FieldDiagnosticsSection> {
  late final TextEditingController _name;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: ref.read(fieldDiagnosticsProvider).deviceName,
    );
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(fieldDiagnosticsProvider);
    if (!state.available) return const SizedBox.shrink();
    final notifier = ref.read(fieldDiagnosticsProvider.notifier);
    final status = !state.enabled
        ? null
        : state.uploadsActive
        ? '${state.buffered} waiting, ${state.uploaded} sent, '
              '${state.uploadFailures} failed attempts'
        : '${state.buffered} recorded — this build does not upload '
              '(release builds only)';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          key: const Key('field-diagnostics-switch'),
          title: const Text('Diagnostics to Sentry'),
          subtitle: Text(
            'Testnet only. Sends this device\'s connection, mailbox and '
            'message events to Sentry — including mailbox ids, message ids, '
            'node ids and addresses in clear text — under the device name '
            'below. Events already handed to Sentry may still go out for a '
            'few seconds after switching off.'
            '${status == null ? '' : '\n$status'}',
          ),
          value: state.enabled,
          onChanged: (value) => notifier.setEnabled(value),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            key: const Key('field-diagnostics-device-name'),
            controller: _name,
            maxLength: FieldDiagnosticsService.maxDeviceNameLength,
            decoration: const InputDecoration(
              hintText: 'Device name (e.g. Mi 10)',
              counterText: '',
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: notifier.setDeviceName,
            onTapOutside: (_) {
              FocusScope.of(context).unfocus();
              if (_name.text.trim() != state.deviceName) {
                notifier.setDeviceName(_name.text);
              }
            },
          ),
        ),
      ],
    );
  }
}
