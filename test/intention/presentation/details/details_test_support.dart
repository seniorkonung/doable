import 'dart:async';

import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_repository.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';

final class ControlledDetailRequest {
  ControlledDetailRequest() {
    controller = StreamController<Result<Intention?>>(
      onCancel: () {
        cancellationCount += 1;
      },
    );
  }

  late final StreamController<Result<Intention?>> controller;
  var cancellationCount = 0;

  void add(Result<Intention?> result) {
    controller.add(result);
  }

  Future<void> close() => controller.close();
}

final class ControlledDetailsRepository implements IntentionRepository {
  final detailIds = <IntentionId>[];
  final detailRequests = <ControlledDetailRequest>[];
  final catalogQueries = <IntentionCatalogQuery>[];
  final commands = <IntentionCommand>[];
  final _commandRequests = <Completer<Result<IntentionCommandSuccess>>>[];

  Result<IntentionCatalogPage>? catalogResult;
  void Function(IntentionId id)? onWatchById;

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
  Stream<Result<Intention?>> watchById(IntentionId id) {
    detailIds.add(id);
    final request = ControlledDetailRequest();
    detailRequests.add(request);
    onWatchById?.call(id);
    return request.controller.stream;
  }

  @override
  Future<Result<IntentionCommandSuccess>> execute(IntentionCommand command) {
    commands.add(command);
    final request = Completer<Result<IntentionCommandSuccess>>();
    _commandRequests.add(request);
    return request.future;
  }

  void completeCommand(int index, Result<IntentionCommandSuccess> result) {
    _commandRequests[index].complete(result);
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
}) {
  final afterSnapshot = _DetailsCatalogEntrySnapshot(intention);
  final mutation = before == null
      ? IntentionCatalogUnchanged(
          revision: const _DetailsCatalogRevision(),
          entry: afterSnapshot,
        )
      : IntentionCatalogUpdated(
          revision: const _DetailsCatalogRevision(),
          before: _DetailsCatalogEntrySnapshot(before),
          after: afterSnapshot,
        );
  return ResultSuccess(IntentionSaved(intention, catalogMutation: mutation));
}

Result<IntentionCommandSuccess> testDetailsDeletedResult(Intention intention) =>
    ResultSuccess(
      IntentionDeleted(
        intention.id,
        catalogMutation: IntentionCatalogDeleted(
          revision: const _DetailsCatalogRevision(),
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

final class _DetailsCatalogRevision implements IntentionCatalogRevision {
  const _DetailsCatalogRevision();

  @override
  IntentionCatalogRevisionOrder compareTo(IntentionCatalogRevision other) =>
      other is _DetailsCatalogRevision
      ? IntentionCatalogRevisionOrder.same
      : IntentionCatalogRevisionOrder.differentEpoch;
}
