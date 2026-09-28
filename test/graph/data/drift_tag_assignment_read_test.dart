import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/application/tag_assignments.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_assignment_status.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_target.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/tag_storage_fixture.dart';

IntentionId _intention(int number) =>
    (IntentionId.decode(tagFixtureId(number)) as IntentionIdDecodingSuccess).id;

LongTermRelationId _relation(int number) => (LongTermRelationId.decode(
  tagFixtureId(number),
) as LongTermRelationIdDecodingSuccess).id;

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

  test(
    'точечное чтение различает пару и отсутствие для обоих получателей',
    () async {
      final assignedTag = (TagId.decode(
        tagFixtureId(firstTagNumber),
      ) as TagIdDecodingSuccess).id;
      final freeTag = (TagId.decode(
        tagFixtureId(lastTagNumber),
      ) as TagIdDecodingSuccess).id;
      final missingTag =
          (TagId.decode(tagFixtureId(999)) as TagIdDecodingSuccess).id;
      for (final (assignedTarget, missingTarget) in [
        (
          IntentionTagTarget(_intention(1)),
          IntentionTagTarget(_intention(999)),
        ),
        (
          LongTermRelationTagTarget(_relation(101)),
          LongTermRelationTagTarget(_relation(999)),
        ),
      ]) {
        final assigned = await graph.getTagAssignmentStatus(
          assignedTag,
          assignedTarget,
        );
        final free = await graph.getTagAssignmentStatus(
          freeTag,
          assignedTarget,
        );
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
            isA<TagAssignmentStatusTargetNotFound>(),
          ),
        );
      }
    },
  );

  test(
    'точечное чтение у начала и конца большого каталога использует индексы',
    () async {
      for (var number = 303; number <= 1502; number++) {
        raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
          tagFixtureId(number),
          'Тег $number',
        ]);
        for (final (column, recipient) in [
          ('intention_id', tagFixtureId(1)),
          ('long_term_relation_id', tagFixtureId(101)),
        ]) {
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
        (IntentionTagTarget(_intention(1)), 'intention_id', tagFixtureId(1)),
        (
          LongTermRelationTagTarget(_relation(101)),
          'long_term_relation_id',
          tagFixtureId(101),
        ),
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

  test('полное чтение назначений сохраняет порядок всех 104 тегов обоих получателей', () async {
    for (var number = 303; number <= 405; number++) {
      raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
        tagFixtureId(number),
        'Тег $number',
      ]);
      for (final (column, recipient) in [
        ('intention_id', tagFixtureId(1)),
        ('long_term_relation_id', tagFixtureId(101)),
      ]) {
        raw.execute(
          'INSERT INTO tag_assignments (tag_id, $column) VALUES (?, ?)',
          [tagFixtureId(number), recipient],
        );
      }
    }
    for (final target in [
      IntentionTagTarget(_intention(1)),
      LongTermRelationTagTarget(_relation(101)),
    ]) {
      probe.statements.clear();
      final loaded = assignments(await graph.getTagAssignments(target));
      expect(loaded.target, target);
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
  });

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
        (IntentionTagTarget(_intention(1)), 'intention_id', tagFixtureId(1)),
        (
          LongTermRelationTagTarget(_relation(101)),
          'long_term_relation_id',
          tagFixtureId(101),
        ),
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

  test('выбор помечает только назначения каждого получателя и проверяет его отсутствие', () async {
    for (final (target, missing) in [
      (IntentionTagTarget(_intention(1)), IntentionTagTarget(_intention(999))),
      (
        LongTermRelationTagTarget(_relation(101)),
        LongTermRelationTagTarget(_relation(999)),
      ),
    ]) {
      probe.statements.clear();
      final loaded = selection(
        await graph.getTagCatalog(TagCatalogSelectionMode(target)),
      );
      expect(loaded.target, target);
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
          isA<TagAssignmentsTargetNotFound>(),
        ),
      );
      expect(
        await graph.getTagCatalog(TagCatalogSelectionMode(missing)),
        isA<TagCatalogError>().having(
          (error) => error.failure,
          'причина',
          isA<TagCatalogTargetNotFound>(),
        ),
      );
    }
  });

  test('существующий получатель без назначений даёт пустой снимок', () async {
    for (final (target, column, recipient) in [
      (IntentionTagTarget(_intention(3)), 'intention_id', tagFixtureId(3)),
      (
        LongTermRelationTagTarget(_relation(102)),
        'long_term_relation_id',
        tagFixtureId(102),
      ),
    ]) {
      raw.execute('DELETE FROM tag_assignments WHERE $column = ?', [recipient]);
      probe.statements.clear();
      final loaded = assignments(await graph.getTagAssignments(target));
      expect(loaded.target, target);
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
    for (final target in [
      IntentionTagTarget(_intention(2)),
      LongTermRelationTagTarget(_relation(102)),
    ]) {
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
      for (final (column, recipient) in [
        ('intention_id', tagFixtureId(1)),
        ('long_term_relation_id', tagFixtureId(101)),
      ]) {
        raw.execute(
          'INSERT INTO tag_assignments (tag_id, $column) VALUES (?, ?)',
          [tagFixtureId(number), recipient],
        );
      }
    }
    for (final target in [
      IntentionTagTarget(_intention(1)),
      LongTermRelationTagTarget(_relation(101)),
    ]) {
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
    for (final target in [
      IntentionTagTarget(_intention(1)),
      LongTermRelationTagTarget(_relation(101)),
    ]) {
      final (column, id) = switch (target) {
        IntentionTagTarget() => ('intention_id', tagFixtureId(1)),
        LongTermRelationTagTarget() => (
          'long_term_relation_id',
          tagFixtureId(101),
        ),
      };
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
      for (final target in [
        IntentionTagTarget(_intention(1)),
        LongTermRelationTagTarget(_relation(101)),
      ]) {
        final (column, id) = switch (target) {
          IntentionTagTarget() => ('intention_id', tagFixtureId(1)),
          LongTermRelationTagTarget() => (
            'long_term_relation_id',
            tagFixtureId(101),
          ),
        };
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

  test('полные снимки разных получателей и ревизий не смешиваются', () async {
    final target = IntentionTagTarget(_intention(1));
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
    final relationTarget = LongTermRelationTagTarget(_relation(101));
    final otherTarget = assignments(
      await graph.getTagAssignments(relationTarget),
    );
    expect(otherTarget.target, relationTarget);
    expect(otherTarget.items.map((tag) => tag.id.toCanonicalString()), [
      tagFixtureId(firstTagNumber),
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
        for (final (column, recipient) in [
          ('intention_id', tagFixtureId(1)),
          ('long_term_relation_id', tagFixtureId(101)),
        ]) {
          raw.execute(
            'INSERT INTO tag_assignments (tag_id, $column) VALUES (?, ?)',
            [tagFixtureId(number), recipient],
          );
        }
      }
      raw.execute('PRAGMA foreign_keys = OFF');
      for (final (target, column, recipient) in [
        (IntentionTagTarget(_intention(1)), 'intention_id', tagFixtureId(1)),
        (
          LongTermRelationTagTarget(_relation(101)),
          'long_term_relation_id',
          tagFixtureId(101),
        ),
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

  test(
    'пустой каталог проверяет существование обоих типов получателя',
    () async {
      raw.execute('DELETE FROM tags');
      for (final (target, missing) in [
        (
          IntentionTagTarget(_intention(1)),
          IntentionTagTarget(_intention(999)),
        ),
        (
          LongTermRelationTagTarget(_relation(101)),
          LongTermRelationTagTarget(_relation(999)),
        ),
      ]) {
        expect(
          assignments(await graph.getTagAssignments(target)).items,
          isEmpty,
        );
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
            isA<TagAssignmentsTargetNotFound>(),
          ),
        );
        expect(
          await graph.getTagCatalog(TagCatalogSelectionMode(missing)),
          isA<TagCatalogError>().having(
            (error) => error.failure,
            'причина',
            isA<TagCatalogTargetNotFound>(),
          ),
        );
      }
    },
  );

  test(
    'осиротевшее назначение не выглядит отсутствующим получателем',
    () async {
      raw.execute('PRAGMA foreign_keys = OFF');
      raw.execute(
        'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
        [tagFixtureId(firstTagNumber), tagFixtureId(999)],
      );
      final target = IntentionTagTarget(_intention(999));
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
    },
  );
}
