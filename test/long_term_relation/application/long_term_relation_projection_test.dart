import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_permissions.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_description.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('прикладные проекции долговременной связи', () {
    test('неизвестное разрешение не допускает удаление или смену смысла', () {
      const permissions = LongTermRelationPermissions.unknown();
      expect(permissions.isConfirmed, isFalse);
      expect(permissions.canDelete, isFalse);
      expect(permissions.canChangeMeaning, isFalse);
      expect(permissions.canEditDescriptionAndPriority, isFalse);
    });
    test('краткие данные участника содержат активное количество', () {
      final participant = RelationParticipantSummary(
        id: _intentionId('0f8fad5b-d9cb-469f-a165-70867728950e'),
        title: 'Быть здоровым',
        archiveState: IntentionArchiveState.active,
        activeRelationCount: 3,
      );

      expect(participant.title, 'Быть здоровым');
      expect(participant.archiveState, IntentionArchiveState.active);
      expect(participant.activeRelationCount, 3);
    });

    test('краткие данные участника отклоняют отрицательное количество', () {
      expect(
        () => RelationParticipantSummary(
          id: _intentionId('0f8fad5b-d9cb-469f-a165-70867728950e'),
          title: 'Быть здоровым',
          archiveState: IntentionArchiveState.active,
          activeRelationCount: -1,
        ),
        throwsA(isA<RelationParticipantSummaryValidationException>()),
      );
    });

    test('подробная проекция намерения содержит полную сводку', () {
      final counts = _counts(activeNeedOutgoing: 2, archivedCanIncoming: 4);
      final details = IntentionDetails(
        intention: _intention(),
        relationCounts: counts,
      );

      expect(details.intention.title, 'Быть здоровым');
      expect(details.relationCounts, same(counts));
      expect(details.activeRelationCount, 2);
      expect(details.relationCounts.total, 6);
    });

    test('краткая связь передаёт только признак проверенного описания', () {
      final summary = LongTermRelationSummary(
        relation: _relation(),
        source: _participant(
          '0f8fad5b-d9cb-469f-a165-70867728950e',
          'Быть здоровым',
        ),
        related: _participant(
          '7c9e6679-7425-40de-944b-e07fc1f90ae7',
          'Много ходить',
        ),
        hasDescription: true,
      );

      expect(summary.hasDescription, isTrue);
      expect(summary.source.activeRelationCount, 1);
      expect(summary.related.activeRelationCount, 1);
    });

    test('подробная связь передаёт полный проверенный текст описания', () {
      const text = '  Пояснение\nс переносом  ';
      final description = LongTermRelationDescription.fromInput(text)!;
      final details = LongTermRelationDetails(
        relation: _relation(),
        source: _participant(
          '0f8fad5b-d9cb-469f-a165-70867728950e',
          'Быть здоровым',
        ),
        related: _participant(
          '7c9e6679-7425-40de-944b-e07fc1f90ae7',
          'Много ходить',
        ),
        description: description,
        permissions: const LongTermRelationPermissions.referencedByDailyPath(),
      );

      expect(details.description, same(description));
      expect(details.description!.value, text);
      expect(
        details.permissions.restriction,
        LongTermRelationPermissionRestriction.referencedByDailyPath,
      );
    });

    test('проекции отклоняют участников, не совпадающих со связью', () {
      expect(
        () => LongTermRelationSummary(
          relation: _relation(),
          source: _participant(
            '00000000-0000-4000-8000-000000000003',
            'Другое намерение',
          ),
          related: _participant(
            '7c9e6679-7425-40de-944b-e07fc1f90ae7',
            'Много ходить',
          ),
          hasDescription: false,
        ),
        throwsA(isA<LongTermRelationProjectionValidationException>()),
      );
    });
  });
}

RelationCounts _counts({
  int activeNeedOutgoing = 0,
  int archivedCanIncoming = 0,
}) => RelationCounts(
  activeNeedIncoming: 0,
  activeNeedOutgoing: activeNeedOutgoing,
  activeCanIncoming: 0,
  activeCanOutgoing: 0,
  archivedNeedIncoming: 0,
  archivedNeedOutgoing: 0,
  archivedCanIncoming: archivedCanIncoming,
  archivedCanOutgoing: 0,
);

RelationParticipantSummary _participant(String id, String title) =>
    RelationParticipantSummary(
      id: _intentionId(id),
      title: title,
      archiveState: IntentionArchiveState.active,
      activeRelationCount: 1,
    );

LongTermRelation _relation() => LongTermRelation(
  id: _relationId('018f0b5d-6b2e-7c80-8000-000000000001'),
  sourceIntentionId: _intentionId('0f8fad5b-d9cb-469f-a165-70867728950e'),
  relatedIntentionId: _intentionId('7c9e6679-7425-40de-944b-e07fc1f90ae7'),
  type: LongTermRelationType.need,
  priority: RelationPriority.p2,
  scope: RelationScope.active,
  creationSequence: RelationCreationSequence(1),
);

Intention _intention() => Intention(
  id: _intentionId('0f8fad5b-d9cb-469f-a165-70867728950e'),
  title: 'Быть здоровым',
  description: null,
  readiness: IntentionReadiness.notReady,
  archiveState: IntentionArchiveState.active,
  createdAt: IntentionTimestamp(DateTime.utc(2026, 9, 19)),
  updatedAt: IntentionTimestamp(DateTime.utc(2026, 9, 19)),
);

LongTermRelationId _relationId(String value) =>
    switch (LongTermRelationId.decode(value)) {
      LongTermRelationIdDecodingSuccess(:final id) => id,
      InvalidLongTermRelationIdDecoding() => throw StateError(
        'Ожидался корректный UUID связи.',
      ),
    };

IntentionId _intentionId(String value) => switch (IntentionId.decode(value)) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw StateError(
    'Ожидался корректный UUID намерения.',
  ),
};
