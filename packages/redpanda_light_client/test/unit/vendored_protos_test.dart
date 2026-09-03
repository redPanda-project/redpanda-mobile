import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

/// T107 / DDD review 2026-08-31 §6 P0: `redpandaj/src/main/proto/*.proto` is the
/// single source of truth for the wire schemas. The copies under
/// `packages/redpanda_light_client/protos/` are vendored artefacts produced by
/// `tool/sync_protos.sh`, and `lib/src/generated/` is produced from them by
/// `tool/generate_protos.sh`.
///
/// This test is the offline half of the drift guard: it proves the vendored
/// `.proto` files still hash to what `protos/UPSTREAM.lock` records, i.e. that
/// nobody hand-edited them after the sync. (Exactly that hand-editing is what
/// let the old `commands.proto` fall three milestones behind the generated
/// code.) Comparing against live upstream needs a redpandaj checkout or the
/// network and lives in `tool/sync_protos.sh --check`, which
/// `tool/pre_push_validation.sh` runs.
void main() {
  group('vendored protos', () {
    late Directory protoDir;

    setUpAll(() {
      for (final candidate in const [
        'protos',
        'packages/redpanda_light_client/protos',
      ]) {
        final dir = Directory(candidate);
        if (dir.existsSync()) {
          protoDir = dir;
          return;
        }
      }
      fail(
        'cannot locate the vendored protos directory from ${Directory.current.path}',
      );
    });

    test('UPSTREAM.lock pins a redpandaj commit', () {
      final lock = File('${protoDir.path}/UPSTREAM.lock');
      expect(lock.existsSync(), isTrue, reason: 'run tool/sync_protos.sh');
      final pin = lock
          .readAsLinesSync()
          .firstWhere(
            (l) => l.startsWith('# upstream-commit:'),
            orElse: () => '',
          )
          .replaceFirst('# upstream-commit:', '')
          .trim();
      expect(
        pin,
        matches(RegExp(r'^[0-9a-f]{40}$')),
        reason: 'UPSTREAM.lock must pin a full redpandaj commit SHA',
      );
    });

    test('vendored .proto files match the checked-in hashes', () {
      final lock = File('${protoDir.path}/UPSTREAM.lock');
      final expected = <String, String>{};
      for (final line in lock.readAsLinesSync()) {
        if (line.startsWith('#') || line.trim().isEmpty) continue;
        final parts = line.split('  ');
        expect(parts.length, 2, reason: 'malformed UPSTREAM.lock entry: $line');
        expected[parts[1]] = parts[0];
      }
      expect(expected, isNotEmpty, reason: 'UPSTREAM.lock lists no protos');

      final onDisk = protoDir
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n.endsWith('.proto'))
          .toSet();
      expect(
        onDisk,
        equals(expected.keys.toSet()),
        reason:
            'every vendored .proto must be listed in UPSTREAM.lock and vice '
            'versa — re-run tool/sync_protos.sh',
      );

      for (final entry in expected.entries) {
        final actual = sha256
            .convert(File('${protoDir.path}/${entry.key}').readAsBytesSync())
            .toString();
        expect(
          actual,
          entry.value,
          reason:
              '${entry.key} was edited after the sync. The schemas are owned by '
              'redPanda-project/redpandaj — change them there, then run '
              'tool/sync_protos.sh && tool/generate_protos.sh.',
        );
      }
    });

    test('generated Dart exists for every vendored .proto', () {
      final generated = Directory('${protoDir.path}/../lib/src/generated');
      expect(generated.existsSync(), isTrue);
      final names = generated
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .toSet();
      for (final proto
          in protoDir
              .listSync()
              .whereType<File>()
              .map((f) => f.uri.pathSegments.last)
              .where((n) => n.endsWith('.proto'))) {
        final base = proto.substring(0, proto.length - '.proto'.length);
        expect(
          names,
          containsAll(<String>['$base.pb.dart', '$base.pbjson.dart']),
          reason: 'run tool/generate_protos.sh',
        );
      }
    });
  });
}
