import 'dart:collection';
import 'dart:convert';

import 'package:doable/src/data/local/app_database.dart' hide Intention;
import 'package:doable/src/favorite/application/favorite_intentions.dart';
import 'package:doable/src/favorite/application/favorite_order_command.dart';
import 'package:doable/src/favorite/domain/favorite_order.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/shared/diagnostics/developer_diagnostics_sink.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/daily_choice_durability_fixture.dart';
import '../../support/favorite_storage_fixture.dart';

void main() {
  late AppDatabase database;
  late sqlite.Database raw;
  late _RecordingDiagnostics diagnostics;
  late _FavoriteOrderFaults faults;
  late DriftPersonalGraphRepository repository;

  setUp(() async {
    diagnostics = _RecordingDiagnostics();
    faults = _FavoriteOrderFaults();
    database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(setup: (connection) => raw = connection),
        faults,
      ),
    );
    await database.open();
    repository = _repository(database, diagnostics);
  });

  tearDown(() async {
    raw.commitFilter = null;
    await database.close();
  });

  /// Граф со связями, тегом, дневным выбором и избранным: единый порядок
  /// с пропусками мест — архивированное 6, 1, архивированное 7, 2, 3, 5.
  /// Намерение 4 не отмечено. Перемещение 5 после 1 даёт порядок
  /// 6, 1, 5, 7, 2, 3.
  Future<void> seedGraph() async {
    await seedDurabilityGraph(database);
    expect(
      await durabilityRepository(database).execute(durabilityCreate()),
      isA<GraphResultSuccess<Object?, Object?>>(),
    );
    for (final number in [6, 7]) {
      _insertArchivedIntention(raw, number: number);
    }
    raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
      _uuid(401),
      'CANARY-тег',
    ]);
    raw.execute(
      'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
      [_uuid(401), _uuid(2)],
    );
    for (final (number, position) in _seededPlaces) {
      storeFavoriteMark(raw, intentionId: _uuid(number), position: position);
    }
  }

  group('Отказ хранилища на каждом шаге', () {
    for (final point in _FaultPoint.values) {
      for (final fault in _storageFaults) {
        test('${fault.name} ${point.description} сохраняет прежний порядок, '
            'данные графа и ревизию', () async {
          await seedGraph();
          final graphBefore = _storedGraph(raw);
          final listBefore = await _favorites(repository);
          final revisionBefore = await _graphRevision(repository);
          diagnostics.clear();
          faults.arm(point, fault.error);

          final result = await repository.execute(_moveFiveAfterOne);

          expect(_failureOf(result), fault.failure);
          expect(faults.failures, 1);
          expect(faults.executedWrites, point.executedWritesBeforeFailure);
          faults.disarm();
          expect(_storedGraph(raw), graphBefore);
          await _expectPublishedState(
            repository,
            listBefore: listBefore,
            revisionBefore: revisionBefore,
          );
          expect(diagnostics.orderEvents, [
            _startedEvent(),
            _failedEvent(point.stage, fault.code),
          ]);
        });
      }
    }

    test('отказ после первого сдвига откатывает уже сдвинутые места', () async {
      await seedGraph();
      final marksBefore = storedFavoriteMarks(raw);
      final maxBefore = marksBefore.last.$2;
      late List<(String, int)> marksAtFailure;
      faults.arm(
        _FaultPoint.afterShift,
        _busy,
        atFailure: () => marksAtFailure = storedFavoriteMarks(raw),
      );

      final result = await repository.execute(_moveFiveAfterOne);

      expect(_failureOf(result), isA<FavoriteOrderUnavailableFailure>());
      // В момент отказа транзакция уже сдвинула все места за прежний
      // максимум, сохранив их взаимный порядок.
      expect(marksAtFailure, [
        for (final (id, position) in marksBefore) (id, position + maxBefore),
      ]);
      expect(storedFavoriteMarks(raw), marksBefore);
    });

    test('отказ commit после записи итоговых мест не оставляет ни одного '
        'изменения', () async {
      await seedGraph();
      final graphBefore = _storedGraph(raw);
      final listBefore = await _favorites(repository);
      final revisionBefore = await _graphRevision(repository);
      diagnostics.clear();
      faults.clear();
      final commits = _CommitRejection.install(raw);

      final result = await repository.execute(_moveFiveAfterOne);

      expect(_failureOf(result), isA<FavoriteOrderUnexpectedFailure>());
      expect(commits.rejected, 1);
      expect(faults.executedWrites, 2);
      expect(_storedGraph(raw), graphBefore);
      await _expectPublishedState(
        repository,
        listBefore: listBefore,
        revisionBefore: revisionBefore,
      );
      expect(diagnostics.orderEvents, [
        _startedEvent(),
        _failedEvent(
          FavoriteOrderCommandDiagnosticsStage.write,
          DiagnosticsFailureCode.unexpected,
        ),
      ]);
    });

    test('назначение итоговых мест, не покрывшее все прочитанные места, '
        'откатывается целиком', () async {
      await seedGraph();
      final graphBefore = _storedGraph(raw);
      final revisionBefore = await _graphRevision(repository);
      diagnostics.clear();
      // Прочитанный порядок теряет скрытое архивированное намерение 7:
      // сдвиг затрагивает все места, а итоговые места получают не все.
      faults.omitFromOrderRead(_uuid(7));

      final result = await repository.execute(_moveFiveAfterOne);

      expect(_failureOf(result), isA<FavoriteOrderUnexpectedFailure>());
      expect(faults.executedWrites, 2);
      expect(_storedGraph(raw), graphBefore);
      expect(
        (await _graphRevision(repository)).compareTo(revisionBefore),
        GraphRevisionOrder.same,
      );
      expect(diagnostics.orderEvents, [
        _startedEvent(),
        _failedEvent(
          FavoriteOrderCommandDiagnosticsStage.write,
          DiagnosticsFailureCode.unexpected,
        ),
      ]);
    });
  });

  group('Повтор после отказа', () {
    for (final point in _FaultPoint.values) {
      test('после недоступности ${point.description} перестановка '
          'выполняется новой командой целиком', () async {
        await seedGraph();
        final revisionBefore = await _graphRevision(repository);
        faults.arm(point, _busy);
        expect(
          _failureOf(await repository.execute(_moveFiveAfterOne)),
          isA<FavoriteOrderUnavailableFailure>(),
        );
        faults.disarm();

        final confirmed = await _confirmed(repository, _moveFiveAfterOne);

        expect(confirmed.value, isA<FavoriteOrderMoved>());
        expect(
          confirmed.revision.compareTo(revisionBefore),
          GraphRevisionOrder.newer,
        );
        expect(storedFavoriteMarks(raw), _movedMarks);
      });
    }

    test('после отказа commit перестановка выполняется новой командой '
        'целиком', () async {
      await seedGraph();
      _CommitRejection.install(raw);
      expect(
        _failureOf(await repository.execute(_moveFiveAfterOne)),
        isA<FavoriteOrderUnexpectedFailure>(),
      );

      final confirmed = await _confirmed(repository, _moveFiveAfterOne);

      expect(confirmed.value, isA<FavoriteOrderMoved>());
      expect(storedFavoriteMarks(raw), _movedMarks);
    });
  });

  group('Повреждение сохранённого порядка до записи', () {
    for (final corruption in _storedCorruptions) {
      test('${corruption.name} — повреждение без записи, пропуска и '
          'исправления данных', () async {
        await seedDurabilityGraph(database);
        for (final number in [6, 7]) {
          _insertArchivedIntention(raw, number: number);
        }
        for (final (number, position) in [(1, 2), (2, 6), (3, 10)]) {
          storeFavoriteMark(
            raw,
            intentionId: _uuid(number),
            position: position,
          );
        }
        corruption.store(raw);
        final graphBefore = _storedGraph(raw);
        final revisionBefore = await _graphRevision(repository);
        diagnostics.clear();
        faults.clear();

        // Участники перемещения активны и целостны: повреждение лежит вне
        // них и не пропускается.
        final result = await repository.execute(
          MoveFavoriteIntention(
            intentionId: _id(3),
            placement: AfterFavoritePlacement(_id(1)),
          ),
        );

        expect(_failureOf(result), isA<FavoriteOrderCorruptionFailure>());
        expect(faults.writes, isEmpty);
        expect(_storedGraph(raw), graphBefore);
        expect(
          (await _graphRevision(repository)).compareTo(revisionBefore),
          GraphRevisionOrder.same,
        );
        expect(diagnostics.orderEvents, [
          _startedEvent(),
          _failedEvent(
            FavoriteOrderCommandDiagnosticsStage.validation,
            DiagnosticsFailureCode.corruption,
          ),
        ]);
        expect(
          await repository.getFavoriteIntentions(),
          isA<FavoriteIntentionsError>().having(
            (result) => result.failure,
            'причина',
            isA<FavoriteIntentionsCorruptionFailure>(),
          ),
        );
      });
    }
  });

  group('Непредставимое промежуточное место', () {
    /// Активные 1 и 2 и скрытое архивированное 6 между ними; намерение 2
    /// стоит на месте [maxPlace].
    Future<void> seedOrderUpTo(int maxPlace) async {
      await seedDurabilityGraph(database);
      _insertArchivedIntention(raw, number: 6);
      for (final (number, position) in [(1, 1), (6, 2), (2, maxPlace)]) {
        storeFavoriteMark(raw, intentionId: _uuid(number), position: position);
      }
    }

    for (final maxPlace in [_largestShiftablePlace + 1, _largestStoredPlace]) {
      test('сдвиг за наибольшее место $maxPlace завершается безопасным '
          'отказом без ослабления ограничений схемы', () async {
        await seedOrderUpTo(maxPlace);
        final graphBefore = _storedGraph(raw);
        final schemaBefore = _schema(raw);
        final revisionBefore = await _graphRevision(repository);
        diagnostics.clear();
        faults.clear();

        final result = await repository.execute(_moveTwoFirst);

        expect(_failureOf(result), isA<FavoriteOrderUnexpectedFailure>());
        expect(faults.writes, hasLength(1));
        expect(faults.executedWrites, 0);
        expect(_storedGraph(raw), graphBefore);
        expect(
          (await _graphRevision(repository)).compareTo(revisionBefore),
          GraphRevisionOrder.same,
        );
        expect(diagnostics.orderEvents, [
          _startedEvent(),
          _failedEvent(
            FavoriteOrderCommandDiagnosticsStage.write,
            DiagnosticsFailureCode.unexpected,
          ),
        ]);
        // Схема и настройка соединения не ослаблены: непредставимое место
        // по-прежнему отклоняется, а повтор даёт тот же отказ.
        expect(_schema(raw), schemaBefore);
        expect(_pragma(raw, 'ignore_check_constraints'), 0);
        expect(_pragma(raw, 'foreign_keys'), 1);
        expect(
          () => raw.execute(
            'INSERT INTO favorite_intentions (intention_id, position) '
            'VALUES (?, ?)',
            [_uuid(3), 9.3e18],
          ),
          throwsA(isA<sqlite.SqliteException>()),
        );
        expect(
          _failureOf(await repository.execute(_moveTwoFirst)),
          isA<FavoriteOrderUnexpectedFailure>(),
        );
        expect(_storedGraph(raw), graphBefore);
      });
    }

    test('наибольшее место, при котором сдвиг представим, переписывается '
        'итоговыми местами', () async {
      await seedOrderUpTo(_largestShiftablePlace);

      final confirmed = await _confirmed(repository, _moveTwoFirst);

      expect(confirmed.value, isA<FavoriteOrderMoved>());
      expect(storedFavoriteMarks(raw), [
        (_uuid(2), 1),
        (_uuid(1), 2),
        (_uuid(6), 3),
      ]);
    });
  });

  group('Категории отказов и диагностика без данных личного графа', () {
    test('каждый исход сохраняет свою категорию и этап, а записи '
        'диагностики не несут контрольных данных', () async {
      await seedGraph();
      diagnostics.clear();
      final moveThreeFirst = MoveFavoriteIntention(
        intentionId: _id(3),
        placement: const FirstFavoritePlacement(),
      );

      final outcomes = <Object>[];
      Future<void> run(
        MoveFavoriteIntention command, {
        (_FaultPoint, Object)? fault,
      }) async {
        if (fault case (final point, final error)) faults.arm(point, error);
        outcomes.add(switch (await repository.execute(command)) {
          FavoriteOrderCommandSucceeded(:final value) =>
            value.value.runtimeType,
          FavoriteOrderCommandFailed(:final failure) => failure.category,
        });
        faults.disarm();
      }

      await run(_moveFiveAfterOne);
      await run(_moveFiveAfterOne);
      await run(
        MoveFavoriteIntention(
          intentionId: _id(2),
          placement: AfterFavoritePlacement(_id(2)),
        ),
      );
      await run(
        MoveFavoriteIntention(
          intentionId: _id(4),
          placement: const FirstFavoritePlacement(),
        ),
      );
      await run(moveThreeFirst, fault: (_FaultPoint.orderRead, _busy));
      await run(
        moveThreeFirst,
        fault: (_FaultPoint.validation, StateError('CANARY-проверка')),
      );
      await run(moveThreeFirst, fault: (_FaultPoint.afterShift, _corrupt));
      await run(
        moveThreeFirst,
        fault: (_FaultPoint.beforeAssignment, StateError('CANARY-запись')),
      );
      _CommitRejection.install(raw);
      await run(moveThreeFirst);
      raw.commitFilter = null;
      storeFavoritePlaceWithoutIntention(
        raw,
        intentionId: _uuid(9),
        position: 99,
      );
      await run(moveThreeFirst);

      expect(outcomes, [
        FavoriteOrderMoved,
        FavoriteOrderUnchanged,
        GraphFailureCategory.validation,
        GraphFailureCategory.conflict,
        GraphFailureCategory.unavailable,
        GraphFailureCategory.unexpected,
        GraphFailureCategory.corruption,
        GraphFailureCategory.unexpected,
        GraphFailureCategory.unexpected,
        GraphFailureCategory.corruption,
      ]);
      final messages = diagnostics.orderMessages;
      expect(
        [
          for (final message in messages)
            if (message['outcome'] != 'started')
              (
                message['stage'],
                message['outcome'],
                message['failureCode'],
                message['completion'],
              ),
        ],
        [
          ('write', 'succeeded', null, 'moved'),
          ('validation', 'succeeded', null, 'unchanged'),
          ('validation', 'failed', 'validation', null),
          ('validation', 'failed', 'conflict', null),
          ('read', 'failed', 'unavailable', null),
          ('validation', 'failed', 'unexpected', null),
          ('write', 'failed', 'corruption', null),
          ('write', 'failed', 'unexpected', null),
          ('write', 'failed', 'unexpected', null),
          ('validation', 'failed', 'corruption', null),
        ],
      );
      expect(
        messages.where((message) => message['outcome'] == 'started'),
        hasLength(10),
      );
      for (final message in messages) {
        expect(
          message.keys.toSet().difference({
            'operation',
            'stage',
            'outcome',
            'durationMicros',
            'failureCode',
            'completion',
          }),
          isEmpty,
        );
        for (final value in message.values) {
          expect(
            value,
            anyOf(
              isA<int>(),
              isIn([
                'favoriteOrderCommand',
                'read',
                'validation',
                'write',
                'started',
                'succeeded',
                'failed',
                'moved',
                'unchanged',
                'conflict',
                'unavailable',
                'corruption',
                'unexpected',
              ]),
            ),
          );
        }
      }
      final written = diagnostics.rawMessages.join('\n');
      for (final secret in [
        'CANARY',
        'Намерение',
        'Выбор',
        for (final number in [1, 2, 3, 4, 5, 6, 7, 9, 401]) _uuid(number),
        'favorite_intentions',
        'position',
        'json_each',
        'UPDATE',
        'SELECT',
        'Exception',
        'StateError',
      ]) {
        expect(written, isNot(contains(secret)));
      }
    });
  });

  group('Независимость от получателя диагностики', () {
    for (final failure in _SinkFailure.values) {
      for (final scenario in _sinkScenarios) {
        test('отказ получателя ${failure.description} не меняет исход '
            '«${scenario.name}» и число записей', () async {
          await seedGraph();
          final sink = _FailingDiagnosticsSink(failure);
          repository = _repository(database, sink);
          final marksBefore = storedFavoriteMarks(raw);
          final revisionBefore = await _graphRevision(repository);
          final fault = scenario.fault;
          if (fault == null) {
            faults.clear();
          } else {
            faults.arm(fault, _busy);
          }

          final result = await repository.execute(scenario.command);

          faults.disarm();
          expect(switch (result) {
            FavoriteOrderCommandSucceeded(:final value) => value.value,
            FavoriteOrderCommandFailed(:final failure) => failure,
          }, scenario.outcome);
          expect(faults.executedWrites, scenario.executedWrites);
          expect(
            storedFavoriteMarks(raw),
            scenario.persists ? _movedMarks : marksBefore,
          );
          expect(
            (await _graphRevision(repository)).compareTo(revisionBefore),
            scenario.persists
                ? GraphRevisionOrder.newer
                : GraphRevisionOrder.same,
          );
          // Каждое событие перестановки передаётся получателю один раз.
          expect(
            sink.attemptedEvents
                .whereType<FavoriteOrderCommandDiagnosticsEvent>(),
            [_startedEvent(), scenario.event],
          );
        });
      }
    }
  });
}

