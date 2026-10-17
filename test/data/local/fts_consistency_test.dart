import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/data/local/fts_integrity.dart';
import 'package:doable/src/data/local/fts_query.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/graph_seed.dart';

void main() {
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase(openInMemoryLocalDatabase());
    await database.open();
  });

  tearDown(() => database.close());

  group('полнотекстовый индекс названий намерений', () {
    test(
      'согласованно отражает вставку, изменение и удаление основной строки',
      () async {
        const id = '018f0b5d-6b2e-7c80-8000-000000000101';

        await _insertIntention(database, id: id, title: 'Купить молоко');

        expect(await _findByTitleFilter(database, 'молоко'), [id]);

        await seedGraph(
          database,
          () => database.customStatement(
            'UPDATE intentions SET title = ? WHERE id = ?',
            ['Купить хлеб', id],
          ),
        );

        expect(await _findByTitleFilter(database, 'молоко'), isEmpty);
        expect(await _findByTitleFilter(database, 'хлеб'), [id]);

        await seedGraph(
          database,
          () => database.customStatement(
            'UPDATE intentions SET description = ? WHERE id = ?',
            ['Изменено неиндексируемое поле', id],
          ),
        );

        expect(await _findByTitleFilter(database, 'хлеб'), [id]);
        await expectLater(
          verifyIntentionTitlesFtsIntegrity(database),
          completes,
        );

        await seedGraph(
          database,
          () => database.customStatement(
            'DELETE FROM intentions WHERE id = ?',
            [id],
          ),
        );

        expect(await _findByTitleFilter(database, 'хлеб'), isEmpty);
      },
    );

    test(
      'находит название по фильтрам из одной, двух и трёх кодовых точек',
      () async {
        const id = '018f0b5d-6b2e-7c80-8000-000000000102';
        await _insertIntention(database, id: id, title: '😀😀😀 купить молоко');

        expect(await _findByTitleFilter(database, '😀'), [id]);
        expect(await _findByTitleFilter(database, '😀😀'), [id]);
        expect(await _findByTitleFilter(database, '😀😀😀'), [id]);

        expect(await _findByTitleFilter(database, '🙂'), isEmpty);
        expect(await _findByTitleFilter(database, '🙂🙂'), isEmpty);
        expect(await _findByTitleFilter(database, '😀😀😀😀'), isEmpty);
      },
    );

    test('сопоставляет короткий фильтр без учёта регистра', () async {
      const id = '018f0b5d-6b2e-7c80-8000-000000000105';
      await _insertIntention(database, id: id, title: 'ꭰ');

      expect(await _findByTitleFilter(database, 'ꭰ'), [id]);
      expect(await _findByTitleFilter(database, 'Ꭰ'), [id]);
    });

    test('сохраняет буквальную семантику для синтаксических FTS-символов и Unicode', () async {
      // Запрос всегда строится как одна буквальная фраза: достаточно кавычки,
      // ключевого слова, префиксного знака, дефиса и Unicode-символов.
      const fixtures = [
        (
          searchKey: 'скажи "да"',
          literalId: '018f0b5d-6b2e-7c80-8000-000000000201',
          interpretedId: '018f0b5d-6b2e-7c80-8000-000000000202',
          interpretedSearchKey: 'скажи да',
        ),
        (
          searchKey: 'чай OR кофе',
          literalId: '018f0b5d-6b2e-7c80-8000-000000000203',
          interpretedId: '018f0b5d-6b2e-7c80-8000-000000000204',
          interpretedSearchKey: 'кофе',
        ),
        (
          searchKey: 'купить*',
          literalId: '018f0b5d-6b2e-7c80-8000-000000000213',
          interpretedId: '018f0b5d-6b2e-7c80-8000-000000000214',
          interpretedSearchKey: 'купить молоко',
        ),
        (
          searchKey: 'self-care',
          literalId: '018f0b5d-6b2e-7c80-8000-000000000215',
          interpretedId: '018f0b5d-6b2e-7c80-8000-000000000216',
          interpretedSearchKey: 'self care',
        ),
        (
          searchKey: 'ёжик café',
          literalId: '018f0b5d-6b2e-7c80-8000-000000000219',
          interpretedId: '018f0b5d-6b2e-7c80-8000-000000000220',
          interpretedSearchKey: 'café ёжик',
        ),
      ];

      for (final fixture in fixtures) {
        await _insertIntention(
          database,
          id: fixture.literalId,
          title: fixture.searchKey,
        );
        await _insertIntention(
          database,
          id: fixture.interpretedId,
          title: fixture.interpretedSearchKey,
        );

        expect(await _findByTitleFilter(database, fixture.searchKey), [
          fixture.literalId,
        ], reason: fixture.searchKey);
      }
    });

    test('index-aware integrity-check обнаруживает рассогласованный индекс, который не видно content-чтению', () async {
      const id = '018f0b5d-6b2e-7c80-8000-000000000104';
      const searchKey = 'прочитать книгу';
      await _insertIntention(database, id: id, title: 'Прочитать книгу');
      await database.customStatement(
        '''
          INSERT INTO intention_titles_fts(
            intention_titles_fts, rowid, title_search_key
          ) VALUES ('delete', 1, ?)
        ''',
        [searchKey],
      );

      final contentRows = await database.customSelect('''
          SELECT rowid, title_search_key
          FROM intention_titles_fts
          WHERE rowid = 1
        ''').get();

      expect(contentRows, hasLength(1));
      expect(contentRows.single.read<String>('title_search_key'), searchKey);
      await expectLater(
        verifyIntentionTitlesFtsIntegrity(database),
        throwsA(isA<Exception>()),
      );
    });
  });
}

Future<void> _insertIntention(
  AppDatabase database, {
  required String id,
  required String title,
}) => seedGraph(
  database,
  () => database.customStatement(
    '''
      INSERT INTO intentions (
        id, title, created_at, updated_at
      ) VALUES (?, ?, ?, ?)
    ''',
    [id, title, 1000000, 1000000],
  ),
);

Future<List<String>> _findByTitleFilter(
  AppDatabase database,
  String userFilter,
) async {
  final titleFilter = IntentionCatalogQuery(
    scope: IntentionScope.all,
    titleFilter: userFilter,
    order: IntentionCatalogOrder.createdAtDescending,
    pageSize: 1,
  ).titleFilter!;
  final search = LocalIntentionTitleSearch(titleFilter);
  final query = database.select(database.intentions)
    ..where((_) => search.conditionFor(database.intentions))
    ..orderBy([(intentions) => OrderingTerm.asc(intentions.id)]);

  final rows = await query.get();
  return rows.map((row) => row.id).toList();
}
