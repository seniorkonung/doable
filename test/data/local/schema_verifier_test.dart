import 'package:doable/src/data/local/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('сохраняемая схема не ссылается на функции проверки связей', () async {
    final database = AppDatabase(openInMemoryLocalDatabase());
    addTearDown(database.close);

    final references = await database.customSelect('''
      SELECT name
      FROM sqlite_schema
      WHERE sql LIKE '%doable_relation_%'
    ''').get();

    expect(references, isEmpty);
  });
}
