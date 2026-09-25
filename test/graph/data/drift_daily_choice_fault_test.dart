import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/daily_choice_durability_fixture.dart';
import '../../support/local_database_harness.dart';

void main() {
  for (final scenario in _scenarios) {
    test('${scenario.operation.description}: ${scenario.point.description} '
        '№${scenario.occurrence} откатывает всё', () async {
      final harness = await LocalDatabaseHarness.fileBacked();
      addTearDown(harness.dispose);
      final observer = _FailureObserver(scenario.point, scenario.occurrence);
      var database = await harness.openReadyDatabase(observer: observer);
      await seedDurabilityGraph(database);
      if (scenario.operation != _Operation.create) {
        expect(
          await durabilityRepository(database).execute(durabilityCreate()),
          isA<GraphCommandSucceeded>(),
        );
      }
      final before = await durabilityState(database);
      final repository = durabilityRepository(
        database,
        choiceNumber: 203,
        firstStepNumber: 313,
      );
      final revisionBefore = await _revision(repository);
      observer.arm();

      final result = await _execute(repository, scenario.operation);

      expect(observer.didFail, isTrue);
      expect(result, isA<GraphCommandFailed>());
      expect(
        (result as GraphCommandFailed).failure.category,
        GraphFailureCategory.unexpected,
      );
      expect(await durabilityState(database), before);
      expect(
        (await _revision(repository)).compareTo(revisionBefore),
        GraphRevisionOrder.same,
      );
      await harness.closePersistenceObjectGraph();

      database = await harness.openReadyDatabase();
      expect(await durabilityState(database), before);
      expect(
        await database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
      final reopened = durabilityRepository(database);
      final choice = await reopened.getDailyChoice(durabilityChoice(201));
      expect(
        (choice as GraphResultSuccess).value.value != null,
        scenario.operation != _Operation.create,
      );
      if (scenario.operation == _Operation.repeat) {
        final repeated = await reopened.getDailyChoice(durabilityChoice(203));
        expect((repeated as GraphResultSuccess).value.value, isNull);
      }
    });
  }
}

Future<Object> _execute(
  DriftPersonalGraphRepository repository,
  _Operation operation,
) => switch (operation) {
  _Operation.create => repository.execute(durabilityCreate()),
  _Operation.repeat => repository.execute(durabilityCreate()),
  _Operation.update => repository.execute(durabilityUpdate(201)),
  _Operation.replace => repository.execute(durabilityReplace(201)),
  _Operation.delete => repository.execute(
    DeleteDailyChoice(durabilityChoice(201)),
  ),
  _Operation.mixedDelete => repository.execute(durabilityMixedDelete(201)),
};

Future<GraphRevision> _revision(
  DriftPersonalGraphRepository repository,
) async => (await repository.getDailyChoice(
  durabilityChoice(999),
) as GraphResultSuccess).value.revision;

enum _Operation {
  create('Создание'),
  repeat('Повтор маршрута'),
  update('Изменение'),
  replace('Замена пути'),
  delete('Удаление'),
  mixedDelete('Смешанное удаление');

  const _Operation(this.description);
  final String description;
}

enum _FaultPoint {
  choiceInsert('запись выбора'),
  stepInsert('запись шага'),
  choiceUpdate('обновление выбора'),
  stepDelete('удаление старых шагов'),
  choiceDelete('удаление выбора'),
  relationDelete('удаление связи'),
  resultRead('чтение результата');

  const _FaultPoint(this.description);
  final String description;
}

typedef _Scenario = ({_Operation operation, _FaultPoint point, int occurrence});

const _scenarios = <_Scenario>[
  (
    operation: _Operation.create,
    point: _FaultPoint.choiceInsert,
    occurrence: 1,
  ),
  (operation: _Operation.create, point: _FaultPoint.stepInsert, occurrence: 1),
  (operation: _Operation.create, point: _FaultPoint.stepInsert, occurrence: 2),
  (operation: _Operation.create, point: _FaultPoint.resultRead, occurrence: 1),
  (
    operation: _Operation.repeat,
    point: _FaultPoint.choiceInsert,
    occurrence: 1,
  ),
  (operation: _Operation.repeat, point: _FaultPoint.stepInsert, occurrence: 1),
  (operation: _Operation.repeat, point: _FaultPoint.stepInsert, occurrence: 2),
  (operation: _Operation.repeat, point: _FaultPoint.resultRead, occurrence: 1),
  (
    operation: _Operation.update,
    point: _FaultPoint.choiceUpdate,
    occurrence: 1,
  ),
  (operation: _Operation.update, point: _FaultPoint.resultRead, occurrence: 2),
  (operation: _Operation.replace, point: _FaultPoint.stepDelete, occurrence: 1),
  (
    operation: _Operation.replace,
    point: _FaultPoint.choiceUpdate,
    occurrence: 1,
  ),
  (operation: _Operation.replace, point: _FaultPoint.stepInsert, occurrence: 1),
  (operation: _Operation.replace, point: _FaultPoint.resultRead, occurrence: 2),
  (
    operation: _Operation.delete,
    point: _FaultPoint.choiceDelete,
    occurrence: 1,
  ),
  (operation: _Operation.delete, point: _FaultPoint.resultRead, occurrence: 2),
  (
    operation: _Operation.mixedDelete,
    point: _FaultPoint.choiceDelete,
    occurrence: 1,
  ),
  (
    operation: _Operation.mixedDelete,
    point: _FaultPoint.relationDelete,
    occurrence: 1,
  ),
  (
    operation: _Operation.mixedDelete,
    point: _FaultPoint.resultRead,
    occurrence: 2,
  ),
];

final class _FailureObserver extends LocalDatabaseConnectionObserver {
  _FailureObserver(this.point, this.occurrence);

  final _FaultPoint point;
  final int occurrence;
  var _armed = false;
  var _matches = 0;
  var didFail = false;

  void arm() => _armed = true;

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (point == _FaultPoint.resultRead) _failIfMatched(statement);
  }

  @override
  void afterStatement(LocalDatabaseSqlStatement statement) {
    if (point != _FaultPoint.resultRead) _failIfMatched(statement);
  }

  void _failIfMatched(LocalDatabaseSqlStatement statement) {
    if (!_armed || didFail) return;
    final matches = switch (point) {
      _FaultPoint.choiceInsert =>
        statement.operation == LocalDatabaseSqlOperation.insert &&
            _contains(statement, 'INSERT INTO daily_choices'),
      _FaultPoint.stepInsert =>
        statement.operation == LocalDatabaseSqlOperation.insert &&
            _contains(statement, 'INSERT INTO daily_choice_path_steps'),
      _FaultPoint.choiceUpdate =>
        statement.operation == LocalDatabaseSqlOperation.update &&
            _contains(statement, 'daily_choices'),
      _FaultPoint.stepDelete =>
        statement.operation == LocalDatabaseSqlOperation.delete &&
            _contains(statement, 'daily_choice_path_steps'),
      _FaultPoint.choiceDelete =>
        statement.operation == LocalDatabaseSqlOperation.delete &&
            _contains(statement, 'daily_choices'),
      _FaultPoint.relationDelete =>
        statement.operation == LocalDatabaseSqlOperation.update &&
            _contains(statement, 'DELETE FROM long_term_relations'),
      _FaultPoint.resultRead =>
        statement.operation == LocalDatabaseSqlOperation.select &&
            _contains(statement, 'FROM daily_choices WHERE id = ?'),
    };
    if (!matches) return;
    _matches++;
    if (_matches != occurrence) return;
    didFail = true;
    throw StateError('Управляемый отказ после существенной записи.');
  }
}

bool _contains(LocalDatabaseSqlStatement statement, String fragment) =>
    statement.statements.any((sql) => sql.contains(fragment));
