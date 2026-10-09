import 'package:doable/src/data/local/app_database.dart' hide Intention;
import 'package:doable/src/favorite/application/favorite_intentions.dart';
import 'package:doable/src/favorite/application/favorite_order_command.dart';
import 'package:doable/src/favorite/domain/favorite_order.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
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
    for (final (point, fault) in [
      (_FaultPoint.orderRead, _unavailableFault),
      (_FaultPoint.afterAssignment, _corruptionFault),
      (_FaultPoint.afterAssignment, _unexpectedFault),
    ]) {
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
  });

  group('Повтор после отказа', () {
    test('после недоступности ${_FaultPoint.afterAssignment.description} '
        'перестановка выполняется новой командой целиком', () async {
      await seedGraph();
      final revisionBefore = await _graphRevision(repository);
      faults.arm(_FaultPoint.afterAssignment, _busy);
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

    const maxPlace = _largestShiftablePlace + 1;
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
}

/// Наибольшее место, сдвиг которого за самого себя остаётся целым числом.
const _largestShiftablePlace = 4611686018427387903;

final _moveTwoFirst = MoveFavoriteIntention(
  intentionId: _id(2),
  placement: const FirstFavoritePlacement(),
);

/// Повреждения сохранённого порядка, недостижимые через приложение, рядом
/// со скрытыми архивированными намерениями 6 и 7 — по одному на каждую
/// проверку прочитанного порядка. Целостный порядок: 1 на месте 2, 2 на
/// месте 6, 3 на месте 10.
final _storedCorruptions =
    <({String name, void Function(sqlite.Database) store})>[
      (
        name: 'дробное место скрытого архивированного намерения',
        store: (database) => storeFavoriteMarkWithInvalidPosition(
          database,
          intentionId: _uuid(6),
          position: 4.5,
        ),
      ),
      (
        name: 'нулевое место скрытого архивированного намерения',
        store: (database) => storeFavoriteMarkWithInvalidPosition(
          database,
          intentionId: _uuid(6),
          position: 0,
        ),
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

typedef _StorageFault = ({
  String name,
  Object error,
  Matcher failure,
  DiagnosticsFailureCode code,
});

/// Отказы хранилища трёх различимых категорий.
final _StorageFault _unavailableFault = (
  name: 'недоступность',
  error: _busy,
  failure: isA<FavoriteOrderUnavailableFailure>(),
  code: DiagnosticsFailureCode.unavailable,
);

final _StorageFault _corruptionFault = (
  name: 'повреждение',
  error: _corrupt,
  failure: isA<FavoriteOrderCorruptionFailure>(),
  code: DiagnosticsFailureCode.corruption,
);

final _StorageFault _unexpectedFault = (
  name: 'неизвестный отказ',
  error: StateError('CANARY-неизвестный-отказ'),
  failure: isA<FavoriteOrderUnexpectedFailure>(),
  code: DiagnosticsFailureCode.unexpected,
);

/// Шаг перестановки, на котором хранилище отказывает.
enum _FaultPoint {
  /// Чтение полного порядка отклонено до выполнения.
  orderRead(
    'при чтении порядка',
    FavoriteOrderCommandDiagnosticsStage.read,
    executedWritesBeforeFailure: 0,
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

  /// Число сработавших отказов с последнего [arm].
  var failures = 0;

  /// Инструкции записи мест, дошедшие до хранилища.
  final writes = <String>[];

  /// Записи мест, выполненные хранилищем.
  var executedWrites = 0;

  void arm(_FaultPoint point, Object error) {
    clear();
    _point = point;
    _error = error;
    failures = 0;
  }

  void disarm() {
    _point = null;
    _error = null;
  }

  void clear() {
    writes.clear();
    executedWrites = 0;
  }

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (_isOrderRead(statement)) {
      _failAt(_FaultPoint.orderRead);
      return;
    }
    if (!_isPlaceWrite(statement)) return;
    writes.addAll(statement.statements);
  }

  @override
  void afterStatement(LocalDatabaseSqlStatement statement) {
    if (!_isPlaceWrite(statement)) return;
    executedWrites++;
    if (executedWrites == 2) _failAt(_FaultPoint.afterAssignment);
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
    throw error;
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

/// Сохраняет события диагностики перестановки.
final class _RecordingDiagnostics implements DiagnosticsSink {
  final _events = <DiagnosticsEvent>[];

  List<FavoriteOrderCommandDiagnosticsEvent> get orderEvents =>
      _events.whereType<FavoriteOrderCommandDiagnosticsEvent>().toList();

  void clear() {
    _events.clear();
  }

  @override
  void record(DiagnosticsEvent event) {
    _events.add(event);
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