/// Момент, в который получатель диагностики отказывает.
enum _SinkFailure {
  /// Событие начала записывается до транзакции и её commit.
  beforeCommit('до commit'),

  /// Событие исхода записывается после завершения транзакции.
  afterCommit('после commit'),

  always('до и после commit');

  const _SinkFailure(this.description);

  final String description;

  bool failsOn(DiagnosticsEvent event) => switch (this) {
    _SinkFailure.beforeCommit => event.status is DiagnosticsStarted,
    _SinkFailure.afterCommit => event.status is! DiagnosticsStarted,
    _SinkFailure.always => true,
  };
}

final class _FailingDiagnosticsSink implements DiagnosticsSink {
  _FailingDiagnosticsSink(this._failure);

  final _SinkFailure _failure;
  final attemptedEvents = <DiagnosticsEvent>[];

  @override
  void record(DiagnosticsEvent event) {
    attemptedEvents.add(event);
    if (_failure.failsOn(event)) {
      throw StateError('CANARY-отказ-получателя-диагностики');
    }
  }
}

/// Исходы перестановки на фикстуре [seedGraph] при отказе получателя
/// диагностики.
final _sinkScenarios =
    <
      ({
        String name,
        MoveFavoriteIntention command,
        _FaultPoint? fault,
        Matcher outcome,
        int executedWrites,
        bool persists,
        Matcher event,
      })
    >[
      (
        name: 'перестановка',
        command: _moveFiveAfterOne,
        fault: null,
        outcome: isA<FavoriteOrderMoved>(),
        executedWrites: 2,
        persists: true,
        event: isA<FavoriteOrderCommandDiagnosticsEvent>().having(
          (event) => event.completion,
          'завершение',
          FavoriteOrderCommandDiagnosticsCompletion.moved,
        ),
      ),
      (
        name: 'без изменения',
        command: MoveFavoriteIntention(
          intentionId: _id(2),
          placement: AfterFavoritePlacement(_id(1)),
        ),
        fault: null,
        outcome: isA<FavoriteOrderUnchanged>(),
        executedWrites: 0,
        persists: false,
        event: isA<FavoriteOrderCommandDiagnosticsEvent>().having(
          (event) => event.completion,
          'завершение',
          FavoriteOrderCommandDiagnosticsCompletion.unchanged,
        ),
      ),
      (
        name: 'конфликт',
        command: MoveFavoriteIntention(
          intentionId: _id(4),
          placement: const FirstFavoritePlacement(),
        ),
        fault: null,
        outcome: isA<FavoriteOrderConflictFailure>(),
        executedWrites: 0,
        persists: false,
        event: _failedEvent(
          FavoriteOrderCommandDiagnosticsStage.validation,
          DiagnosticsFailureCode.conflict,
        ),
      ),
      (
        name: 'недоступность после назначения итоговых мест',
        command: _moveFiveAfterOne,
        fault: _FaultPoint.afterAssignment,
        outcome: isA<FavoriteOrderUnavailableFailure>(),
        executedWrites: 2,
        persists: false,
        event: _failedEvent(
          FavoriteOrderCommandDiagnosticsStage.write,
          DiagnosticsFailureCode.unavailable,
        ),
      ),
    ];

