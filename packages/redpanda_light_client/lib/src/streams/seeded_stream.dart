import 'dart:async';

/// Wraps a broadcast [source] so every subscriber first receives the values
/// [seed] returns, and receives them *without* the gap the obvious idiom
/// leaves open. [seed] returns an iterable so a getter with no current value
/// yet (an empty snapshot) can simply seed nothing.
///
/// The obvious idiom is
///
/// ```dart
/// Stream<T> get thing async* {
///   yield _current;
///   yield* _controller.stream;
/// }
/// ```
///
/// which looks like a replay but is not one: an `async*` generator suspends at
/// the `yield` until the subscriber asks for the next event, so the
/// subscription to `_controller.stream` is only attached an event-loop turn
/// later. Anything the producer emits in that window reaches a broadcast
/// controller with no listeners and is dropped — and since the seed already
/// went out with the *old* value, the subscriber is left holding stale state
/// until the next change happens to come along.
///
/// That is T81: the app's `connectionStatusProvider` kept reporting
/// `connecting` while the node log showed the peer connected and the client
/// polling mailboxes normally, so the emulator gate failed with "client never
/// connected to the node" after its 3-minute wait.
///
/// Here the seed and the upstream subscription happen in the same synchronous
/// turn inside `onListen`, so no event can slip between them: nothing is lost,
/// and the seed is always the first event.
Stream<T> seededStream<T>(Iterable<T> Function() seed, Stream<T> source) {
  late final StreamController<T> controller;
  StreamSubscription<T>? subscription;
  controller = StreamController<T>(
    onListen: () {
      seed().forEach(controller.add);
      subscription = source.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
    },
    onCancel: () async {
      final sub = subscription;
      subscription = null;
      await sub?.cancel();
    },
  );
  return controller.stream;
}
