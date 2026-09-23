import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RelationGroupQuery', () {
    test('принимает граничные размеры ограниченной порции', () {
      for (final pageSize in [1, 100]) {
        final query = RelationGroupQuery(
          intentionId: _intentionId,
          type: LongTermRelationType.need,
          direction: RelationDirection.outgoing,
          scope: RelationScope.active,
          pageSize: pageSize,
        );

        expect(query.intentionId, _intentionId);
        expect(query.type, LongTermRelationType.need);
        expect(query.direction, RelationDirection.outgoing);
        expect(query.scope, RelationScope.active);
        expect(query.pageSize, pageSize);
        expect(query.cursor, isNull);
      }
    });

    test('отклоняет размеры за пределами 1–100', () {
      for (final pageSize in [0, 101]) {
        expect(
          () => RelationGroupQuery(
            intentionId: _intentionId,
            type: LongTermRelationType.can,
            direction: RelationDirection.incoming,
            scope: RelationScope.archived,
            pageSize: pageSize,
          ),
          throwsA(
            isA<RelationGroupQueryValidationException>().having(
              (error) => error.failure,
              'failure',
              RelationGroupQueryValidationFailure.pageSizeOutOfRange,
            ),
          ),
        );
      }
    });

    test('сохраняет непрозрачное продолжение без раскрытия его данных', () {
      const cursor = _TestRelationGroupCursor();

      final query = RelationGroupQuery(
        intentionId: _intentionId,
        type: LongTermRelationType.can,
        direction: RelationDirection.incoming,
        scope: RelationScope.archived,
        pageSize: 25,
        cursor: cursor,
      );

      expect(query.cursor, same(cursor));
    });
  });
}

final IntentionId _intentionId = switch (IntentionId.decode(
  '018f0b5d-6b2e-7c80-8000-000000000001',
)) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw StateError('Некорректная фикстура.'),
};

final class _TestRelationGroupCursor implements RelationGroupCursor {
  const _TestRelationGroupCursor();
}
