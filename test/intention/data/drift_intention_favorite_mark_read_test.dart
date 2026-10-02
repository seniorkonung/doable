import 'package:doable/src/data/local/app_database.dart' hide Intention;
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/favorite_storage_fixture.dart';
import '../../support/in_memory_diagnostics_sink.dart';

void main() {
  late AppDatabase database;
  late sqlite.Database raw;
  late InMemoryDiagnosticsSink diagnostics;
  late _StatementTrace trace;
  late DriftPersonalGraphRepository repository;

  setUp(() async {
    diagnostics = InMemoryDiagnosticsSink();
    trace = _StatementTrace();
    database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(setup: (connection) => raw = connection),
        trace,
      ),
    );
    await database.open();
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 10, 2, 12),
      diagnostics,
    );
  });

  tearDown(() => database.close());

  group('Подробные данные намерения', () {
    test('несут отметку своего идентификатора, а не названия', () async {
      _insertIntention(raw, number: 1, title: 'Гулять');
      _insertIntention(raw, number: 2, title: 'Гулять');
      storeFavoriteMark(raw, intentionId: _uuid(2), position: 5);

      expect(
        (await _details(repository, 1)).favoriteMark,
        FavoriteMark.notFavorite,
      );
      expect(
        (await _details(repository, 2)).favoriteMark,
        FavoriteMark.favorite,
      );
    });

    test('несут отметку архивированного готового намерения', () async {
      _insertIntention(
        raw,
        number: 1,
        title: 'Архивное действие',
        isArchived: true,
        isActionReady: true,
      );
      storeFavoriteMark(raw, intentionId: _uuid(1), position: 1);

      final details = await _details(repository, 1);

      expect(details.favoriteMark, FavoriteMark.favorite);
      expect(details.intention.archiveState, IntentionArchiveState.archived);
      expect(details.intention.readiness, IntentionReadiness.ready);
    });

    test('читают только отметку запрошенного намерения без записи', () async {
      _insertIntention(raw, number: 1, title: 'Первое');
      _insertIntention(raw, number: 2, title: 'Второе');
      storeFavoriteMark(raw, intentionId: _uuid(1), position: 1);
      storeFavoriteMark(raw, intentionId: _uuid(2), position: 2);
      final changesBefore = _connectionChanges(raw);
      trace.clear();

      await _details(repository, 1);

      final markRead = trace.favoriteMarkReads.single;
      expect(markRead.arguments, [_uuid(1)]);
      expect(markRead.rowCount, 1);
      expect(trace.writes, isEmpty);
      expect(_connectionChanges(raw), changesBefore);
    });
  });

  group('Порция каталога', () {
    test('различает одноимённые избранное и неизбранное намерения', () async {
      _insertIntention(raw, number: 1, title: 'Гулять');
      _insertIntention(raw, number: 2, title: 'Гулять');
      storeFavoriteMark(raw, intentionId: _uuid(2), position: 1);

      final page = await _page(repository, _query());

      expect(_marks(page.items), {
        _uuid(1): FavoriteMark.notFavorite,
        _uuid(2): FavoriteMark.favorite,
      });
    });

    test(
      'показывает отметку архивированного намерения в архивном охвате',
      () async {
        _insertIntention(raw, number: 1, title: 'Активное');
        _insertIntention(raw, number: 2, title: 'Архивное', isArchived: true);
        _insertIntention(raw, number: 3, title: 'Архивное', isArchived: true);
        storeFavoriteMark(raw, intentionId: _uuid(1), position: 1);
        storeFavoriteMark(raw, intentionId: _uuid(3), position: 2);

        final page = await _page(
          repository,
          _query(scope: IntentionScope.archived),
        );

        expect(_marks(page.items), {
          _uuid(2): FavoriteMark.notFavorite,
          _uuid(3): FavoriteMark.favorite,
        });
        expect(
          page.items.map((item) => item.archiveState),
          everyElement(IntentionArchiveState.archived),
        );
      },
    );

    test(
      'не меняет состав, порядок, количество и продолжение выдачи',
      () async {
        for (var number = 1; number <= 7; number++) {
          _insertIntention(
            raw,
            number: number,
            title: number.isEven ? 'Чётное намерение' : 'Нечётное намерение',
            isArchived: number % 3 == 0,
            isActionReady: number > 2,
          );
        }
        final queries = [
          for (final scope in IntentionScope.values)
            for (final order in [
              IntentionCatalogOrder.createdAtAscending,
              IntentionCatalogOrder.createdAtDescending,
            ])
              for (final titleFilter in [null, 'нечётное'])
                (scope: scope, order: order, titleFilter: titleFilter),
        ];
        final before = [
          for (final query in queries)
            await _traverse(
              repository,
              scope: query.scope,
              order: query.order,
              titleFilter: query.titleFilter,
            ),
        ];

        // Места расставлены против порядка создания: выдача от них не зависит.
        final favorites = {7: 1, 6: 2, 3: 3, 1: 9};
        for (final MapEntry(key: number, value: position)
            in favorites.entries) {
          storeFavoriteMark(
            raw,
            intentionId: _uuid(number),
            position: position,
          );
        }
        final after = [
          for (final query in queries)
            await _traverse(
              repository,
              scope: query.scope,
              order: query.order,
              titleFilter: query.titleFilter,
            ),
        ];

        for (var index = 0; index < queries.length; index++) {
          final reason = '${queries[index]}';
          expect(after[index].pages, before[index].pages, reason: reason);
          expect(
            after[index].totalCount,
            before[index].totalCount,
            reason: reason,
          );
          expect(
            before[index].marks.values,
            everyElement(FavoriteMark.notFavorite),
            reason: reason,
          );
          expect(after[index].marks, {
            for (final id in before[index].marks.keys)
              id: favorites.keys.map(_uuid).contains(id)
                  ? FavoriteMark.favorite
                  : FavoriteMark.notFavorite,
          }, reason: reason);
        }
      },
    );

    test('получает отметки одним чтением по идентификаторам порции', () async {
      for (var number = 1; number <= 6; number++) {
        _insertIntention(raw, number: number, title: 'Намерение $number');
        storeFavoriteMark(raw, intentionId: _uuid(number), position: number);
      }
      final changesBefore = _connectionChanges(raw);

      for (final pageSize in [1, 3, 5]) {
        trace.clear();
        final first = await _page(repository, _query(pageSize: pageSize));
        _expectSingleMarkRead(trace, first.items);

        trace.clear();
        final continuation = await _page(
          repository,
          _query(pageSize: pageSize, cursor: first.nextCursor),
        );
        _expectSingleMarkRead(trace, continuation.items);
      }
      expect(_connectionChanges(raw), changesBefore);
    });
  });

  group('Порция согласования каталога', () {
    test('несёт отметки недостающих совпадений одним чтением', () async {
      for (var number = 1; number <= 4; number++) {
        _insertIntention(raw, number: number, title: 'Гулять');
      }
      storeFavoriteMark(raw, intentionId: _uuid(2), position: 4);
      storeFavoriteMark(raw, intentionId: _uuid(4), position: 2);
      final changesBefore = _connectionChanges(raw);
      trace.clear();

      final result = await repository.getCatalogReconciliationPortion(
        _reconciliationQuery(),
      );

      expect(
        result,
        isA<ResultSuccess<IntentionCatalogReconciliationOutcome>>(),
      );
      final portion =
          (result as ResultSuccess<IntentionCatalogReconciliationOutcome>).value
              as IntentionCatalogReconciliationFirstPortion;
      expect(portion.totalCount, 4);
      expect(_marks(portion.items), {
        _uuid(1): FavoriteMark.notFavorite,
        _uuid(2): FavoriteMark.favorite,
        _uuid(3): FavoriteMark.notFavorite,
        _uuid(4): FavoriteMark.favorite,
      });
      _expectSingleMarkRead(trace, portion.items);
      expect(_connectionChanges(raw), changesBefore);
    });
  });

  group('Каталожные снимки команд', () {
    test('команды намерения несут отметку до и после изменения', () async {
      _insertIntention(raw, number: 1, title: 'Гулять');
      _insertIntention(raw, number: 2, title: 'Гулять');
      storeFavoriteMark(raw, intentionId: _uuid(1), position: 3);

      for (final (number, mark) in [
        (1, FavoriteMark.favorite),
        (2, FavoriteMark.notFavorite),
      ]) {
        final id = _id(number);
        for (final command in <IntentionCommand>[
          UpdateIntention(id: id, title: 'Гулять дольше', description: null),
          UpdateIntention(id: id, title: 'Гулять дольше', description: null),
          EnableIntentionReadiness(id),
          DisableIntentionReadiness(id),
          ArchiveIntention(id),
          RestoreIntention(id),
          DeleteIntention(id),
        ]) {
          final mutation = (await _execute(
            repository,
            command,
          )).catalogMutation;
          final reason = '${command.runtimeType} намерения $number';
          for (final snapshot in [mutation.before, mutation.after]) {
            if (snapshot == null) continue;
            expect(snapshot.summary.id, id, reason: reason);
            expect(snapshot.summary.favoriteMark, mark, reason: reason);
          }
          expect(mutation.before, isNotNull, reason: reason);
        }
      }
    });

    test('создание возвращает снимок без отметки', () async {
      _insertIntention(raw, number: 1, title: 'Гулять');
      storeFavoriteMark(raw, intentionId: _uuid(1), position: 1);

      final created = await _execute(
        repository,
        const CreateIntention(title: 'Гулять', description: null),
      );

      expect(
        created.catalogMutation.after!.summary.favoriteMark,
        FavoriteMark.notFavorite,
      );
      expect(raw.select('SELECT intention_id FROM favorite_intentions'), [
        {'intention_id': _uuid(1)},
      ]);
    });

    test(
      'назначение и снятие тега несут отметку до и после изменения',
      () async {
        _insertIntention(raw, number: 1, title: 'Гулять');
        _insertIntention(raw, number: 2, title: 'Гулять');
        storeFavoriteMark(raw, intentionId: _uuid(2), position: 1);
        final tagId = switch (await repository.execute(
          CreateTag(TagName.fromInput('Дом')),
        )) {
          TagCommandSucceeded(
            value: ConfirmedGraphResult(:final TagCreated value),
          ) =>
            value.change.after.id,
          final other => fail('Тег не создан: $other'),
        };

        for (final (number, mark) in [
          (1, FavoriteMark.notFavorite),
          (2, FavoriteMark.favorite),
        ]) {
          for (final command in <TagCommand>[
            AssignTag(tagId: tagId, intentionId: _id(number)),
            RemoveTagAssignment(tagId: tagId, intentionId: _id(number)),
          ]) {
            final result = await repository.execute(command);
            final reason = '${command.runtimeType} намерения $number';
            expect(result, isA<TagCommandSucceeded>(), reason: reason);
            final changed =
                (result as TagCommandSucceeded).value.value
                    as TagAssignmentChanged;
            expect(
              changed.catalogMutation.before.summary.favoriteMark,
              mark,
              reason: reason,
            );
            expect(
              changed.catalogMutation.after.summary.favoriteMark,
              mark,
              reason: reason,
            );
          }
        }
      },
    );
  });

  group('Недопустимое место отметки запрошенного намерения', () {
    for (final position in <Object>[0, -3, 1.5, 'CANARY-место']) {
      test('$position даёт повреждение без частичного результата', () async {
        _insertIntention(raw, number: 1, title: 'CANARY-здоровое');
        _insertIntention(raw, number: 2, title: 'CANARY-повреждённое');
        storeFavoriteMark(raw, intentionId: _uuid(1), position: 1);
        storeFavoriteMarkWithInvalidPosition(
          raw,
          intentionId: _uuid(2),
          position: position,
        );
        final tagId = switch (await repository.execute(
          CreateTag(TagName.fromInput('CANARY-тег')),
        )) {
          TagCommandSucceeded(
            value: ConfirmedGraphResult(:final TagCreated value),
          ) =>
            value.change.after.id,
          final other => fail('Тег не создан: $other'),
        };
        final storedBefore = _storedGraph(raw);

        expect(
          await repository.watchIntention(_id(2)).first,
          isA<ResultFailure<GraphSnapshot<IntentionDetails?>>>().having(
            (result) => result.failure,
            'причина',
            isA<IntentionCorruptionFailure>(),
          ),
        );
        expect(
          diagnostics.events.last,
          isA<IntentionDetailReadDiagnosticsEvent>().having(
            (event) => event.status,
            'исход',
            _failedWith(DiagnosticsFailureCode.corruption),
          ),
        );

        expect(
          await repository.getCatalogPage(_query()),
          isA<ResultFailure<IntentionCatalogPage>>().having(
            (result) => result.failure,
            'причина',
            isA<IntentionCorruptionFailure>(),
          ),
        );
        expect(
          diagnostics.events.last,
          isA<CatalogPageReadDiagnosticsEvent>().having(
            (event) => event.status,
            'исход',
            _failedWith(DiagnosticsFailureCode.corruption),
          ),
        );

        expect(
          await repository.getCatalogReconciliationPortion(
            _reconciliationQuery(),
          ),
          isA<ResultFailure<IntentionCatalogReconciliationOutcome>>().having(
            (result) => result.failure,
            'причина',
            isA<IntentionCorruptionFailure>(),
          ),
        );
        expect(
          diagnostics.events.last,
          isA<CatalogReconciliationReadDiagnosticsEvent>(),
        );

        expect(
          await repository.execute(
            UpdateIntention(
              id: _id(2),
              title: 'CANARY-новое название',
              description: null,
            ),
          ),
          isA<ResultFailure<ConfirmedGraphResult<IntentionCommandSuccess>>>()
              .having(
                (result) => result.failure,
                'причина',
                isA<IntentionCorruptionFailure>(),
              ),
        );
        expect(
          diagnostics.events.last,
          isA<IntentionCommandDiagnosticsEvent>().having(
            (event) => event.status,
            'исход',
            _failedWith(DiagnosticsFailureCode.corruption),
          ),
        );

        expect(
          await repository.execute(
            AssignTag(tagId: tagId, intentionId: _id(2)),
          ),
          isA<TagCommandFailed>().having(
            (result) => result.failure,
            'причина',
            isA<TagCorruptionFailure>(),
          ),
        );

        expect(_storedGraph(raw), storedBefore);
        expect(diagnostics.events.toString(), isNot(contains('CANARY')));
      });
    }
  });
}

