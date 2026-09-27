import 'dart:async';

import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/application/tag_assignments_page.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/domain/tag_target.dart';
import 'package:doable/src/tag/presentation/assignments/tag_assignments_state.dart';
import 'package:doable/src/tag/presentation/assignments/tag_assignments_view_model.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_state.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/in_memory_diagnostics_sink.dart';
import '../support/tag_storage_fixture.dart';

void main() {
  test('открытые каталог, выбор и назначения видят общее переименование и удаление', () async {
    late sqlite.Database raw;
    final runtime = AppRuntime(
      connectionFactory: () =>
          openInMemoryLocalDatabase(setup: (database) => raw = database),
      diagnosticsSink: InMemoryDiagnosticsSink(),
    );
    addTearDown(runtime.shutdown);
    final ready = await runtime.bootstrap() as AppRuntimeReady;
    seedTagStorageFixture(raw);
    final container = ready.container;
    final target = _intentionTarget(1);
    final relation = _relationTarget(102);
    final browse = tagCatalogViewModelProvider();
    final choose = tagCatalogViewModelProvider(
      mode: TagCatalogSelectionMode(target),
    );
    final assignments = tagAssignmentsViewModelProvider(target);
    final archivedAssignments = tagAssignmentsViewModelProvider(relation);
    final subscriptions = [
      container.listen(browse, (_, _) {}),
      container.listen(choose, (_, _) {}),
      container.listen(assignments, (_, _) {}),
      container.listen(archivedAssignments, (_, _) {}),
    ];
    addTearDown(() {
      for (final subscription in subscriptions) {
        subscription.close();
      }
    });
    await _until(
      () =>
          container.read(assignments) is TagAssignmentsLoaded &&
          container.read(choose) is TagCatalogLoaded &&
          container.read(archivedAssignments) is TagAssignmentsLoaded,
    );
    final id = _tagId(firstTagNumber);
    container.read(choose.notifier).selectTag(id);
    await _until(
      () =>
          (container.read(choose) as TagCatalogLoaded).selection
              is TagCatalogSelectionReady,
    );

    final renamed = runtime.commandCoordinator.acceptTagRename(
      RenameTag(tagId: id, name: TagName.fromInput('Быт')),
    ) as TagCommandAccepted;
    await renamed.future;
    await _until(
      () =>
          [container.read(browse), container.read(choose)].every(
            (state) =>
                state is TagCatalogLoaded &&
                state.items.first.name.value == 'Быт',
          ) &&
          [
            container.read(assignments),
            container.read(archivedAssignments),
          ].every(
            (state) =>
                state is TagAssignmentsLoaded &&
                state.items.first.name.value == 'Быт' &&
                state.canUseCurrentItems,
          ),
    );
    expect((container.read(choose) as TagCatalogLoaded).selection.id, id);

    final deleted = runtime.commandCoordinator.acceptTagDelete(
      DeleteTag(id),
    ) as TagCommandAccepted;
    await deleted.future;
    await _until(
      () =>
          [container.read(browse), container.read(choose)].every(
            (state) =>
                state is TagCatalogLoaded &&
                state.items.every((tag) => tag.id != id) &&
                state.canUseCurrentItems,
          ) &&
          [
            container.read(assignments),
            container.read(archivedAssignments),
          ].every(
            (state) =>
                state is TagAssignmentsLoaded &&
                state.items.every((tag) => tag.id != id) &&
                state.canUseCurrentItems,
          ),
    );
    expect(
      (container.read(choose) as TagCatalogLoaded).selection,
      isA<TagCatalogNoSelection>(),
    );
    expect(container.read(choose.notifier).canActOn(id), isFalse);
    expect(container.read(assignments.notifier).canActOn(id), isFalse);
    expect(
      raw.select('SELECT * FROM tag_assignments WHERE tag_id = ?', [
        tagFixtureId(firstTagNumber),
      ]),
      isEmpty,
    );
    expect(raw.select('SELECT id FROM daily_choices'), hasLength(1));
    expect(raw.select('SELECT id FROM daily_choice_path_steps'), hasLength(1));
  });

  test(
    'поздняя порция до пакета не возвращает старое имя и не повторяет запись',
    () async {
      late sqlite.Database raw;
      late _ControlledReads repository;
      final diagnostics = InMemoryDiagnosticsSink();
      final runtime = AppRuntime(
        connectionFactory: () =>
            openInMemoryLocalDatabase(setup: (database) => raw = database),
        diagnosticsSink: diagnostics,
        repositoryFactory: (database) => repository = _ControlledReads(
          DriftPersonalGraphRepository(
            database,
            UuidV7IntentionIdGenerator(),
            () => DateTime.utc(2026, 9, 25),
            diagnostics,
          ),
        ),
      );
      addTearDown(runtime.shutdown);
      final ready = await runtime.bootstrap() as AppRuntimeReady;
      seedTagStorageFixture(raw);
      final target = _intentionTarget(1);
      final assignments = tagAssignmentsViewModelProvider(target);
      final browse = tagCatalogViewModelProvider();
      repository.holdNextAssignmentsRead();
      final subscription = ready.container.listen(assignments, (_, _) {});
      final catalogSubscription = ready.container.listen(browse, (_, _) {});
      addTearDown(() {
        subscription.close();
        catalogSubscription.close();
      });
      await repository.heldReadStarted;
      final id = _tagId(firstTagNumber);
      final renamed = runtime.commandCoordinator.acceptTagRename(
        RenameTag(tagId: id, name: TagName.fromInput('Быт')),
      ) as TagCommandAccepted;
      await renamed.future;
      repository.releaseAssignmentsRead();
      await _until(() {
        final state = ready.container.read(assignments);
        return state is TagAssignmentsLoaded &&
            state.canUseCurrentItems &&
            state.items.first.name.value == 'Быт';
      });
      expect(repository.renameAttempts, 1);
      expect(
        (ready.container.read(
          browse,
        ) as TagCatalogLoaded).items.first.name.value,
        'Быт',
      );
    },
  );

  test(
    'после смены получателя позднее чтение не подменяет его назначения',
    () async {
      late sqlite.Database raw;
      late _ControlledReads repository;
      final diagnostics = InMemoryDiagnosticsSink();
      final runtime = AppRuntime(
        connectionFactory: () =>
            openInMemoryLocalDatabase(setup: (database) => raw = database),
        diagnosticsSink: diagnostics,
        repositoryFactory: (database) => repository = _ControlledReads(
          DriftPersonalGraphRepository(
            database,
            UuidV7IntentionIdGenerator(),
            () => DateTime.utc(2026, 9, 25),
            diagnostics,
          ),
        ),
      );
      addTearDown(runtime.shutdown);
      final ready = await runtime.bootstrap() as AppRuntimeReady;
      seedTagStorageFixture(raw);
      final first = _intentionTarget(1);
      final second = _intentionTarget(3);
      final provider = tagAssignmentsViewModelProvider(first);
      repository.holdNextAssignmentsRead();
      final subscription = ready.container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await repository.heldReadStarted;
      ready.container.read(provider.notifier).setTarget(second);
      expect(
        ready.container.read(provider),
        isA<TagAssignmentsInitialLoading>(),
      );
      repository.releaseAssignmentsRead();
      await _until(() {
        final state = ready.container.read(provider);
        return state is TagAssignmentsLoaded && state.target == second;
      });
      final state = ready.container.read(provider) as TagAssignmentsLoaded;
      expect(state.items.map((tag) => tag.id), [_tagId(lastTagNumber)]);
      expect(
        state.items.map((tag) => tag.id),
        isNot(contains(_tagId(firstTagNumber))),
      );
    },
  );

  test(
    'выбор вне порции исчезает при удалении даже после отказа чтения',
    () async {
      late sqlite.Database raw;
      late _ControlledReads repository;
      final diagnostics = InMemoryDiagnosticsSink();
      final runtime = AppRuntime(
        connectionFactory: () =>
            openInMemoryLocalDatabase(setup: (database) => raw = database),
        diagnosticsSink: diagnostics,
        repositoryFactory: (database) => repository = _ControlledReads(
          DriftPersonalGraphRepository(
            database,
            UuidV7IntentionIdGenerator(),
            () => DateTime.utc(2026, 9, 25),
            diagnostics,
          ),
        ),
      );
      addTearDown(runtime.shutdown);
      final ready = await runtime.bootstrap() as AppRuntimeReady;
      seedTagStorageFixture(raw);
      for (var number = 303; number <= 352; number++) {
        raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
          tagFixtureId(number),
          'Дополнительный тег $number',
        ]);
      }
      final provider = tagCatalogViewModelProvider(
        mode: TagCatalogSelectionMode(_intentionTarget(1)),
      );
      final subscription = ready.container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await _until(() => ready.container.read(provider) is TagCatalogLoaded);
      final id = _tagId(352);
      final model = ready.container.read(provider.notifier);
      expect(
        (ready.container.read(provider) as TagCatalogLoaded).items.any(
          (tag) => tag.id == id,
        ),
        isFalse,
      );
      model.selectTag(id);
      await _until(
        () =>
            (ready.container.read(provider) as TagCatalogLoaded).selection
                is TagCatalogSelectionReady,
      );
      expect(model.canActOn(id), isTrue);

      repository.failNextCatalogRead = true;
      final deleted = runtime.commandCoordinator.acceptTagDelete(
        DeleteTag(id),
      ) as TagCommandAccepted;
      await deleted.future;
      await _until(() {
        final state = ready.container.read(provider);
        return state is TagCatalogLoaded &&
            state.freshness == TagCatalogFreshness.stale;
      });
      final stale = ready.container.read(provider) as TagCatalogLoaded;
      expect(stale.selection, isA<TagCatalogNoSelection>());
      expect(model.canActOn(id), isFalse);
      expect(model.assignSelected(), isNull);
      await model.retryRefresh();
      final current = ready.container.read(provider) as TagCatalogLoaded;
      expect(current.canUseCurrentItems, isTrue);
      expect(current.selection, isA<TagCatalogNoSelection>());
      expect(
        raw.select('SELECT id FROM tags WHERE id = ?', [tagFixtureId(352)]),
        isEmpty,
      );
    },
  );

  test(
    'назначение и снятие завершаются после ухода и удерживают ключи',
    () async {
      late sqlite.Database raw;
      late _ControlledReads repository;
      final diagnostics = InMemoryDiagnosticsSink();
      final runtime = AppRuntime(
        connectionFactory: () =>
            openInMemoryLocalDatabase(setup: (database) => raw = database),
        diagnosticsSink: diagnostics,
        repositoryFactory: (database) => repository = _ControlledReads(
          DriftPersonalGraphRepository(
            database,
            UuidV7IntentionIdGenerator(),
            () => DateTime.utc(2026, 9, 25),
            diagnostics,
          ),
        ),
      );
      addTearDown(runtime.shutdown);
      final ready = await runtime.bootstrap() as AppRuntimeReady;
      seedTagStorageFixture(raw);
      final target = _intentionTarget(3);
      final id = _tagId(firstTagNumber);
      final assignments = tagAssignmentsViewModelProvider(target);
      var subscription = ready.container.listen(assignments, (_, _) {});
      await _until(
        () => ready.container.read(assignments) is TagAssignmentsLoaded,
      );
      final presentation = runtime.commandCoordinator.registerAppPresentation();
      addTearDown(presentation.release);

      repository.holdNextAssign();
      final assigned = runtime.commandCoordinator.acceptTagAssign(
        AssignTag(tagId: id, target: target),
      ) as TagCommandAccepted;
      await repository.heldCommandStarted;
      subscription.close();
      expect(
        runtime.commandCoordinator.acceptTagAssign(
          AssignTag(tagId: id, target: target),
        ),
        isA<TagCommandAlreadyRunning>(),
      );
      expect(
        runtime.commandCoordinator.acceptTagRemoveAssignment(
          RemoveTagAssignment(tagId: id, target: target),
        ),
        isA<TagCommandAlreadyRunning>(),
      );
      repository.releaseCommand();
      await assigned.future;
      expect(
        raw.select(
          'SELECT * FROM tag_assignments WHERE tag_id = ? AND intention_id = ?',
          [tagFixtureId(firstTagNumber), tagFixtureId(3)],
        ),
        hasLength(1),
      );
      final firstClaim = await presentation.nextClaim();
      expect(firstClaim!.token, same(assigned.token));
      runtime.commandCoordinator.confirmPresentation(firstClaim);
      subscription = ready.container.listen(assignments, (_, _) {});
      await _until(() {
        final state = ready.container.read(assignments);
        return state is TagAssignmentsLoaded && state.contains(id);
      });

      repository.holdNextRemove();
      final removed = runtime.commandCoordinator.acceptTagRemoveAssignment(
        RemoveTagAssignment(tagId: id, target: target),
      ) as TagCommandAccepted;
      await repository.heldCommandStarted;
      subscription.close();
      expect(
        runtime.commandCoordinator.acceptTagAssign(
          AssignTag(tagId: id, target: target),
        ),
        isA<TagCommandAlreadyRunning>(),
      );
      repository.releaseCommand();
      await removed.future;
      expect(
        raw.select(
          'SELECT * FROM tag_assignments WHERE tag_id = ? AND intention_id = ?',
          [tagFixtureId(firstTagNumber), tagFixtureId(3)],
        ),
        isEmpty,
      );
      final secondClaim = await presentation.nextClaim();
      expect(secondClaim!.token, same(removed.token));
      runtime.commandCoordinator.confirmPresentation(secondClaim);
      subscription = ready.container.listen(assignments, (_, _) {});
      addTearDown(subscription.close);
      await _until(() {
        final state = ready.container.read(assignments);
        return state is TagAssignmentsLoaded && !state.contains(id);
      });
      expect(repository.assignAttempts, 1);
      expect(repository.removeAttempts, 1);
      final noThirdResult = presentation.nextClaim();
      presentation.release();
      expect(await noThirdResult, isNull);
    },
  );

  test(
    'после отказа принятой команды сообщение о занятости исчезает',
    () async {
      late sqlite.Database raw;
      late _ControlledReads repository;
      final diagnostics = InMemoryDiagnosticsSink();
      final runtime = AppRuntime(
        connectionFactory: () =>
            openInMemoryLocalDatabase(setup: (database) => raw = database),
        diagnosticsSink: diagnostics,
        repositoryFactory: (database) => repository = _ControlledReads(
          DriftPersonalGraphRepository(
            database,
            UuidV7IntentionIdGenerator(),
            () => DateTime.utc(2026, 9, 25),
            diagnostics,
          ),
        ),
      );
      addTearDown(runtime.shutdown);
      final ready = await runtime.bootstrap() as AppRuntimeReady;
      seedTagStorageFixture(raw);
      raw.execute('''
      CREATE TEMP TRIGGER fail_assignment BEFORE INSERT ON tag_assignments
      BEGIN SELECT RAISE(ABORT, 'injected assignment failure'); END
    ''');
      final target = _intentionTarget(3);
      final id = _tagId(firstTagNumber);
      final provider = tagCatalogViewModelProvider(
        mode: TagCatalogSelectionMode(target),
      );
      final subscription = ready.container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await _until(() => ready.container.read(provider) is TagCatalogLoaded);
      final model = ready.container.read(provider.notifier);
      model.selectTag(id);
      await _until(
        () =>
            (ready.container.read(provider) as TagCatalogLoaded).selection
                is TagCatalogSelectionReady,
      );

      repository.holdNextAssign();
      final accepted = runtime.commandCoordinator.acceptTagAssign(
        AssignTag(tagId: id, target: target),
      ) as TagCommandAccepted;
      await repository.heldCommandStarted;
      expect(model.assignSelected(), isA<TagCommandAlreadyRunning>());
      expect(
        (ready.container.read(provider) as TagCatalogLoaded).assignmentStatus,
        isA<TagCatalogAssignmentKeysBusy>(),
      );
      repository.releaseCommand();
      final completion = await accepted.future;
      expect(completion.result, isA<GraphResultFailure>());
      await _until(
        () =>
            (ready.container.read(
                  provider,
                ) as TagCatalogLoaded).assignmentStatus
                is TagCatalogAssignmentIdle,
      );
      expect(repository.assignAttempts, 1);
      expect(
        raw.select(
          'SELECT * FROM tag_assignments WHERE tag_id = ? AND intention_id = ?',
          [tagFixtureId(firstTagNumber), tagFixtureId(3)],
        ),
        isEmpty,
      );
    },
  );
}

