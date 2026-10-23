import 'package:characters/characters.dart';
import 'package:doable/src/intention/application/intention_description_preview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('начало описания намерения', () {
    test('сворачивает и обрезает ровно те кодовые единицы, что убирает trim', () {
      // `String.trim` определяет пробельные символы по кодовым единицам UTF-16,
      // поэтому перебор всех единиц полностью сверяет с ним набор свёртки.
      final mismatches = <String>[];
      for (var unit = 0; unit <= 0xFFFF; unit++) {
        final char = String.fromCharCode(unit);
        final description = '$char$charа$char$charб$char';
        final expected = char.trim().isEmpty ? 'а б' : description;

        final preview = IntentionDescriptionPreview.fromDescription(
          description,
        );

        if (preview.text != expected) {
          mismatches.add(
            'U+${unit.toRadixString(16).toUpperCase().padLeft(4, '0')}',
          );
        }
      }

      expect(mismatches, isEmpty, reason: 'Набор свёртки расходится с trim');
    });

    test('заменяет каждую серию пробельных символов одним пробелом', () {
      final preview = IntentionDescriptionPreview.fromDescription(
        'Купить\nмолоко\t\tи\u00A0хлеб\u3000к\uFEFF \r\nужину',
      );

      expect(preview.text, 'Купить молоко и хлеб к ужину');
    });

    test('оставляет 512 кластеров, не разрывая составной emoji', () {
      const family = '👨‍👩‍👧‍👦';
      final preview = IntentionDescriptionPreview.fromDescription(
        '${'а' * 511}$family${'б' * 10}',
      );

      expect(preview.text, '${'а' * 511}$family');
      expect(preview.text.characters, hasLength(512));
    });
  });
}
