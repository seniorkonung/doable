import 'package:doable/src/data/local/app_database.dart' hide TagAssignment;
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag_assignment.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/domain/tag_target.dart';
import 'package:doable/src/tag/presentation/assignments/tag_assignments_state.dart';
import 'package:doable/src/tag/presentation/assignments/tag_assignments_view_model.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_state.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/local_database_harness.dart';
import '../../support/tag_storage_fixture.dart';

TagId _tag(int number) =>
    (TagId.decode(tagFixtureId(number)) as TagIdDecodingSuccess).id;

IntentionTagTarget _intention(int number) => IntentionTagTarget(
  (IntentionId.decode(tagFixtureId(number)) as IntentionIdDecodingSuccess).id,
);

LongTermRelationTagTarget _relation(int number) => LongTermRelationTagTarget(
  (LongTermRelationId.decode(
    tagFixtureId(number),
  ) as LongTermRelationIdDecodingSuccess).id,
);

final class _AssignmentFailureProbe extends LocalDatabaseConnectionObserver {
  bool failAfterInsert = false;

  @override
  void afterStatement(LocalDatabaseSqlStatement statement) {
    if (failAfterInsert &&
        statement.operation == LocalDatabaseSqlOperation.insert &&
        statement.statements.any((sql) => sql.contains('tag_assignments'))) {
      failAfterInsert = false;
      throw StateError('Управляемый отказ после записи назначения.');
    }
  }
}

