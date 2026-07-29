import 'dart:async';

import 'package:test/test.dart';
import 'package:redpanda_light_client/src/streams/seeded_stream.dart';

void main() {
  group('T81 seededStream', () {
    test('delivers the seed first and keeps a same-turn event', () async {
      final source = StreamController<int>.broadcast();
      addTearDown(source.close);
      var current = 1;

      final seen = <int>[];
      final sub = seededStream(() => [current], source.stream).listen(seen.add);
      addTearDown(sub.cancel);

      // Same turn as listen(): this is exactly the window in which the old
      // `yield _current; yield* _controller.stream;` idiom had not attached to
      // the source yet.
      current = 2;
      source.add(2);
      await Future<void>.delayed(Duration.zero);

      expect(seen, [1, 2]);
    });

    test('an empty seed emits nothing until the source does', () async {
      final source = StreamController<int>.broadcast();
      addTearDown(source.close);

      final seen = <int>[];
      final sub = seededStream<int>(
        () => const [],
        source.stream,
      ).listen(seen.add);
      addTearDown(sub.cancel);

      await Future<void>.delayed(Duration.zero);
      expect(seen, isEmpty);

      source.add(7);
      await Future<void>.delayed(Duration.zero);
      expect(seen, [7]);
    });

    test('cancelling the subscription releases the upstream one', () async {
      final source = StreamController<int>.broadcast();
      addTearDown(source.close);

      final sub = seededStream(() => [0], source.stream).listen((_) {});
      await Future<void>.delayed(Duration.zero);
      expect(source.hasListener, isTrue);

      await sub.cancel();
      expect(source.hasListener, isFalse);
    });

    test(
      'the idiom it replaces really does drop that event (regression guard)',
      () async {
        // Pins the reason seededStream exists: if this ever starts passing,
        // Dart changed its async* semantics and the helper can be revisited.
        final source = StreamController<int>.broadcast();
        addTearDown(source.close);
        var current = 1;

        Stream<int> oldIdiom() async* {
          yield current;
          yield* source.stream;
        }

        final seen = <int>[];
        final sub = oldIdiom().listen(seen.add);
        addTearDown(sub.cancel);

        current = 2;
        source.add(3);
        await Future<void>.delayed(Duration.zero);

        // Only the seed arrives — `3` was emitted while the generator had not
        // reached `yield* source` yet, so the broadcast controller had no
        // listener and dropped it. Which value the seed carries is timing
        // dependent (the generator body itself only starts on the first pull);
        // the event loss is not, and that is what left
        // connectionStatusProvider stuck on "connecting" until the next
        // status change happened to come along.
        expect(seen, hasLength(1));
        expect(seen, isNot(contains(3)));
      },
    );
  });
}