/// Наибольшее место, которое SQLite хранит целым числом.
const _largestStoredPlace = 9223372036854775807;

/// Наибольшее место, сдвиг которого за самого себя остаётся целым числом.
const _largestShiftablePlace = 4611686018427387903;

final _moveTwoFirst = MoveFavoriteIntention(
  intentionId: _id(2),
  placement: const FirstFavoritePlacement(),
);

/// Повреждения сохранённого порядка, недостижимые через приложение, рядом
/// со скрытыми архивированными намерениями 6 и 7. Целостный порядок:
/// 1 на месте 2, 2 на месте 6, 3 на месте 10.
final _storedCorruptions =
    <({String name, void Function(sqlite.Database) store})>[
      for (final (name, position) in <(String, Object)>[
        ('нулевое', 0),
        ('отрицательное', -4),
        ('дробное', 4.5),
        ('текстовое', 'четыре'),
      ])
        (
          name: '$name место скрытого архивированного намерения',
          store: (database) => storeFavoriteMarkWithInvalidPosition(
            database,
            intentionId: _uuid(6),
            position: position,
          ),
        ),
      (
        name: 'место скрытого архивированного намерения без значения',
        store: (database) {
          removeFavoriteSchemaProtection(database);
          database.execute(
            'INSERT INTO favorite_intentions (intention_id, position) '
            'VALUES (?, NULL)',
            [_uuid(6)],
          );
        },
      ),
      (
        name: 'два скрытых архивированных намерения на одном месте',
        store: (database) {
          removeFavoriteSchemaProtection(database);
          storeFavoriteMark(database, intentionId: _uuid(6), position: 8);
          storeFavoriteMark(database, intentionId: _uuid(7), position: 8);
        },
      ),
      (
        name: 'скрытое архивированное намерение на месте активного',
        store: (database) {
          removeFavoriteSchemaProtection(database);
          storeFavoriteMark(database, intentionId: _uuid(6), position: 6);
        },
      ),
      (
        name: 'вторая отметка скрытого архивированного намерения',
        store: (database) {
          removeFavoriteSchemaProtection(database);
          storeFavoriteMark(database, intentionId: _uuid(6), position: 4);
          storeFavoriteMark(database, intentionId: _uuid(6), position: 8);
        },
      ),
      (
        name: 'место без намерения между скрытыми архивированными',
        store: (database) {
          storeFavoriteMark(database, intentionId: _uuid(6), position: 4);
          storeFavoritePlaceWithoutIntention(
            database,
            intentionId: _uuid(9),
            position: 5,
          );
          storeFavoriteMark(database, intentionId: _uuid(7), position: 8);
        },
      ),
      (
        name: 'место без намерения перед всеми избранными',
        store: (database) => storeFavoritePlaceWithoutIntention(
          database,
          intentionId: _uuid(9),
          position: 1,
        ),
      ),
    ];

