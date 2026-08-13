@Tags(['e2e'])
// Seconds, not minutes: one short-lived java process, no node topology. The
// generous budget only covers a cold JIT/compile on a loaded CI runner.
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:hex/hex.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:redpanda_light_client/src/crypto/channel_rendezvous.dart';
import 'redpanda_node_launcher.dart';

/// TD022 (c): cross-implementation check of the channel-rendezvous record
/// format between this client and the backend release JAR the e2e suites run
/// against.
///
/// The rendezvous record format is a two-sided contract with no version byte on
/// the wire: nodes reject every record whose content is not exactly
/// `ChannelDht.RECORD_SIZE_BYTES`, and both sides sign the identical byte
/// string. A one-sided change is therefore invisible until records silently
/// stop being stored. That happened for real: redpandaj widened the bucket
/// 512 → 1024 and shipped a release before the client followed, so mobile
/// `main` published 512-byte records into 1024-byte nodes. Nothing named the
/// cause — the only symptom was `t44_rendezvous_heal` burning its 15 min
/// recovery budget and being written off as a timing flake.
///
/// Both repos already pin the same hand-copied vector
/// (`ChannelDhtTest.buildRecordContent_matchesTheClientCrossCheckVector` /
/// `channel_rendezvous_test.dart`), which keeps each side from drifting away
/// from its own constant — but two hand-copied vectors cannot notice that they
/// disagree with each other. This suite closes that gap by asking the actual
/// artefact: it runs `ChannelDht` straight out of the downloaded
/// `redpanda.jar` and compares its answers against what [ChannelRendezvous]
/// computes for the same input.
///
/// Because the JAR comes from redpandaj's `latest` **release**, this gates the
/// deployment order the project works by (backend release first, mobile
/// after): a client change that lands before the matching backend release goes
/// red here, in seconds and by name, instead of 15 minutes later as a mystery
/// e2e timeout.
void main() {
  final jarAvailable = e2eJarAvailable();

  group('channel rendezvous record format vs. the backend release JAR', () {
    test(
      'the fixed record bucket size matches ChannelDht.RECORD_SIZE_BYTES',
      () async {
        final backend = await _backendFormat();

        expect(
          ChannelRendezvous.recordSizeBytes,
          backend.recordSizeBytes,
          reason: _skewReason(
            'record bucket size',
            expected:
                '${backend.recordSizeBytes} bytes '
                '(ChannelDht.RECORD_SIZE_BYTES in ${backend.jarPath})',
            actual:
                '${ChannelRendezvous.recordSizeBytes} bytes '
                '(ChannelRendezvous.recordSizeBytes)',
            consequence:
                'Nodes drop every record of a different size (WRONG_SIZE), so no '
                'rendezvous record of this client is ever stored and channel '
                'healing over the DHT silently stops working.',
          ),
        );
      },
      skip: !jarAvailable,
    );

    test('the record TTL matches ChannelDht.MAX_RECORD_AGE_MS', () async {
      final backend = await _backendFormat();

      expect(
        ChannelRendezvous.maxRecordAgeMs,
        backend.maxRecordAgeMs,
        reason: _skewReason(
          'record TTL',
          expected:
              '${backend.maxRecordAgeMs} ms '
              '(ChannelDht.MAX_RECORD_AGE_MS in ${backend.jarPath})',
          actual:
              '${ChannelRendezvous.maxRecordAgeMs} ms '
              '(ChannelRendezvous.maxRecordAgeMs)',
          consequence:
              'A client TTL longer than the node TTL makes the client trust '
              'records the DHT has already dropped; a shorter one discards '
              'records that are still being served.',
        ),
      );
    }, skip: !jarAvailable);

    test(
      'derived key, rotating kademlia id and record signature are byte-identical',
      () async {
        final backend = await _backendFormat();

        // Guarded explicitly: with mismatched bucket sizes every value below
        // differs too, and three signature diffs are a much worse error message
        // than the one line that names the real cause.
        expect(
          ChannelRendezvous.recordSizeBytes,
          backend.recordSizeBytes,
          reason:
              'record bucket size already differs — see the bucket-size test '
              'for the actual cause; the vectors below cannot match.',
        );

        final pubkey = await ChannelRendezvous.recordPublicExport(_secret);
        expect(
          HEX.encode(pubkey),
          backend.recordPubkeyHex,
          reason: _skewReason(
            'derived record public key',
            expected:
                '${backend.recordPubkeyHex} '
                '(ChannelDht.deriveRecordNodeId in ${backend.jarPath})',
            actual:
                '${HEX.encode(pubkey)} '
                '(ChannelRendezvous.recordPublicExport)',
            consequence:
                'The record key is the identity the DHT stores under and '
                'verifies against — a different one means participants never '
                'find each other.',
          ),
        );

        final kademliaId = await ChannelRendezvous.rendezvousKademliaId(
          _secret,
          _timestampMs,
        );
        expect(
          HEX.encode(kademliaId),
          backend.kademliaIdHex,
          reason: _skewReason(
            'rendezvous kademlia id',
            expected:
                '${backend.kademliaIdHex} '
                '(ChannelDht.rendezvousKademliaId in ${backend.jarPath})',
            actual:
                '${HEX.encode(kademliaId)} '
                '(ChannelRendezvous.rendezvousKademliaId)',
            consequence:
                'Publisher and reader would use different DHT keys, so a '
                'lookup never returns the record that was stored.',
          ),
        );

        final content = Uint8List(ChannelRendezvous.recordSizeBytes)
          ..fillRange(0, ChannelRendezvous.recordSizeBytes, _contentFillByte);
        final signed = await ChannelRendezvous.signContent(
          _secret,
          content,
          _timestampMs,
        );
        expect(
          HEX.encode(signed.signature),
          backend.signatureHex,
          reason: _skewReason(
            'record signature',
            expected:
                '${backend.signatureHex} '
                '(ChannelDht.buildRecordContent in ${backend.jarPath})',
            actual:
                '${HEX.encode(signed.signature)} '
                '(ChannelRendezvous.signContent)',
            consequence:
                'Both sides sign SHA256(int64_be(ts) || content) with the '
                'derived key. A different signature means the node rejects the '
                'record as BAD_SIGNATURE — or this client rejects the node\'s.',
          ),
        );
      },
      skip: !jarAvailable,
    );
  });
}

