import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/data/local/app_database.dart' hide Intention;
import 'package:doable/src/graph/application/delete_blocking_relations.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_description.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/daily_choice_durability_fixture.dart';
import '../../support/favorite_storage_fixture.dart';
import '../../support/in_memory_diagnostics_sink.dart';

/// Тег фикстуры, назначенный намерениям 1 и 3.
const _homeTag = 301;

/// Тег фикстуры, назначенный намерению 4.
const _workTag = 302;

/// Отметки фикстуры в порядке мест: места идут с пропусками и не совпадают
/// ни с порядком идентификаторов, ни с порядком создания намерений.
final _seededMarks = [
  (durabilityUuid(2), 2),
  (durabilityUuid(1), 5),
  (durabilityUuid(7), 7),
  (durabilityUuid(8), 9),
];

TagId _tag(int number) =>
    (TagId.decode(durabilityUuid(number)) as TagIdDecodingSuccess).id;

void main() {
  late AppDatabase database;
  late sqlite.Database raw;
  late DateTime now;
  late DriftPersonalGraphRepository repository;

  /// Намерения 1–5 соединены долговременными связями 101–104. Намерение 6 —
  /// одноимённое с избранным намерением 2 и без отметки; 7 и архивированное
  /// 8 — избранные без блокирующих связей.
  setUp(() async {
    database = AppDatabase(openInMemoryLocalDatabase(setup: (db) => raw = db));
    await database.open();
    await seedDurabilityGraph(database);
    for (final (number, title, archived) in [
      (6, 'Намерение 2', 0),
      (7, 'Свободное', 0),
      (8, 'Свободное в архиве', 1),
    ]) {
      raw.execute(
        'INSERT INTO intentions (id, title, is_action_ready, is_archived, '
        'created_at, updated_at) VALUES (?, ?, 0, ?, 1, 1)',
        [durabilityUuid(number), title, archived],
      );
    }
    for (final (number, name) in [(_homeTag, 'Дом'), (_workTag, 'Работа')]) {
      raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
        durabilityUuid(number),
        name,
      ]);
    }
    for (final (tag, intention) in [
      (_homeTag, 1),
      (_homeTag, 3),
      (_workTag, 4),
    ]) {
      raw.execute(
        'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
        [durabilityUuid(tag), durabilityUuid(intention)],
      );
    }
    for (final (intentionId, position) in _seededMarks) {
      storeFavoriteMark(raw, intentionId: intentionId, position: position);
    }
    now = DateTime.utc(2026, 10, 2, 12);
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => now,
      InMemoryDiagnosticsSink(),
      dailyChoiceIdGenerator: FixedChoiceIds(durabilityChoice(201)),
      choicePathStepIdGenerator: SequentialStepIds(301),
    );
  });

  tearDown(() => database.close());

  List<List<Object?>> rows(String table) => raw
      .select('SELECT * FROM $table ORDER BY rowid')
      .map((row) => row.values.toList())
      .toList();

  /// Строки таблиц графа, которые отметка и её снятие не меняют.
  Map<String, List<List<Object?>>> graphWithoutMarks() => {
    for (final table in [
      'intentions',
      'intention_titles_fts',
      'long_term_relations',
      'daily_choices',
      'daily_choice_path_steps',
      'tags',
      'tag_assignments',
    ])
      table: rows(table),
  };

  Map<String, Object?> intentionRow(int number) => Map.of(
    raw.select('SELECT * FROM intentions WHERE id = ?', [
      durabilityUuid(number),
    ]).single,
  );

  Map<String, Object?> relationRow(int number) => Map.of(
    raw.select('SELECT * FROM long_term_relations WHERE id = ?', [
      durabilityUuid(number),
    ]).single,
  );

  Future<GraphRevision> revision() async => (await repository.getRelationCounts(
    durabilityIntention(1),
  ) as ResultSuccess<GraphSnapshot<RelationCounts>>).value.revision;

  Future<FavoriteMark> detailsMark(IntentionId id) async =>
      ((await repository.watchIntention(id).first)
              as ResultSuccess<GraphSnapshot<IntentionDetails?>>)
          .value
          .value!
          .favoriteMark;

  Future<IntentionCommandSuccess> intentionSucceeded(
    IntentionCommand command,
  ) async {
    final result = await repository.execute(command);
    expect(
      result,
      isA<ResultSuccess<ConfirmedGraphResult<IntentionCommandSuccess>>>(),
    );
    return (result
            as ResultSuccess<ConfirmedGraphResult<IntentionCommandSuccess>>)
        .value
        .value;
  }

  /// Каталожные снимки команды несут сохранённую отметку каждого намерения.
  void expectSnapshotsCarryStoredMarks(IntentionCommandSuccess success) {
    final favorites = {for (final (id, _) in storedFavoriteMarks(raw)) id};
    for (final mutation in success.catalogMutations) {
      for (final snapshot in [mutation.before, mutation.after].nonNulls) {
        expect(
          snapshot.summary.favoriteMark,
          favorites.contains(snapshot.summary.id.toCanonicalString())
              ? FavoriteMark.favorite
              : FavoriteMark.notFavorite,
        );
      }
    }
  }

  group('Команды графа сохраняют отметки и места', () {
    test('новое намерение создаётся без отметки, в том числе одноимённое с '
        'избранным', () async {
      final success = await intentionSucceeded(
        const CreateIntention(title: 'Намерение 2', description: null),
      );

      final created = (success as IntentionSaved).intention.id;
      expect(storedFavoriteMarks(raw), _seededMarks);
      expect(
        success.catalogMutation.after!.summary.favoriteMark,
        FavoriteMark.notFavorite,
      );
      expect(await detailsMark(created), FavoriteMark.notFavorite);
      expect(await detailsMark(durabilityIntention(2)), FavoriteMark.favorite);
    });

    test('изменение названия, описания и готовности, архивирование с '
        'каскадом связей и восстановление сохраняют отметку и место и '
        'обновляют время изменения', () async {
      final createdAt = intentionRow(1)['created_at'];
      final neighborsBefore = [
        for (final n in [2, 4, 5, 6]) intentionRow(n),
      ];
      var minute = 0;

      Future<void> expectStep(
        IntentionCommand command,
        Map<String, Object?> expectedChange, {
        required int directRelationArchive,
      }) async {
        now = DateTime.utc(2026, 10, 2, 12, ++minute);
        final before = intentionRow(1);

        final success = await intentionSucceeded(command);

        expect(intentionRow(1), {
          ...before,
          ...expectedChange,
          'updated_at': now.microsecondsSinceEpoch,
        });
        expect(intentionRow(1)['created_at'], createdAt);
        final mutation = success.catalogMutation as IntentionCatalogUpdated;
        expect(mutation.before.summary.favoriteMark, FavoriteMark.favorite);
        expect(mutation.after.summary.favoriteMark, FavoriteMark.favorite);
        expectSnapshotsCarryStoredMarks(success);
        expect(storedFavoriteMarks(raw), _seededMarks);
        for (final relation in [101, 103, 104]) {
          expect(relationRow(relation)['is_archived'], directRelationArchive);
        }
        // Соседи каскада и одноимённое намерение не меняются сами и не
        // получают отметку.
        expect([
          for (final n in [2, 4, 5, 6]) intentionRow(n),
        ], neighborsBefore);
        expect(
          await detailsMark(durabilityIntention(1)),
          FavoriteMark.favorite,
        );
        expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
      }

      await expectStep(
        UpdateIntention(
          id: durabilityIntention(1),
          title: 'Намерение 2',
          description: null,
        ),
        {'title': 'Намерение 2', 'title_search_key': 'намерение 2'},
        directRelationArchive: 0,
      );
      await expectStep(
        UpdateIntention(
          id: durabilityIntention(1),
          title: 'Намерение 2',
          description: 'Новое описание',
        ),
        {'description': 'Новое описание'},
        directRelationArchive: 0,
      );
      await expectStep(EnableIntentionReadiness(durabilityIntention(1)), {
        'is_action_ready': 1,
      }, directRelationArchive: 0);
      await expectStep(DisableIntentionReadiness(durabilityIntention(1)), {
        'is_action_ready': 0,
      }, directRelationArchive: 0);
      await expectStep(ArchiveIntention(durabilityIntention(1)), {
        'is_archived': 1,
      }, directRelationArchive: 1);
      await expectStep(RestoreIntention(durabilityIntention(1)), {
        'is_archived': 0,
      }, directRelationArchive: 1);
    });

    test('изменения неизбранного намерения не ставят отметку', () async {
      for (final command in [
        UpdateIntention(
          id: durabilityIntention(6),
          title: 'Намерение 2',
          description: 'Одноимённое с избранным',
        ),
        EnableIntentionReadiness(durabilityIntention(6)),
        DisableIntentionReadiness(durabilityIntention(4)),
        ArchiveIntention(durabilityIntention(4)),
        RestoreIntention(durabilityIntention(4)),
      ]) {
        final success = await intentionSucceeded(command);

        expect(success.catalogMutation, isA<IntentionCatalogUpdated>());
        expectSnapshotsCarryStoredMarks(success);
        expect(storedFavoriteMarks(raw), _seededMarks);
      }
      expect(
        await detailsMark(durabilityIntention(4)),
        FavoriteMark.notFavorite,
      );
      expect(
        await detailsMark(durabilityIntention(6)),
        FavoriteMark.notFavorite,
      );
    });

    test('назначение и снятие тегов, переименование и удаление тега '
        'сохраняют отметки и места', () async {
      final created = await repository.execute(
        CreateTag(TagName.fromInput('Отдых')),
      );
      final newTag =
          ((created as TagCommandSucceeded).value.value as TagCreated).tag.id;

      for (final command in <TagCommand>[
        AssignTag(tagId: newTag, intentionId: durabilityIntention(2)),
        AssignTag(tagId: newTag, intentionId: durabilityIntention(6)),
        AssignTag(tagId: _tag(_workTag), intentionId: durabilityIntention(8)),
        RemoveTagAssignment(
          tagId: _tag(_homeTag),
          intentionId: durabilityIntention(1),
        ),
        RemoveTagAssignment(
          tagId: _tag(_workTag),
          intentionId: durabilityIntention(4),
        ),
        RenameTag(tagId: _tag(_homeTag), name: TagName.fromInput('Быт')),
        DeleteTag(newTag),
      ]) {
        expect(await repository.execute(command), isA<TagCommandSucceeded>());
        expect(storedFavoriteMarks(raw), _seededMarks);
      }
      expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
    });

    test('создание, изменение, архивирование, восстановление и удаление '
        'связей сохраняют отметки и места', () async {
      final created = await repository.execute(
        CreateLongTermRelation(
          sourceIntentionId: durabilityIntention(7),
          relatedIntentionId: durabilityIntention(6),
          type: LongTermRelationType.need,
          priority: RelationPriority.p2,
          description: LongTermRelationDescription.fromInput('Описание'),
        ),
      );
      final relation =
          ((created as GraphCommandSucceeded).value.value
                  as LongTermRelationCreated)
              .relation
              .id;
      expect(storedFavoriteMarks(raw), _seededMarks);

      for (final command in <GraphCommand>[
        UpdateLongTermRelation(
          relationId: relation,
          patch: LongTermRelationPatch(
            type: const LongTermRelationFieldSet(LongTermRelationType.can),
            priority: const LongTermRelationFieldSet(RelationPriority.p4),
            relatedIntentionId: LongTermRelationFieldSet(
              durabilityIntention(2),
            ),
          ),
        ),
        ArchiveLongTermRelation(relation),
        RestoreLongTermRelation(relation),
        DeleteLongTermRelation(relation),
        DeleteBlockingRelations.longTerm(
          intentionId: durabilityIntention(1),
          relationIds: [durabilityRelation(104)],
        ),
      ]) {
        expect(await repository.execute(command), isA<GraphResultSuccess>());
        expect(storedFavoriteMarks(raw), _seededMarks);
      }
      expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
    });

    test('создание, изменение, замена пути и удаление дневного выбора '
        'сохраняют отметки и места', () async {
      for (final command in <GraphCommand>[
        durabilityCreate(),
        durabilityUpdate(201),
        durabilityReplace(201),
        DeleteDailyChoice(durabilityChoice(201)),
      ]) {
        expect(await repository.execute(command), isA<GraphResultSuccess>());
        expect(storedFavoriteMarks(raw), _seededMarks);
      }
      expect(rows('daily_choices'), isEmpty);
      expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
    });
  });

  group('Физическое удаление намерения', () {
    test('удаляет активное и архивированное избранное намерение вместе с '
        'отметкой и сохраняет места остальных', () async {
      final relationsBefore = rows('long_term_relations');
      final assignmentsBefore = rows('tag_assignments');
      final revisionBefore = await revision();

      final active = await intentionSucceeded(
        DeleteIntention(durabilityIntention(7)),
      );

      expect(active, isA<IntentionDeleted>());
      expect(
        active.catalogMutation.before!.summary.favoriteMark,
        FavoriteMark.favorite,
      );
      expect(
        raw.select('SELECT id FROM intentions WHERE id = ?', [
          durabilityUuid(7),
        ]),
        isEmpty,
      );
      expect(storedFavoriteMarks(raw), [
        (durabilityUuid(2), 2),
        (durabilityUuid(1), 5),
        (durabilityUuid(8), 9),
      ]);
      expect(
        (await revision()).compareTo(revisionBefore),
        GraphRevisionOrder.newer,
      );

      final archived = await intentionSucceeded(
        DeleteIntention(durabilityIntention(8)),
      );

      expect(archived, isA<IntentionDeleted>());
      expect(storedFavoriteMarks(raw), [
        (durabilityUuid(2), 2),
        (durabilityUuid(1), 5),
      ]);
      expect(rows('long_term_relations'), relationsBefore);
      expect(rows('tag_assignments'), assignmentsBefore);
      expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
    });

    test('удаление неизбранного намерения не меняет отметки и места', () async {
      final success = await intentionSucceeded(
        DeleteIntention(durabilityIntention(6)),
      );

      expect(
        success.catalogMutation.before!.summary.favoriteMark,
        FavoriteMark.notFavorite,
      );
      expect(storedFavoriteMarks(raw), _seededMarks);
    });

    test('долговременная связь и дневной выбор блокируют удаление и '
        'сохраняют намерение, его отметку и место', () async {
      storeFavoriteMark(raw, intentionId: durabilityUuid(3), position: 11);
      expect(
        await repository.execute(durabilityCreate()),
        isA<GraphResultSuccess>(),
      );
      final graphBefore = graphWithoutMarks();
      final marksBefore = storedFavoriteMarks(raw);
      final revisionBefore = await revision();

      // Намерение 2 защищено долговременными связями, 1 и 3 — ещё и дневным
      // выбором как исходное и выбранное намерения.
      for (final number in [2, 1, 3]) {
        final result = await repository.execute(
          DeleteIntention(durabilityIntention(number)),
        );

        expect(
          (result as ResultFailure).failure,
          isA<IntentionHasBlockingRelationsFailure>(),
        );
        expect(graphWithoutMarks(), graphBefore);
        expect(storedFavoriteMarks(raw), marksBefore);
        expect(
          await detailsMark(durabilityIntention(number)),
          FavoriteMark.favorite,
        );
      }
      expect(
        (await revision()).compareTo(revisionBefore),
        GraphRevisionOrder.same,
      );
    });

    test('ошибка удаления откатывает намерение вместе с отметкой и '
        'местом', () async {
      final graphBefore = graphWithoutMarks();
      final revisionBefore = await revision();
      await database.customStatement('''
        CREATE TEMP TRIGGER fail_favorite_mark_cascade
        AFTER DELETE ON favorite_intentions
        WHEN OLD.intention_id = '${durabilityUuid(7)}'
        BEGIN
          SELECT RAISE(ABORT, 'canary favorite mark cascade');
        END
      ''');

      final result = await repository.execute(
        DeleteIntention(durabilityIntention(7)),
      );

      expect(
        (result as ResultFailure).failure,
        isA<IntentionUnexpectedFailure>(),
      );
      expect(graphWithoutMarks(), graphBefore);
      expect(storedFavoriteMarks(raw), _seededMarks);
      expect(await detailsMark(durabilityIntention(7)), FavoriteMark.favorite);
      expect(
        (await revision()).compareTo(revisionBefore),
        GraphRevisionOrder.same,
      );
      expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
    });
  });

  group('Отметка и её снятие', () {
    test('не меняют намерение, теги, связи и дневные выборы, в том числе '
        'архивированного действия из выполненного дневного выбора', () async {
      expect(
        await repository.execute(durabilityCreate()),
        isA<GraphResultSuccess>(),
      );
      await intentionSucceeded(ArchiveIntention(durabilityIntention(3)));
      final archivedAction = intentionRow(3);
      expect(archivedAction['is_archived'], 1);
      expect(archivedAction['is_action_ready'], 1);
      expect(rows('daily_choices').single, contains(durabilityUuid(3)));
      final graphBefore = graphWithoutMarks();

      // Каждая команда выполняется при новом показании часов: запись времени
      // намерения изменила бы его строку.
      now = DateTime.utc(2026, 10, 3);
      await intentionSucceeded(MarkIntentionFavorite(durabilityIntention(3)));
      expect(graphWithoutMarks(), graphBefore);
      expect(storedFavoriteMarks(raw), [
        ..._seededMarks,
        (durabilityUuid(3), 10),
      ]);

      now = DateTime.utc(2026, 10, 4);
      await intentionSucceeded(MarkIntentionFavorite(durabilityIntention(4)));
      expect(graphWithoutMarks(), graphBefore);
      expect(storedFavoriteMarks(raw), [
        ..._seededMarks,
        (durabilityUuid(3), 10),
        (durabilityUuid(4), 11),
      ]);

      now = DateTime.utc(2026, 10, 5);
      for (final number in [1, 3]) {
        await intentionSucceeded(
          UnmarkIntentionFavorite(durabilityIntention(number)),
        );
        expect(graphWithoutMarks(), graphBefore);
      }
      expect(storedFavoriteMarks(raw), [
        (durabilityUuid(2), 2),
        (durabilityUuid(7), 7),
        (durabilityUuid(8), 9),
        (durabilityUuid(4), 11),
      ]);
      expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
    });
  });
}
