import 'dart:typed_data';

import 'package:hex/hex.dart';
import 'package:redpanda_light_client/src/crypto/channel_rendezvous.dart';
import 'package:redpanda_light_client/src/crypto/crypto_utils.dart';
import 'package:redpanda_light_client/src/domain/oh_descriptor.dart';
import 'package:test/test.dart';

/// Cross-check vectors generated from the reference `redpanda.jar`
/// (`im.redpanda.outbound.ChannelDht`, T43 release cdc726ab…) for
/// channelSecret = bytes 0x00..0x1f. See the task's vector generator.
const _skHex =
    '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f';
const _recordPubkeyHex =
    '472bf471805191c1d91160177c130f768eff71accd9430df7ac8c78338eafe83'
    'dd972f08beef48a682d05acf3b080bc357a0e5a19672bdee2d8f037b2e7be246';
const _ts = 1000000000000;
const _kademliaIdHex = 'dd83fa6b288e25f3aa52545015316b6fe379ab01';
// buildRecordContent(sk, [0xAB * 1024], ts) → deterministic Ed25519 signature.
// Regenerated for the 1024-byte bucket; the backend pins the same vector in
// ChannelDhtTest.buildRecordContent_matchesTheClientCrossCheckVector.
const _contentSignatureHex =
    'e649ea68beaedc8e66a11765ec5d4b3fbac2bf58e54815105741fd6007276893'
    '4838668388001641eac6c21223ec4e195fc590b1c91571ae9c0699932b411600';
const _ts2 = 1752960000000;
const _kademliaIdTs2Hex = '3b581f272eb90fc51fce892b881512ae104cce4a';

Uint8List _sk() => Uint8List.fromList(HEX.decode(_skHex));

OHDescriptor _oh(String ep) => OHDescriptor(
  serverEndpoint: ep,
  handleId: CryptoUtils.randomBytes(20),
  authPublicKey: CryptoUtils.randomBytes(32),
);

RendezvousEntry _entry({
  required List<int> id,
  required String name,
  required int ts,
  required List<OHDescriptor> ohs,
}) => RendezvousEntry(participantId: id, name: name, entryTs: ts, ohs: ohs);

