import 'package:doable/src/data/local/app_database.dart';

Future<void> verifyIntentionTitlesFtsIntegrity(AppDatabase database) {
  return database.customStatement('''
    INSERT INTO intention_titles_fts(intention_titles_fts, rank)
    VALUES ('integrity-check', 1)
  ''');
}
