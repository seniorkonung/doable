import 'package:doable/src/long_term_relation/domain/long_term_relation_description.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('описание долговременной связи', () {
    test('преобразует пустой и полностью пробельный ввод в отсутствие', () {
      expect(LongTermRelationDescription.fromInput(''), isNull);
      expect(LongTermRelationDescription.fromInput(' \n\t '), isNull);
      expect(
        LongTermRelationDescription.fromInput(List.filled(4097, ' ').join()),
        isNull,
      );
    });

    test('сохраняет присутствующий текст посимвольно', () {
      const input = '  Первая строка\n\nВторая\t👩🏽‍💻 и e\u0301  ';

      final description = LongTermRelationDescription.fromInput(input);

      expect(description, isNotNull);
      expect(description!.value, input);
      expect(description, LongTermRelationDescription.fromInput(input));
    });

    test('принимает ровно 4096 расширенных графемных кластеров', () {
      final input = List.filled(4096, '👩🏽‍💻').join();

      final description = LongTermRelationDescription.fromInput(input);

      expect(description, isNotNull);
      expect(description!.value, input);
    });

    test('отклоняет 4097 расширенных графемных кластеров', () {
      final input = List.filled(4097, '👩🏽‍💻').join();

      expect(
        () => LongTermRelationDescription.fromInput(input),
        _throwsDescriptionFailure(LongTermRelationTextValidationReason.tooLong),
      );
    });

    test('отклоняет NUL и непарные UTF-16 surrogate как ошибку поля', () {
      final invalidValues = [
        '\u0000',
        String.fromCharCode(0xd800),
        String.fromCharCode(0xdc00),
      ];

      for (final invalidValue in invalidValues) {
        expect(
          () => LongTermRelationDescription.fromInput('до$invalidValueпосле'),
          _throwsDescriptionFailure(
            LongTermRelationTextValidationReason.invalidUnicodeRepertoire,
          ),
        );
      }
    });

    test('проверяет Unicode до определения пробельности и длины', () {
      final input = '${List.filled(4097, ' ').join()}\u0000';

      expect(
        () => LongTermRelationDescription.fromInput(input),
        _throwsDescriptionFailure(
          LongTermRelationTextValidationReason.invalidUnicodeRepertoire,
        ),
      );
    });
  });
}

Matcher _throwsDescriptionFailure(
  LongTermRelationTextValidationReason reason,
) => throwsA(
  isA<LongTermRelationTextValidationException>()
      .having(
        (exception) => exception.failure.field,
        'field',
        LongTermRelationTextField.description,
      )
      .having((exception) => exception.failure.reason, 'reason', reason),
);
