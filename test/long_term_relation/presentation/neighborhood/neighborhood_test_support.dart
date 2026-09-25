import 'dart:async';

import 'package:doable/src/daily_choice/application/daily_choice_catalog.dart';
import 'package:doable/src/daily_choice/application/choice_path_continuations.dart';
import 'package:doable/src/daily_choice/application/choice_path_suggestions.dart';

import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_result.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/delete_blocking_relations.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/selected_relations.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';

import '../../../support/tag_read_contract_test_fallback.dart';

/// Управляемый граф: каждое чтение группы завершается тестом вручную.
final class ControlledNeighborhoodRepository
    with TagReadContractTestFallback
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
  ) async => _selectedSnapshot(query);

  @override
  Stream<SelectedRelationsReadResult> watchSelectedRelations(
    SelectedRelationsQuery query,
  ) => Stream.value(_selectedSnapshot(query));

  SelectedRelationsReadResult _selectedSnapshot(
    SelectedRelationsQuery query,
  ) => SelectedRelationsReadSuccess(
    GraphSnapshot(
      revision: _latestRevision ?? const TestGraphRevision(0),
      value: SelectedRelationsSnapshot(
        query: query,
        entries: {
          for (final id in query.relationIds)
            id: switch (_relationRows[id]) {
              null => SelectedRelationMissing(id),
              final row
                  when row.relation.sourceIntentionId != query.intentionId &&
                      row.relation.relatedIntentionId != query.intentionId =>
                SelectedRelationNoLongerBlocking(id),
              final row => SelectedRelationPresent(
                LongTermRelationDetails(
                  relation: row.relation,
                  source: row.source,
                  related: row.related,
                  description: null,
                ),
              ),
            },
        },
      ),
    ),
  );

  final queries = <RelationGroupQuery>[];
  final pageQueries = <RelationGroupPageQuery>[];
  final _requests = <Completer<RelationGroupPageResult>>[];
  final intentionIds = <IntentionId>[];
  final intentionCommands = <IntentionCommand>[];
  final relationCommands = <LongTermRelationCommand>[];
  final blockingCommands = <DeleteBlockingRelations>[];
  final dailyChoiceCommands = <DailyChoiceCommand>[];
  final _relationRows = <LongTermRelationId, LongTermRelationSummary>{};
  RelationCounts? _latestCounts;
  GraphRevision? _latestRevision;
  final _intentionController =
      StreamController<Result<GraphSnapshot<IntentionDetails?>>>.broadcast(
        sync: true,
      );
  final _commandRequests =
      <Completer<Result<ConfirmedGraphResult<IntentionCommandSuccess>>>>[];
  final _relationCommandRequests = <Completer<LongTermRelationCommandResult>>[];
  final _blockingRequests = <Completer<DeleteBlockingRelationsResult>>[];
  final _dailyChoiceRequests = <Completer<DailyChoiceCommandResult>>[];

  int get requestCount => _requests.length;

  RelationGroupQuery queryAt(int index) =>
      pageQueries[index] as RelationGroupQuery;

  RelationGroupPageQuery pageQueryAt(int index) => pageQueries[index];

  void complete(int index, RelationGroupPageResult result) {
    _requests[index].complete(result);
  }

  void completePage(int index, RelationGroupPage page) {
    final rows = switch (page) {
      RelationGroupFirstPage(:final items) ||
      RelationGroupContinuationPage(:final items) => items,
      DailyChoiceGroupFirstPage() ||
      DailyChoiceGroupContinuationPage() => <LongTermRelationSummary>[],
    };
    for (final row in rows) {
      _relationRows[row.relation.id] = row;
    }
    if (page is RelationGroupFirstPage || page is DailyChoiceGroupFirstPage) {
      _latestCounts = switch (page) {
        RelationGroupFirstPage(:final counts) ||
        DailyChoiceGroupFirstPage(:final counts) => counts,
        _ => throw StateError('Ожидалась первая порция.'),
      };
      _latestRevision = page.revision;
    }
    complete(index, GraphResultSuccess(page));
  }

  void failRead(int index, RelationGroupReadFailure failure) {
    complete(index, GraphResultFailure(failure));
  }

  void throwOnRead(int index, Object error) {
    _requests[index].completeError(error);
  }

  void emitIntention(
    Intention intention, {
    required RelationCounts counts,
    required GraphRevision revision,
  }) {
    _intentionController.add(
      ResultSuccess(
        GraphSnapshot(
          value: IntentionDetails(intention: intention, relationCounts: counts),
          revision: revision,
        ),
      ),
    );
  }

  void emitIntentionNotFound({required GraphRevision revision}) {
    _intentionController.add(
      ResultSuccess(GraphSnapshot(value: null, revision: revision)),
    );
  }

  void failIntentionRead(IntentionFailure failure) {
    _intentionController.add(ResultFailure(failure));
  }

  void completeIntentionCommand(
    int index,
    Result<IntentionCommandSuccess> result,
  ) {
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

  void completeRelationCommand(
    int index,
    LongTermRelationCommandResult result,
  ) {
    _relationCommandRequests[index].complete(result);
  }

  void completeBlockingCommand(
    int index,
    DeleteBlockingRelationsResult result,
  ) {
    _blockingRequests[index].complete(result);
  }

  void completeDailyChoiceCommand(int index, DailyChoiceCommandResult result) {
    _dailyChoiceRequests[index].complete(result);
  }

  @override
  Future<DailyChoiceCatalogPageResult> getDailyChoiceCatalogPage(
    DailyChoiceCatalogQuery query,
  ) => throw UnsupportedError(
    'Каталог дневных выборов не используется в этом тесте.',
  );

  @override
  Future<RelationGroupPageResult> getRelationGroupPage(
    RelationGroupPageQuery query,
  ) {
    pageQueries.add(query);
    if (query is RelationGroupQuery) queries.add(query);
    final request = Completer<RelationGroupPageResult>();
    _requests.add(request);
    return request.future;
  }

  @override
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  ) => throw UnsupportedError('Каталог не используется в тесте соседства.');

  @override
  Future<Result<GraphSnapshot<RelationCounts>>> getRelationCounts(
    IntentionId intentionId,
  ) async => switch ((_latestCounts, _latestRevision)) {
    (final RelationCounts counts, final GraphRevision revision) =>
      ResultSuccess(GraphSnapshot(value: counts, revision: revision)),
    _ => const ResultFailure(IntentionUnexpectedFailure()),
  };

  @override
  Stream<LongTermRelationReadResult> watchRelation(LongTermRelationId id) =>
      Stream.value(
        LongTermRelationReadSuccess(
          GraphSnapshot(
            value: switch (_relationRows[id]) {
              null => null,
              final row => LongTermRelationDetails(
                relation: row.relation,
                source: row.source,
                related: row.related,
                description: null,
              ),
            },
            revision: _latestRevision ?? const TestGraphRevision(0),
          ),
        ),
      );

  @override
  Stream<Result<GraphSnapshot<IntentionDetails?>>> watchIntention(
    IntentionId id,
  ) {
    intentionIds.add(id);
    return _intentionController.stream;
  }

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    final result = switch (command) {
      final IntentionCommand intentionCommand => await _executeIntention(
        intentionCommand,
      ),
      final LongTermRelationCommand relationCommand =>
        await _executeLongTermRelation(relationCommand),
      final DeleteBlockingRelations blockingCommand =>
        await _executeBlockingRelationsDelete(blockingCommand),
      final DailyChoiceCommand choiceCommand => await _executeDailyChoice(
        choiceCommand,
      ),
      _ => throw UnsupportedError('Неизвестная команда графа в тесте.'),
    };
    return result as GraphCommandResult<TSuccess, TFailure>;
  }

  Future<Result<ConfirmedGraphResult<IntentionCommandSuccess>>>
  _executeIntention(IntentionCommand command) {
    intentionCommands.add(command);
    final request =
        Completer<Result<ConfirmedGraphResult<IntentionCommandSuccess>>>();
    _commandRequests.add(request);
    return request.future;
  }

  Future<LongTermRelationCommandResult> _executeLongTermRelation(
    LongTermRelationCommand command,
  ) {
    relationCommands.add(command);
    final request = Completer<LongTermRelationCommandResult>();
    _relationCommandRequests.add(request);
    return request.future;
  }

  Future<DeleteBlockingRelationsResult> _executeBlockingRelationsDelete(
    DeleteBlockingRelations command,
  ) {
    blockingCommands.add(command);
    final request = Completer<DeleteBlockingRelationsResult>();
    _blockingRequests.add(request);
    return request.future;
  }

  Future<DailyChoiceCommandResult> _executeDailyChoice(
    DailyChoiceCommand command,
  ) {
    dailyChoiceCommands.add(command);
    final request = Completer<DailyChoiceCommandResult>();
    _dailyChoiceRequests.add(request);
    return request.future;
  }

  Future<void> dispose() => _intentionController.close();
}

