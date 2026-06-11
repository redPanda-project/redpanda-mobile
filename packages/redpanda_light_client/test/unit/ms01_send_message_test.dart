import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pc;
import 'package:test/test.dart';

import 'package:redpanda_light_client/src/client/redpanda_light_client.dart';
import 'package:redpanda_light_client/src/domain/channel.dart';
import 'package:redpanda_light_client/src/models/key_pair.dart';
import 'package:redpanda_light_client/src/models/node_id.dart';

void main() {
  group('MS01 AK1 / MS02: sendMessage() reports delivery failures', () {
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

    test('sendMessage without channel keys throws StateError', () async {
      final channel = Channel.generate('Test');

      // MS02: failures must surface so the retry queue can re-send later.
      expect(
        () => client.sendMessage(channel.id, 'Hello World'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('no encryption keys'),
          ),
        ),
      );
    });

    test(
      'sendMessage with keys but no connected peer throws StateError',
      () async {
        final channel = Channel.generate('Test');
        client.addChannelKeys(channel.id, channel.encryptionKey);

        expect(
          () => client.sendMessage(channel.id, 'Hello'),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('no active peer'),
            ),
          ),
        );
      },
    );
  });

  group('MS01 AK4: AES-256-CTR + HMAC-SHA256 encrypt → decrypt roundtrip', () {
    test('encrypt and decrypt produces original plaintext', () {
      final channel = Channel.generate('Test');
      final encKey = Uint8List.fromList(channel.encryptionKey);
      final plaintext = 'Hello, Bob! This is a secret message.';
      final plaintextBytes = Uint8List.fromList(utf8.encode(plaintext));

      // Encrypt: same logic as sendMessage()
      // NOTE: Deterministic IV used here for test reproducibility only.
      // Production code in sendMessage() uses Random.secure() for IVs.
      final iv = Uint8List(16);
      for (var i = 0; i < 16; i++) {
        iv[i] = i;
      }

      final cipher = pc.CTRStreamCipher(pc.AESEngine());
      cipher.init(true, pc.ParametersWithIV(pc.KeyParameter(encKey), iv));
      final ciphertext = cipher.process(plaintextBytes);

      // Compute HMAC-SHA256
      final macInput = Uint8List(iv.length + ciphertext.length);
      macInput.setRange(0, iv.length, iv);
      macInput.setRange(iv.length, macInput.length, ciphertext);
      final hmac = pc.HMac(pc.SHA256Digest(), 64)
        ..init(pc.KeyParameter(encKey));
      final mac = hmac.process(macInput);

      // Build payload: [IV (16)][ciphertext][HMAC (32)]
      final payload = Uint8List(iv.length + ciphertext.length + mac.length);
      payload.setRange(0, iv.length, iv);
      payload.setRange(iv.length, iv.length + ciphertext.length, ciphertext);
      payload.setRange(iv.length + ciphertext.length, payload.length, mac);

      // Verify: payload is [IV (16)][ciphertext][HMAC (32)]
      expect(payload.length, equals(16 + plaintextBytes.length + 32));

      // Decrypt: extract IV, ciphertext, and HMAC
      final extractedIv = payload.sublist(0, 16);
      final extractedCiphertext = payload.sublist(16, payload.length - 32);
      final extractedMac = payload.sublist(payload.length - 32);

      // Verify HMAC before decrypting
      final verifyInput = Uint8List(
        extractedIv.length + extractedCiphertext.length,
      );
      verifyInput.setRange(0, extractedIv.length, extractedIv);
      verifyInput.setRange(
        extractedIv.length,
        verifyInput.length,
        extractedCiphertext,
      );
      final verifyHmac = pc.HMac(pc.SHA256Digest(), 64)
        ..init(pc.KeyParameter(encKey));
      final expectedMac = verifyHmac.process(verifyInput);
      expect(extractedMac, equals(expectedMac));

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

    test('tampered ciphertext is detected by HMAC verification', () {
      final encKey = Uint8List.fromList(List.generate(32, (i) => i));
      final plaintext = Uint8List.fromList(utf8.encode('Secret message'));
      final iv = Uint8List.fromList(List.generate(16, (i) => i));

      // Encrypt
      final cipher = pc.CTRStreamCipher(pc.AESEngine());
      cipher.init(true, pc.ParametersWithIV(pc.KeyParameter(encKey), iv));
      final ciphertext = cipher.process(plaintext);

      // Compute HMAC
      final macInput = Uint8List(iv.length + ciphertext.length);
      macInput.setRange(0, iv.length, iv);
      macInput.setRange(iv.length, macInput.length, ciphertext);
      final hmac = pc.HMac(pc.SHA256Digest(), 64)
        ..init(pc.KeyParameter(encKey));
      final mac = hmac.process(macInput);

      // Build payload
      final payload = Uint8List(iv.length + ciphertext.length + mac.length);
      payload.setRange(0, iv.length, iv);
      payload.setRange(iv.length, iv.length + ciphertext.length, ciphertext);
      payload.setRange(iv.length + ciphertext.length, payload.length, mac);

      // Tamper with ciphertext (flip a bit)
      payload[17] ^= 0xFF;

      // Verify: HMAC should not match
      final extractedIv = payload.sublist(0, 16);
      final extractedCiphertext = payload.sublist(16, payload.length - 32);
      final extractedMac = payload.sublist(payload.length - 32);

      final verifyInput = Uint8List(
        extractedIv.length + extractedCiphertext.length,
      );
      verifyInput.setRange(0, extractedIv.length, extractedIv);
      verifyInput.setRange(
        extractedIv.length,
        verifyInput.length,
        extractedCiphertext,
      );
      final verifyHmac = pc.HMac(pc.SHA256Digest(), 64)
        ..init(pc.KeyParameter(encKey));
      final expectedMac = verifyHmac.process(verifyInput);

      expect(extractedMac, isNot(equals(expectedMac)));
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
