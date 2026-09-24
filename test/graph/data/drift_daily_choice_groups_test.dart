import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/in_memory_diagnostics_sink.dart';

String _uuid(int number) =>
    '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}';

IntentionId _id(int number) => switch (IntentionId.decode(_uuid(number))) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw StateError('Некорректный тестовый ID'),
};

final class _ReadProbe extends LocalDatabaseConnectionObserver {
  final statements = <String>[];

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (statement.operation == LocalDatabaseSqlOperation.select) {
      statements.add(statement.statements.single);
    }
  }
}

void main() {
  late AppDatabase database;
  late sqlite.Database raw;
  late DriftPersonalGraphRepository repository;
  late InMemoryDiagnosticsSink diagnostics;
  late _ReadProbe probe;

  setUp(() async {
    probe = _ReadProbe();
    diagnostics = InMemoryDiagnosticsSink();
    database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(setup: (db) => raw = db),
        probe,
      ),
    );
    await database.open();
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 23),
      diagnostics,
    );
    for (final number in [1, 2, 3, 4]) {
      raw.execute(
        '''INSERT INTO intentions
           (id, title, is_action_ready, is_archived, created_at, updated_at)
           VALUES (?, ?, ?, 0, 1, 1)''',
        [_uuid(number), 'Намерение $number', number == 2 ? 1 : 0],
      );
    }
    for (final (number, source, related) in [(101, 1, 2), (102, 3, 1)]) {
      raw.execute(
        '''INSERT INTO long_term_relations
           (id, source_intention_id, related_intention_id, type, priority,
            is_archived) VALUES (?, ?, ?, 'need', 2, 0)''',
        [_uuid(number), _uuid(source), _uuid(related)],
      );
    }
  });

  tearDown(() => database.close());

  void addChoice(
    int number, {
    required int source,
    required int selected,
    required List<int> path,
    String date = '2026-09-23',
    int completed = 0,
  }) {
    raw.execute(
      '''INSERT INTO daily_choices
         (id, source_intention_id, selected_intention_id, choice_date,
          is_completed) VALUES (?, ?, ?, ?, ?)''',
      [_uuid(number), _uuid(source), _uuid(selected), date, completed],
    );
    for (var index = 0; index < path.length; index++) {
      raw.execute(
        '''INSERT INTO daily_choice_path_steps
           (id, daily_choice_id, long_term_relation_id, previous_step_id)
           VALUES (?, ?, ?, ?)''',
        [
          _uuid(number * 10 + index + 10000),
          _uuid(number),
          _uuid(path[index]),
          index == 0 ? null : _uuid(number * 10 + index + 9999),
        ],
      );
    }
  }

  DailyChoiceGroupQuery query(
    DailyChoiceRelationRole role, {
    int owner = 1,
    int pageSize = 50,
    RelationGroupCursor? cursor,
  }) => DailyChoiceGroupQuery(
    intentionId: _id(owner),
    role: role,
    pageSize: pageSize,
    cursor: cursor,
  );

  RelationGroupPage page(RelationGroupPageResult result) =>
      (result as RelationGroupPageSuccess).value;

  RelationGroupReadFailure failure(RelationGroupPageResult result) =>
      (result as RelationGroupPageFailure).failure;

  test('разделяет прямые роли, сохраняет порядок и всю сводку', () async {
    addChoice(201, source: 1, selected: 2, path: [101], date: '2026-09-22');
    addChoice(202, source: 1, selected: 2, path: [101], completed: 1);
    addChoice(203, source: 1, selected: 2, path: [101]);
    addChoice(206, source: 1, selected: 2, path: [101]);
    addChoice(204, source: 3, selected: 1, path: [102]);
    addChoice(205, source: 3, selected: 2, path: [102, 101]);
    raw.execute('UPDATE long_term_relations SET is_archived = 1');

    final source = page(
      await repository.getRelationGroupPage(
        query(DailyChoiceRelationRole.source),
      ),
    ) as DailyChoiceGroupFirstPage;
    final selected = page(
      await repository.getRelationGroupPage(
        query(DailyChoiceRelationRole.selected),
      ),
    ) as DailyChoiceGroupFirstPage;

    expect(source.items.map((item) => item.id.toCanonicalString()), [
      _uuid(206),
      _uuid(203),
      _uuid(202),
      _uuid(201),
    ]);
    expect(source.items[2].isCompleted, isTrue);
    expect(source.items.first.source.title, 'Намерение 1');
    expect(source.items.first.selected.title, 'Намерение 2');
    expect(source.counts.dailySource, 4);
    expect(source.counts.dailySelected, 1);
    expect(source.counts.archivedNeedIncoming, 1);
    expect(source.counts.archivedNeedOutgoing, 1);
    expect(source.counts.total, 7);
    expect(selected.items.single.id.toCanonicalString(), _uuid(204));
    expect(selected.counts, source.counts);
    expect(source.nextCursor, isNull);
    expect(selected.nextCursor, isNull);
  });

  test('читает 250 зависимостей порциями по 50 без остальных путей', () async {
    for (var number = 200; number < 450; number++) {
      addChoice(number, source: 1, selected: 2, path: [101]);
    }
    addChoice(500, source: 3, selected: 1, path: [102]);
    addChoice(501, source: 3, selected: 2, path: [102, 101]);
    raw.execute(
      'DELETE FROM daily_choice_path_steps WHERE daily_choice_id = ?',
      [_uuid(500)],
    );
    probe.statements.clear();

    final ids = <String>[];
    RelationGroupCursor? cursor;
    var reads = 0;
    do {
      final result = page(
        await repository.getRelationGroupPage(
          query(DailyChoiceRelationRole.source, cursor: cursor),
        ),
      );
      if (reads == 0) {
        expect((result as DailyChoiceGroupFirstPage).counts.dailySource, 250);
        expect(result.counts.dailySelected, 1);
      } else {
        expect(result, isA<DailyChoiceGroupContinuationPage>());
      }
      ids.addAll(switch (result) {
        DailyChoiceGroupFirstPage(:final items) ||
        DailyChoiceGroupContinuationPage(
          :final items,
        ) => items.map((item) => item.id.toCanonicalString()),
        _ => throw StateError('Ожидалась дневная группа'),
      });
      cursor = result.nextCursor;
      reads++;
    } while (cursor != null);

    expect(reads, 5);
    expect(ids, [
      for (var number = 449; number >= 200; number--) _uuid(number),
    ]);
    final pageReads = probe.statements.where(
      (sql) => sql.contains('FROM daily_choices') && !sql.contains('COUNT('),
    );
    expect(pageReads, hasLength(5));
    expect(pageReads.every((sql) => sql.contains('LIMIT')), isTrue);
    final pathReads = probe.statements.where(
      (sql) => sql.contains('FROM daily_choice_path_steps'),
    );
    expect(pathReads, hasLength(5));
    expect(
      pathReads.every((sql) => sql.contains('daily_choice_id IN')),
      isTrue,
    );
  });

  test('продолжает группу выбранного действия через границу дат', () async {
    addChoice(201, source: 3, selected: 1, path: [102], date: '2026-09-22');
    addChoice(202, source: 3, selected: 1, path: [102]);
    addChoice(203, source: 3, selected: 2, path: [102, 101]);
    raw.execute(
      'DELETE FROM daily_choice_path_steps WHERE daily_choice_id = ?',
      [_uuid(203)],
    );

    final first = page(
      await repository.getRelationGroupPage(
        query(DailyChoiceRelationRole.selected, pageSize: 1),
      ),
    ) as DailyChoiceGroupFirstPage;
    final second = page(
      await repository.getRelationGroupPage(
        query(
          DailyChoiceRelationRole.selected,
          pageSize: 1,
          cursor: first.nextCursor,
        ),
      ),
    ) as DailyChoiceGroupContinuationPage;

    expect(first.counts.dailySelected, 2);
    expect(first.items.single.id.toCanonicalString(), _uuid(202));
    expect(second.items.single.id.toCanonicalString(), _uuid(201));
    expect(second.revision.compareTo(first.revision), GraphRevisionOrder.same);
    expect(second.nextCursor, isNull);
  });

  test('отклоняет чужой курсор и устаревшую ревизию', () async {
    addChoice(201, source: 1, selected: 2, path: [101]);
    addChoice(202, source: 1, selected: 2, path: [101]);
    final first = page(
      await repository.getRelationGroupPage(
        query(DailyChoiceRelationRole.source, pageSize: 1),
      ),
    );
    final cursor = first.nextCursor!;
    for (final invalid in [
      query(DailyChoiceRelationRole.selected, pageSize: 1, cursor: cursor),
      query(
        DailyChoiceRelationRole.source,
        owner: 2,
        pageSize: 1,
        cursor: cursor,
      ),
      query(DailyChoiceRelationRole.source, pageSize: 2, cursor: cursor),
    ]) {
      expect(
        failure(await repository.getRelationGroupPage(invalid)),
        isA<RelationGroupReadValidationFailure>(),
      );
    }
    final other = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 23),
      diagnostics,
    );
    expect(
      failure(
        await other.getRelationGroupPage(
          query(DailyChoiceRelationRole.source, pageSize: 1, cursor: cursor),
        ),
      ),
      isA<RelationGroupSnapshotExpired>(),
    );
    await repository.execute(EnableIntentionReadiness(_id(4)));
    expect(
      failure(
        await repository.getRelationGroupPage(
          query(DailyChoiceRelationRole.source, pageSize: 1, cursor: cursor),
        ),
      ),
      isA<RelationGroupSnapshotExpired>(),
    );
    expect(
      diagnostics.events
          .whereType<DailyChoiceGroupPageReadDiagnosticsEvent>()
          .last
          .requiresNewSnapshot,
      isTrue,
    );
  });

  test('различает отсутствие, пустую группу и повреждённый путь', () async {
    expect(
      failure(
        await repository.getRelationGroupPage(
          query(DailyChoiceRelationRole.source, owner: 999),
        ),
      ),
      isA<RelationGroupIntentionNotFoundFailure>(),
    );
    final empty = page(
      await repository.getRelationGroupPage(
        query(DailyChoiceRelationRole.selected),
      ),
    ) as DailyChoiceGroupFirstPage;
    expect(empty.items, isEmpty);
    expect(empty.counts.dailySelected, 0);

    addChoice(201, source: 1, selected: 2, path: [101]);
    addChoice(202, source: 1, selected: 2, path: [101]);
    raw.execute(
      'DELETE FROM daily_choice_path_steps WHERE daily_choice_id = ?',
      [_uuid(201)],
    );
    final first = page(
      await repository.getRelationGroupPage(
        query(DailyChoiceRelationRole.source, pageSize: 1),
      ),
    ) as DailyChoiceGroupFirstPage;
    expect(first.items.single.id.toCanonicalString(), _uuid(202));
    expect(first.counts.dailySource, 2);
    expect(
      failure(
        await repository.getRelationGroupPage(
          query(
            DailyChoiceRelationRole.source,
            pageSize: 1,
            cursor: first.nextCursor,
          ),
        ),
      ),
      isA<RelationGroupCorruptionFailure>(),
    );
    expect(
      (diagnostics.events
                  .whereType<DailyChoiceGroupPageReadDiagnosticsEvent>()
                  .last
                  .status
              as DiagnosticsFailed)
          .code,
      DiagnosticsFailureCode.corruption,
    );
  });
}
