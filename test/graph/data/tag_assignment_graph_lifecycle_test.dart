import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/application/tagged_intentions_page.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/tag_storage_fixture.dart';

IntentionId _intention(int number) =>
    (IntentionId.decode(tagFixtureId(number)) as IntentionIdDecodingSuccess).id;

LongTermRelationId _relation(int number) => (LongTermRelationId.decode(
  tagFixtureId(number),
) as LongTermRelationIdDecodingSuccess).id;

TagId _tag(int number) =>
    (TagId.decode(tagFixtureId(number)) as TagIdDecodingSuccess).id;

void main() {
  late AppDatabase database;
  late sqlite.Database raw;
  late DriftPersonalGraphRepository repository;
  late DateTime now;

  setUp(() async {
    database = AppDatabase(openInMemoryLocalDatabase(setup: (db) => raw = db));
    await database.open();
    seedTagStorageFixture(raw);
    now = DateTime.utc(2026, 9, 25, 12);
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => now,
      InMemoryDiagnosticsSink(),
    );
  });
  tearDown(() => database.close());

  Map<String, Object?> row(String table, int id) => Map.of(
    raw.select('SELECT * FROM $table WHERE id = ?', [tagFixtureId(id)]).single,
  );

  List<List<Object?>> rows(String table) => raw
      .select('SELECT * FROM $table ORDER BY rowid')
      .map((entry) => entry.values.toList())
      .toList();

  List<List<Object?>> assignments() => rows('tag_assignments');

  List<Object?> assignedTags(int id) => raw
      .select(
        'SELECT tag_id FROM tag_assignments WHERE intention_id = ? ORDER BY creation_sequence',
        [tagFixtureId(id)],
      )
      .map((entry) => entry['tag_id'])
      .toList();

  Future<void> expectNavigation(
    int tag,
    TaggedIntentionsScope scope,
    List<int> intentions,
  ) async {
    final result = await repository.getTaggedIntentionsPage(
      TaggedIntentionsQuery(tagId: _tag(tag), scope: scope),
    );
    expect(result, isA<TaggedIntentionsPageSuccess>());
    final page = (result as TaggedIntentionsPageSuccess).value;
    expect(page.items.map((item) => item.id), intentions.map(_intention));
    expect(page.nextCursor, isNull);
  }

  Map<String, List<List<Object?>>> graph() => {
    for (final table in [
      'intentions',
      'long_term_relations',
      'daily_choices',
      'daily_choice_path_steps',
      'tags',
      'tag_assignments',
    ])
      table: rows(table),
  };

  test(
    'правки намерения, каскад архива и восстановление сохраняют назначения',
    () async {
      raw.execute(
        'INSERT INTO long_term_relations (id, source_intention_id, related_intention_id, type, priority) VALUES (?, ?, ?, ?, ?)',
        [tagFixtureId(103), tagFixtureId(3), tagFixtureId(1), 'can', 3],
      );
      final intentionBeforeAssignments = row('intentions', 1);
      expect(
        await repository.execute(
          AssignTag(tagId: _tag(lastTagNumber), intentionId: _intention(1)),
        ),
        isA<TagCommandSucceeded>(),
      );
      expect(row('intentions', 1), intentionBeforeAssignments);

      final originalAssignments = assignments();
      expect(originalAssignments, hasLength(4));
      expect(assignedTags(1), [
        tagFixtureId(firstTagNumber),
        tagFixtureId(lastTagNumber),
      ]);
      expect(assignedTags(2), [tagFixtureId(firstTagNumber)]);
      expect(assignedTags(3), [tagFixtureId(lastTagNumber)]);
      final otherIntentions = [row('intentions', 2), row('intentions', 3)];
      final alreadyArchivedRelation = row('long_term_relations', 102);
      final dailyChoices = rows('daily_choices');
      final pathSteps = rows('daily_choice_path_steps');
      final tags = rows('tags');
      final createdAt = row('intentions', 1)['created_at'];
      final activeDirectRelations = [
        row('long_term_relations', 101),
        row('long_term_relations', 103),
      ];

      Future<void> expectStep(
        IntentionCommand command, {
        required int minute,
        required String title,
        required String description,
        required int readiness,
        required int archived,
        required int directRelationArchive,
      }) async {
        now = DateTime.utc(2026, 9, 25, 12, minute);
        expect(await repository.execute(command), isA<GraphCommandSucceeded>());
        final intention = row('intentions', 1);
        expect(intention['title'], title);
        expect(intention['description'], description);
        expect(intention['is_action_ready'], readiness);
        expect(intention['is_archived'], archived);
        expect(intention['created_at'], createdAt);
        expect(intention['updated_at'], now.microsecondsSinceEpoch);
        expect(row('long_term_relations', 101), {
          ...activeDirectRelations[0],
          'is_archived': directRelationArchive,
        });
        expect(row('long_term_relations', 103), {
          ...activeDirectRelations[1],
          'is_archived': directRelationArchive,
        });
        expect(row('long_term_relations', 102), alreadyArchivedRelation);
        expect([row('intentions', 2), row('intentions', 3)], otherIntentions);
        expect(assignments(), originalAssignments);
        expect(rows('tags'), tags);
        expect(rows('daily_choices'), dailyChoices);
        expect(rows('daily_choice_path_steps'), pathSteps);
        await expectNavigation(
          firstTagNumber,
          TaggedIntentionsScope.active,
          archived == 0 ? [1] : [],
        );
        await expectNavigation(
          firstTagNumber,
          TaggedIntentionsScope.archived,
          archived == 0 ? [2] : [1, 2],
        );
        await expectNavigation(
          lastTagNumber,
          TaggedIntentionsScope.active,
          archived == 0 ? [3, 1] : [3],
        );
        await expectNavigation(
          lastTagNumber,
          TaggedIntentionsScope.archived,
          archived == 0 ? [] : [1],
        );
        expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
      }

      await expectStep(
        UpdateIntention(
          id: _intention(1),
          title: 'Новое название',
          description: 'Описание 1',
        ),
        minute: 1,
        title: 'Новое название',
        description: 'Описание 1',
        readiness: 1,
        archived: 0,
        directRelationArchive: 0,
      );
      await expectStep(
        UpdateIntention(
          id: _intention(1),
          title: 'Новое название',
          description: 'Новое описание',
        ),
        minute: 2,
        title: 'Новое название',
        description: 'Новое описание',
        readiness: 1,
        archived: 0,
        directRelationArchive: 0,
      );
      await expectStep(
        DisableIntentionReadiness(_intention(1)),
        minute: 3,
        title: 'Новое название',
        description: 'Новое описание',
        readiness: 0,
        archived: 0,
        directRelationArchive: 0,
      );
      await expectStep(
        ArchiveIntention(_intention(1)),
        minute: 4,
        title: 'Новое название',
        description: 'Новое описание',
        readiness: 0,
        archived: 1,
        directRelationArchive: 1,
      );
      await expectStep(
        RestoreIntention(_intention(1)),
        minute: 5,
        title: 'Новое название',
        description: 'Новое описание',
        readiness: 0,
        archived: 0,
        directRelationArchive: 1,
      );

      final beforeUnchangedAndRejected = graph();
      now = DateTime.utc(2026, 9, 25, 12, 6);
      expect(
        await repository.execute(
          UpdateIntention(
            id: _intention(1),
            title: 'Новое название',
            description: 'Новое описание',
          ),
        ),
        isA<GraphCommandSucceeded>(),
      );
      expect(graph(), beforeUnchangedAndRejected);
      expect(
        await repository.execute(
          UpdateIntention(id: _intention(1), title: '  ', description: 'Отказ'),
        ),
        isA<GraphCommandFailed>(),
      );
      expect(graph(), beforeUnchangedAndRejected);
    },
  );

  test(
    'правки участников, типа и архива связи сохраняют назначения намерениям',
    () async {
      for (final number in [4, 5]) {
        raw.execute(
          'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, 0, 0, 100, 200)',
          [tagFixtureId(number), 'Намерение $number'],
        );
      }
      raw.execute(
        'INSERT INTO long_term_relations (id, source_intention_id, related_intention_id, type, priority, description) VALUES (?, ?, ?, ?, ?, ?)',
        [
          tagFixtureId(103),
          tagFixtureId(3),
          tagFixtureId(4),
          'need',
          2,
          'Прежнее',
        ],
      );
      for (final (tag, intention) in [
        (firstTagNumber, 3),
        (firstTagNumber, 4),
        (lastTagNumber, 4),
        (lastTagNumber, 5),
      ]) {
        expect(
          await repository.execute(
            AssignTag(tagId: _tag(tag), intentionId: _intention(intention)),
          ),
          isA<TagCommandSucceeded>(),
        );
      }

      final originalAssignments = assignments();
      expect(assignedTags(4), [
        tagFixtureId(firstTagNumber),
        tagFixtureId(lastTagNumber),
      ]);
      final intentions = rows('intentions');
      final otherRelations = [
        row('long_term_relations', 101),
        row('long_term_relations', 102),
      ];
      final dailyChoices = rows('daily_choices');
      final pathSteps = rows('daily_choice_path_steps');
      final tags = rows('tags');

      Future<void> expectRelationStep(
        LongTermRelationCommand command,
        Map<String, Object?> expectedChange,
      ) async {
        final before = row('long_term_relations', 103);
        expect(await repository.execute(command), isA<GraphCommandSucceeded>());
        expect(row('long_term_relations', 103), {...before, ...expectedChange});
        expect(assignments(), originalAssignments);
        expect(rows('intentions'), intentions);
        expect([
          row('long_term_relations', 101),
          row('long_term_relations', 102),
        ], otherRelations);
        expect(rows('daily_choices'), dailyChoices);
        expect(rows('daily_choice_path_steps'), pathSteps);
        expect(rows('tags'), tags);
        expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
      }

      await expectRelationStep(
        UpdateLongTermRelation(
          relationId: _relation(103),
          patch: const LongTermRelationPatch(
            type: LongTermRelationFieldSet(LongTermRelationType.can),
          ),
        ),
        {'type': 'can'},
      );
      await expectRelationStep(
        UpdateLongTermRelation(
          relationId: _relation(103),
          patch: LongTermRelationPatch(
            sourceIntentionId: LongTermRelationFieldSet(_intention(1)),
          ),
        ),
        {'source_intention_id': tagFixtureId(1)},
      );
      await expectRelationStep(
        UpdateLongTermRelation(
          relationId: _relation(103),
          patch: LongTermRelationPatch(
            relatedIntentionId: LongTermRelationFieldSet(_intention(5)),
          ),
        ),
        {'related_intention_id': tagFixtureId(5)},
      );
      await expectRelationStep(
        UpdateLongTermRelation(
          relationId: _relation(103),
          patch: LongTermRelationPatch(
            description: LongTermRelationDescriptionPatch.fromInput(
              'Новое описание',
            ),
          ),
        ),
        {'description': 'Новое описание'},
      );
      await expectRelationStep(
        UpdateLongTermRelation(
          relationId: _relation(103),
          patch: const LongTermRelationPatch(
            priority: LongTermRelationFieldSet(RelationPriority.p4),
          ),
        ),
        {'priority': 4},
      );
      await expectRelationStep(ArchiveLongTermRelation(_relation(103)), {
        'is_archived': 1,
      });
      await expectRelationStep(RestoreLongTermRelation(_relation(103)), {
        'is_archived': 0,
      });
    },
  );

  test(
    'теги участников дневного пути меняются без обхода защиты смысла связи',
    () async {
      raw.execute(
        'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, 0, 0, 100, 200)',
        [tagFixtureId(4), 'Новое намерение'],
      );
      final relationBefore = row('long_term_relations', 101);
      final intentionsBefore = rows('intentions');
      final choicesBefore = rows('daily_choices');
      final pathBefore = rows('daily_choice_path_steps');

      expect(
        await repository.execute(
          AssignTag(tagId: _tag(lastTagNumber), intentionId: _intention(1)),
        ),
        isA<TagCommandSucceeded>(),
      );
      expect(
        await repository.execute(
          RemoveTagAssignment(
            tagId: _tag(firstTagNumber),
            intentionId: _intention(1),
          ),
        ),
        isA<TagCommandSucceeded>(),
      );
      expect(row('long_term_relations', 101), relationBefore);
      expect(rows('intentions'), intentionsBefore);
      expect(rows('daily_choices'), choicesBefore);
      expect(rows('daily_choice_path_steps'), pathBefore);
      expect(assignedTags(1), [tagFixtureId(lastTagNumber)]);

      final beforeRejectedEdits = graph();
      for (final patch in [
        const LongTermRelationPatch(
          type: LongTermRelationFieldSet(LongTermRelationType.can),
          priority: LongTermRelationFieldSet(RelationPriority.p4),
        ),
        LongTermRelationPatch(
          sourceIntentionId: LongTermRelationFieldSet(_intention(4)),
        ),
        LongTermRelationPatch(
          relatedIntentionId: LongTermRelationFieldSet(_intention(4)),
        ),
      ]) {
        final result = await repository.execute(
          UpdateLongTermRelation(relationId: _relation(101), patch: patch),
        );
        expect(result, isA<GraphCommandFailed>());
        expect(
          (result as GraphCommandFailed).failure,
          isA<LongTermRelationReferencedByDailyPathFailure>(),
        );
        expect(graph(), beforeRejectedEdits);
      }

      expect(
        await repository.execute(
          UpdateLongTermRelation(
            relationId: _relation(101),
            patch: LongTermRelationPatch(
              priority: const LongTermRelationFieldSet(RelationPriority.p4),
              description: LongTermRelationDescriptionPatch.fromInput(
                'Обновлено',
              ),
            ),
          ),
        ),
        isA<GraphCommandSucceeded>(),
      );
      expect(row('long_term_relations', 101), {
        ...relationBefore,
        'priority': 4,
        'description': 'Обновлено',
      });
      expect(assignments(), beforeRejectedEdits['tag_assignments']);
      expect(rows('daily_choices'), choicesBefore);
      expect(rows('daily_choice_path_steps'), pathBefore);
    },
  );
}
