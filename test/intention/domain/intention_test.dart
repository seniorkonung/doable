import 'package:doable/src/intention/domain/intention.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('временная метка переводит локальное время в UTC без смены момента', () {
    final localTime = DateTime(2026, 8, 29, 15);

    final timestamp = IntentionTimestamp(localTime);

    expect(localTime.isUtc, isFalse);
    expect(timestamp.value.isUtc, isTrue);
    expect(
      timestamp.value.microsecondsSinceEpoch,
      localTime.microsecondsSinceEpoch,
    );
  });
}
