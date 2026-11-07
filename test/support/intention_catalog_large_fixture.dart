import 'package:doable/src/data/local/app_database.dart';
import 'package:drift/drift.dart';

import 'graph_seed.dart';

String intentionCatalogFixtureId(int index) =>
    '018f0b5d-6b2e-7c80-8000-${index.toRadixString(16).padLeft(12, '0')}';

/// Каждое второе намерение архивировано, а в каждом охвате половина намерений
/// вспомогательные: в каждой четвёрке подряд идут активное главное, архивное
/// главное, активное вспомогательное и архивное вспомогательное. Связей набор
/// не содержит: каталог читает вид без них.
Future<void> populateIntentionCatalogFixture(AppDatabase database, int size) =>
    seedGraph(
      database,
      () => database.batch((batch) {
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
              kind: Value(index % 4 < 2 ? 'main' : 'supporting'),
              isArchived: Value(index.isOdd),
              createdAt: timestamp,
              updatedAt: timestamp,
            ),
          );
        }
      }),
    );
