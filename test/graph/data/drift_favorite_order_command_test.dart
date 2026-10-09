import 'package:doable/src/data/local/app_database.dart' hide Intention;
import 'package:doable/src/favorite/application/favorite_intentions.dart';
import 'package:doable/src/favorite/application/favorite_order_command.dart';
import 'package:doable/src/favorite/domain/favorite_order.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/daily_choice_durability_fixture.dart';
import '../../support/favorite_storage_fixture.dart';
import '../../support/in_memory_diagnostics_sink.dart';

void main() {
  late AppDatabase database;
  late sqlite.Database raw;
  late InMemoryDiagnosticsSink diagnostics;
  late _WriteTrace trace;
  late DriftPersonalGraphRepository repository;

  setUp(() async {
    diagnostics = InMemoryDiagnosticsSink();
    trace = _WriteTrace();
    database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(setup: (connection) => raw = connection),
        trace,
      ),
    );
    await database.open();
    repository = _repository(database, diagnostics);
  });

  tearDown(() => database.close());

  group('Правило перестановки на реальном хранилище', () {
    test('одноимённые намерения различаются по идентификатору', () async {
      _insertFavorite(raw, number: 1, title: 'Гулять', position: 1);
      _insertFavorite(raw, number: 2, title: 'Читать', position: 2);
      _insertFavorite(raw, number: 3, title: 'Гулять', position: 3);

      await _moved(repository, _move(3, after: 1));

      expect(_storedOrder(raw), _uuids([1, 3, 2]));
    });

    test('подтверждённое архивирование перемещаемого намерения и опоры не '
        'отклоняет перестановку', () async {
      for (final number in [1, 2, 3, 4]) {
        _insertFavorite(
          raw,
          number: number,
          title: '$number',
          position: number,
        );
      }
      await _succeeded(repository, ArchiveIntention(_id(1)));
      await _succeeded(repository, ArchiveIntention(_id(4)));

      await _moved(repository, _move(4, after: 1));

      expect(_storedOrder(raw), _uuids([1, 4, 2, 3]));
    });

    test('каждое размещение активного намерения между архивированными '
        'совпадает с правилом перестановки над полным порядком', () async {
      // Архивированные намерения стоят в начале, между активными и в конце,
      // а места идут с пропусками.
      const initial = [
        (number: 1, position: 2, archived: true),
        (number: 2, position: 5, archived: false),
        (number: 3, position: 6, archived: true),
        (number: 4, position: 11, archived: false),
        (number: 5, position: 12, archived: false),
        (number: 6, position: 30, archived: true),
      ];
      for (final entry in initial) {
        _insertIntention(
          raw,
          number: entry.number,
          title: 'Намерение ${entry.number}',
          isArchived: entry.archived,
        );
      }
      final order = FavoriteOrder([
        for (final entry in initial)
          FavoriteOrderEntry(
            intentionId: _id(entry.number),
            archiveState: entry.archived
                ? IntentionArchiveState.archived
                : IntentionArchiveState.active,
          ),
      ]);
      final storedInitial = [
        for (final entry in initial) (_uuid(entry.number), entry.position),
      ];
      final placements = <FavoritePlacement>[
        const FirstFavoritePlacement(),
        for (final entry in initial) AfterFavoritePlacement(_id(entry.number)),
      ];

      // Активное намерение 4 стоит между архивированными 3 и 6.
      final moved = initial[3];
      for (final placement in placements) {
        _replaceStoredMarks(raw, storedInitial);
        final command = MoveFavoriteIntention(
          intentionId: _id(moved.number),
          placement: placement,
        );
        final reason = '${moved.number} → ${_placementName(placement)}';

        final result = await repository.execute(command);

        switch (moveInFavoriteOrder(
          order,
          intentionId: command.intentionId,
          placement: placement,
        )) {
          case FavoriteOrderMoveApplied(order: final expected):
            expect(_successOf(result), isA<FavoriteOrderMoved>());
            expect(storedFavoriteMarks(raw), [
              for (final (index, id) in expected.intentionIds.indexed)
                (id.toCanonicalString(), index + 1),
            ], reason: reason);
          case FavoriteOrderMoveWithoutChange():
            expect(
              _successOf(result),
              isA<FavoriteOrderUnchanged>(),
              reason: reason,
            );
            expect(storedFavoriteMarks(raw), storedInitial, reason: reason);
          case final FavoriteOrderMoveRejected rejection:
            expect(
              _failureOf(result).runtimeType,
              FavoriteOrderCommandFailure.rejected(rejection).runtimeType,
              reason: reason,
            );
            expect(storedFavoriteMarks(raw), storedInitial, reason: reason);
        }
      }
    });
  });

  group('Запись мест', () {
    const count = 3;
    test('перестановка $count избранных переписывает места значениями '
        '1..$count двумя пакетными инструкциями', () async {
      // Места идут с пропусками и не начинаются с единицы.
      for (var number = 1; number <= count; number++) {
        _insertFavorite(
          raw,
          number: number,
          title: 'Намерение $number',
          position: number * 3 + 4,
        );
      }
      trace.clear();

      await _moved(repository, _move(count, first: true));

      expect(
        _storedOrder(raw),
        _uuids([count, for (var n = 1; n < count; n++) n]),
      );
      expect(storedFavoriteMarks(raw).map((mark) => mark.$2), [
        for (var place = 1; place <= count; place++) place,
      ]);
      expect(trace.writes, hasLength(2));
      expect(
        trace.writes,
        everyElement(startsWith('UPDATE favorite_intentions')),
      );
    });

    test('промежуточные места положительны, уникальны и не совпадают ни с '
        'прежними, ни с итоговыми', () async {
      for (final (number, position) in [(1, 3), (2, 8), (3, 20)]) {
        _insertFavorite(
          raw,
          number: number,
          title: '$number',
          position: position,
        );
      }
      final placeLog = _PlaceLog.install(raw);

      await _moved(repository, _move(3, after: 1));

      final shifted = placeLog.updates.take(3).map((update) => update.after);
      final assigned = placeLog.updates.skip(3).map((update) => update.after);
      expect(placeLog.updates, hasLength(6));
      expect(shifted, everyElement(greaterThan(0)));
      expect(shifted.toSet(), hasLength(3));
      expect(shifted.toSet().intersection({3, 8, 20, 1, 2}), isEmpty);
      expect(assigned.toSet(), {1, 2, 3});
      expect(_storedOrder(raw), _uuids([1, 3, 2]));
    });

    test('перестановка не меняет намерения, их показания времени, поисковую '
        'проекцию, связи, теги и дневные выборы', () async {
      await seedDurabilityGraph(database);
      expect(
        await durabilityRepository(database).execute(durabilityCreate()),
        isA<GraphResultSuccess<Object?, Object?>>(),
      );
      raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
        durabilityUuid(401),
        'Дом',
      ]);
      raw.execute(
        'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
        [durabilityUuid(401), durabilityUuid(2)],
      );
      for (final number in [1, 2, 3, 4, 5]) {
        storeFavoriteMark(
          raw,
          intentionId: durabilityUuid(number),
          position: number,
        );
      }
      final graphBefore = _graphWithoutFavorites(raw);
      trace.clear();

      await _moved(repository, _move(5, after: 1));

      expect(_graphWithoutFavorites(raw), graphBefore);
      expect(_storedOrder(raw), _uuids([1, 5, 2, 3, 4]));
      expect(
        trace.writes,
        everyElement(startsWith('UPDATE favorite_intentions')),
      );
    });
  });

  group('Результат и ревизия', () {
    test('фактическая перестановка подтверждается одним изменением порядка на '
        'одной новой ревизии', () async {
      for (final number in [1, 2, 3]) {
        _insertFavorite(
          raw,
          number: number,
          title: '$number',
          position: number,
        );
      }
      final revisionBefore = await _revision(repository);

      final confirmed = await _confirmed(repository, _move(3, first: true));

      final moved = confirmed.value as FavoriteOrderMoved;
      expect(
        confirmed.revision.compareTo(revisionBefore),
        GraphRevisionOrder.newer,
      );
      expect(
        moved.change.revision.compareTo(confirmed.revision),
        GraphRevisionOrder.same,
      );
      expect(confirmed.changes, [same(moved.change)]);
      expect(confirmed.changes.whereType<IntentionCatalogMutation>(), isEmpty);
      // Независимое чтение видит новый порядок на той же ревизии: ревизия
      // продвинута ровно одним изменением.
      final snapshot = await _favorites(repository);
      expect(snapshot.items.map((row) => row.id), [_id(3), _id(1), _id(2)]);
      expect(
        snapshot.revision.compareTo(confirmed.revision),
        GraphRevisionOrder.same,
      );
    });

    test(
      'следующая перестановка подтверждается на более новой ревизии',
      () async {
        for (final number in [1, 2, 3]) {
          _insertFavorite(
            raw,
            number: number,
            title: '$number',
            position: number,
          );
        }

        final first = await _confirmed(repository, _move(3, first: true));
        final second = await _confirmed(repository, _move(1, first: true));

        expect(
          second.revision.compareTo(first.revision),
          GraphRevisionOrder.newer,
        );
        expect(_storedOrder(raw), _uuids([1, 3, 2]));
      },
    );

    test('перемещение после ближайшего предшествующего активного намерения '
        'сохраняет места и ревизию без записей', () async {
      // Скрытое архивированное намерение стоит перед первым активным и
      // между активными; места идут с пропусками.
      _insertFavorite(raw, number: 4, title: 'Б', position: 2, archived: true);
      _insertFavorite(raw, number: 1, title: 'А', position: 5);
      _insertFavorite(raw, number: 2, title: 'Г', position: 7, archived: true);
      _insertFavorite(raw, number: 3, title: 'В', position: 12);
      final marksBefore = storedFavoriteMarks(raw);
      final revisionBefore = await _revision(repository);
      final changesBefore = _connectionChanges(raw);
      trace.clear();

      final confirmed = await _confirmed(repository, _move(3, after: 1));

      final unchanged = confirmed.value as FavoriteOrderUnchanged;
      expect(
        confirmed.revision.compareTo(revisionBefore),
        GraphRevisionOrder.same,
      );
      expect(
        unchanged.change.revision.compareTo(revisionBefore),
        GraphRevisionOrder.same,
      );
      expect(confirmed.changes, [same(unchanged.change)]);
      expect(trace.writes, isEmpty);
      expect(_connectionChanges(raw), changesBefore);
      expect(storedFavoriteMarks(raw), marksBefore);
      expect(
        (await _revision(repository)).compareTo(revisionBefore),
        GraphRevisionOrder.same,
      );
    });
  });

  group('Отказы', () {
    test('опора, совпадающая с перемещаемым намерением, — ошибка ввода без '
        'записи', () async {
      for (final number in [1, 2]) {
        _insertFavorite(
          raw,
          number: number,
          title: '$number',
          position: number,
        );
      }

      await _expectRejectedWithoutWrite(
        raw,
        repository,
        trace,
        _move(2, after: 2),
        isA<FavoriteOrderInputFailure>(),
      );
    });

    test('опора, утратившая отметку, — конфликт с прежним порядком', () async {
      for (final number in [1, 2, 3]) {
        _insertFavorite(
          raw,
          number: number,
          title: '$number',
          position: number,
        );
      }
      await _succeeded(repository, UnmarkIntentionFavorite(_id(2)));

      await _expectRejectedWithoutWrite(
        raw,
        repository,
        trace,
        _move(3, after: 2),
        isA<FavoriteOrderConflictFailure>(),
      );
      expect(_storedOrder(raw), _uuids([1, 3]));
    });

    test('физически удалённое перемещаемое намерение — конфликт без '
        'записи', () async {
      for (final number in [1, 2, 3]) {
        _insertFavorite(
          raw,
          number: number,
          title: '$number',
          position: number,
        );
      }
      await _succeeded(repository, DeleteIntention(_id(2)));

      await _expectRejectedWithoutWrite(
        raw,
        repository,
        trace,
        _move(2, first: true),
        isA<FavoriteOrderConflictFailure>(),
      );
      expect(_storedOrder(raw), _uuids([1, 3]));
    });

    group('Повреждение сохранённого порядка до записи', () {
      test('недопустимый идентификатор отметки', () async {
        _insertFavorite(raw, number: 1, title: '1', position: 1);
        raw.execute(
          'INSERT INTO intentions (id, title, is_action_ready, is_archived, '
          'created_at, updated_at) VALUES (?, ?, 0, 0, 1, 1)',
          [_uuid(2).toUpperCase(), '2'],
        );
        storeFavoriteMark(
          raw,
          intentionId: _uuid(2).toUpperCase(),
          position: 2,
        );

        await _expectRejectedWithoutWrite(
          raw,
          repository,
          trace,
          _move(1, first: true),
          isA<FavoriteOrderCorruptionFailure>(),
        );
      });
    });
  });
}

