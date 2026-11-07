import 'package:doable/src/action/domain/action_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('запланированное время действия', () {
    test('принимает граничные часы 0 и 23', () {
      expect(ActionAtHour(0).hour, 0);
      expect(ActionAtHour(23).hour, 23);
    });

    test('отклоняет час вне 0–23', () {
      expect(() => ActionAtHour(-1), throwsRangeError);
      expect(() => ActionAtHour(24), throwsRangeError);
    });
  });
}
