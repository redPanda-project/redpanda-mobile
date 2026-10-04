import 'dart:io';

import 'package:test/test.dart';

/// TD120: every node-backed e2e suite binds its own, hard-coded node ports
/// (T30: suite-private ports instead of a shared topology lock). Two suites
/// that copy the same range wedge each other as soon as one leaves a node
/// bound — `could not bound to port: 50590` hit ms06 and t45 that way, and the
/// t45 self-hop probe shared 50600 with ms08. This pins the invariant on the
/// source text so a copy-pasted range fails here, not as a CI flake.
void main() {
  test('no two e2e suites use the same node port', () {
    // Node ports live in 50000–50999; 59557/59558 are blackhole/default
    // addresses that never get bound by a test node. Every 50xxx literal in a
    // suite counts, comments included — refer to another suite's ports by
    // name, not by number.
    final portPattern = RegExp(r'\b50\d{3}\b');
    final owners = <int, Set<String>>{};
    final suites = Directory(
      'test/e2e',
    ).listSync().whereType<File>().where((f) => f.path.endsWith('_test.dart'));
    for (final file in suites) {
      final name = file.uri.pathSegments.last;
      for (final match in portPattern.allMatches(file.readAsStringSync())) {
        owners.putIfAbsent(int.parse(match[0]!), () => {}).add(name);
      }
    }

    expect(owners, isNotEmpty, reason: 'no e2e suites found under test/e2e');
    final shared = {
      for (final e in owners.entries)
        if (e.value.length > 1) e.key: e.value,
    };
    expect(shared, isEmpty, reason: 'e2e suites must use disjoint ports');
  });
}
