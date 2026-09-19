import 'package:doable/src/shared/domain/unicode_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('общая проверка Unicode-текста', () {
    test('отклоняет NUL и непарные UTF-16 surrogate', () {
      final invalidValues = [
        '\u0000',
        String.fromCharCode(0xd800),
        String.fromCharCode(0xdc00),
      ];

      for (final invalidValue in invalidValues) {
        expect(
          () => UnicodeText.ensureValidScalarValuesWithoutNul(
            'до$invalidValueпосле',
          ),
          throwsA(isA<InvalidUnicodeTextException>()),
        );
      }
    });

    test('принимает остальные корректные скалярные значения без изменений', () {
      const value = 'Строка\nс\t👩🏽‍💻, e\u0301, \u200D и \u202E';

      expect(
        () => UnicodeText.ensureValidScalarValuesWithoutNul(value),
        returnsNormally,
      );
    });

    test('принимает корректную UTF-16 surrogate pair', () {
      final value = String.fromCharCodes([0xd83d, 0xde00]);

      expect(
        () => UnicodeText.ensureValidScalarValuesWithoutNul(value),
        returnsNormally,
      );
    });
  });
}
