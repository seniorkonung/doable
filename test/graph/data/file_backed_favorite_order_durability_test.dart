import 'package:doable/src/data/local/app_database.dart' hide Intention;
import 'package:doable/src/favorite/application/favorite_intentions.dart';
import 'package:doable/src/favorite/application/favorite_order_command.dart';
import 'package:doable/src/favorite/domain/favorite_order.dart';
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

import '../../support/favorite_storage_fixture.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/local_database_harness.dart';
import '../../support/tag_storage_fixture.dart';

/// Сохранённая отметка фикстуры: номер намерения и его место.
typedef _Mark = (int number, int position);

void main() {
  group('Повторное открытие после перестановки', () {
    test('сохраняет весь порядок и отметки, включая место скрытого '
        'архивированного намерения, а восстановление возвращает его на это '
        'место', () async {
      final harness = await LocalDatabaseHarness.fileBacked();
      addTearDown(harness.dispose);
      late sqlite.Database raw;
      var repository = _repository(
        await harness.openReadyDatabase(setup: (db) => raw = db),
      );
      // Избранные в этом порядке: 1, архивированное 2, 3, архивированное 4
      // и 5.
      _seedGraph(raw);
      for (final number in [1, 2, 3, 4, 5]) {
        await _saved(repository, MarkIntentionFavorite(_id(number)));
      }
      await _saved(repository, ArchiveIntention(_id(4)));
      final graphBefore = _storedGraph(raw);

      await _moved(repository, _move(5, after: 1));
      expect(await _order(repository), [1, 5, 3]);
      await harness.closePersistenceObjectGraph();

      const marks = <_Mark>[(1, 1), (5, 2), (2, 3), (3, 4), (4, 5)];
      for (var restart = 0; restart < 2; restart++) {
        repository = _repository(
          await harness.openReadyDatabase(setup: (db) => raw = db),
        );
        expect(_storedMarks(raw), marks);
        final snapshot = await _favorites(repository);
        expect(_ids(snapshot), [1, 5, 3]);
        expect(snapshot.archivedCount, 2);
        expect(
          (await _detailMarks(repository, [1, 2, 3, 4, 5])).values,
          everyElement(FavoriteMark.favorite),
        );
        expect(_storedGraph(raw), graphBefore);
        _expectIntegrity(raw);
        await harness.closePersistenceObjectGraph();
      }

      repository = _repository(
        await harness.openReadyDatabase(setup: (db) => raw = db),
      );
      await _saved(repository, RestoreIntention(_id(2)));
      expect(await _order(repository), [1, 5, 2, 3]);
      await harness.closePersistenceObjectGraph();

      repository = _repository(
        await harness.openReadyDatabase(setup: (db) => raw = db),
      );
      final restored = await _favorites(repository);
      expect(_ids(restored), [1, 5, 2, 3]);
      expect(restored.archivedCount, 1);
      await _saved(repository, RestoreIntention(_id(4)));
      await harness.closePersistenceObjectGraph();

      repository = _repository(
        await harness.openReadyDatabase(setup: (db) => raw = db),
      );
      final all = await _favorites(repository);
      expect(_ids(all), [1, 5, 2, 3, 4]);
      expect(all.archivedCount, 0);
      expect(_storedMarks(raw), marks);
      _expectIntegrity(raw);
    });

    test('сохраняет место намерения, перемещённого первым перед скрытым '
        'архивированным намерением', () async {
      final harness = await LocalDatabaseHarness.fileBacked();
      addTearDown(harness.dispose);
      late sqlite.Database raw;
      var repository = _repository(
        await harness.openReadyDatabase(setup: (db) => raw = db),
      );
      // Избранные в этом порядке: архивированное 2, 1 и 3.
      _seedGraph(raw);
      for (final number in [2, 1, 3]) {
        await _saved(repository, MarkIntentionFavorite(_id(number)));
      }

      await _moved(repository, _moveFirst(3));
      await harness.closePersistenceObjectGraph();

      repository = _repository(
        await harness.openReadyDatabase(setup: (db) => raw = db),
      );
      expect(_storedMarks(raw), [(3, 1), (2, 2), (1, 3)]);
      expect(await _order(repository), [3, 1]);
      await _saved(repository, RestoreIntention(_id(2)));
      await harness.closePersistenceObjectGraph();

      repository = _repository(
        await harness.openReadyDatabase(setup: (db) => raw = db),
      );
      expect(await _order(repository), [3, 2, 1]);
      expect(_storedMarks(raw), [(3, 1), (2, 2), (1, 3)]);
      _expectIntegrity(raw);
    });

    test('снятие и повторная отметка после перестановки ставят намерение в '
        'конец всего порядка, и это сохраняется', () async {
      final harness = await LocalDatabaseHarness.fileBacked();
      addTearDown(harness.dispose);
      late sqlite.Database raw;
      var repository = _repository(
        await harness.openReadyDatabase(setup: (db) => raw = db),
      );
      // Избранные в этом порядке: 1, 5, архивированное 2, 3 и
      // архивированное 4.
      _seedGraph(raw);
      for (final number in [1, 2, 3, 4, 5]) {
        await _saved(repository, MarkIntentionFavorite(_id(number)));
      }
      await _saved(repository, ArchiveIntention(_id(4)));
      await _moved(repository, _move(5, after: 1));
      await harness.closePersistenceObjectGraph();

      repository = _repository(
        await harness.openReadyDatabase(setup: (db) => raw = db),
      );
      await _saved(repository, UnmarkIntentionFavorite(_id(1)));
      await _saved(repository, MarkIntentionFavorite(_id(1)));
      await harness.closePersistenceObjectGraph();

      repository = _repository(
        await harness.openReadyDatabase(setup: (db) => raw = db),
      );
      // Повторно отмеченное намерение встаёт после скрытого архивированного
      // последнего, а не на прежнее первое место.
      expect(_storedMarks(raw), [(5, 2), (2, 3), (3, 4), (4, 5), (1, 6)]);
      final snapshot = await _favorites(repository);
      expect(_ids(snapshot), [5, 3, 1]);
      expect(snapshot.archivedCount, 2);
      expect(
        (await _details(repository, 1)).favoriteMark,
        FavoriteMark.favorite,
      );
      _expectIntegrity(raw);
    });

    test(
      'перестановки не меняют показания времени намерений при переводе '
      'часов назад и вперёд, в том числе после повторного открытия',
      () async {
        final harness = await LocalDatabaseHarness.fileBacked();
        addTearDown(harness.dispose);
        late sqlite.Database raw;
        final markedAt = DateTime.utc(2026, 10, 3, 12);
        var now = markedAt;
        DateTime clock() => now;
        var repository = _repository(
          await harness.openReadyDatabase(setup: (db) => raw = db),
          clock: clock,
        );
        // Избранные в этом порядке: 1, архивированное 2, 3, 4 и 5.
        _seedGraph(raw);
        for (final number in [1, 2, 3, 4, 5]) {
          await _saved(repository, MarkIntentionFavorite(_id(number)));
        }
        final graphBefore = _storedGraph(raw);

        now = markedAt.subtract(const Duration(days: 1));
        await _moved(repository, _moveFirst(5));
        now = markedAt.add(const Duration(days: 30));
        await _moved(repository, _move(1, after: 3));

        expect(_storedGraph(raw), graphBefore);
        expect(_storedMarks(raw), [(5, 1), (2, 2), (3, 3), (1, 4), (4, 5)]);
        await harness.closePersistenceObjectGraph();

        now = markedAt.subtract(const Duration(days: 365));
        repository = _repository(
          await harness.openReadyDatabase(setup: (db) => raw = db),
          clock: clock,
        );
        expect(_storedMarks(raw), [(5, 1), (2, 2), (3, 3), (1, 4), (4, 5)]);
        expect(await _order(repository), [5, 3, 1, 4]);
        expect(_storedGraph(raw), graphBefore);

        await _moved(repository, _move(4, after: 5));
        await harness.closePersistenceObjectGraph();

        await harness.openReadyDatabase(setup: (db) => raw = db);
        expect(_storedMarks(raw), [(5, 1), (4, 2), (2, 3), (3, 4), (1, 5)]);
        expect(_storedGraph(raw), graphBefore);
        _expectIntegrity(raw);
      },
    );
  });
}

