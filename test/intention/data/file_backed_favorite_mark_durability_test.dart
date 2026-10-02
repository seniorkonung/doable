import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:doable/src/data/local/app_database.dart' hide Intention;
import 'package:doable/src/data/local/bootstrap/local_data_bootstrap_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/doable_schema_verifier.dart';
import '../../support/favorite_storage_fixture.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/local_database_harness.dart';
import '../../support/tag_storage_fixture.dart';

const _workerOperationEnvironment = 'DOABLE_GRAPH_OPERATION';
const _workerStopPointEnvironment = 'DOABLE_GRAPH_STOP_POINT';
const _workerDatabasePathEnvironment = 'DOABLE_GRAPH_DATABASE_PATH';
const _workerStartedMarker = 'DOABLE_GRAPH_WORKER_STARTED';
const _workerReadyMarker = 'DOABLE_GRAPH_WORKER_READY';

/// Намерение фикстуры, которое отмечает и с которого снимает отметку
/// дочерний процесс.
const _workerIntentionNumber = 3;

void main() {
  group('Повторное открытие', () {
    test('сохраняет отметки и места, включая отметку архивированного '
        'намерения, и не возвращает снятую отметку', () async {
      final harness = await LocalDatabaseHarness.fileBacked();
      addTearDown(harness.dispose);
      late sqlite.Database raw;
      var repository = _repository(
        await harness.openReadyDatabase(setup: (db) => raw = db),
      );
      seedTagStorageFixture(raw);
      _insertIntention(raw, number: 4, title: 'Намерение 4');
      final graphBefore = _storedGraph(raw);

      // Второе намерение фикстуры архивировано.
      for (final number in [1, 2, 3, 4]) {
        await _saved(repository, MarkIntentionFavorite(_id(number)));
      }
      await _saved(repository, UnmarkIntentionFavorite(_id(3)));
      await harness.closePersistenceObjectGraph();

      repository = _repository(
        await harness.openReadyDatabase(setup: (db) => raw = db),
      );
      expect(storedFavoriteMarks(raw), [
        (tagFixtureId(1), 1),
        (tagFixtureId(2), 2),
        (tagFixtureId(4), 4),
      ]);
      expect(await _detailMarks(repository, [1, 2, 3, 4]), {
        1: FavoriteMark.favorite,
        2: FavoriteMark.favorite,
        3: FavoriteMark.notFavorite,
        4: FavoriteMark.favorite,
      });
      expect(await _catalogMarks(repository, IntentionScope.all), {
        tagFixtureId(1): FavoriteMark.favorite,
        tagFixtureId(2): FavoriteMark.favorite,
        tagFixtureId(3): FavoriteMark.notFavorite,
        tagFixtureId(4): FavoriteMark.favorite,
      });
      expect(await _catalogMarks(repository, IntentionScope.archived), {
        tagFixtureId(2): FavoriteMark.favorite,
      });
      final archived = await _details(repository, 2);
      expect(archived.intention.archiveState, IntentionArchiveState.archived);

      // Новая отметка после повторного открытия встаёт за сохранённым
      // максимумом, а не на освобождённое место.
      await _saved(repository, MarkIntentionFavorite(_id(3)));
      await harness.closePersistenceObjectGraph();

      await harness.openReadyDatabase(setup: (db) => raw = db);
      expect(storedFavoriteMarks(raw), [
        (tagFixtureId(1), 1),
        (tagFixtureId(2), 2),
        (tagFixtureId(4), 4),
        (tagFixtureId(3), 5),
      ]);
      expect(_storedGraph(raw), graphBefore);
      _expectIntegrity(raw);
    });

    test('подтверждённое снятие единственной отметки оставляет хранилище '
        'без отметок', () async {
      final harness = await LocalDatabaseHarness.fileBacked();
      addTearDown(harness.dispose);
      late sqlite.Database raw;
      var repository = _repository(
        await harness.openReadyDatabase(setup: (db) => raw = db),
      );
      seedTagStorageFixture(raw);
      await _saved(repository, MarkIntentionFavorite(_id(2)));
      await harness.closePersistenceObjectGraph();

      repository = _repository(
        await harness.openReadyDatabase(setup: (db) => raw = db),
      );
      expect(storedFavoriteMarks(raw), [(tagFixtureId(2), 1)]);
      await _saved(repository, UnmarkIntentionFavorite(_id(2)));
      await harness.closePersistenceObjectGraph();

      repository = _repository(
        await harness.openReadyDatabase(setup: (db) => raw = db),
      );
      expect(storedFavoriteMarks(raw), isEmpty);
      expect(
        (await _details(repository, 2)).favoriteMark,
        FavoriteMark.notFavorite,
      );
      _expectIntegrity(raw);
    });

    test('хранилище с намерениями, связями, тегами и дневными выборами без '
        'отметок остаётся без отметок', () async {
      final harness = await LocalDatabaseHarness.fileBacked();
      addTearDown(harness.dispose);
      late sqlite.Database raw;
      await harness.openReadyDatabase(setup: (db) => raw = db);
      seedTagStorageFixture(raw);
      final graphBefore = _storedGraph(raw);
      await harness.closePersistenceObjectGraph();

      // Открытия и чтения отметки не создают её.
      for (var restart = 0; restart < 2; restart++) {
        final repository = _repository(
          await harness.openReadyDatabase(setup: (db) => raw = db),
        );
        expect(storedFavoriteMarks(raw), isEmpty);
        expect(
          (await _detailMarks(repository, [1, 2, 3])).values,
          everyElement(FavoriteMark.notFavorite),
        );
        expect(
          (await _catalogMarks(repository, IntentionScope.all)).values,
          everyElement(FavoriteMark.notFavorite),
        );
        expect(storedFavoriteMarks(raw), isEmpty);
        expect(_storedGraph(raw), graphBefore);
        await harness.closePersistenceObjectGraph();
      }
    });
  });

  group('Остановка отдельного процесса', () {
    for (final operation in _FavoriteProcessOperation.values) {
      for (final stopPoint in _FavoriteProcessStopPoint.values) {
        test('${stopPoint.testDescription} ${operation.testDescription} '
            'оставляет целое состояние', () async {
          final harness = await LocalDatabaseHarness.fileBacked();
          addTearDown(harness.dispose);
          late sqlite.Database raw;
          await harness.openReadyDatabase(setup: (db) => raw = db);
          seedTagStorageFixture(raw);
          // Места с пропуском: отметка процесса встаёт за максимумом.
          storeFavoriteMark(raw, intentionId: tagFixtureId(1), position: 2);
          storeFavoriteMark(raw, intentionId: tagFixtureId(2), position: 5);
          if (operation == _FavoriteProcessOperation.unmark) {
            storeFavoriteMark(
              raw,
              intentionId: tagFixtureId(_workerIntentionNumber),
              position: 6,
            );
          }
          final marksBefore = storedFavoriteMarks(raw);
          final graphBefore = _storedGraph(raw);
          await harness.closePersistenceObjectGraph();

          await _runFavoriteWorkerUntilStopPoint(harness, operation, stopPoint);

          final database = await harness.openReadyDatabase(
            setup: (db) => raw = db,
          );
          final committed = stopPoint == _FavoriteProcessStopPoint.afterCommit;
          final isFavoriteAfter = switch (operation) {
            _FavoriteProcessOperation.mark => committed,
            _FavoriteProcessOperation.unmark => !committed,
          };
          expect(storedFavoriteMarks(raw), [
            (tagFixtureId(1), 2),
            (tagFixtureId(2), 5),
            if (isFavoriteAfter) (tagFixtureId(_workerIntentionNumber), 6),
          ]);
          if (!committed) expect(storedFavoriteMarks(raw), marksBefore);
          expect(
            (await _details(
              _repository(database),
              _workerIntentionNumber,
            )).favoriteMark,
            isFavoriteAfter ? FavoriteMark.favorite : FavoriteMark.notFavorite,
          );
          expect(_storedGraph(raw), graphBefore);
          _expectIntegrity(raw);
          await expectLater(verifyDoableDatabaseSchema(database), completes);
        }, timeout: Timeout.none);
      }
    }
  });

  group('Хранилище прежнего состава', () {
    test('с маркером версии 1 не дополняется, не удаляется и не '
        'пересоздаётся, а чтения возвращают неизвестный отказ', () async {
      final harness = await LocalDatabaseHarness.fileBacked();
      addTearDown(harness.dispose);
      late sqlite.Database raw;
      await harness.openReadyDatabase(setup: (db) => raw = db);
      seedTagStorageFixture(raw);
      await harness.closePersistenceObjectGraph();
      final previous = sqlite.sqlite3.open(harness.databaseFile.path);
      late final List<List<Object?>> schemaBefore;
      late final Map<String, List<List<Object?>>> graphBefore;
      try {
        // Состав до изменения: объектов избранного нет, маркер версии тот же.
        previous.execute('DROP TABLE favorite_intentions');
        schemaBefore = _storedSchema(previous);
        graphBefore = _storedGraph(previous);
        expect(_userVersion(previous), AppDatabase.currentSchemaVersion);
        expect(_favoriteSchemaObjects(previous), isEmpty);
      } finally {
        previous.close();
      }

      final opened = await harness.open(setup: (db) => raw = db);

      expect(opened, isA<LocalDataReady>());
      final repository = _repository((opened as LocalDataReady).database);
      expect(
        await repository.watchIntention(_id(1)).first,
        _unexpectedFailure<GraphSnapshot<IntentionDetails?>>(),
      );
      for (final scope in IntentionScope.values) {
        expect(
          await repository.getCatalogPage(_query(scope)),
          _unexpectedFailure<IntentionCatalogPage>(),
          reason: '$scope',
        );
      }
      expect(_storedSchema(raw), schemaBefore);
      expect(_storedGraph(raw), graphBefore);
      await harness.closePersistenceObjectGraph();

      expect(await harness.databaseFile.exists(), isTrue);
      final reopened = sqlite.sqlite3.open(harness.databaseFile.path);
      try {
        expect(_storedSchema(reopened), schemaBefore);
        expect(_favoriteSchemaObjects(reopened), isEmpty);
        expect(_userVersion(reopened), AppDatabase.currentSchemaVersion);
        expect(_storedGraph(reopened), graphBefore);
      } finally {
        reopened.close();
      }
    });
  });
}

