import 'package:doable/src/data/local/app_database.dart' hide Intention;
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_repository.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/data/drift_intention_repository.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/shared/diagnostics/developer_diagnostics_sink.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../support/in_memory_diagnostics_sink.dart';

void main() {
  late AppDatabase database;
  late InMemoryDiagnosticsSink diagnostics;
  late _DeterministicIntentionIdGenerator idGenerator;
  late _DeterministicClock clock;
  late DriftIntentionRepository repository;
  late _WriteTrace writeTrace;

  setUp(() async {
    writeTrace = _WriteTrace();
    database = AppDatabase(NativeDatabase.memory().interceptWith(writeTrace));
    await database.open();
    diagnostics = InMemoryDiagnosticsSink();
    idGenerator = _DeterministicIntentionIdGenerator([_id(_firstUuid)]);
    clock = _DeterministicClock([DateTime.utc(2026, 9, 3, 12)]);
    repository = DriftIntentionRepository(
      database,
      idGenerator,
      clock.call,
      diagnostics,
    );
  });

  tearDown(() => database.close());

  group('DriftIntentionRepository.execute', () {
    test('создаёт active not-ready намерение с нормализованными данными и единым UTC-временем', () async {
      final result = await repository.execute(
        const CreateIntention(
          title: '  Купить  молоко  ',
          description: '  В фермерском магазине\n',
        ),
      );

      final saved = _saved(result);
      expect(saved.id, _id(_firstUuid));
      expect(saved.title, 'Купить  молоко');
      expect(saved.description, '  В фермерском магазине\n');
      expect(saved.readiness, IntentionReadiness.notReady);
      expect(saved.archiveState, IntentionArchiveState.active);
      expect(saved.createdAt.value, DateTime.utc(2026, 9, 3, 12));
      expect(saved.createdAt.value.isUtc, isTrue);
      expect(saved.updatedAt, saved.createdAt);
      expect(idGenerator.generated, [_id(_firstUuid)]);
      expect(clock.calls, 1);
      expect(diagnostics.events, [
        _successfulCommand(IntentionCommandDiagnosticsType.create),
      ]);
    });

    test('допускает два намерения с одинаковым названием и разными идентификаторами', () async {
      final secondId = _id(_secondUuid);
      idGenerator = _DeterministicIntentionIdGenerator([
        _id(_firstUuid),
        secondId,
      ]);
      clock = _DeterministicClock([
        DateTime.utc(2026, 9, 3, 12),
        DateTime.utc(2026, 9, 3, 13),
      ]);
      repository = DriftIntentionRepository(
        database,
        idGenerator,
        clock.call,
        diagnostics,
      );

      final first = _saved(
        await repository.execute(
          const CreateIntention(title: 'Быть здоровым', description: null),
        ),
      );
      final second = _saved(
        await repository.execute(
          const CreateIntention(title: 'Быть здоровым', description: null),
        ),
      );

      expect(first.id, _id(_firstUuid));
      expect(second.id, secondId);
      expect(first.id, isNot(second.id));
      expect(await database.select(database.intentions).get(), hasLength(2));
    });

    test(
      'отклоняет недопустимый Unicode title до генерации ID и записи',
      () async {
        final title = List.filled(256, '👩🏽‍💻').join();

        final result = await repository.execute(
          CreateIntention(title: title, description: null),
        );

        expect(result, _failure<IntentionValidationFailure>());
        expect(idGenerator.generated, isEmpty);
        expect(clock.calls, 0);
        expect(await database.select(database.intentions).get(), isEmpty);
        expect(diagnostics.events, [
          _failedCommand(
            IntentionCommandDiagnosticsType.create,
            DiagnosticsFailureCode.validation,
          ),
        ]);
      },
    );

    test('принимает title из 255 Unicode-графем', () async {
      final title = List.filled(255, '👩🏽‍💻').join();

      final result = await repository.execute(
        CreateIntention(title: title, description: '  \n\t  '),
      );

      final saved = _saved(result);
      expect(saved.title, title);
      expect(saved.description, isNull);
    });

    test('возвращает conflict при collision нового первичного ключа и не перезаписывает строку', () async {
      await _insertIntention(
        database,
        id: _firstUuid,
        title: 'Существующее намерение',
        createdAt: DateTime.utc(2026, 9, 2, 10),
      );

      final result = await repository.execute(
        const CreateIntention(title: 'Новое намерение', description: null),
      );

      expect(result, _failure<IntentionConflictFailure>());
      final row = await (database.select(
        database.intentions,
      )..where((row) => row.id.equals(_firstUuid))).getSingle();
      expect(row.title, 'Существующее намерение');
      expect(
        row.createdAt,
        DateTime.utc(2026, 9, 2, 10).microsecondsSinceEpoch,
      );
      expect(diagnostics.events, [
        _failedCommand(
          IntentionCommandDiagnosticsType.create,
          DiagnosticsFailureCode.conflict,
        ),
      ]);
    });

    test('изменяет active и archived намерения, сохраняя их остальные подтверждённые данные', () async {
      final fixtures = [
        (
          id: _id(_firstUuid),
          isActionReady: false,
          isArchived: false,
          createdAt: DateTime.utc(2026, 9, 2, 10),
        ),
        (
          id: _id(_secondUuid),
          isActionReady: true,
          isArchived: true,
          createdAt: DateTime.utc(2026, 9, 2, 11),
        ),
      ];
      for (final fixture in fixtures) {
        await _insertIntention(
          database,
          id: fixture.id.toCanonicalString(),
          title: 'Исходное название',
          description: 'Исходное описание',
          isActionReady: fixture.isActionReady,
          isArchived: fixture.isArchived,
          createdAt: fixture.createdAt,
        );
      }

      clock = _DeterministicClock([
        DateTime.utc(2026, 9, 3, 12),
        DateTime.utc(2026, 9, 3, 13),
      ]);
      repository = DriftIntentionRepository(
        database,
        idGenerator,
        clock.call,
        diagnostics,
      );

      for (var index = 0; index < fixtures.length; index++) {
        final fixture = fixtures[index];
        final result = await repository.execute(
          UpdateIntention(
            id: fixture.id,
            title: '  Обновлённое  название  ',
            description: '  Новое описание\n',
          ),
        );

        final saved = _saved(result);
        expect(saved.id, fixture.id);
        expect(saved.title, 'Обновлённое  название');
        expect(saved.description, '  Новое описание\n');
        expect(
          saved.readiness,
          fixture.isActionReady
              ? IntentionReadiness.ready
              : IntentionReadiness.notReady,
        );
        expect(
          saved.archiveState,
          fixture.isArchived
              ? IntentionArchiveState.archived
              : IntentionArchiveState.active,
        );
        expect(saved.createdAt.value, fixture.createdAt);
        expect(saved.updatedAt.value, DateTime.utc(2026, 9, 3, 12 + index));
      }

      final updatedRows = await database.select(database.intentions).get();
      expect(
        updatedRows.map((row) => row.titleSearchKey),
        everyElement('обновлённое  название'),
      );
      expect(diagnostics.events, [
        _successfulCommand(IntentionCommandDiagnosticsType.update),
        _successfulCommand(IntentionCommandDiagnosticsType.update),
      ]);
    });

    test(
      'не выполняет запись и возвращает прежнее намерение при no-op update',
      () async {
        final id = _id(_firstUuid);
        final createdAt = DateTime.utc(2026, 9, 2, 10);
        await _insertIntention(
          database,
          id: id.toCanonicalString(),
          title: 'Неизменное название',
          description: 'Неизменное описание',
          isActionReady: true,
          isArchived: true,
          createdAt: createdAt,
        );
        clock = _DeterministicClock([DateTime.utc(2026, 9, 3, 12)]);
        repository = DriftIntentionRepository(
          database,
          idGenerator,
          clock.call,
          diagnostics,
        );
        writeTrace.updateStatements.clear();

        final result = await repository.execute(
          UpdateIntention(
            id: id,
            title: 'Неизменное название',
            description: 'Неизменное описание',
          ),
        );

        final saved = _saved(result);
        expect(saved.updatedAt.value, createdAt);
        expect(saved.createdAt.value, createdAt);
        expect(clock.calls, 0);
        expect(writeTrace.updateStatements, isEmpty);
      },
    );

    test(
      'сохраняет равные и убывающие показания часов для фактических изменений',
      () async {
        final id = _id(_firstUuid);
        final createdAt = DateTime.utc(2026, 9, 3, 12);
        final previouslyUpdatedAt = DateTime.utc(2026, 9, 3, 13);
        await _insertIntention(
          database,
          id: id.toCanonicalString(),
          title: 'Исходное название',
          createdAt: createdAt,
          updatedAt: previouslyUpdatedAt,
        );
        clock = _DeterministicClock([
          previouslyUpdatedAt,
          createdAt,
          DateTime.utc(2026, 9, 3, 11),
        ]);
        repository = DriftIntentionRepository(
          database,
          idGenerator,
          clock.call,
          diagnostics,
        );
        writeTrace.updateStatements.clear();

        final titleUpdated = _saved(
          await repository.execute(
            UpdateIntention(
              id: id,
              title: 'Обновлённое название',
              description: null,
            ),
          ),
        );
        final readinessUpdated = _saved(
          await repository.execute(EnableIntentionReadiness(id)),
        );
        final archiveUpdated = _saved(
          await repository.execute(ArchiveIntention(id)),
        );

        expect(titleUpdated.updatedAt.value, previouslyUpdatedAt);
        expect(readinessUpdated.updatedAt.value, createdAt);
        expect(archiveUpdated.updatedAt.value, DateTime.utc(2026, 9, 3, 11));
        expect(archiveUpdated.createdAt.value, createdAt);
        expect(clock.calls, 3);
        expect(writeTrace.updateStatements, hasLength(3));
        final stored = await (database.select(
          database.intentions,
        )..where((row) => row.id.equals(id.toCanonicalString()))).getSingle();
        expect(
          stored.updatedAt,
          DateTime.utc(2026, 9, 3, 11).microsecondsSinceEpoch,
        );
      },
    );

    test('оставляет прежнее намерение при недопустимом изменении', () async {
      final id = _id(_firstUuid);
      final createdAt = DateTime.utc(2026, 9, 2, 10);
      await _insertIntention(
        database,
        id: id.toCanonicalString(),
        title: 'Исходное название',
        description: 'Исходное описание',
        createdAt: createdAt,
      );
      writeTrace.updateStatements.clear();

      final result = await repository.execute(
        UpdateIntention(id: id, title: '  \n\t  ', description: null),
      );

      expect(result, _failure<IntentionValidationFailure>());
      expect(clock.calls, 0);
      expect(writeTrace.updateStatements, isEmpty);
      final row = await (database.select(
        database.intentions,
      )..where((row) => row.id.equals(id.toCanonicalString()))).getSingle();
      expect(row.title, 'Исходное название');
      expect(row.description, 'Исходное описание');
      expect(row.updatedAt, createdAt.microsecondsSinceEpoch);
    });

    test(
      'возвращает not-found при изменении отсутствующего намерения',
      () async {
        final result = await repository.execute(
          UpdateIntention(
            id: _id(_firstUuid),
            title: 'Новое название',
            description: null,
          ),
        );

        expect(result, _failure<IntentionNotFoundFailure>());
        expect(clock.calls, 0);
        expect(diagnostics.events, [
          _failedCommand(
            IntentionCommandDiagnosticsType.update,
            DiagnosticsFailureCode.notFound,
          ),
        ]);
      },
    );

    test(
      'физически удаляет active и archived намерения из всех публичных чтений',
      () async {
        final fixtures = [
          (id: _id(_firstUuid), isArchived: false),
          (id: _id(_secondUuid), isArchived: true),
        ];
        for (final fixture in fixtures) {
          await _insertIntention(
            database,
            id: fixture.id.toCanonicalString(),
            title: 'Удаляемое намерение ${fixture.id.toCanonicalString()}',
            isArchived: fixture.isArchived,
            createdAt: DateTime.utc(2026, 9, 2, 10),
          );

          final result = await repository.execute(DeleteIntention(fixture.id));

          expect(result, _deleted(fixture.id));
          expect(
            _watched(await repository.watchById(fixture.id).first),
            isNull,
          );
          for (final scope in IntentionScope.values) {
            final page = await repository.getCatalogPage(
              IntentionCatalogQuery(
                scope: scope,
                titleFilter: null,
                order: IntentionCatalogOrder.createdAtDescending,
                pageSize: 100,
              ),
            );
            expect(
              _catalogItems(page).map((summary) => summary.id),
              isNot(contains(fixture.id)),
            );
          }
        }

        expect(
          diagnostics.events.whereType<IntentionCommandDiagnosticsEvent>(),
          [
            _successfulCommand(IntentionCommandDiagnosticsType.delete),
            _successfulCommand(IntentionCommandDiagnosticsType.delete),
          ],
        );
      },
    );

    test(
      'возвращает not-found при удалении отсутствующего намерения',
      () async {
        final result = await repository.execute(
          DeleteIntention(_id(_firstUuid)),
        );

        expect(result, _failure<IntentionNotFoundFailure>());
        expect(diagnostics.events, [
          _failedCommand(
            IntentionCommandDiagnosticsType.delete,
            DiagnosticsFailureCode.notFound,
          ),
        ]);
      },
    );

    test('выполняет матрицу переходов readiness и архива без изменения несвязанных данных', () async {
      final transitions =
          <
            ({
              IntentionCommand Function(IntentionId) command,
              IntentionCommandDiagnosticsType commandType,
              IntentionReadiness? readiness,
              IntentionArchiveState? archiveState,
              List<
                ({
                  IntentionReadiness readiness,
                  IntentionArchiveState archiveState,
                })
              >
              fixtures,
            })
          >[
            (
              command: (IntentionId id) => EnableIntentionReadiness(id),
              commandType: IntentionCommandDiagnosticsType.enableReadiness,
              readiness: IntentionReadiness.ready,
              archiveState: null,
              fixtures: [
                (
                  readiness: IntentionReadiness.notReady,
                  archiveState: IntentionArchiveState.active,
                ),
                (
                  readiness: IntentionReadiness.notReady,
                  archiveState: IntentionArchiveState.archived,
                ),
                (
                  readiness: IntentionReadiness.ready,
                  archiveState: IntentionArchiveState.active,
                ),
                (
                  readiness: IntentionReadiness.ready,
                  archiveState: IntentionArchiveState.archived,
                ),
              ],
            ),
            (
              command: (IntentionId id) => DisableIntentionReadiness(id),
              commandType: IntentionCommandDiagnosticsType.disableReadiness,
              readiness: IntentionReadiness.notReady,
              archiveState: null,
              fixtures: [
                (
                  readiness: IntentionReadiness.ready,
                  archiveState: IntentionArchiveState.active,
                ),
                (
                  readiness: IntentionReadiness.ready,
                  archiveState: IntentionArchiveState.archived,
                ),
                (
                  readiness: IntentionReadiness.notReady,
                  archiveState: IntentionArchiveState.active,
                ),
                (
                  readiness: IntentionReadiness.notReady,
                  archiveState: IntentionArchiveState.archived,
                ),
              ],
            ),
            (
              command: (IntentionId id) => ArchiveIntention(id),
              commandType: IntentionCommandDiagnosticsType.archive,
              readiness: null,
              archiveState: IntentionArchiveState.archived,
              fixtures: [
                (
                  readiness: IntentionReadiness.notReady,
                  archiveState: IntentionArchiveState.active,
                ),
                (
                  readiness: IntentionReadiness.ready,
                  archiveState: IntentionArchiveState.active,
                ),
                (
                  readiness: IntentionReadiness.notReady,
                  archiveState: IntentionArchiveState.archived,
                ),
                (
                  readiness: IntentionReadiness.ready,
                  archiveState: IntentionArchiveState.archived,
                ),
              ],
            ),
            (
              command: (IntentionId id) => RestoreIntention(id),
              commandType: IntentionCommandDiagnosticsType.restore,
              readiness: null,
              archiveState: IntentionArchiveState.active,
              fixtures: [
                (
                  readiness: IntentionReadiness.notReady,
                  archiveState: IntentionArchiveState.archived,
                ),
                (
                  readiness: IntentionReadiness.ready,
                  archiveState: IntentionArchiveState.archived,
                ),
                (
                  readiness: IntentionReadiness.notReady,
                  archiveState: IntentionArchiveState.active,
                ),
                (
                  readiness: IntentionReadiness.ready,
                  archiveState: IntentionArchiveState.active,
                ),
              ],
            ),
          ];
      final transitionTimes = [
        for (var hour = 10; hour < 18; hour++) DateTime.utc(2026, 9, 3, hour),
      ];
      clock = _DeterministicClock(transitionTimes);
      repository = DriftIntentionRepository(
        database,
        idGenerator,
        clock.call,
        diagnostics,
      );

      var sequence = 1;
      var transitionCount = 0;
      for (final transition in transitions) {
        for (final fixture in transition.fixtures) {
          final id = _idForSequence(sequence++);
          final title = 'Название $sequence';
          final description = 'Описание $sequence';
          final createdAt = DateTime.utc(2026, 9, 2, 10, sequence);
          await _insertIntention(
            database,
            id: id.toCanonicalString(),
            title: title,
            description: description,
            isActionReady: fixture.readiness == IntentionReadiness.ready,
            isArchived: fixture.archiveState == IntentionArchiveState.archived,
            createdAt: createdAt,
          );
          final expectedReadiness = transition.readiness ?? fixture.readiness;
          final expectedArchiveState =
              transition.archiveState ?? fixture.archiveState;
          final changesState =
              expectedReadiness != fixture.readiness ||
              expectedArchiveState != fixture.archiveState;
          final updatesBefore = writeTrace.updateStatements.length;

          final saved = _saved(
            await repository.execute(transition.command(id)),
          );

          expect(saved.id, id);
          expect(saved.title, title);
          expect(saved.description, description);
          expect(saved.createdAt.value, createdAt);
          expect(saved.readiness, expectedReadiness);
          expect(saved.archiveState, expectedArchiveState);
          if (changesState) {
            expect(saved.updatedAt.value, transitionTimes[transitionCount++]);
            expect(writeTrace.updateStatements, hasLength(updatesBefore + 1));
          } else {
            expect(saved.updatedAt.value, createdAt);
            expect(writeTrace.updateStatements, hasLength(updatesBefore));
          }

          final row = await (database.select(
            database.intentions,
          )..where((row) => row.id.equals(id.toCanonicalString()))).getSingle();
          expect(row.title, title);
          expect(row.description, description);
          expect(
            row.isActionReady,
            expectedReadiness == IntentionReadiness.ready,
          );
          expect(
            row.isArchived,
            expectedArchiveState == IntentionArchiveState.archived,
          );
          expect(row.createdAt, createdAt.microsecondsSinceEpoch);
          expect(row.updatedAt, saved.updatedAt.value.microsecondsSinceEpoch);
        }
      }

      expect(transitionCount, transitionTimes.length);
      expect(clock.calls, transitionTimes.length);
      expect(
        diagnostics.events,
        everyElement(
          isA<IntentionCommandDiagnosticsEvent>().having(
            (event) => event.status,
            'status',
            isA<DiagnosticsSucceeded>(),
          ),
        ),
      );
      expect(
        diagnostics.events.whereType<IntentionCommandDiagnosticsEvent>().map(
          (event) => event.commandType,
        ),
        [
          for (final transition in transitions)
            for (final _ in transition.fixtures) transition.commandType,
        ],
      );
    });

    test(
      'возвращает not-found для каждого отсутствующего state transition',
      () async {
        final id = _id(_firstUuid);
        final transitions =
            <
              ({
                IntentionCommand Function(IntentionId) command,
                IntentionCommandDiagnosticsType commandType,
              })
            >[
              (
                command: (IntentionId id) => EnableIntentionReadiness(id),
                commandType: IntentionCommandDiagnosticsType.enableReadiness,
              ),
              (
                command: (IntentionId id) => DisableIntentionReadiness(id),
                commandType: IntentionCommandDiagnosticsType.disableReadiness,
              ),
              (
                command: (IntentionId id) => ArchiveIntention(id),
                commandType: IntentionCommandDiagnosticsType.archive,
              ),
              (
                command: (IntentionId id) => RestoreIntention(id),
                commandType: IntentionCommandDiagnosticsType.restore,
              ),
            ];

        for (final transition in transitions) {
          expect(
            await repository.execute(transition.command(id)),
            _failure<IntentionNotFoundFailure>(),
          );
        }

        expect(clock.calls, 0);
        expect(writeTrace.updateStatements, isEmpty);
        expect(diagnostics.events, [
          for (final transition in transitions)
            _failedCommand(
              transition.commandType,
              DiagnosticsFailureCode.notFound,
            ),
        ]);
      },
    );

    test(
      'изолирует параллельные state transitions одного и разных намерений',
      () async {
        final firstId = _id(_firstUuid);
        final secondId = _id(_secondUuid);
        final createdAt = DateTime.utc(2026, 9, 2, 10);
        await _insertIntention(
          database,
          id: firstId.toCanonicalString(),
          title: 'Первое намерение',
          description: 'Первое описание',
          createdAt: createdAt,
        );
        await _insertIntention(
          database,
          id: secondId.toCanonicalString(),
          title: 'Второе намерение',
          description: 'Второе описание',
          isActionReady: true,
          isArchived: true,
          createdAt: createdAt,
        );
        clock = _DeterministicClock([
          DateTime.utc(2026, 9, 3, 10),
          DateTime.utc(2026, 9, 3, 11),
          DateTime.utc(2026, 9, 3, 12),
          DateTime.utc(2026, 9, 3, 13),
        ]);
        repository = DriftIntentionRepository(
          database,
          idGenerator,
          clock.call,
          diagnostics,
        );

        final results = await Future.wait([
          repository.execute(EnableIntentionReadiness(firstId)),
          repository.execute(ArchiveIntention(firstId)),
          repository.execute(DisableIntentionReadiness(secondId)),
          repository.execute(RestoreIntention(secondId)),
        ]);

        final firstReadiness = _saved(results[0]);
        final firstArchive = _saved(results[1]);
        final secondReadiness = _saved(results[2]);
        final secondRestore = _saved(results[3]);
        expect(firstReadiness.id, firstId);
        expect(firstReadiness.readiness, IntentionReadiness.ready);
        expect(firstArchive.id, firstId);
        expect(firstArchive.archiveState, IntentionArchiveState.archived);
        expect(secondReadiness.id, secondId);
        expect(secondReadiness.readiness, IntentionReadiness.notReady);
        expect(secondRestore.id, secondId);
        expect(secondRestore.archiveState, IntentionArchiveState.active);

        final first = _watched(await repository.watchById(firstId).first);
        final second = _watched(await repository.watchById(secondId).first);
        expect(first?.title, 'Первое намерение');
        expect(first?.description, 'Первое описание');
        expect(first?.readiness, IntentionReadiness.ready);
        expect(first?.archiveState, IntentionArchiveState.archived);
        expect(second?.title, 'Второе намерение');
        expect(second?.description, 'Второе описание');
        expect(second?.readiness, IntentionReadiness.notReady);
        expect(second?.archiveState, IntentionArchiveState.active);
        expect(clock.calls, 4);
      },
    );

    test('сохраняет success create, update и no-op при отказе diagnostics после commit', () async {
      var writerWasCalled = false;
      final diagnosticsWithFailingWriter = DeveloperDiagnosticsSink((_) {
        writerWasCalled = true;
        throw StateError('CANARY-diagnostics-writer-failure');
      });
      final id = _id(_firstUuid);
      clock = _DeterministicClock([
        DateTime.utc(2026, 9, 3, 12),
        DateTime.utc(2026, 9, 3, 13),
      ]);
      repository = DriftIntentionRepository(
        database,
        idGenerator,
        clock.call,
        diagnosticsWithFailingWriter,
      );

      final created = _saved(
        await repository.execute(
          const CreateIntention(
            title: 'Исходное название',
            description: 'Исходное описание',
          ),
        ),
      );
      final updated = _saved(
        await repository.execute(
          UpdateIntention(
            id: id,
            title: 'Обновлённое название',
            description: 'Обновлённое описание',
          ),
        ),
      );
      final noOp = _saved(
        await repository.execute(
          UpdateIntention(
            id: id,
            title: 'Обновлённое название',
            description: 'Обновлённое описание',
          ),
        ),
      );

      expect(created.id, id);
      expect(updated.title, 'Обновлённое название');
      expect(noOp.id, updated.id);
      expect(noOp.title, updated.title);
      expect(noOp.description, updated.description);
      expect(noOp.createdAt, updated.createdAt);
      expect(noOp.updatedAt, updated.updatedAt);
      final row = await (database.select(
        database.intentions,
      )..where((row) => row.id.equals(id.toCanonicalString()))).getSingle();
      expect(row.titleSearchKey, 'обновлённое название');
      final snapshot = await repository.watchById(id).first;
      expect(snapshot, isA<ResultSuccess<Intention?>>());
      final watched = (snapshot as ResultSuccess<Intention?>).value;
      expect(watched?.id, id);
      expect(watched?.title, updated.title);
      expect(watched?.description, updated.description);
      expect(watched?.createdAt, updated.createdAt);
      expect(watched?.updatedAt, updated.updatedAt);
      expect(writerWasCalled, isTrue);
    });

    test(
      'сохраняет typed storage failure при отказе diagnostics writer',
      () async {
        final storageFailure = _InsertFailureInterceptor(
          SqliteException(
            extendedResultCode: SqlError.SQLITE_BUSY,
            message: 'CANARY-storage-failure',
          ),
        );
        var writerWasCalled = false;
        final diagnosticsWithFailingWriter = DeveloperDiagnosticsSink((_) {
          writerWasCalled = true;
          throw StateError('CANARY-diagnostics-writer-failure');
        });
        await database.close();
        database = AppDatabase(
          NativeDatabase.memory().interceptWith(storageFailure),
        );
        await database.open();
        repository = DriftIntentionRepository(
          database,
          idGenerator,
          clock.call,
          diagnosticsWithFailingWriter,
        );

        final result = await repository.execute(
          const CreateIntention(title: 'Намерение', description: null),
        );

        expect(result, _failure<IntentionUnavailableFailure>());
        expect(await database.select(database.intentions).get(), isEmpty);
        expect(writerWasCalled, isTrue);
      },
    );
  });
}

