import 'package:test/test.dart';

import '../helpers/wait_for.dart';

void main() {
  test(
    'onPoll runs once per failed poll; message is not built on success',
    () async {
      var checks = 0;
      var polls = 0;
      var messages = 0;
      await waitFor(
        () => ++checks >= 3,
        interval: const Duration(milliseconds: 1),
        onPoll: () => polls++,
        message: () => '${messages++}',
      );
      expect(checks, 3);
      expect(polls, 2);
      expect(messages, 0);
    },
  );

  test('a timeout fails with the lazily built message', () async {
    var state = 'early';
    final result = waitFor(
      () => false,
      timeout: const Duration(milliseconds: 30),
      interval: const Duration(milliseconds: 5),
      onPoll: () => state = 'late',
      message: () => 'state at timeout: $state',
    );
    await expectLater(
      result,
      throwsA(
        isA<TestFailure>().having(
          (e) => e.message,
          'message',
          'state at timeout: late',
        ),
      ),
    );
  });

  test('without message the description default is kept', () async {
    await expectLater(
      waitFor(
        () => false,
        timeout: const Duration(milliseconds: 20),
        description: 'thing',
      ),
      throwsA(
        isA<TestFailure>().having(
          (e) => e.message,
          'message',
          startsWith('thing not met within'),
        ),
      ),
    );
  });
}
