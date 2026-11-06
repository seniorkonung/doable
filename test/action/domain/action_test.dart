import 'package:doable/src/action/domain/action.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('порядок создания действия', () {
    test('отклоняет неположительный номер', () {
      expect(() => ActionCreationSequence(0), throwsArgumentError);
      expect(() => ActionCreationSequence(-1), throwsArgumentError);
    });
  });

  test('показание времени действия переводит локальное время в UTC', () {
    final localTime = DateTime(2026, 10, 6, 15);

    final timestamp = ActionTimestamp(localTime);

    expect(timestamp.value.isUtc, isTrue);
    expect(
      timestamp.value.microsecondsSinceEpoch,
      localTime.microsecondsSinceEpoch,
    );
  });
}
