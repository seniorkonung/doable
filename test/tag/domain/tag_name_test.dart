import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('название тега', () {
    test('удаляет только окружающие пробелы и сохраняет написание', () {
      final name = TagName.fromInput('  Для  дома  ');

      expect(name.value, 'Для  дома');
      expect(TagName.fromStored(name.value), name);
      expect(TagName.fromInput('e\u0301').value, 'e\u0301');
    });

    test('принимает 255 составных emoji и отклоняет 256', () {
      final atLimit = List.filled(255, '👩🏽‍💻').join();
      final overLimit = List.filled(256, '👩🏽‍💻').join();

      expect(TagName.fromInput(atLimit).value, atLimit);
      expect(
        () => TagName.fromInput(overLimit),
        _failsWith(TagNameFailureReason.tooLong),
      );
    });

    test('отклоняет пустое название после trim', () {
      for (final input in ['', ' \n\t ', '\uFEFF']) {
        expect(
          () => TagName.fromInput(input),
          _failsWith(TagNameFailureReason.empty),
        );
      }
    });

    test('проверяет NUL и оба непарных surrogate до обрезки', () {
      for (final invalid in [
        '\u0000',
        String.fromCharCode(0xd800),
        String.fromCharCode(0xdc00),
      ]) {
        expect(
          () => TagName.fromInput(' $invalid '),
          _failsWith(TagNameFailureReason.invalidUnicodeRepertoire),
        );
        expect(
          () => TagName.fromStored(' $invalid '),
          _failsWith(TagNameFailureReason.invalidUnicodeRepertoire),
        );
      }
    });

    test('строгое чтение отклоняет неканоничные и повреждённые значения', () {
      for (final input in [' Дом', 'Дом ', '\uFEFFДом']) {
        expect(
          () => TagName.fromStored(input),
          _failsWith(TagNameFailureReason.nonCanonical),
        );
      }
      expect(
        () => TagName.fromStored(' \n '),
        _failsWith(TagNameFailureReason.empty),
      );
      expect(
        () => TagName.fromStored(List.filled(256, '👩🏽‍💻').join()),
        _failsWith(TagNameFailureReason.tooLong),
      );
    });

    test('ключ использует полное Unicode folding без нормализации', () {
      expect(
        TagName.fromInput('Straße').matchingKey,
        TagName.fromInput('STRASSE').matchingKey,
      );
      expect(
        TagName.fromInput('Все').matchingKey,
        isNot(TagName.fromInput('Всё').matchingKey),
      );
      expect(
        TagName.fromInput('é').matchingKey,
        isNot(TagName.fromInput('e\u0301').matchingKey),
      );
    });
  });
}

Matcher _failsWith(TagNameFailureReason reason) => throwsA(
  isA<TagNameValidationException>().having(
    (exception) => exception.reason,
    'reason',
    reason,
  ),
);
