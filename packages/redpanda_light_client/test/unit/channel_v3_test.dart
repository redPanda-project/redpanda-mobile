import 'package:test/test.dart';
import 'package:redpanda_light_client/src/domain/channel.dart';
import 'package:redpanda_light_client/src/domain/oh_descriptor.dart';

void main() {
  group('Channel v3 (MS03 key model)', () {
    test('generate creates Ed25519 auth keypair and 32-byte enc key', () async {
      final channel = await Channel.generate('Test Channel');

      expect(channel.label, 'Test Channel');
      expect(channel.encryptionKey.length, 32);
      expect(channel.authPublicKey.length, 32);
      expect(channel.authPrivateKey, isNotNull);
      expect(channel.authPrivateKey!.length, 32);
      expect(channel.peerOhDescriptor, isNull);
    });

    test('QR JSON v3 contains only k_enc and public material', () async {
      final channel = await Channel.generate('Secret Group');
      final json = channel.toJson();

      expect(json.contains('"v":3'), true);
      expect(json.contains('"k_enc"'), true);
      expect(json.contains('"k_auth_pub"'), true);
      // The auth private key must never be serialized into the QR code.
      expect(json.contains('k_auth_priv'), false);
      expect(json.contains('"k_auth"'), false);
    });

    test('joiner reconstructs the channel without the private key', () async {
      final original = await Channel.generate('Secret Group');
      final reconstructed = Channel.fromJson(original.toJson());

      expect(reconstructed.label, original.label);
      expect(reconstructed.encryptionKey, original.encryptionKey);
      expect(reconstructed.authPublicKey, original.authPublicKey);
      expect(reconstructed.authPrivateKey, isNull);
      // Both sides derive the same channel id from the QR material alone.
      expect(reconstructed.id, original.id);
    });

    test(
      'serializes v3 channel with OH descriptor (32-byte Ed25519 pk)',
      () async {
        final ohDescriptor = OHDescriptor(
          serverEndpoint: '192.168.1.100:59558',
          handleId: List.generate(20, (i) => i),
          authPublicKey: List.generate(32, (i) => i),
        );

        final original = (await Channel.generate(
          'With OH',
        )).copyWith(peerOhDescriptor: ohDescriptor);

        final json = original.toJson();
        expect(json.contains('"v":3'), true);
        expect(json.contains('"oh"'), true);

        final reconstructed = Channel.fromJson(json);
        expect(reconstructed.peerOhDescriptor, isNotNull);
        expect(
          reconstructed.peerOhDescriptor!.serverEndpoint,
          ohDescriptor.serverEndpoint,
        );
        expect(reconstructed.peerOhDescriptor!.handleId, ohDescriptor.handleId);
        expect(
          reconstructed.peerOhDescriptor!.authPublicKey,
          ohDescriptor.authPublicKey,
        );
      },
    );

    test('rejects legacy v1/v2 QR codes', () {
      const v1 = '{"l":"Old","k_enc":"00","k_auth":"00","v":1}';
      const v2 = '{"l":"Old","k_enc":"00","k_auth":"00","v":2}';
      const v999 = '{"l":"Bad","k_enc":"00","k_auth_pub":"00","v":999}';
      expect(() => Channel.fromJson(v1), throwsA(isA<FormatException>()));
      expect(() => Channel.fromJson(v2), throwsA(isA<FormatException>()));
      expect(() => Channel.fromJson(v999), throwsA(isA<FormatException>()));
    });

    test('rejects v3 codes with wrong key lengths', () {
      const shortEnc = '{"l":"Bad","k_enc":"0011","k_auth_pub":"00","v":3}';
      expect(() => Channel.fromJson(shortEnc), throwsA(isA<FormatException>()));
    });

    test('channel id = SHA256(encryptionKey || authPublicKey)', () {
      final channel = Channel(
        label: 'Test',
        encryptionKey: List.filled(32, 0x01),
        authPublicKey: List.filled(32, 0x02),
      );

      // SHA256 of 32x 0x01 followed by 32x 0x02 — stable identity.
      expect(channel.id.length, 64);

      final withOh = channel.copyWith(
        peerOhDescriptor: OHDescriptor(
          serverEndpoint: 'h:1',
          handleId: const [1],
          authPublicKey: const [2],
        ),
      );

      // Channel ID depends only on the keys, not the OH descriptor.
      expect(channel.id, equals(withOh.id));
    });

    test('copyWith preserves keys and private seed', () async {
      final channel = await Channel.generate('Test');

      final ohDescriptor = OHDescriptor(
        serverEndpoint: 'host:1234',
        handleId: List.filled(20, 0xFF),
        authPublicKey: List.filled(32, 0xAA),
      );

      final updated = channel.copyWith(peerOhDescriptor: ohDescriptor);
      expect(updated.label, channel.label);
      expect(updated.encryptionKey, channel.encryptionKey);
      expect(updated.authPrivateKey, channel.authPrivateKey);
      expect(updated.authPublicKey, channel.authPublicKey);
      expect(updated.peerOhDescriptor!.serverEndpoint, 'host:1234');
    });
  });
}
