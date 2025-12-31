import 'package:test/test.dart';
import 'package:redpanda_light_client/src/domain/channel.dart';

void main() {
  group('Channel', () {
    test('should generate a valid channel with random keys', () {
      final channel = Channel.generate('Test Channel');
      
      expect(channel.label, 'Test Channel');
      expect(channel.encryptionKey.length, 32);
      expect(channel.authenticationKey.length, 32);
    });

    test('should serialize and deserialize correctly (JSON)', () {
      final original = Channel.generate('Secret Group');
      final json = original.toJson();
      
      print('Serialized Channel: $json');
      
      final reconstructed = Channel.fromJson(json);
      
      expect(reconstructed, equals(original));
      expect(reconstructed.label, original.label);
      expect(reconstructed.encryptionKey, original.encryptionKey);
      expect(reconstructed.authenticationKey, original.authenticationKey);
    });

    test('should throw FormatException on unsupported version', () {
      final json = '{"l":"Bad","k_enc":"00","k_auth":"00","v":999}';
      expect(() => Channel.fromJson(json), throwsA(isA<FormatException>()));
    });
  });
}
