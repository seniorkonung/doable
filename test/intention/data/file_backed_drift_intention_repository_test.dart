import 'dart:async';

import 'package:doable/src/data/local/app_database.dart' hide Intention;
import 'package:doable/src/data/local/fts_integrity.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_repository.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/data/drift_intention_repository.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/local_database_harness.dart';

void main() {
  group('file-backed DriftIntentionRepository', () {
    test('после отказавшего создания открывает тот же файл без созданного намерения', () async {
      final harness = await LocalDatabaseHarness.fileBacked();
      addTearDown(harness.dispose);
      final id = _id('018f0b5d-6b2e-7c80-8000-000000000811');
      final interceptor = _FailAfterDmlInterceptor(_DmlOperation.insert);
      final firstDatabase = await harness.openReadyDatabase(
        observer: interceptor,
      );
      final IntentionRepository firstRepository = DriftIntentionRepository(
        firstDatabase,
        _SequenceIntentionIdGenerator([id]),
        () => DateTime.utc(2026, 9, 3, 10),
        InMemoryDiagnosticsSink(),
      );

      interceptor.arm();
      final result = await firstRepository.execute(
        const CreateIntention(
          title: 'Несохранённое создание',
          description: 'Не должно остаться в файле',
        ),
      );

      expect(result, _unexpectedCommandFailure());
      final firstSnapshot = Completer<Result<Intention?>>();
      final subscription = firstRepository
          .watchById(id)
          .listen(firstSnapshot.complete);
      expect(_watched(await firstSnapshot.future), isNull);
      await subscription.cancel();
      await harness.closePersistenceObjectGraph();

      final reopenedDatabase = await harness.openReadyDatabase();
      final IntentionRepository reopenedRepository = DriftIntentionRepository(
        reopenedDatabase,
        _SequenceIntentionIdGenerator(const []),
        () => DateTime.utc(2026, 9, 3, 11),
        InMemoryDiagnosticsSink(),
      );

      expect(_watched(await reopenedRepository.watchById(id).first), isNull);
      final page = _firstPage(
        await reopenedRepository.getCatalogPage(
          _catalogQuery(
            IntentionScope.all,
            titleFilter: 'несохранённое создание',
          ),
        ),
      );
      expect(page.totalCount, 0);
      expect(page.items, isEmpty);
      await verifyIntentionTitlesFtsIntegrity(reopenedDatabase);
      await harness.closePersistenceObjectGraph();
    });

    for (final scenario in [
      _PostDmlFailureReopenScenario(
        description: 'изменения',
        operation: _DmlOperation.update,
        id: _id('018f0b5d-6b2e-7c80-8000-000000000812'),
        initialTitle: 'Исходное обновление',
        initialDescription: 'Исходное описание',
        failedCommand: (id) => UpdateIntention(
          id: id,
          title: 'Несохранённое обновление',
          description: 'Несохранённое описание',
        ),
        readiness: IntentionReadiness.notReady,
        archiveState: IntentionArchiveState.active,
        updatedAt: DateTime.utc(2026, 9, 3, 10),
        scope: IntentionScope.active,
        titleFilter: 'исходное обновление',
      ),
      _PostDmlFailureReopenScenario(
        description: 'изменения готовности к действию',
        operation: _DmlOperation.update,
        id: _id('018f0b5d-6b2e-7c80-8000-000000000813'),
        initialTitle: 'Намерение для готовности',
        initialDescription: 'Сохраняемая готовность',
        failedCommand: EnableIntentionReadiness.new,
        readiness: IntentionReadiness.notReady,
        archiveState: IntentionArchiveState.active,
        updatedAt: DateTime.utc(2026, 9, 3, 10),
        scope: IntentionScope.active,
        titleFilter: 'намерение для готовности',
      ),
      _PostDmlFailureReopenScenario(
        description: 'физического удаления',
        operation: _DmlOperation.delete,
        id: _id('018f0b5d-6b2e-7c80-8000-000000000814'),
        initialTitle: 'Архивируемое намерение',
        initialDescription: null,
        preparationCommands: [
          EnableIntentionReadiness.new,
          ArchiveIntention.new,
        ],
        failedCommand: DeleteIntention.new,
        readiness: IntentionReadiness.ready,
        archiveState: IntentionArchiveState.archived,
        updatedAt: DateTime.utc(2026, 9, 3, 12),
        scope: IntentionScope.archived,
        titleFilter: 'архивируемое намерение',
      ),
    ]) {
      test(
        'после отказавшего ${scenario.description} сохраняет согласованное намерение после повторного открытия',
        () async {
          final harness = await LocalDatabaseHarness.fileBacked();
          addTearDown(harness.dispose);
          final interceptor = _FailAfterDmlInterceptor(scenario.operation);
          final firstDatabase = await harness.openReadyDatabase(
            observer: interceptor,
          );
          final IntentionRepository firstRepository = DriftIntentionRepository(
            firstDatabase,
            _SequenceIntentionIdGenerator([scenario.id]),
            _SequenceClock([
              DateTime.utc(2026, 9, 3, 10),
              DateTime.utc(2026, 9, 3, 11),
              DateTime.utc(2026, 9, 3, 12),
              DateTime.utc(2026, 9, 3, 13),
            ]).call,
            InMemoryDiagnosticsSink(),
          );

          _saved(
            await firstRepository.execute(
              CreateIntention(
                title: scenario.initialTitle,
                description: scenario.initialDescription,
              ),
            ),
          );
          for (final command in scenario.preparationCommands) {
            _saved(await firstRepository.execute(command(scenario.id)));
          }

          interceptor.arm();
          expect(
            await firstRepository.execute(scenario.failedCommand(scenario.id)),
            _unexpectedCommandFailure(),
          );
          final firstSnapshot = Completer<Result<Intention?>>();
          final subscription = firstRepository
              .watchById(scenario.id)
              .listen(firstSnapshot.complete);
          _expectIntention(_watched(await firstSnapshot.future), scenario);
          await subscription.cancel();
          await harness.closePersistenceObjectGraph();

          final reopenedDatabase = await harness.openReadyDatabase();
          final IntentionRepository reopenedRepository =
              DriftIntentionRepository(
                reopenedDatabase,
                _SequenceIntentionIdGenerator(const []),
                () => DateTime.utc(2026, 9, 3, 14),
                InMemoryDiagnosticsSink(),
              );

          _expectIntention(
            _watched(await reopenedRepository.watchById(scenario.id).first),
            scenario,
          );
          final scopePage = _firstPage(
            await reopenedRepository.getCatalogPage(
              _catalogQuery(scenario.scope),
            ),
          );
          expect(scopePage.totalCount, 1);
          expect(scopePage.items.map((item) => item.id), [scenario.id]);

          final excludedScope = switch (scenario.scope) {
            IntentionScope.active => IntentionScope.archived,
            IntentionScope.archived => IntentionScope.active,
            IntentionScope.all => throw StateError(
              'Охват all не может быть исключающим.',
            ),
          };
          final excludedPage = _firstPage(
            await reopenedRepository.getCatalogPage(
              _catalogQuery(excludedScope),
            ),
          );
          expect(excludedPage.totalCount, 0);
          expect(excludedPage.items, isEmpty);

          final filteredPage = _firstPage(
            await reopenedRepository.getCatalogPage(
              _catalogQuery(
                IntentionScope.all,
                titleFilter: scenario.titleFilter,
              ),
            ),
          );
          expect(filteredPage.totalCount, 1);
          expect(filteredPage.items.map((item) => item.id), [scenario.id]);
          await verifyIntentionTitlesFtsIntegrity(reopenedDatabase);
          await harness.closePersistenceObjectGraph();
        },
      );
    }

    test('сохраняет полный lifecycle через публичную seam после повторного открытия', () async {
      final harness = await LocalDatabaseHarness.fileBacked();
      addTearDown(harness.dispose);
      final activeId = _id('550e8400-e29b-41d4-a716-446655440000');
      final archivedId = _id('018f0b5d-6b2e-7c80-8000-000000000801');
      final deletedId = _id('018f0b5d-6b2e-7c80-8000-000000000802');

      await _createFirstObjectGraph(
        harness,
        activeId: activeId,
        archivedId: archivedId,
        deletedId: deletedId,
      );

      final reopenedDatabase = await harness.openReadyDatabase();
      final IntentionRepository repository = DriftIntentionRepository(
        reopenedDatabase,
        _SequenceIntentionIdGenerator(const []),
        () => DateTime.utc(2026, 9, 3, 18),
        InMemoryDiagnosticsSink(),
      );

      final active = _watched(await repository.watchById(activeId).first);
      expect(active, isNotNull);
      expect(active!.id, activeId);
      expect(active.title, 'Переписать "статью"');
      expect(active.description, '  Сохранить точный\nтекст  ');
      expect(active.readiness, IntentionReadiness.ready);
      expect(active.archiveState, IntentionArchiveState.active);
      expect(active.createdAt.value, DateTime.utc(2026, 9, 3, 10));
      expect(active.updatedAt.value, DateTime.utc(2026, 9, 3, 12));

      final archived = _watched(await repository.watchById(archivedId).first);
      expect(archived, isNotNull);
      expect(archived!.id, archivedId);
      expect(archived.title, 'Архивировать журнал');
      expect(archived.description, isNull);
      expect(archived.readiness, IntentionReadiness.notReady);
      expect(archived.archiveState, IntentionArchiveState.archived);
      expect(archived.createdAt.value, DateTime.utc(2026, 9, 3, 13));
      expect(archived.updatedAt.value, DateTime.utc(2026, 9, 3, 16));

      expect(_watched(await repository.watchById(deletedId).first), isNull);

      final activePage = _firstPage(
        await repository.getCatalogPage(_catalogQuery(IntentionScope.active)),
      );
      expect(activePage.totalCount, 1);
      expect(activePage.items.map((item) => item.id), [activeId]);

      final archivedPage = _firstPage(
        await repository.getCatalogPage(_catalogQuery(IntentionScope.archived)),
      );
      expect(archivedPage.totalCount, 1);
      expect(archivedPage.items.map((item) => item.id), [archivedId]);

      final allPage = _firstPage(
        await repository.getCatalogPage(_catalogQuery(IntentionScope.all)),
      );
      expect(allPage.totalCount, 2);
      expect(allPage.items.map((item) => item.id), [activeId, archivedId]);

      final filteredPage = _firstPage(
        await repository.getCatalogPage(
          _catalogQuery(IntentionScope.all, titleFilter: '  "статью"  '),
        ),
      );
      expect(filteredPage.totalCount, 1);
      expect(filteredPage.items.map((item) => item.id), [activeId]);

      await verifyIntentionTitlesFtsIntegrity(reopenedDatabase);
    });

    for (final fixture in [
      (description: 'некорректным', id: 'not-a-uuid'),
      (description: 'nil UUID', id: '00000000-0000-0000-0000-000000000000'),
    ]) {
      test(
        'возвращает corruption без частичной страницы после повторного открытия строки с ${fixture.description} идентификатором',
        () async {
          final harness = await LocalDatabaseHarness.fileBacked();
          addTearDown(harness.dispose);
          final database = await harness.openReadyDatabase();
          await database.customStatement(
            '''
              INSERT INTO intentions (
                id,
                title,
                title_search_key,
                description,
                is_action_ready,
                is_archived,
                created_at,
                updated_at
              ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ''',
            [
              fixture.id,
              'Повреждённое намерение',
              'повреждённое намерение',
              null,
              0,
              0,
              DateTime.utc(2026, 9, 3, 10).microsecondsSinceEpoch,
              DateTime.utc(2026, 9, 3, 10).microsecondsSinceEpoch,
            ],
          );
          await harness.closePersistenceObjectGraph();

          final reopenedDatabase = await harness.openReadyDatabase();
          final IntentionRepository repository = DriftIntentionRepository(
            reopenedDatabase,
            _SequenceIntentionIdGenerator(const []),
            () => DateTime.utc(2026, 9, 3, 11),
            InMemoryDiagnosticsSink(),
          );

          final result = await repository.getCatalogPage(
            _catalogQuery(IntentionScope.all),
          );

          expect(
            result,
            isA<ResultFailure<IntentionCatalogPage>>().having(
              (failure) => failure.failure,
              'failure',
              isA<IntentionCorruptionFailure>(),
            ),
          );
          await harness.closePersistenceObjectGraph();
        },
      );
    }
  });
}

