import 'package:drift/drift.dart';

Future<void> verifyIntentionTitlesFtsIntegrity(GeneratedDatabase database) {
  return database.customStatement('''
    INSERT INTO intention_titles_fts(intention_titles_fts, rank)
    VALUES ('integrity-check', 1)
  ''');
}