// --- The cross-check vector input (identical in ChannelDhtTest) ---

/// channelSecret = 0x00..0x1f. Same bytes as the pinned vector in the backend
/// unit test and in `channel_rendezvous_test.dart`, so all three checks stay
/// comparable by eye.
final Uint8List _secret = Uint8List.fromList(List<int>.generate(32, (i) => i));
const int _timestampMs = 1000000000000;
const int _contentFillByte = 0xAB;

/// Assembles a failure message that names the skew, both sides, the effect and
/// the deployment rule — the whole point of TD022 (c) is that this failure
/// explains itself without anyone having to reconstruct it from an e2e
/// timeout.
String _skewReason(
  String what, {
  required String expected,
  required String actual,
  required String consequence,
}) {
  return 'Rendezvous record FORMAT SKEW — $what disagrees with the backend.\n'
      '  backend (release JAR): $expected\n'
      '  this client:           $actual\n'
      '$consequence\n'
      'Deployment order: the backend release ships FIRST, the client follows. '
      'If you are changing the format on purpose, merge and release redpandaj '
      'first, then update the client constants/vectors here (and the pinned '
      'vector in ChannelDhtTest) in a follow-up PR. If you changed nothing '
      'here, the downloaded redpanda.jar moved under you — rebase onto a '
      'client that matches the current release.';
}

// --- Reading the format out of the release JAR ---

/// The record-format values as the reference JAR itself computes them.
class _BackendFormat {
  final int recordSizeBytes;
  final int maxRecordAgeMs;
  final String recordPubkeyHex;
  final String kademliaIdHex;
  final String signatureHex;
  final String jarPath;

  _BackendFormat({
    required this.recordSizeBytes,
    required this.maxRecordAgeMs,
    required this.recordPubkeyHex,
    required this.kademliaIdHex,
    required this.signatureHex,
    required this.jarPath,
  });
}

Future<_BackendFormat>? _cached;

/// Runs the probe at most once per suite — three tests, one JVM start.
Future<_BackendFormat> _backendFormat() => _cached ??= _runProbe();

