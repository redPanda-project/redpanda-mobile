import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pc;
import 'package:test/test.dart';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/domain/channel.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';

void main() {
  group('MS01 AK1: sendMessage() does not throw UnimplementedError', () {
    late RedPandaLightClient client;

    setUp(() {
      final keys = KeyPair.generate();
      client = RedPandaLightClient(
        selfNodeId: NodeId.fromPublicKey(keys),
        selfKeys: keys,
        seeds: [],
      );
    });

    tearDown(() async {
      await client.disconnect();
    });

    test('sendMessage returns a message ID without throwing', () async {
      final channel = Channel.generate('Test');
      final messageId = await client.sendMessage(channel.id, 'Hello World');

      expect(messageId, isNotEmpty);
      expect(messageId, isA<String>());
    });

    test(
      'sendMessage with registered channel keys returns message ID',
      () async {
        final channel = Channel.generate('Test');
        client.addChannelKeys(channel.id, channel.encryptionKey);

        final messageId = await client.sendMessage(channel.id, 'Hello');
        expect(messageId, isNotEmpty);
      },
    );

    test('sendMessage with different content returns unique IDs', () async {
      final channel = Channel.generate('Test');
      client.addChannelKeys(channel.id, channel.encryptionKey);

      final id1 = await client.sendMessage(channel.id, 'Message 1');
      final id2 = await client.sendMessage(channel.id, 'Message 2');

      expect(id1, isNot(equals(id2)));
    });
  });

  group('MS01 AK4: AES-256-CTR encrypt → decrypt roundtrip', () {
    test('encrypt and decrypt produces original plaintext', () {
      final channel = Channel.generate('Test');
      final encKey = Uint8List.fromList(channel.encryptionKey);
      final plaintext = 'Hello, Bob! This is a secret message.';
      final plaintextBytes = Uint8List.fromList(utf8.encode(plaintext));

      // Encrypt: same logic as sendMessage()
      final iv = Uint8List(16);
      for (var i = 0; i < 16; i++) {
        iv[i] = i; // Deterministic IV for testing
      }

      final cipher = pc.CTRStreamCipher(pc.AESEngine());
      cipher.init(true, pc.ParametersWithIV(pc.KeyParameter(encKey), iv));
      final ciphertext = cipher.process(plaintextBytes);

      // Build payload: [IV (16)][ciphertext]
      final payload = Uint8List(iv.length + ciphertext.length);
      payload.setRange(0, iv.length, iv);
      payload.setRange(iv.length, payload.length, ciphertext);

      // Decrypt: same logic as fetchMessages()
      final extractedIv = payload.sublist(0, 16);
      final extractedCiphertext = payload.sublist(16);

      final decipher = pc.CTRStreamCipher(pc.AESEngine());
      decipher.init(
        false,
        pc.ParametersWithIV(pc.KeyParameter(encKey), extractedIv),
      );
      final decrypted = decipher.process(
        Uint8List.fromList(extractedCiphertext),
      );

      expect(utf8.decode(decrypted), equals(plaintext));
    });

    test('different IVs produce different ciphertexts', () {
      final encKey = Uint8List.fromList(List.generate(32, (i) => i));
      final plaintext = Uint8List.fromList(utf8.encode('Same message'));

      final iv1 = Uint8List.fromList(List.generate(16, (i) => i));
      final iv2 = Uint8List.fromList(List.generate(16, (i) => i + 100));

      final cipher1 = pc.CTRStreamCipher(pc.AESEngine());
      cipher1.init(true, pc.ParametersWithIV(pc.KeyParameter(encKey), iv1));

      final cipher2 = pc.CTRStreamCipher(pc.AESEngine());
      cipher2.init(true, pc.ParametersWithIV(pc.KeyParameter(encKey), iv2));

      final ct1 = cipher1.process(plaintext);
      final ct2 = cipher2.process(plaintext);

      expect(ct1, isNot(equals(ct2)));
    });

    test('wrong key fails to decrypt correctly', () {
      final correctKey = Uint8List.fromList(List.generate(32, (i) => i));
      final wrongKey = Uint8List.fromList(List.generate(32, (i) => 255 - i));
      final plaintext = Uint8List.fromList(utf8.encode('Secret'));
      final iv = Uint8List.fromList(List.generate(16, (i) => i));

      // Encrypt with correct key
      final cipher = pc.CTRStreamCipher(pc.AESEngine());
      cipher.init(true, pc.ParametersWithIV(pc.KeyParameter(correctKey), iv));
      final ciphertext = cipher.process(plaintext);

      // Decrypt with wrong key
      final decipher = pc.CTRStreamCipher(pc.AESEngine());
      decipher.init(false, pc.ParametersWithIV(pc.KeyParameter(wrongKey), iv));
      final decrypted = decipher.process(ciphertext);

      // CTR mode won't error, but produces garbage
      expect(decrypted, isNot(equals(plaintext)));
    });

    test('encrypts unicode and emoji correctly', () {
      final encKey = Uint8List.fromList(List.generate(32, (i) => i));
      final content = 'Hallo Welt! 🎉 Ünïcödé';
      final plaintext = Uint8List.fromList(utf8.encode(content));
      final iv = Uint8List.fromList(List.generate(16, (i) => i));

      final cipher = pc.CTRStreamCipher(pc.AESEngine());
      cipher.init(true, pc.ParametersWithIV(pc.KeyParameter(encKey), iv));
      final ciphertext = cipher.process(plaintext);

      final decipher = pc.CTRStreamCipher(pc.AESEngine());
      decipher.init(false, pc.ParametersWithIV(pc.KeyParameter(encKey), iv));
      final decrypted = decipher.process(ciphertext);

      expect(utf8.decode(decrypted), equals(content));
    });

    test('empty message encrypts and decrypts', () {
      final encKey = Uint8List.fromList(List.generate(32, (i) => i));
      final plaintext = Uint8List(0);
      final iv = Uint8List.fromList(List.generate(16, (i) => i));

      final cipher = pc.CTRStreamCipher(pc.AESEngine());
      cipher.init(true, pc.ParametersWithIV(pc.KeyParameter(encKey), iv));
      final ciphertext = cipher.process(plaintext);
      expect(ciphertext.length, 0);

      final decipher = pc.CTRStreamCipher(pc.AESEngine());
      decipher.init(false, pc.ParametersWithIV(pc.KeyParameter(encKey), iv));
      final decrypted = decipher.process(ciphertext);

      expect(decrypted.length, 0);
    });
  });
}