/// Сохранённые места фикстуры: номер намерения и место.
const _seededPlaces = [(6, 3), (1, 4), (7, 9), (2, 15), (3, 16), (5, 30)];

/// Итоговые места после перемещения 5 сразу после 1.
final _movedMarks = [
  for (final (index, number) in [6, 1, 5, 7, 2, 3].indexed)
    (_uuid(number), index + 1),
];

final _moveFiveAfterOne = MoveFavoriteIntention(
  intentionId: _id(5),
  placement: AfterFavoritePlacement(_id(1)),
);

final _busy = sqlite.SqliteException(
  extendedResultCode: sqlite.SqlError.SQLITE_BUSY,
  message: 'CANARY-недоступность',
);

final _corrupt = sqlite.SqliteException(
  extendedResultCode: sqlite.SqlError.SQLITE_CORRUPT,
  message: 'CANARY-повреждение',
);

/// Отказы хранилища трёх различимых категорий.
final _storageFaults =
    <
      ({
        String name,
        Object error,
        Matcher failure,
        DiagnosticsFailureCode code,
      })
    >[
      (
        name: 'недоступность',
        error: _busy,
        failure: isA<FavoriteOrderUnavailableFailure>(),
        code: DiagnosticsFailureCode.unavailable,
      ),
      (
        name: 'повреждение',
        error: _corrupt,
        failure: isA<FavoriteOrderCorruptionFailure>(),
        code: DiagnosticsFailureCode.corruption,
      ),
      (
        name: 'неизвестный отказ',
        error: StateError('CANARY-неизвестный-отказ'),
        failure: isA<FavoriteOrderUnexpectedFailure>(),
        code: DiagnosticsFailureCode.unexpected,
      ),
    ];

