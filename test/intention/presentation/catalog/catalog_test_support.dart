import 'dart:async';

import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_repository.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';

final class ControlledCatalogRepository implements IntentionRepository {
  final queries = <IntentionCatalogQuery>[];
  final _requests = <Completer<Result<IntentionCatalogPage>>>[];

  IntentionCatalogQuery queryAt(int index) => queries[index];

  void complete(int index, Result<IntentionCatalogPage> result) {
    _requests[index].complete(result);
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
  Future<Result<IntentionCommandSuccess>> execute(IntentionCommand command) =>
      throw UnsupportedError('Изменяющие операции не используются в тесте.');

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