/// Чтения отметок и записи одного соединения в порядке выполнения.
final class _StatementTrace extends LocalDatabaseConnectionObserver {
  final favoriteMarkReads = <({List<Object?> arguments, int rowCount})>[];
  final writes = <String>[];

  void clear() {
    favoriteMarkReads.clear();
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
    if (statement.statements.single.contains('FROM favorite_intentions')) {
      favoriteMarkReads.add((
        arguments: statement.arguments,
        rowCount: rows.length,
      ));
    }
    return rows;
  }
}

/// Порция читает отметки одним обращением: только по своим идентификаторам,
/// без строки-признака продолжения и без записи на соединение.
void _expectSingleMarkRead(
  _StatementTrace trace,
  List<IntentionSummary> items,
) {
  final markRead = trace.favoriteMarkReads.single;
  expect(
    markRead.arguments,
    unorderedEquals(items.map((item) => item.id.toCanonicalString())),
  );
  expect(markRead.rowCount, lessThanOrEqualTo(items.length));
  expect(
    markRead.rowCount,
    items.where((item) => item.favoriteMark == FavoriteMark.favorite).length,
  );
  expect(trace.writes, isEmpty);
}

Matcher _failedWith(DiagnosticsFailureCode code) =>
    isA<DiagnosticsFailed>().having((status) => status.code, 'категория', code);

