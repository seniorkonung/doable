import 'package:doable/src/daily_choice/application/daily_choice_catalog.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_priority.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_schedule.dart';
import 'package:doable/src/graph/application/blocking_relation_reference.dart';
import 'package:doable/src/graph/application/selected_relations.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final owner = _intentionId(1);
  final other = _intentionId(2);
  final relationId = _relationId(3);
  final choiceId = _choiceId(relationId.toCanonicalString());
  final relation = LongTermBlockingRelationReference(relationId);
  final choice = DailyChoiceBlockingRelationReference(choiceId);

  test('смешанный запрос сохраняет только явные ссылки обоих видов', () {
    final source = <BlockingRelationReference>{relation, choice};
    final query = SelectedRelationsQuery.mixed(
      intentionId: owner,
      references: source,
    );
    source.clear();

    expect(query.references, {relation, choice});
    expect(() => query.references.add(relation), throwsUnsupportedError);
    expect(query.relationIds, {relationId});
    expect(query.dailyChoiceIds, {choiceId});
  });

  test(
    'повтор одной ссылки отклоняется, совпадающие UUID разных видов допустимы',
    () {
      expect(
        () => SelectedRelationsQuery.mixed(
          intentionId: owner,
          references: [relation, LongTermBlockingRelationReference(relationId)],
        ),
        throwsA(isA<SelectedRelationsQueryValidationException>()),
      );
      expect(
        () => SelectedRelationsQuery.mixed(
          intentionId: owner,
          references: const [],
        ),
        throwsA(isA<SelectedRelationsQueryValidationException>()),
      );
    },
  );

  test('снимок отклоняет неполный набор и дневную запись чужого намерения', () {
    final query = SelectedRelationsQuery.mixed(
      intentionId: owner,
      references: [relation, choice],
    );
    expect(
      () => SelectedRelationsSnapshot.mixed(
        query: query,
        entriesByReference: {relation: SelectedRelationMissing(relationId)},
      ),
      throwsA(isA<SelectedRelationsSnapshotValidationException>()),
    );
    expect(
      () => SelectedRelationsSnapshot.mixed(
        query: query,
        entriesByReference: {
          relation: SelectedDailyChoiceMissing(choiceId),
          choice: SelectedDailyChoiceMissing(choiceId),
        },
      ),
      throwsA(isA<SelectedRelationsSnapshotValidationException>()),
    );
    expect(
      () => SelectedRelationsSnapshot.mixed(
        query: query,
        entriesByReference: {
          relation: SelectedRelationMissing(relationId),
          choice: SelectedDailyChoicePresent(
            DailyChoiceCatalogItem(
              id: choiceId,
              source: _participant(other),
              selected: _participant(_intentionId(4)),
              date: _date(),
              isCompleted: false,
              schedule: const DailyChoiceAllDay(),
              priority: DailyChoicePriority.p4,
              description: null,
              pathIntentionCount: 2,
            ),
          ),
        },
      ),
      throwsA(isA<SelectedRelationsSnapshotValidationException>()),
    );
  });

  test('дневной выбор может блокировать выбранное действие', () {
    final query = SelectedRelationsQuery.mixed(
      intentionId: owner,
      references: [choice],
    );
    final snapshot = SelectedRelationsSnapshot.mixed(
      query: query,
      entriesByReference: {
        choice: SelectedDailyChoicePresent(
          DailyChoiceCatalogItem(
            id: choiceId,
            source: _participant(other),
            selected: _participant(owner),
            date: _date(),
            isCompleted: false,
            schedule: const DailyChoiceAllDay(),
            priority: DailyChoicePriority.p4,
            description: null,
            pathIntentionCount: 2,
          ),
        ),
      },
    );

    expect(
      snapshot.entriesByReference[choice],
      isA<SelectedDailyChoicePresent>(),
    );
  });
}

IntentionId _intentionId(int suffix) => (IntentionId.decode(
  '018f0b5d-6b2e-7c80-8000-${suffix.toString().padLeft(12, '0')}',
) as IntentionIdDecodingSuccess).id;

LongTermRelationId _relationId(int suffix) => (LongTermRelationId.decode(
  '018f0b5d-6b2e-7c80-8000-${suffix.toString().padLeft(12, '0')}',
) as LongTermRelationIdDecodingSuccess).id;

DailyChoiceId _choiceId(String value) =>
    (DailyChoiceId.decode(value) as DailyChoiceIdDecodingSuccess).id;

CalendarDate _date() => CalendarDate.parseCanonical('2026-09-24');

DailyChoiceCatalogParticipant _participant(IntentionId id) =>
    DailyChoiceCatalogParticipant(
      id: id,
      title: 'Намерение',
      archiveState: IntentionArchiveState.active,
      readiness: IntentionReadiness.ready,
    );