TagId _tagId(int number) =>
    (TagId.decode(tagFixtureId(number)) as TagIdDecodingSuccess).id;

IntentionTagTarget _intentionTarget(int number) => IntentionTagTarget(
  (IntentionId.decode(tagFixtureId(number)) as IntentionIdDecodingSuccess).id,
);

LongTermRelationTagTarget _relationTarget(int number) =>
    LongTermRelationTagTarget(
      (LongTermRelationId.decode(
        tagFixtureId(number),
      ) as LongTermRelationIdDecodingSuccess).id,
    );

Future<void> _until(bool Function() condition) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  expect(condition(), isTrue);
}

final class _ControlledReads extends Fake implements PersonalGraphRepository {
  _ControlledReads(this.delegate);

  final PersonalGraphRepository delegate;
  Completer<void>? _assignmentsGate;
  Completer<void>? _releaseGate;
  Completer<void>? _heldReadStarted;
  Completer<void>? _commandGate;
  Completer<void>? _commandStarted;
  bool _holdAssign = false;
  bool _holdRemove = false;
  bool failNextCatalogRead = false;
  int renameAttempts = 0;
  int assignAttempts = 0;
  int removeAttempts = 0;

  void holdNextAssignmentsRead() {
    _assignmentsGate = Completer<void>();
    _releaseGate = _assignmentsGate;
    _heldReadStarted = Completer<void>();
  }

