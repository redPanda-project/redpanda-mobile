import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

/// TD091: the Dart command bytes are hand-written mirrors of redpandaj
/// `im.redpanda.core.Command` (top-level frame commands) and
/// `im.redpanda.routing.FlaschenpostV2` (garlic layer commands). This test
/// checks every one of them against the wire registry redpandaj generates
/// from exactly those constants.
///
/// `test/fixtures/wire-registry.md` is a verbatim copy of redpandaj
/// `src/main/resources/wire-registry.md` at commit
/// 0dba7bb284166309eb71d04aea12a268bc656c07 (pinned by [_fixtureSha256] so a
/// hand-edit of the fixture cannot quietly agree with a wrong Dart value).
/// When redpandaj adds or changes a command, copy the file again, update the
/// SHA-256 and the commit above, then mirror the byte in Dart.
///
/// Coverage is discovered, not listed: every `const int cmd…`/`_cmd…` in
/// `lib/` (generated code excluded) is parsed from source and must match a
/// registry row whose name equals it modulo case and underscores
/// (`_cmdOutboundAckFetchReq` <-> `OUTBOUND_ACK_FETCH_REQ`). Constants in
/// `garlic_builder.dart` are garlic layer commands and are looked up in the
/// garlic table (`cmdForward` <-> `CMD_FORWARD`), everything else in the
/// top-level table.
const String _fixtureSha256 =
    '9b8c9a2b4c2c6212624d23034bcf37197ba541ac0ce51dcec959a9f920e2386c';

/// A Dart command-byte declaration, e.g. `static const int _cmdPing = 5;`.
final RegExp _cmdDeclaration = RegExp(
  r'const\s+int\s+(_?cmd\w+)\s*=\s*(0x[0-9A-Fa-f]+|\d+)\s*;',
);

/// Loose detector for anything that looks like a command constant, so a
/// declaration [_cmdDeclaration] cannot parse fails instead of being skipped.
/// Also catches `static const _cmdX = …` and `final int _cmdX = …`.
final RegExp _cmdLooseDeclaration = RegExp(
  r'\b(?:const|final|var)\s+(?:int\s+)?_?cmd[A-Z]',
);

/// Call sites that must name their command byte instead of using a literal
/// (TD091): `sendCommand(142, …)`, `command == 158`, `_pendingResponses[153]`
/// and the command byte of a signed request (`signingBuffer.addByte(159)`).
/// A literal is any decimal or hex number, e.g. `0xA0`.
final RegExp _bareCommandLiteral = RegExp(
  r'(?:sendCommand\(|command\s*==|_pendingResponses(?:\[|\.remove\()'
  r'|signingBuffer\.addByte\()\s*(?:0x[0-9A-Fa-f]|\d)',
);

/// A registry table row: `| `NAME` | 142 | `0x8E` |`.
final RegExp _registryRow = RegExp(
  r'^\| `([A-Z0-9_]+)` \| (\d+) \| `0x[0-9A-F]{2}` \|$',
);

String _normalize(String name) =>
    name.replaceAll('_', '').toLowerCase().replaceFirst(RegExp('^cmd'), '');

void main() {
  late Directory packageDir;

  setUpAll(() {
    for (final candidate in const ['.', 'packages/redpanda_light_client']) {
      if (File('$candidate/test/fixtures/wire-registry.md').existsSync()) {
        packageDir = Directory(candidate);
        return;
      }
    }
    fail(
      'cannot locate packages/redpanda_light_client from '
      '${Directory.current.path}',
    );
  });

  File fixture() => File('${packageDir.path}/test/fixtures/wire-registry.md');

  /// Parses the rows of one `## ` section into normalized name -> byte.
  Map<String, int> registrySection(String registry, String heading) {
    final start = registry.indexOf(heading);
    expect(start, greaterThanOrEqualTo(0), reason: 'missing section $heading');
    final end = registry.indexOf('\n## ', start + heading.length);
    final section = end < 0
        ? registry.substring(start)
        : registry.substring(start, end);
    final rows = <String, int>{};
    for (final line in section.split('\n')) {
      final m = _registryRow.firstMatch(line);
      if (m == null) continue;
      final key = _normalize(m.group(1)!);
      expect(rows.containsKey(key), isFalse, reason: 'ambiguous row $line');
      rows[key] = int.parse(m.group(2)!);
    }
    expect(rows, isNotEmpty, reason: 'no rows parsed in $heading');
    return rows;
  }

  test('fixture is the pinned verbatim copy of the redpandaj registry', () {
    final digest = sha256.convert(fixture().readAsBytesSync()).toString();
    expect(
      digest,
      _fixtureSha256,
      reason:
          'test/fixtures/wire-registry.md changed. It must be a verbatim '
          'copy of redpandaj src/main/resources/wire-registry.md; update '
          '_fixtureSha256 and the commit in the header together with it.',
    );
  });

  test('every Dart command-byte constant matches the wire registry', () {
    final registry = fixture().readAsStringSync();
    final topLevel = registrySection(registry, '## Top-level commands');
    final garlic = registrySection(registry, '## Garlic layer commands');

    final libDir = Directory('${packageDir.path}/lib');
    final checkedPerFile = <String, int>{};
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (path.contains('/generated/')) continue;
      final source = entity.readAsStringSync();
      expect(
        _bareCommandLiteral.allMatches(source).map((m) => m.group(0)),
        isEmpty,
        reason: '$path: use a named _cmd… constant instead of a bare byte',
      );
      final declarations = _cmdDeclaration.allMatches(source).toList();
      expect(
        declarations.length,
        _cmdLooseDeclaration.allMatches(source).length,
        reason:
            '$path: a command constant is declared in a form '
            'this test cannot parse — use `const int _cmdName = <int>;`',
      );
      if (declarations.isEmpty) continue;
      final isGarlic = path.endsWith('/garlic_builder.dart');
      final table = isGarlic ? garlic : topLevel;
      for (final m in declarations) {
        final dartName = m.group(1)!;
        final value = int.parse(m.group(2)!);
        final where = '$path: $dartName';
        final key = _normalize(dartName);
        expect(
          table.containsKey(key),
          isTrue,
          reason:
              '$where has no ${isGarlic ? 'garlic layer' : 'top-level'} '
              'command of that name in the wire registry',
        );
        expect(
          value,
          table[key],
          reason:
              '$where = $value, registry says '
              '${table[key]}',
        );
      }
      checkedPerFile[path.split('/lib/').last] = declarations.length;
    }

    // The known mirrors must actually have been scanned (guards against a
    // renamed file or a broken regex turning this test into a no-op).
    expect(
      checkedPerFile.keys,
      containsAll(<String>[
        'src/network/active_peer.dart',
        'src/client/redpanda_light_client.dart',
        'src/garlic/garlic_builder.dart',
      ]),
    );
  });
}
