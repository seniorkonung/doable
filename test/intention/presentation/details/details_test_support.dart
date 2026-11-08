import 'package:doable/src/action/application/action_command.dart';
import 'package:doable/src/action/application/action_result.dart';
import 'package:doable/src/action/application/intention_actions.dart';

import 'dart:async';

import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/intention/application/cascade/intention_cascade.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/statistics/application/intention_statistics_read_contract.dart';

import '../../../support/tag_read_contract_test_fallback.dart';
import '../../../support/action_read_contract_test_fallback.dart';
import '../../../support/statistics_read_contract_test_fallback.dart';
import '../../../support/intention_description_preview.dart';
import '../../../support/intention_title_order_key.dart';
import '../../../support/intention_kind_counts.dart';
import '../../../support/intention_holding_read_contract_test_fallback.dart';
import '../../../support/intention_cascade_execution.dart';

final class ControlledDetailRequest {
  ControlledDetailRequest({bool broadcast = false}) {
    controller = broadcast
        ? StreamController<Result<GraphSnapshot<IntentionDetails?>>>.broadcast(
            onCancel: () {
              cancellationCount += 1;
            },
          )
        : StreamController<Result<GraphSnapshot<IntentionDetails?>>>(
            onCancel: () {
              cancellationCount += 1;
            },
          );
  }

  late final StreamController<Result<GraphSnapshot<IntentionDetails?>>>
  controller;
  var cancellationCount = 0;

  void add(
    Result<Intention?> result, {
    GraphRevision revision = const TestDetailsRevision(0),
    RelationCounts? relationCounts,
  }) {
    final snapshotResult = switch (result) {
      ResultSuccess(:final value) =>
        ResultSuccess<GraphSnapshot<IntentionDetails?>>(
          GraphSnapshot(
            value: value == null
                ? null
                : IntentionDetails(
                    intention: value,
                    relationCounts: relationCounts ?? testRelationCounts(),
                  ),
            revision: revision,
          ),
        ),
      ResultFailure(:final failure) =>
        ResultFailure<GraphSnapshot<IntentionDetails?>>(failure),
    };
    controller.add(snapshotResult);
  }

  Future<void> close() => controller.close();
}

