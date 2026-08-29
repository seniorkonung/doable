import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
