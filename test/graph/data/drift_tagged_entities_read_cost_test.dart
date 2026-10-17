import 'dart:io';

import 'package:doable/src/data/local/app_database.dart' hide Tags;
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/tag/application/tagged_intentions_page.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/tag_storage_fixture.dart';

/// Запоминает число строк, которое вернуло каждое чтение.
final class _Trace extends LocalDatabaseConnectionObserver {
  final rowCounts = <int>[];

  @override
  List<Map<String, Object?>> afterSelect(
    LocalDatabaseSqlStatement statement,
    List<Map<String, Object?>> rows,
  ) {
    rowCounts.add(rows.length);
    return rows;
  }

  void clear() => rowCounts.clear();
}

/// Архивирован один получатель из двадцати: среди 2 006 назначений
/// выбранного тега 51 архивное, то есть больше одной порции по 50.
const _archivePeriod = 40;

void main() {
  const pairs = 1003;
  test(
    'порции намерений и редкого архива среди назначений противоположного охвата и другого тега читаются ограниченно и полностью при ${pairs * 2} назначениях',
    () => _readAllPages(pairs),
  );
}

Future<void> _readAllPages(int pairs) async {
  final directory = await Directory.systemTemp.createTemp('doable_navigation_');
  final file = File('${directory.path}/navigation.sqlite');
  final trace = _Trace();
  late sqlite.Database raw;
  final database = AppDatabase(
    observeConfiguredLocalDatabaseConnection(
      openFileBackedLocalDatabase(
        file,
        setup: (connection) => raw = connection,
      ),
      trace,
    ),
  );
  try {
    await database.open();
    seedLargeTaggedEntitiesFixture(
      raw,
      recipientPairs: pairs,
      archivePeriod: _archivePeriod,
    );
    final graph = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 28),
      InMemoryDiagnosticsSink(),
    );
    final tagId = switch (TagId.decode(tagFixtureId(9000))) {
      TagIdDecodingSuccess(:final id) => id,
      InvalidTagIdDecoding() => throw StateError('Некорректная фикстура'),
    };
    int scalar(String sql) => raw.select(sql).single.values.single as int;
    expect(scalar('SELECT COUNT(*) FROM intentions'), pairs * 2 + 1);
    expect(scalar('SELECT COUNT(*) FROM long_term_relations'), pairs);
    expect(scalar('SELECT COUNT(*) FROM tag_assignments'), pairs * 4);

    for (final scope in TaggedIntentionsScope.values) {
      for (final size in [1, 50]) {
        await _traverse(graph, trace, tagId, pairs, scope, size);
      }
    }
  } finally {
    await database.close();
    await directory.delete(recursive: true);
  }
}

String _identity(TaggedIntention intention) => intention.id.toCanonicalString();

/// Проходит все порции охвата: каждая порция не больше [size], ни одно чтение
/// не возвращает больше [size] строк и признака продолжения, а вместе порции
/// дают весь охват в устойчивом порядке без повторов.
Future<void> _traverse(
  DriftPersonalGraphRepository graph,
  _Trace trace,
  TagId tagId,
  int pairs,
  TaggedIntentionsScope scope,
  int size,
) async {
  final expected = largeTaggedIntentions(
    pairs,
    archivePeriod: _archivePeriod,
    archived: scope == TaggedIntentionsScope.archived,
  );
  final ids = <String>[];
  TaggedIntentionsCursor? cursor;
  var pages = 0;
  do {
    trace.clear();
    final result = await graph.getTaggedIntentionsPage(
      TaggedIntentionsQuery(
        tagId: tagId,
        scope: scope,
        pageSize: size,
        cursor: cursor,
      ),
    );
    expect(result, isA<TaggedIntentionsPageSuccess>());
    final page = (result as TaggedIntentionsPageSuccess).value;
    expect(page.tag.id, tagId);
    expect(page.scope, scope);
    expect(page.items.length, lessThanOrEqualTo(size));
    expect(trace.rowCounts, everyElement(lessThanOrEqualTo(size + 1)));
    ids.addAll(page.items.map(_identity));
    cursor = page.nextCursor;
    pages++;
  } while (cursor != null);
  expect(pages, (expected.length / size).ceil());
  expect(ids, expected.map((entry) => entry.$1));
  expect(ids.toSet(), hasLength(expected.length));
}
