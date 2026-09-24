import 'package:doable/src/daily_choice/application/daily_choice_catalog.dart';
import 'package:doable/src/graph/application/selected_relations.dart';

import 'dart:async';

import 'package:doable/src/daily_choice/application/choice_path_continuations.dart';
import 'package:doable/src/daily_choice/application/choice_path_suggestions.dart';

import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_permissions.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_description.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';

/// Граф, в котором тест сам решает исход каждой команды сохранения связи.
///
/// Чтения здесь недоступны намеренно: черновик формы не должен заводить
/// собственного источника данных графа.
final class ControlledRelationEditorRepository
    implements PersonalGraphRepository {
  @override
  Future<ChoicePathSuggestionsResult> getChoicePathSuggestions(
    ChoicePathSuggestionsQuery query,
  ) => throw UnimplementedError();

  @override
  Future<ChoicePathContinuationResult> getChoicePathContinuations(
    ChoicePathContinuationQuery query,
  ) => throw UnimplementedError();

  @override
  Future<DailyChoiceReadResult> getDailyChoice(DailyChoiceId id) =>
      throw UnsupportedError(
        'Чтение дневного выбора не используется этим тестом.',
      );

  @override
  Stream<DailyChoiceReadResult> watchDailyChoice(DailyChoiceId id) =>
      throw UnsupportedError(
        'Наблюдение дневного выбора не используется этим тестом.',
      );

  @override
  Future<SelectedRelationsReadResult> getSelectedRelations(
    SelectedRelationsQuery query,
  ) => throw UnsupportedError(
    'Чтение выбранных связей не используется в этом тесте.',
  );

  @override
  Stream<SelectedRelationsReadResult> watchSelectedRelations(
    SelectedRelationsQuery query,
  ) => throw UnsupportedError(
    'Наблюдение выбранных связей не используется в этом тесте.',
  );

  final relationCommands = <LongTermRelationCommand>[];
  final _relationRequests = <Completer<LongTermRelationCommandResult>>[];

  int get commandCount => relationCommands.length;

  CreateLongTermRelation createCommandAt(int index) =>
      relationCommands[index] as CreateLongTermRelation;

  UpdateLongTermRelation updateCommandAt(int index) =>
      relationCommands[index] as UpdateLongTermRelation;

  void completeRelationCommand(
    int index,
    LongTermRelationCommandResult result,
  ) {
    _relationRequests[index].complete(result);
  }

  void failRelationCommand(int index, LongTermRelationCommandFailure failure) {
    completeRelationCommand(index, GraphCommandFailed(failure));
  }

  /// Подтверждает создание связи по отправленной команде того же индекса.
  LongTermRelation completeRelationCreated(
    int index, {
    LongTermRelationId? relationId,
    int revision = 1,
  }) {
    final command = createCommandAt(index);
    final graphRevision = TestRelationEditorRevision(revision);
    final relation = LongTermRelation(
      id: relationId ?? testRelationId(1),
      sourceIntentionId: command.sourceIntentionId,
      relatedIntentionId: command.relatedIntentionId,
      type: command.type,
      priority: command.priority,
      scope: RelationScope.active,
      creationSequence: RelationCreationSequence(1),
    );
    completeRelationCommand(
      index,
      GraphCommandSucceeded(
        ConfirmedGraphResult(
          revision: graphRevision,
          value: LongTermRelationCreated(
            relation: relation,
            description: command.description,
            changes: <GraphChange>[
              LongTermRelationCreatedChange(
                revision: graphRevision,
                relation: relation,
              ),
            ],
          ),
        ),
      ),
    );
    return relation;
  }

  void completeRelationUpdated(
    int index, {
    required LongTermRelation before,
    required LongTermRelation after,
    LongTermRelationDescription? description,
    int revision = 1,
    Iterable<GraphChange> additionalChanges = const [],
  }) {
    final graphRevision = TestRelationEditorRevision(revision);
    completeRelationCommand(
      index,
      GraphCommandSucceeded(
        ConfirmedGraphResult(
          revision: graphRevision,
          value: LongTermRelationUpdated(
            before: before,
            relation: after,
            description: description,
            changes: <GraphChange>[
              LongTermRelationUpdatedChange(
                revision: graphRevision,
                before: before,
                after: after,
              ),
              ...additionalChanges,
            ],
          ),
        ),
      ),
    );
  }

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    final result = switch (command) {
      final LongTermRelationCommand relationCommand => await _executeRelation(
        relationCommand,
      ),
      _ => throw UnsupportedError('Форма связи не отправляет других команд.'),
    };
    return result as GraphCommandResult<TSuccess, TFailure>;
  }

  Future<LongTermRelationCommandResult> _executeRelation(
    LongTermRelationCommand command,
  ) {
    relationCommands.add(command);
    final request = Completer<LongTermRelationCommandResult>();
    _relationRequests.add(request);
    return request.future;
  }

  @override
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  ) => throw UnsupportedError('Каталог читает страница выбора участника.');

  @override
  Future<Result<GraphSnapshot<RelationCounts>>> getRelationCounts(
    IntentionId intentionId,
  ) => throw UnsupportedError('Сводка не читается черновиком формы.');

  @override
  Future<DailyChoiceCatalogPageResult> getDailyChoiceCatalogPage(
    DailyChoiceCatalogQuery query,
  ) => throw UnsupportedError(
    'Каталог дневных выборов не используется в этом тесте.',
  );

  @override
  Future<RelationGroupPageResult> getRelationGroupPage(
    RelationGroupPageQuery query,
  ) => throw UnsupportedError('Группы связей не читаются черновиком формы.');

  @override
  Stream<LongTermRelationReadResult> watchRelation(LongTermRelationId id) =>
      throw UnsupportedError('Связь не наблюдается черновиком формы.');

  @override
  Stream<Result<GraphSnapshot<IntentionDetails?>>> watchIntention(
    IntentionId id,
  ) => throw UnsupportedError('Намерение не наблюдается черновиком формы.');
}