Future<void> _createFirstObjectGraph(
  LocalDatabaseHarness harness, {
  required IntentionId activeId,
  required IntentionId archivedId,
  required IntentionId deletedId,
}) async {
  final database = await harness.openReadyDatabase();
  final IntentionRepository repository = DriftIntentionRepository(
    database,
    _SequenceIntentionIdGenerator([activeId, archivedId, deletedId]),
    _SequenceClock([
      DateTime.utc(2026, 9, 3, 10),
      DateTime.utc(2026, 9, 3, 11),
      DateTime.utc(2026, 9, 3, 12),
      DateTime.utc(2026, 9, 3, 13),
      DateTime.utc(2026, 9, 3, 14),
      DateTime.utc(2026, 9, 3, 15),
      DateTime.utc(2026, 9, 3, 16),
      DateTime.utc(2026, 9, 3, 17),
    ]).call,
    InMemoryDiagnosticsSink(),
  );

  _saved(
    await repository.execute(
      const CreateIntention(title: 'Исходная статья', description: 'Черновик'),
    ),
  );
  _saved(
    await repository.execute(
      UpdateIntention(
        id: activeId,
        title: 'Переписать "статью"',
        description: '  Сохранить точный\nтекст  ',
      ),
    ),
  );
  _saved(await repository.execute(EnableIntentionReadiness(activeId)));

  _saved(
    await repository.execute(
      const CreateIntention(title: 'Архивировать журнал', description: null),
    ),
  );
  _saved(await repository.execute(ArchiveIntention(archivedId)));
  _saved(await repository.execute(RestoreIntention(archivedId)));
  _saved(await repository.execute(ArchiveIntention(archivedId)));

  _saved(
    await repository.execute(
      const CreateIntention(title: 'Удалить черновик', description: null),
    ),
  );
  expect(
    await repository.execute(DeleteIntention(deletedId)),
    _deleted(deletedId),
  );

  final firstSnapshot = Completer<Result<Intention?>>();
  final subscription = repository
      .watchById(activeId)
      .listen(firstSnapshot.complete);
  expect(_watched(await firstSnapshot.future)?.id, activeId);
  await subscription.cancel();

  await harness.closePersistenceObjectGraph();
}

