import 'package:doable/src/data/local/app_database.dart';
import 'package:drift/drift.dart';

String intentionCatalogFixtureId(int index) =>
    '018f0b5d-6b2e-7c80-8000-${index.toRadixString(16).padLeft(12, '0')}';

Future<void> populateIntentionCatalogFixture(AppDatabase database, int size) =>
    database.batch((batch) {
      final timestampBase = DateTime.utc(2026, 9, 1).microsecondsSinceEpoch;
      for (var index = 0; index < size; index++) {
        final timestamp =
            timestampBase + (index % 7) * Duration.microsecondsPerMinute;
        final title = 'ааа запись $index';
        batch.insert(
          database.intentions,
          IntentionsCompanion.insert(
            id: intentionCatalogFixtureId(index),
            title: title,
            isArchived: Value(index.isOdd),
            createdAt: timestamp,
            updatedAt: timestamp,
          ),
        );
      }
    });
