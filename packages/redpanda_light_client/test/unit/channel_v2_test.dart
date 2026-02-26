import 'package:test/test.dart';
import 'package:redpanda_light_client/src/domain/channel.dart';
import 'package:redpanda_light_client/src/domain/oh_descriptor.dart';

void main() {
  group('Channel v2', () {
    test('should generate a channel without OH descriptor (v1)', () {
      final channel = Channel.generate('Test Channel');

      expect(channel.label, 'Test Channel');
      expect(channel.encryptionKey.length, 32);
      expect(channel.authenticationKey.length, 32);
      expect(channel.peerOhDescriptor, isNull);
    });

    test('should serialize v1 channel (no OH) and deserialize', () {
      final original = Channel.generate('Secret Group');
      final json = original.toJson();
      final reconstructed = Channel.fromJson(json);

      expect(reconstructed.label, original.label);
      expect(reconstructed.encryptionKey, original.encryptionKey);
      expect(reconstructed.authenticationKey, original.authenticationKey);
      expect(reconstructed.peerOhDescriptor, isNull);
    });

    test('should serialize v2 channel (with OH) and deserialize', () {
      final ohDescriptor = OHDescriptor(
        serverEndpoint: '192.168.1.100:59558',
        handleId: List.generate(20, (i) => i),
        authPublicKey: List.generate(65, (i) => i),
      );

      final original = Channel(
        label: 'With OH',
        encryptionKey: List.generate(32, (i) => i + 100),
        authenticationKey: List.generate(32, (i) => i + 200),
        peerOhDescriptor: ohDescriptor,
      );

      final json = original.toJson();
      expect(json.contains('"v":2'), true);
      expect(json.contains('"oh"'), true);

      final reconstructed = Channel.fromJson(json);

      expect(reconstructed.label, original.label);
      expect(reconstructed.encryptionKey, original.encryptionKey);
      expect(reconstructed.authenticationKey, original.authenticationKey);
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
    });

    test('should throw on unsupported version', () {
      final json = '{"l":"Bad","k_enc":"00","k_auth":"00","v":999}';
      expect(() => Channel.fromJson(json), throwsA(isA<FormatException>()));
    });

    test('should support copyWith for adding OH descriptor', () {
      final channel = Channel.generate('Test');
      expect(channel.peerOhDescriptor, isNull);

      final ohDescriptor = OHDescriptor(
        serverEndpoint: 'host:1234',
        handleId: List.filled(20, 0xFF),
        authPublicKey: List.filled(65, 0xAA),
      );

      final updated = channel.copyWith(peerOhDescriptor: ohDescriptor);
      expect(updated.label, channel.label);
      expect(updated.encryptionKey, channel.encryptionKey);
      expect(updated.peerOhDescriptor, isNotNull);
      expect(updated.peerOhDescriptor!.serverEndpoint, 'host:1234');
    });

    test('channel ID should be stable with or without OH', () {
      final channel = Channel(
        label: 'Test',
        encryptionKey: List.filled(32, 0x01),
        authenticationKey: List.filled(32, 0x02),
      );

      final withOh = channel.copyWith(
        peerOhDescriptor: OHDescriptor(
          serverEndpoint: 'h:1',
          handleId: [1],
          authPublicKey: [2],
        ),
      );

      // Channel ID depends only on keys, not OH descriptor
      expect(channel.id, equals(withOh.id));
    });
  });
}
