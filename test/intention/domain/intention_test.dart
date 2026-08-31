import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('временная метка переводит локальное время в UTC без смены момента', () {
    final localTime = DateTime(2026, 8, 29, 15);

    final timestamp = IntentionTimestamp(localTime);

    expect(localTime.isUtc, isFalse);
    expect(timestamp.value.isUtc, isTrue);
    expect(
      timestamp.value.microsecondsSinceEpoch,
      localTime.microsecondsSinceEpoch,
    );
  });

  test('фабрика нормализует название и сохраняет непустое описание', () {
    final id = IntentionId('0f8fad5b-d9cb-469f-a165-70867728950e');
    final createdAt = IntentionTimestamp(DateTime.utc(2026, 8, 29, 12));
    const description = '  Первая строка\n\nВторая строка  ';
    final intention = Intention(
      id: id,
      title: '  Быть  здоровым  ',
      description: description,
      readiness: IntentionReadiness.notReady,
      archiveState: IntentionArchiveState.active,
      createdAt: createdAt,
      updatedAt: createdAt,
    );

    expect(intention.title, 'Быть  здоровым');
    expect(intention.description, description);
  });

  test('фабрика преобразует пробельное описание в отсутствие', () {
    final timestamp = IntentionTimestamp(DateTime.utc(2026, 8, 29, 12));

    final intention = Intention(
      id: IntentionId('7c9e6679-7425-40de-944b-e07fc1f90ae7'),
      title: 'Здоровье',
      description: ' \n\t ',
      readiness: IntentionReadiness.ready,
      archiveState: IntentionArchiveState.archived,
      createdAt: timestamp,
      updatedAt: timestamp,
    );

    expect(intention.description, isNull);
  });

  test('фабрика отклоняет изменение раньше создания', () {
    final createdAt = IntentionTimestamp(DateTime.utc(2026, 8, 29, 12));
    final updatedAt = IntentionTimestamp(DateTime.utc(2026, 8, 29, 11));

    expect(
      () => Intention(
        id: IntentionId('7c9e6679-7425-40de-944b-e07fc1f90ae7'),
        title: 'Здоровье',
        description: null,
        readiness: IntentionReadiness.notReady,
        archiveState: IntentionArchiveState.active,
        createdAt: createdAt,
        updatedAt: updatedAt,
      ),
      throwsA(isA<IntentionTimestampOrderException>()),
    );
  });
}