DriftPersonalGraphRepository _repository(
  AppDatabase database, {
  DateTime Function()? clock,
}) => DriftPersonalGraphRepository(
  database,
  UuidV7IntentionIdGenerator(),
  clock ?? () => DateTime.utc(2026, 10, 3, 12),
  InMemoryDiagnosticsSink(),
);

IntentionId _id(int number) => switch (IntentionId.decode(
  tagFixtureId(number),
)) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw ArgumentError.value(number, 'number'),
};

MoveFavoriteIntention _move(int number, {required int after}) =>
    MoveFavoriteIntention(
      intentionId: _id(number),
      placement: AfterFavoritePlacement(_id(after)),
    );

MoveFavoriteIntention _moveFirst(int number) => MoveFavoriteIntention(
  intentionId: _id(number),
  placement: const FirstFavoritePlacement(),
);

/// Граф фикстуры тегов со связями и дневным выбором: активные 1 и 3 и
/// архивированное 2, а также активные 4 и 5 без связей.
void _seedGraph(sqlite.Database database) {
  seedTagStorageFixture(database);
  for (final number in [4, 5]) {
    database.execute(
      'INSERT INTO intentions (id, title, created_at, updated_at) '
      'VALUES (?, ?, ?, ?)',
      [tagFixtureId(number), 'Намерение $number', 100 + number, 200 + number],
    );
  }
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

Future<void> _moved(
  DriftPersonalGraphRepository repository,
  MoveFavoriteIntention command,
) async {
  final result = await repository.execute(command);
  switch (result) {
    case FavoriteOrderCommandSucceeded(:final value):
      expect(value.value, isA<FavoriteOrderMoved>());
    case FavoriteOrderCommandFailed(:final failure):
      fail('Ожидался успех перестановки, получен ${failure.runtimeType}.');
  }
}

Future<FavoriteIntentionsSnapshot> _favorites(
  DriftPersonalGraphRepository repository,
) async {
  final result = await repository.getFavoriteIntentions();
  expect(result, isA<FavoriteIntentionsSuccess>());
  return (result as FavoriteIntentionsSuccess).value;
}

/// Номера намерений списка Главной в порядке снимка.
List<int> _ids(FavoriteIntentionsSnapshot snapshot) => [
  for (final row in snapshot.items)
    int.parse(row.id.toCanonicalString().split('-').last, radix: 16),
];

Future<List<int>> _order(DriftPersonalGraphRepository repository) async =>
    _ids(await _favorites(repository));

/// Сохранённые отметки в порядке мест с номерами намерений фикстуры.
List<_Mark> _storedMarks(sqlite.Database database) => [
  for (final (intentionId, position) in storedFavoriteMarks(database))
    (int.parse(intentionId.split('-').last, radix: 16), position),
];

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

/// Строки графа вне избранного, включая показания времени намерений и
/// поисковую проекцию: намерения, связи, дневные выборы, теги и назначения.
Map<String, List<List<Object?>>> _storedGraph(sqlite.Database database) => {
  ...retainedTagFixtureGraph(database),
  for (final table in ['tags', 'tag_assignments'])
    table: database
        .select('SELECT * FROM $table ORDER BY creation_sequence')
        .map((row) => row.values.toList())
        .toList(),
};

void _expectIntegrity(sqlite.Database database) {
  expect(database.select('PRAGMA integrity_check').single.values.single, 'ok');
  expect(database.select('PRAGMA foreign_key_check'), isEmpty);
}
