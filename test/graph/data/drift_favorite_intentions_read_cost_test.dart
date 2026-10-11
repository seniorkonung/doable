@Tags(['slow'])
library;

import 'package:doable/src/favorite/application/favorite_intentions.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/favorite_storage_fixture.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/local_database_harness.dart';

void main() {
  late LocalDatabaseHarness harness;
  late sqlite.Database raw;
  late DriftPersonalGraphRepository repository;

  setUp(() async {
    harness = await LocalDatabaseHarness.fileBacked();
    final database = await harness.openReadyDatabase(
      setup: (connection) => raw = connection,
    );
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 10, 2, 12),
      InMemoryDiagnosticsSink(),
    );
  });

  tearDown(() => harness.dispose());

  test('1000 избранных намерений с архивированными возвращаются одним '
      'снимком без продолжения, усечения и предела', () async {
    const count = 1000;
    const archivedEvery = 4;
    seedLargeFavoriteFixture(raw, count: count, archivedEvery: archivedEvery);
    final expected = largeFavoriteFixtureActiveRows(
      count: count,
      archivedEvery: archivedEvery,
    );
    final archivedCount = largeFavoriteFixtureArchivedCount(
      count: count,
      archivedEvery: archivedEvery,
    );
    expect(expected, hasLength(750));
    expect(archivedCount, 250);

    final result = await repository.getFavoriteIntentions();

    final snapshot = (result as FavoriteIntentionsSuccess).value;
    expect(snapshot.items.map(_row), expected);
    expect(snapshot.archivedCount, archivedCount);
  });
}

LargeFavoriteFixtureRow _row(FavoriteIntentionRow row) => (
  id: row.id.toCanonicalString(),
  title: row.title,
  isActionReady: row.readiness == IntentionReadiness.ready,
  activeRelationCount: row.activeRelationCount,
);
