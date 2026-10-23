import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:doable/src/tag/domain/tag_color.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/graph_seed.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/tag_storage_fixture.dart';

TagId _tag(int number) =>
    (TagId.decode(tagFixtureId(number)) as TagIdDecodingSuccess).id;

IntentionId _intention(int number) =>
    (IntentionId.decode(tagFixtureId(number)) as IntentionIdDecodingSuccess).id;

/// Выражение чтения строк каталога с условиями по тегам, в котором
/// внедряется отказ.
bool _isCatalogRows(String sql) =>
    sql.contains('json_each(') && sql.contains('LIMIT');

final class _ReadProbe extends LocalDatabaseConnectionObserver {
  /// Однократный отказ после первого подходящего выражения.
  bool Function(String sql)? failAfter;

  @override
  void afterStatement(LocalDatabaseSqlStatement statement) {
    final matches = failAfter;
    if (matches != null && matches(statement.statements.single)) {
      failAfter = null;
      throw StateError('CANARY-отказ совместного поиска');
    }
  }
}

void main() {
  late AppDatabase database;
  late sqlite.Database raw;
  late DriftPersonalGraphRepository graph;
  late _ReadProbe probe;
  late InMemoryDiagnosticsSink diagnostics;

  setUp(() async {
    probe = _ReadProbe();
    database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(setup: (db) => raw = db),
        probe,
      ),
    );
    await database.open();
    seedTagStorageFixture(raw);
    seedRawGraph(raw, () {
      raw.execute(
        'INSERT INTO intentions (id, title, created_at, updated_at) VALUES (?, ?, 1, 1)',
        [tagFixtureId(4), 'Намерение 4'],
      );
      // Назначения другого тега тем же намерениям чередуются с назначениями
      // выбранного тега.
      for (final (tagNumber, intentionNumber) in [
        (lastTagNumber, 1),
        (lastTagNumber, 4),
        (firstTagNumber, 4),
      ]) {
        raw.execute(
          'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
          [tagFixtureId(tagNumber), tagFixtureId(intentionNumber)],
        );
      }
    });
    diagnostics = InMemoryDiagnosticsSink();
    graph = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 28),
      diagnostics,
    );
  });
  tearDown(() => database.close());

  Future<void> expectCorruption() async {
    expect(
      await graph.getCatalogPage(
        IntentionCatalogQuery(
          scope: IntentionScope.active,
          titleFilter: null,
          tagFilter: IntentionTagFilter(requiredTagIds: [_tag(firstTagNumber)]),
          order: IntentionCatalogOrder.createdAtAscending,
          pageSize: 1,
        ),
      ),
      isA<ResultFailure<IntentionCatalogPage>>().having(
        (error) => error.failure,
        'причина',
        isA<IntentionCorruptionFailure>(),
      ),
    );
  }

  test(
    'краткие данные намерений возвращают теги с цветом и без цвета',
    () async {
      seedRawGraph(raw, () {
        raw.execute("UPDATE tags SET color = 'blue' WHERE id = ?", [
          tagFixtureId(firstTagNumber),
        ]);
      });

      final catalog = await graph.getCatalogPage(
        IntentionCatalogQuery(
          scope: IntentionScope.active,
          titleFilter: null,
          order: IntentionCatalogOrder.createdAtAscending,
          pageSize: 10,
        ),
      );

      final summary = (catalog as ResultSuccess<IntentionCatalogPage>)
          .value
          .items
          .singleWhere((item) => item.id == _intention(1));
      expect(summary.tags.map((tag) => tag.id), [
        _tag(firstTagNumber),
        _tag(lastTagNumber),
      ]);
      expect(summary.tags.map((tag) => tag.color), [TagColor.blue, null]);
    },
  );

  test('повреждение дополнительного намерения отклоняет всю порцию', () async {
    seedRawGraph(raw, () {
      raw.execute('UPDATE intentions SET title = ? WHERE id = ?', [
        ' CANARY-название ',
        tagFixtureId(4),
      ]);
    });
    await expectCorruption();
    final events = diagnostics.events
        .whereType<CatalogPageReadDiagnosticsEvent>()
        .toList();
    expect(
      events.last.status,
      isA<DiagnosticsFailed>().having(
        (status) => status.code,
        'категория',
        DiagnosticsFailureCode.corruption,
      ),
    );
    expect(events.join(' '), isNot(contains('CANARY')));
  });

  test(
    'неверная идентичность намерения отклоняет дополнительную строку',
    () async {
      seedRawGraph(raw, () {
        raw.execute('DELETE FROM tag_assignments WHERE intention_id = ?', [
          tagFixtureId(4),
        ]);
        raw.execute(
          'INSERT INTO intentions (id, title, created_at, updated_at) VALUES (?, ?, 1, 1)',
          ['CANARY-неверный-id', 'Намерение'],
        );
        raw.execute(
          'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
          [tagFixtureId(firstTagNumber), 'CANARY-неверный-id'],
        );
      });
      await expectCorruption();
    },
  );

  test('успешные и отказавшие чтения каталога с обязательным и '
      'исключёнными тегами не меняют сохранённый граф', () async {
    seedRawGraph(raw, () {
      for (var number = 10; number < 17; number++) {
        raw.execute(
          'INSERT INTO intentions (id, title, created_at, updated_at) VALUES (?, ?, ?, ?)',
          [tagFixtureId(number), 'Намерение $number', number, number],
        );
        for (final tagNumber in [
          firstTagNumber,
          if (number.isEven) lastTagNumber,
        ]) {
          raw.execute(
            'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
            [tagFixtureId(tagNumber), tagFixtureId(number)],
          );
        }
      }
    });
    Map<String, List<List<Object?>>> storedGraph() => {
      ...retainedTagFixtureGraph(raw),
      for (final table in ['tags', 'tag_assignments'])
        table: raw
            .select('SELECT * FROM $table ORDER BY rowid')
            .map((row) => row.values.toList())
            .toList(),
    };
    IntentionCatalogQuery query({IntentionCatalogCursor? cursor}) =>
        IntentionCatalogQuery(
          scope: IntentionScope.active,
          titleFilter: null,
          tagFilter: IntentionTagFilter(
            requiredTagIds: [_tag(firstTagNumber)],
            excludedTagIds: [_tag(lastTagNumber), _tag(999)],
          ),
          order: IntentionCatalogOrder.createdAtAscending,
          pageSize: 1,
          cursor: cursor,
        );
    IntentionCatalogPage success(Result<IntentionCatalogPage> result) =>
        (result as ResultSuccess<IntentionCatalogPage>).value;
    final before = storedGraph();

    final first = success(await graph.getCatalogPage(query()));
    expect(first.nextCursor, isNotNull);
    expect(storedGraph(), before);
    final repeated = success(await graph.getCatalogPage(query()));
    expect(
      repeated.items.map((item) => item.id),
      first.items.map((item) => item.id),
    );
    expect(storedGraph(), before);
    final continuation = success(
      await graph.getCatalogPage(query(cursor: first.nextCursor)),
    );
    expect(continuation.items.single.id, isNot(first.items.single.id));
    expect(storedGraph(), before);

    for (final (point, failAfter, cursor) in [
      ('первая порция', _isCatalogRows, null),
      ('продолжение', _isCatalogRows, first.nextCursor),
    ]) {
      probe.failAfter = failAfter;
      expect(
        await graph.getCatalogPage(query(cursor: cursor)),
        isA<ResultFailure<IntentionCatalogPage>>().having(
          (result) => result.failure,
          'отказ: $point',
          isA<IntentionUnexpectedFailure>(),
        ),
      );
      expect(probe.failAfter, isNull, reason: point);
      expect(storedGraph(), before, reason: point);
    }
    expect(
      success(await graph.getCatalogPage(query())).items.single.id,
      first.items.single.id,
    );
    expect(storedGraph(), before);
  });
}