  Future<void> get heldReadStarted => _heldReadStarted!.future;

  void releaseAssignmentsRead() => _releaseGate!.complete();

  void holdNextAssign() {
    _commandGate = Completer<void>();
    _commandStarted = Completer<void>();
    _holdAssign = true;
  }

  void holdNextRemove() {
    _commandGate = Completer<void>();
    _commandStarted = Completer<void>();
    _holdRemove = true;
  }

  Future<void> get heldCommandStarted => _commandStarted!.future;

  void releaseCommand() => _commandGate!.complete();

  @override
  Future<TagCatalogPageResult> getTagCatalogPage(TagCatalogQuery query) {
    if (failNextCatalogRead) {
      failNextCatalogRead = false;
      return Future.value(
        const TagCatalogPageError(TagCatalogUnavailableFailure()),
      );
    }
    return delegate.getTagCatalogPage(query);
  }

  @override
  Future<TagAssignmentsPageResult> getTagAssignmentsPage(
    TagAssignmentsQuery query,
  ) async {
    final result = await delegate.getTagAssignmentsPage(query);
    final gate = _assignmentsGate;
    if (gate != null) {
      _assignmentsGate = null;
      _heldReadStarted!.complete();
      await gate.future;
    }
    return result;
  }

  @override
  Stream<TagReadResult> watchTag(TagId id) => delegate.watchTag(id);

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    if (command is RenameTag) renameAttempts++;
    if (command is AssignTag) {
      assignAttempts++;
      if (_holdAssign) {
        _holdAssign = false;
        _commandStarted!.complete();
        await _commandGate!.future;
      }
    }
    if (command is RemoveTagAssignment) {
      removeAttempts++;
      if (_holdRemove) {
        _holdRemove = false;
        _commandStarted!.complete();
        await _commandGate!.future;
      }
    }
    return delegate.execute(command);
  }
}