/// Записи одного соединения в порядке выполнения.
final class _WriteTrace extends LocalDatabaseConnectionObserver {
  final writes = <String>[];

  void clear() => writes.clear();

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (statement.operation != LocalDatabaseSqlOperation.select) {
      writes.addAll(statement.statements);
    }
  }
}

/// Журнал изменений мест, который ведёт временный триггер соединения.
/// Триггер наблюдает каждую изменённую строку, не меняя схему хранилища.
final class _PlaceLog {
  _PlaceLog._(this._database);

  factory _PlaceLog.install(sqlite.Database database) {
    database.execute(
      'CREATE TEMP TABLE favorite_place_log ('
      'sequence INTEGER PRIMARY KEY AUTOINCREMENT, '
      'before_place INTEGER, after_place INTEGER)',
    );
    database.execute(
      'CREATE TEMP TRIGGER favorite_place_log_after_update '
      'AFTER UPDATE OF position ON main.favorite_intentions '
      'BEGIN '
      'INSERT INTO favorite_place_log (before_place, after_place) '
      'VALUES (old.position, new.position); '
      'END',
    );
    return _PlaceLog._(database);
  }

  final sqlite.Database _database;

  List<({int before, int after})> get updates => [
    for (final row in _database.select(
      'SELECT before_place, after_place FROM favorite_place_log '
      'ORDER BY sequence',
    ))
      (before: row['before_place'] as int, after: row['after_place'] as int),
  ];
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

List<String> _uuids(List<int> numbers) => numbers.map(_uuid).toList();

IntentionId _id(int number) => durabilityIntention(number);

MoveFavoriteIntention _move(int number, {int? after, bool first = false}) {
  assert(first != (after != null), 'Нужно ровно одно размещение.');
  return MoveFavoriteIntention(
    intentionId: _id(number),
    placement: after == null
        ? const FirstFavoritePlacement()
        : AfterFavoritePlacement(_id(after)),
  );
}

String _placementName(FavoritePlacement placement) => switch (placement) {
  FirstFavoritePlacement() => 'первым',
  AfterFavoritePlacement(:final anchorId) =>
    'после ${anchorId.toCanonicalString()}',
};

/// Намерение фикстуры: время создания растёт с номером.
void _insertIntention(
  sqlite.Database database, {
  required int number,
  required String title,
  bool isArchived = false,
}) {
  final timestamp = DateTime.utc(
    2026,
    10,
    1,
    10,
    number,
  ).microsecondsSinceEpoch;
  database.execute(
    'INSERT INTO intentions (id, title, description, is_action_ready, '
    'is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
    [_uuid(number), title, null, 0, isArchived ? 1 : 0, timestamp, timestamp],
  );
}

/// Избранное намерение фикстуры на месте [position].
void _insertFavorite(
  sqlite.Database database, {
  required int number,
  required String title,
  required int position,
  bool archived = false,
}) {
  _insertIntention(
    database,
    number: number,
    title: title,
    isArchived: archived,
  );
  storeFavoriteMark(database, intentionId: _uuid(number), position: position);
}

/// Заменяет все отметки сохранёнными местами [marks].
void _replaceStoredMarks(sqlite.Database database, List<(String, int)> marks) {
  database.execute('DELETE FROM favorite_intentions');
  for (final (intentionId, position) in marks) {
    storeFavoriteMark(database, intentionId: intentionId, position: position);
  }
}

/// Идентификаторы всех избранных намерений в порядке мест.
List<String> _storedOrder(sqlite.Database database) => [
  for (final (intentionId, _) in storedFavoriteMarks(database)) intentionId,
];

int _connectionChanges(sqlite.Database database) =>
    database.select('SELECT total_changes() AS count').single['count'] as int;

/// Все строки всех таблиц хранилища, кроме отметок избранного, включая
/// служебные таблицы поисковой проекции.
Map<String, List<Map<String, Object?>>> _graphWithoutFavorites(
  sqlite.Database database,
) => {
  for (final table in database.select(
    "SELECT name FROM sqlite_master WHERE type = 'table' "
    "AND name <> 'favorite_intentions' ORDER BY name",
  ))
    table['name'] as String: [
      for (final row in database.select('SELECT * FROM "${table['name']}"'))
        {...row},
    ],
};

Future<FavoriteIntentionsSnapshot> _favorites(
  DriftPersonalGraphRepository repository,
) async {
  final result = await repository.getFavoriteIntentions();
  expect(result, isA<FavoriteIntentionsSuccess>());
  return (result as FavoriteIntentionsSuccess).value;
}

Future<GraphRevision> _revision(
  DriftPersonalGraphRepository repository,
) async => (await _favorites(repository)).revision;

FavoriteOrderCommandSuccess _successOf(FavoriteOrderCommandResult result) =>
    switch (result) {
      FavoriteOrderCommandSucceeded(:final value) => value.value,
      FavoriteOrderCommandFailed(:final failure) => fail(
        'Ожидался успех, получен ${failure.runtimeType}.',
      ),
    };

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

Future<FavoriteOrderMoved> _moved(
  DriftPersonalGraphRepository repository,
  MoveFavoriteIntention command,
) async {
  final success = (await _confirmed(repository, command)).value;
  expect(success, isA<FavoriteOrderMoved>());
  return success as FavoriteOrderMoved;
}

Future<void> _succeeded(
  DriftPersonalGraphRepository repository,
  IntentionCommand command,
) async {
  expect(
    await repository.execute(command),
    isA<ResultSuccess<ConfirmedGraphResult<IntentionCommandSuccess>>>(),
    reason: '${command.runtimeType}',
  );
}

/// Исполняет [command] и проверяет отказ [failure] без записи, изменения
/// отметок и продвижения ревизии.
Future<void> _expectRejectedWithoutWrite(
  sqlite.Database raw,
  DriftPersonalGraphRepository repository,
  _WriteTrace trace,
  MoveFavoriteIntention command,
  Matcher failure,
) async {
  final marksBefore = storedFavoriteMarks(raw);
  final changesBefore = _connectionChanges(raw);
  final revisionBefore = await _graphRevision(repository);
  trace.clear();

  final result = await repository.execute(command);

  expect(_failureOf(result), failure);
  expect(trace.writes, isEmpty);
  expect(_connectionChanges(raw), changesBefore);
  expect(storedFavoriteMarks(raw), marksBefore);
  expect(
    (await _graphRevision(repository)).compareTo(revisionBefore),
    GraphRevisionOrder.same,
  );
}

/// Ревизия графа, читаемая независимо от сохранённых данных намерений и
/// избранного, в том числе повреждённых.
Future<GraphRevision> _graphRevision(
  DriftPersonalGraphRepository repository,
) async {
  final result = await repository.getTagCatalog(const TagCatalogBrowseMode());
  expect(result, isA<TagCatalogSuccess>());
  return (result as TagCatalogSuccess).value.revision;
}
