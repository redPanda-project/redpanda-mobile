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

  /// Cursor for paginated fetching; updated after each fetch.
  List<int> lastCursor;

  OHRegistration({
    required this.ohId,
    required this.keypair,
    required this.expiresAtMs,
    this.channelId,
    List<int>? lastCursor,
  }) : lastCursor = lastCursor ?? [];
}