/// Executes [_probeSource] against the release JAR and parses its `KEY=value`
/// output.
///
/// Mechanism: `java -cp <jar> ChannelDhtVector.java`, the single-file source
/// launcher (JEP 330, Java 11+). It compiles in memory, so it needs nothing on
/// PATH that the other e2e suites do not already need — they all start nodes
/// with `Process.start('java', ...)`, and CI installs a full Temurin 21 JDK via
/// `actions/setup-java` before any test runs. Reading the constants out of the
/// class file (javap or a hand-rolled parser) would cover the bucket size but
/// not the derivation and signing chain, which is where the rest of the format
/// actually lives.
Future<_BackendFormat> _runProbe() async {
  final jar = RedPandaNodeLauncher.locateJar();
  if (jar == null) {
    // Unreachable via the e2eJarAvailable() guard; kept so a future direct
    // caller gets a diagnosis instead of a null dereference.
    throw StateError(
      'No backend JAR to cross-check against — expected '
      '<repo>/references/redPandaj/target/redpanda.jar.',
    );
  }

  final workDir = await Directory.systemTemp.createTemp('rp_channel_dht_vec');
  try {
    final source = File(p.join(workDir.path, 'ChannelDhtVector.java'));
    await source.writeAsString(_probeSource);

    final result = await Process.run('java', [
      '-cp',
      jar,
      source.path,
    ], workingDirectory: workDir.path);

    final stdoutText = result.stdout.toString();
    if (result.exitCode != 0) {
      throw StateError(
        'Could not read the rendezvous record format out of the backend JAR.\n'
        'Command: java -cp $jar ${source.path}\n'
        'Exit code: ${result.exitCode}\n'
        'stdout:\n$stdoutText\n'
        'stderr:\n${result.stderr}\n'
        'This is NOT a format skew: either the JDK is missing/too old for the '
        'single-file source launcher (Java 11+ required; the e2e node launcher '
        'needs a JVM anyway), or the JAR no longer exposes '
        'im.redpanda.outbound.ChannelDht with the API this probe uses. In the '
        'latter case the backend changed the rendezvous API and this suite has '
        'to follow.',
      );
    }

    final values = <String, String>{};
    for (final line in const LineSplitter().convert(stdoutText)) {
      final marker = line.indexOf(_probeMarker);
      if (marker < 0) continue;
      final body = line.substring(marker + _probeMarker.length);
      final sep = body.indexOf('=');
      if (sep <= 0) continue;
      values[body.substring(0, sep)] = body.substring(sep + 1).trim();
    }

    String read(String key) {
      final value = values[key];
      if (value == null || value.isEmpty) {
        throw StateError(
          'The backend probe did not report "$key". Full output:\n$stdoutText\n'
          'stderr:\n${result.stderr}',
        );
      }
      return value;
    }

    return _BackendFormat(
      recordSizeBytes: int.parse(read('RECORD_SIZE_BYTES')),
      maxRecordAgeMs: int.parse(read('MAX_RECORD_AGE_MS')),
      recordPubkeyHex: read('RECORD_PUBKEY').toLowerCase(),
      kademliaIdHex: read('KADEMLIA_ID').toLowerCase(),
      signatureHex: read('SIGNATURE').toLowerCase(),
      jarPath: jar,
    );
  } finally {
    await workDir.delete(recursive: true);
  }
}

/// Prefixed so the values survive a JAR that logs to stdout on class init.
/// Duplicated as a literal in [_probeSource] — that source is a raw string on
/// purpose (it must stay valid Java that can be pasted into a scratch file), so
/// the two are kept in sync by hand.
const String _probeMarker = 'RPVEC:';

/// The probe, kept in one place with the Dart side that consumes it. It is
/// written to a temp file and thrown away again — nothing is compiled into the
/// repository, and the values it prints are produced by the release JAR, not by
/// this file.
const String _probeSource = r'''
import im.redpanda.crypt.Utils;
import im.redpanda.kademlia.KadContent;
import im.redpanda.outbound.ChannelDht;
import java.util.Arrays;

/**
 * Prints the channel-rendezvous record format of the surrounding redpanda.jar.
 *
 * Generated at test time by channel_record_format_crosscheck_test.dart in
 * redpanda-mobile (TD022). Not part of redpandaj — do not commit it there.
 */
public class ChannelDhtVector {

  public static void main(String[] args) {
    byte[] secret = new byte[32];
    for (int i = 0; i < secret.length; i++) {
      secret[i] = (byte) i;
    }
    long timestampMs = 1000000000000L;

    byte[] content = new byte[ChannelDht.RECORD_SIZE_BYTES];
    Arrays.fill(content, (byte) 0xAB);
    KadContent record = ChannelDht.buildRecordContent(secret, content, timestampMs);

    emit("RECORD_SIZE_BYTES", Integer.toString(ChannelDht.RECORD_SIZE_BYTES));
    emit("MAX_RECORD_AGE_MS", Long.toString(ChannelDht.MAX_RECORD_AGE_MS));
    emit("RECORD_PUBKEY", Utils.bytesToHexString(record.getPubkey()));
    emit(
        "KADEMLIA_ID",
        Utils.bytesToHexString(ChannelDht.rendezvousKademliaId(secret, timestampMs).getBytes()));
    emit("SIGNATURE", Utils.bytesToHexString(record.getSignature()));
  }

  private static void emit(String key, String value) {
    System.out.println("RPVEC:" + key + "=" + value);
  }
}
''';