/// Шаг перестановки, на котором хранилище отказывает.
enum _FaultPoint {
  /// Чтение полного порядка отклонено до выполнения.
  orderRead(
    'при чтении порядка',
    FavoriteOrderCommandDiagnosticsStage.read,
    executedWritesBeforeFailure: 0,
  ),

  /// Проверка прочитанных мест прервана при обращении к строке порядка.
  validation(
    'при проверке прочитанного порядка',
    FavoriteOrderCommandDiagnosticsStage.validation,
    executedWritesBeforeFailure: 0,
  ),

  /// Сдвиг мест за прежний максимум отклонён до выполнения.
  beforeShift(
    'до сдвига мест',
    FavoriteOrderCommandDiagnosticsStage.write,
    executedWritesBeforeFailure: 0,
  ),

  /// Сдвиг выполнен, но транзакция не завершена.
  afterShift(
    'после первого сдвига',
    FavoriteOrderCommandDiagnosticsStage.write,
    executedWritesBeforeFailure: 1,
  ),

  /// Назначение итоговых мест отклонено до выполнения.
  beforeAssignment(
    'до назначения итоговых мест',
    FavoriteOrderCommandDiagnosticsStage.write,
    executedWritesBeforeFailure: 1,
  ),

  /// Итоговые места назначены, но транзакция не завершена.
  afterAssignment(
    'после назначения итоговых мест',
    FavoriteOrderCommandDiagnosticsStage.write,
    executedWritesBeforeFailure: 2,
  );

