import 'package:redpanda_light_client/src/crypto/oh_keypair.dart';

/// Represents a registered Outbound Handle on a Full Node.
///
/// After successful registration, this object holds the OH credentials
/// needed for fetching incoming messages.
class OHRegistration {
  final List<int> ohId;
  final OHKeypair keypair;
  final int expiresAtMs;
  final String? channelId;

  /// Address (host:port) of the Full Node the OH was registered on.
  /// Needed to build the OHDescriptor shared via QR code.
  final String? serverEndpoint;

  /// Cursor for paginated fetching; updated after each fetch.
  int lastCursor;

  OHRegistration({
    required this.ohId,
    required this.keypair,
    required this.expiresAtMs,
    this.channelId,
    this.serverEndpoint,
    int? lastCursor,
  }) : lastCursor = lastCursor ?? 0;
}