DriftPersonalGraphRepository _repository(AppDatabase database) =>
    DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 10, 2, 12),
      InMemoryDiagnosticsSink(),
    );

IntentionId _id(int number) => switch (IntentionId.decode(
  tagFixtureId(number),
)) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw ArgumentError.value(number, 'number'),
};

void _insertIntention(
  sqlite.Database database, {
  required int number,
  required String title,
}) {
  database.execute(
    'INSERT INTO intentions (id, title, created_at, updated_at) '
    'VALUES (?, ?, ?, ?)',
    [tagFixtureId(number), title, 100 + number, 200 + number],
  );
}

IntentionCatalogQuery _query(IntentionScope scope) => IntentionCatalogQuery(
  scope: scope,
  titleFilter: null,
  order: IntentionCatalogOrder.createdAtAscending,
  pageSize: 10,
);

Future<IntentionSaved> _saved(
  DriftPersonalGraphRepository repository,
  ExistingIntentionCommand command,
) async {
  final result = await repository.execute(command);
  expect(
    result,
    isA<ResultSuccess<ConfirmedGraphResult<IntentionCommandSuccess>>>(),
    reason: '${command.runtimeType}',
  );
  return (result
              as ResultSuccess<ConfirmedGraphResult<IntentionCommandSuccess>>)
          .value
          .value
      as IntentionSaved;
}