const _firstUuid = '018f0b5d-6b2e-7c80-8000-000000000401';
const _secondUuid = '018f0b5d-6b2e-7c80-8000-000000000402';

Intention _saved(Result<IntentionCommandSuccess> result) {
  expect(result, isA<ResultSuccess<IntentionCommandSuccess>>());
  final success = (result as ResultSuccess<IntentionCommandSuccess>).value;
  expect(success, isA<IntentionSaved>());
  return (success as IntentionSaved).intention;
}

Matcher _failure<TFailure extends IntentionFailure>() =>
    isA<ResultFailure<IntentionCommandSuccess>>().having(
      (result) => result.failure,
      'failure',
      isA<TFailure>(),
    );

Matcher _successfulCommand(IntentionCommandDiagnosticsType commandType) =>
    isA<IntentionCommandDiagnosticsEvent>()
        .having((event) => event.commandType, 'commandType', commandType)
        .having((event) => event.status, 'status', isA<DiagnosticsSucceeded>());

Matcher _failedCommand(
  IntentionCommandDiagnosticsType commandType,
  DiagnosticsFailureCode failureCode,
) => isA<IntentionCommandDiagnosticsEvent>()
    .having((event) => event.commandType, 'commandType', commandType)
    .having(
      (event) => event.status,
      'status',
      isA<DiagnosticsFailed>().having(
        (status) => status.code,
        'code',
        failureCode,
      ),
    );