final class ControlledDetailsRepository
    with
        IntentionHoldingReadContractTestFallback,
        ActionReadContractTestFallback,
        StatisticsReadContractTestFallback,
        TagReadContractTestFallback
    implements PersonalGraphRepository {
  ControlledDetailsRepository({this.shareSecondWatch = false});

  /// Страница подробностей и вкладка «Связи» наблюдают одно намерение
  /// параллельно.
  bool shareSecondWatch;

  final detailRequests = <ControlledDetailRequest>[];
  final catalogQueries = <IntentionCatalogQuery>[];
  final commands = <IntentionCommand>[];
  final relationCommands = <LongTermRelationCommand>[];
  final actionCommands = <ActionCommand>[];
  final tagCommands = <TagCommand>[];
  final _commandRequests =
      <Completer<Result<ConfirmedGraphResult<IntentionCommandSuccess>>>>[];
  final _relationCommandRequests = <Completer<LongTermRelationCommandResult>>[];
  final _actionCommandRequests = <Completer<ActionCommandResult>>[];
  final _tagCommandRequests = <Completer<TagCommandResult>>[];
  var _watchCallCount = 0;

  Result<IntentionCatalogPage>? catalogResult;
  void Function(IntentionId id)? onWatchIntention;
  Stream<LongTermRelationReadResult> Function(LongTermRelationId id)?
  onWatchRelation;

  /// Запросы порций групп связей в порядке их поступления.
  final relationGroupQueries = <RelationGroupQuery>[];

  /// Запросы порций действий намерения в порядке их поступления.
  final intentionActionsQueries = <IntentionActionsQuery>[];

  /// Запросы, читающие строки списка, а не только числа вкладки.
  Iterable<IntentionActionsQuery> get intentionActionsListQueries =>
      intentionActionsQueries.where(
        (query) => query.pageSize > IntentionActionsQuery.minPageSize,
      );

  /// Ответ на запрос порции действий; по умолчанию чтение действий
  /// отклоняется, как в графах, не читающих действия.
  IntentionActionsPageResult Function(IntentionActionsQuery query)?
  onIntentionActionsPage;

  @override
  Future<IntentionActionsPageResult> getIntentionActionsPage(
    IntentionActionsQuery query,
  ) {
    intentionActionsQueries.add(query);
    return onIntentionActionsPage == null
        ? super.getIntentionActionsPage(query)
        : Future.value(onIntentionActionsPage!(query));
  }

  final statisticsQueries = <IntentionStatisticsQuery>[];
  FutureOr<IntentionStatisticsSectionResult> Function(
    IntentionStatisticsQuery query,
  )?
  onStatisticsSection;

  @override
  Future<IntentionStatisticsSectionResult> getIntentionStatisticsSection(
    IntentionStatisticsQuery query,
  ) async {
    statisticsQueries.add(query);
    return onStatisticsSection?.call(query) ??
        super.getIntentionStatisticsSection(query);
  }

  /// Ответ на предпросмотр каскада; по умолчанию операция не затрагивает
  /// другие намерения.
  FutureOr<CascadePreviewResult> Function(
    CascadeSubject subject,
    CascadeOperation operation,
  )?
  onPreviewCascade;

  @override
  Future<CascadePreviewResult> previewCascade(
    CascadeSubject subject,
    CascadeOperation operation,
  ) async =>
      onPreviewCascade?.call(subject, operation) ??
      givenCascadePreview(subject, operation, const TestDetailsRevision(0));

  /// Ответ на запрос порции группы связей; по умолчанию группа пуста.
  RelationGroupPageResult Function(RelationGroupQuery query)?
  onRelationGroupPage;

  @override
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  ) {
    catalogQueries.add(query);
    final result = catalogResult;
    if (result == null) {
      throw StateError('Результат каталога не настроен для теста.');
    }
    return Future.value(answerCatalogQuery(query, result));
  }

  @override
  Future<RelationGroupPageResult> getRelationGroupPage(
    RelationGroupQuery query,
  ) {
    relationGroupQueries.add(query);
    final result = onRelationGroupPage?.call(query);
    return Future.value(
      result ??
          GraphResultSuccess(
            RelationGroupFirstPage(
              items: const [],
              counts: testRelationCounts(),
              nextCursor: null,
              revision: const TestDetailsRevision(0),
            ),
          ),
    );
  }

  @override
  Stream<LongTermRelationReadResult> watchRelation(LongTermRelationId id) =>
      onWatchRelation?.call(id) ??
      (throw UnsupportedError(
        'Связи не наблюдаются в тесте подробного просмотра.',
      ));

  @override
  Stream<Result<GraphSnapshot<IntentionDetails?>>> watchIntention(
    IntentionId id,
  ) {
    _watchCallCount += 1;
    if (shareSecondWatch && _watchCallCount == 2 && detailRequests.isNotEmpty) {
      return detailRequests.first.controller.stream;
    }
    final request = ControlledDetailRequest(broadcast: shareSecondWatch);
    detailRequests.add(request);
    onWatchIntention?.call(id);
    return request.controller.stream;
  }

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    final result = switch (command) {
      final IntentionCommand intention => await _executeIntention(intention),
      final LongTermRelationCommand relation => await _executeRelation(
        relation,
      ),
      final ActionCommand action => await _executeAction(action),
      final TagCommand tag => await _executeTag(tag),
      _ => throw UnsupportedError('Неизвестная команда графа в тесте.'),
    };
    return result as GraphCommandResult<TSuccess, TFailure>;
  }

  Future<LongTermRelationCommandResult> _executeRelation(
    LongTermRelationCommand command,
  ) {
    relationCommands.add(command);
    final request = Completer<LongTermRelationCommandResult>();
    _relationCommandRequests.add(request);
    return request.future;
  }

  Future<ActionCommandResult> _executeAction(ActionCommand command) {
    actionCommands.add(command);
    final request = Completer<ActionCommandResult>();
    _actionCommandRequests.add(request);
    return request.future;
  }

  void completeActionCommand(int index, ActionCommandResult result) =>
      _actionCommandRequests[index].complete(result);

  Future<TagCommandResult> _executeTag(TagCommand command) {
    tagCommands.add(command);
    final request = Completer<TagCommandResult>();
    _tagCommandRequests.add(request);
    return request.future;
  }

  void completeTagCommand(int index, TagCommandResult result) =>
      _tagCommandRequests[index].complete(result);

  void failTagCommand(int index, Object error) =>
      _tagCommandRequests[index].completeError(error);

  Future<Result<ConfirmedGraphResult<IntentionCommandSuccess>>>
  _executeIntention(IntentionCommand command) {
    commands.add(command);
    final request =
        Completer<Result<ConfirmedGraphResult<IntentionCommandSuccess>>>();
    _commandRequests.add(request);
    return request.future;
  }

  void completeRelationCommand(
    int index,
    LongTermRelationCommandResult result,
  ) => _relationCommandRequests[index].complete(result);

  void completeCommand(int index, Result<IntentionCommandSuccess> result) {
    _commandRequests[index].complete(switch (result) {
      ResultSuccess(:final value) => ResultSuccess(
        ConfirmedGraphResult(
          revision: value.catalogMutation.revision,
          value: value,
        ),
      ),
      ResultFailure(:final failure) => ResultFailure(failure),
    });
  }
}

