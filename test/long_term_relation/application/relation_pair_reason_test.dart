import 'package:doable/src/long_term_relation/application/intention_relation_group.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/relation_pair_probe.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../intention/presentation/catalog/catalog_test_support.dart';

void main() {
  final intention = testSummary(index: 9).id;
  final relation = testRelation(
    sourceIntentionId: intention,
    relatedIntentionId: testSummary(index: 1).id,
  );

  test(
    'проба исключает намерение страницы и выбирает роль по направлению группы',
    () {
      for (final group in IntentionRelationGroup.values) {
        final probe = RelationPairProbe.forGroup(
          intentionId: intention,
          group: group,
        );
        expect(probe.counterpartId, intention);
        expect(
          probe.candidateRole,
          group.direction == RelationDirection.outgoing
              ? RelationParticipantRole.related
              : RelationParticipantRole.source,
        );
      }
    },
  );

  test('причина учитывает тип, направление группы и архив связи', () {
    for (final group in IntentionRelationGroup.values) {
      for (final type in LongTermRelationType.values) {
        for (final scope in RelationScope.values) {
          final occupant = PairOccupant(
            relationId: relation.id,
            type: type,
            scope: scope,
          );
          final reason = RelationPairReason.from(
            group: group,
            occupant: occupant,
          );
          if (type == group.type) {
            expect(reason, isA<RelationPairSameGroup>());
            expect((reason as RelationPairSameGroup).scope, scope);
          } else {
            expect(reason, isA<RelationPairOtherGroup>());
            final other = reason as RelationPairOtherGroup;
            expect(other.group.type, type);
            expect(other.group.direction, group.direction);
            expect(other.scope, scope);
          }
        }
      }
    }
  });
}