  const _FaultPoint(
    this.description,
    this.stage, {
    required this.executedWritesBeforeFailure,
  });

  final String description;
  final FavoriteOrderCommandDiagnosticsStage stage;
  final int executedWritesBeforeFailure;
}

/// Однократный отказ хранилища на заданном шаге перестановки и журнал
/// записей мест с последнего [arm] или [clear].
///
/// Шаги различаются по порядку записей мест внутри команды: первая запись —
/// сдвиг за прежний максимум, вторая — назначение итоговых мест.
final class _FavoriteOrderFaults extends LocalDatabaseConnectionObserver {
  _FaultPoint? _point;
  Object? _error;
  void Function()? _atFailure;
  String? _omittedIntentionId;

  /// Число сработавших отказов с последнего [arm].
  var failures = 0;

  /// Инструкции записи мест, дошедшие до хранилища.
  final writes = <String>[];

  /// Записи мест, выполненные хранилищем.
  var executedWrites = 0;

  void arm(_FaultPoint point, Object error, {void Function()? atFailure}) {
    clear();
    _point = point;
    _error = error;
    _atFailure = atFailure;
    failures = 0;
  }

  void disarm() {
    _point = null;
    _error = null;
    _atFailure = null;
  }

  void clear() {
    writes.clear();
    executedWrites = 0;
  }

