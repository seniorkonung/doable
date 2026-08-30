import 'package:doable/src/intention/domain/intention_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('текст намерения', () {
    test('нормализует только окружающие пробелы в названии', () {
      expect(
        IntentionText.normalizeTitle('  быть  здоровым  '),
        'быть  здоровым',
      );
    });

    test('принимает одно и 255 составных emoji в названии', () {
      expect(IntentionText.normalizeTitle('👩🏽‍💻'), '👩🏽‍💻');
      expect(
        IntentionText.normalizeTitle(List.filled(255, '👩🏽‍💻').join()),
        List.filled(255, '👩🏽‍💻').join(),
      );
    });

    test('отклоняет пустое, BOM и слишком длинное название', () {
      expect(
        () => IntentionText.normalizeTitle(' \n\t '),
        _throwsTextFailure(IntentionTextValidationFailure.emptyTitle),
      );
      expect(
        () => IntentionText.normalizeTitle('\uFEFF'),
        _throwsTextFailure(IntentionTextValidationFailure.emptyTitle),
      );
      expect(
        () => IntentionText.normalizeTitle(List.filled(256, '👩🏽‍💻').join()),
        _throwsTextFailure(IntentionTextValidationFailure.titleTooLong),
      );
    });

    test('преобразует только пробельное описание в отсутствие', () {
      expect(IntentionText.normalizeDescription(' \n\t '), isNull);
    });

    test('сохраняет непустое описание посимвольно', () {
      const description = '  Первая строка\n\nВторая строка  ';

      expect(IntentionText.normalizeDescription(description), description);
    });

    test('принимает 4096 и отклоняет 4097 графем в описании', () {
      expect(
        IntentionText.normalizeDescription(List.filled(4096, '👩🏽‍💻').join()),
        hasLength(List.filled(4096, '👩🏽‍💻').join().length),
      );
      expect(
        () => IntentionText.normalizeDescription(
          List.filled(4097, '👩🏽‍💻').join(),
        ),
        _throwsTextFailure(IntentionTextValidationFailure.descriptionTooLong),
      );
    });
  });
}

Matcher _throwsTextFailure(IntentionTextValidationFailure failure) => throwsA(
  isA<IntentionTextValidationException>().having(
    (exception) => exception.failure,
    'failure',
    failure,
  ),
);
