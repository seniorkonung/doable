import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/presentation/assignments/tag_assignments_state.dart';
import 'package:doable/src/tag/presentation/assignments/tag_assignments_view_model.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_state.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/graph_seed.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/local_database_harness.dart';
import '../../support/tag_storage_fixture.dart';
import '../../support/tag_positions.dart';

TagId _tag(int number) =>
    (TagId.decode(tagFixtureId(number)) as TagIdDecodingSuccess).id;

IntentionId _intention(int number) =>
    (IntentionId.decode(tagFixtureId(number)) as IntentionIdDecodingSuccess).id;

void main() {
  late LocalDatabaseHarness harness;
  late sqlite.Database raw;
  late sqlite.Database reader;
  late ProviderContainer container;
  late DriftPersonalGraphRepository repository;
  late GraphCommandCoordinator coordinator;
  late Map<GraphCommandCompletion, Map<String, List<List<Object?>>>> published;

  Map<String, List<List<Object?>>> graph() => {
    for (final table in [
      'intentions',
      'long_term_relations',
      'daily_choices',
      'daily_choice_path_steps',
      'tags',
      'tag_assignments',
    ])
      table: reader
          .select('SELECT * FROM $table ORDER BY rowid')
          .map((row) => row.values.toList())
          .toList(),
  };

  Future<TagCommandCompletion> send(TagCommand command) => (switch (command) {
    CreateTag() => coordinator.acceptTagCreation(TagCreationFormKey(), command),
    UpdateTag() => coordinator.acceptTagUpdate(command),
    DeleteTag() => coordinator.acceptTagDelete(command),
    AssignTag() => coordinator.acceptTagAssign(command),
    RemoveTagAssignment() => coordinator.acceptTagRemoveAssignment(command),
  } as TagCommandAccepted).future;

  TagCommandSuccess success(TagCommandCompletion completion) {
    expect(completion.isFailure, isFalse);
    expect(published[completion], graph());
    return (completion.confirmedResult as TagCommandSucceeded).value.value;
  }

  void expectAssignmentChange(
    TagCommandCompletion completion,
    TagAssignmentState state, {
    required bool changed,
  }) {
    final outcome = success(completion);
    expect(
      outcome,
      changed ? isA<TagAssignmentChanged>() : isA<TagAssignmentUnchanged>(),
    );
    expect(switch (outcome) {
      TagAssignmentChanged(:final state) ||
      TagAssignmentUnchanged(:final state) => state,
      _ => throw StateError('Ожидался исход назначения.'),
    }, state);
    // Изменение пары намерения несёт и каталожный снимок той же ревизии.
    expect(completion.confirmedChange!.changes, [
      isA<TagChange>(),
      if (changed) isA<IntentionCatalogUpdated>(),
    ]);
    for (final change in completion.confirmedChange!.changes) {
      expect(
        change.revision.compareTo(completion.revision!),
        GraphRevisionOrder.same,
      );
    }
  }

  setUp(() async {
    harness = await LocalDatabaseHarness.fileBacked();
    final database = await harness.openReadyDatabase(setup: (db) => raw = db);
    seedTagStorageFixture(raw);
    seedRawGraph(raw, () {
      raw.execute(
        'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
        [tagFixtureId(4), 'Свободное намерение', 1, 0, 104, 204],
      );
    });
    reader = sqlite.sqlite3.open(harness.databaseFile.path);
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 25),
      InMemoryDiagnosticsSink(),
    );
    container = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
    );
    coordinator = container.read(graphCommandCoordinatorProvider.notifier);
    published = {};
    coordinator.completions.listen((completion) {
      published[completion] = graph();
    });
  });

  tearDown(() async {
    await coordinator.shutdown();
    container.dispose();
    reader.close();
    await harness.dispose();
  });

  for (final (label, target) in [('намерения', _intention(1))]) {
    test('два потребителя $label согласуют полные снимки и изменения графа', () async {
      seedRawGraph(raw, () {
        for (var number = 303; number <= 439; number++) {
          raw.execute(
            'INSERT INTO tags (id, name, position) VALUES (?, ?, ?)',
            [tagFixtureId(number), 'Тег $number', tagPositionKey(number)],
          );
          raw.execute(
            'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
            [tagFixtureId(number), target.toCanonicalString()],
          );
        }
      });

      final assignmentsSubscription = container.listen(
        tagAssignmentsViewModelProvider(target),
        (_, _) {},
      );
      final catalogSubscription = container.listen(
        tagCatalogViewModelProvider(),
        (_, _) {},
      );
      addTearDown(assignmentsSubscription.close);
      addTearDown(catalogSubscription.close);
      final catalog = container.read(tagCatalogViewModelProvider().notifier);
      TagAssignmentsState assignmentState() =>
          container.read(tagAssignmentsViewModelProvider(target));
      TagCatalogState catalogState() =>
          container.read(tagCatalogViewModelProvider());

      Future<void> until(bool Function() condition) async {
        for (var attempt = 0; attempt < 40 && !condition(); attempt++) {
          await pumpEventQueue();
        }
        expect(condition(), isTrue);
      }

      Future<void> settled(GraphRevision revision) => until(
        () =>
            catalogState() is TagCatalogLoaded &&
            assignmentState() is TagAssignmentsLoaded &&
            (catalogState() as TagCatalogLoaded).freshness ==
                TagCatalogFreshness.current &&
            (assignmentState() as TagAssignmentsLoaded).freshness ==
                TagAssignmentsFreshness.current &&
            (catalogState() as TagCatalogLoaded).revision.compareTo(revision) ==
                GraphRevisionOrder.same &&
            (assignmentState() as TagAssignmentsLoaded).revision.compareTo(
                  revision,
                ) ==
                GraphRevisionOrder.same,
      );

      await until(() => catalogState() is TagCatalogLoaded);
      catalog.setMode(TagCatalogSelectionMode(target));
      await until(
        () =>
            catalogState() is TagCatalogLoaded &&
            (catalogState() as TagCatalogLoaded).mode ==
                TagCatalogSelectionMode(target) &&
            assignmentState() is TagAssignmentsLoaded,
      );
      final selected = catalogState() as TagCatalogLoaded;
      final assigned = assignmentState() as TagAssignmentsLoaded;
      expect(selected.items, hasLength(139));
      expect(assigned.items, hasLength(138));
      expect(selected.selectionRows.first.isAssigned, isTrue);
      expect(selected.selectionRows[1].isAssigned, isFalse);
      expect(assigned.items.map((tag) => tag.id).toSet(), hasLength(138));

      final completion = await send(
        AssignTag(tagId: _tag(lastTagNumber), intentionId: target),
      );
      expectAssignmentChange(
        completion,
        TagAssignmentState.assigned,
        changed: true,
      );
      await settled(completion.revision!);
      expect(
        (catalogState() as TagCatalogLoaded).selectionRows[1].isAssigned,
        isTrue,
      );
      expect(
        (assignmentState() as TagAssignmentsLoaded).items.map((tag) => tag.id),
        contains(_tag(lastTagNumber)),
      );

      final removed = await send(
        RemoveTagAssignment(tagId: _tag(firstTagNumber), intentionId: target),
      );
      expectAssignmentChange(removed, TagAssignmentState.absent, changed: true);
      await settled(removed.revision!);
      expect(
        (catalogState() as TagCatalogLoaded).selectionRows.first.isAssigned,
        isFalse,
      );
      expect(
        (assignmentState() as TagAssignmentsLoaded).items.map((tag) => tag.id),
        isNot(contains(_tag(firstTagNumber))),
      );

      final renamed = await send(
        UpdateTag(
          tagId: _tag(lastTagNumber),
          name: TagName.fromInput('Переименованный'),
          color: null,
        ),
      );
      expect(success(renamed), isA<TagUpdated>());
      await settled(renamed.revision!);
      expect(
        (catalogState() as TagCatalogLoaded).items[1].name.value,
        'Переименованный',
      );
      expect(
        (assignmentState() as TagAssignmentsLoaded).items.first.name.value,
        'Переименованный',
      );

      final unrelated = coordinator.acceptCreation(
        IntentionCreationFormKey(),
        const CreateIntention(
          title: 'Постороннее намерение',
          description: null,
        ),
      ) as IntentionCommandAccepted;
      final unrelatedCompletion = await unrelated.future;
      expect(unrelatedCompletion.isFailure, isFalse);
      await settled(unrelatedCompletion.revision!);
      expect(
        (catalogState() as TagCatalogLoaded).selectionRows[1].isAssigned,
        isTrue,
      );
      expect(
        (assignmentState() as TagAssignmentsLoaded).items.first.name.value,
        'Переименованный',
      );

      final deleted = await send(DeleteTag(_tag(lastTagNumber)));
      expect(success(deleted), isA<TagDeleted>());
      await settled(deleted.revision!);
      expect(
        (catalogState() as TagCatalogLoaded).items.map((tag) => tag.id),
        isNot(contains(_tag(lastTagNumber))),
      );
      expect(
        (assignmentState() as TagAssignmentsLoaded).items.map((tag) => tag.id),
        isNot(contains(_tag(lastTagNumber))),
      );
      final finalSelection = catalogState() as TagCatalogLoaded;
      final finalAssignments = assignmentState() as TagAssignmentsLoaded;
      expect(finalSelection.items, hasLength(138));
      expect(finalSelection.items.map((tag) => tag.id).toSet(), hasLength(138));
      expect(finalSelection.selectionRows.first.isAssigned, isFalse);
      expect(finalAssignments.items, hasLength(137));
      expect(
        finalAssignments.items.map((tag) => tag.id).toSet(),
        hasLength(137),
      );
      expect(reader.select('PRAGMA foreign_key_check'), isEmpty);
    });
  }
}
