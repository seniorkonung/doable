import 'dart:async';

import 'package:doable/src/data/local/app_database.dart' hide Intention;
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_repository.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../support/in_memory_diagnostics_sink.dart';

void main() {
  late AppDatabase database;
  late InMemoryDiagnosticsSink diagnostics;
  late DriftPersonalGraphRepository repository;

  setUp(() async {
    database = AppDatabase(openInMemoryLocalDatabase());
    await database.open();
    diagnostics = InMemoryDiagnosticsSink();
    repository = _repository(database, diagnostics);
  });

  tearDown(() => database.close());

  test(
    'согласует снимки намерения с подтверждённой ревизией команды графа',
    () async {
      final id = _id(_uuidV7);
      await _insertIntention(
        database,
        id: id.toCanonicalString(),
        title: 'Прочитать книгу',
      );
      final graphRepository = DriftPersonalGraphRepository(
        database,
        UuidV7IntentionIdGenerator(),
        () => DateTime.utc(2026, 9, 3, 12),
        diagnostics,
      );
      final events = StreamIterator(graphRepository.watchIntention(id));
      addTearDown(events.cancel);

      expect(await events.moveNext(), isTrue);
      final initial = _graphSnapshot(events.current);
      expect(initial.value?.archiveState, IntentionArchiveState.active);

      final result = await graphRepository.execute(ArchiveIntention(id));
      expect(
        result,
        isA<ResultSuccess<ConfirmedGraphResult<IntentionCommandSuccess>>>(),
      );
      final confirmed =
          (result
                  as ResultSuccess<
                    ConfirmedGraphResult<IntentionCommandSuccess>
                  >)
              .value;

      expect(await events.moveNext(), isTrue);
      final updated = _graphSnapshot(events.current);
      expect(updated.value?.archiveState, IntentionArchiveState.archived);
      expect(
        initial.revision.compareTo(confirmed.revision),
        GraphRevisionOrder.older,
      );
      expect(
        updated.revision.compareTo(confirmed.revision),
        GraphRevisionOrder.same,
      );
    },
  );

  group('DriftPersonalGraphRepository.watchIntention', () {
    test('публикует начальное подтверждённое отсутствие', () async {
      final result = await repository.watchIntention(_id(_uuidV7)).first;

      expect(result, isA<ResultSuccess<GraphSnapshot<Intention?>>>());
      expect(
        (result as ResultSuccess<GraphSnapshot<Intention?>>).value.value,
        isNull,
      );
      expect(diagnostics.events, [
        isA<IntentionDetailReadDiagnosticsEvent>().having(
          (event) => event.status,
          'status',
          isA<DiagnosticsStarted>(),
        ),
        isA<IntentionDetailReadDiagnosticsEvent>().having(
          (event) => event.status,
          'status',
          isA<DiagnosticsSucceeded>(),
        ),
      ]);
    });

    test(
      'публикует новую строку только после подтверждения transaction',
      () async {
        final id = _id(_uuidV7);
        final events = StreamIterator(repository.watchIntention(id));
        addTearDown(events.cancel);

        expect(await events.moveNext(), isTrue);
        expect(events.current, _isSuccessfulAbsence());

        final result = await repository.execute(
          const CreateIntention(
            title: 'Купить молоко',
            description: 'В фермерском магазине',
          ),
        );

        expect(
          result,
          isA<ResultSuccess<ConfirmedGraphResult<IntentionCommandSuccess>>>(),
        );

        expect(await events.moveNext(), isTrue);
        expect(
          events.current,
          _isSuccessfulIntention(
            id: id,
            title: 'Купить молоко',
            description: 'В фермерском магазине',
            createdAt: DateTime.utc(2026, 9, 2, 10),
          ),
        );
      },
    );

    test(
      'публикует state transition только после подтверждённого commit',
      () async {
        final id = _id(_uuidV7);
        final createdAt = DateTime.utc(2026, 9, 2, 10);
        await _insertIntention(
          database,
          id: id.toCanonicalString(),
          title: 'Прочитать книгу',
          description: 'До выходных',
          isActionReady: true,
          createdAt: createdAt,
        );
        repository = DriftPersonalGraphRepository(
          database,
          UuidV7IntentionIdGenerator(),
          () => DateTime.utc(2026, 9, 3, 12),
          diagnostics,
        );
        final events = StreamIterator(repository.watchIntention(id));
        addTearDown(events.cancel);

        expect(await events.moveNext(), isTrue);
        expect(
          events.current,
          _isSuccessfulIntention(
            id: id,
            title: 'Прочитать книгу',
            description: 'До выходных',
            readiness: IntentionReadiness.ready,
            createdAt: createdAt,
          ),
        );

        final result = await repository.execute(ArchiveIntention(id));

        expect(
          result,
          isA<ResultSuccess<ConfirmedGraphResult<IntentionCommandSuccess>>>(),
        );
        expect(await events.moveNext(), isTrue);
        expect(
          events.current,
          _isSuccessfulIntention(
            id: id,
            title: 'Прочитать книгу',
            description: 'До выходных',
            readiness: IntentionReadiness.ready,
            archiveState: IntentionArchiveState.archived,
            createdAt: createdAt,
            updatedAt: DateTime.utc(2026, 9, 3, 12),
          ),
        );
      },
    );

    test('публикует подтверждённое отсутствие после удаления', () async {
      final id = _id(_uuidV7);
      await _insertIntention(
        database,
        id: id.toCanonicalString(),
        title: 'Прочитать книгу',
      );
      final events = StreamIterator(repository.watchIntention(id));
      addTearDown(events.cancel);

      expect(await events.moveNext(), isTrue);
      expect(
        events.current,
        _isSuccessfulIntention(id: id, title: 'Прочитать книгу'),
      );

      final result = await repository.execute(DeleteIntention(id));

      expect(
        result,
        isA<ResultSuccess<ConfirmedGraphResult<IntentionCommandSuccess>>>(),
      );

      expect(await events.moveNext(), isTrue);
      expect(events.current, _isSuccessfulAbsence());
    });

    test(
      'rehydrate сохраняет UUID v4 и v7, текст, состояния и UTC timestamps',
      () async {
        final fixtures = [
          (
            id: _id(_uuidV4),
            title: 'Быть здоровым',
            description: null,
            readiness: IntentionReadiness.notReady,
            archiveState: IntentionArchiveState.active,
            createdAt: DateTime.utc(2026, 9, 2, 9),
            updatedAt: DateTime.utc(2026, 9, 2, 9),
          ),
          (
            id: _id(_uuidV7),
            title: 'Учить английский',
            description: 'Сохраняются  внутренние пробелы\nи перенос строки',
            readiness: IntentionReadiness.ready,
            archiveState: IntentionArchiveState.archived,
            createdAt: DateTime.utc(2026, 9, 2, 10),
            updatedAt: DateTime.utc(2026, 9, 2, 12),
          ),
          (
            id: _id('018f0b5d-6b2e-7c80-8000-000000000305'),
            title: 'Показание после перевода часов',
            description: null,
            readiness: IntentionReadiness.notReady,
            archiveState: IntentionArchiveState.active,
            createdAt: DateTime.utc(2026, 9, 2, 12),
            updatedAt: DateTime.utc(2026, 9, 2, 11),
          ),
        ];

        for (final fixture in fixtures) {
          await _insertIntention(
            database,
            id: fixture.id.toCanonicalString(),
            title: fixture.title,
            description: fixture.description,
            isActionReady: fixture.readiness == IntentionReadiness.ready,
            isArchived: fixture.archiveState == IntentionArchiveState.archived,
            createdAt: fixture.createdAt,
            updatedAt: fixture.updatedAt,
          );

          expect(
            await repository.watchIntention(fixture.id).first,
            _isSuccessfulIntention(
              id: fixture.id,
              title: fixture.title,
              description: fixture.description,
              readiness: fixture.readiness,
              archiveState: fixture.archiveState,
              createdAt: fixture.createdAt,
              updatedAt: fixture.updatedAt,
            ),
          );
        }
      },
    );

    test(
      'превращает сохранённые нарушения предметных инвариантов в corruption',
      () async {
        final fixtures = [
          (
            id: _id('018f0b5d-6b2e-7c80-8000-000000000301'),
            title: '  ',
            description: null,
            createdAt: DateTime.utc(2026, 9, 2, 10),
            updatedAt: DateTime.utc(2026, 9, 2, 10),
          ),
          (
            id: _id('018f0b5d-6b2e-7c80-8000-000000000302'),
            title: 'Допустимое название',
            description: ' \n\t ',
            createdAt: DateTime.utc(2026, 9, 2, 10),
            updatedAt: DateTime.utc(2026, 9, 2, 10),
          ),
          (
            id: _id('018f0b5d-6b2e-7c80-8000-000000000303'),
            title: List.filled(256, 'a').join(),
            description: null,
            createdAt: DateTime.utc(2026, 9, 2, 10),
            updatedAt: DateTime.utc(2026, 9, 2, 10),
          ),
        ];

        await database.customStatement('PRAGMA ignore_check_constraints = ON');
        for (final fixture in fixtures) {
          await _insertIntention(
            database,
            id: fixture.id.toCanonicalString(),
            title: fixture.title,
            description: fixture.description,
            createdAt: fixture.createdAt,
            updatedAt: fixture.updatedAt,
          );
        }
        await database.customStatement('PRAGMA ignore_check_constraints = OFF');

        for (final fixture in fixtures) {
          await expectLater(
            repository.watchIntention(fixture.id),
            emitsInOrder([_isFailure<IntentionCorruptionFailure>(), emitsDone]),
          );
        }
      },
    );

    test(
      'отклоняет недопустимые raw storage-значения до typed Drift mapping',
      () async {
        final fixtures = [
          (
            id: _id('018f0b5d-6b2e-7c80-8000-000000000306'),
            isActionReady: 2 as Object,
            isArchived: 0 as Object,
            createdAt:
                DateTime.utc(2026, 9, 2, 10).microsecondsSinceEpoch as Object,
            updatedAt:
                DateTime.utc(2026, 9, 2, 10).microsecondsSinceEpoch as Object,
            description: null as Object?,
          ),
          (
            id: _id('018f0b5d-6b2e-7c80-8000-000000000307'),
            isActionReady: -1 as Object,
            isArchived: 0 as Object,
            createdAt:
                DateTime.utc(2026, 9, 2, 10).microsecondsSinceEpoch as Object,
            updatedAt:
                DateTime.utc(2026, 9, 2, 10).microsecondsSinceEpoch as Object,
            description: null as Object?,
          ),
          (
            id: _id('018f0b5d-6b2e-7c80-8000-000000000308'),
            isActionReady: 1.5 as Object,
            isArchived: 0 as Object,
            createdAt:
                DateTime.utc(2026, 9, 2, 10).microsecondsSinceEpoch as Object,
            updatedAt:
                DateTime.utc(2026, 9, 2, 10).microsecondsSinceEpoch as Object,
            description: null as Object?,
          ),
          (
            id: _id('018f0b5d-6b2e-7c80-8000-000000000309'),
            isActionReady: 0 as Object,
            isArchived: 0 as Object,
            createdAt: 1.5 as Object,
            updatedAt:
                DateTime.utc(2026, 9, 2, 10).microsecondsSinceEpoch as Object,
            description: null as Object?,
          ),
          (
            id: _id('018f0b5d-6b2e-7c80-8000-000000000310'),
            isActionReady: 0 as Object,
            isArchived: 0 as Object,
            createdAt: 9223372036854775807 as Object,
            updatedAt:
                DateTime.utc(2026, 9, 2, 10).microsecondsSinceEpoch as Object,
            description: null as Object?,
          ),
          (
            id: _id('018f0b5d-6b2e-7c80-8000-000000000311'),
            isActionReady: Uint8List.fromList([1]) as Object,
            isArchived: 0 as Object,
            createdAt:
                DateTime.utc(2026, 9, 2, 10).microsecondsSinceEpoch as Object,
            updatedAt:
                DateTime.utc(2026, 9, 2, 10).microsecondsSinceEpoch as Object,
            description: Uint8List.fromList([1]) as Object,
          ),
        ];

        await database.customStatement('PRAGMA ignore_check_constraints = ON');
        for (final fixture in fixtures) {
          await _insertRawIntention(
            database,
            id: fixture.id.toCanonicalString(),
            description: fixture.description,
            isActionReady: fixture.isActionReady,
            isArchived: fixture.isArchived,
            createdAt: fixture.createdAt,
            updatedAt: fixture.updatedAt,
          );
        }
        await database.customStatement('PRAGMA ignore_check_constraints = OFF');

        for (final fixture in fixtures) {
          await expectLater(
            repository.watchIntention(fixture.id),
            emitsInOrder([_isFailure<IntentionCorruptionFailure>(), emitsDone]),
          );
        }
      },
    );

    test('отклоняет null в обязательном raw storage-поле', () async {
      final interceptor = _RawRowValueInterceptor();
      await database.close();
      database = AppDatabase(
        observeConfiguredLocalDatabaseConnection(
          openInMemoryLocalDatabase(),
          interceptor,
        ),
      );
      await database.open();
      repository = _repository(database, diagnostics);
      final id = _id(_uuidV7);
      await _insertIntention(
        database,
        id: id.toCanonicalString(),
        title: 'Корректное название',
      );
      interceptor.overrides = const {'title': null};

      await expectLater(
        repository.watchIntention(id),
        emitsInOrder([_isFailure<IntentionCorruptionFailure>(), emitsDone]),
      );
    });

    test('превращает временную SQLite-недоступность в failure и завершает подписку', () async {
      final interceptor = _SelectFailureInterceptor();
      await database.close();
      database = AppDatabase(
        observeConfiguredLocalDatabaseConnection(
          openInMemoryLocalDatabase(),
          interceptor,
        ),
      );
      await database.open();
      repository = _repository(database, diagnostics);
      interceptor.failure = SqliteException(
        extendedResultCode: SqlError.SQLITE_BUSY,
        message: 'CANARY-exception-личные-данные',
      );

      await expectLater(
        repository.watchIntention(_id(_uuidV7)),
        emitsInOrder([_isFailure<IntentionUnavailableFailure>(), emitsDone]),
      );

      interceptor.failure = null;
      await expectLater(
        repository.watchIntention(_id(_uuidV7)),
        emits(_isSuccessfulAbsence()),
      );
    });

    test(
      'превращает IOERR_DATA в corruption failure и завершает подписку',
      () async {
        final interceptor = _SelectFailureInterceptor();
        await database.close();
        database = AppDatabase(
          observeConfiguredLocalDatabaseConnection(
            openInMemoryLocalDatabase(),
            interceptor,
          ),
        );
        await database.open();
        repository = _repository(database, diagnostics);
        interceptor.failure = SqliteException(
          extendedResultCode: SqlExtendedError.SQLITE_IOERR_DATA,
          message: 'CANARY-exception-личные-данные',
        );

        await expectLater(
          repository.watchIntention(_id(_uuidV7)),
          emitsInOrder([_isFailure<IntentionCorruptionFailure>(), emitsDone]),
        );
      },
    );

    test('превращает constraint и неизвестную ошибку чтения в unexpected и завершает подписку', () async {
      final interceptor = _SelectFailureInterceptor();
      await database.close();
      database = AppDatabase(
        observeConfiguredLocalDatabaseConnection(
          openInMemoryLocalDatabase(),
          interceptor,
        ),
      );
      await database.open();
      repository = _repository(database, diagnostics);

      for (final failure in <Object>[
        SqliteException(
          extendedResultCode: SqlExtendedError.SQLITE_CONSTRAINT_UNIQUE,
          message: 'CANARY-exception-личные-данные',
        ),
        SqliteException(
          extendedResultCode: SqlError.SQLITE_CANTOPEN,
          message: 'CANARY-exception-личные-данные',
        ),
        SqliteException(
          extendedResultCode: _sqliteIoerrCorruptFs,
          message: 'CANARY-exception-личные-данные',
        ),
        SqliteException(
          extendedResultCode: SqlError.SQLITE_BUSY | (999 << 8),
          message: 'CANARY-exception-личные-данные',
        ),
        StateError('CANARY-exception-личные-данные'),
      ]) {
        interceptor.failure = failure;
        await expectLater(
          repository.watchIntention(_id(_uuidV7)),
          emitsInOrder([_isFailure<IntentionUnexpectedFailure>(), emitsDone]),
        );
      }
    });
  });
}