IntentionCatalogQuery _catalogQuery(
  IntentionScope scope, {
  String? titleFilter,
}) => IntentionCatalogQuery(
  scope: scope,
  titleFilter: titleFilter,
  order: const IntentionCatalogOrder(
    field: IntentionCatalogSortField.createdAt,
    direction: IntentionCatalogSortDirection.ascending,
  ),
  pageSize: 10,
);

IntentionCatalogFirstPage _firstPage(Result<IntentionCatalogPage> result) {
  expect(result, isA<ResultSuccess<IntentionCatalogPage>>());
  final page = (result as ResultSuccess<IntentionCatalogPage>).value;
  expect(page, isA<IntentionCatalogFirstPage>());
  return page as IntentionCatalogFirstPage;
}

Intention _saved(Result<IntentionCommandSuccess> result) {
  expect(result, isA<ResultSuccess<IntentionCommandSuccess>>());
  final success = (result as ResultSuccess<IntentionCommandSuccess>).value;
  expect(success, isA<IntentionSaved>());
  return (success as IntentionSaved).intention;
}

Intention? _watched(Result<Intention?> result) {
  expect(result, isA<ResultSuccess<Intention?>>());
  return (result as ResultSuccess<Intention?>).value;
}

Matcher _deleted(IntentionId id) =>
    isA<ResultSuccess<IntentionCommandSuccess>>().having(
      (result) => result.value,
      'value',
      isA<IntentionDeleted>().having((success) => success.id, 'id', id),
    );

