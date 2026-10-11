import 'package:doable/src/data/local/app_database.dart' hide Intention;
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
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
  late DriftPersonalGraphRepository repository;

  setUp(() async {
    diagnostics = InMemoryDiagnosticsSink();
    database = AppDatabase(
      openInMemoryLocalDatabase(setup: (connection) => raw = connection),
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

  group('Порция каталога', () {
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
  });

  group('Порция согласования каталога', () {
    test('несёт отметки недостающих совпадений', () async {
      for (var number = 1; number <= 4; number++) {
        _insertIntention(raw, number: number, title: 'Гулять');
      }
      storeFavoriteMark(raw, intentionId: _uuid(2), position: 4);
      storeFavoriteMark(raw, intentionId: _uuid(4), position: 2);

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
}

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