final class TestDetailsRevision implements GraphRevision {
  const TestDetailsRevision(this.sequence, {this.epoch = 0});

  final int sequence;
  final int epoch;

  @override
  GraphRevisionOrder compareTo(GraphRevision other) {
    if (other is! TestDetailsRevision || epoch != other.epoch) {
      return GraphRevisionOrder.differentEpoch;
    }
    final comparison = sequence.compareTo(other.sequence);
    if (comparison < 0) return GraphRevisionOrder.older;
    if (comparison > 0) return GraphRevisionOrder.newer;
    return GraphRevisionOrder.same;
  }
}

Intention testDetailsIntention({
  int index = 1,
  String title = 'Намерение',
  String? description = 'Описание',
  IntentionKind kind = IntentionKind.main,
  IntentionArchiveState archiveState = IntentionArchiveState.active,
}) {
  final id = testDetailsIntentionId(index);
  final timestamp = IntentionTimestamp(DateTime.utc(2026, 1, index));
  return Intention(
    id: id,
    title: title,
    description: description,
    kind: kind,
    archiveState: archiveState,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

IntentionId testDetailsIntentionId(int index) {
  final encoded =
      '018f0000-0000-7000-8000-${index.toString().padLeft(12, '0')}';
  return switch (IntentionId.decode(encoded)) {
    IntentionIdDecodingSuccess(:final id) => id,
    InvalidIntentionIdDecoding() => throw StateError(
      'Некорректный fixture ID.',
    ),
  };
}

IntentionSummary testDetailsSummary(Intention intention) => IntentionSummary(
  id: intention.id,
  title: intention.title,
  descriptionPreview: testDescriptionPreview(intention.description),
  kind: intention.kind,
  archiveState: intention.archiveState,
  createdAt: intention.createdAt,
  updatedAt: intention.updatedAt,
  titleOrderKey: testTitleOrderKey(intention.title),
);

RelationCounts testRelationCounts({
  int activeNeedIncoming = 0,
  int activeNeedOutgoing = 0,
  int activeCanIncoming = 0,
  int activeCanOutgoing = 0,
  int archivedNeedIncoming = 0,
  int archivedNeedOutgoing = 0,
  int archivedCanIncoming = 0,
  int archivedCanOutgoing = 0,
}) => RelationCounts(
  activeNeedIncoming: activeNeedIncoming,
  activeNeedOutgoing: activeNeedOutgoing,
  activeCanIncoming: activeCanIncoming,
  activeCanOutgoing: activeCanOutgoing,
  archivedNeedIncoming: archivedNeedIncoming,
  archivedNeedOutgoing: archivedNeedOutgoing,
  archivedCanIncoming: archivedCanIncoming,
  archivedCanOutgoing: archivedCanOutgoing,
);

Future<void> waitForDetailRequests(
  ControlledDetailsRepository repository,
  int count,
) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (repository.detailRequests.length >= count) {
      return;
    }
    await Future<void>.delayed(Duration.zero);
  }
  throw StateError('Не дождались $count запросов подробных данных.');
}