final class TestRelationEditorRevision implements GraphRevision {
  const TestRelationEditorRevision(this.sequence);

  final int sequence;

  @override
  GraphRevisionOrder compareTo(GraphRevision other) {
    if (other is! TestRelationEditorRevision) {
      return GraphRevisionOrder.differentEpoch;
    }
    final comparison = sequence.compareTo(other.sequence);
    if (comparison < 0) return GraphRevisionOrder.older;
    if (comparison > 0) return GraphRevisionOrder.newer;
    return GraphRevisionOrder.same;
  }
}

IntentionId testEditorIntentionId(int index) {
  final encoded =
      '018f1200-0000-7000-8000-${index.toString().padLeft(12, '0')}';
  return switch (IntentionId.decode(encoded)) {
    IntentionIdDecodingSuccess(:final id) => id,
    InvalidIntentionIdDecoding() => throw StateError(
      'Некорректный fixture ID намерения.',
    ),
  };
}

RelationParticipantSummary testEditorParticipant(
  int index, {
  String? title,
  IntentionArchiveState archiveState = IntentionArchiveState.active,
  int activeRelationCount = 0,
}) => RelationParticipantSummary(
  id: testEditorIntentionId(index),
  title: title ?? 'Намерение $index',
  archiveState: archiveState,
  activeRelationCount: activeRelationCount,
);

GraphSnapshot<RelationParticipantSummary> testEditorSelection(
  int index, {
  String? title,
  IntentionArchiveState archiveState = IntentionArchiveState.active,
  int activeRelationCount = 0,
  int revision = 1,
}) => GraphSnapshot(
  value: testEditorParticipant(
    index,
    title: title,
    archiveState: archiveState,
    activeRelationCount: activeRelationCount,
  ),
  revision: TestRelationEditorRevision(revision),
);

LongTermRelationDetails testEditorRelationDetails({
  LongTermRelationType type = LongTermRelationType.need,
  RelationPriority priority = RelationPriority.p2,
  RelationScope scope = RelationScope.active,
  String? description = 'Исходное описание',
  LongTermRelationPermissions permissions =
      const LongTermRelationPermissions.unrestricted(),
}) {
  final relation = LongTermRelation(
    id: testRelationId(1),
    sourceIntentionId: testEditorIntentionId(1),
    relatedIntentionId: testEditorIntentionId(2),
    type: type,
    priority: priority,
    scope: scope,
    creationSequence: RelationCreationSequence(1),
  );
  return LongTermRelationDetails(
    relation: relation,
    source: testEditorParticipant(1),
    related: testEditorParticipant(2),
    description: description == null
        ? null
        : LongTermRelationDescription.fromInput(description),
    permissions: permissions,
  );
}

LongTermRelationId testRelationId(int index) {
  final encoded =
      '018f1300-0000-7000-8000-${index.toString().padLeft(12, '0')}';
  return switch (LongTermRelationId.decode(encoded)) {
    LongTermRelationIdDecodingSuccess(:final id) => id,
    InvalidLongTermRelationIdDecoding() => throw StateError(
      'Некорректный fixture ID связи.',
    ),
  };
}
