import 'package:doable/src/daily_choice/application/choice_path_continuations.dart';
import 'package:doable/src/daily_choice/application/choice_path_draft.dart';
import 'package:doable/src/daily_choice/application/confirmed_choice_path.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('нулевой черновик допускается, но не является подтверждаемым путём', () {
    final draft = ChoicePathDraftStart(_intention(1));
    expect(draft.steps, isEmpty);
    expect(draft.currentIntentionId, _intention(1));
    expect(draft, isNot(isA<ChoicePathDraftProgress>()));
    expect(() => ConfirmedChoicePath(draft.steps), throwsArgumentError);
  });

  test(
    'пройденный черновик копирует шаги и сохраняет подтверждённый смысл',
    () {
      final steps = [
        ConfirmedChoicePathStep(
          relationId: _relation(1),
          sourceIntentionId: _intention(1),
          type: LongTermRelationType.need,
          relatedIntentionId: _intention(2),
        ),
      ];
      final draft = ChoicePathDraftProgress(_intention(1), steps);
      steps.clear();
      expect(draft.steps, hasLength(1));
      expect(draft.currentIntentionId, _intention(2));
      expect(draft.confirmedPath.steps.single.relationId, _relation(1));
      expect(() => draft.steps.clear(), throwsUnsupportedError);
      expect(
        () => ChoicePathDraftProgress(_intention(1), const []),
        throwsArgumentError,
      );
    },
  );

  test('черновик отклоняет разрыв и повторное посещение намерения', () {
    ConfirmedChoicePathStep step(IntentionId from, IntentionId to) =>
        ConfirmedChoicePathStep(
          relationId: _relation(1),
          sourceIntentionId: from,
          type: LongTermRelationType.need,
          relatedIntentionId: to,
        );
    expect(
      () => ChoicePathDraftProgress(_intention(1), [
        step(_intention(2), _intention(3)),
      ]),
      throwsArgumentError,
    );
    expect(
      () => ChoicePathDraftProgress(_intention(1), [
        step(_intention(1), _intention(2)),
        step(_intention(2), _intention(1)),
      ]),
      throwsArgumentError,
    );
  });

  test('размер порции по умолчанию 50, допустимы границы 1 и 100', () {
    final draft = ChoicePathDraftStart(_intention(1));
    expect(ChoicePathContinuationQuery(draft: draft).pageSize, 50);
    expect(ChoicePathContinuationQuery(draft: draft, pageSize: 1).pageSize, 1);
    expect(
      ChoicePathContinuationQuery(draft: draft, pageSize: 100).pageSize,
      100,
    );
    for (final size in [0, -1, 101]) {
      expect(
        () => ChoicePathContinuationQuery(draft: draft, pageSize: size),
        throwsA(isA<ChoicePathContinuationQueryValidationException>()),
      );
    }
  });

  test('ответ сохраняет порядок групп, приоритетов и создания', () {
    final items = [
      _summary(4, LongTermRelationType.can, RelationPriority.p1, 1),
      _summary(3, LongTermRelationType.need, RelationPriority.p2, 1),
      _summary(2, LongTermRelationType.need, RelationPriority.p1, 2),
      _summary(1, LongTermRelationType.need, RelationPriority.p1, 1),
    ];
    final page = ChoicePathContinuationsPage(
      draft: ChoicePathDraftStart(_intention(1)),
      current: _current(_intention(1), IntentionReadiness.ready),
      items: items,
      nextCursor: null,
      revision: const _Revision(),
    );
    items.clear();
    expect(page.items.map((item) => item.relation.id), [
      _relation(1),
      _relation(2),
      _relation(3),
      _relation(4),
    ]);
    expect(page.canConfirm, isFalse);
    expect(() => page.items.clear(), throwsUnsupportedError);
  });

  test('завершение доступно только после перехода к действию', () {
    final draft = ChoicePathDraftProgress(_intention(1), [
      ConfirmedChoicePathStep(
        relationId: _relation(1),
        sourceIntentionId: _intention(1),
        type: LongTermRelationType.need,
        relatedIntentionId: _intention(2),
      ),
    ]);
    ChoicePathContinuationsPage page(IntentionReadiness readiness) =>
        ChoicePathContinuationsPage(
          draft: draft,
          current: _current(_intention(2), readiness),
          items: const [],
          nextCursor: null,
          revision: const _Revision(),
        );
    expect(page(IntentionReadiness.ready).canConfirm, isTrue);
    expect(page(IntentionReadiness.notReady).canConfirm, isFalse);
  });

  test('контракт различает ввод, отсутствие, конфликт и ошибки чтения', () {
    const failures = <ChoicePathContinuationFailure>[
      ChoicePathContinuationValidationFailure(),
      ChoicePathContinuationIntentionNotFoundFailure(),
      ChoicePathContinuationSnapshotExpired(),
      ChoicePathContinuationUnavailableFailure(),
      ChoicePathContinuationCorruptionFailure(),
      ChoicePathContinuationUnexpectedFailure(),
    ];
    expect(
      failures.map((failure) => failure.category).toSet(),
      GraphFailureCategory.values.toSet(),
    );
  });
}

IntentionId _intention(int value) => (IntentionId.decode(
  '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}',
) as IntentionIdDecodingSuccess).id;

LongTermRelationId _relation(int value) => (LongTermRelationId.decode(
  '00000000-0000-4000-8001-${value.toString().padLeft(12, '0')}',
) as LongTermRelationIdDecodingSuccess).id;

Intention _current(IntentionId id, IntentionReadiness readiness) => Intention(
  id: id,
  title: 'Намерение',
  description: null,
  readiness: readiness,
  archiveState: IntentionArchiveState.active,
  createdAt: IntentionTimestamp(DateTime.utc(2026)),
  updatedAt: IntentionTimestamp(DateTime.utc(2026)),
);

LongTermRelationSummary _summary(
  int id,
  LongTermRelationType type,
  RelationPriority priority,
  int sequence,
) {
  final source = RelationParticipantSummary(
    id: _intention(1),
    title: 'Исходное',
    archiveState: IntentionArchiveState.active,
    activeRelationCount: 4,
  );
  final related = RelationParticipantSummary(
    id: _intention(id + 1),
    title: 'Связанное',
    archiveState: IntentionArchiveState.active,
    activeRelationCount: 0,
  );
  return LongTermRelationSummary(
    relation: LongTermRelation(
      id: _relation(id),
      sourceIntentionId: source.id,
      relatedIntentionId: related.id,
      type: type,
      priority: priority,
      scope: RelationScope.active,
      creationSequence: RelationCreationSequence(sequence),
    ),
    source: source,
    related: related,
    hasDescription: false,
  );
}

final class _Revision implements GraphRevision {
  const _Revision();

  @override
  GraphRevisionOrder compareTo(GraphRevision other) => GraphRevisionOrder.same;
}
