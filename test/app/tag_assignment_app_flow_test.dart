import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/design_system/components/sheet.dart';
import 'package:doable/src/design_system/components/tag_row.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/app_root_pages.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/tag_storage_fixture.dart';
import '../support/in_memory_quick_creation_mode_store.dart';

void main() {
  const number = 1;
  testWidgets('намерение: сквозное назначение и снятие', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.platformDispatcher.localesTestValue = [const Locale('ru')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late sqlite.Database raw;
    final diagnostics = InMemoryDiagnosticsSink();
    final runtime = AppRuntime(
      quickCreationModeStore: InMemoryQuickCreationModeStore(),
      connectionFactory: () =>
          openInMemoryLocalDatabase(setup: (database) => raw = database),
      diagnosticsSink: diagnostics,
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await runtime.shutdown();
    });
    final ready = (await tester.runAsync(runtime.bootstrap)) as AppRuntimeReady;
    seedTagStorageFixture(raw);
    final graphBefore = retainedTagFixtureGraph(raw);
    final router = ready.container.read(appRouterProvider);
    await tester.pumpWidget(MainApp(runtime: runtime));
    await openIntentionGraph(tester, waitFor: _until);
    await _until(tester, find.byKey(const ValueKey('catalog-open-tags')));

    final id = (IntentionId.decode(
      tagFixtureId(number),
    ) as IntentionIdDecodingSuccess).id;
    unawaited(router.push(IntentionDetailsRoute(intentionId: id)));
    final choose = find.byKey(
      const ValueKey('tag-assignments-choose'),
      skipOffstage: false,
    );
    await _until(tester, choose);
    await tester.pumpAndSettle();
    expect(find.byType(Sheet), findsNothing);
    await _tap(tester, choose);

    final homeTagId = tagFixtureId(firstTagNumber);
    final existingTagId = tagFixtureId(lastTagNumber);
    final homeRow = find.byKey(ValueKey('tags-panel-row-$homeTagId'));
    final workRow = find.byKey(ValueKey('tags-panel-row-$existingTagId'));
    await _until(tester, homeRow);
    await tester.pumpAndSettle();
    final search = find.descendant(
      of: find.byType(Sheet),
      matching: find.byType(TextField),
    );
    final localizations = AppLocalizations.of(tester.element(search));
    final storedBeforeSearch = _storedGraph(raw);
    final diagnosticsBeforeSearch = diagnostics.events;
    for (final (query, hasHome, hasWork) in [
      ('д', true, false),
      ('до', true, false),
      ('дмо', false, false),
      ('дом', true, false),
      ('спорт', false, false),
      ('раб', false, true),
      ('работ', false, true),
    ]) {
      await tester.enterText(search, query);
      await tester.pumpAndSettle();
      expect(homeRow, hasHome ? findsOneWidget : findsNothing);
      expect(workRow, hasWork ? findsOneWidget : findsNothing);
      if (hasHome) expect(_mark(tester, homeRow), TagRowSelectionMark.checked);
      if (hasWork) expect(_mark(tester, workRow), TagRowSelectionMark.none);
      if (!hasHome && !hasWork) {
        expect(
          find.text(localizations.tagsPanelCreateTag(query)),
          findsOneWidget,
        );
      }
      expect(_storedGraph(raw), storedBeforeSearch);
      expect(diagnostics.events, diagnosticsBeforeSearch);
    }
    await tester.tap(find.bySemanticsLabel(localizations.tagsPanelClearSearch));
    await tester.pumpAndSettle();
    expect(homeRow, findsOneWidget);
    expect(workRow, findsOneWidget);
    expect(_mark(tester, homeRow), TagRowSelectionMark.checked);
    expect(_storedGraph(raw), storedBeforeSearch);
    expect(diagnostics.events, diagnosticsBeforeSearch);

    // Нажатие на строку само назначает тег, отдельного действия нет.
    await tester.enterText(search, 'работ');
    await tester.pumpAndSettle();
    expect(homeRow, findsNothing);
    expect(_storedGraph(raw), storedBeforeSearch);
    expect(diagnostics.events, diagnosticsBeforeSearch);
    await _tap(tester, workRow);
    await _waitFor(tester, () => _assigned(raw, existingTagId, number));
    await _waitFor(
      tester,
      () => _mark(tester, workRow) == TagRowSelectionMark.checked,
    );
    final storedAfterAssign = _storedGraph(raw);
    final assignmentsBefore = storedBeforeSearch['tag_assignments']!;
    expect(storedAfterAssign['tags'], storedBeforeSearch['tags']);
    expect(
      storedAfterAssign['tag_assignments']!.take(assignmentsBefore.length),
      assignmentsBefore,
    );
    expect(
      storedAfterAssign['tag_assignments'],
      hasLength(assignmentsBefore.length + 1),
    );
    expect(retainedTagFixtureGraph(raw), graphBefore);
    await _tap(tester, find.text(localizations.tagsPanelDone));
    await _until(
      tester,
      find.byKey(
        ValueKey('tag-assignment-remove-$existingTagId'),
        skipOffstage: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Sheet), findsNothing);
    expect(find.byType(SnackBar), findsNothing);

    // Созданный из строки создания тег сразу назначен этому намерению.
    await _tap(tester, choose);
    await _until(tester, homeRow);
    const newName = 'Общий тег 🏷️';
    await tester.enterText(search, newName);
    await _tap(tester, find.text(localizations.tagsPanelCreateTag(newName)));
    await _tap(
      tester,
      find.widgetWithText(FilledButton, localizations.tagEditorCreateAction),
    );
    await _waitFor(
      tester,
      () => raw.select('SELECT id FROM tags WHERE name = ?', [
        newName,
      ]).isNotEmpty,
    );
    final newTagId =
        raw.select('SELECT id FROM tags WHERE name = ?', [newName]).single['id']
            as String;
    await _waitFor(tester, () => _assigned(raw, newTagId, number));
    final newRow = find.byKey(ValueKey('tags-panel-row-$newTagId'));
    await _waitFor(
      tester,
      () =>
          newRow.evaluate().isNotEmpty &&
          _mark(tester, newRow) == TagRowSelectionMark.checked,
    );
    await tester.pumpAndSettle();
    expect(find.text(localizations.tagEditorCreateTitle), findsNothing);
    expect(tester.widgetList<TagRow>(find.byType(TagRow)).first.name, newName);
    expect(find.byType(SnackBar), findsNothing);
    await _tap(tester, find.text(localizations.tagsPanelDone));
    final remove = find.byKey(
      ValueKey('tag-assignment-remove-$newTagId'),
      skipOffstage: false,
    );
    await _until(tester, remove);
    await tester.pumpAndSettle();
    expect(find.byType(Sheet), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    await _tap(tester, remove);
    await _waitFor(tester, () => _assignments(raw, newTagId).isEmpty);
    expect(
      raw.select('SELECT id FROM tags WHERE id = ?', [newTagId]),
      hasLength(1),
    );
    expect(_assigned(raw, existingTagId, number), isTrue);
    expect(
      raw.select('SELECT id FROM daily_choices WHERE id = ?', [
        tagFixtureId(201),
      ]),
      hasLength(1),
    );
    expect(retainedTagFixtureGraph(raw), graphBefore);

    router.pop();
    await _tap(tester, find.byKey(const ValueKey('catalog-open-tags')));
    await _until(tester, find.text(newName));
    expect(find.text(newName), findsOneWidget);
    await tester.pumpAndSettle();
    final storedBeforeBrowseSearch = _storedGraph(raw);
    final catalogSearch = find.byKey(const ValueKey('tag-catalog-search'));
    for (final query in ['общ', 'спорт', 'общий']) {
      await tester.enterText(catalogSearch, query);
      await tester.pumpAndSettle();
      expect(
        find.text(newName),
        query == 'спорт' ? findsNothing : findsOneWidget,
      );
      expect(_storedGraph(raw), storedBeforeBrowseSearch);
    }
    await tester.tap(find.byTooltip(localizations.tagCatalogClearSearch));
    await tester.pumpAndSettle();
    expect(find.text(newName), findsOneWidget);
    expect(_storedGraph(raw), storedBeforeBrowseSearch);
    router.pop();
    final choiceId = (DailyChoiceId.decode(
      tagFixtureId(201),
    ) as DailyChoiceIdDecodingSuccess).id;
    unawaited(router.push(DailyChoiceDetailsRoute(choiceId: choiceId)));
    await _until(tester, find.byKey(const ValueKey('daily-choice-edit-open')));
    expect(choose, findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Map<String, List<List<Object?>>> _storedGraph(sqlite.Database raw) => {
  ...retainedTagFixtureGraph(raw),
  for (final table in ['tags', 'tag_assignments'])
    table: raw
        .select('SELECT * FROM $table ORDER BY rowid')
        .map((row) => row.values.toList())
        .toList(),
};

TagRowMark _mark(WidgetTester tester, Finder row) => tester
    .widget<TagRow>(find.descendant(of: row, matching: find.byType(TagRow)))
    .mark;

List<sqlite.Row> _assignments(sqlite.Database raw, String tagId) =>
    raw.select('SELECT * FROM tag_assignments WHERE tag_id = ?', [tagId]);

bool _assigned(sqlite.Database raw, String tagId, int number) =>
    raw.select(
      'SELECT * FROM tag_assignments WHERE tag_id = ? AND intention_id = ?',
      [tagId, tagFixtureId(number)],
    ).length ==
    1;

Future<void> _until(WidgetTester tester, Finder finder) =>
    _waitFor(tester, () => finder.evaluate().isNotEmpty);

Future<void> _waitFor(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 100 && !done(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _until(tester, finder);
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}
