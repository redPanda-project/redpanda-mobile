import 'package:test/test.dart';
import 'package:redpanda_light_client/src/domain/channel.dart';

void main() {
  group('Channel', () {
    test('should generate a valid channel with random keys', () async {
      final channel = await Channel.generate('Test Channel');

      expect(channel.label, 'Test Channel');
      expect(channel.encryptionKey.length, 32);
      expect(channel.authPublicKey.length, 32);
      expect(channel.authPrivateKey!.length, 32);
    });

    test('two generated channels have different keys and ids', () async {
      final a = await Channel.generate('A');
      final b = await Channel.generate('B');

      expect(a.encryptionKey, isNot(equals(b.encryptionKey)));
      expect(a.authPublicKey, isNot(equals(b.authPublicKey)));
      expect(a.id, isNot(equals(b.id)));
    });

    test('should throw FormatException on unsupported version', () {
      const json = '{"l":"Bad","k_enc":"00","k_auth_pub":"00","v":999}';
      expect(() => Channel.fromJson(json), throwsA(isA<FormatException>()));
    });
  });
}