  /// Скрывает из следующего чтения порядка строку намерения [intentionId].
  void omitFromOrderRead(String intentionId) {
    clear();
    _omittedIntentionId = intentionId;
  }

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (_isOrderRead(statement)) {
      _failAt(_FaultPoint.orderRead);
      return;
    }
    if (!_isPlaceWrite(statement)) return;
    writes.addAll(statement.statements);
    _failAt(
      writes.length == 1
          ? _FaultPoint.beforeShift
          : _FaultPoint.beforeAssignment,
    );
  }

  @override
  void afterStatement(LocalDatabaseSqlStatement statement) {
    if (!_isPlaceWrite(statement)) return;
    executedWrites++;
    _failAt(
      executedWrites == 1
          ? _FaultPoint.afterShift
          : _FaultPoint.afterAssignment,
    );
  }

  @override
  List<Map<String, Object?>> afterSelect(
    LocalDatabaseSqlStatement statement,
    List<Map<String, Object?>> rows,
  ) {
    if (!_isOrderRead(statement)) return rows;
    final omitted = _omittedIntentionId;
    _omittedIntentionId = null;
    return [
      for (final row in rows)
        if (row['intention_id'] != omitted)
          _point == _FaultPoint.validation
              ? _FailingRow(row, () => _failAt(_FaultPoint.validation))
              : row,
    ];
  }

  /// Внутри команды перестановки таблицу мест читает только чтение полного
  /// порядка.
  bool _isOrderRead(LocalDatabaseSqlStatement statement) =>
      statement.operation == LocalDatabaseSqlOperation.select &&
      statement.statements.single.contains('FROM favorite_intentions');

  bool _isPlaceWrite(LocalDatabaseSqlStatement statement) =>
      statement.operation != LocalDatabaseSqlOperation.select &&
      statement.statements.any((sql) => sql.contains('favorite_intentions'));

  void _failAt(_FaultPoint point) {
    final error = _error;
    if (_point != point || error == null || failures > 0) return;
    failures++;
    _atFailure?.call();
    throw error;
  }
}

/// Строка прочитанного порядка, обращение к значению которой сначала
/// вызывает [_onRead].
final class _FailingRow extends UnmodifiableMapBase<String, Object?> {
  _FailingRow(this._row, this._onRead);

  final Map<String, Object?> _row;
  final void Function() _onRead;

  @override
  Iterable<String> get keys => _row.keys;

  @override
  Object? operator [](Object? key) {
    _onRead();
    return _row[key];
  }
}

/// Отклоняет первый commit пишущей транзакции соединения штатным commit
/// hook SQLite: commit превращается в откат, а инструкция завершается
/// отказом.
///
/// Наблюдатель соединения commit транзакции не видит, поэтому отказ вносится
/// в то же настроенное соединение, полученное через его setup.
final class _CommitRejection {
  _CommitRejection._();

  factory _CommitRejection.install(sqlite.Database database) {
    final rejection = _CommitRejection._();
    database.commitFilter = () {
      if (rejection.rejected > 0) return true;
      rejection.rejected++;
      return false;
    };
    return rejection;
  }

  var rejected = 0;
}

/// Сохраняет события и то, что получатель разработчика записал бы в журнал.
final class _RecordingDiagnostics implements DiagnosticsSink {
  final _events = <DiagnosticsEvent>[];
  final rawMessages = <String>[];
  late final _developer = DeveloperDiagnosticsSink(rawMessages.add);

  List<FavoriteOrderCommandDiagnosticsEvent> get orderEvents =>
      _events.whereType<FavoriteOrderCommandDiagnosticsEvent>().toList();

  /// Записи получателя разработчика о перестановке.
  List<Map<String, Object?>> get orderMessages => [
    for (final message in rawMessages)
      if (jsonDecode(message) case final Map<String, Object?> decoded
          when decoded['operation'] == 'favoriteOrderCommand')
        decoded,
  ];

  void clear() {
    _events.clear();
    rawMessages.clear();
  }

  @override
  void record(DiagnosticsEvent event) {
    _events.add(event);
    _developer.record(event);
  }
}