final class TestGraphRevision implements GraphRevision {
  const TestGraphRevision(this.sequence, {this.epoch = 0});

  final int sequence;
  final int epoch;

  @override
  GraphRevisionOrder compareTo(GraphRevision other) {
    if (other is! TestGraphRevision || epoch != other.epoch) {
      return GraphRevisionOrder.differentEpoch;
    }
    final comparison = sequence.compareTo(other.sequence);
    if (comparison < 0) return GraphRevisionOrder.older;
    if (comparison > 0) return GraphRevisionOrder.newer;
    return GraphRevisionOrder.same;
  }
}

final class TestRelationGroupCursor implements RelationGroupCursor {
  const TestRelationGroupCursor(this.offset);

  final int offset;
}

IntentionId testIntentionId(int index) {
  final encoded =
      '018f0000-0000-7000-8000-${index.toString().padLeft(12, '0')}';
  return switch (IntentionId.decode(encoded)) {
    IntentionIdDecodingSuccess(:final id) => id,
    InvalidIntentionIdDecoding() => throw StateError(
      'Некорректный fixture ID намерения.',
    ),
  };
}

LongTermRelationId testRelationId(int index) {
  final encoded =
      '018f0001-0000-7000-8000-${index.toString().padLeft(12, '0')}';
  return switch (LongTermRelationId.decode(encoded)) {
    LongTermRelationIdDecodingSuccess(:final id) => id,
    InvalidLongTermRelationIdDecoding() => throw StateError(
      'Некорректный fixture ID связи.',
    ),
  };
}

