import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class ShareChannelDialog extends StatelessWidget {
  final String channelName;
  final String qrData;

  const ShareChannelDialog({
    super.key,
    required this.channelName,
    required this.qrData,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Share $channelName"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("Scan this QR code to join the channel"),
          const SizedBox(height: 20),
          SizedBox(
            width: 200,
            height: 200,
            child: QrImageView(
              data: qrData,
              version: QrVersions.auto,
              size: 200.0,
            ),
          ),
          const SizedBox(height: 16),
          Text("Channel Code", style: Theme.of(context).textTheme.labelSmall),
          SelectableText(
            qrData,
            style: const TextStyle(fontFamily: 'Courier', fontSize: 10),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("Close"),
        ),
      ],
    );
  }
}
