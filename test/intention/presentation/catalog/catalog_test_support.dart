import 'dart:async';

import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_repository.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';

final class ControlledCatalogRepository implements IntentionRepository {
  final queries = <IntentionCatalogQuery>[];
  final _requests = <Completer<Result<IntentionCatalogPage>>>[];
  final commands = <IntentionCommand>[];
  final _commandRequests = <Completer<Result<IntentionCommandSuccess>>>[];

  IntentionCatalogQuery queryAt(int index) => queries[index];

  void complete(int index, Result<IntentionCatalogPage> result) {
    _requests[index].complete(result);
  }

  void completeCommand(int index, Result<IntentionCommandSuccess> result) {
    _commandRequests[index].complete(result);
  }

  @override
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  ) {
    queries.add(query);
    final request = Completer<Result<IntentionCatalogPage>>();
    _requests.add(request);
    return request.future;
  }

  @override
  Future<Result<IntentionCommandSuccess>> execute(IntentionCommand command) {
    commands.add(command);
    final request = Completer<Result<IntentionCommandSuccess>>();
    _commandRequests.add(request);
    return request.future;
  }

  @override
  Stream<Result<Intention?>> watchById(IntentionId id) =>
      throw UnsupportedError('Подробное чтение не используется в тесте.');
}

final class TestCatalogCursor implements IntentionCatalogCursor {
  const TestCatalogCursor();
}

final class TestCatalogRevision implements IntentionCatalogRevision {
  const TestCatalogRevision(this.sequence);

  final int sequence;

  @override
  IntentionCatalogRevisionOrder compareTo(IntentionCatalogRevision other) {
    if (other is! TestCatalogRevision) {
      return IntentionCatalogRevisionOrder.differentEpoch;
    }
    final comparison = sequence.compareTo(other.sequence);
    if (comparison < 0) return IntentionCatalogRevisionOrder.older;
    if (comparison > 0) return IntentionCatalogRevisionOrder.newer;
    return IntentionCatalogRevisionOrder.same;
  }
}

final class TestCatalogEntrySnapshot implements IntentionCatalogEntrySnapshot {
  const TestCatalogEntrySnapshot(this.summary);

  @override
  final IntentionSummary summary;

  @override
  bool matches(IntentionCatalogQuery query) => query.includes(summary);
}

IntentionSummary testSummary({
  int index = 1,
  String title = 'Намерение',
  bool hasDescription = false,
  IntentionReadiness readiness = IntentionReadiness.notReady,
}) {
  final encodedId =
      '018f0000-0000-7000-8000-${index.toString().padLeft(12, '0')}';
  final id = switch (IntentionId.decode(encodedId)) {
    IntentionIdDecodingSuccess(:final id) => id,
    InvalidIntentionIdDecoding() => throw StateError(
      'Некорректный fixture ID.',
    ),
  };
  final timestamp = IntentionTimestamp(DateTime.utc(2026, 1, index));
  return IntentionSummary(
    id: id,
    title: title,
    hasDescription: hasDescription,
    readiness: readiness,
    archiveState: IntentionArchiveState.active,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

Intention testIntention({int index = 1, String title = 'Намерение'}) {
  final summary = testSummary(index: index, title: title);
  return Intention(
    id: summary.id,
    title: summary.title,
    description: null,
    readiness: summary.readiness,
    archiveState: summary.archiveState,
    createdAt: summary.createdAt,
    updatedAt: summary.updatedAt,
  );
}
