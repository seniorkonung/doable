import 'package:doable/src/daily_choice/application/choice_path_suggestions.dart';
import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/choice_path_step_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('запрос различает исходное намерение и выбранное действие', () {
    final top = ChoicePathSuggestionsForSource(_intention(1));
    final bottom = ChoicePathSuggestionsForAction(_intention(3));
    expect(top.participantId, _intention(1));
    expect(bottom.participantId, _intention(3));
    expect(top, isA<ChoicePathSuggestionsForSource>());
    expect(bottom, isA<ChoicePathSuggestionsForAction>());
  });

  test('допустимая подсказка содержит текущий полный путь и предложение', () {
    final details = _details();
    final suggestion = ChoicePathSuggestion.fromDetails(details);
    expect(suggestion, isA<AvailableChoicePathSuggestion>());
    expect(suggestion.originChoiceId, details.choice.id);
    expect(suggestion.source.id, _intention(1));
    expect(suggestion.action.id, _intention(3));
    expect(suggestion.path.map((step) => step.relation.id), [
      _relation(1),
      _relation(2),
    ]);
    final available = suggestion as AvailableChoicePathSuggestion;
    expect(available.confirmedPath.steps.map((step) => step.relationId), [
      _relation(1),
      _relation(2),
    ]);
    expect(available.confirmedPath.steps.last.type, LongTermRelationType.can);
  });

  test('архивный маршрут и утрата готовности не дают подтверждаемого пути', () {
    final archived = ChoicePathSuggestion.fromDetails(
      _details(archivedRelation: true),
    );
    final notReady = ChoicePathSuggestion.fromDetails(
      _details(actionReady: false),
    );
    expect(archived, isA<UnavailableChoicePathSuggestion>());
    expect(
      (archived as UnavailableChoicePathSuggestion).reason,
      ChoicePathSuggestionUnavailableReason.archivedRelation,
    );
    expect(notReady, isA<UnavailableChoicePathSuggestion>());
    expect(
      (notReady as UnavailableChoicePathSuggestion).reason,
      ChoicePathSuggestionUnavailableReason.actionNotReady,
    );
    expect(archived.path, hasLength(2));
  });

  test('повреждённый путь отклоняет весь результат, а не одну подсказку', () {
    final broken = _details();
    final wrongStep = DailyChoicePathStepDetails(
      step: broken.path.last.step,
      relation: broken.path.last.relation,
      description: null,
      source: broken.source,
      related: broken.selected,
    );
    expect(
      () => ChoicePathSuggestion.fromDetails(
        DailyChoiceDetails(
          choice: broken.choice,
          source: broken.source,
          selected: broken.selected,
          path: [broken.path.first, wrongStep],
        ),
      ),
      throwsA(isA<ChoicePathSuggestionCorruptionException>()),
    );
    expect(
      const ChoicePathSuggestionsCorruptionFailure().category,
      GraphFailureCategory.corruption,
    );
  });

  test('снимок копирует подсказки, ограничивает их и проверяет вход', () {
    final one = ChoicePathSuggestion.fromDetails(
      _details(),
    ) as AvailableChoicePathSuggestion;
    final input = [one];
    final snapshot = ChoicePathSuggestionsSnapshot(
      query: ChoicePathSuggestionsForSource(_intention(1)),
      items: input,
      revision: const _Revision(),
    );
    input.clear();
    expect(snapshot.items, [one]);
    expect(() => snapshot.items.clear(), throwsUnsupportedError);
    expect(snapshot.revision, isA<GraphRevision>());
    expect(
      ChoicePathSuggestionsSnapshot(
        query: ChoicePathSuggestionsForAction(_intention(3)),
        items: [one],
        revision: const _Revision(),
      ).items,
      [one],
    );
    expect(
      () => ChoicePathSuggestionsSnapshot(
        query: ChoicePathSuggestionsForAction(_intention(1)),
        items: [one],
        revision: const _Revision(),
      ),
      throwsArgumentError,
    );
    expect(
      () => ChoicePathSuggestionsSnapshot(
        query: ChoicePathSuggestionsForSource(_intention(1)),
        items: [
          one,
          ChoicePathSuggestion.fromDetails(_details(choiceNumber: 2))
              as AvailableChoicePathSuggestion,
        ],
        revision: const _Revision(),
      ),
      throwsArgumentError,
    );
    expect(
      () => ChoicePathSuggestionsSnapshot(
        query: ChoicePathSuggestionsForSource(_intention(1)),
        items: [
          for (var number = 1; number <= 6; number++)
            ChoicePathSuggestion.fromDetails(
              _details(choiceNumber: number, firstRelation: number * 2),
            ) as AvailableChoicePathSuggestion,
        ],
        revision: const _Revision(),
      ),
      throwsArgumentError,
    );
  });

  test('пустой ответ, отсутствие участника и отказы различимы', () {
    final empty = ChoicePathSuggestionsSnapshot(
      query: ChoicePathSuggestionsForSource(_intention(1)),
      items: const [],
      revision: const _Revision(),
    );
    expect(empty.items, isEmpty);
    expect(
      const ChoicePathSuggestionsIntentionNotFoundFailure().category,
      GraphFailureCategory.notFound,
    );
    expect(
      const ChoicePathSuggestionsUnavailableFailure().category,
      GraphFailureCategory.unavailable,
    );
    expect(
      const ChoicePathSuggestionsUnexpectedFailure().category,
      GraphFailureCategory.unexpected,
    );
  });
}

