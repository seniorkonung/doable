import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:drift/drift.dart' show Value;

/// Набор пересекает внутреннюю границу удаления в 400 SQL-параметров.
abstract final class LargeBlockingRelationsFixture {
  static const selectedCount = 401;

  static IntentionId participant(int index) => _intentionId(50000 + index);
  static LongTermRelationId selected(int index) => _relationId(60000 + index);
  static LongTermRelationId get unselected => _relationId(61000);
  static LongTermRelationId get unrelated => _relationId(61001);

  static List<LongTermRelationId> get selectedIds => [
    for (var index = 0; index < selectedCount; index++) selected(index),
  ];

  static Future<void> seed(AppDatabase database, IntentionId owner) =>
      database.batch((batch) {
        const timestamp = 1789862400000000;
        for (var index = 0; index <= selectedCount; index++) {
          final neighbor = participant(index);
          batch.insert(
            database.intentions,
            IntentionsCompanion.insert(
              id: neighbor.toCanonicalString(),
              title: 'Участник $index',
              createdAt: timestamp + index,
              updatedAt: timestamp + index,
            ),
          );
          batch.insert(
            database.longTermRelations,
            LongTermRelationsCompanion.insert(
              id: (index < selectedCount ? selected(index) : unselected)
                  .toCanonicalString(),
              sourceIntentionId: owner.toCanonicalString(),
              relatedIntentionId: neighbor.toCanonicalString(),
              type: 'need',
              priority: index % 4 + 1,
              description: Value('Описание $index'),
            ),
          );
        }
        batch.insert(
          database.longTermRelations,
          LongTermRelationsCompanion.insert(
            id: unrelated.toCanonicalString(),
            sourceIntentionId: participant(0).toCanonicalString(),
            relatedIntentionId: participant(1).toCanonicalString(),
            type: 'can',
            priority: 2,
          ),
        );
      });
}

String _uuid(int value) =>
    '018f0b5d-6b2e-7c80-8000-${value.toString().padLeft(12, '0')}';

IntentionId _intentionId(int value) =>
    switch (IntentionId.decode(_uuid(value))) {
      IntentionIdDecodingSuccess(:final id) => id,
      InvalidIntentionIdDecoding() => throw StateError(
        'Недопустимый ID намерения.',
      ),
    };

LongTermRelationId _relationId(int value) =>
    switch (LongTermRelationId.decode(_uuid(value))) {
      LongTermRelationIdDecodingSuccess(:final id) => id,
      InvalidLongTermRelationIdDecoding() => throw StateError(
        'Недопустимый ID связи.',
      ),
    };