const _uuidV4 = '550e8400-e29b-41d4-a716-446655440000';
const _uuidV7 = '018f0b5d-6b2e-7c80-8000-000000000300';
const _sqliteIoerrCorruptFs = 8458;

DriftPersonalGraphRepository _repository(
  AppDatabase database,
  DiagnosticsSink diagnostics,
) => DriftPersonalGraphRepository(
  database,
  _FixedIntentionIdGenerator(_id(_uuidV7)),
  () => DateTime.utc(2026, 9, 2, 10),
  diagnostics,
);

Future<void> _insertIntention(
  AppDatabase database, {
  required String id,
  required String title,
  String? description,
  bool isActionReady = false,
  bool isArchived = false,
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  final created = createdAt ?? DateTime.utc(2026, 9, 2, 10);
  final updated = updatedAt ?? created;
  return database
      .into(database.intentions)
      .insert(
        IntentionsCompanion.insert(
          id: id,
          title: title,
          description: Value(description),
          isActionReady: Value(isActionReady),
          isArchived: Value(isArchived),
          createdAt: created.microsecondsSinceEpoch,
          updatedAt: updated.microsecondsSinceEpoch,
        ),
      );
}

Future<void> _insertRawIntention(
  AppDatabase database, {
  required String id,
  required Object isActionReady,
  required Object isArchived,
  required Object createdAt,
  required Object updatedAt,
  Object? description,
}) => database.customStatement(
  '''
    INSERT INTO intentions (
      id,
      title,
      description,
      is_action_ready,
      is_archived,
      created_at,
      updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?)
  ''',
  [
    id,
    'Корректное название',
    description,
    isActionReady,
    isArchived,
    createdAt,
    updatedAt,
  ],
);

IntentionId _id(String value) => switch (IntentionId.decode(value)) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw ArgumentError.value(value, 'value'),
};