Result<IntentionCommandSuccess> testDetailsSavedResult(
  Intention intention, {
  Intention? before,
  GraphRevision revision = const TestDetailsRevision(0),
  Iterable<GraphChange> additionalChanges = const [],
}) {
  final afterSnapshot = _DetailsCatalogEntrySnapshot(intention);
  final mutation = before == null
      ? IntentionCatalogUnchanged(revision: revision, entry: afterSnapshot)
      : IntentionCatalogUpdated(
          revision: revision,
          before: _DetailsCatalogEntrySnapshot(before),
          after: afterSnapshot,
        );
  return ResultSuccess(
    IntentionSaved(
      intention,
      catalogMutation: mutation,
      additionalChanges: additionalChanges,
    ),
  );
}

Result<IntentionCommandSuccess> testDetailsDeletedResult(
  Intention intention, {
  GraphRevision revision = const TestDetailsRevision(0),
}) => ResultSuccess(
  IntentionDeleted(
    intention.id,
    catalogMutation: IntentionCatalogDeleted(
      revision: revision,
      entry: _DetailsCatalogEntrySnapshot(intention),
    ),
  ),
);

final class _DetailsCatalogEntrySnapshot
    implements IntentionCatalogEntrySnapshot {
  _DetailsCatalogEntrySnapshot(Intention intention)
    : summary = testDetailsSummary(intention);

  @override
  final IntentionSummary summary;

  @override
  bool matches(IntentionCatalogQuery query) => query.includes(summary);
}

/// Строка выбранной группы связей намерения-владельца.
RelationGroupEntry testDetailsRelationRow({
  required IntentionId ownerId,
  required int index,
  LongTermRelationType type = LongTermRelationType.need,
  RelationDirection direction = RelationDirection.outgoing,
  RelationScope scope = RelationScope.active,
  IntentionId? neighborId,
  String? neighborTitle,
}) {
  neighborId ??= testDetailsIntentionId(900 + index);
  final isOutgoing = direction == RelationDirection.outgoing;
  return RelationGroupEntry(
    relation: LongTermRelation(
      id: _testDetailsRelationId(index),
      sourceIntentionId: isOutgoing ? ownerId : neighborId,
      relatedIntentionId: isOutgoing ? neighborId : ownerId,
      type: type,
      priority: RelationPriority.p2,
      scope: scope,
      creationSequence: RelationCreationSequence(index),
      createdAt: RelationTimestamp(DateTime.utc(2026)),
      updatedAt: RelationTimestamp(DateTime.utc(2026)),
    ),
    neighbor: RelationNeighbor(
      id: neighborId,
      title:
          neighborTitle ??
          (isOutgoing ? 'Связанное $index' : 'Исходное $index'),
      archiveState: IntentionArchiveState.active,
    ),
  );
}

LongTermRelationId _testDetailsRelationId(int index) {
  final encoded =
      '018f0001-0000-7000-8000-${index.toString().padLeft(12, '0')}';
  return switch (LongTermRelationId.decode(encoded)) {
    LongTermRelationIdDecodingSuccess(:final id) => id,
    InvalidLongTermRelationIdDecoding() => throw StateError(
      'Некорректный fixture ID связи.',
    ),
  };
}
