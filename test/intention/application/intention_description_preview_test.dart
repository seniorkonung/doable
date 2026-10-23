import 'package:characters/characters.dart';
import 'package:doable/src/intention/application/intention_description_preview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('начало описания намерения', () {
    // Набор решения 5 дизайна: Unicode White_Space и U+FEFF.
    const whitespace = <String, String>{
      'U+0009': '\u0009',
      'U+000A': '\u000A',
      'U+000B': '\u000B',
      'U+000C': '\u000C',
      'U+000D': '\u000D',
      'U+0020': '\u0020',
      'U+0085': '\u0085',
      'U+00A0': '\u00A0',
      'U+1680': '\u1680',
      'U+2000': '\u2000',
      'U+2001': '\u2001',
      'U+2002': '\u2002',
      'U+2003': '\u2003',
      'U+2004': '\u2004',
      'U+2005': '\u2005',
      'U+2006': '\u2006',
      'U+2007': '\u2007',
      'U+2008': '\u2008',
      'U+2009': '\u2009',
      'U+200A': '\u200A',
      'U+2028': '\u2028',
      'U+2029': '\u2029',
      'U+202F': '\u202F',
      'U+205F': '\u205F',
      'U+3000': '\u3000',
      'U+FEFF': '\uFEFF',
    };

    for (final MapEntry(key: name, value: char) in whitespace.entries) {
      test('сворачивает и обрезает $name', () {
        final preview = IntentionDescriptionPreview.fromDescription(
          '$char$charКупить$char$charмолоко$char',
        );

        expect(preview.text, 'Купить молоко');
      });
    }

    test('заменяет каждую серию пробельных символов одним пробелом', () {
      final preview = IntentionDescriptionPreview.fromDescription(
        'Купить\nмолоко\t\tи\u00A0хлеб\u3000к\uFEFF \r\nужину',
      );

      expect(preview.text, 'Купить молоко и хлеб к ужину');
    });

    test('обрезает пробельные символы по краям', () {
      final preview = IntentionDescriptionPreview.fromDescription(
        '\u3000 \n Купить молоко \t\uFEFF',
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
