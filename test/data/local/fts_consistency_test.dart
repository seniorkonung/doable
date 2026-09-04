import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/data/local/fts_integrity.dart';
import 'package:doable/src/data/local/fts_query.dart';
import 'package:doable/src/intention/application/intention_repository.dart';
import 'package:doable/src/intention/application/title_search_key.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late _SqlTrace sqlTrace;

  setUp(() async {
    sqlTrace = _SqlTrace();
    database = AppDatabase(NativeDatabase.memory().interceptWith(sqlTrace));
    await database.open();
    sqlTrace.clear();
  });

  tearDown(() => database.close());

  group('полнотекстовый индекс названий намерений', () {
    test(
      'согласованно отражает вставку, изменение и удаление основной строки',
      () async {
        const id = '018f0b5d-6b2e-7c80-8000-000000000101';

        await _insertIntention(
          database,
          id: id,
          title: 'Купить молоко',
          titleSearchKey: 'купить молоко',
        );

        expect(await _findByTitleFilter(database, 'молоко'), [id]);

        await database.customStatement(
          'UPDATE intentions SET title = ?, title_search_key = ? WHERE id = ?',
          ['Купить хлеб', 'купить хлеб', id],
        );

        expect(await _findByTitleFilter(database, 'молоко'), isEmpty);
        expect(await _findByTitleFilter(database, 'хлеб'), [id]);

        await database.customStatement('DELETE FROM intentions WHERE id = ?', [
          id,
        ]);

        expect(await _findByTitleFilter(database, 'хлеб'), isEmpty);
      },
    );

    test(
      'выбирает параметризованный путь по числу Unicode-кодовых точек',
      () async {
        const id = '018f0b5d-6b2e-7c80-8000-000000000102';
        await _insertIntention(
          database,
          id: id,
          title: '😀😀😀 купить молоко',
          titleSearchKey: '😀😀😀 купить молоко',
        );

        expect(await _findByTitleFilter(database, '😀'), [id]);
        expect(_lastSelectStatement, contains('instr('));
        expect(_lastSelectArguments, ['😀']);

        sqlTrace.clear();
        expect(await _findByTitleFilter(database, '😀😀'), [id]);
        expect(_lastSelectStatement, contains('instr('));
        expect(_lastSelectArguments, ['😀😀']);

        sqlTrace.clear();
        expect(await _findByTitleFilter(database, '😀😀😀'), [id]);
        expect(_lastSelectStatement, contains('intention_titles_fts MATCH ?'));
        expect(_lastSelectArguments, ['"😀😀😀"']);

        final queryPlan = await database
            .customSelect(
              'EXPLAIN QUERY PLAN $_lastSelectStatement',
              variables: _lastSelectArguments.map(Variable.withString).toList(),
            )
            .get();
        expect(
          queryPlan.map((row) => row.read<String>('detail')).join('\n'),
          contains('intention_titles_fts'),
        );
      },
    );

    test(
      'готовит короткий фильтр только через единый поисковый ключ',
      () async {
        const id = '018f0b5d-6b2e-7c80-8000-000000000105';
        await _insertIntention(
          database,
          id: id,
          title: 'ꭰ',
          titleSearchKey: titleSearchKey('ꭰ'),
        );

        expect(await _findByTitleFilter(database, 'ꭰ'), [id]);
        expect(_lastSelectStatement, contains('instr("title_search_key", ?)'));
        expect(_lastSelectStatement, isNot(contains(' OR instr(')));
        expect(_lastSelectArguments, ['Ꭰ']);
      },
    );

    test('сохраняет буквальную семантику для синтаксических FTS-символов и Unicode', () async {
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
          searchKey: 'дело AND срочно',
          literalId: '018f0b5d-6b2e-7c80-8000-000000000205',
          interpretedId: '018f0b5d-6b2e-7c80-8000-000000000206',
          interpretedSearchKey: 'срочно дело',
        ),
        (
          searchKey: 'дело NOT срочно',
          literalId: '018f0b5d-6b2e-7c80-8000-000000000207',
          interpretedId: '018f0b5d-6b2e-7c80-8000-000000000208',
          interpretedSearchKey: 'дело важно',
        ),
        (
          searchKey: 'NEAR(дело срочно)',
          literalId: '018f0b5d-6b2e-7c80-8000-000000000209',
          interpretedId: '018f0b5d-6b2e-7c80-8000-000000000210',
          interpretedSearchKey: 'дело очень срочно',
        ),
        (
          searchKey: '(дело OR срочно)',
          literalId: '018f0b5d-6b2e-7c80-8000-000000000211',
          interpretedId: '018f0b5d-6b2e-7c80-8000-000000000212',
          interpretedSearchKey: 'срочно',
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
          searchKey: 'сделать  дело',
          literalId: '018f0b5d-6b2e-7c80-8000-000000000217',
          interpretedId: '018f0b5d-6b2e-7c80-8000-000000000218',
          interpretedSearchKey: 'сделать дело',
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
          titleSearchKey: fixture.searchKey,
        );
        await _insertIntention(
          database,
          id: fixture.interpretedId,
          title: fixture.interpretedSearchKey,
          titleSearchKey: fixture.interpretedSearchKey,
        );

        expect(await _findByTitleFilter(database, fixture.searchKey), [
          fixture.literalId,
        ], reason: fixture.searchKey);
      }
    });

    test(
      'index-aware integrity-check проходит для согласованных данных',
      () async {
        await _insertIntention(
          database,
          id: '018f0b5d-6b2e-7c80-8000-000000000103',
          title: 'Заняться спортом',
          titleSearchKey: 'заняться спортом',
        );

        await expectLater(
          verifyIntentionTitlesFtsIntegrity(database),
          completes,
        );
      },
    );

    test('index-aware integrity-check обнаруживает рассогласованный индекс, который не видно content-чтению', () async {
      const id = '018f0b5d-6b2e-7c80-8000-000000000104';
      const searchKey = 'прочитать книгу';
      await _insertIntention(
        database,
        id: id,
        title: 'Прочитать книгу',
        titleSearchKey: searchKey,
      );
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
  required String titleSearchKey,
}) => database.customStatement(
  '''
      INSERT INTO intentions (
        id, title, title_search_key, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?)
    ''',
  [id, title, titleSearchKey, 1000000, 1000000],
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

String get _lastSelectStatement => _currentSqlTrace.lastSelect.statement;

List<String> get _lastSelectArguments =>
    _currentSqlTrace.lastSelect.arguments.cast<String>();

late _SqlTrace _currentSqlTrace;

final class _SqlTrace extends QueryInterceptor {
  final selects = <_SelectStatement>[];

  _SelectStatement get lastSelect => selects.last;

  void clear() {
    selects.clear();
    _currentSqlTrace = this;
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    selects.add(_SelectStatement(statement, List.unmodifiable(args)));
    return super.runSelect(executor, statement, args);
  }
}

final class _SelectStatement {
  const _SelectStatement(this.statement, this.arguments);

  final String statement;
  final List<Object?> arguments;
}
