import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('изменение описания из введённого текста', () {
    test('полностью пробельный текст очищает описание', () {
      final patch = DailyChoiceDescriptionPatch.fromInput(' \n\t ');

      expect(patch, isA<DailyChoiceDescriptionCleared>());
    });

    test('текст сохраняется целиком с окружающими пробелами и переносами', () {
      const input = '  Первая строка\n\nвторая  ';

      final patch = DailyChoiceDescriptionPatch.fromInput(input);

      expect(
        patch,
        isA<DailyChoiceDescriptionSet>().having(
          (patch) => patch.value.value,
          'value',
          input,
        ),
      );
    });
  });
}
