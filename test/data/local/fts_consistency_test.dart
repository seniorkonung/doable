import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/data/local/fts_integrity.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
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

        expect(await _findByLiteralFtsPhrase(database, 'молоко'), [id]);

        await database.customStatement(
          'UPDATE intentions SET title_search_key = ? WHERE id = ?',
          ['купить хлеб', id],
        );

        expect(await _findByLiteralFtsPhrase(database, 'молоко'), isEmpty);
        expect(await _findByLiteralFtsPhrase(database, 'хлеб'), [id]);

        await database.customStatement('DELETE FROM intentions WHERE id = ?', [
          id,
        ]);

        expect(await _findByLiteralFtsPhrase(database, 'хлеб'), isEmpty);
      },
    );

    test('выполняет параметризованный буквальный MATCH и хранит короткие ключи через параметризованный путь', () async {
      const id = '018f0b5d-6b2e-7c80-8000-000000000102';
      await _insertIntention(
        database,
        id: id,
        title: 'Купить молоко',
        titleSearchKey: 'купить молоко',
      );

      expect(await _findByLiteralFtsPhrase(database, 'молоко'), [id]);
      expect(await _findByShortSearchKey(database, 'к'), [id]);
      expect(await _findByShortSearchKey(database, 'ко'), [id]);
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

Future<List<String>> _findByLiteralFtsPhrase(
  AppDatabase database,
  String searchKey,
) async {
  final rows = await database
      .customSelect(
        '''
      SELECT intentions.id
      FROM intention_titles_fts
      INNER JOIN intentions ON intentions.rowid = intention_titles_fts.rowid
      WHERE intention_titles_fts MATCH ?
      ORDER BY intentions.id ASC
    ''',
        variables: [Variable.withString('"$searchKey"')],
      )
      .get();

  return rows.map((row) => row.read<String>('id')).toList();
}

Future<List<String>> _findByShortSearchKey(
  AppDatabase database,
  String searchKey,
) async {
  final rows = await database
      .customSelect(
        '''
      SELECT id
      FROM intentions
      WHERE instr(title_search_key, ?) > 0
      ORDER BY id ASC
    ''',
        variables: [Variable.withString(searchKey)],
      )
      .get();

  return rows.map((row) => row.read<String>('id')).toList();
}
