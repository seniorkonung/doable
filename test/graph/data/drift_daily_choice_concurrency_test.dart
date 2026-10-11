import 'dart:async';

import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/daily_choice_durability_fixture.dart';

void main() {
  late AppDatabase database;
  late _SqlGate gate;
  late DriftPersonalGraphRepository repository;

  setUp(() async {
    gate = _SqlGate();
    database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(),
        gate,
      ),
    );
    await database.open();
    await seedDurabilityGraph(database);
    repository = durabilityRepository(
      database,
      choiceNumber: 202,
      firstStepNumber: 401,
    );
  });

  tearDown(() async {
    gate.release();
    await database.close();
  });

  Future<(Object, Object)> overlap(
    Future<Object> Function() first,
    Future<Object> Function() second,
  ) async {
    gate.arm();
    final firstResult = first();
    await gate.entered;
    final secondResult = second();
    gate.release();
    return (await firstResult, await secondResult);
  }

  test('Создание и удаление связи: изменение графа первым', () async {
    final choicesBefore = await durabilityRows(database, 'daily_choices');
    final stepsBefore = await durabilityRows(
      database,
      'daily_choice_path_steps',
    );

    final (first, second) = await overlap(
      () => repository.execute(DeleteLongTermRelation(durabilityRelation(103))),
      () => repository.execute(durabilityCreate(path: [103])),
    );

    final choice = await repository.getDailyChoice(durabilityChoice(202));
    expect(choice, isA<DailyChoiceReadSuccess>());
    final snapshot = (choice as DailyChoiceReadSuccess).value;
    expect(first, isA<GraphCommandSucceeded>());
    expect(
      (second as GraphCommandFailed).failure.category,
      GraphFailureCategory.conflict,
    );
    expect(snapshot.value, isNull);
    expect(
      snapshot.revision.compareTo(
        (first as GraphCommandSucceeded).value.revision,
      ),
      GraphRevisionOrder.same,
    );
    expect(await durabilityRows(database, 'daily_choices'), choicesBefore);
    expect(
      await durabilityRows(database, 'daily_choice_path_steps'),
      stepsBefore,
    );
  });
}

final class _SqlGate extends LocalDatabaseConnectionObserver {
  Completer<void> _entered = Completer<void>();
  Completer<void> _released = Completer<void>();
  bool _armed = false;

  Future<void> get entered => _entered.future;

  void arm() {
    _entered = Completer<void>();
    _released = Completer<void>();
    _armed = true;
  }

  void release() {
    if (!_released.isCompleted) _released.complete();
  }

  @override
  Future<void> beforeStatement(LocalDatabaseSqlStatement statement) async {
    if (!_armed || statement.operation != LocalDatabaseSqlOperation.select) {
      return;
    }
    _armed = false;
    _entered.complete();
    await _released.future;
  }
}
