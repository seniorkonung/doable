import 'package:doable/src/data/local/app_database.dart' hide Intention;
import 'package:doable/src/data/local/bootstrap/local_data_bootstrap_result.dart';
import 'package:doable/src/favorite/application/favorite_intentions.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/favorite_storage_fixture.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/local_database_harness.dart';
import '../../support/tag_storage_fixture.dart';

/// Строка списка, сравниваемая до и после повторного открытия.
typedef _Row = (String id, String title, IntentionReadiness readiness, int);

void main() {
  group('Повторное открытие', () {
    test('возвращает те же избранные намерения в том же едином порядке и не '
        'возвращает снятую отметку', () async {
      final harness = await LocalDatabaseHarness.fileBacked();
      addTearDown(harness.dispose);
      late sqlite.Database raw;
      var repository = _repository(
        await harness.openReadyDatabase(setup: (db) => raw = db),
      );
      seedTagStorageFixture(raw);
      _insertIntention(raw, number: 4, title: 'Намерение 4');
      _insertIntention(raw, number: 5, title: 'Намерение 1');
      final graphBefore = _storedGraph(raw);

      // Отметки ставятся против порядка идентификаторов и времени создания;
      // второе намерение фикстуры архивировано.
      for (final number in [4, 2, 5, 1, 3]) {
        await _saved(repository, MarkIntentionFavorite(_id(number)));
      }
      await _saved(repository, UnmarkIntentionFavorite(_id(5)));
      final before = await _favorites(repository);
      expect(before.items.map(_rowId), [
        tagFixtureId(4),
        tagFixtureId(1),
        tagFixtureId(3),
      ]);
      expect(before.archivedCount, 1);
      await harness.closePersistenceObjectGraph();

      for (var restart = 0; restart < 2; restart++) {
        repository = _repository(
          await harness.openReadyDatabase(setup: (db) => raw = db),
        );
        final after = await _favorites(repository);
        expect(after.items.map(_row), before.items.map(_row));
        expect(after.archivedCount, before.archivedCount);
        expect(storedFavoriteMarks(raw), [
          (tagFixtureId(4), 1),
          (tagFixtureId(2), 2),
          (tagFixtureId(1), 4),
          (tagFixtureId(3), 5),
        ]);
        expect(_storedGraph(raw), graphBefore);
        _expectIntegrity(raw);
        await harness.closePersistenceObjectGraph();
      }
    });

    test('сохраняет место архивированного избранного намерения, и после '
        'восстановления оно стоит на прежнем месте', () async {
      final harness = await LocalDatabaseHarness.fileBacked();
      addTearDown(harness.dispose);
      late sqlite.Database raw;
      var repository = _repository(
        await harness.openReadyDatabase(setup: (db) => raw = db),
      );
      seedTagStorageFixture(raw);
      _insertIntention(raw, number: 4, title: 'Намерение 4');
      // Второе намерение фикстуры архивировано до отметки, четвёртое
      // архивируется уже избранным.
      for (final number in [3, 2, 4, 1]) {
        await _saved(repository, MarkIntentionFavorite(_id(number)));
      }
      await _saved(repository, ArchiveIntention(_id(4)));
      final marks = [
        (tagFixtureId(3), 1),
        (tagFixtureId(2), 2),
        (tagFixtureId(4), 3),
        (tagFixtureId(1), 4),
      ];
      expect(await _order(repository), [tagFixtureId(3), tagFixtureId(1)]);
      await harness.closePersistenceObjectGraph();

      repository = _repository(
        await harness.openReadyDatabase(setup: (db) => raw = db),
      );
      final hidden = await _favorites(repository);
      expect(hidden.items.map(_rowId), [tagFixtureId(3), tagFixtureId(1)]);
      expect(hidden.archivedCount, 2);
      expect(storedFavoriteMarks(raw), marks);

      // Восстановление после повторного открытия возвращает намерение на
      // сохранённое место.
      await _saved(repository, RestoreIntention(_id(2)));
      expect(await _order(repository), [
        tagFixtureId(3),
        tagFixtureId(2),
        tagFixtureId(1),
      ]);
      await harness.closePersistenceObjectGraph();

      repository = _repository(
        await harness.openReadyDatabase(setup: (db) => raw = db),
      );
      final restored = await _favorites(repository);
      expect(restored.items.map(_rowId), [
        tagFixtureId(3),
        tagFixtureId(2),
        tagFixtureId(1),
      ]);
      expect(restored.archivedCount, 1);
      await _saved(repository, RestoreIntention(_id(4)));
      await harness.closePersistenceObjectGraph();

      repository = _repository(
        await harness.openReadyDatabase(setup: (db) => raw = db),
      );
      final all = await _favorites(repository);
      expect(all.items.map(_rowId), [
        tagFixtureId(3),
        tagFixtureId(2),
        tagFixtureId(4),
        tagFixtureId(1),
      ]);
      expect(all.archivedCount, 0);
      expect(storedFavoriteMarks(raw), marks);
      _expectIntegrity(raw);
    });

    test(
      'подтверждённое снятие единственной отметки даёт пустой снимок',
      () async {
        final harness = await LocalDatabaseHarness.fileBacked();
        addTearDown(harness.dispose);
        late sqlite.Database raw;
        var repository = _repository(
          await harness.openReadyDatabase(setup: (db) => raw = db),
        );
        seedTagStorageFixture(raw);
        await _saved(repository, MarkIntentionFavorite(_id(1)));
        await harness.closePersistenceObjectGraph();

        repository = _repository(
          await harness.openReadyDatabase(setup: (db) => raw = db),
        );
        expect(await _order(repository), [tagFixtureId(1)]);
        await _saved(repository, UnmarkIntentionFavorite(_id(1)));
        await harness.closePersistenceObjectGraph();

        repository = _repository(
          await harness.openReadyDatabase(setup: (db) => raw = db),
        );
        final snapshot = await _favorites(repository);
        expect(snapshot.items, isEmpty);
        expect(snapshot.archivedCount, 0);
        expect(storedFavoriteMarks(raw), isEmpty);
      },
    );

    test('хранилище с намерениями, связями, тегами и дневными выборами без '
        'отметок даёт пустой снимок и не получает отметок', () async {
      final harness = await LocalDatabaseHarness.fileBacked();
      addTearDown(harness.dispose);
      late sqlite.Database raw;
      await harness.openReadyDatabase(setup: (db) => raw = db);
      seedTagStorageFixture(raw);
      final graphBefore = _storedGraph(raw);
      for (final table in graphBefore.keys) {
        expect(graphBefore[table], isNotEmpty, reason: table);
      }
      await harness.closePersistenceObjectGraph();

      // Открытия и чтения списка не создают отметок.
      for (var restart = 0; restart < 2; restart++) {
        final repository = _repository(
          await harness.openReadyDatabase(setup: (db) => raw = db),
        );
        final snapshot = await _favorites(repository);
        expect(snapshot.items, isEmpty);
        expect(snapshot.archivedCount, 0);
        expect(storedFavoriteMarks(raw), isEmpty);
        expect(_storedGraph(raw), graphBefore);
        await harness.closePersistenceObjectGraph();
      }
    });
  });

  group('Хранилище прежнего состава', () {
    test(
      'с маркером версии 1 возвращает неповторяемый неизвестный отказ, а не '
      'пустой снимок, и не дополняется, не удаляется и не пересоздаётся',
      () async {
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
        // Повтор не восстанавливает чтение: отказ остаётся тем же.
        for (var attempt = 0; attempt < 2; attempt++) {
          final result = await repository.getFavoriteIntentions();
          expect(
            result,
            isA<FavoriteIntentionsError>().having(
              (error) => error.failure,
              'причина отказа',
              isA<FavoriteIntentionsUnexpectedFailure>().having(
                (failure) => failure.category,
                'категория',
                GraphFailureCategory.unexpected,
              ),
            ),
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
      },
    );
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

String _rowId(FavoriteIntentionRow row) => row.id.toCanonicalString();

_Row _row(FavoriteIntentionRow row) =>
    (_rowId(row), row.title, row.readiness, row.activeRelationCount);

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

Future<void> _saved(
  DriftPersonalGraphRepository repository,
  ExistingIntentionCommand command,
) async {
  expect(
    await repository.execute(command),
    isA<ResultSuccess<ConfirmedGraphResult<IntentionCommandSuccess>>>(),
    reason: '${command.runtimeType}',
  );
}

Future<FavoriteIntentionsSnapshot> _favorites(
  DriftPersonalGraphRepository repository,
) async {
  final result = await repository.getFavoriteIntentions();
  expect(result, isA<FavoriteIntentionsSuccess>());
  return (result as FavoriteIntentionsSuccess).value;
}

/// Идентификаторы строк списка в порядке снимка.
Future<List<String>> _order(DriftPersonalGraphRepository repository) async =>
    (await _favorites(repository)).items.map(_rowId).toList();

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
