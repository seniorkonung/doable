import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
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
        throwsA(isA<IntentionTextValidationException>()),
      );
      expect(
        () => IntentionText.normalizeTitle('\uFEFF'),
        throwsA(isA<IntentionTextValidationException>()),
      );
      expect(
        () => IntentionText.normalizeTitle(List.filled(256, '👩🏽‍💻').join()),
        throwsA(isA<IntentionTextValidationException>()),
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
        throwsA(isA<IntentionTextValidationException>()),
      );
    });
  });

  test('модель намерения неизменяема и хранит предметные типы', () {
    final id = IntentionId('0f8fad5b-d9cb-469f-a165-70867728950e');
    final createdAt = IntentionTimestamp(DateTime.utc(2026, 8, 29, 12));
    final intention = Intention(
      id: id,
      title: 'Здоровье',
      description: null,
      readiness: IntentionReadiness.notReady,
      archiveState: IntentionArchiveState.active,
      createdAt: createdAt,
      updatedAt: createdAt,
    );

    expect(intention.id, id);
    expect(intention.createdAt.value.isUtc, isTrue);
    expect(intention.updatedAt, createdAt);
  });
}
