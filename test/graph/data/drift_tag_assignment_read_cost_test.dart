@Tags(['slow'])
library;

import 'dart:io';

import 'package:doable/src/data/local/app_database.dart' hide Tags;
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/tag/application/tag_assignments.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/tag_storage_fixture.dart';

void main() {
  const tagCount = 1203;
  test(
    'назначения и выбор читаются полными снимками при $tagCount тегах',
    () => _expectFullAssignmentSnapshots(tagCount),
  );
}

Future<void> _expectFullAssignmentSnapshots(int tagCount) async {
  final directory = await Directory.systemTemp.createTemp(
    'doable_assignment_cost_',
  );
  final file = File('${directory.path}/assignments.sqlite');
  late sqlite.Database raw;
  final database = AppDatabase(
    openFileBackedLocalDatabase(file, setup: (connection) => raw = connection),
  );
  try {
    await database.open();
    seedLargeTagReadFixture(
      raw,
      tagCount: tagCount,
      includeDenseRecipients: true,
    );
    // Посторонние назначения тех же тегов другим намерениям обоих охватов
    // не уменьшают объём, среди которого читаются снимки.
    expect(
      raw.select('SELECT COUNT(*) FROM tag_assignments').single.values.single,
      largeTagReadFixtureAssignmentCount(
        tagCount: tagCount,
        includeDenseRecipients: true,
      ),
    );
    expect(
      raw
          .select('SELECT COUNT(DISTINCT intention_id) FROM tag_assignments')
          .single
          .values
          .single,
      4,
    );
    final repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 27),
      InMemoryDiagnosticsSink(),
    );
    final intention =
        (IntentionId.decode(tagFixtureId(1)) as IntentionIdDecodingSuccess).id;

    // Намерению назначен каждый второй тег.
    final assignedIds = [
      for (var index = 0; index < tagCount; index++)
        if (index.isEven) tagFixtureId(10000 + index),
    ];
    final allIds = [
      for (var index = 0; index < tagCount; index++)
        tagFixtureId(10000 + index),
    ];

    final assignments = await repository.getTagAssignments(intention);
    expect(assignments, isA<TagAssignmentsSuccess>());
    final assignmentsSnapshot = (assignments as TagAssignmentsSuccess).value;
    expect(assignmentsSnapshot.intentionId, intention);
    expect(
      assignmentsSnapshot.items.map((tag) => tag.id.toCanonicalString()),
      assignedIds,
    );

    final selection = await repository.getTagCatalog(
      TagCatalogSelectionMode(intention),
    );
    expect(selection, isA<TagCatalogSuccess>());
    final selectionSnapshot =
        (selection as TagCatalogSuccess).value as TagSelectionSnapshot;
    expect(selectionSnapshot.intentionId, intention);
    expect(
      selectionSnapshot.rows.map((row) => row.tag.id.toCanonicalString()),
      allIds,
    );
    expect(selectionSnapshot.rows.map((row) => row.isAssigned), [
      for (var index = 0; index < tagCount; index++) index.isEven,
    ]);
  } finally {
    await database.close();
    await directory.delete(recursive: true);
  }
}
