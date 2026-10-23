import 'dart:async';

import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/design_system/components/sheet.dart';
import 'package:doable/src/design_system/components/tag_row.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_tag_conditions_view_model.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/presentation/assignments/tag_assignments_state.dart';
import 'package:doable/src/tag/presentation/assignments/tag_assignments_view_model.dart';
import 'package:doable/src/tag/presentation/panel/tags_panel_context.dart';
import 'package:doable/src/tag/presentation/panel/tags_panel_state.dart';
import 'package:doable/src/tag/presentation/panel/tags_panel_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/app_flow_wait.dart';
import '../support/app_root_pages.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/tag_storage_fixture.dart';
import '../support/in_memory_quick_creation_mode_store.dart';

void main() {
  final target = _intentionId(1);

  testWidgets(
    'Закрытие панели во время назначения: страница намерения показывает '
    'подтверждённое назначение без сообщения об успехе',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.binding.platformDispatcher.localesTestValue = [const Locale('ru')];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late sqlite.Database raw;
      final runtime = AppRuntime(
        quickCreationModeStore: InMemoryQuickCreationModeStore(),
        connectionFactory: () =>
            openInMemoryLocalDatabase(setup: (database) => raw = database),
        diagnosticsSink: InMemoryDiagnosticsSink(),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await runtime.shutdown();
      });
      final ready = await tester.runAsync(runtime.bootstrap) as AppRuntimeReady;
      seedTagStorageFixture(raw);
      final router = ready.container.read(appRouterProvider);
      await tester.pumpWidget(MainApp(runtime: runtime));
      await openIntentionGraph(tester, waitFor: until);
      unawaited(router.push(IntentionDetailsRoute(intentionId: target)));
      final choose = find.byKey(
        const ValueKey('tag-assignments-choose'),
        skipOffstage: false,
      );
      await until(tester, choose);
      await tester.pumpAndSettle();
      await tester.ensureVisible(choose);
      await tester.pumpAndSettle();
      await tester.tap(choose);
      final workId = tagFixtureId(lastTagNumber);
      final workRow = find.byKey(ValueKey('tags-panel-row-$workId'));
      await until(tester, workRow);
      await tester.pumpAndSettle();

      // Нажатие и закрытие в одном событии: запись ещё не подтверждена.
      tester
          .widget<TagRow>(
            find.descendant(of: workRow, matching: find.byType(TagRow)),
          )
          .onPressed!();
      Navigator.of(tester.element(workRow)).pop();
      expect(_assignments(raw, workId, 1), isEmpty);

      final remove = find.byKey(
        ValueKey('tag-assignment-remove-$workId'),
        skipOffstage: false,
      );
      await until(tester, remove);
      await settle(tester);
      expect(find.byType(Sheet), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(_assignments(raw, workId, 1), hasLength(1));
      expect(router.current.name, IntentionDetailsRoute.name);
      expect(tester.takeException(), isNull);
    },
  );

  test('открытые панели тегов фильтра и назначения и секции назначений видят общее переименование и удаление', () async {
    late sqlite.Database raw;
    final runtime = AppRuntime(
      quickCreationModeStore: InMemoryQuickCreationModeStore(),
      connectionFactory: () =>
          openInMemoryLocalDatabase(setup: (database) => raw = database),
      diagnosticsSink: InMemoryDiagnosticsSink(),
    );
    addTearDown(runtime.shutdown);
    final ready = await runtime.bootstrap() as AppRuntimeReady;
    seedTagStorageFixture(raw);
    final container = ready.container;
    final target = _intentionId(1);
    final archivedIntention = _intentionId(2);
    final conditions = intentionTagConditionsViewModelProvider(
      const BrowseIntentionCatalog(),
    );
    final conditionsSubscription = container.listen(conditions, (_, _) {});
    final filter = tagsPanelViewModelProvider(
      TagsPanelOpening(
        TagsPanelFilterContext(container.read(conditions.notifier)),
      ),
    );
    final panel = tagsPanelViewModelProvider(
      TagsPanelOpening(TagsPanelAssignmentContext(target)),
    );
    final assignments = tagAssignmentsViewModelProvider(target);
    final archivedAssignments = tagAssignmentsViewModelProvider(
      archivedIntention,
    );
    final subscriptions = [
      conditionsSubscription,
      container.listen(filter, (_, _) {}),
      container.listen(panel, (_, _) {}),
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
          container.read(panel).catalog is TagsPanelLoaded &&
          container.read(filter).catalog is TagsPanelLoaded &&
          container.read(archivedAssignments) is TagAssignmentsLoaded,
    );
    final id = _tagId(firstTagNumber);
    TagsPanelLoaded panelCatalog() =>
        container.read(panel).catalog as TagsPanelLoaded;
    TagsPanelLoaded filterCatalog() =>
        container.read(filter).catalog as TagsPanelLoaded;

    final renamed = runtime.commandCoordinator.acceptTagUpdate(
      UpdateTag(tagId: id, name: TagName.fromInput('Быт'), color: null),
    ) as TagCommandAccepted;
    await renamed.future;
    await _until(
      () =>
          filterCatalog().rows.first.tag.name.value == 'Быт' &&
          filterCatalog().rowsAreCurrent &&
          panelCatalog().rows.first.tag.name.value == 'Быт' &&
          panelCatalog().rows.first.mark == TagsPanelSelectionMark.marked &&
          panelCatalog().rowsAreCurrent &&
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

    final deleted = runtime.commandCoordinator.acceptTagDelete(
      DeleteTag(id),
    ) as TagCommandAccepted;
    await deleted.future;
    await _until(
      () =>
          filterCatalog().rows.every((row) => row.tag.id != id) &&
          filterCatalog().rowsAreCurrent &&
          panelCatalog().rows.every((row) => row.tag.id != id) &&
          panelCatalog().rowsAreCurrent &&
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
    expect(container.read(panel.notifier).toggle(id), isNull);
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
}

TagId _tagId(int number) =>
    (TagId.decode(tagFixtureId(number)) as TagIdDecodingSuccess).id;

IntentionId _intentionId(int number) =>
    (IntentionId.decode(tagFixtureId(number)) as IntentionIdDecodingSuccess).id;

Future<void> _until(bool Function() condition) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  expect(condition(), isTrue);
}

List<sqlite.Row> _assignments(sqlite.Database raw, String tagId, int number) =>
    raw.select(
      'SELECT * FROM tag_assignments WHERE tag_id = ? AND intention_id = ?',
      [tagId, tagFixtureId(number)],
    );
