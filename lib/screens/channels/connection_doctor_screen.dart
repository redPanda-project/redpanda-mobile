import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:redpanda/shared/providers.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart' hide Channel;

/// Verbindungs-Doctor (T25): runs the per-channel diagnostic stages
/// sequentially and renders each with a traffic-light dot, its runtime and a
/// human-readable detail — never a silent fail. All logic lives in the light
/// client's [RedPandaClient.runChannelDoctor]; this screen only renders.
class ConnectionDoctorScreen extends ConsumerStatefulWidget {
  final String channelUuid;

  const ConnectionDoctorScreen({super.key, required this.channelUuid});

  @override
  ConsumerState<ConnectionDoctorScreen> createState() =>
      _ConnectionDoctorScreenState();
}

class _ConnectionDoctorScreenState
    extends ConsumerState<ConnectionDoctorScreen> {
  bool _running = false;
  ChannelDoctorReport? _report;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _report = null;
    });
    final client = ref.read(redPandaClientProvider);
    final report = await client.runChannelDoctor(widget.channelUuid);
    if (!mounted) return;
    setState(() {
      _running = false;
      _report = report;
    });
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Connection doctor'),
            Text(
              'Step-by-step channel checks',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
      ),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Each stage runs one after another. Green means healthy, amber '
              'means limited, red means it needs attention.',
            ),
          ),
          if (report != null)
            for (final stage in report.stages) _StageTile(stage: stage),
          if (_running)
            const ListTile(
              leading: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              title: Text('Running checks…'),
              subtitle: Text('The loopback stage can take up to 60 s.'),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _running ? null : _run,
        icon: const Icon(Icons.refresh),
        label: Text(report == null ? 'Run' : 'Run again'),
      ),
    );
  }
}

/// One diagnostic stage row: traffic-light dot, name + runtime, detail.
class _StageTile extends StatelessWidget {
  final DoctorStage stage;

  const _StageTile({required this.stage});

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (stage.status) {
      DoctorStatus.ok => (Colors.green, Icons.check_circle),
      DoctorStatus.warn => (Colors.amber, Icons.warning),
      DoctorStatus.fail => (Colors.red, Icons.error),
    };
    return ListTile(
      leading: Icon(icon, color: color),
      title: Row(
        children: [
          Expanded(child: Text(stage.name)),
          Text(
            _fmtRuntime(stage.durationMs),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
      subtitle: Text(stage.detail),
    );
  }

  static String _fmtRuntime(int ms) =>
      ms < 1000 ? '$ms ms' : '${(ms / 1000).toStringAsFixed(1)} s';
}
