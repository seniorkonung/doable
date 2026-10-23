import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/tag/application/tag_assignments.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag_color.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/graph_seed.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/tag_storage_fixture.dart';
import '../../support/tag_positions.dart';

IntentionId _intention(int number) =>
    (IntentionId.decode(tagFixtureId(number)) as IntentionIdDecodingSuccess).id;

void main() {
  late AppDatabase database;
  late sqlite.Database raw;
  late DriftPersonalGraphRepository graph;
  late InMemoryDiagnosticsSink diagnostics;

  setUp(() async {
    diagnostics = InMemoryDiagnosticsSink();
    database = AppDatabase(openInMemoryLocalDatabase(setup: (db) => raw = db));
    await database.open();
    seedTagStorageFixture(raw);
    graph = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 27),
      diagnostics,
    );
  });
  tearDown(() => database.close());

  TagAssignmentsSnapshot assignments(TagAssignmentsResult result) =>
      (result as TagAssignmentsSuccess).value;

  TagSelectionSnapshot selection(TagCatalogResult result) =>
      (result as TagCatalogSuccess).value as TagSelectionSnapshot;

  test(
    'полное чтение назначений даёт все 104 тега намерения в ручном порядке',
    () async {
      seedRawGraph(raw, () {
        // Места новых тегов обратны порядку их создания и назначения.
        for (var number = 303; number <= 405; number++) {
          raw.execute(
            'INSERT INTO tags (id, name, position) VALUES (?, ?, ?)',
            [
              tagFixtureId(number),
              'Тег $number',
              tagPositionKey(1000 - number),
            ],
          );
          for (final (column, recipient) in [
            ('intention_id', tagFixtureId(1)),
          ]) {
            raw.execute(
              'INSERT INTO tag_assignments (tag_id, $column) VALUES (?, ?)',
              [tagFixtureId(number), recipient],
            );
          }
        }
      });
      for (final target in [_intention(1)]) {
        final loaded = assignments(await graph.getTagAssignments(target));
        expect(loaded.intentionId, target);
        expect(loaded.items.map((tag) => tag.name.value), [
          'Дом',
          for (var number = 405; number >= 303; number--) 'Тег $number',
        ]);
        expect(loaded.items.map((tag) => tag.id.toCanonicalString()), [
          tagFixtureId(firstTagNumber),
          for (var number = 405; number >= 303; number--) tagFixtureId(number),
        ]);
      }
    },
  );

  test('назначения другим намерениям и идентичность связи не становятся назначениями намерения', () async {
    seedRawGraph(raw, () {
      raw.execute('INSERT INTO tags (id, name, position) VALUES (?, ?, ?)', [
        tagFixtureId(303),
        'Только другим намерениям',
        tagPositionKey(303),
      ]);
      for (final number in [1, 3]) {
        raw.execute(
          'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
          [tagFixtureId(303), tagFixtureId(number)],
        );
      }
    });
    final oldAssignments = raw.select('SELECT * FROM tag_assignments');
    final loaded = selection(
      await graph.getTagCatalog(TagCatalogSelectionMode(_intention(2))),
    );
    expect(loaded.rows.map((row) => row.isAssigned), [true, false, false]);
    expect(loaded.items.map((tag) => tag.name.value), [
      'Дом',
      'Работа',
      'Только другим намерениям',
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

    seedRawGraph(raw, () {
      raw.execute(
        'INSERT INTO intentions (id, title, created_at, updated_at) VALUES (?, ?, ?, ?)',
        [tagFixtureId(101), 'Отдельное намерение', 1, 1],
      );
    });
    final empty = assignments(await graph.getTagAssignments(_intention(101)));
    expect(empty.items, isEmpty);
    final unassigned = selection(
      await graph.getTagCatalog(TagCatalogSelectionMode(_intention(101))),
    );
    expect(unassigned.items, hasLength(3));
    expect(unassigned.rows.map((row) => row.isAssigned), [false, false, false]);
    expect(raw.select('SELECT * FROM tag_assignments'), oldAssignments);
  });

  test('неизменяемые снимки сохраняют порядок тегов, их цвет и общую '
      'ревизию', () async {
    final intentionId = _intention(1);
    final tagId =
        (TagId.decode(tagFixtureId(firstTagNumber)) as TagIdDecodingSuccess).id;
    seedRawGraph(raw, () {
      raw.execute("UPDATE tags SET color = 'blue' WHERE id = ?", [
        tagFixtureId(firstTagNumber),
      ]);
    });
    final before = assignments(await graph.getTagAssignments(intentionId));
    final catalog = selection(
      await graph.getTagCatalog(TagCatalogSelectionMode(intentionId)),
    );
    expect(
      catalog.revision.compareTo(before.revision),
      GraphRevisionOrder.same,
    );
    expect(() => before.items.clear(), throwsUnsupportedError);
    expect(() => catalog.items.clear(), throwsUnsupportedError);
    expect(() => catalog.rows.clear(), throwsUnsupportedError);

    final renamed = await graph.execute(
      UpdateTag(
        tagId: tagId,
        name: TagName.fromInput('Я'),
        color: TagColor.blue,
      ),
    );
    final outcome = (renamed as TagCommandSucceeded).value.value as TagUpdated;
    expect(
      [outcome.before.color, outcome.after.color],
      [TagColor.blue, TagColor.blue],
    );
    final after = assignments(await graph.getTagAssignments(intentionId));
    final renamedCatalog = selection(
      await graph.getTagCatalog(TagCatalogSelectionMode(intentionId)),
    );
    expect(after.items.map((tag) => tag.name.value), ['Я']);
    expect(after.items.map((tag) => tag.color), [TagColor.blue]);
    expect(renamedCatalog.items.map((tag) => tag.name.value), ['Я', 'Работа']);
    expect(renamedCatalog.items.map((tag) => tag.color), [TagColor.blue, null]);
    expect(after.revision.compareTo(before.revision), GraphRevisionOrder.newer);
    expect(
      renamedCatalog.revision.compareTo(after.revision),
      GraphRevisionOrder.same,
    );
    expect(before.items.single.name.value, 'Дом');
    expect(before.items.single.color, TagColor.blue);
    expect(catalog.items.first.name.value, 'Дом');
    expect(catalog.rows.map((row) => row.tag.color), [TagColor.blue, null]);
  });

  test(
    'порядок тегов намерения не зависит от очерёдности назначения и создания',
    () async {
      final recipientId = tagFixtureId(1);
      seedRawGraph(raw, () {
        // «Спорт» создан последним, но стоит в ручном порядке первым.
        raw.execute('INSERT INTO tags (id, name, position) VALUES (?, ?, ?)', [
          tagFixtureId(303),
          'Спорт',
          tagPositionKey(1),
        ]);
        raw.execute(
          'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
          [tagFixtureId(lastTagNumber), recipientId],
        );
        raw.execute(
          'DELETE FROM tag_assignments WHERE tag_id = ? AND intention_id = ?',
          [tagFixtureId(firstTagNumber), recipientId],
        );
        raw.execute(
          'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
          [tagFixtureId(firstTagNumber), recipientId],
        );
        raw.execute(
          'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
          [tagFixtureId(303), recipientId],
        );
      });
      final loaded = assignments(await graph.getTagAssignments(_intention(1)));
      expect(loaded.items.map((tag) => tag.name.value), [
        'Спорт',
        'Дом',
        'Работа',
      ]);
    },
  );

  test(
    'выбор помечает только назначения намерения и проверяет его отсутствие',
    () async {
      for (final (target, missing) in [(_intention(1), _intention(999))]) {
        final loaded = selection(
          await graph.getTagCatalog(TagCatalogSelectionMode(target)),
        );
        expect(loaded.intentionId, target);
        expect(loaded.rows.map((row) => row.tag.id.toCanonicalString()), [
          tagFixtureId(firstTagNumber),
          tagFixtureId(lastTagNumber),
        ]);
        expect(loaded.rows.map((row) => row.isAssigned), [true, false]);
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
      seedRawGraph(raw, () {
        raw.execute('DELETE FROM tag_assignments WHERE $column = ?', [
          recipient,
        ]);
      });
      final loaded = assignments(await graph.getTagAssignments(target));
      expect(loaded.intentionId, target);
      expect(loaded.items, isEmpty);
    }
  });

  test('каталог выбора возвращает все 105 тегов без пропусков', () async {
    seedRawGraph(raw, () {
      for (var number = 303; number <= 405; number++) {
        // Места новых тегов обратны порядку их создания.
        raw.execute('INSERT INTO tags (id, name, position) VALUES (?, ?, ?)', [
          tagFixtureId(number),
          'Тег $number',
          tagPositionKey(1000 - number),
        ]);
      }
    });
    for (final target in [_intention(2)]) {
      final loaded = selection(
        await graph.getTagCatalog(TagCatalogSelectionMode(target)),
      );
      expect(loaded.rows.map((row) => row.tag.name.value), [
        'Дом',
        'Работа',
        for (var number = 405; number >= 303; number--) 'Тег $number',
      ]);
      expect(loaded.rows.map((row) => row.tag.id.toCanonicalString()), [
        tagFixtureId(firstTagNumber),
        tagFixtureId(lastTagNumber),
        for (var number = 405; number >= 303; number--) tagFixtureId(number),
      ]);
      expect(loaded.rows.map((row) => row.isAssigned), [
        true,
        for (var n = 0; n < 104; n++) false,
      ]);
    }
  });

  test('полные снимки разных намерений и ревизий не смешиваются', () async {
    final target = _intention(1);
    seedRawGraph(raw, () {
      raw.execute(
        'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
        [tagFixtureId(lastTagNumber), tagFixtureId(1)],
      );
    });
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

  test('повреждение строки после сотой отклоняет снимок', () async {
    final target = _intention(1);
    seedRawGraph(raw, () {
      for (var number = 303; number <= 439; number++) {
        raw.execute('INSERT INTO tags (id, name, position) VALUES (?, ?, ?)', [
          tagFixtureId(number),
          'Тег $number',
          tagPositionKey(number),
        ]);
        raw.execute(
          'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
          [tagFixtureId(number), tagFixtureId(1)],
        );
      }
      // Формат идентификатора тега схема не проверяет.
      raw.execute('INSERT INTO tags (id, name, position) VALUES (?, ?, ?)', [
        'некорректный-id',
        'Повреждённый',
        tagPositionKey(200000),
      ]);
      raw.execute(
        'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
        ['некорректный-id', tagFixtureId(1)],
      );
    });
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

  test('пустой каталог проверяет существование намерения', () async {
    seedRawGraph(raw, () {
      raw.execute('DELETE FROM tags');
    });
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
}
