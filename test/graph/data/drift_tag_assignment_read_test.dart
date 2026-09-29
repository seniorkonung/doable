import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/tag/application/tag_assignments.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_assignment_status.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/tag_storage_fixture.dart';

IntentionId _intention(int number) =>
    (IntentionId.decode(tagFixtureId(number)) as IntentionIdDecodingSuccess).id;

void _insertMissingTagReference(
  sqlite.Database database,
  String recipientColumn,
  String recipientId,
) {
  final tagId = tagFixtureId(999);
  database.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
    tagId,
    'Временный тег',
  ]);
  database.execute(
    'INSERT INTO tag_assignments (tag_id, $recipientColumn) VALUES (?, ?)',
    [tagId, recipientId],
  );
  database.execute('DELETE FROM tags WHERE id = ?', [tagId]);
}

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
  late DriftPersonalGraphRepository graph;
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
    seedTagStorageFixture(raw);
    graph = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 27),
      diagnostics,
    );
    probe.statements.clear();
  });
  tearDown(() => database.close());

  TagAssignmentsSnapshot assignments(TagAssignmentsResult result) =>
      (result as TagAssignmentsSuccess).value;

  TagSelectionSnapshot selection(TagCatalogResult result) =>
      (result as TagCatalogSuccess).value as TagSelectionSnapshot;

  test('точечное чтение различает пару и отсутствие для активного и архивированного намерения', () async {
    final assignedTag =
        (TagId.decode(tagFixtureId(firstTagNumber)) as TagIdDecodingSuccess).id;
    final freeTag =
        (TagId.decode(tagFixtureId(lastTagNumber)) as TagIdDecodingSuccess).id;
    final missingTag =
        (TagId.decode(tagFixtureId(999)) as TagIdDecodingSuccess).id;
    for (final (assignedTarget, missingTarget) in [
      (_intention(1), _intention(999)),
      (_intention(2), _intention(999)),
    ]) {
      final assigned = await graph.getTagAssignmentStatus(
        assignedTag,
        assignedTarget,
      );
      final free = await graph.getTagAssignmentStatus(freeTag, assignedTarget);
      expect((assigned as TagAssignmentStatusSuccess).value.value, isTrue);
      expect((free as TagAssignmentStatusSuccess).value.value, isFalse);
      expect(
        assigned.value.revision.compareTo(free.value.revision),
        GraphRevisionOrder.same,
      );
      expect(
        await graph.getTagAssignmentStatus(missingTag, assignedTarget),
        isA<TagAssignmentStatusError>().having(
          (error) => error.failure,
          'причина',
          isA<TagAssignmentStatusTagNotFound>(),
        ),
      );
      expect(
        await graph.getTagAssignmentStatus(assignedTag, missingTarget),
        isA<TagAssignmentStatusError>().having(
          (error) => error.failure,
          'причина',
          isA<TagAssignmentStatusIntentionNotFound>(),
        ),
      );
    }
  });

  test(
    'точечное чтение у начала и конца большого каталога использует индексы',
    () async {
      for (var number = 303; number <= 1502; number++) {
        raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
          tagFixtureId(number),
          'Тег $number',
        ]);
        for (final (column, recipient) in [('intention_id', tagFixtureId(1))]) {
          raw.execute(
            'INSERT INTO tag_assignments (tag_id, $column) VALUES (?, ?)',
            [tagFixtureId(number), recipient],
          );
        }
      }
      var visits = 0;
      raw.createFunction(
        functionName: 'measure_pair_scan',
        function: (_) {
          visits++;
          return 1;
        },
      );
      for (final (target, column, recipient) in [
        (_intention(1), 'intention_id', tagFixtureId(1)),
      ]) {
        for (final number in [303, 1502]) {
          final tag =
              (TagId.decode(tagFixtureId(number)) as TagIdDecodingSuccess).id;
          probe.statements.clear();
          final result = await graph.getTagAssignmentStatus(tag, target);
          expect((result as TagAssignmentStatusSuccess).value.value, isTrue);
          final query = probe.statements.singleWhere(
            (sql) => sql.contains('AS is_assigned'),
          );
          expect(probe.statements, hasLength(1));
          final args = [
            tagFixtureId(number),
            recipient,
            tagFixtureId(number),
            recipient,
          ];
          final plan = raw
              .select('EXPLAIN QUERY PLAN $query', args)
              .map((row) => row['detail'].toString())
              .toList();
          expect(
            plan.join(' '),
            contains('SEARCH tag_assignments USING COVERING INDEX'),
          );
          final measured = query.replaceFirst(
            'AND $column = ?',
            'AND $column = ? AND measure_pair_scan(tag_id) = 1',
          );
          expect(measured, isNot(query));
          expect(
            raw
                .select('EXPLAIN QUERY PLAN $measured', args)
                .map((row) => row['detail'].toString())
                .toList(),
            plan,
          );
          visits = 0;
          expect(raw.select(measured, args).single['is_assigned'], 1);
          expect(visits, 1);
        }
      }
    },
  );

  test(
    'полное чтение назначений сохраняет порядок всех 104 тегов намерения',
    () async {
      for (var number = 303; number <= 405; number++) {
        raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
          tagFixtureId(number),
          'Тег $number',
        ]);
        for (final (column, recipient) in [('intention_id', tagFixtureId(1))]) {
          raw.execute(
            'INSERT INTO tag_assignments (tag_id, $column) VALUES (?, ?)',
            [tagFixtureId(number), recipient],
          );
        }
      }
      for (final target in [_intention(1)]) {
        probe.statements.clear();
        final loaded = assignments(await graph.getTagAssignments(target));
        expect(loaded.intentionId, target);
        expect(loaded.items.map((tag) => tag.name.value), [
          'Дом',
          for (var number = 303; number <= 405; number++) 'Тег $number',
        ]);
        expect(loaded.items.map((tag) => tag.id.toCanonicalString()), [
          tagFixtureId(firstTagNumber),
          for (var number = 303; number <= 405; number++) tagFixtureId(number),
        ]);
        expect(
          probe.statements.where(
            (sql) => sql.contains('FROM tag_assignments a JOIN tags t'),
          ),
          hasLength(1),
        );
      }
    },
  );

  test(
    'прежние назначения связям не становятся назначениями намерений',
    () async {
      raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
        tagFixtureId(303),
        'Только прежним связям',
      ]);
      for (final number in [101, 102]) {
        raw.execute(
          'INSERT INTO tag_assignments (tag_id, long_term_relation_id) VALUES (?, ?)',
          [tagFixtureId(303), tagFixtureId(number)],
        );
      }
      final oldAssignments = raw.select('SELECT * FROM tag_assignments');
      final loaded = selection(
        await graph.getTagCatalog(TagCatalogSelectionMode(_intention(2))),
      );
      expect(loaded.rows.map((row) => row.isAssigned), [true, false, false]);
      expect(loaded.items.map((tag) => tag.name.value), [
        'Дом',
        'Работа',
        'Только прежним связям',
      ]);
      expect(
        (await graph.getTagCatalog(
          const TagCatalogBrowseMode(),
        ) as TagCatalogSuccess).value.items.map((tag) => tag.id),
        loaded.items.map((tag) => tag.id),
      );
      expect(
        assignments(await graph.getTagAssignments(_intention(2))).items
            .map((tag) => tag.id.toCanonicalString()),
        [tagFixtureId(firstTagNumber)],
      );
      expect(
        await graph.getTagAssignments(_intention(101)),
        isA<TagAssignmentsError>().having(
          (error) => error.failure,
          'причина',
          isA<TagAssignmentsIntentionNotFound>(),
        ),
      );

      raw.execute(
        'INSERT INTO intentions (id, title, created_at, updated_at) VALUES (?, ?, ?, ?)',
        [tagFixtureId(101), 'Отдельное намерение', 1, 1],
      );
      final empty = assignments(await graph.getTagAssignments(_intention(101)));
      expect(empty.items, isEmpty);
      final unassigned = selection(
        await graph.getTagCatalog(TagCatalogSelectionMode(_intention(101))),
      );
      expect(unassigned.items, hasLength(3));
      expect(unassigned.rows.map((row) => row.isAssigned), [
        false,
        false,
        false,
      ]);
      final tagId =
          (TagId.decode(tagFixtureId(303)) as TagIdDecodingSuccess).id;
      expect(
        (await graph.getTagAssignmentStatus(
          tagId,
          _intention(101),
        ) as TagAssignmentStatusSuccess).value.value,
        isFalse,
      );
      expect(raw.select('SELECT * FROM tag_assignments'), oldAssignments);
      for (final sql in probe.statements) {
        expect(sql, isNot(contains('long_term_relations')));
        expect(sql, isNot(contains('long_term_relation_id')));
        expect(sql, isNot(contains('daily_choice')));
        expect(sql, isNot(contains('description')));
        expect(sql, isNot(contains('title')));
      }
    },
  );

  test('неизменяемые снимки сохраняют порядок тегов и общую ревизию', () async {
    final intentionId = _intention(1);
    final tagId =
        (TagId.decode(tagFixtureId(firstTagNumber)) as TagIdDecodingSuccess).id;
    final before = assignments(await graph.getTagAssignments(intentionId));
    final catalog = selection(
      await graph.getTagCatalog(TagCatalogSelectionMode(intentionId)),
    );
    final status = (await graph.getTagAssignmentStatus(
      tagId,
      intentionId,
    ) as TagAssignmentStatusSuccess).value;
    expect(
      catalog.revision.compareTo(before.revision),
      GraphRevisionOrder.same,
    );
    expect(status.revision.compareTo(before.revision), GraphRevisionOrder.same);
    expect(() => before.items.clear(), throwsUnsupportedError);
    expect(() => catalog.items.clear(), throwsUnsupportedError);
    expect(() => catalog.rows.clear(), throwsUnsupportedError);

    expect(
      await graph.execute(
        RenameTag(tagId: tagId, name: TagName.fromInput('Я')),
      ),
      isA<TagCommandSucceeded>(),
    );
    final after = assignments(await graph.getTagAssignments(intentionId));
    final renamed = selection(
      await graph.getTagCatalog(TagCatalogSelectionMode(intentionId)),
    );
    final updated = (await graph.getTagAssignmentStatus(
      tagId,
      intentionId,
    ) as TagAssignmentStatusSuccess).value;
    expect(after.items.map((tag) => tag.name.value), ['Я']);
    expect(renamed.items.map((tag) => tag.name.value), ['Я', 'Работа']);
    expect(after.revision.compareTo(before.revision), GraphRevisionOrder.newer);
    expect(renamed.revision.compareTo(after.revision), GraphRevisionOrder.same);
    expect(updated.revision.compareTo(after.revision), GraphRevisionOrder.same);
    expect(before.items.single.name.value, 'Дом');
    expect(catalog.items.first.name.value, 'Дом');
  });

  test(
    'точечное чтение не скрывает отсутствующую сторону сохранённой пары',
    () async {
      raw.execute('PRAGMA foreign_keys = OFF');
      final tagId = (TagId.decode(
        tagFixtureId(firstTagNumber),
      ) as TagIdDecodingSuccess).id;
      raw.execute(
        'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
        [tagFixtureId(firstTagNumber), tagFixtureId(999)],
      );
      expect(
        await graph.getTagAssignmentStatus(tagId, _intention(999)),
        isA<TagAssignmentStatusError>().having(
          (error) => error.failure,
          'причина',
          isA<TagAssignmentStatusCorruption>(),
        ),
      );
      _insertMissingTagReference(raw, 'intention_id', tagFixtureId(1));
      final missingTag =
          (TagId.decode(tagFixtureId(999)) as TagIdDecodingSuccess).id;
      expect(
        await graph.getTagAssignmentStatus(missingTag, _intention(1)),
        isA<TagAssignmentStatusError>().having(
          (error) => error.failure,
          'причина',
          isA<TagAssignmentStatusCorruption>(),
        ),
      );
    },
  );

  test(
    'ключ порядка назначения повторяет создание тега и остаётся неизменным',
    () {
      final tagId = tagFixtureId(firstTagNumber);
      final expected = raw.select(
        'SELECT creation_sequence FROM tags WHERE id = ?',
        [tagId],
      ).single['creation_sequence'];
      final assignment = raw.select(
        'SELECT creation_sequence, tag_creation_sequence FROM tag_assignments WHERE tag_id = ? AND intention_id = ?',
        [tagId, tagFixtureId(1)],
      ).single;
      expect(assignment['tag_creation_sequence'], expected);

      expect(
        () => raw.execute(
          'UPDATE tag_assignments SET tag_creation_sequence = ? WHERE creation_sequence = ?',
          [(expected as int) + 1, assignment['creation_sequence']],
        ),
        throwsA(isA<sqlite.SqliteException>()),
      );
      expect(
        () => raw.execute(
          'INSERT INTO tag_assignments (tag_id, intention_id, tag_creation_sequence) VALUES (?, ?, ?)',
          [tagFixtureId(lastTagNumber), tagFixtureId(1), expected],
        ),
        throwsA(isA<sqlite.SqliteException>()),
      );
      expect(
        raw.select(
          'SELECT tag_creation_sequence FROM tag_assignments WHERE creation_sequence = ?',
          [assignment['creation_sequence']],
        ).single['tag_creation_sequence'],
        expected,
      );
    },
  );

  test(
    'повторное назначение не переносит тег в конец списка получателя',
    () async {
      for (final (target, column, recipientId) in [
        (_intention(1), 'intention_id', tagFixtureId(1)),
      ]) {
        raw.execute(
          'INSERT INTO tag_assignments (tag_id, $column) VALUES (?, ?)',
          [tagFixtureId(lastTagNumber), recipientId],
        );
        raw.execute(
          'DELETE FROM tag_assignments WHERE tag_id = ? AND $column = ?',
          [tagFixtureId(firstTagNumber), recipientId],
        );
        raw.execute(
          'INSERT INTO tag_assignments (tag_id, $column) VALUES (?, ?)',
          [tagFixtureId(firstTagNumber), recipientId],
        );
        final loaded = assignments(await graph.getTagAssignments(target));
        expect(loaded.items.map((tag) => tag.name.value), ['Дом', 'Работа']);
      }
    },
  );

  test(
    'выбор помечает только назначения намерения и проверяет его отсутствие',
    () async {
      for (final (target, missing) in [(_intention(1), _intention(999))]) {
        probe.statements.clear();
        final loaded = selection(
          await graph.getTagCatalog(TagCatalogSelectionMode(target)),
        );
        expect(loaded.intentionId, target);
        expect(loaded.rows.map((row) => row.tag.id.toCanonicalString()), [
          tagFixtureId(firstTagNumber),
          tagFixtureId(lastTagNumber),
        ]);
        expect(loaded.rows.map((row) => row.isAssigned), [true, false]);
        final mainQueries = probe.statements.where(
          (sql) => sql.contains('FROM tags t'),
        );
        expect(mainQueries, hasLength(1));
        expect(mainQueries.single, contains('EXISTS('));
        expect(
          await graph.getTagAssignments(missing),
          isA<TagAssignmentsError>().having(
            (error) => error.failure,
            'причина',
            isA<TagAssignmentsIntentionNotFound>(),
          ),
        );
        expect(
          await graph.getTagCatalog(TagCatalogSelectionMode(missing)),
          isA<TagCatalogError>().having(
            (error) => error.failure,
            'причина',
            isA<TagCatalogIntentionNotFound>(),
          ),
        );
      }
    },
  );

  test('существующее намерение без назначений даёт пустой снимок', () async {
    for (final (target, column, recipient) in [
      (_intention(3), 'intention_id', tagFixtureId(3)),
    ]) {
      raw.execute('DELETE FROM tag_assignments WHERE $column = ?', [recipient]);
      probe.statements.clear();
      final loaded = assignments(await graph.getTagAssignments(target));
      expect(loaded.intentionId, target);
      expect(loaded.items, isEmpty);
      expect(
        probe.statements.where(
          (sql) => sql.contains('FROM tag_assignments a JOIN tags t'),
        ),
        hasLength(1),
      );
    }
  });

  test('каталог выбора возвращает все 105 тегов без пропусков', () async {
    for (var number = 303; number <= 405; number++) {
      raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
        tagFixtureId(number),
        'Тег $number',
      ]);
    }
    for (final target in [_intention(2)]) {
      probe.statements.clear();
      final loaded = selection(
        await graph.getTagCatalog(TagCatalogSelectionMode(target)),
      );
      expect(loaded.rows.map((row) => row.tag.name.value), [
        'Дом',
        'Работа',
        for (var number = 303; number <= 405; number++) 'Тег $number',
      ]);
      expect(loaded.rows.map((row) => row.tag.id.toCanonicalString()), [
        tagFixtureId(firstTagNumber),
        tagFixtureId(lastTagNumber),
        for (var number = 303; number <= 405; number++) tagFixtureId(number),
      ]);
      expect(loaded.rows.map((row) => row.isAssigned), [
        true,
        for (var n = 0; n < 104; n++) false,
      ]);
      expect(
        probe.statements.where((sql) => sql.contains('FROM tags t')),
        hasLength(1),
      );
    }
  });

  test('каждый полный снимок проверяет ссылки одним запросом', () async {
    for (var number = 303; number <= 405; number++) {
      raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
        tagFixtureId(number),
        'Тег $number',
      ]);
      for (final (column, recipient) in [('intention_id', tagFixtureId(1))]) {
        raw.execute(
          'INSERT INTO tag_assignments (tag_id, $column) VALUES (?, ?)',
          [tagFixtureId(number), recipient],
        );
      }
    }
    for (final target in [_intention(1)]) {
      probe.statements.clear();
      expect(
        assignments(await graph.getTagAssignments(target)).items,
        hasLength(104),
      );
      expect(
        probe.statements.where((sql) => sql.contains('LEFT JOIN tags')),
        hasLength(1),
      );
      expect(
        probe.statements.where(
          (sql) => sql.contains('FROM tag_assignments a JOIN tags t'),
        ),
        hasLength(1),
      );

      probe.statements.clear();
      expect(
        selection(await graph.getTagCatalog(TagCatalogSelectionMode(target)))
            .rows,
        hasLength(105),
      );
      expect(
        probe.statements.where((sql) => sql.contains('LEFT JOIN tags')),
        hasLength(1),
      );
      expect(
        probe.statements.where((sql) => sql.contains('FROM tags t')),
        hasLength(1),
      );
    }
  });

  test('повреждённая ссылка отклоняет оба полных чтения', () async {
    raw.execute('PRAGMA foreign_keys = OFF');
    for (final target in [_intention(1)]) {
      final column = 'intention_id';
      final id = target.toCanonicalString();
      _insertMissingTagReference(raw, column, id);
      expect(
        await graph.getTagAssignments(target),
        isA<TagAssignmentsError>().having(
          (error) => error.failure,
          'причина',
          isA<TagAssignmentsCorruptionFailure>(),
        ),
      );
      expect(
        await graph.getTagCatalog(TagCatalogSelectionMode(target)),
        isA<TagCatalogError>().having(
          (error) => error.failure,
          'причина',
          isA<TagCatalogCorruptionFailure>(),
        ),
      );
      raw.execute('DELETE FROM tag_assignments WHERE tag_id = ?', [
        tagFixtureId(999),
      ]);
    }
  });

  test(
    'новое чтение замечает повреждение и восстанавливается после исправления',
    () async {
      raw.execute('PRAGMA foreign_keys = OFF');
      for (final target in [_intention(1)]) {
        final column = 'intention_id';
        final id = target.toCanonicalString();
        final firstAssignments = assignments(
          await graph.getTagAssignments(target),
        );
        final firstSelection = selection(
          await graph.getTagCatalog(TagCatalogSelectionMode(target)),
        );
        _insertMissingTagReference(raw, column, id);
        expect(
          await graph.getTagAssignments(target),
          isA<TagAssignmentsError>().having(
            (error) => error.failure,
            'причина',
            isA<TagAssignmentsCorruptionFailure>(),
          ),
        );
        expect(
          await graph.getTagCatalog(TagCatalogSelectionMode(target)),
          isA<TagCatalogError>().having(
            (error) => error.failure,
            'причина',
            isA<TagCatalogCorruptionFailure>(),
          ),
        );
        raw.execute('DELETE FROM tag_assignments WHERE tag_id = ?', [
          tagFixtureId(999),
        ]);
        final restoredAssignments = assignments(
          await graph.getTagAssignments(target),
        );
        final restoredSelection = selection(
          await graph.getTagCatalog(TagCatalogSelectionMode(target)),
        );
        expect(
          restoredAssignments.items.map((tag) => tag.id),
          firstAssignments.items.map((tag) => tag.id),
        );
        expect(
          restoredSelection.rows.map((row) => row.tag.id),
          firstSelection.rows.map((row) => row.tag.id),
        );
        expect(
          restoredSelection.rows.map((row) => row.isAssigned),
          firstSelection.rows.map((row) => row.isAssigned),
        );
      }
    },
  );

  test('полные снимки разных намерений и ревизий не смешиваются', () async {
    final target = _intention(1);
    raw.execute(
      'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
      [tagFixtureId(lastTagNumber), tagFixtureId(1)],
    );
    final first = assignments(await graph.getTagAssignments(target));
    final other = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 27),
      diagnostics,
    );
    final sameTarget = assignments(await other.getTagAssignments(target));
    expect(
      sameTarget.items.map((tag) => tag.id),
      first.items.map((tag) => tag.id),
    );
    final otherIntention = _intention(3);
    final otherTarget = assignments(
      await graph.getTagAssignments(otherIntention),
    );
    expect(otherTarget.intentionId, otherIntention);
    expect(otherTarget.items.map((tag) => tag.id.toCanonicalString()), [
      tagFixtureId(lastTagNumber),
    ]);
    expect(
      await graph.execute(
        const CreateIntention(title: 'Новое намерение', description: null),
      ),
      isA<GraphCommandSucceeded>(),
    );
    final updated = assignments(await graph.getTagAssignments(target));
    expect(
      updated.items.map((tag) => tag.id),
      first.items.map((tag) => tag.id),
    );
    expect(
      updated.revision.compareTo(first.revision),
      GraphRevisionOrder.newer,
    );
    expect(first.items, hasLength(2));
  });

  test(
    'повреждение строки после сотой и отсутствующей ссылки отклоняет снимок',
    () async {
      for (var number = 303; number <= 439; number++) {
        raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
          tagFixtureId(number),
          'Тег $number',
        ]);
        for (final (column, recipient) in [('intention_id', tagFixtureId(1))]) {
          raw.execute(
            'INSERT INTO tag_assignments (tag_id, $column) VALUES (?, ?)',
            [tagFixtureId(number), recipient],
          );
        }
      }
      raw.execute('PRAGMA foreign_keys = OFF');
      for (final (target, column, recipient) in [
        (_intention(1), 'intention_id', tagFixtureId(1)),
      ]) {
        raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
          'некорректный-id',
          'Повреждённый',
        ]);
        raw.execute(
          'INSERT INTO tag_assignments (tag_id, $column) VALUES (?, ?)',
          ['некорректный-id', recipient],
        );
        expect(
          await graph.getTagAssignments(target),
          isA<TagAssignmentsError>().having(
            (error) => error.failure,
            'причина',
            isA<TagAssignmentsCorruptionFailure>(),
          ),
        );
        expect(
          await graph.getTagCatalog(TagCatalogSelectionMode(target)),
          isA<TagCatalogError>().having(
            (error) => error.failure,
            'причина',
            isA<TagCatalogCorruptionFailure>(),
          ),
        );
        raw.execute('DELETE FROM tag_assignments WHERE tag_id = ?', [
          'некорректный-id',
        ]);
        raw.execute('DELETE FROM tags WHERE id = ?', ['некорректный-id']);
        _insertMissingTagReference(raw, column, recipient);
        expect(
          await graph.getTagAssignments(target),
          isA<TagAssignmentsError>().having(
            (error) => error.failure,
            'причина',
            isA<TagAssignmentsCorruptionFailure>(),
          ),
        );
        expect(
          await graph.getTagCatalog(TagCatalogSelectionMode(target)),
          isA<TagCatalogError>().having(
            (error) => error.failure,
            'причина',
            isA<TagCatalogCorruptionFailure>(),
          ),
        );
        raw.execute('DELETE FROM tag_assignments WHERE tag_id = ?', [
          tagFixtureId(999),
        ]);
      }
    },
  );

  test('пустой каталог проверяет существование намерения', () async {
    raw.execute('DELETE FROM tags');
    for (final (target, missing) in [(_intention(1), _intention(999))]) {
      expect(assignments(await graph.getTagAssignments(target)).items, isEmpty);
      expect(
        selection(await graph.getTagCatalog(TagCatalogSelectionMode(target)))
            .rows,
        isEmpty,
      );
      expect(
        await graph.getTagAssignments(missing),
        isA<TagAssignmentsError>().having(
          (error) => error.failure,
          'причина',
          isA<TagAssignmentsIntentionNotFound>(),
        ),
      );
      expect(
        await graph.getTagCatalog(TagCatalogSelectionMode(missing)),
        isA<TagCatalogError>().having(
          (error) => error.failure,
          'причина',
          isA<TagCatalogIntentionNotFound>(),
        ),
      );
    }
  });

  test('осиротевшее назначение не выглядит отсутствующим намерением', () async {
    raw.execute('PRAGMA foreign_keys = OFF');
    raw.execute(
      'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
      [tagFixtureId(firstTagNumber), tagFixtureId(999)],
    );
    final target = _intention(999);
    expect(
      await graph.getTagAssignments(target),
      isA<TagAssignmentsError>().having(
        (error) => error.failure,
        'причина',
        isA<TagAssignmentsCorruptionFailure>(),
      ),
    );
    expect(
      await graph.getTagCatalog(TagCatalogSelectionMode(target)),
      isA<TagCatalogError>().having(
        (error) => error.failure,
        'причина',
        isA<TagCatalogCorruptionFailure>(),
      ),
    );
  });
}
