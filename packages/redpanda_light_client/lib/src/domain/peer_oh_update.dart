import 'package:redpanda_light_client/src/domain/oh_descriptor.dart';
import 'package:redpanda_light_client/src/domain/state_update.dart';

/// An authenticated in-band announcement (T21 OH failover / T42 multi-OH)
/// carrying the channel partner's FULL current mailbox set. Emitted after a
/// fetched `oh_update` ChannelMessage was ratchet-decrypted (the decryption IS
/// the authenticity check — only the partner holds the message keys); the app
/// layer persists the whole set so the deposit fan-out survives an app
/// restart.
class PeerOhUpdate extends StateUpdate {
  final String channelId;

  /// The partner's complete current mailbox set (each: endpoint, handle id,
  /// auth key). Never empty. The first entry is the primary. Deposits (T42)
  /// fan out to every entry; the receiver deduplicates by message id.
  final List<OHDescriptor> descriptors;

  const PeerOhUpdate({required this.channelId, required this.descriptors});
}
