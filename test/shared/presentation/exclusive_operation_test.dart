import 'dart:async';

import 'package:doable/src/shared/presentation/exclusive_operation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ExclusiveOperation', () {
    test('синхронно резервирует выполнение и не запускает повтор', () async {
      final operation = ExclusiveOperation<int>();
      final result = Completer<int>();
      var invocations = 0;

      final first = operation.start(() {
        invocations++;
        return result.future;
      });
      final repeated = operation.start(() {
        invocations++;
        return 2;
      });

      expect(first, isA<ExclusiveOperationAccepted<int>>());
      expect(repeated, isA<ExclusiveOperationAlreadyRunning<int>>());
      expect(operation.isRunning, isTrue);
      expect(invocations, 1);

      result.complete(1);
      expect(await (first as ExclusiveOperationAccepted<int>).future, 1);
      expect(operation.isRunning, isFalse);

      final next = operation.start(() => 3);
      expect(next, isA<ExclusiveOperationAccepted<int>>());
      expect(await (next as ExclusiveOperationAccepted<int>).future, 3);
    });

    test('освобождает gate после асинхронной и синхронной ошибки', () async {
      final operation = ExclusiveOperation<int>();
      final asynchronous = Completer<int>();
      final first = operation.start(
        () => asynchronous.future,
      ) as ExclusiveOperationAccepted<int>;

      asynchronous.completeError(StateError('асинхронный отказ'));
      await expectLater(first.future, throwsStateError);
      expect(operation.isRunning, isFalse);

      final second = operation.start(() {
        throw StateError('синхронный отказ');
      }) as ExclusiveOperationAccepted<int>;
      await expectLater(second.future, throwsStateError);
      expect(operation.isRunning, isFalse);
    });

    test('не связывает независимые экземпляры', () async {
      final firstOperation = ExclusiveOperation<int>();
      final secondOperation = ExclusiveOperation<int>();
      final firstResult = Completer<int>();

      final first = firstOperation.start(() => firstResult.future);
      final second = secondOperation.start(() => 2);

      expect(first, isA<ExclusiveOperationAccepted<int>>());
      expect(second, isA<ExclusiveOperationAccepted<int>>());
      expect(await (second as ExclusiveOperationAccepted<int>).future, 2);

      firstResult.complete(1);
      expect(await (first as ExclusiveOperationAccepted<int>).future, 1);
    });
  });
}