Matcher _isSuccessfulAbsence() =>
    isA<ResultSuccess<GraphSnapshot<Intention?>>>().having(
      (result) => result.value.value,
      'value',
      isNull,
    );

GraphSnapshot<Intention?> _graphSnapshot(
  Result<GraphSnapshot<Intention?>> result,
) {
  expect(result, isA<ResultSuccess<GraphSnapshot<Intention?>>>());
  return (result as ResultSuccess<GraphSnapshot<Intention?>>).value;
}

Matcher _isSuccessfulIntention({
  required IntentionId id,
  required String title,
  String? description,
  IntentionReadiness readiness = IntentionReadiness.notReady,
  IntentionArchiveState archiveState = IntentionArchiveState.active,
  DateTime? createdAt,
  DateTime? updatedAt,
}) => isA<ResultSuccess<GraphSnapshot<Intention?>>>()
    .having((result) => result.value.value, 'value', isNotNull)
    .having((result) => result.value.value!.id, 'id', id)
    .having((result) => result.value.value!.title, 'title', title)
    .having(
      (result) => result.value.value!.description,
      'description',
      description,
    )
    .having((result) => result.value.value!.readiness, 'readiness', readiness)
    .having(
      (result) => result.value.value!.archiveState,
      'archiveState',
      archiveState,
    )
    .having(
      (result) => result.value.value!.createdAt.value,
      'createdAt',
      createdAt ?? DateTime.utc(2026, 9, 2, 10),
    )
    .having(
      (result) => result.value.value!.updatedAt.value,
      'updatedAt',
      updatedAt ?? createdAt ?? DateTime.utc(2026, 9, 2, 10),
    );

Matcher _isFailure<TFailure extends IntentionFailure>() =>
    isA<ResultFailure<GraphSnapshot<Intention?>>>().having(
      (result) => result.failure,
      'failure',
      isA<TFailure>(),
    );

final class _FixedIntentionIdGenerator implements IntentionIdGenerator {
  _FixedIntentionIdGenerator(this.id);

  final IntentionId id;

  @override
  IntentionId generate() => id;
}

final class _SelectFailureInterceptor extends LocalDatabaseConnectionObserver {
  Object? failure;

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (statement.operation != LocalDatabaseSqlOperation.select) return;
    final failure = this.failure;
    if (failure != null) throw failure;
  }
}

final class _RawRowValueInterceptor extends LocalDatabaseConnectionObserver {
  Map<String, Object?>? overrides;

  @override
  List<Map<String, Object?>> afterSelect(
    LocalDatabaseSqlStatement statement,
    List<Map<String, Object?>> rows,
  ) {
    final overrides = this.overrides;
    return overrides == null
        ? rows
        : [
            for (final row in rows) {...row, ...overrides},
          ];
  }
}