Future<IntentionDetails> _details(
  DriftPersonalGraphRepository repository,
  int number,
) async {
  final result = await repository.watchIntention(_id(number)).first;
  expect(result, isA<ResultSuccess<GraphSnapshot<IntentionDetails?>>>());
  return (result as ResultSuccess<GraphSnapshot<IntentionDetails?>>)
      .value
      .value!;
}

Future<Map<int, FavoriteMark>> _detailMarks(
  DriftPersonalGraphRepository repository,
  List<int> numbers,
) async => {
  for (final number in numbers)
    number: (await _details(repository, number)).favoriteMark,
};

Future<Map<String, FavoriteMark>> _catalogMarks(
  DriftPersonalGraphRepository repository,
  IntentionScope scope,
) async {
  final result = await repository.getCatalogPage(_query(scope));
  expect(result, isA<ResultSuccess<IntentionCatalogPage>>());
  final page = (result as ResultSuccess<IntentionCatalogPage>).value;
  expect(page.nextCursor, isNull);
  return {
    for (final item in page.items)
      item.id.toCanonicalString(): item.favoriteMark,
  };
}

Matcher _unexpectedFailure<T>() => isA<ResultFailure<T>>().having(
  (result) => result.failure,
  'причина отказа',
  isA<IntentionUnexpectedFailure>(),
);

/// Строки графа вне избранного: намерения, связи, дневные выборы, теги и
/// назначения.
Map<String, List<List<Object?>>> _storedGraph(sqlite.Database database) => {
  ...retainedTagFixtureGraph(database),
  for (final table in ['tags', 'tag_assignments'])
    table: database
        .select('SELECT * FROM $table ORDER BY creation_sequence')
        .map((row) => row.values.toList())
        .toList(),
};

List<List<Object?>> _storedSchema(sqlite.Database database) => database
    .select('SELECT type, name, tbl_name, sql FROM sqlite_schema ORDER BY name')
    .map((row) => row.values.toList())
    .toList();

List<Object?> _favoriteSchemaObjects(sqlite.Database database) => database
    .select("SELECT name FROM sqlite_schema WHERE name LIKE '%favorite%'")
    .map((row) => row['name'])
    .toList();

int _userVersion(sqlite.Database database) =>
    database.select('PRAGMA user_version').single.values.single as int;

