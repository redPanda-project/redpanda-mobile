import 'package:redpanda_light_client/src/domain/oh_descriptor.dart';

/// An authenticated in-band announcement (T21 OH failover) that the channel
/// partner moved their mailbox to a new Full Node. Emitted after a fetched
/// `oh_update` ChannelMessage was ratchet-decrypted (the decryption IS the
/// authenticity check — only the partner holds the message keys); the app
/// layer persists the new descriptor so sends survive an app restart.
class PeerOhUpdate {
  final String channelId;

  /// The partner's NEW mailbox descriptor (endpoint, handle id, auth key).
  final OHDescriptor descriptor;

  const PeerOhUpdate({required this.channelId, required this.descriptor});
}