String _uuid(int number) =>
    '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}';

IntentionId _id(int number) => switch (IntentionId.decode(_uuid(number))) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw ArgumentError.value(number, 'number'),
};

/// Намерение фикстуры: время создания растёт с номером.
void _insertIntention(
  sqlite.Database database, {
  required int number,
  required String title,
  bool isArchived = false,
  bool isActionReady = false,
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
    [
      _uuid(number),
      title,
      null,
      isActionReady ? 1 : 0,
      isArchived ? 1 : 0,
      timestamp,
      timestamp,
    ],
  );
}

int _connectionChanges(sqlite.Database database) =>
    database.select('SELECT total_changes() AS count').single['count'] as int;

/// Строки намерений, отметок и назначений тегов для сравнения до и после.
List<List<Map<String, Object?>>> _storedGraph(sqlite.Database database) => [
  for (final table in ['intentions', 'favorite_intentions', 'tag_assignments'])
    [
      for (final row in database.select('SELECT * FROM $table ORDER BY 1, 2'))
        {...row},
    ],
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

IntentionCatalogQuery _query({
  IntentionScope scope = IntentionScope.all,
  IntentionCatalogOrder order = IntentionCatalogOrder.createdAtAscending,
  String? titleFilter,
  int pageSize = 10,
  IntentionCatalogCursor? cursor,
}) => IntentionCatalogQuery(
  scope: scope,
  titleFilter: titleFilter,
  order: order,
  pageSize: pageSize,
  cursor: cursor,
);

/// Согласование ранее пустой завершённой выдачи: недостающие совпадения —
/// все намерения фикстуры.
IntentionCatalogReconciliationQuery _reconciliationQuery() =>
    IntentionCatalogReconciliationQuery(
      catalogQuery: _query(),
      boundary: const IntentionCatalogCompletedBoundary(),
      window: IntentionCatalogFinalReconciliationWindow(const []),
    );

Future<IntentionCatalogPage> _page(
  DriftPersonalGraphRepository repository,
  IntentionCatalogQuery query,
) async {
  final result = await repository.getCatalogPage(query);
  expect(result, isA<ResultSuccess<IntentionCatalogPage>>());
  return (result as ResultSuccess<IntentionCatalogPage>).value;
}

Map<String, FavoriteMark> _marks(List<IntentionSummary> items) => {
  for (final item in items) item.id.toCanonicalString(): item.favoriteMark,
};

/// Полный обход выдачи порциями по две строки.
Future<
  ({List<List<String>> pages, int totalCount, Map<String, FavoriteMark> marks})
>
_traverse(
  DriftPersonalGraphRepository repository, {
  required IntentionScope scope,
  required IntentionCatalogOrder order,
  required String? titleFilter,
}) async {
  final pages = <List<String>>[];
  final marks = <String, FavoriteMark>{};
  late final int totalCount;
  IntentionCatalogCursor? cursor;
  do {
    final page = await _page(
      repository,
      _query(
        scope: scope,
        order: order,
        titleFilter: titleFilter,
        pageSize: 2,
        cursor: cursor,
      ),
    );
    if (page is IntentionCatalogFirstPage) totalCount = page.totalCount;
    pages.add([for (final item in page.items) item.id.toCanonicalString()]);
    marks.addAll(_marks(page.items));
    cursor = page.nextCursor;
  } while (cursor != null);
  return (pages: pages, totalCount: totalCount, marks: marks);
}

Future<IntentionCommandSuccess> _execute(
  DriftPersonalGraphRepository repository,
  IntentionCommand command,
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
      .value;
}
