import 'package:characters/characters.dart';
import 'package:doable/src/intention/application/intention_description_preview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('начало описания намерения', () {
    test('заменяет каждую серию пробельных символов одним пробелом', () {
      final preview = IntentionDescriptionPreview.fromDescription(
        'Купить\nмолоко\t\tи хлеб　к﻿ \r\nужину',
      );

      expect(preview.text, 'Купить молоко и хлеб к ужину');
    });

    test('обрезает пробельные символы по краям', () {
      final preview = IntentionDescriptionPreview.fromDescription(
        '　 \n Купить молоко \t﻿',
      );

      expect(preview.text, 'Купить молоко');
    });

    test('оставляет 512 кластеров, не разрывая составной emoji', () {
      const family = '👨‍👩‍👧‍👦';
      final preview = IntentionDescriptionPreview.fromDescription(
        '${'а' * 511}$family${'б' * 10}',
      );

      expect(preview.text, '${'а' * 511}$family');
      expect(preview.text.characters, hasLength(512));
    });

    test('у описания с краевыми пробелами и переносами начало непусто', () {
      final preview = IntentionDescriptionPreview.fromDescription(
        '\n\n   я\n\n   ',
      );

      expect(preview.text, 'я');
    });
  });
}