void main() {
  late LocalDatabaseHarness harness;
  late sqlite.Database raw;
  late sqlite.Database reader;
  late ProviderContainer container;
  late DriftPersonalGraphRepository repository;
  late GraphCommandCoordinator coordinator;
  late _AssignmentFailureProbe probe;
  late List<GraphCommandCompletion> completions;
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

  List<sqlite.Row> assignment(TagId tagId, TagTarget target) =>
      switch (target) {
        IntentionTagTarget(:final intentionId) => reader.select(
          'SELECT * FROM tag_assignments WHERE tag_id = ? AND intention_id = ?',
          [tagId.toCanonicalString(), intentionId.toCanonicalString()],
        ),
        LongTermRelationTagTarget(:final relationId) => reader.select(
          'SELECT * FROM tag_assignments WHERE tag_id = ? AND long_term_relation_id = ?',
          [tagId.toCanonicalString(), relationId.toCanonicalString()],
        ),
      };

  Future<GraphRevision> revision() async => (await repository.getTagCatalog(
    const TagCatalogBrowseMode(),
  ) as TagCatalogSuccess).value.revision;

  Future<TagCommandCompletion> send(TagCommand command) => (switch (command) {
    CreateTag() => coordinator.acceptTagCreation(TagCreationFormKey(), command),
    RenameTag() => coordinator.acceptTagRename(command),
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
    expect(completion.confirmedChange!.changes, hasLength(1));
    expect(
      completion.confirmedChange!.changes.single.revision.compareTo(
        completion.revision!,
      ),
      GraphRevisionOrder.same,
    );
  }

  setUp(() async {
    harness = await LocalDatabaseHarness.fileBacked();
    probe = _AssignmentFailureProbe();
    final database = await harness.openReadyDatabase(
      setup: (db) => raw = db,
      observer: probe,
    );
    seedTagStorageFixture(raw);
    raw.execute(
      'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
      [tagFixtureId(4), 'Свободное намерение', 1, 0, 104, 204],
    );
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
    completions = [];
    published = {};
    coordinator.completions.listen((completion) {
      completions.add(completion);
      published[completion] = graph();
    });
  });

  tearDown(() async {
    await coordinator.shutdown();
    container.dispose();
    reader.close();
    await harness.dispose();
  });

  for (final (label, target) in [
    ('архивному намерению', _intention(2)),
    ('связи из дневного пути', _relation(101)),
  ]) {
    test(
      'назначение $label, повторы и снятие подтверждаются после фиксации',
      () async {
        final tagId = _tag(lastTagNumber);
        final before = graph();
        final initialRevision = await revision();

        final assigned = await send(AssignTag(tagId: tagId, target: target));
        expectAssignmentChange(
          assigned,
          TagAssignmentState.assigned,
          changed: true,
        );
        expect(
          (success(assigned) as TagAssignmentChanged).assignment,
          TagAssignment(tagId: tagId, target: target),
        );
        expect(
          assigned.revision!.compareTo(initialRevision),
          GraphRevisionOrder.newer,
        );
        final originalSequence = assignment(
          tagId,
          target,
        ).single['creation_sequence'];

        final repeated = await send(AssignTag(tagId: tagId, target: target));
        expectAssignmentChange(
          repeated,
          TagAssignmentState.assigned,
          changed: false,
        );
        expect(
          repeated.revision!.compareTo(assigned.revision!),
          GraphRevisionOrder.same,
        );
        expect(
          assignment(tagId, target).single['creation_sequence'],
          originalSequence,
        );

        final removed = await send(
          RemoveTagAssignment(tagId: tagId, target: target),
        );
        expectAssignmentChange(
          removed,
          TagAssignmentState.absent,
          changed: true,
        );
        expect(
          (success(removed) as TagAssignmentChanged).assignment,
          TagAssignment(tagId: tagId, target: target),
        );
        expect(
          removed.revision!.compareTo(repeated.revision!),
          GraphRevisionOrder.newer,
        );
        expect(assignment(tagId, target), isEmpty);

        final repeatedRemoval = await send(
          RemoveTagAssignment(tagId: tagId, target: target),
        );
        expectAssignmentChange(
          repeatedRemoval,
          TagAssignmentState.absent,
          changed: false,
        );
        expect(
          repeatedRemoval.revision!.compareTo(removed.revision!),
          GraphRevisionOrder.same,
        );
        expect(graph(), before);
        expect(reader.select('PRAGMA foreign_key_check'), isEmpty);
      },
    );

    test('две отправки назначения $label дают одну пару', () async {
      final tagId = _tag(lastTagNumber);
      final command = AssignTag(tagId: tagId, target: target);
      final initialRevision = await revision();
      final first = coordinator.acceptTagAssign(command) as TagCommandAccepted;
      expect(
        coordinator.acceptTagAssign(command),
        isA<TagCommandAlreadyRunning>(),
      );
      expect(assignment(tagId, target), isEmpty);
      final committed = await first.future;
      expectAssignmentChange(
        committed,
        TagAssignmentState.assigned,
        changed: true,
      );
      expect(
        committed.revision!.compareTo(initialRevision),
        GraphRevisionOrder.newer,
      );
      expect(assignment(tagId, target), hasLength(1));
      expect(completions, [same(committed)]);

      final repeated = await send(command);
      expectAssignmentChange(
        repeated,
        TagAssignmentState.assigned,
        changed: false,
      );
      expect(
        repeated.revision!.compareTo(committed.revision!),
        GraphRevisionOrder.same,
      );
      expect(assignment(tagId, target), hasLength(1));
    });

    for (final assignFirst in [true, false]) {
      test(
        '$label: ${assignFirst ? 'назначение' : 'удаление тега'} первым оставляет целый граф',
        () async {
          final tagId = _tag(lastTagNumber);
          final before = graph();
          if (assignFirst) {
            final assigned = await send(
              AssignTag(tagId: tagId, target: target),
            );
            expectAssignmentChange(
              assigned,
              TagAssignmentState.assigned,
              changed: true,
            );
            expect(assignment(tagId, target), hasLength(1));
          }
          final deleted = await send(DeleteTag(tagId));
          expect(success(deleted), isA<TagDeleted>());
          expect(assignment(tagId, target), isEmpty);
          final afterDelete = graph();
          final failed = await send(AssignTag(tagId: tagId, target: target));
          expect(
            (failed.confirmedResult as TagCommandFailed).failure,
            isA<TagNotFoundFailure>(),
          );
          expect(failed.confirmedChange, isNull);
          expect(published[failed], afterDelete);
          expect(graph(), afterDelete);
          expect(
            (await revision()).compareTo(deleted.revision!),
            GraphRevisionOrder.same,
          );
          expect(graph()['intentions'], before['intentions']);
          expect(graph()['long_term_relations'], before['long_term_relations']);
          expect(graph()['daily_choices'], before['daily_choices']);
          expect(reader.select('PRAGMA foreign_key_check'), isEmpty);
        },
      );
    }
  }

  for (final (label, target) in [
    ('намерения', _intention(4)),
    ('связи', _relation(102)),
  ]) {
    for (final assignFirst in [true, false]) {
      test(
        '${assignFirst ? 'назначение' : 'удаление'} $label первым не оставляет висячую пару',
        () async {
          final tagId = _tag(lastTagNumber);
          final before = graph();
          if (assignFirst) {
            final assigned = await send(
              AssignTag(tagId: tagId, target: target),
            );
            expectAssignmentChange(
              assigned,
              TagAssignmentState.assigned,
              changed: true,
            );
          }
          final deleted = switch (target) {
            IntentionTagTarget(:final intentionId) =>
              await (coordinator.acceptExisting(
                DeleteIntention(intentionId),
                presentationTitle: 'Свободное намерение',
              ) as IntentionCommandAccepted).future,
            LongTermRelationTagTarget(:final relationId) =>
              await (coordinator.acceptRelationDelete(
                DeleteLongTermRelation(relationId),
              ) as LongTermRelationCommandAccepted).future,
          };
          expect(deleted.isFailure, isFalse);
          expect(deleted.revision, isNotNull);
          expect(published[deleted], graph());
          expect(assignment(tagId, target), isEmpty);
          final afterDelete = graph();
          final failed = await send(AssignTag(tagId: tagId, target: target));
          expect(
            (failed.confirmedResult as TagCommandFailed).failure,
            isA<TagTargetNotFoundFailure>(),
          );
          expect(failed.confirmedChange, isNull);
          expect(published[failed], afterDelete);
          expect(graph(), afterDelete);
          expect(
            (await revision()).compareTo(deleted.revision!),
            GraphRevisionOrder.same,
          );
          expect(
            reader.select('SELECT id FROM tags WHERE id = ?', [
              tagId.toCanonicalString(),
            ]),
            hasLength(1),
          );
          expect(reader.select('PRAGMA foreign_key_check'), isEmpty);
          expect(graph()['tags'], before['tags']);
        },
      );
    }
  }

  test('переименование сохраняет выбор, новое одноимённое имя не подменяет удалённый тег', () async {
    final tagId = _tag(lastTagNumber);
    final target = _intention(2);
    final renamed = await send(
      RenameTag(tagId: tagId, name: TagName.fromInput('Быт')),
    );
    expect(success(renamed), isA<TagRenamed>());
    final assigned = await send(AssignTag(tagId: tagId, target: target));
    expectAssignmentChange(
      assigned,
      TagAssignmentState.assigned,
      changed: true,
    );
    expect(assignment(tagId, target), hasLength(1));
    expect(
      reader.select('SELECT name FROM tags WHERE id = ?', [
        tagId.toCanonicalString(),
      ]).single['name'],
      'Быт',
    );

    final deleted = await send(DeleteTag(tagId));
    expect(success(deleted), isA<TagDeleted>());
    final created = await send(CreateTag(TagName.fromInput('Быт')));
    final replacement = (success(created) as TagCreated).tag.id;
    expect(replacement, isNot(tagId));
    final afterCreate = graph();
    final stale = await send(AssignTag(tagId: tagId, target: target));
    expect(
      (stale.confirmedResult as TagCommandFailed).failure,
      isA<TagNotFoundFailure>(),
    );
    expect(published[stale], afterCreate);
    expect(graph(), afterCreate);
    expect(assignment(replacement, target), isEmpty);
    expect(
      (await revision()).compareTo(created.revision!),
      GraphRevisionOrder.same,
    );
  });

  test(
    'сбой после записи откатывает назначение и освобождает оба ключа',
    () async {
      final tagId = _tag(lastTagNumber);
      final target = _intention(2);
      final before = graph();
      final initialRevision = await revision();
      probe.failAfterInsert = true;
      final failed = await send(AssignTag(tagId: tagId, target: target));
      expect(
        (failed.confirmedResult as TagCommandFailed).failure,
        isA<TagUnexpectedFailure>(),
      );
      expect(failed.confirmedChange, isNull);
      expect(published[failed], before);
      expect(graph(), before);
      expect(
        (await revision()).compareTo(initialRevision),
        GraphRevisionOrder.same,
      );
      expect(coordinator.isTagRunning(tagId), isFalse);
      expect(coordinator.isRunning(target.intentionId), isFalse);

      final retry = await send(AssignTag(tagId: tagId, target: target));
      expectAssignmentChange(retry, TagAssignmentState.assigned, changed: true);
      expect(assignment(tagId, target), hasLength(1));
      expect(reader.select('PRAGMA foreign_key_check'), isEmpty);
    },
  );

  for (final (label, target) in [
    ('намерения', _intention(1)),
    ('долговременной связи', _relation(101)),
  ]) {
    test(
      'два потребителя $label согласуют полные снимки и изменения графа',
      () async {
        for (var number = 303; number <= 439; number++) {
          raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
            tagFixtureId(number),
            'Тег $number',
          ]);
          switch (target) {
            case IntentionTagTarget(:final intentionId):
              raw.execute(
                'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
                [tagFixtureId(number), intentionId.toCanonicalString()],
              );
            case LongTermRelationTagTarget(:final relationId):
              raw.execute(
                'INSERT INTO tag_assignments (tag_id, long_term_relation_id) VALUES (?, ?)',
                [tagFixtureId(number), relationId.toCanonicalString()],
              );
          }
        }

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
              (catalogState() as TagCatalogLoaded).revision.compareTo(
                    revision,
                  ) ==
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
          AssignTag(tagId: _tag(lastTagNumber), target: target),
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
          (assignmentState() as TagAssignmentsLoaded).items.map(
            (tag) => tag.id,
          ),
          contains(_tag(lastTagNumber)),
        );

        final removed = await send(
          RemoveTagAssignment(tagId: _tag(firstTagNumber), target: target),
        );
        expectAssignmentChange(
          removed,
          TagAssignmentState.absent,
          changed: true,
        );
        await settled(removed.revision!);
        expect(
          (catalogState() as TagCatalogLoaded).selectionRows.first.isAssigned,
          isFalse,
        );
        expect(
          (assignmentState() as TagAssignmentsLoaded).items.map(
            (tag) => tag.id,
          ),
          isNot(contains(_tag(firstTagNumber))),
        );

        final renamed = await send(
          RenameTag(
            tagId: _tag(lastTagNumber),
            name: TagName.fromInput('Переименованный'),
          ),
        );
        expect(success(renamed), isA<TagRenamed>());
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
          (assignmentState() as TagAssignmentsLoaded).items.map(
            (tag) => tag.id,
          ),
          isNot(contains(_tag(lastTagNumber))),
        );
        final finalSelection = catalogState() as TagCatalogLoaded;
        final finalAssignments = assignmentState() as TagAssignmentsLoaded;
        expect(finalSelection.items, hasLength(138));
        expect(
          finalSelection.items.map((tag) => tag.id).toSet(),
          hasLength(138),
        );
        expect(finalSelection.selectionRows.first.isAssigned, isFalse);
        expect(finalAssignments.items, hasLength(137));
        expect(
          finalAssignments.items.map((tag) => tag.id).toSet(),
          hasLength(137),
        );
        expect(reader.select('PRAGMA foreign_key_check'), isEmpty);
      },
    );
  }
}