Matcher _unexpectedCommandFailure() =>
    isA<ResultFailure<IntentionCommandSuccess>>().having(
      (result) => result.failure,
      'failure',
      isA<IntentionUnexpectedFailure>(),
    );

void _expectIntention(
  Intention? intention,
  _PostDmlFailureReopenScenario scenario,
) {
  expect(intention, isNotNull);
  expect(intention!.id, scenario.id);
  expect(intention.title, scenario.initialTitle);
  expect(intention.description, scenario.initialDescription);
  expect(intention.readiness, scenario.readiness);
  expect(intention.archiveState, scenario.archiveState);
  expect(intention.createdAt.value, DateTime.utc(2026, 9, 3, 10));
  expect(intention.updatedAt.value, scenario.updatedAt);
}

IntentionId _id(String value) => switch (IntentionId.decode(value)) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw ArgumentError.value(value, 'value'),
};

enum _DmlOperation { insert, update, delete }

typedef _IntentionCommandFactory = IntentionCommand Function(IntentionId id);

final class _PostDmlFailureReopenScenario {
  _PostDmlFailureReopenScenario({
    required this.description,
    required this.operation,
    required this.id,
    required this.initialTitle,
    required this.initialDescription,
    required this.failedCommand,
    required this.readiness,
    required this.archiveState,
    required this.updatedAt,
    required this.scope,
    required this.titleFilter,
    this.preparationCommands = const [],
  });