IntentionId _id(String value) => switch (IntentionId.decode(value)) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw ArgumentError.value(value, 'value'),
};

IntentionId _idForSequence(int value) =>
    _id('018f0b5d-6b2e-7c80-8000-${value.toRadixString(16).padLeft(12, '0')}');

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

List<IntentionSummary> _catalogItems(Result<IntentionCatalogPage> result) {
  expect(result, isA<ResultSuccess<IntentionCatalogPage>>());
  return (result as ResultSuccess<IntentionCatalogPage>).value.items;
}

Future<void> _insertIntention(
  AppDatabase database, {
  required String id,
  required String title,
  String? description,
  bool isActionReady = false,
  bool isArchived = false,
  required DateTime createdAt,
  DateTime? updatedAt,
}) => database
    .into(database.intentions)
    .insert(
      IntentionsCompanion.insert(
        id: id,
        title: title,
        titleSearchKey: title.toLowerCase(),
        description: Value(description),
        isActionReady: Value(isActionReady),
        isArchived: Value(isArchived),
        createdAt: createdAt.microsecondsSinceEpoch,
        updatedAt: (updatedAt ?? createdAt).microsecondsSinceEpoch,
      ),
    );

final class _DeterministicIntentionIdGenerator implements IntentionIdGenerator {
  _DeterministicIntentionIdGenerator(Iterable<IntentionId> ids)
    : _ids = List.unmodifiable(ids);

  final List<IntentionId> _ids;
  final List<IntentionId> generated = [];

  @override
  IntentionId generate() {
    if (generated.length == _ids.length) {
      throw StateError('Последовательность идентификаторов исчерпана.');
    }
    final id = _ids[generated.length];
    generated.add(id);
    return id;
  }
}

final class _DeterministicClock {
  _DeterministicClock(Iterable<DateTime> values)
    : _values = List.unmodifiable(values);

  final List<DateTime> _values;
  var calls = 0;

  DateTime call() {
    if (calls == _values.length) {
      throw StateError('Последовательность времени исчерпана.');
    }
    return _values[calls++];
  }
}

final class _WriteTrace extends QueryInterceptor {
  final List<String> updateStatements = [];

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    updateStatements.add(statement);
    return super.runUpdate(executor, statement, args);
  }
}

final class _InsertFailureInterceptor extends QueryInterceptor {
  _InsertFailureInterceptor(this.failure);

  final Object failure;

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => Future<int>.error(failure);
}