DailyChoiceDetails _details({
  bool archivedRelation = false,
  bool actionReady = true,
  int choiceNumber = 1,
  int firstRelation = 1,
}) {
  final source = _node(1);
  final middle = _node(2);
  final action = _node(
    3,
    readiness: actionReady
        ? IntentionReadiness.ready
        : IntentionReadiness.notReady,
  );
  final choiceId = _choice(choiceNumber);
  final firstStepId = _step(firstRelation);
  DailyChoicePathStepDetails pathStep(
    int number,
    Intention from,
    Intention to,
    ChoicePathStepId? previous,
    LongTermRelationType type,
    RelationScope scope,
  ) => DailyChoicePathStepDetails(
    step: ChoicePathStep(
      id: _step(number),
      dailyChoiceId: choiceId,
      relationId: _relation(number),
      previousStepId: previous,
    ),
    relation: LongTermRelation(
      id: _relation(number),
      sourceIntentionId: from.id,
      relatedIntentionId: to.id,
      type: type,
      priority: RelationPriority.p1,
      scope: scope,
      creationSequence: RelationCreationSequence(number),
    ),
    description: null,
    source: from,
    related: to,
  );
  return DailyChoiceDetails(
    choice: DailyChoice(
      id: choiceId,
      sourceIntentionId: source.id,
      selectedIntentionId: action.id,
      date: CalendarDate.fromParts(2026, 9, 25),
      description: null,
      isCompleted: true,
    ),
    source: source,
    selected: action,
    path: [
      pathStep(
        firstRelation,
        source,
        middle,
        null,
        LongTermRelationType.need,
        archivedRelation ? RelationScope.archived : RelationScope.active,
      ),
      pathStep(
        firstRelation + 1,
        middle,
        action,
        firstStepId,
        LongTermRelationType.can,
        RelationScope.active,
      ),
    ],
  );
}

Intention _node(
  int value, {
  IntentionReadiness readiness = IntentionReadiness.notReady,
}) => Intention(
  id: _intention(value),
  title: 'Намерение $value',
  description: null,
  readiness: readiness,
  archiveState: IntentionArchiveState.active,
  createdAt: IntentionTimestamp(DateTime.utc(2026)),
  updatedAt: IntentionTimestamp(DateTime.utc(2026)),
);

IntentionId _intention(int value) => (IntentionId.decode(
  '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}',
) as IntentionIdDecodingSuccess).id;
DailyChoiceId _choice(int value) => (DailyChoiceId.decode(
  '00000000-0000-4000-8002-${value.toString().padLeft(12, '0')}',
) as DailyChoiceIdDecodingSuccess).id;
ChoicePathStepId _step(int value) => (ChoicePathStepId.decode(
  '00000000-0000-4000-8003-${value.toString().padLeft(12, '0')}',
) as ChoicePathStepIdDecodingSuccess).id;
LongTermRelationId _relation(int value) => (LongTermRelationId.decode(
  '00000000-0000-4000-8001-${value.toString().padLeft(12, '0')}',
) as LongTermRelationIdDecodingSuccess).id;

final class _Revision implements GraphRevision {
  const _Revision();

  @override
  GraphRevisionOrder compareTo(GraphRevision other) => GraphRevisionOrder.same;
}
