import 'dart:convert';
import 'dart:typed_data';

import 'package:doable/src/data/local/app_database.dart' hide Intention;
import 'package:doable/src/favorite/application/favorite_intentions.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/shared/diagnostics/developer_diagnostics_sink.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/favorite_storage_fixture.dart';

void main() {
  late AppDatabase database;
  late sqlite.Database raw;
  late _RecordingDiagnostics diagnostics;
  late _FavoriteListStorage storage;
  late DriftPersonalGraphRepository repository;

  DriftPersonalGraphRepository repositoryWith(DiagnosticsSink sink) =>
      DriftPersonalGraphRepository(
        database,
        UuidV7IntentionIdGenerator(),
        () => DateTime.utc(2026, 10, 2, 12),
        sink,
      );

  setUp(() async {
    diagnostics = _RecordingDiagnostics();
    storage = _FavoriteListStorage();
    database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(setup: (connection) => raw = connection),
        storage,
      ),
    );
    await database.open();
    repository = repositoryWith(diagnostics);
  });

  tearDown(() => database.close());

  /// Целостное избранное: активное первое, архивированное второе и активное
  /// третье намерения на местах 2, 4 и 6; четвёртое намерение не отмечено.
  void seedFavorites() {
    _insertIntention(raw, number: 1, title: 'CANARY-первое');
    _insertIntention(raw, number: 2, title: 'CANARY-второе', isArchived: true);
    _insertIntention(raw, number: 3, title: 'CANARY-третье');
    _insertIntention(raw, number: 4, title: 'CANARY-неизбранное');
    storeFavoriteMark(raw, intentionId: _uuid(1), position: 2);
    storeFavoriteMark(raw, intentionId: _uuid(2), position: 4);
    storeFavoriteMark(raw, intentionId: _uuid(3), position: 6);
  }

  /// Чтение списка возвращает повреждение на этапе проверки сохранённых
  /// данных и не меняет их.
  Future<void> expectCorruption() async {
    final storedBefore = _storedGraph(raw);
    final changesBefore = _connectionChanges(raw);
    storage.clear();
    diagnostics.clear();

    final result = await repository.getFavoriteIntentions();

    expect(result, _failure(isA<FavoriteIntentionsCorruptionFailure>()));
    expect(
      (result as FavoriteIntentionsError).failure.category,
      GraphFailureCategory.corruption,
    );
    expect(storage.writes, isEmpty);
    expect(_connectionChanges(raw), changesBefore);
    expect(_storedGraph(raw), storedBefore);
    expect(diagnostics.readEvents, [
      _started(),
      _failed(
        FavoriteIntentionsReadDiagnosticsStage.validation,
        DiagnosticsFailureCode.corruption,
      ),
    ]);
  }

  group('Место без существующего намерения', () {
    for (final (description, position) in [
      ('перед остальными местами', 1),
      ('между местами избранных намерений', 3),
      ('после остальных мест', 9),
    ]) {
      test('$description даёт повреждение без списка', () async {
        seedFavorites();
        storeFavoritePlaceWithoutIntention(
          raw,
          intentionId: _uuid(101),
          position: position,
        );

        await expectCorruption();
      });
    }

    test('единственное в хранилище не выдаётся за пустой снимок', () async {
      storeFavoritePlaceWithoutIntention(
        raw,
        intentionId: _uuid(101),
        position: 1,
      );

      await expectCorruption();
    });
  });

  group('Неоднозначный порядок', () {
    test('два намерения на одном месте дают повреждение', () async {
      seedFavorites();
      removeFavoriteSchemaProtection(raw);
      storeFavoriteMark(raw, intentionId: _uuid(4), position: 6);

      await expectCorruption();
    });

    test('активное и архивированное намерения на одном месте дают '
        'повреждение', () async {
      seedFavorites();
      removeFavoriteSchemaProtection(raw);
      storeFavoriteMark(raw, intentionId: _uuid(4), position: 4);

      await expectCorruption();
    });

    test('вторая отметка одного намерения даёт повреждение', () async {
      seedFavorites();
      removeFavoriteSchemaProtection(raw);
      storeFavoriteMark(raw, intentionId: _uuid(1), position: 8);

      await expectCorruption();
    });
  });

  group('Недопустимое место', () {
    for (final position in <Object>[0, -3, 1.5, 'CANARY-место']) {
      for (final (description, isArchived) in [
        ('активного', false),
        ('архивированного', true),
      ]) {
        test('$position $description избранного намерения даёт '
            'повреждение', () async {
          seedFavorites();
          _insertIntention(
            raw,
            number: 5,
            title: 'CANARY-повреждённое',
            isArchived: isArchived,
          );
          storeFavoriteMarkWithInvalidPosition(
            raw,
            intentionId: _uuid(5),
            position: position,
          );

          await expectCorruption();
        });
      }
    }

    test('отсутствующее место даёт повреждение', () async {
      seedFavorites();
      removeFavoriteSchemaProtection(raw);
      raw.execute(
        'INSERT INTO favorite_intentions (intention_id, position) '
        'VALUES (?, NULL)',
        [_uuid(4)],
      );

      await expectCorruption();
    });
  });

  group('Недопустимый идентификатор', () {
    for (final (description, id) in [
      ('не UUID', 'CANARY-идентификатор'),
      ('UUID в неканонической записи', _uuid(5).toUpperCase()),
    ]) {
      for (final (scope, isArchived) in [
        ('активного', false),
        ('архивированного', true),
      ]) {
        test('$description $scope избранного намерения даёт '
            'повреждение', () async {
          seedFavorites();
          _insertIntentionWithId(
            raw,
            id: id,
            title: 'CANARY-повреждённое',
            isArchived: isArchived,
          );
          storeFavoriteMark(raw, intentionId: id, position: 8);

          await expectCorruption();
        });
      }
    }

    test('идентификатор отметки не текстом даёт повреждение', () async {
      seedFavorites();
      removeFavoriteSchemaProtection(raw);
      raw.execute(
        'INSERT INTO favorite_intentions (intention_id, position) '
        'VALUES (?, ?)',
        [_blob, 8],
      );

      await expectCorruption();
    });
  });

  group('Недопустимые поля намерения', () {
    for (final (description, column, value) in <(String, String, Object?)>[
      ('название с пробелами по краям', 'title', ' CANARY-название '),
      ('описание не текстом', 'description', _blob),
      ('готовность вне двух значений', 'is_action_ready', 7),
      ('архивное состояние вне двух значений', 'is_archived', 2),
      ('время создания не числом', 'created_at', 'CANARY-время'),
      ('время изменения не числом', 'updated_at', 'CANARY-время'),
    ]) {
      for (final (scope, number) in [
        ('активного', 1),
        ('архивированного', 2),
      ]) {
        test('$description у $scope избранного намерения даёт '
            'повреждение', () async {
          seedFavorites();
          _corruptIntentionField(
            raw,
            number: number,
            column: column,
            value: value,
          );

          await expectCorruption();
        });
      }
    }

    test('повреждённые поля неизбранного намерения списку не мешают', () async {
      seedFavorites();
      _corruptIntentionField(
        raw,
        number: 4,
        column: 'title',
        value: ' CANARY-название ',
      );

      final snapshot = await _favorites(repository);

      expect(snapshot.items.map(_rowId), [_uuid(1), _uuid(3)]);
      expect(snapshot.archivedCount, 1);
    });
  });

  group('Категории отказов', () {
    for (final point in _FaultPoint.values) {
      for (final fault in _storageFaults) {
        test('${fault.name} ${point.description} не подменяется пустым '
            'снимком', () async {
          seedFavorites();
          final storedBefore = _storedGraph(raw);
          storage.clear();
          diagnostics.clear();
          storage.arm(point, fault.error);

          final result = await repository.getFavoriteIntentions();

          expect(result, _failure(fault.failure));
          expect(
            (result as FavoriteIntentionsError).failure.category,
            fault.category,
          );
          expect(storage.failures, 1);
          expect(storage.writes, isEmpty);
          expect(_storedGraph(raw), storedBefore);
          expect(diagnostics.readEvents, [
            _started(),
            _failed(FavoriteIntentionsReadDiagnosticsStage.read, fault.code),
          ]);
        });
      }
    }

    test('отклонение ограничением схемы не считается недоступностью', () async {
      seedFavorites();
      storage.arm(
        _FaultPoint.rowsRead,
        sqlite.SqliteException(
          extendedResultCode: sqlite.SqlExtendedError.SQLITE_CONSTRAINT_UNIQUE,
          message: 'CANARY-уникальность',
        ),
      );

      expect(
        await repository.getFavoriteIntentions(),
        _failure(isA<FavoriteIntentionsUnexpectedFailure>()),
      );
    });

    test('пустой снимок отличим от каждого отказа', () async {
      _insertIntention(raw, number: 1, title: 'CANARY-неизбранное');

      final empty = await repository.getFavoriteIntentions();

      expect(empty, isA<FavoriteIntentionsSuccess>());
      for (final fault in _storageFaults) {
        storage.arm(_FaultPoint.rowsRead, fault.error);
        expect(
          await repository.getFavoriteIntentions(),
          _failure(fault.failure),
          reason: fault.name,
        );
        storage.disarm();
      }
    });

    for (final point in _FaultPoint.values) {
      test('повтор после недоступности ${point.description} выполняется как '
          'новое чтение', () async {
        seedFavorites();
        storage.arm(point, _busy);
        expect(
          await repository.getFavoriteIntentions(),
          _failure(isA<FavoriteIntentionsUnavailableFailure>()),
        );
        storage.disarm();
        storage.clear();
        diagnostics.clear();

        final snapshot = await _favorites(repository);

        expect(snapshot.items.map(_rowId), [_uuid(1), _uuid(3)]);
        expect(snapshot.archivedCount, 1);
        expect(storage.favoriteReads, 1);
        expect(storage.writes, isEmpty);
        expect(diagnostics.readEvents, [_started(), _succeeded()]);
      });
    }

    test('повтор после повреждения возвращает то же повреждение', () async {
      seedFavorites();
      storeFavoritePlaceWithoutIntention(
        raw,
        intentionId: _uuid(101),
        position: 3,
      );

      await expectCorruption();
      await expectCorruption();
    });
  });

  group('Чтения состояния отметки при месте без существующего намерения', () {
    setUp(() {
      seedFavorites();
      storeFavoritePlaceWithoutIntention(
        raw,
        intentionId: _uuid(101),
        position: 3,
      );
    });

    test(
      'подробные данные остаются успешными, а список — повреждение',
      () async {
        for (final (number, mark) in _intactMarks) {
          final result = await repository.watchIntention(_id(number)).first;
          expect(
            result,
            isA<ResultSuccess<GraphSnapshot<IntentionDetails?>>>().having(
              (result) => result.value.value?.favoriteMark,
              'отметка',
              mark,
            ),
            reason: 'намерение $number',
          );
        }

        await expectCorruption();
      },
    );

    test('порция с целостными отметками остаётся успешной, а список — '
        'повреждение', () async {
      final result = await repository.getCatalogPage(
        IntentionCatalogQuery(
          scope: IntentionScope.all,
          titleFilter: null,
          order: IntentionCatalogOrder.createdAtAscending,
          pageSize: 10,
          cursor: null,
        ),
      );

      expect(result, isA<ResultSuccess<IntentionCatalogPage>>());
      expect(
        {
          for (final item
              in (result as ResultSuccess<IntentionCatalogPage>).value.items)
            item.id.toCanonicalString(): item.favoriteMark,
        },
        {for (final (number, mark) in _intactMarks) _uuid(number): mark},
      );

      await expectCorruption();
    });
  });

  group('Диагностика чтения списка', () {
    test(
      'успех несёт этап проверки сохранённых данных и длительность',
      () async {
        seedFavorites();
        diagnostics.clear();

        await _favorites(repository);

        expect(diagnostics.readEvents, [_started(), _succeeded()]);
        expect(
          (diagnostics.readEvents.last.status as DiagnosticsSucceeded).duration,
          greaterThanOrEqualTo(Duration.zero),
        );
      },
    );

    test('успешный пустой снимок диагностируется как успех', () async {
      diagnostics.clear();

      final snapshot = await _favorites(repository);

      expect(snapshot.items, isEmpty);
      expect(diagnostics.readEvents, [_started(), _succeeded()]);
    });

    test('чтение списка не получает событий других операций', () async {
      seedFavorites();
      diagnostics.clear();

      await _favorites(repository);

      expect(
        diagnostics.events,
        everyElement(isA<FavoriteIntentionsReadDiagnosticsEvent>()),
      );
    });

    test('события и запись получателя разработчика несут только безопасные '
        'поля', () async {
      seedFavorites();
      diagnostics.clear();

      await _favorites(repository);
      for (final (point, error) in [
        (_FaultPoint.rowsRead, _busy),
        (_FaultPoint.rowsRead, _corrupt),
        (_FaultPoint.countsRead, StateError('CANARY-исключение')),
        (_FaultPoint.countsRead, _readOnly),
      ]) {
        storage.arm(point, error);
        await repository.getFavoriteIntentions();
        storage.disarm();
      }
      _insertIntentionWithId(
        raw,
        id: 'CANARY-идентификатор',
        title: 'CANARY-повреждённое',
        description: 'CANARY-описание',
      );
      storeFavoriteMark(raw, intentionId: 'CANARY-идентификатор', position: 8);
      await repository.getFavoriteIntentions();

      expect(
        [
          for (final message in diagnostics.messages)
            (message['outcome'], message['stage'], message['failureCode']),
        ],
        [
          ('started', 'read', null),
          ('succeeded', 'validation', null),
          ('started', 'read', null),
          ('failed', 'read', 'unavailable'),
          ('started', 'read', null),
          ('failed', 'read', 'corruption'),
          ('started', 'read', null),
          ('failed', 'read', 'unexpected'),
          ('started', 'read', null),
          ('failed', 'read', 'unexpected'),
          ('started', 'read', null),
          ('failed', 'validation', 'corruption'),
        ],
      );
      for (final message in diagnostics.messages) {
        expect(message['operation'], 'favoriteIntentionsRead');
        expect(message.keys.toSet(), switch (message['outcome']) {
          'started' => {'operation', 'stage', 'outcome'},
          'succeeded' => {'operation', 'stage', 'outcome', 'durationMicros'},
          _ => {
            'operation',
            'stage',
            'outcome',
            'durationMicros',
            'failureCode',
          },
        });
      }
      final written = diagnostics.rawMessages.join('\n');
      for (final secret in [
        'CANARY',
        for (var number = 1; number <= 4; number++) _uuid(number),
        'favorite_intentions',
        'position',
        'SELECT',
        'Exception',
        'StateError',
      ]) {
        expect(written, isNot(contains(secret)));
      }
      // Значения событий — только перечисления и длительность: названий,
      // идентификаторов, состава и порядка избранных в них нет по построению
      // типа.
      for (final value in [
        for (final message in diagnostics.messages) ...message.values,
      ]) {
        expect(
          value,
          anyOf(
            isA<int>(),
            isIn([
              'favoriteIntentionsRead',
              'read',
              'validation',
              'started',
              'succeeded',
              'failed',
              'unavailable',
              'corruption',
              'unexpected',
            ]),
          ),
        );
      }
    });
  });

  group('Независимость от получателя диагностики', () {
    test('отказ получателя не меняет успешный список и не повторяет '
        'чтение', () async {
      seedFavorites();
      final failing = _ThrowingDiagnosticsSink();
      repository = repositoryWith(failing);
      storage.clear();

      final snapshot = await _favorites(repository);

      expect(snapshot.items.map(_rowId), [_uuid(1), _uuid(3)]);
      expect(snapshot.archivedCount, 1);
      expect(storage.favoriteReads, 1);
      expect(storage.writes, isEmpty);
      expect(failing.attemptedEvents, [_started(), _succeeded()]);
    });

    test('отказ получателя не меняет повреждение и не повторяет '
        'чтение', () async {
      seedFavorites();
      storeFavoritePlaceWithoutIntention(
        raw,
        intentionId: _uuid(101),
        position: 3,
      );
      final failing = _ThrowingDiagnosticsSink();
      repository = repositoryWith(failing);
      storage.clear();

      final result = await repository.getFavoriteIntentions();

      expect(result, _failure(isA<FavoriteIntentionsCorruptionFailure>()));
      expect(storage.favoriteReads, 1);
      expect(failing.attemptedEvents, [
        _started(),
        _failed(
          FavoriteIntentionsReadDiagnosticsStage.validation,
          DiagnosticsFailureCode.corruption,
        ),
      ]);
    });

    for (final fault in _storageFaults) {
      test('отказ получателя не меняет категорию отказа: '
          '${fault.name}', () async {
        seedFavorites();
        final failing = _ThrowingDiagnosticsSink();
        repository = repositoryWith(failing);
        storage.clear();
        storage.arm(_FaultPoint.rowsRead, fault.error);

        final result = await repository.getFavoriteIntentions();

        expect(result, _failure(fault.failure));
        expect(storage.failures, 1);
        expect(storage.favoriteReads, 1);
        expect(failing.attemptedEvents, [
          _started(),
          _failed(FavoriteIntentionsReadDiagnosticsStage.read, fault.code),
        ]);
      });
    }

    test('отказ записи получателя разработчика не меняет результат и не '
        'повторяет чтение', () async {
      seedFavorites();
      var writeAttempts = 0;
      repository = repositoryWith(
        DeveloperDiagnosticsSink((_) {
          writeAttempts++;
          throw StateError('CANARY-отказ-записи-диагностики');
        }),
      );
      storage.clear();

      final snapshot = await _favorites(repository);

      expect(snapshot.items.map(_rowId), [_uuid(1), _uuid(3)]);
      expect(writeAttempts, 2);
      expect(storage.favoriteReads, 1);
    });
  });
}

