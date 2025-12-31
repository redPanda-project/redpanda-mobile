import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';
import 'package:redpanda/repositories/channel_repository.dart';

class JoinChannelScreen extends ConsumerStatefulWidget {
  const JoinChannelScreen({super.key});

  @override
  ConsumerState<JoinChannelScreen> createState() => _JoinChannelScreenState();
}

class _JoinChannelScreenState extends ConsumerState<JoinChannelScreen> {
  final MobileScannerController controller = MobileScannerController();
  bool _isProcessing = false;

  @override
  void dispose() {
    controller.dispose();
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
      // Decode channel
      final channel = Channel.fromJson(code);
      
      // Add to repository
      await ref.read(channelRepositoryProvider).addChannel(channel);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Joined channel: ${channel.label}')),
        );
        context.go('/');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invalid Channel Code: $e')),
        );
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
      body: MobileScanner(
        controller: controller,
        onDetect: _onDetect,
      ),
    );
  }
}
