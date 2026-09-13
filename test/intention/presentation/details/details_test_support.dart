import 'dart:async';

import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_repository.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';

final class ControlledDetailRequest {
  ControlledDetailRequest() {
    controller = StreamController<Result<GraphSnapshot<Intention?>>>(
      onCancel: () {
        cancellationCount += 1;
      },
    );
  }

  late final StreamController<Result<GraphSnapshot<Intention?>>> controller;
  var cancellationCount = 0;

  void add(
    Result<Intention?> result, {
    GraphRevision revision = const TestDetailsRevision(0),
  }) {
    final snapshotResult = switch (result) {
      ResultSuccess(:final value) => ResultSuccess<GraphSnapshot<Intention?>>(
        GraphSnapshot(value: value, revision: revision),
      ),
      ResultFailure(:final failure) => ResultFailure<GraphSnapshot<Intention?>>(
        failure,
      ),
    };
    controller.add(snapshotResult);
  }

  Future<void> close() => controller.close();
}

final class ControlledDetailsRepository implements PersonalGraphRepository {
  final detailIds = <IntentionId>[];
  final detailRequests = <ControlledDetailRequest>[];
  final catalogQueries = <IntentionCatalogQuery>[];
  final commands = <IntentionCommand>[];
  final _commandRequests =
      <Completer<Result<ConfirmedGraphResult<IntentionCommandSuccess>>>>[];

  Result<IntentionCatalogPage>? catalogResult;
  void Function(IntentionId id)? onWatchIntention;

  @override
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  ) {
    catalogQueries.add(query);
    final result = catalogResult;
    if (result == null) {
      throw StateError('Результат каталога не настроен для теста.');
    }
    return Future.value(result);
  }

  @override
  Stream<Result<GraphSnapshot<Intention?>>> watchIntention(IntentionId id) {
    detailIds.add(id);
    final request = ControlledDetailRequest();
    detailRequests.add(request);
    onWatchIntention?.call(id);
    return request.controller.stream;
  }

  @override
  Future<Result<ConfirmedGraphResult<IntentionCommandSuccess>>> execute(
    IntentionCommand command,
  ) {
    commands.add(command);
    final request =
        Completer<Result<ConfirmedGraphResult<IntentionCommandSuccess>>>();
    _commandRequests.add(request);
    return request.future;
  }

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
  IntentionReadiness readiness = IntentionReadiness.notReady,
  IntentionArchiveState archiveState = IntentionArchiveState.active,
}) {
  final id = testDetailsIntentionId(index);
  final timestamp = IntentionTimestamp(DateTime.utc(2026, 1, index));
  return Intention(
    id: id,
    title: title,
    description: description,
    readiness: readiness,
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
  hasDescription: intention.description != null,
  readiness: intention.readiness,
  archiveState: intention.archiveState,
  createdAt: intention.createdAt,
  updatedAt: intention.updatedAt,
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
}) {
  final afterSnapshot = _DetailsCatalogEntrySnapshot(intention);
  final mutation = before == null
      ? IntentionCatalogUnchanged(revision: revision, entry: afterSnapshot)
      : IntentionCatalogUpdated(
          revision: revision,
          before: _DetailsCatalogEntrySnapshot(before),
          after: afterSnapshot,
        );
  return ResultSuccess(IntentionSaved(intention, catalogMutation: mutation));
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
