import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';
import 'package:redpanda/repositories/channel_repository.dart';

class CreateChannelScreen extends ConsumerStatefulWidget {
  const CreateChannelScreen({super.key});

  @override
  ConsumerState<CreateChannelScreen> createState() =>
      _CreateChannelScreenState();
}

class _CreateChannelScreenState extends ConsumerState<CreateChannelScreen> {
  final _labelController = TextEditingController();
  Channel? _createdChannel;

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  void _generateChannel() {
    if (_labelController.text.trim().isEmpty) return;

    final channel = Channel.generate(_labelController.text.trim());
    setState(() {
      _createdChannel = channel;
    });

    // Add to repository
    ref.read(channelRepositoryProvider).addChannel(channel);
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
                data: _createdChannel!.toJson(),
                version: QrVersions.auto,
                size: 250.0,
                backgroundColor: Colors.white,
              ),
              const SizedBox(height: 20),
              const Text(
                'Scan this code on another device to join.',
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
