import 'package:doable/src/daily_choice/domain/daily_choice_description.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('описание дневного выбора', () {
    test('превращает полностью пробельный ввод в отсутствие', () {
      expect(DailyChoiceDescription.fromInput(''), isNull);
      expect(DailyChoiceDescription.fromInput(' \n\t '), isNull);
      expect(
        DailyChoiceDescription.fromInput(List.filled(4097, ' ').join()),
        isNull,
      );
    });

    test('сохраняет текст и составные графемы без нормализации', () {
      const value = '  Строка\n👩🏽‍💻 и e\u0301\t  ';
      final description = DailyChoiceDescription.fromInput(value);

      expect(description?.value, value);
      expect(description, DailyChoiceDescription.fromStored(value));
      expect(DailyChoiceDescription.fromInput('é')?.value, isNot('e\u0301'));
    });

    test('принимает 4096 и отклоняет 4097 расширенных графем', () {
      final allowed = List.filled(4096, '👩🏽‍💻').join();
      final excessive = '$allowed👩🏽‍💻';

      expect(DailyChoiceDescription.fromInput(allowed)?.value, allowed);
      expect(
        () => DailyChoiceDescription.fromInput(excessive),
        _throwsDescriptionFailure(
          DailyChoiceDescriptionValidationReason.tooLong,
        ),
      );
      expect(
        () => DailyChoiceDescription.fromStored(excessive),
        _throwsDescriptionFailure(
          DailyChoiceDescriptionValidationReason.tooLong,
        ),
      );
    });

    test('проверяет Unicode до пробельности и длины', () {
      for (final invalid in [
        '\u0000',
        String.fromCharCode(0xd800),
        String.fromCharCode(0xdc00),
      ]) {
        final value = '${List.filled(4097, ' ').join()}$invalid';
        expect(
          () => DailyChoiceDescription.fromInput(value),
          _throwsDescriptionFailure(
            DailyChoiceDescriptionValidationReason.invalidUnicodeRepertoire,
          ),
        );
        expect(
          () => DailyChoiceDescription.fromStored(value),
          _throwsDescriptionFailure(
            DailyChoiceDescriptionValidationReason.invalidUnicodeRepertoire,
          ),
        );
      }
    });

    test('при чтении отвергает сохранённое пробельное значение', () {
      for (final value in ['', ' \n\t ']) {
        expect(
          () => DailyChoiceDescription.fromStored(value),
          _throwsDescriptionFailure(
            DailyChoiceDescriptionValidationReason.absent,
          ),
        );
      }
    });
  });
}

Matcher _throwsDescriptionFailure(
  DailyChoiceDescriptionValidationReason reason,
) => throwsA(
  isA<DailyChoiceDescriptionValidationException>()
      .having(
        (exception) => exception.failure.field,
        'поле',
        DailyChoiceDescriptionField.description,
      )
      .having((exception) => exception.failure.reason, 'причина', reason),
);
