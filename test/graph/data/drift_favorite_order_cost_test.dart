@Tags(['slow'])
library;

import 'package:doable/src/data/local/app_database.dart'
    show
        LocalDatabaseConnectionObserver,
        LocalDatabaseSqlOperation,
        LocalDatabaseSqlStatement;
import 'package:doable/src/favorite/application/favorite_intentions.dart';
import 'package:doable/src/favorite/application/favorite_order_command.dart';
import 'package:doable/src/favorite/domain/favorite_order.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/favorite_storage_fixture.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/local_database_harness.dart';

/// Обращения одного соединения с числом строк каждого чтения.
final class _ConnectionTrace extends LocalDatabaseConnectionObserver {
  final statements = <LocalDatabaseSqlStatement>[];
  final selectRows = <int>[];

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    statements.add(statement);
  }

  @override
  List<Map<String, Object?>> afterSelect(
    LocalDatabaseSqlStatement statement,
    List<Map<String, Object?>> rows,
  ) {
    selectRows.add(rows.length);
    return rows;
  }

  void clear() {
    statements.clear();
    selectRows.clear();
  }
}

/// Одна перестановка: исход и наблюдённые обращения.
final class _MeasuredMove {
  const _MeasuredMove({
    required this.outcome,
    required this.selects,
    required this.writes,
    required this.changedRows,
  });

  final FavoriteOrderCommandSuccess outcome;
  final List<LocalDatabaseSqlStatement> selects;
  final List<LocalDatabaseSqlStatement> writes;

  /// Строки, изменённые соединением, включая изменения триггеров.
  final int changedRows;

  List<String> get writeSql => [
    for (final statement in writes)
      statement.statements.single.replaceAll(RegExp(r'\s+'), ' ').trim(),
  ];
}

/// Каждое такое по счёту избранное намерение фикстуры архивировано.
const _archivedEvery = 4;

