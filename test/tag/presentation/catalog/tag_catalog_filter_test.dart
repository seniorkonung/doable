import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('фильтр каталога тегов', () {
    test('пустой запрос соответствует любому названию', () {
      final filter = _filter('');

      expect(filter.isEmpty, isTrue);
      for (final name in ['Дом', 'Работа', 'Straße', '👩🏽‍💻']) {
        expect(filter.matches(TagName.fromInput(name)), isTrue);
      }
    });

    test(
      'находит кириллическую подстроку в любом месте без учёта регистра',
      () {
        final filter = _filter('дом');

        expect(filter.isEmpty, isFalse);
        expect(filter.matches(TagName.fromInput('Дом')), isTrue);
        expect(filter.matches(TagName.fromInput('Для дома')), isTrue);
        expect(filter.matches(TagName.fromInput('Домашнее')), isTrue);
        expect(filter.matches(TagName.fromInput('Работа')), isFalse);
      },
    );

    test('использует многосимвольное сопоставление названия и запроса', () {
      expect(_filter('STRASS').matches(TagName.fromInput('Straße')), isTrue);
      expect(_filter('straß').matches(TagName.fromInput('STRASSE')), isTrue);
      expect(_filter('FFI').matches(TagName.fromInput('офис ﬃ')), isTrue);
      expect(_filter('ﬃ').matches(TagName.fromInput('офис FFI')), isTrue);
    });

    test('сопоставляет греческую конечную сигму по общему правилу', () {
      expect(_filter('οσ').matches(TagName.fromInput('ΟΣ')), isTrue);
      expect(_filter('ος').matches(TagName.fromInput('οσ')), isTrue);
    });

    test('не применяет турецкие правила регистра', () {
      expect(_filter('I').matches(TagName.fromInput('i')), isTrue);
      expect(_filter('I').matches(TagName.fromInput('ı')), isFalse);
      expect(_filter('İ').matches(TagName.fromInput('i')), isFalse);
      expect(_filter('İ').matches(TagName.fromInput('i\u0307')), isTrue);
    });

    test('различает буквы е и ё', () {
      expect(_filter('ВСЕ').matches(TagName.fromInput('Все')), isTrue);
      expect(_filter('ВСЕ').matches(TagName.fromInput('Всё')), isFalse);
      expect(_filter('ВСЁ').matches(TagName.fromInput('Все')), isFalse);
    });

    test('не нормализует составные и разложенные символы', () {
      expect(_filter('É').matches(TagName.fromInput('é')), isTrue);
      expect(_filter('É').matches(TagName.fromInput('e\u0301')), isFalse);
      expect(_filter('E\u0301').matches(TagName.fromInput('é')), isFalse);
      expect(_filter('E\u0301').matches(TagName.fromInput('e\u0301')), isTrue);
    });

    test('сохраняет окружающие пробелы запроса', () {
      final filter = _filter(' дом ');

      expect(filter.matches(TagName.fromInput('Мой дом сегодня')), isTrue);
      expect(filter.matches(TagName.fromInput('Дом')), isFalse);
      expect(filter.matches(TagName.fromInput('Для дома')), isFalse);
    });

    test('сохраняет количество внутренних пробелов', () {
      final filter = _filter('ДЛЯ  ДОМА');

      expect(filter.matches(TagName.fromInput('Тег для  дома')), isTrue);
      expect(filter.matches(TagName.fromInput('Тег для дома')), isFalse);
    });

    test('пробельный запрос участвует в буквальном поиске', () {
      final filter = _filter(' \t');

      expect(filter.isEmpty, isFalse);
      expect(filter.matches(TagName.fromInput('Для \tдома')), isTrue);
      expect(filter.matches(TagName.fromInput('Для дома')), isFalse);
    });

    test('символы шаблонов и регулярных выражений ищет буквально', () {
      for (final query in ['%', '_', '.', '*', '[дом]', r'\d', '.*']) {
        final filter = _filter(query);

        expect(filter.matches(TagName.fromInput('Тег $query здесь')), isTrue);
        expect(filter.matches(TagName.fromInput('Дом 123')), isFalse);
      }
    });

    test('принимает запрос длиннее ограничения названия тега', () {
      final input = List.filled(TagName.maxGraphemeClusters + 1, 'Д').join();
      final filter = _filter(input);

      expect(filter.isEmpty, isFalse);
      expect(
        filter.matches(
          TagName.fromInput(
            List.filled(TagName.maxGraphemeClusters, 'д').join(),
          ),
        ),
        isFalse,
      );
    });

    test('принимает корректные surrogate pair и составные emoji', () {
      final emoji = String.fromCharCodes([0xd83d, 0xde00]);

      expect(
        _filter(emoji).matches(TagName.fromInput('Настроение $emoji')),
        isTrue,
      );
      expect(
        _filter('👩🏽‍💻').matches(TagName.fromInput('Работа 👩🏽‍💻')),
        isTrue,
      );
    });

    test('сопоставляет регистр символов за пределами BMP', () {
      expect(
        _filter('\u{10400}').matches(TagName.fromInput('Тег \u{10428}')),
        isTrue,
      );
      expect(
        _filter('\u{10428}').matches(TagName.fromInput('Тег \u{10400}')),
        isTrue,
      );
    });

    test('не исправляет NUL и непарные surrogate, а возвращает отказ', () {
      for (final invalid in [
        '\u0000',
        String.fromCharCode(0xd800),
        String.fromCharCode(0xdc00),
        String.fromCharCodes([0xdc00, 0xd800]),
      ]) {
        for (final input in [
          invalid,
          'Дом$invalid',
          '$invalid Дом',
          ' $invalid ',
        ]) {
          expect(
            TagCatalogFilter.fromInput(input),
            isA<TagCatalogFilterInvalidUnicode>(),
          );
        }
      }
    });

    test('символ замены остаётся допустимым буквальным символом', () {
      final filter = _filter('\uFFFD');

      expect(filter.matches(TagName.fromInput('Тег \uFFFD')), isTrue);
      expect(filter.matches(TagName.fromInput('Дом')), isFalse);
    });

    test('сопоставление не изменяет название тега и его ключ', () {
      final name = TagName.fromInput('Straße');
      final originalKey = name.matchingKey;
      final filter = _filter('STRASS');

      expect(filter.matches(name), isTrue);
      expect(filter.matches(name), isTrue);
      expect(name.value, 'Straße');
      expect(name.matchingKey, originalKey);
    });
  });
}

TagCatalogFilter _filter(String input) =>
    switch (TagCatalogFilter.fromInput(input)) {
      TagCatalogFilter filter => filter,
      TagCatalogFilterInvalidUnicode() => throw StateError(
        'Ожидался корректный поисковый запрос',
      ),
    };
