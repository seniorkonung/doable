import 'dart:async';

import 'package:doable/src/data/local/app_database.dart' hide Intention;
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/data/drift_intention_repository.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../support/in_memory_diagnostics_sink.dart';

void main() {
  late AppDatabase database;
  late InMemoryDiagnosticsSink diagnostics;
  late DriftIntentionRepository repository;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await database.open();
    diagnostics = InMemoryDiagnosticsSink();
    repository = _repository(database, diagnostics);
  });

  tearDown(() => database.close());

  group('DriftIntentionRepository.watchById', () {
    test('публикует начальное подтверждённое отсутствие', () async {
      final result = await repository.watchById(_id(_uuidV7)).first;

      expect(result, isA<ResultSuccess<Intention?>>());
      expect((result as ResultSuccess<Intention?>).value, isNull);
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
        final events = StreamIterator(repository.watchById(id));
        addTearDown(events.cancel);

        expect(await events.moveNext(), isTrue);
        expect(events.current, _isSuccessfulAbsence());

        await database.transaction(() async {
          await _insertIntention(
            database,
            id: id.toCanonicalString(),
            title: 'Купить молоко',
            description: 'В фермерском магазине',
            isActionReady: true,
            isArchived: true,
            createdAt: DateTime.utc(2026, 9, 2, 10),
            updatedAt: DateTime.utc(2026, 9, 2, 11),
          );
        });

        expect(await events.moveNext(), isTrue);
        expect(
          events.current,
          _isSuccessfulIntention(
            id: id,
            title: 'Купить молоко',
            description: 'В фермерском магазине',
            readiness: IntentionReadiness.ready,
            archiveState: IntentionArchiveState.archived,
            createdAt: DateTime.utc(2026, 9, 2, 10),
            updatedAt: DateTime.utc(2026, 9, 2, 11),
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
        repository = DriftIntentionRepository(
          database,
          UuidV7IntentionIdGenerator(),
          () => DateTime.utc(2026, 9, 3, 12),
          diagnostics,
        );
        final events = StreamIterator(repository.watchById(id));
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

        expect(result, isA<ResultSuccess<IntentionCommandSuccess>>());
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
      final events = StreamIterator(repository.watchById(id));
      addTearDown(events.cancel);

      expect(await events.moveNext(), isTrue);
      expect(
        events.current,
        _isSuccessfulIntention(id: id, title: 'Прочитать книгу'),
      );

      await database.transaction(() async {
        await (database.delete(
          database.intentions,
        )..where((row) => row.id.equals(id.toCanonicalString()))).go();
      });

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
            await repository.watchById(fixture.id).first,
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
          (
            id: _id('018f0b5d-6b2e-7c80-8000-000000000304'),
            title: 'Нарушенный порядок времени',
            description: null,
            createdAt: DateTime.utc(2026, 9, 2, 11),
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
            repository.watchById(fixture.id),
            emitsInOrder([_isFailure<IntentionCorruptionFailure>(), emitsDone]),
          );
        }
      },
    );

    test('превращает временную SQLite-недоступность в failure и завершает подписку', () async {
      final interceptor = _SelectFailureInterceptor();
      await database.close();
      database = AppDatabase(
        NativeDatabase.memory().interceptWith(interceptor),
      );
      await database.open();
      repository = _repository(database, diagnostics);
      interceptor.failure = SqliteException(
        extendedResultCode: SqlError.SQLITE_BUSY,
        message: 'CANARY-exception-личные-данные',
      );

      await expectLater(
        repository.watchById(_id(_uuidV7)),
        emitsInOrder([_isFailure<IntentionUnavailableFailure>(), emitsDone]),
      );

      interceptor.failure = null;
      await expectLater(
        repository.watchById(_id(_uuidV7)),
        emits(_isSuccessfulAbsence()),
      );
    });

    test(
      'превращает IOERR_DATA в corruption failure и завершает подписку',
      () async {
        final interceptor = _SelectFailureInterceptor();
        await database.close();
        database = AppDatabase(
          NativeDatabase.memory().interceptWith(interceptor),
        );
        await database.open();
        repository = _repository(database, diagnostics);
        interceptor.failure = SqliteException(
          extendedResultCode: SqlExtendedError.SQLITE_IOERR_DATA,
          message: 'CANARY-exception-личные-данные',
        );

        await expectLater(
          repository.watchById(_id(_uuidV7)),
          emitsInOrder([_isFailure<IntentionCorruptionFailure>(), emitsDone]),
        );
      },
    );

    test('превращает constraint и неизвестную ошибку чтения в unexpected и завершает подписку', () async {
      final interceptor = _SelectFailureInterceptor();
      await database.close();
      database = AppDatabase(
        NativeDatabase.memory().interceptWith(interceptor),
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
          repository.watchById(_id(_uuidV7)),
          emitsInOrder([_isFailure<IntentionUnexpectedFailure>(), emitsDone]),
        );
      }
    });
  });
}

const _uuidV4 = '550e8400-e29b-41d4-a716-446655440000';
const _uuidV7 = '018f0b5d-6b2e-7c80-8000-000000000300';
const _sqliteIoerrCorruptFs = 8458;

DriftIntentionRepository _repository(
  AppDatabase database,
  DiagnosticsSink diagnostics,
) => DriftIntentionRepository(
  database,
  UuidV7IntentionIdGenerator(),
  () => DateTime.utc(2026, 9, 2),
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
          titleSearchKey: title.toLowerCase(),
          description: Value(description),
          isActionReady: Value(isActionReady),
          isArchived: Value(isArchived),
          createdAt: created.microsecondsSinceEpoch,
          updatedAt: updated.microsecondsSinceEpoch,
        ),
      );
}

IntentionId _id(String value) => switch (IntentionId.decode(value)) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw ArgumentError.value(value, 'value'),
};

Matcher _isSuccessfulAbsence() => isA<ResultSuccess<Intention?>>().having(
  (result) => result.value,
  'value',
  isNull,
);

Matcher _isSuccessfulIntention({
  required IntentionId id,
  required String title,
  String? description,
  IntentionReadiness readiness = IntentionReadiness.notReady,
  IntentionArchiveState archiveState = IntentionArchiveState.active,
  DateTime? createdAt,
  DateTime? updatedAt,
}) => isA<ResultSuccess<Intention?>>()
    .having((result) => result.value, 'value', isNotNull)
    .having((result) => result.value!.id, 'id', id)
    .having((result) => result.value!.title, 'title', title)
    .having((result) => result.value!.description, 'description', description)
    .having((result) => result.value!.readiness, 'readiness', readiness)
    .having(
      (result) => result.value!.archiveState,
      'archiveState',
      archiveState,
    )
    .having(
      (result) => result.value!.createdAt.value,
      'createdAt',
      createdAt ?? DateTime.utc(2026, 9, 2, 10),
    )
    .having(
      (result) => result.value!.updatedAt.value,
      'updatedAt',
      updatedAt ?? createdAt ?? DateTime.utc(2026, 9, 2, 10),
    );

Matcher _isFailure<TFailure extends IntentionFailure>() =>
    isA<ResultFailure<Intention?>>().having(
      (result) => result.failure,
      'failure',
      isA<TFailure>(),
    );

final class _SelectFailureInterceptor extends QueryInterceptor {
  Object? failure;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    final failure = this.failure;
    return failure == null
        ? super.runSelect(executor, statement, args)
        : Future.error(failure);
  }
}