void main() {
  late LocalDatabaseHarness harness;
  late sqlite.Database raw;
  late _ConnectionTrace trace;
  late DriftPersonalGraphRepository repository;

  setUp(() async {
    harness = await LocalDatabaseHarness.fileBacked();
    trace = _ConnectionTrace();
    final database = await harness.openReadyDatabase(
      setup: (connection) => raw = connection,
      observer: trace,
    );
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 10, 3, 12),
      InMemoryDiagnosticsSink(),
    );
  });

  tearDown(() => harness.dispose());

  /// Исполняет [command] и проверяет общие для любого исхода свойства:
  /// весь порядок читается одним запросом без предела и без построчных
  /// обращений, а намерения не меняются.
  Future<_MeasuredMove> measure(
    MoveFavoriteIntention command, {
    required int count,
  }) async {
    final intentionsBefore = _storedIntentions(raw);
    final changesBefore = _connectionChanges(raw);
    trace.clear();
    final result = await repository.execute(command);
    final outcome = switch (result) {
      FavoriteOrderCommandSucceeded(:final value) => value.value,
      FavoriteOrderCommandFailed(:final failure) => fail(
        'Ожидался успех, получен ${failure.runtimeType}.',
      ),
    };

    final selects = [
      for (final statement in trace.statements)
        if (statement.operation == LocalDatabaseSqlOperation.select) statement,
    ];
    final writes = [
      for (final statement in trace.statements)
        if (statement.operation != LocalDatabaseSqlOperation.select) statement,
    ];
    // Весь порядок, включая архивированные избранные намерения, приходит
    // одним чтением без предела; построчных чтений нет.
    expect(selects, hasLength(1));
    final orderRead = selects.single.statements.single.toUpperCase();
    expect(orderRead, contains('FROM FAVORITE_INTENTIONS'));
    expect(orderRead, isNot(contains('LIMIT')));
    expect(orderRead, isNot(contains('OFFSET')));
    expect(selects.single.arguments, isEmpty);
    expect(trace.selectRows, [count]);
    // Число параметров инструкции не растёт с размером списка: места не
    // перечисляются построчно в тексте или параметрах запроса.
    for (final statement in trace.statements) {
      expect(statement.statements, hasLength(1));
      expect(statement.arguments.length, lessThanOrEqualTo(1));
    }
    // Строки намерений и их показания времени перестановка не меняет.
    expect(_storedIntentions(raw), intentionsBefore);

    return _MeasuredMove(
      outcome: outcome,
      selects: selects,
      writes: writes,
      changedRows: _connectionChanges(raw) - changesBefore,
    );
  }

  /// Проверяет фактическую перестановку: две инструкции изменения мест
  /// переписывают места всех избранных и ничего, кроме них.
  void expectPlaceRewrite(_MeasuredMove move, {required int count}) {
    expect(move.outcome, isA<FavoriteOrderMoved>());
    expect(move.writes.map((statement) => statement.operation), [
      LocalDatabaseSqlOperation.update,
      LocalDatabaseSqlOperation.update,
    ]);
    for (final sql in move.writeSql) {
      expect(sql.toUpperCase(), startsWith('UPDATE FAVORITE_INTENTIONS '));
    }
    // Сдвиг за прежний максимум и назначение итоговых мест затрагивают по
    // одной строке каждого избранного; триггеры ничего не дописывают.
    expect(move.changedRows, 2 * count);
  }

  const count = 1000;
  test('перемещения в начало и в конец $count избранных намерений '
      'переписывают точный полный порядок двумя инструкциями без '
      'построчной записи, а перемещение без видимого изменения не '
      'пишет', () async {
    seedLargeFavoriteFixture(raw, count: count, archivedEvery: _archivedEvery);
    var expected = largeFavoriteFixtureOrder(
      count: count,
      archivedEvery: _archivedEvery,
    );
    final initialMarks = storedFavoriteMarks(raw);
    expect(initialMarks.map((mark) => mark.$1), expected.map(_idOf));
    // Места фикстуры идут с пропусками, а архивированные избранные
    // намерения стоят между активными.
    expect(initialMarks.last.$2, greaterThan(count));
    final archivedCount = expected.where((place) => place.isArchived).length;
    expect(archivedCount, count ~/ _archivedEvery);
    final firstActive = expected.indexWhere((place) => !place.isArchived);
    final lastActive = expected.lastIndexWhere((place) => !place.isArchived);
    expect(
      expected
          .sublist(firstActive, lastActive)
          .where((place) => place.isArchived),
      isNotEmpty,
    );

    // Последнее активное избранное намерение становится первым во всём
    // порядке, перед скрытыми архивированными.
    final last = _activeIds(expected).last;
    final movedToStart = await measure(
      MoveFavoriteIntention(
        intentionId: _intentionId(last),
        placement: const FirstFavoritePlacement(),
      ),
      count: count,
    );
    expectPlaceRewrite(movedToStart, count: count);
    expected = _movedFirst(expected, last);
    expect(storedFavoriteMarks(raw), _placesOf(expected));

    // Первое активное избранное намерение встаёт сразу после последнего
    // активного, перед замыкающими архивированными.
    final activesBeforeEnd = _activeIds(expected);
    final movedToEnd = await measure(
      MoveFavoriteIntention(
        intentionId: _intentionId(activesBeforeEnd.first),
        placement: AfterFavoritePlacement(_intentionId(activesBeforeEnd.last)),
      ),
      count: count,
    );
    expectPlaceRewrite(movedToEnd, count: count);
    expected = _movedAfter(
      expected,
      activesBeforeEnd.first,
      anchor: activesBeforeEnd.last,
    );
    expect(storedFavoriteMarks(raw), _placesOf(expected));
    expect(movedToEnd.writeSql, movedToStart.writeSql);

    // Опора уже ближайшее предшествующее активное намерение.
    final actives = _activeIds(expected);
    final marksBefore = storedFavoriteMarks(raw);
    final unchanged = await measure(
      MoveFavoriteIntention(
        intentionId: _intentionId(actives[1]),
        placement: AfterFavoritePlacement(_intentionId(actives.first)),
      ),
      count: count,
    );
    expect(unchanged.outcome, isA<FavoriteOrderUnchanged>());
    expect(unchanged.writes, isEmpty);
    expect(unchanged.changedRows, 0);
    expect(storedFavoriteMarks(raw), marksBefore);

    // Список Главной содержит все активные избранные намерения в новом
    // порядке, без усечения.
    final snapshot = switch (await repository.getFavoriteIntentions()) {
      FavoriteIntentionsSuccess(:final value) => value,
      final FavoriteIntentionsResult other => fail(
        'Ожидался снимок, получен ${other.runtimeType}.',
      ),
    };
    expect(snapshot.items.map((row) => row.id.toCanonicalString()), actives);
    expect(snapshot.archivedCount, archivedCount);
  });
}

String _idOf(LargeFavoriteFixturePlace place) => place.id;

List<String> _activeIds(List<LargeFavoriteFixturePlace> order) => [
  for (final place in order)
    if (!place.isArchived) place.id,
];

/// Ожидаемые сохранённые места: `1..n` в порядке [order].
List<(String, int)> _placesOf(List<LargeFavoriteFixturePlace> order) => [
  for (final (index, place) in order.indexed) (place.id, index + 1),
];

List<LargeFavoriteFixturePlace> _movedFirst(
  List<LargeFavoriteFixturePlace> order,
  String id,
) => [
  order.singleWhere((place) => place.id == id),
  for (final place in order)
    if (place.id != id) place,
];

List<LargeFavoriteFixturePlace> _movedAfter(
  List<LargeFavoriteFixturePlace> order,
  String id, {
  required String anchor,
}) {
  final moved = order.singleWhere((place) => place.id == id);
  final rest = [
    for (final place in order)
      if (place.id != id) place,
  ];
  return rest
    ..insert(rest.indexWhere((place) => place.id == anchor) + 1, moved);
}

IntentionId _intentionId(String id) => switch (IntentionId.decode(id)) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => fail('Недопустимый идентификатор фикстуры.'),
};

/// Все строки намерений со всеми полями, включая показания времени.
List<Map<String, Object?>> _storedIntentions(sqlite.Database database) => [
  for (final row in database.select('SELECT * FROM intentions ORDER BY id'))
    {...row},
];

int _connectionChanges(sqlite.Database database) =>
    database.select('SELECT total_changes() AS count').single['count'] as int;
