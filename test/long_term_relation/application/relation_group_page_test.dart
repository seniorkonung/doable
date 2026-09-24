import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'закрытые группы различают восемь долговременных и две дневные роли',
    () {
      final counts = RelationCounts(
        activeNeedIncoming: 1,
        activeNeedOutgoing: 2,
        activeCanIncoming: 3,
        activeCanOutgoing: 4,
        archivedNeedIncoming: 5,
        archivedNeedOutgoing: 6,
        archivedCanIncoming: 7,
        archivedCanOutgoing: 8,
        dailySource: 9,
        dailySelected: 10,
      );
      final longTerm = LongTermRelationGroup(
        type: LongTermRelationType.need,
        direction: RelationDirection.incoming,
        scope: RelationScope.archived,
      );
      const daily = DailyChoiceRelationGroup(
        role: DailyChoiceRelationRole.source,
      );

      expect(counts.forSelection(longTerm), 5);
      expect(counts.forSelection(daily), 9);
      expect(
        counts.forSelection(
          const DailyChoiceRelationGroup(
            role: DailyChoiceRelationRole.selected,
          ),
        ),
        10,
      );
      expect(daily, isNot(isA<LongTermRelationGroup>()));
    },
  );

  test('дневной запрос и первая порция сохраняют общую ревизию и сводку', () {
    final query = DailyChoiceGroupQuery(
      intentionId: _intentionId,
      role: DailyChoiceRelationRole.selected,
      pageSize: 50,
    );
    final revision = _TestRevision();
    final counts = RelationCounts(
      activeNeedIncoming: 0,
      activeNeedOutgoing: 0,
      activeCanIncoming: 0,
      activeCanOutgoing: 0,
      archivedNeedIncoming: 0,
      archivedNeedOutgoing: 0,
      archivedCanIncoming: 0,
      archivedCanOutgoing: 0,
      dailySelected: 0,
    );
    final page = DailyChoiceGroupFirstPage(
      items: const [],
      counts: counts,
      nextCursor: null,
      revision: revision,
    );

    expect(
      query.group,
      const DailyChoiceRelationGroup(role: DailyChoiceRelationRole.selected),
    );
    expect(page.revision, same(revision));
    expect(page.counts, same(counts));
    expect(() => page.items.clear(), throwsUnsupportedError);
  });

  test('дневная группа сохраняет границы порции 1–100', () {
    for (final pageSize in [0, 101]) {
      expect(
        () => DailyChoiceGroupQuery(
          intentionId: _intentionId,
          role: DailyChoiceRelationRole.source,
          pageSize: pageSize,
        ),
        throwsA(isA<RelationGroupQueryValidationException>()),
      );
    }
  });

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

final class _TestRevision implements GraphRevision {
  @override
  GraphRevisionOrder compareTo(GraphRevision other) => identical(this, other)
      ? GraphRevisionOrder.same
      : GraphRevisionOrder.differentEpoch;
}
