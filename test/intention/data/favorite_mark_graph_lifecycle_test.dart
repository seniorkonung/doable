import 'package:doable/src/data/local/app_database.dart' hide Intention;
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
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
    );
  });

  tearDown(() => database.close());

  List<List<Object?>> rows(String table) => raw
      .select('SELECT * FROM $table ORDER BY rowid')
      .map((row) => row.values.toList())
      .toList();

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
  });
}
