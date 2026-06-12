import 'package:test/test.dart';

import 'package:redpanda_light_client/src/garlic/session_tag_store.dart';

void main() {
  group('SessionTagStore lifecycle (MS05)', () {
    late SessionTagStore store;

    setUp(() => store = SessionTagStore());

    test('store → lookup → consume is single-use', () {
      store.store('aa' * 16, 'channel-1');

      expect(store.lookup('aa' * 16), 'channel-1');
      expect(store.lookup('aa' * 16), 'channel-1', reason: 'lookup is free');

      expect(store.consume('aa' * 16), 'channel-1');
      expect(store.lookup('aa' * 16), isNull);
      expect(
        store.consume('aa' * 16),
        isNull,
        reason: 'a consumed tag never resolves again',
      );
    });

    test('unknown tags resolve to null', () {
      expect(store.lookup('bb' * 16), isNull);
      expect(store.consume('bb' * 16), isNull);
    });

    test('tagsForChannel snapshots only the requested channel', () {
      store.store('aa' * 16, 'channel-1', createdAtMs: 1000);
      store.store('bb' * 16, 'channel-1', createdAtMs: 2000);
      store.store('cc' * 16, 'channel-2', createdAtMs: 3000);

      expect(
        store.tagsForChannel('channel-1'),
        equals({'aa' * 16: 1000, 'bb' * 16: 2000}),
      );
      expect(store.hasTagsFor('channel-2'), isTrue);
      expect(store.hasTagsFor('channel-3'), isFalse);
    });

    test('cleanup drops tags older than 48h and reports their channels', () {
      const hour = 3600 * 1000;
      store.store('aa' * 16, 'channel-1', createdAtMs: 0);
      store.store('bb' * 16, 'channel-2', createdAtMs: 47 * hour);

      final affected = store.cleanup(nowMs: 49 * hour);

      expect(affected, equals({'channel-1'}));
      expect(store.lookup('aa' * 16), isNull);
      expect(store.lookup('bb' * 16), 'channel-2');
    });
  });
}
