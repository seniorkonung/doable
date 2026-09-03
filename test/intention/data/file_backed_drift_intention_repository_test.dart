import 'dart:async';

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
        'возвращает corruption без частичной страницы для строки с ${fixture.description} идентификатором',
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
          final IntentionRepository repository = DriftIntentionRepository(
            database,
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

IntentionId _id(String value) => switch (IntentionId.decode(value)) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw ArgumentError.value(value, 'value'),
};

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
