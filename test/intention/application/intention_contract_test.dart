import 'dart:async';

import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_repository.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final id = IntentionId('0f8fad5b-d9cb-469f-a165-70867728950e');
  final intention = _intention(id);

  test('commands различают все операции над намерением', () {
    final commands = <IntentionCommand>[
      CreateIntention(title: 'Здоровье', description: 'Описание'),
      ChangeIntentionDetails(id: id, title: 'Сон', description: null),
      EnableIntentionActionReadiness(id),
      DisableIntentionActionReadiness(id),
      ArchiveIntention(id),
      RestoreIntention(id),
      DeleteIntention(id),
    ];

    expect(commands.map(_commandKind), <String>[
      'create',
      'changeDetails',
      'enableReadiness',
      'disableReadiness',
      'archive',
      'restore',
      'delete',
    ]);
  });

  test('success различает сохранение и удаление без changed flag', () {
    final saved = IntentionSaved(intention);
    final deleted = IntentionDeleted(id);

    expect(_successPayload(saved), same(intention));
    expect(_successPayload(deleted), same(id));
  });

  test('result выражает success и все стабильные repository failures', () {
    final results = <Result<IntentionCommandSuccess>>[
      Result.success(IntentionSaved(intention)),
      Result.failure(
        const IntentionValidationFailure(
          IntentionValidationFailureCode.emptyTitle,
        ),
      ),
      Result.failure(IntentionNotFoundFailure(id)),
      const Result.failure(IntentionConflictFailure()),
      const Result.failure(IntentionUnavailableFailure()),
      const Result.failure(IntentionCorruptionFailure()),
    ];

    expect(results.map(_resultKind), <String>[
      'success',
      'validation',
      'notFound',
      'conflict',
      'unavailable',
      'corruption',
    ]);
  });

  test(
    'watch streams публикуют только типизированную failure и завершаются',
    () async {
      final repository = _FailingRepository();
      final errors = <Object>[];
      var completed = false;

      repository
          .watchCatalog(
            IntentionScope.active,
            IntentionCatalogOrder.byCreationTime,
          )
          .listen((_) {}, onError: errors.add, onDone: () => completed = true);
      await repository.failCatalog();

      expect(errors, [isA<IntentionUnavailableFailure>()]);
      expect(completed, isTrue);
    },
  );
}

String _commandKind(IntentionCommand command) => switch (command) {
  CreateIntention() => 'create',
  ChangeIntentionDetails() => 'changeDetails',
  EnableIntentionActionReadiness() => 'enableReadiness',
  DisableIntentionActionReadiness() => 'disableReadiness',
  ArchiveIntention() => 'archive',
  RestoreIntention() => 'restore',
  DeleteIntention() => 'delete',
};

Object _successPayload(IntentionCommandSuccess success) => switch (success) {
  IntentionSaved(:final intention) => intention,
  IntentionDeleted(:final id) => id,
};

String _resultKind(Result<IntentionCommandSuccess> result) => switch (result) {
  ResultSuccess() => 'success',
  ResultFailure(:final failure) => switch (failure) {
    IntentionValidationFailure() => 'validation',
    IntentionNotFoundFailure() => 'notFound',
    IntentionConflictFailure() => 'conflict',
    IntentionUnavailableFailure() => 'unavailable',
    IntentionCorruptionFailure() => 'corruption',
  },
};

Intention _intention(IntentionId id) {
  final timestamp = IntentionTimestamp(DateTime.utc(2026, 8, 29));
  return Intention(
    id: id,
    title: 'Здоровье',
    description: null,
    readiness: IntentionReadiness.notReady,
    archiveState: IntentionArchiveState.active,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

final class _FailingRepository implements IntentionRepository {
  final _catalogController = StreamController<List<Intention>>();

  @override
  Future<Result<IntentionCommandSuccess>> execute(IntentionCommand command) {
    throw UnimplementedError();
  }

  @override
  Stream<List<Intention>> watchCatalog(
    IntentionScope scope,
    IntentionCatalogOrder order,
  ) => _catalogController.stream;

  @override
  Stream<Intention?> watchById(IntentionId id) => const Stream.empty();

  Future<void> failCatalog() async {
    _catalogController.addError(const IntentionUnavailableFailure());
    await _catalogController.close();
  }
}