/// Подтверждённые отметки намерений фикстуры, чьи сохранённые данные целостны.
const _intactMarks = [
  (1, FavoriteMark.favorite),
  (2, FavoriteMark.favorite),
  (3, FavoriteMark.favorite),
  (4, FavoriteMark.notFavorite),
];

/// Значение, которое текстовый столбец сохраняет без приведения к тексту.
final _blob = Uint8List.fromList([0xCA, 0xFE]);

final _busy = sqlite.SqliteException(
  extendedResultCode: sqlite.SqlError.SQLITE_BUSY,
  message: 'CANARY-недоступность',
);

final _corrupt = sqlite.SqliteException(
  extendedResultCode: sqlite.SqlError.SQLITE_CORRUPT,
  message: 'CANARY-повреждение',
);

final _readOnly = sqlite.SqliteException(
  extendedResultCode: sqlite.SqlError.SQLITE_READONLY,
  message: 'CANARY-неизвестный-SQLite-отказ',
);

/// Отказы хранилища трёх различимых категорий.
final _storageFaults =
    <
      ({
        String name,
        Object error,
        Matcher failure,
        GraphFailureCategory category,
        DiagnosticsFailureCode code,
      })
    >[
      (
        name: 'недоступность',
        error: _busy,
        failure: isA<FavoriteIntentionsUnavailableFailure>(),
        category: GraphFailureCategory.unavailable,
        code: DiagnosticsFailureCode.unavailable,
      ),
      (
        name: 'повреждение',
        error: _corrupt,
        failure: isA<FavoriteIntentionsCorruptionFailure>(),
        category: GraphFailureCategory.corruption,
        code: DiagnosticsFailureCode.corruption,
      ),
      (
        name: 'неизвестный отказ',
        error: StateError('CANARY-неизвестный-отказ'),
        failure: isA<FavoriteIntentionsUnexpectedFailure>(),
        category: GraphFailureCategory.unexpected,
        code: DiagnosticsFailureCode.unexpected,
      ),
    ];