void _expectIntegrity(sqlite.Database database) {
  expect(database.select('PRAGMA integrity_check').single.values.single, 'ok');
  expect(database.select('PRAGMA foreign_key_check'), isEmpty);
}

Future<void> _runFavoriteWorkerUntilStopPoint(
  LocalDatabaseHarness harness,
  _FavoriteProcessOperation operation,
  _FavoriteProcessStopPoint stopPoint,
) async {
  final workerPath = File.fromUri(
    Directory.current.uri.resolve(
      'test/support/graph_operation_process_worker.dart',
    ),
  ).path;
  final process = await Process.start(
    _findFlutterExecutable(),
    ['test', '--no-pub', '--reporter', 'compact', workerPath],
    workingDirectory: Directory.current.path,
    environment: {
      _workerOperationEnvironment: operation.environmentValue,
      _workerStopPointEnvironment: stopPoint.environmentValue,
      _workerDatabasePathEnvironment: harness.databaseFile.path,
    },
  );
  final stdoutBuffer = StringBuffer();
  final stderrBuffer = StringBuffer();
  final ready = Completer<int>();
  final startedPidPattern = RegExp('$_workerStartedMarker:(\\d+)');
  final readyPidPattern = RegExp('$_workerReadyMarker:(\\d+)');
  final stdoutDone = Completer<void>();
  final stderrDone = Completer<void>();
  int? startedWorkerPid;

  process.stdout.transform(utf8.decoder).listen((chunk) {
    stdoutBuffer.write(chunk);
    final output = stdoutBuffer.toString();
    final startedMatch = startedPidPattern.firstMatch(output);
    if (startedMatch != null) {
      startedWorkerPid = int.parse(startedMatch.group(1)!);
    }
    final readyMatch = readyPidPattern.firstMatch(output);
    if (readyMatch != null && !ready.isCompleted) {
      ready.complete(int.parse(readyMatch.group(1)!));
    }
  }, onDone: stdoutDone.complete);
  process.stderr
      .transform(utf8.decoder)
      .listen(stderrBuffer.write, onDone: stderrDone.complete);
  unawaited(
    process.exitCode.then((exitCode) {
      if (!ready.isCompleted) {
        ready.completeError(
          StateError(
            'Процесс операции отметки завершился с кодом $exitCode до точки '
            '${stopPoint.environmentValue}.\nstdout:\n$stdoutBuffer\n'
            'stderr:\n$stderrBuffer',
          ),
        );
      }
    }),
  );

  var workerWasKilled = false;
  try {
    final workerPid = await ready.future.timeout(
      const Duration(seconds: 45),
      onTimeout: () => throw TimeoutException(
        'Процесс операции отметки не достиг точки '
        '${stopPoint.environmentValue}.\nstdout:\n$stdoutBuffer\n'
        'stderr:\n$stderrBuffer',
      ),
    );
    workerWasKilled = Process.killPid(workerPid, ProcessSignal.sigkill);
    expect(
      workerWasKilled,
      isTrue,
      reason: 'Не удалось принудительно завершить процесс операции отметки.',
    );
  } finally {
    if (!workerWasKilled) {
      final workerPid = startedWorkerPid;
      if (workerPid != null) {
        Process.killPid(workerPid, ProcessSignal.sigkill);
      }
      process.kill(ProcessSignal.sigkill);
    }
  }

  final exitCode = await process.exitCode.timeout(const Duration(seconds: 15));
  await Future.wait([stdoutDone.future, stderrDone.future]);
  expect(exitCode, isNot(0));
}

String _findFlutterExecutable() {
  var directory = File(Platform.resolvedExecutable).parent;
  while (true) {
    final candidate = File(
      '${directory.path}/bin/${Platform.isWindows ? 'flutter.bat' : 'flutter'}',
    );
    if (candidate.existsSync()) return candidate.path;
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError(
        'Не удалось найти Flutter SDK от Platform.resolvedExecutable.',
      );
    }
    directory = parent;
  }
}

enum _FavoriteProcessOperation {
  mark(environmentValue: 'favorite_mark', testDescription: 'отметки'),
  unmark(
    environmentValue: 'favorite_unmark',
    testDescription: 'снятия отметки',
  );

  const _FavoriteProcessOperation({
    required this.environmentValue,
    required this.testDescription,
  });

  final String environmentValue;
  final String testDescription;
}

enum _FavoriteProcessStopPoint {
  beforeCommit(
    environmentValue: 'before_commit',
    testDescription: 'до подтверждения',
  ),
  afterCommit(
    environmentValue: 'after_commit',
    testDescription: 'после подтверждения',
  );

  const _FavoriteProcessStopPoint({
    required this.environmentValue,
    required this.testDescription,
  });

  final String environmentValue;
  final String testDescription;
}
