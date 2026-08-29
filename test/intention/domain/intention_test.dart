import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/domain/intention_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Intention createIntention({
    String title = 'Здоровье',
    String? description,
    IntentionTimestamp? createdAt,
    IntentionTimestamp? updatedAt,
  }) {
    final timestamp =
        createdAt ?? IntentionTimestamp(DateTime.utc(2026, 8, 29, 12));
    return Intention(
      id: IntentionId('0f8fad5b-d9cb-469f-a165-70867728950e'),
      title: title,
      description: description,
      readiness: IntentionReadiness.notReady,
      archiveState: IntentionArchiveState.active,
      createdAt: timestamp,
      updatedAt: updatedAt ?? timestamp,
    );
  }

  test('модель намерения неизменяема и хранит предметные типы', () {
    final id = IntentionId('0f8fad5b-d9cb-469f-a165-70867728950e');
    final createdAt = IntentionTimestamp(DateTime.utc(2026, 8, 29, 12));
    final intention = createIntention(createdAt: createdAt);

    expect(intention.id, equals(id));
    expect(intention.readiness, IntentionReadiness.notReady);
    expect(intention.archiveState, IntentionArchiveState.active);
    expect(intention.createdAt.value.isUtc, isTrue);
    expect(intention.updatedAt, createdAt);
  });

  test('нормализует заголовок и очищает полностью пробельное описание', () {
    final intention = createIntention(
      title: '  быть  здоровым  ',
      description: ' \n\t ',
    );

    expect(intention.title, 'быть  здоровым');
    expect(intention.description, isNull);
  });

  test('сохраняет непустое описание без преобразования', () {
    const description = '  Первая строка\n\nВторая строка  ';

    expect(createIntention(description: description).description, description);
  });

  test('отклоняет недопустимый текст при создании модели', () {
    expect(
      () => createIntention(title: ' \n\t '),
      throwsA(
        isA<IntentionTextValidationException>().having(
          (error) => error.failure,
          'причина',
          IntentionTextValidationFailure.emptyTitle,
        ),
      ),
    );
    expect(
      () => createIntention(description: List.filled(4097, '👩🏽‍💻').join()),
      throwsA(
        isA<IntentionTextValidationException>().having(
          (error) => error.failure,
          'причина',
          IntentionTextValidationFailure.descriptionTooLong,
        ),
      ),
    );
  });

  test('приводит timestamps к UTC и сравнивает их по моменту времени', () {
    final local = DateTime(2026, 8, 29, 15, 30);
    final timestamp = IntentionTimestamp(local);

    expect(timestamp.value, local.toUtc());
    expect(timestamp.value.isUtc, isTrue);
    expect(timestamp, IntentionTimestamp(local.toUtc()));
    expect(timestamp.hashCode, IntentionTimestamp(local.toUtc()).hashCode);
  });

  test('идентификатор имеет value equality и не допускает пустое значение', () {
    final first = IntentionId('0f8fad5b-d9cb-469f-a165-70867728950e');
    final second = IntentionId('0f8fad5b-d9cb-469f-a165-70867728950e');

    expect(first, second);
    expect(first.hashCode, second.hashCode);
    expect(first.toString(), first.value);
    expect(() => IntentionId(''), throwsArgumentError);
  });
}