RelationParticipantSummary testParticipant(
  IntentionId id, {
  String title = 'Намерение',
  IntentionArchiveState archiveState = IntentionArchiveState.active,
  int activeRelationCount = 0,
}) => RelationParticipantSummary(
  id: id,
  title: title,
  archiveState: archiveState,
  activeRelationCount: activeRelationCount,
);

/// Строка выбранной группы намерения-владельца.
LongTermRelationSummary testGroupRow({
  required IntentionId ownerId,
  required int index,
  LongTermRelationType type = LongTermRelationType.need,
  RelationDirection direction = RelationDirection.outgoing,
  RelationScope scope = RelationScope.active,
  RelationPriority priority = RelationPriority.p2,
  String ownerTitle = 'Намерение-владелец',
  String? neighborTitle,
  int neighborActiveRelationCount = 0,
}) {
  final neighborId = testIntentionId(1000 + index);
  final isOutgoing = direction == RelationDirection.outgoing;
  final sourceId = isOutgoing ? ownerId : neighborId;
  final relatedId = isOutgoing ? neighborId : ownerId;
  return LongTermRelationSummary(
    relation: LongTermRelation(
      id: testRelationId(index),
      sourceIntentionId: sourceId,
      relatedIntentionId: relatedId,
      type: type,
      priority: priority,
      scope: scope,
      creationSequence: RelationCreationSequence(index),
    ),
    source: testParticipant(
      sourceId,
      title: isOutgoing ? ownerTitle : neighborTitle ?? 'Исходное $index',
      activeRelationCount: isOutgoing ? 0 : neighborActiveRelationCount,
    ),
    related: testParticipant(
      relatedId,
      title: isOutgoing ? neighborTitle ?? 'Связанное $index' : ownerTitle,
      activeRelationCount: isOutgoing ? neighborActiveRelationCount : 0,
    ),
    hasDescription: false,
  );
}

List<LongTermRelationSummary> testGroupRows({
  required IntentionId ownerId,
  required int from,
  required int count,
  LongTermRelationType type = LongTermRelationType.need,
  RelationDirection direction = RelationDirection.outgoing,
  RelationScope scope = RelationScope.active,
  String ownerTitle = 'Намерение-владелец',
  Map<int, String> neighborTitles = const {},
  Map<int, int> neighborActiveRelationCounts = const {},
}) => [
  for (var offset = 0; offset < count; offset += 1)
    testGroupRow(
      ownerId: ownerId,
      index: from + offset,
      type: type,
      direction: direction,
      scope: scope,
      ownerTitle: ownerTitle,
      neighborTitle: neighborTitles[from + offset],
      neighborActiveRelationCount:
          neighborActiveRelationCounts[from + offset] ?? 0,
    ),
];

