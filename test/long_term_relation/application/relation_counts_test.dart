import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('сводка количеств долговременных связей', () {
    test('вычисляет все итоги только из восьми групп', () {
      final counts = RelationCounts(
        activeNeedIncoming: 1,
        activeNeedOutgoing: 2,
        activeCanIncoming: 3,
        activeCanOutgoing: 4,
        archivedNeedIncoming: 5,
        archivedNeedOutgoing: 6,
        archivedCanIncoming: 7,
        archivedCanOutgoing: 8,
      );

      expect(counts.activeNeed, 3);
      expect(counts.activeCan, 7);
      expect(counts.archivedNeed, 11);
      expect(counts.archivedCan, 15);
      expect(counts.active, 10);
      expect(counts.archived, 26);
      expect(counts.total, 36);
    });

    test('возвращает количество каждой из восьми конкретных групп', () {
      final counts = RelationCounts(
        activeNeedIncoming: 1,
        activeNeedOutgoing: 2,
        activeCanIncoming: 3,
        activeCanOutgoing: 4,
        archivedNeedIncoming: 5,
        archivedNeedOutgoing: 6,
        archivedCanIncoming: 7,
        archivedCanOutgoing: 8,
      );

      expect(
        counts.forGroup(
          scope: RelationScope.active,
          type: LongTermRelationType.need,
          direction: RelationDirection.incoming,
        ),
        1,
      );
      expect(
        counts.forGroup(
          scope: RelationScope.active,
          type: LongTermRelationType.need,
          direction: RelationDirection.outgoing,
        ),
        2,
      );
      expect(
        counts.forGroup(
          scope: RelationScope.active,
          type: LongTermRelationType.can,
          direction: RelationDirection.incoming,
        ),
        3,
      );
      expect(
        counts.forGroup(
          scope: RelationScope.active,
          type: LongTermRelationType.can,
          direction: RelationDirection.outgoing,
        ),
        4,
      );
      expect(
        counts.forGroup(
          scope: RelationScope.archived,
          type: LongTermRelationType.need,
          direction: RelationDirection.incoming,
        ),
        5,
      );
      expect(
        counts.forGroup(
          scope: RelationScope.archived,
          type: LongTermRelationType.need,
          direction: RelationDirection.outgoing,
        ),
        6,
      );
      expect(
        counts.forGroup(
          scope: RelationScope.archived,
          type: LongTermRelationType.can,
          direction: RelationDirection.incoming,
        ),
        7,
      );
      expect(
        counts.forGroup(
          scope: RelationScope.archived,
          type: LongTermRelationType.can,
          direction: RelationDirection.outgoing,
        ),
        8,
      );
    });

    test('считает встречные связи как две отдельные группы направлений', () {
      final counts = RelationCounts(
        activeNeedIncoming: 1,
        activeNeedOutgoing: 1,
        activeCanIncoming: 0,
        activeCanOutgoing: 0,
        archivedNeedIncoming: 0,
        archivedNeedOutgoing: 0,
        archivedCanIncoming: 0,
        archivedCanOutgoing: 0,
      );

      expect(counts.activeNeed, 2);
      expect(counts.active, 2);
      expect(counts.total, 2);
    });

    test('отклоняет отрицательное значение в любой группе', () {
      for (var groupIndex = 0; groupIndex < 8; groupIndex++) {
        expect(
          () => _countsWithNegativeGroup(groupIndex),
          throwsA(isA<RelationCountsValidationException>()),
          reason: 'Группа $groupIndex должна проверяться отдельно.',
        );
      }
    });

    test('отличает неизвестную сводку от подтверждённых нулей', () {
      const unknown = UnknownRelationCounts();
      final confirmed = ConfirmedRelationCounts(
        RelationCounts(
          activeNeedIncoming: 0,
          activeNeedOutgoing: 0,
          activeCanIncoming: 0,
          activeCanOutgoing: 0,
          archivedNeedIncoming: 0,
          archivedNeedOutgoing: 0,
          archivedCanIncoming: 0,
          archivedCanOutgoing: 0,
        ),
      );

      expect(unknown, isA<RelationCountsState>());
      expect(confirmed, isA<RelationCountsState>());
      expect(confirmed.counts.total, 0);
      expect(unknown, isNot(isA<ConfirmedRelationCounts>()));
    });
  });
}

RelationCounts _countsWithNegativeGroup(int groupIndex) => RelationCounts(
  activeNeedIncoming: groupIndex == 0 ? -1 : 0,
  activeNeedOutgoing: groupIndex == 1 ? -1 : 0,
  activeCanIncoming: groupIndex == 2 ? -1 : 0,
  activeCanOutgoing: groupIndex == 3 ? -1 : 0,
  archivedNeedIncoming: groupIndex == 4 ? -1 : 0,
  archivedNeedOutgoing: groupIndex == 5 ? -1 : 0,
  archivedCanIncoming: groupIndex == 6 ? -1 : 0,
  archivedCanOutgoing: groupIndex == 7 ? -1 : 0,
);