DriftPersonalGraphRepository _repository(
  AppDatabase database,
  DiagnosticsSink diagnostics,
) => DriftPersonalGraphRepository(
  database,
  UuidV7IntentionIdGenerator(),
  () => DateTime.utc(2026, 10, 3, 12),
  diagnostics,
);

String _uuid(int number) => durabilityUuid(number);

IntentionId _id(int number) => durabilityIntention(number);

/// Архивированное намерение без связей с контрольным названием.
void _insertArchivedIntention(sqlite.Database database, {required int number}) {
  database.execute(
    'INSERT INTO intentions (id, title, description, is_action_ready, '
    'is_archived, created_at, updated_at) VALUES (?, ?, ?, 0, 1, ?, ?)',
    [
      _uuid(number),
      'CANARY-архивное $number',
      'CANARY-описание $number',
      number,
      number,
    ],
  );
}

/// Все строки всех таблиц хранилища, включая отметки избранного и служебные
/// таблицы поисковой проекции.
Map<String, List<Map<String, Object?>>> _storedGraph(
  sqlite.Database database,
) => {
  for (final table in database.select(
    "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
  ))
    table['name'] as String: [
      for (final row in database.select('SELECT * FROM "${table['name']}"'))
        {...row},
    ],
};

/// Объекты схемы хранилища с их определениями.
List<Map<String, Object?>> _schema(sqlite.Database database) => [
  for (final row in database.select(
    'SELECT type, name, tbl_name, sql FROM sqlite_master ORDER BY type, name',
  ))
    {...row},
];

Object? _pragma(sqlite.Database database, String name) =>
    database.select('PRAGMA $name').single.values.single;

Future<FavoriteIntentionsSnapshot> _favorites(
  DriftPersonalGraphRepository repository,
) async {
  final result = await repository.getFavoriteIntentions();
  expect(result, isA<FavoriteIntentionsSuccess>());
  return (result as FavoriteIntentionsSuccess).value;
}

/// Ревизия графа, читаемая независимо от сохранённых данных избранного, в
/// том числе повреждённых.
Future<GraphRevision> _graphRevision(
  DriftPersonalGraphRepository repository,
) async {
  final result = await repository.getTagCatalog(const TagCatalogBrowseMode());
  expect(result, isA<TagCatalogSuccess>());
  return (result as TagCatalogSuccess).value.revision;
}

/// Независимые чтения видят прежний список Главной на прежней ревизии:
/// успешный результат не опубликован.
Future<void> _expectPublishedState(
  DriftPersonalGraphRepository repository, {
  required FavoriteIntentionsSnapshot listBefore,
  required GraphRevision revisionBefore,
}) async {
  final listAfter = await _favorites(repository);
  expect(
    listAfter.items.map((row) => row.id),
    listBefore.items.map((row) => row.id),
  );
  expect(
    listAfter.revision.compareTo(listBefore.revision),
    GraphRevisionOrder.same,
  );
  expect(
    (await _graphRevision(repository)).compareTo(revisionBefore),
    GraphRevisionOrder.same,
  );
}

FavoriteOrderCommandFailure _failureOf(FavoriteOrderCommandResult result) =>
    switch (result) {
      FavoriteOrderCommandFailed(:final failure) => failure,
      FavoriteOrderCommandSucceeded(:final value) => fail(
        'Ожидался отказ, получен ${value.value.runtimeType}.',
      ),
    };

Future<ConfirmedGraphResult<FavoriteOrderCommandSuccess>> _confirmed(
  DriftPersonalGraphRepository repository,
  MoveFavoriteIntention command,
) async => switch (await repository.execute(command)) {
  FavoriteOrderCommandSucceeded(:final value) => value,
  FavoriteOrderCommandFailed(:final failure) => fail(
    'Ожидался успех, получен ${failure.runtimeType}.',
  ),
};

Matcher _startedEvent() => isA<FavoriteOrderCommandDiagnosticsEvent>()
    .having(
      (event) => event.stage,
      'этап',
      FavoriteOrderCommandDiagnosticsStage.read,
    )
    .having((event) => event.status, 'исход', isA<DiagnosticsStarted>());

Matcher _failedEvent(
  FavoriteOrderCommandDiagnosticsStage stage,
  DiagnosticsFailureCode code,
) => isA<FavoriteOrderCommandDiagnosticsEvent>()
    .having((event) => event.stage, 'этап', stage)
    .having((event) => event.completion, 'завершение', isNull)
    .having(
      (event) => event.status,
      'исход',
      isA<DiagnosticsFailed>()
          .having((status) => status.code, 'категория', code)
          .having(
            (status) => status.duration,
            'длительность',
            greaterThanOrEqualTo(Duration.zero),
          ),
    );
