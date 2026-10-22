import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/design_system/components/tag_dot.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/app_root_pages.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/in_memory_quick_creation_mode_store.dart';
import '../support/inline_text.dart';
import '../support/tag_storage_fixture.dart';

Future<void> _until(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('Не появился элемент: $finder');
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _until(tester, finder);
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _saveName(WidgetTester tester, String name) async {
  await _until(tester, find.byKey(const ValueKey('tag-editor-name')));
  await tester.enterText(find.byKey(const ValueKey('tag-editor-name')), name);
  await _tap(tester, find.byKey(const ValueKey('tag-editor-submit')));
  for (var attempt = 0; attempt < 100; attempt++) {
    if (find.byKey(const ValueKey('tag-editor-name')).evaluate().isEmpty) {
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('Форма не закрылась после сохранения');
}

void main() {
  testWidgets('Изменение только цвета общего тега', (tester) async {
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
    await tester.runAsync(runtime.bootstrap);
    seedTagStorageFixture(raw);
    final tagId = tagFixtureId(firstTagNumber);
    final graphBefore = retainedTagFixtureGraph(raw);
    final assignmentsBefore = raw.select(
      'SELECT * FROM tag_assignments ORDER BY rowid',
    );
    expect(
      raw.select('SELECT id, name, color FROM tags WHERE id = ?', [tagId]),
      [
        {'id': tagId, 'name': 'Дом', 'color': null},
      ],
    );
    await tester.pumpWidget(MainApp(runtime: runtime));
    await openIntentionGraph(
      tester,
      waitFor: _until,
      content: findTextIgnoringInlineWidgets('Теги: Дом'),
    );
    await _tap(tester, find.byKey(const ValueKey('catalog-open-tags')));
    final row = find.byKey(ValueKey('tag-catalog-row-$tagId'));
    await _tap(
      tester,
      find.descendant(of: row, matching: find.byTooltip('Изменить тег')),
    );
    await _tap(tester, find.bySemanticsLabel('Синий'));
    await _tap(tester, find.byKey(const ValueKey('tag-editor-submit')));
    await _expectBlueDot(tester, row);
    expect(find.byKey(const ValueKey('tag-editor-name')), findsNothing);
    expect(
      raw.select('SELECT id, name, color FROM tags WHERE id = ?', [tagId]),
      [
        {'id': tagId, 'name': 'Дом', 'color': 'blue'},
      ],
    );
    expect(
      raw.select('SELECT * FROM tag_assignments ORDER BY rowid'),
      assignmentsBefore,
    );
    expect(retainedTagFixtureGraph(raw), graphBefore);

    await tester.binding.handlePopRoute();
    await _expectBlueDot(tester, findTextIgnoringInlineWidgets('Теги: Дом'));
    await _tap(tester, find.text('Намерение 1'));
    await _expectBlueDot(
      tester,
      find.byKey(ValueKey('tag-assignment-row-$tagId')),
    );
    await _tap(tester, find.byKey(ValueKey('tag-assignment-open-$tagId')));
    await _expectBlueDot(tester, findTextIgnoringInlineWidgets('Тег: Дом'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('серия назначений и снятий сохраняется без сообщений об успехе', (
    tester,
  ) async {
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
    await tester.runAsync(runtime.bootstrap);
    seedTagStorageFixture(raw);
    final completions = <GraphCommandCompletion>[];
    final subscription = runtime.commandCoordinator.completions.listen(
      completions.add,
    );
    addTearDown(subscription.cancel);
    await tester.pumpWidget(MainApp(runtime: runtime));
    await openIntentionGraph(tester, waitFor: _until);
    await _tap(tester, find.text('Намерение 1'));
    final homeRemove = find.byKey(
      ValueKey('tag-assignment-remove-${tagFixtureId(firstTagNumber)}'),
      skipOffstage: false,
    );
    final empty = find.text('Назначений тегов пока нет.', skipOffstage: false);
    await _tap(tester, homeRemove);
    await _until(tester, empty);
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar, skipOffstage: false), findsNothing);

    for (final (number, assign) in [
      (lastTagNumber, true),
      (lastTagNumber, false),
    ]) {
      final tagId = tagFixtureId(number);
      final remove = find.byKey(
        ValueKey('tag-assignment-remove-$tagId'),
        skipOffstage: false,
      );
      if (assign) {
        await _tap(
          tester,
          find.byKey(
            const ValueKey('tag-assignments-choose'),
            skipOffstage: false,
          ),
        );
        await _tap(tester, find.byKey(ValueKey('tag-catalog-row-$tagId')));
        await _tap(tester, find.byKey(const ValueKey('tag-catalog-assign')));
        await _until(tester, find.text('Назначен'));
        await _tap(tester, find.byType(BackButton));
        await _until(tester, remove);
      } else {
        await _tap(tester, remove);
        await _until(tester, empty);
      }
      await tester.pumpAndSettle();
      expect(
        raw.select(
          'SELECT * FROM tag_assignments WHERE tag_id = ? AND intention_id = ?',
          [tagId, tagFixtureId(1)],
        ),
        hasLength(assign ? 1 : 0),
      );
      expect(find.byType(SnackBar, skipOffstage: false), findsNothing);
    }

    expect(empty, findsOneWidget);
    expect(completions, hasLength(3));
    final stored = raw.select('SELECT * FROM tag_assignments ORDER BY rowid');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Намерение 1'));
    await _until(tester, empty);
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar, skipOffstage: false), findsNothing);
    expect(empty, findsOneWidget);
    expect(completions, hasLength(3));
    expect(raw.select('SELECT * FROM tag_assignments ORDER BY rowid'), stored);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'каталог: вход, создание, переименование, удаление и повтор имени',
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
      await tester.pumpWidget(MainApp(runtime: runtime));
      await openIntentionGraph(tester, waitFor: _until);
      await _tap(tester, find.byKey(const ValueKey('catalog-open-tags')));
      await _until(tester, find.byKey(const ValueKey('tag-catalog-create')));

      await _tap(tester, find.byKey(const ValueKey('tag-catalog-create')));
      await _saveName(tester, '  Straße  ');
      await _until(tester, find.text('Straße'));
      final firstId = raw.select('SELECT id FROM tags').single['id'];
      expect(raw.select('SELECT name FROM tags').single['name'], 'Straße');

      await _tap(tester, find.byKey(const ValueKey('tag-catalog-create')));
      await _until(tester, find.byKey(const ValueKey('tag-editor-name')));
      await tester.enterText(
        find.byKey(const ValueKey('tag-editor-name')),
        'STRASSE',
      );
      await _tap(tester, find.byKey(const ValueKey('tag-editor-submit')));
      await _until(
        tester,
        find.byKey(const ValueKey('tag-editor-use-existing')),
      );
      expect(raw.select('SELECT id FROM tags'), hasLength(1));
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('tag-editor-name')))
            .controller!
            .text,
        'STRASSE',
      );
      await _tap(tester, find.byKey(const ValueKey('tag-editor-cancel')));
      await _until(tester, find.text('Straße'));

      await _tap(tester, find.byIcon(Icons.edit_outlined));
      await _saveName(tester, 'Быт 🏠');
      await _until(tester, find.text('Быт 🏠'));
      expect(find.text('Straße'), findsNothing);
      expect(raw.select('SELECT id FROM tags').single['id'], firstId);

      final delete = find.byKey(ValueKey('tag-catalog-delete-$firstId'));
      await _tap(tester, delete);
      await _until(tester, find.byKey(const ValueKey('tag-delete-scope')));
      expect(find.textContaining('Быт 🏠'), findsWidgets);
      await _tap(tester, find.byKey(const ValueKey('tag-delete-confirm')));
      for (
        var attempt = 0;
        attempt < 100 && raw.select('SELECT id FROM tags').isNotEmpty;
        attempt++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(raw.select('SELECT id FROM tags'), isEmpty);
      await tester.pumpAndSettle();
      expect(find.text('Быт 🏠'), findsNothing);
      expect(delete, findsNothing);

      await _tap(tester, find.byKey(const ValueKey('tag-catalog-create')));
      await _saveName(tester, 'Быт 🏠');
      await _until(tester, find.text('Быт 🏠'));
      expect(raw.select('SELECT id FROM tags'), hasLength(1));
      expect(raw.select('SELECT id FROM tags').single['id'], isNot(firstId));
      tester.binding.platformDispatcher.localesTestValue = [const Locale('en')];
      await tester.pumpAndSettle();
      expect(find.text('Быт 🏠'), findsOneWidget);
      expect(raw.select('SELECT name FROM tags').single['name'], 'Быт 🏠');
      expect(find.text('Tags'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _expectBlueDot(WidgetTester tester, Finder view) async {
  final dot = find.descendant(
    of: view,
    matching: find.byWidgetPredicate(
      (widget) => widget is TagDot && widget.color == DoableTagColor.blue,
    ),
  );
  await _until(tester, dot);
  await tester.ensureVisible(dot);
  await tester.pumpAndSettle();
  expect(dot, findsOneWidget);
  expect(
    tester.renderObject(dot),
    paints..circle(color: DoableColors.light.tagBlue),
  );
}
