import 'dart:convert';
import 'dart:io';

import 'package:hex/hex.dart';
import 'package:test/test.dart';

import 'package:redpanda_light_client/src/crypto/channel_message.dart';
import 'package:redpanda_light_client/src/crypto/group_control.dart';
import 'package:redpanda_light_client/src/domain/reverse_garlic_block.dart';
import 'package:redpanda_light_client/src/generated/client/channel_message.pb.dart'
    as cm_pb;
import 'package:redpanda_light_client/src/generated/client/group_control.pb.dart'
    as gc_pb;
import 'package:redpanda_light_client/src/generated/client/reverse_garlic_block.pb.dart'
    as rgb_pb;

/// TD098/T142: `test/fixtures/legacy_client_wire_corpus.json` holds bytes
/// produced by the hand-written client codecs right before they were replaced
/// by the generated `protos/client/` code. Deployed clients still emit
/// exactly these bytes, so the codec classes must decode every entry and
/// re-encode it byte for byte, and the generated messages must round-trip it
/// unchanged too.
void main() {
  late Map<String, dynamic> corpus;

  setUpAll(() {
    for (final candidate in const ['.', 'packages/redpanda_light_client']) {
      final file = File(
        '$candidate/test/fixtures/legacy_client_wire_corpus.json',
      );
      if (file.existsSync()) {
        corpus = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        return;
      }
    }
    fail('legacy_client_wire_corpus.json not found');
  });

  void checkAll(
    String key,
    List<int> Function(List<int>) codecRoundTrip,
    List<int> Function(List<int>) generatedRoundTrip,
  ) {
    final entries = (corpus[key] as List).cast<String>();
    expect(entries, isNotEmpty);
    for (final hex in entries) {
      final wire = HEX.decode(hex);
      expect(HEX.encode(codecRoundTrip(wire)), hex, reason: '$key codec');
      expect(HEX.encode(generatedRoundTrip(wire)), hex, reason: '$key pb');
    }
  }

  test('ChannelMessage', () {
    checkAll(
      'channel_message',
      (b) => ChannelMessage.decode(b).encode(),
      (b) => cm_pb.ChannelMessage.fromBuffer(b).writeToBuffer(),
    );
  });

  test('ReverseGarlicBlock', () {
    checkAll(
      'reverse_garlic_block',
      (b) => ReverseGarlicBlock.deserialize(b).serialize(),
      (b) => rgb_pb.ReverseGarlicBlock.fromBuffer(b).writeToBuffer(),
    );
  });

  test('GroupControl', () {
    checkAll(
      'group_control',
      (b) => GroupControl.decode(b).encode(),
      (b) => gc_pb.GroupControl.fromBuffer(b).writeToBuffer(),
    );
  });

  test('GroupHandshake', () {
    checkAll(
      'group_handshake',
      (b) => GroupHandshake.decode(b).encode(),
      (b) => gc_pb.GroupHandshake.fromBuffer(b).writeToBuffer(),
    );
  });

  group('malformed input throws FormatException, never an Error', () {
    // Negative length prefix (-1 as a 5-byte varint) after a given tag byte.
    List<int> negativeLength(int tag) => [tag, 0xff, 0xff, 0xff, 0xff, 0x0f];
    final common = <List<int>>[
      [0x0a], // tag without length
      [0x0a, 0x05, 0x01], // length beyond the end
      [0x08, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01],
      [0x0f], // wire type 7
    ];

    void expectAllRejected(
      String what,
      Object? Function(List<int>) decode,
      List<int> lengthDelimitedTags,
    ) {
      for (final input in [
        ...common,
        for (final tag in lengthDelimitedTags) negativeLength(tag),
      ]) {
        expect(
          () => decode(input),
          throwsA(isA<FormatException>()),
          reason: '$what ${HEX.encode(input)}',
        );
      }
    }

    test('ChannelMessage', () {
      expectAllRejected('ChannelMessage', ChannelMessage.decode, [
        0x0a,
        0x1a,
        0x2a,
        0x32,
        0x3a,
        0x42,
        0x4a,
      ]);
    });

    test('ReverseGarlicBlock', () {
      expectAllRejected('ReverseGarlicBlock', ReverseGarlicBlock.deserialize, [
        0x1a,
        0x22,
        0x2a,
      ]);
    });

    test('GroupControl / KeyRotation / GroupHandshake', () {
      expectAllRejected('GroupControl', GroupControl.decode, [0x0a, 0x12]);
      expectAllRejected('KeyRotation', KeyRotation.decode, [0x0a, 0x1a, 0x22]);
      expectAllRejected('GroupHandshake', GroupHandshake.decode, [0x0a, 0x12]);
    });
  });
}