/// Момент чтения списка, в который хранилище отказывает.
enum _FaultPoint {
  /// Чтение строк избранного.
  rowsRead('при чтении строк избранного'),

  /// Пакетное чтение счётчиков активных связей.
  countsRead('при чтении счётчиков связей');

  const _FaultPoint(this.description);

  final String description;
}

/// Наблюдает чтения и записи соединения и однократно отказывает в заданный
/// момент чтения списка.
final class _FavoriteListStorage extends LocalDatabaseConnectionObserver {
  _FaultPoint? _point;
  Object? _error;

  /// Число сработавших отказов с последнего [arm].
  var failures = 0;

  /// Число чтений строк избранного.
  var favoriteReads = 0;

  /// Записи соединения в порядке выполнения.
  final writes = <String>[];

  void arm(_FaultPoint point, Object error) {
    _point = point;
    _error = error;
    failures = 0;
  }

  void disarm() {
    _point = null;
    _error = null;
  }

  void clear() {
    favoriteReads = 0;
    writes.clear();
  }

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (statement.operation != LocalDatabaseSqlOperation.select) {
      writes.addAll(statement.statements);
    }
  }

  @override
  List<Map<String, Object?>> afterSelect(
    LocalDatabaseSqlStatement statement,
    List<Map<String, Object?>> rows,
  ) {
    final sql = statement.statements.single;
    if (sql.contains('FROM favorite_intentions')) {
      favoriteReads++;
      _failAt(_FaultPoint.rowsRead);
    } else if (sql.contains('long_term_relations')) {
      _failAt(_FaultPoint.countsRead);
    }
    return rows;
  }

  void _failAt(_FaultPoint point) {
    final error = _error;
    if (_point != point || error == null || failures > 0) return;
    failures++;
    throw error;
  }
}

