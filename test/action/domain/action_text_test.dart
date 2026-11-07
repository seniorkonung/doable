import 'package:doable/src/action/domain/action_text.dart';
import 'package:doable/src/intention/domain/intention_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('название действия', () {
    test('обрезает окружающие пробелы', () {
      expect(ActionTitle('  Пройти до парка  ').value, 'Пройти до парка');
    });

    test('отклоняет пустое после обрезки название', () {
      expect(
        () => ActionTitle(' \n\t '),
        _throwsTextFailure(
          field: IntentionTextField.title,
          reason: IntentionTextValidationReason.empty,
        ),
      );
    });

    test('подчиняется правилам названия намерения', () {
      expect(
        () => ActionTitle(List.filled(256, 'я').join()),
        _throwsTextFailure(
          field: IntentionTextField.title,
          reason: IntentionTextValidationReason.tooLong,
        ),
      );
    });
  });

  group('описание действия', () {
    test('пробельное описание означает отсутствие описания', () {
      expect(ActionDescription.fromInput(' \n\t '), isNull);
    });

    test('непустое описание сохраняется посимвольно', () {
      const text = '  Первая строка\n\nВторая строка  ';

      expect(ActionDescription.fromInput(text)?.value, text);
    });

    test('подчиняется правилам описания намерения', () {
      expect(
        () => ActionDescription.fromInput(List.filled(4097, 'я').join()),
        _throwsTextFailure(
          field: IntentionTextField.description,
          reason: IntentionTextValidationReason.tooLong,
        ),
      );
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
