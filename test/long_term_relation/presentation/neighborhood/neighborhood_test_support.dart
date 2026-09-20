import 'dart:async';

import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';

/// Управляемый граф: каждое чтение группы завершается тестом вручную.
final class ControlledNeighborhoodRepository
    implements PersonalGraphRepository {
  final queries = <RelationGroupQuery>[];
  final _requests = <Completer<RelationGroupPageResult>>[];

  int get requestCount => queries.length;

  RelationGroupQuery queryAt(int index) => queries[index];

  void complete(int index, RelationGroupPageResult result) {
    _requests[index].complete(result);
  }

  void completePage(int index, RelationGroupPage page) {
    complete(index, GraphResultSuccess(page));
  }

  void failRead(int index, RelationGroupReadFailure failure) {
    complete(index, GraphResultFailure(failure));
  }

  void throwOnRead(int index, Object error) {
    _requests[index].completeError(error);
  }

  @override
  Future<RelationGroupPageResult> getRelationGroupPage(
    RelationGroupQuery query,
  ) {
    queries.add(query);
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
  ) => throw UnsupportedError('Отдельная сводка не читается этим тестом.');

  @override
  Stream<LongTermRelationReadResult> watchRelation(LongTermRelationId id) =>
      throw UnsupportedError('Подробные данные связи не наблюдаются здесь.');

  @override
  Stream<Result<GraphSnapshot<IntentionDetails?>>> watchIntention(
    IntentionId id,
  ) => throw UnsupportedError('Намерение не наблюдается в тесте соседства.');

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) =>
      throw UnsupportedError('Команды графа не выполняются в тесте соседства.');
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
    source: testParticipant(sourceId, title: 'Исходное $index'),
    related: testParticipant(relatedId, title: 'Связанное $index'),
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
}) => [
  for (var offset = 0; offset < count; offset += 1)
    testGroupRow(
      ownerId: ownerId,
      index: from + offset,
      type: type,
      direction: direction,
      scope: scope,
    ),
];

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