/// Сохраняет события и то, что получатель разработчика записал бы в журнал.
final class _RecordingDiagnostics implements DiagnosticsSink {
  final _events = <DiagnosticsEvent>[];
  final rawMessages = <String>[];
  late final _developer = DeveloperDiagnosticsSink(rawMessages.add);

  List<DiagnosticsEvent> get events => List.unmodifiable(_events);

  List<FavoriteIntentionsReadDiagnosticsEvent> get readEvents =>
      _events.whereType<FavoriteIntentionsReadDiagnosticsEvent>().toList();

  /// Записи получателя разработчика.
  List<Map<String, Object?>> get messages => [
    for (final message in rawMessages)
      jsonDecode(message) as Map<String, Object?>,
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

final class _ThrowingDiagnosticsSink implements DiagnosticsSink {
  final List<DiagnosticsEvent> attemptedEvents = [];

  @override
  void record(DiagnosticsEvent event) {
    attemptedEvents.add(event);
    throw StateError('CANARY-отказ-получателя-диагностики');
  }
}

Matcher _failure(Matcher failure) => isA<FavoriteIntentionsError>().having(
  (result) => result.failure,
  'причина',
  failure,
);

Matcher _started() => isA<FavoriteIntentionsReadDiagnosticsEvent>()
    .having(
      (event) => event.stage,
      'этап',
      FavoriteIntentionsReadDiagnosticsStage.read,
    )
    .having((event) => event.status, 'исход', isA<DiagnosticsStarted>());

Matcher _succeeded() => isA<FavoriteIntentionsReadDiagnosticsEvent>()
    .having(
      (event) => event.stage,
      'этап',
      FavoriteIntentionsReadDiagnosticsStage.validation,
    )
    .having((event) => event.status, 'исход', isA<DiagnosticsSucceeded>());

Matcher _failed(
  FavoriteIntentionsReadDiagnosticsStage stage,
  DiagnosticsFailureCode code,
) => isA<FavoriteIntentionsReadDiagnosticsEvent>()
    .having((event) => event.stage, 'этап', stage)
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

String _uuid(int number) =>
    '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}';

IntentionId _id(int number) => switch (IntentionId.decode(_uuid(number))) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw ArgumentError.value(number, 'number'),
};

String _rowId(FavoriteIntentionRow row) => row.id.toCanonicalString();

/// Намерение фикстуры: время создания растёт с номером.
void _insertIntention(
  sqlite.Database database, {
  required int number,
  required String title,
  bool isArchived = false,
}) => _insertIntentionWithId(
  database,
  id: _uuid(number),
  title: title,
  isArchived: isArchived,
  createdAt: DateTime.utc(2026, 10, 1, 10, number),
);

/// Намерение с произвольным сохранённым идентификатором: схема его не
/// проверяет.
void _insertIntentionWithId(
  sqlite.Database database, {
  required String id,
  required String title,
  String? description,
  bool isArchived = false,
  DateTime? createdAt,
}) {
  final timestamp =
      (createdAt ?? DateTime.utc(2026, 10, 1, 11)).microsecondsSinceEpoch;
  database.execute(
    'INSERT INTO intentions (id, title, description, is_action_ready, '
    'is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
    [id, title, description, 0, isArchived ? 1 : 0, timestamp, timestamp],
  );
}

/// Записывает в поле намерения значение, которое схема отклоняет или
/// приложение не сохраняет. Проверка `CHECK` отключается только на время
/// записи этого значения.
void _corruptIntentionField(
  sqlite.Database database, {
  required int number,
  required String column,
  required Object? value,
}) {
  database.execute('PRAGMA ignore_check_constraints = ON');
  try {
    database.execute('UPDATE intentions SET $column = ? WHERE id = ?', [
      value,
      _uuid(number),
    ]);
  } finally {
    database.execute('PRAGMA ignore_check_constraints = OFF');
  }
}

int _connectionChanges(sqlite.Database database) =>
    database.select('SELECT total_changes() AS count').single['count'] as int;

/// Строки намерений и отметок для сравнения до и после чтения.
List<List<Map<String, Object?>>> _storedGraph(sqlite.Database database) => [
  for (final table in ['intentions', 'favorite_intentions'])
    [
      for (final row in database.select('SELECT * FROM $table ORDER BY 1, 2'))
        {...row},
    ],
];

Future<FavoriteIntentionsSnapshot> _favorites(
  DriftPersonalGraphRepository repository,
) async {
  final result = await repository.getFavoriteIntentions();
  expect(result, isA<FavoriteIntentionsSuccess>());
  return (result as FavoriteIntentionsSuccess).value;
}
