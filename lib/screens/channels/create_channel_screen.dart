import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';
import 'package:redpanda/repositories/channel_repository.dart';
import 'package:redpanda/repositories/outbound_handle_repository.dart';
import 'package:redpanda/shared/providers.dart';

class CreateChannelScreen extends ConsumerStatefulWidget {
  const CreateChannelScreen({super.key});

  @override
  ConsumerState<CreateChannelScreen> createState() =>
      _CreateChannelScreenState();
}

class _CreateChannelScreenState extends ConsumerState<CreateChannelScreen> {
  final _labelController = TextEditingController();
  Channel? _createdChannel;
  String? _qrData;
  bool _ohRegistered = false;

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _generateChannel() async {
    if (_labelController.text.trim().isEmpty) return;

    final channel = await Channel.generate(_labelController.text.trim());
    if (!mounted) return;
    setState(() {
      _createdChannel = channel;
      // Show the QR right away; the peer OH is embedded once registered.
      _qrData = channel.toJson();
    });

    // Add to repository
    await ref.read(channelRepositoryProvider).addChannel(channel);

    // Fire-and-forget by design: the QR is usable without the OH and gets
    // upgraded in place once registration succeeds.
    unawaited(_registerOwnOh(channel));
  }

  /// Registers our own Outbound Handle for this channel and embeds it into
  /// the QR code (v3 `oh` field), so the scanning peer knows where to send
  /// messages.
  Future<void> _registerOwnOh(Channel channel) async {
    final client = ref.read(redPandaClientProvider);
    final ownDescriptor = await ref
        .read(outboundHandleRepositoryProvider)
        .ensureOwnDescriptor(client, channel.id);

    if (ownDescriptor == null || !mounted) return;
    if (_createdChannel?.id != channel.id) return;

    setState(() {
      // Transient copy for the QR only: in the QR JSON, `oh` means "the OH
      // of whoever generated this code". Our persisted channel keeps
      // peerOhDescriptor = null until we scan the peer's code.
      _qrData = channel.copyWith(peerOhDescriptor: ownDescriptor).toJson();
      _ohRegistered = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_createdChannel != null) {
      // Show QR Code view
      return Scaffold(
        appBar: AppBar(title: const Text('Channel Created')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _createdChannel!.label,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 20),
              QrImageView(
                data: _qrData!,
                version: QrVersions.auto,
                size: 250.0,
                backgroundColor: Colors.white,
              ),
              const SizedBox(height: 20),
              Text(
                _ohRegistered
                    ? 'Scan this code on another device to join.'
                    : 'Scan this code on another device to join.\n'
                          '(Registering mailbox… reopen the QR via the chat '
                          'screen to include it.)',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: () => context.go('/'),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Create New Channel')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _labelController,
              decoration: const InputDecoration(
                labelText: 'Channel Name',
                hintText: 'e.g. Family Chat to secret things',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _generateChannel,
              child: const Text('Generate Secure Channel'),
            ),
          ],
        ),
      ),
    );
  }
}