Intention testNeighborhoodIntention({
  required IntentionId id,
  String title = 'Намерение',
  IntentionArchiveState archiveState = IntentionArchiveState.active,
}) {
  final timestamp = IntentionTimestamp(DateTime.utc(2026, 9, 20));
  return Intention(
    id: id,
    title: title,
    description: null,
    readiness: IntentionReadiness.notReady,
    archiveState: archiveState,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

Result<IntentionCommandSuccess> testNeighborhoodSavedResult({
  required Intention before,
  required Intention after,
  required GraphRevision revision,
  Iterable<IntentionCatalogMutation> additionalCatalogMutations = const [],
  Iterable<GraphChange> additionalChanges = const [],
}) => ResultSuccess(
  IntentionSaved(
    after,
    catalogMutation: IntentionCatalogUpdated(
      revision: revision,
      before: _NeighborhoodCatalogEntrySnapshot(before),
      after: _NeighborhoodCatalogEntrySnapshot(after),
    ),
    additionalCatalogMutations: additionalCatalogMutations,
    additionalChanges: additionalChanges,
  ),
);

IntentionCatalogUpdated testNeighborhoodCatalogUpdated({
  required Intention before,
  required Intention after,
  required GraphRevision revision,
}) => IntentionCatalogUpdated(
  revision: revision,
  before: _NeighborhoodCatalogEntrySnapshot(before),
  after: _NeighborhoodCatalogEntrySnapshot(after),
);

final class _NeighborhoodCatalogEntrySnapshot
    implements IntentionCatalogEntrySnapshot {
  _NeighborhoodCatalogEntrySnapshot(Intention intention)
    : summary = IntentionSummary(
        id: intention.id,
        title: intention.title,
        hasDescription: intention.description != null,
        readiness: intention.readiness,
        archiveState: intention.archiveState,
        activeRelationCount: 0,
        createdAt: intention.createdAt,
        updatedAt: intention.updatedAt,
      );

  @override
  final IntentionSummary summary;

  @override
  bool matches(IntentionCatalogQuery query) => query.includes(summary);
}

RelationCounts testRelationCounts({
  int activeNeedIncoming = 0,
  int activeNeedOutgoing = 0,
  int activeCanIncoming = 0,
  int activeCanOutgoing = 0,
  int archivedNeedIncoming = 0,
  int archivedNeedOutgoing = 0,
  int archivedCanIncoming = 0,
  int archivedCanOutgoing = 0,
  int dailySource = 0,
  int dailySelected = 0,
}) => RelationCounts(
  activeNeedIncoming: activeNeedIncoming,
  activeNeedOutgoing: activeNeedOutgoing,
  activeCanIncoming: activeCanIncoming,
  activeCanOutgoing: activeCanOutgoing,
  archivedNeedIncoming: archivedNeedIncoming,
  archivedNeedOutgoing: archivedNeedOutgoing,
  archivedCanIncoming: archivedCanIncoming,
  archivedCanOutgoing: archivedCanOutgoing,
  dailySource: dailySource,
  dailySelected: dailySelected,
);

/// Сводка, в которой заполнена только выбранная группа.
RelationCounts testCountsForGroup({
  required int count,
  LongTermRelationType type = LongTermRelationType.need,
  RelationDirection direction = RelationDirection.outgoing,
  RelationScope scope = RelationScope.active,
}) {
  final isActive = scope == RelationScope.active;
  final isNeed = type == LongTermRelationType.need;
  final isIncoming = direction == RelationDirection.incoming;
  return testRelationCounts(
    activeNeedIncoming: isActive && isNeed && isIncoming ? count : 0,
    activeNeedOutgoing: isActive && isNeed && !isIncoming ? count : 0,
    activeCanIncoming: isActive && !isNeed && isIncoming ? count : 0,
    activeCanOutgoing: isActive && !isNeed && !isIncoming ? count : 0,
    archivedNeedIncoming: !isActive && isNeed && isIncoming ? count : 0,
    archivedNeedOutgoing: !isActive && isNeed && !isIncoming ? count : 0,
    archivedCanIncoming: !isActive && !isNeed && isIncoming ? count : 0,
    archivedCanOutgoing: !isActive && !isNeed && !isIncoming ? count : 0,
  );
}
