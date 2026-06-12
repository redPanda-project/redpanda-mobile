import 'package:redpanda_light_client/src/crypto/crypto_utils.dart';
import 'package:redpanda_light_client/src/domain/reverse_garlic_block.dart';
import 'package:redpanda_light_client/src/garlic/garlic_builder.dart';
import 'package:redpanda_light_client/src/garlic/hop_selector.dart';

/// Builds Reverse Garlic Blocks (Frontend MS05).
///
/// An RGB describes the return path to the sender's own OH mailbox: a fresh
/// random 16-byte session tag, an expiry timestamp and the relay hops the
/// responder's reply onion must traverse (master spec MS05, Decision 6 —
/// hop descriptors, not pre-encrypted layers). The actual reply onion is
/// built by the responder with the shared [GarlicBuilder].
class RgbBuilder {
  /// RGBs expire this long after creation (master spec MS05, section 6).
  /// The responder must not use an expired RGB; the issuer prunes the
  /// matching session tag after [SessionTagStore.maxTagAge].
  static const Duration rgbLifetime = Duration(hours: 24);

  final HopSelector _hopSelector;

  RgbBuilder(this._hopSelector);

  /// Builds an RGB pointing at the caller's own OH mailbox [ohId], with a
  /// fresh random session tag and up to [hopCount] return hops selected from
  /// the known peers ([excludeAddresses]/[excludeNodeIds] as in
  /// [HopSelector.selectHops]; pass the OH host so the return path never
  /// starts or ends at the mailbox node itself).
  ///
  /// Returns null when no eligible hop candidates are known — the message
  /// then travels without a reply path (the responder falls back to the
  /// forward MS04 path, master spec MS05, OQ 3).
  ReverseGarlicBlock? build({
    required List<int> ohId,
    int hopCount = 3,
    Set<String> excludeAddresses = const {},
    Set<String> excludeNodeIds = const {},
  }) {
    final hops = _hopSelector.selectHops(
      count: hopCount,
      excludeAddresses: excludeAddresses,
      excludeNodeIds: excludeNodeIds,
    );
    if (hops.isEmpty) return null;

    return ReverseGarlicBlock(
      expiryTs: DateTime.now().add(rgbLifetime).millisecondsSinceEpoch,
      sessionTag: CryptoUtils.randomBytes(GarlicBuilder.sessionTagLength),
      ohId: ohId,
      hops: hops,
    );
  }
}
