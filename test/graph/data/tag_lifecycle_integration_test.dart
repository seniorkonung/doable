import 'dart:async';

import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/in_memory_diagnostics_sink.dart';

String _uuid(int number) =>
    '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}';

void main() {
  test('координатор проводит полный цикл тега через общий граф', () async {
    late sqlite.Database raw;
    final database = AppDatabase(
      openInMemoryLocalDatabase(setup: (db) => raw = db),
    );
    await database.open();
    addTearDown(database.close);
    final repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 25),
      InMemoryDiagnosticsSink(),
    );
    final container = ProviderContainer.test(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    final coordinator = container.read(
      graphCommandCoordinatorProvider.notifier,
    );
    addTearDown(coordinator.shutdown);
    final completions = <GraphCommandCompletion>[];
    final subscription = coordinator.completions.listen(completions.add);
    addTearDown(subscription.cancel);

    raw.execute(
      'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
      [_uuid(1), 'Намерение', 1, 0, 100, 200],
    );
    raw.execute(
      'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
      [_uuid(2), 'Действие', 1, 0, 300, 400],
    );
    raw.execute(
      'INSERT INTO long_term_relations (id, source_intention_id, related_intention_id, type, priority) VALUES (?, ?, ?, ?, ?)',
      [_uuid(3), _uuid(1), _uuid(2), 'need', 1],
    );
    raw.execute(
      'INSERT INTO daily_choices (id, source_intention_id, selected_intention_id, choice_date, is_completed) VALUES (?, ?, ?, ?, ?)',
      [_uuid(4), _uuid(1), _uuid(2), '2026-09-25', 0],
    );
    raw.execute(
      'INSERT INTO daily_choice_path_steps (id, daily_choice_id, long_term_relation_id) VALUES (?, ?, ?)',
      [_uuid(5), _uuid(4), _uuid(3)],
    );
    final graphBefore = {
      for (final table in [
        'intentions',
        'intention_titles_fts',
        'long_term_relations',
        'daily_choices',
        'daily_choice_path_steps',
      ])
        table: raw
            .select('SELECT * FROM $table')
            .map((row) => row.values.toList())
            .toList(),
    };

    Future<TagCommandCompletion> create(String name) async =>
        await (coordinator.acceptTagCreation(
          TagCreationFormKey(),
          CreateTag(TagName.fromInput(name)),
        ) as TagCommandAccepted).future;
    Future<TagCatalogPage> catalog() async =>
        (await repository.getTagCatalogPage(
          TagCatalogQuery(),
        ) as TagCatalogPageSuccess).value;

    final initialRevision = (await catalog()).revision;
    final created = await create('Дом');
    final firstTag =
        ((created.confirmedResult as TagCommandSucceeded).value.value
                as TagCreated)
            .tag;
    expect(created.confirmedChange!.changes.single, isA<TagCreatedChange>());
    expect(
      created.revision!.compareTo(initialRevision),
      GraphRevisionOrder.newer,
    );
    expect((await catalog()).items.single.id, firstTag.id);
    expect((await catalog()).items.single.name.value, 'Дом');

    final watched = StreamIterator(repository.watchTag(firstTag.id));
    addTearDown(watched.cancel);
    expect(await watched.moveNext(), isTrue);
    expect((watched.current as TagReadSuccess).value.value!.id, firstTag.id);
    expect((watched.current as TagReadSuccess).value.value!.name.value, 'Дом');

    raw.execute(
      'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
      [firstTag.id.toCanonicalString(), _uuid(1)],
    );
    raw.execute(
      'INSERT INTO tag_assignments (tag_id, long_term_relation_id) VALUES (?, ?)',
      [firstTag.id.toCanonicalString(), _uuid(3)],
    );

    final renamed = await (coordinator.acceptTagRename(
      RenameTag(tagId: firstTag.id, name: TagName.fromInput('Быт')),
    ) as TagCommandAccepted).future;
    expect(renamed.confirmedChange!.changes.single, isA<TagRenamedChange>());
    expect(
      renamed.revision!.compareTo(created.revision!),
      GraphRevisionOrder.newer,
    );
    expect(await watched.moveNext(), isTrue);
    expect((watched.current as TagReadSuccess).value.value!.name.value, 'Быт');
    expect(
      (watched.current as TagReadSuccess).value.revision.compareTo(
        renamed.revision!,
      ),
      GraphRevisionOrder.same,
    );
    expect((await catalog()).items.single.name.value, 'Быт');

    final unchanged = await (coordinator.acceptTagRename(
      RenameTag(tagId: firstTag.id, name: TagName.fromInput('Быт')),
    ) as TagCommandAccepted).future;
    expect(
      unchanged.confirmedChange!.changes.single,
      isA<TagUnchangedChange>(),
    );
    expect(
      unchanged.revision!.compareTo(renamed.revision!),
      GraphRevisionOrder.same,
    );

    final conflict = await create('БЫТ');
    expect(conflict.isFailure, isTrue);
    expect(
      (conflict.confirmedResult as TagCommandFailed).failure,
      isA<TagNameOccupiedFailure>().having(
        (failure) => failure.existingTagId,
        'id',
        firstTag.id,
      ),
    );
    expect(conflict.confirmedChange, isNull);
    expect(
      (await catalog()).revision.compareTo(renamed.revision!),
      GraphRevisionOrder.same,
    );

    final deleted = await (coordinator.acceptTagDelete(
      DeleteTag(firstTag.id),
    ) as TagCommandAccepted).future;
    expect(deleted.confirmedChange!.changes.single, isA<TagDeletedChange>());
    expect(
      deleted.revision!.compareTo(renamed.revision!),
      GraphRevisionOrder.newer,
    );
    expect(await watched.moveNext(), isTrue);
    expect((watched.current as TagReadSuccess).value.value, isNull);
    expect(
      (watched.current as TagReadSuccess).value.revision.compareTo(
        deleted.revision!,
      ),
      GraphRevisionOrder.same,
    );
    expect((await catalog()).items, isEmpty);
    expect(raw.select('SELECT * FROM tag_assignments'), isEmpty);

    final recreated = await create('Дом');
    final nextTag =
        ((recreated.confirmedResult as TagCommandSucceeded).value.value
                as TagCreated)
            .tag;
    expect(nextTag.id, isNot(firstTag.id));
    expect(
      recreated.revision!.compareTo(deleted.revision!),
      GraphRevisionOrder.newer,
    );
    expect((await catalog()).items.single.id, nextTag.id);
    expect((await catalog()).items.single.name.value, 'Дом');
    final staleDelete = await (coordinator.acceptTagDelete(
      DeleteTag(firstTag.id),
    ) as TagCommandAccepted).future;
    expect(
      (staleDelete.confirmedResult as TagCommandFailed).failure,
      isA<TagNotFoundFailure>(),
    );
    expect(staleDelete.confirmedChange, isNull);
    expect(
      (await catalog()).revision.compareTo(recreated.revision!),
      GraphRevisionOrder.same,
    );

    expect(completions, [
      same(created),
      same(renamed),
      same(unchanged),
      same(conflict),
      same(deleted),
      same(recreated),
      same(staleDelete),
    ]);
    expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
    for (final entry in graphBefore.entries) {
      expect(
        raw
            .select('SELECT * FROM ${entry.key}')
            .map((row) => row.values.toList())
            .toList(),
        entry.value,
      );
    }
  });
}
