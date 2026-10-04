import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';
import 'package:redpanda/repositories/channel_repository.dart';
import 'package:redpanda/repositories/outbound_handle_repository.dart';
import 'package:redpanda/services/message_sync_service.dart';
import 'package:redpanda/shared/providers.dart';

class JoinChannelScreen extends ConsumerStatefulWidget {
  const JoinChannelScreen({super.key, this.injectedCode});

  /// Test hook (T140): a QR payload handed to the SAME handler a camera scan
  /// feeds ([_JoinChannelScreenState._processCode]), so parsing, validation
  /// and persistence run through the production join path on a device
  /// without a camera (the headless emulator duo E2E passes it as the route's
  /// `extra`). When set, the camera scanner is not started at all. Not
  /// `@visibleForTesting` only because the router (lib code) forwards it.
  final String? injectedCode;

  @override
  ConsumerState<JoinChannelScreen> createState() => _JoinChannelScreenState();
}

class _JoinChannelScreenState extends ConsumerState<JoinChannelScreen> {
  /// Only created when the camera is used (no [JoinChannelScreen.injectedCode]).
  MobileScannerController? _controller;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    final injected = widget.injectedCode;
    if (injected == null) {
      _controller = MobileScannerController();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _processCode(injected);
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;
    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue != null) {
        _processCode(barcode.rawValue!);
        break; // Only process the first valid code
      }
    }
  }

  Future<void> _processCode(String code) async {
    setState(() {
      _isProcessing = true;
    });

    try {
      // Decode channel (QR v4: the code carries only the channel secret).
      final channel = await Channel.fromJson(code);

      // Add to repository. Re-scanning a QR for a channel we already joined
      // keeps the existing row (and its ratchet state) intact — see H8.
      final isNewChannel = await ref
          .read(channelRepositoryProvider)
          .addChannel(channel);

      // T111: hand the channel to the network worker through the ONE restore
      // entry point (full argument set), BEFORE the OH registration — the
      // rendezvous publish needs the channel's rendezvous state to exist.
      // Its own catch: a failure here must not be reported as "invalid QR
      // code", and `MessageSyncService`'s channel-table watcher repairs it.
      try {
        await ref.read(messageSyncServiceProvider).registerChannel(channel.id);
      } catch (e) {
        debugPrint('Failed to register the joined channel: $e');
      }

      // Register our own OH for this channel in the background so it's
      // ready when we share our QR code with the counterpart later.
      unawaited(
        ref
            .read(outboundHandleRepositoryProvider)
            .ensureOwnDescriptor(ref.read(redPandaClientProvider), channel.id),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isNewChannel
                  ? 'Joined channel: ${channel.label}'
                  : 'Channel already joined: ${channel.label}',
            ),
          ),
        );
        context.go('/');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Invalid Channel Code: $e')));
        // Resume scanning after a delay
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          setState(() {
            _isProcessing = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan to Join')),
      body: _controller == null
          ? const Center(child: CircularProgressIndicator())
          : MobileScanner(controller: _controller, onDetect: _onDetect),
    );
  }
}
