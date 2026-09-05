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
        _throwsTextFailure(
          field: IntentionTextField.title,
          reason: IntentionTextValidationReason.empty,
        ),
      );
      expect(
        () => IntentionText.normalizeTitle('\uFEFF'),
        _throwsTextFailure(
          field: IntentionTextField.title,
          reason: IntentionTextValidationReason.empty,
        ),
      );
      expect(
        () => IntentionText.normalizeTitle(List.filled(256, '👩🏽‍💻').join()),
        _throwsTextFailure(
          field: IntentionTextField.title,
          reason: IntentionTextValidationReason.tooLong,
        ),
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
        _throwsTextFailure(
          field: IntentionTextField.description,
          reason: IntentionTextValidationReason.tooLong,
        ),
      );
    });

    test('отклоняет NUL и непарные UTF-16 surrogate до нормализации', () {
      final invalidValues = [
        '\u0000',
        String.fromCharCode(0xd800),
        String.fromCharCode(0xdc00),
      ];

      for (final invalidValue in invalidValues) {
        expect(
          () => IntentionText.normalizeTitle('до$invalidValueпосле'),
          _throwsTextFailure(
            field: IntentionTextField.title,
            reason: IntentionTextValidationReason.invalidUnicodeRepertoire,
          ),
        );
        expect(
          () => IntentionText.normalizeDescription('до$invalidValueпосле'),
          _throwsTextFailure(
            field: IntentionTextField.description,
            reason: IntentionTextValidationReason.invalidUnicodeRepertoire,
          ),
        );
      }
    });

    test('сохраняет корректные scalar values без Unicode-нормализации', () {
      const title = 'Название\tс\n👩🏽‍💻 и e\u0301';
      const description = '  Строка\nс\t👩🏽‍💻 и é  ';

      expect(IntentionText.normalizeTitle(title), title);
      expect(IntentionText.normalizeDescription(description), description);
    });
  });
}

Matcher _throwsTextFailure({
  required IntentionTextField field,
  required IntentionTextValidationReason reason,
}) => throwsA(
  isA<IntentionTextValidationException>()
      .having((exception) => exception.failure.field, 'field', field)
      .having((exception) => exception.failure.reason, 'reason', reason),
);
