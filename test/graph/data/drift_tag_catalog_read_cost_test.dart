import 'dart:io';

import 'package:doable/src/data/local/app_database.dart' hide Tags;
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/graph_seed.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/tag_storage_fixture.dart';

void main() {
  test(
    'большой каталог читается одним полным снимком без пропусков',
    expectFullTagCatalogSnapshot,
  );
}

Future<void> expectFullTagCatalogSnapshot() async {
  final directory = await Directory.systemTemp.createTemp('doable_tag_cost_');
  final file = File('${directory.path}/catalog.sqlite');
  late sqlite.Database raw;
  final database = AppDatabase(
    openFileBackedLocalDatabase(file, setup: (connection) => raw = connection),
  );
  try {
    await database.open();
    final repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 25),
      InMemoryDiagnosticsSink(),
    );
    seedTagStorageFixture(raw);

    void seedTo(int count, int current) {
      seedRawGraph(raw, () {
        for (var index = current; index < count; index++) {
          final number = 10000 + index;
          raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
            tagFixtureId(number),
            'Тег ${index.toString().padLeft(6, '0')}',
          ]);
          if (index % 10 == 0) {
            raw.execute(
              'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
              [tagFixtureId(number), tagFixtureId(1)],
            );
          }
        }
      });
    }

    Future<void> expectFullSnapshot(int count) async {
      final result = await repository.getTagCatalog(
        const TagCatalogBrowseMode(),
      );
      expect(result, isA<TagCatalogSuccess>());
      final snapshot = (result as TagCatalogSuccess).value;
      final expectedIds = [
        tagFixtureId(firstTagNumber),
        tagFixtureId(lastTagNumber),
        for (var index = 2; index < count; index++) tagFixtureId(10000 + index),
      ];
      expect(
        snapshot.items.map((tag) => tag.id.toCanonicalString()),
        expectedIds,
      );
      expect(snapshot.items.map((tag) => tag.id).toSet(), hasLength(count));
    }

    seedTo(10000, 2);
    await expectFullSnapshot(10000);
  } finally {
    await database.close();
    await directory.delete(recursive: true);
  }
}