void main() {
  group('derivations match the backend (byte-for-byte)', () {
    test(
      'recordPublicExport equals NodeId.fromSeed(...).exportPublic()',
      () async {
        final pub = await ChannelRendezvous.recordPublicExport(_sk());
        expect(HEX.encode(pub), _recordPubkeyHex);
      },
    );

    test('rendezvousKademliaId matches for two timestamps/days', () async {
      final id = await ChannelRendezvous.rendezvousKademliaId(_sk(), _ts);
      expect(HEX.encode(id), _kademliaIdHex);
      final id2 = await ChannelRendezvous.rendezvousKademliaId(_sk(), _ts2);
      expect(HEX.encode(id2), _kademliaIdTs2Hex);
    });

    test(
      'signContent reproduces the backend Ed25519 record signature',
      () async {
        final content = Uint8List(ChannelRendezvous.recordSizeBytes)
          ..fillRange(0, ChannelRendezvous.recordSizeBytes, 0xAB);
        final signed = await ChannelRendezvous.signContent(_sk(), content, _ts);
        expect(HEX.encode(signed.signature), _contentSignatureHex);
        expect(HEX.encode(signed.publicKey), _recordPubkeyHex);
        expect(await ChannelRendezvous.verifyRecord(signed), isTrue);
      },
    );

    test('derivations are deterministic and channel-specific', () async {
      final a = await ChannelRendezvous.recordPublicExport(_sk());
      final b = await ChannelRendezvous.recordPublicExport(_sk());
      expect(a, b);
      final other = await ChannelRendezvous.recordPublicExport(
        CryptoUtils.randomBytes(32),
      );
      expect(a, isNot(equals(other)));
    });
  });

  group('utcDayString matches SimpleDateFormat("dd.MM.yy") UTC', () {
    test('known timestamps', () {
      expect(ChannelRendezvous.utcDayString(_ts), '09.09.01');
      expect(ChannelRendezvous.utcDayString(0), '01.01.70');
    });
  });

  group('plaintext codec', () {
    test('round-trips entries and ignores padding', () {
      final entries = [
        _entry(
          id: CryptoUtils.randomBytes(32),
          name: 'Alice',
          ts: 1234,
          ohs: [_oh('1.2.3.4:59558'), _oh('5.6.7.8:59558')],
        ),
        _entry(
          id: CryptoUtils.randomBytes(32),
          name: 'Bob 🐼',
          ts: 5678,
          ohs: [_oh('9.9.9.9:59558')],
        ),
      ];
      final encoded = ChannelRendezvous.encodeEntries(entries);
      expect(encoded.length, ChannelRendezvous.plaintextLength);
      final decoded = ChannelRendezvous.decodeEntries(encoded);
      expect(decoded.length, 2);
      expect(decoded[0].name, 'Alice');
      expect(decoded[0].entryTs, 1234);
      expect(decoded[0].ohs.length, 2);
      expect(decoded[0].ohs[0].serverEndpoint, '1.2.3.4:59558');
      expect(decoded[1].name, 'Bob 🐼');
      expect(decoded[1].ohs.single.serverEndpoint, '9.9.9.9:59558');
    });

    test('two participants with k=3 OHs fit the 1024-byte bucket', () {
      final entries = [
        for (var p = 0; p < 2; p++)
          _entry(
            id: CryptoUtils.randomBytes(32),
            name: 'Participant $p',
            ts: 1000 + p,
            ohs: [
              _oh('123.123.123.123:59558'),
              _oh('200.200.200.200:59558'),
              _oh('42.42.42.42:59558'),
            ],
          ),
      ];
      final encoded = ChannelRendezvous.encodeEntries(entries);
      expect(encoded.length, ChannelRendezvous.plaintextLength);
    });

    test('k=3 with IPv6 endpoints still fits for two participants', () {
      // The bucket must hold the worst realistic 1:1 case, not just IPv4:
      // an IPv6 endpoint costs ~96 bytes per descriptor instead of ~74.
      final entries = [
        for (var p = 0; p < 2; p++)
          _entry(
            id: CryptoUtils.randomBytes(32),
            name: 'Participant $p',
            ts: 1000 + p,
            ohs: [
              for (var i = 0; i < 3; i++)
                _oh('[2001:db8:85a3:8d3:1319:8a2e:370:$i]:59558'),
            ],
          ),
      ];
      final encoded = ChannelRendezvous.encodeEntries(entries);
      expect(encoded.length, ChannelRendezvous.plaintextLength);
    });

    test('three participants with k=3 OHs still fit on IPv4', () {
      // k=3 is the last redundancy that leaves room for a third participant —
      // the guard behind RedPandaLightClient.ohRedundancy. A k=4 set of three
      // participants overflows (1055 > 996 bytes), and the overflow would only
      // ever surface as a swallowed publish error.
      final entries = [
        for (var p = 0; p < 3; p++)
          _entry(
            id: CryptoUtils.randomBytes(32),
            name: 'Participant $p',
            ts: 1000 + p,
            ohs: [for (var i = 0; i < 3; i++) _oh('123.123.123.12$i:59558')],
          ),
      ];
      final encoded = ChannelRendezvous.encodeEntries(entries);
      expect(encoded.length, ChannelRendezvous.plaintextLength);

      final withFourth = [
        for (final e in entries)
          _entry(
            id: e.participantId,
            name: e.name,
            ts: e.entryTs,
            ohs: [...e.ohs, _oh('123.123.123.99:59558')],
          ),
      ];
      expect(
        () => ChannelRendezvous.encodeEntries(withFourth),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('oversized payload throws', () {
      final entries = [
        for (var p = 0; p < 6; p++)
          _entry(
            id: CryptoUtils.randomBytes(32),
            name: 'Participant number $p with a long name',
            ts: 1000,
            ohs: [for (var i = 0; i < 3; i++) _oh('some.host.example:59558')],
          ),
      ];
      expect(
        () => ChannelRendezvous.encodeEntries(entries),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('record encrypt/decrypt', () {
    test('round-trips through the fixed 1024-byte bucket', () async {
      final sk = CryptoUtils.randomBytes(32);
      final entries = [
        _entry(
          id: CryptoUtils.randomBytes(32),
          name: 'Alice',
          ts: 42,
          ohs: [_oh('1.1.1.1:59558')],
        ),
      ];
      final content = await ChannelRendezvous.encryptRecordContent(sk, entries);
      expect(content.length, ChannelRendezvous.recordSizeBytes);
      final decoded = await ChannelRendezvous.decryptRecordContent(sk, content);
      expect(decoded.single.name, 'Alice');
      expect(decoded.single.ohs.single.serverEndpoint, '1.1.1.1:59558');
    });

    test(
      'every encryption is a fresh nonce (constant size, no leak)',
      () async {
        final sk = CryptoUtils.randomBytes(32);
        final entries = [
          _entry(
            id: CryptoUtils.randomBytes(32),
            name: 'A',
            ts: 1,
            ohs: [_oh('1.1.1.1:59558')],
          ),
        ];
        final c1 = await ChannelRendezvous.encryptRecordContent(sk, entries);
        final c2 = await ChannelRendezvous.encryptRecordContent(sk, entries);
        expect(c1.length, c2.length);
        expect(c1, isNot(equals(c2))); // random nonce
      },
    );

    test('wrong channel secret cannot decrypt', () async {
      final sk = CryptoUtils.randomBytes(32);
      final content = await ChannelRendezvous.encryptRecordContent(sk, [
        _entry(
          id: CryptoUtils.randomBytes(32),
          name: 'A',
          ts: 1,
          ohs: [_oh('1.1.1.1:59558')],
        ),
      ]);
      expect(
        () => ChannelRendezvous.decryptRecordContent(
          CryptoUtils.randomBytes(32),
          content,
        ),
        throwsA(isA<GcmAuthenticationException>()),
      );
    });
  });

  group('newest-wins per-participant merge', () {
    test('keeps the newest entryTs per participant', () {
      final idA = CryptoUtils.randomBytes(32);
      final idB = CryptoUtils.randomBytes(32);
      final existing = [
        _entry(id: idA, name: 'A-old', ts: 100, ohs: [_oh('1.1.1.1:1')]),
        _entry(id: idB, name: 'B-old', ts: 100, ohs: [_oh('2.2.2.2:2')]),
      ];
      final incoming = [
        _entry(id: idA, name: 'A-new', ts: 200, ohs: [_oh('3.3.3.3:3')]),
        _entry(id: idB, name: 'B-stale', ts: 50, ohs: [_oh('4.4.4.4:4')]),
      ];
      final merged = ChannelRendezvous.mergeEntries(existing, incoming);
      expect(merged.length, 2);
      final byId = {for (final e in merged) HEX.encode(e.participantId): e};
      expect(byId[HEX.encode(idA)]!.name, 'A-new');
      expect(byId[HEX.encode(idA)]!.ohs.single.serverEndpoint, '3.3.3.3:3');
      expect(byId[HEX.encode(idB)]!.name, 'B-old'); // stale incoming ignored
    });
  });
}