  final String description;
  final _DmlOperation operation;
  final IntentionId id;
  final String initialTitle;
  final String? initialDescription;
  final List<_IntentionCommandFactory> preparationCommands;
  final _IntentionCommandFactory failedCommand;
  final IntentionReadiness readiness;
  final IntentionArchiveState archiveState;
  final DateTime updatedAt;
  final IntentionScope scope;
  final String titleFilter;
}

final class _FailAfterDmlInterceptor extends LocalDatabaseConnectionObserver {
  _FailAfterDmlInterceptor(this._operation);

  final _DmlOperation _operation;
  var _armed = false;
  var _hasFailed = false;

  void arm() => _armed = true;

  @override
  void afterStatement(LocalDatabaseSqlStatement statement) {
    final isExpectedOperation = switch (_operation) {
      _DmlOperation.insert =>
        statement.operation == LocalDatabaseSqlOperation.insert,
      _DmlOperation.update =>
        statement.operation == LocalDatabaseSqlOperation.update,
      _DmlOperation.delete =>
        statement.operation == LocalDatabaseSqlOperation.delete,
    };
    if (!isExpectedOperation) return;
    if (_armed && !_hasFailed) {
      _hasFailed = true;
      throw StateError('CANARY-after-dml-failure');
    }
  }
}

final class _SequenceIntentionIdGenerator implements IntentionIdGenerator {
  _SequenceIntentionIdGenerator(this._ids);

  final List<IntentionId> _ids;
  var _nextIndex = 0;

  @override
  IntentionId generate() {
    if (_nextIndex == _ids.length) {
      throw StateError(
        'Не осталось идентификаторов для тестовой последовательности.',
      );
    }
    return _ids[_nextIndex++];
  }
}

final class _SequenceClock {
  _SequenceClock(this._times);

  final List<DateTime> _times;
  var _nextIndex = 0;

  DateTime call() {
    if (_nextIndex == _times.length) {
      throw StateError('Не осталось времён для тестовой последовательности.');
    }
    return _times[_nextIndex++];
  }
}
