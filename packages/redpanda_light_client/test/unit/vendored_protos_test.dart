import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

/// T107 / DDD review 2026-08-31 §6 P0: `redpandaj/src/main/proto/*.proto` is the
/// single source of truth for the wire schemas. The copies under
/// `packages/redpanda_light_client/protos/` are vendored artefacts produced by
/// `tool/sync_protos.sh`, and `lib/src/generated/` is produced from them by
/// `tool/generate_protos.sh`.
///
/// This test is the offline half of the drift guard — the half that actually
/// runs in CI, which has neither protoc nor a redpandaj checkout. It proves
/// that nobody hand-edited either side after the last sync/codegen:
///
///  * the vendored `.proto` files still hash to `protos/UPSTREAM.lock`, and
///  * the generated Dart still hashes to `lib/src/generated/CODEGEN.lock`.
///
/// Hand-editing the *generated* code is not a hypothetical: it is exactly how
/// the pre-T107 `commands.pb.dart` ended up three milestones ahead of the
/// `commands.proto` it claimed to come from, invisibly.
///
/// Comparing against live upstream needs a redpandaj checkout or the network
/// and lives in `tool/sync_protos.sh --check`, which
/// `tool/pre_push_validation.sh` runs as step 0b.
///
/// TD098/T142: `protos/client/*.proto` are client-to-client schemas OWNED by
/// this repo (redpandaj does not model them). They are not vendored, so they
/// are not in `UPSTREAM.lock`; their generated Dart lives in
/// `lib/src/generated/client/` and is covered by `CODEGEN.lock` like the rest.
void main() {
  late Directory protoDir;
  late Directory generatedDir;

  setUpAll(() {
    for (final candidate in const ['.', 'packages/redpanda_light_client']) {
      final dir = Directory('$candidate/protos');
      if (dir.existsSync()) {
        protoDir = dir;
        generatedDir = Directory('$candidate/lib/src/generated');
        return;
      }
    }
    fail(
      'cannot locate packages/redpanda_light_client/protos from '
      '${Directory.current.path}',
    );
  });

  /// Parses a `<sha256>  <name>` lock file, skipping `#` comments.
  Map<String, String> readLock(File lock, String createdBy) {
    expect(
      lock.existsSync(),
      isTrue,
      reason: '${lock.path} is missing — run $createdBy',
    );
    final entries = <String, String>{};
    for (final line in lock.readAsLinesSync()) {
      if (line.startsWith('#') || line.trim().isEmpty) continue;
      final parts = line.split('  ');
      expect(parts.length, 2, reason: 'malformed lock entry: $line');
      entries[parts[1]] = parts[0];
    }
    expect(entries, isNotEmpty, reason: '${lock.path} lists no files');
    return entries;
  }

  Set<String> filesIn(Directory dir, String suffix) => dir
      .listSync()
      .whereType<File>()
      .map((f) => f.uri.pathSegments.last)
      .where((n) => n.endsWith(suffix))
      .toSet();

  /// Generated Dart, top level plus `client/` (the depth
  /// tool/generate_protos.sh hashes), as `client/x.pb.dart`-style paths.
  Set<String> generatedFiles() {
    final client = Directory('${generatedDir.path}/client');
    return {
      ...filesIn(generatedDir, '.dart'),
      if (client.existsSync())
        ...filesIn(client, '.dart').map((n) => 'client/$n'),
    };
  }

  void expectHashesMatch(
    Directory dir,
    Map<String, String> expected,
    String fixHint,
  ) {
    for (final entry in expected.entries) {
      final file = File('${dir.path}/${entry.key}');
      expect(file.existsSync(), isTrue, reason: '${entry.key} is missing');
      final actual = sha256.convert(file.readAsBytesSync()).toString();
      expect(
        actual,
        entry.value,
        reason: '${entry.key} was edited after the last run of $fixHint',
      );
    }
  }

  group('vendored protos', () {
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

    test('the .proto files match UPSTREAM.lock', () {
      final expected = readLock(
        File('${protoDir.path}/UPSTREAM.lock'),
        'tool/sync_protos.sh',
      );
      expect(
        filesIn(protoDir, '.proto'),
        equals(expected.keys.toSet()),
        reason:
            'every vendored .proto must be listed in UPSTREAM.lock and vice '
            'versa — re-run tool/sync_protos.sh',
      );
      expectHashesMatch(
        protoDir,
        expected,
        'tool/sync_protos.sh (the schemas are owned by '
        'redPanda-project/redpandaj — change them there)',
      );
    });
  });

  group('generated protobuf Dart', () {
    test('matches CODEGEN.lock', () {
      final expected = readLock(
        File('${generatedDir.path}/CODEGEN.lock'),
        'tool/generate_protos.sh',
      );
      expect(
        generatedFiles(),
        equals(expected.keys.toSet()),
        reason:
            'generated files and CODEGEN.lock disagree — re-run '
            'tool/generate_protos.sh',
      );
      expectHashesMatch(generatedDir, expected, 'tool/generate_protos.sh');
    });

    test('was produced by the protoc_plugin pinned in pubspec.lock', () {
      // A plugin bump in pubspec.lock without a re-run of
      // tool/generate_protos.sh leaves stale generated code behind that the
      // hashes above cannot see (TD098/T142 found 25.0.0 output under a 25.1.0
      // pin).
      final lockPath = '${generatedDir.parent.parent.parent.path}/pubspec.lock';
      final pubspecLock = File(
        lockPath,
      ).readAsStringSync().replaceAll('\r\n', '\n');
      final pinned = RegExp(
        r'\n  protoc_plugin:\n(?:    .*\n)*?    version: "([^"]+)"',
      ).firstMatch(pubspecLock)?.group(1);
      expect(pinned, isNotNull, reason: 'protoc_plugin missing in $lockPath');
      final codegenLine = File('${generatedDir.path}/CODEGEN.lock')
          .readAsLinesSync()
          .firstWhere(
            (l) => l.startsWith('# protoc_plugin:'),
            orElse: () => '',
          );
      expect(
        codegenLine.replaceFirst('# protoc_plugin:', '').trim(),
        pinned,
        reason:
            'pubspec.lock pins protoc_plugin $pinned — re-run '
            'tool/generate_protos.sh',
      );
    });

    test('every vendored and client .proto has generated Dart', () {
      final generated = generatedFiles();
      final clientDir = Directory('${protoDir.path}/client');
      final protos = [
        ...filesIn(protoDir, '.proto'),
        ...filesIn(clientDir, '.proto').map((n) => 'client/$n'),
      ];
      expect(
        protos.where((p) => p.startsWith('client/')),
        isNotEmpty,
        reason: 'protos/client/ must hold the client-to-client schemas',
      );
      for (final proto in protos) {
        final base = proto.substring(0, proto.length - '.proto'.length);
        expect(
          generated,
          containsAll(<String>[
            '$base.pb.dart',
            '$base.pbenum.dart',
            '$base.pbjson.dart',
          ]),
          reason: 'run tool/generate_protos.sh',
        );
      }
    });
  });
}
