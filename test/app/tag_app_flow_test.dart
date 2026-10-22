import 'dart:ui' show CheckedState;

import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/design_system/components/sheet.dart';
import 'package:doable/src/design_system/components/tag_dot.dart';
import 'package:doable/src/design_system/components/tag_row.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/app_root_pages.dart';
import '../support/graph_seed.dart';
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

// Строка отмечена по семантике: название — только название тега, а отметку
// передаёт отмеченное состояние.
Finder _checkedRow(Finder row, String name) => find.descendant(
  of: row,
  matching: find.byElementPredicate((element) {
    final data = element.renderObject?.debugSemantics?.getSemanticsData();
    return data != null &&
        data.label == name &&
        data.flagsCollection.isChecked == CheckedState.isTrue;
  }, description: 'отмеченная строка тега «$name»'),
  matchRoot: true,
);

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
  await tester.pump();
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
    final raw = await _launch(tester);
    final tagId = tagFixtureId(firstTagNumber);
    final graphBefore = retainedTagFixtureGraph(raw);
    final assignmentsBefore = _assignments(raw);
    final tagBefore = _tagRow(raw, tagId);
    expect(tagBefore['color'], isNull);
    await _openRequiredHomeIntention(tester);

    final row = _panelRow(tagId);
    await _chooseFromMenu(tester, row, 'Изменить тег');
    await _tap(tester, find.bySemanticsLabel('Синий').last);
    await _submitTagSheet(tester, 'Сохранить');
    await _expectBlueDot(tester, row);
    await _expectBlueDot(tester, _assignmentRow(tagId));
    expect(_tagRow(raw, tagId), {...tagBefore, 'color': 'blue'});
    expect(_assignments(raw), assignmentsBefore);
    expect(retainedTagFixtureGraph(raw), graphBefore);

    await _closePanelAndPage(tester);
    await tester.ensureVisible(_conditionLabel);
    await tester.pumpAndSettle();
    await _expectBlueDot(tester, _conditionLabel);
    await _expectBlueDot(tester, findTextIgnoringInlineWidgets('Теги: Дом'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Общее переименование', (tester) async {
    final raw = await _launch(tester);
    final tagId = tagFixtureId(firstTagNumber);
    final graphBefore = retainedTagFixtureGraph(raw);
    final assignmentsBefore = _assignments(raw);
    final tagBefore = _tagRow(raw, tagId);
    await _openRequiredHomeIntention(tester);

    final row = _panelRow(tagId);
    await _chooseFromMenu(tester, row, 'Изменить тег');
    await tester.enterText(_tagSheetName, 'Быт');
    await tester.pump();
    await _submitTagSheet(tester, 'Сохранить');
    await _until(tester, find.descendant(of: row, matching: find.text('Быт')));
    expect(_panelNames(tester), ['Быт', 'Работа']);
    await _until(
      tester,
      find.descendant(of: _assignmentRow(tagId), matching: find.text('Быт')),
    );
    // Идентичность, место и оба назначения, в том числе архивированному
    // намерению, сохранены.
    expect(_tagRow(raw, tagId), {...tagBefore, 'name': 'Быт'});
    expect(_assignments(raw), assignmentsBefore);
    expect(retainedTagFixtureGraph(raw), graphBefore);

    await _closePanelAndPage(tester);
    await _until(tester, findTextIgnoringInlineWidgets('Теги: Быт'));
    expect(
      textIgnoringInlineWidgets(tester.widget<Text>(_conditionLabel)),
      'Быт',
    );
    expect(findTextIgnoringInlineWidgets('Теги: Дом'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Копия встаёт после оригинала без его назначений', (
    tester,
  ) async {
    final homeId = tagFixtureId(firstTagNumber);
    final raw = await _launch(
      tester,
      adjust: (raw) => raw.execute('UPDATE tags SET color = ? WHERE id = ?', [
        'blue',
        homeId,
      ]),
    );
    final homeBefore = _tagRow(raw, homeId);
    final homeAssignments = _assignmentsOf(raw, homeId);
    expect(homeAssignments, hasLength(2));
    // Намерению 3 «Дом» не назначен.
    await _tap(tester, find.text('Намерение 3'));
    await _openPanel(tester);

    await _chooseFromMenu(tester, _panelRow(homeId), 'Дублировать тег');
    expect(_tagSheetNameText(tester), 'Дом 2');
    await _submitTagSheet(tester, 'Создать тег');
    await _waitFor(tester, () => _panelNames(tester).length == 3);
    expect(_panelNames(tester), ['Дом', 'Дом 2', 'Работа']);

    final copy = raw.select('SELECT id, color FROM tags WHERE name = ?', [
      'Дом 2',
    ]).single;
    final copyId = copy['id'] as String;
    expect(copy['color'], 'blue');
    await _until(tester, _checkedRow(_panelRow(copyId), 'Дом 2'));
    await _expectBlueDot(tester, _panelRow(copyId));
    await _until(tester, _assignmentRow(copyId));
    expect(_assignmentsOf(raw, copyId), [tagFixtureId(3)]);
    expect(_tagRow(raw, homeId), homeBefore);
    expect(_assignmentsOf(raw, homeId), homeAssignments);
    expect(
      raw
          .select('SELECT name FROM tags ORDER BY position')
          .map((r) => r['name']),
      ['Дом', 'Дом 2', 'Работа'],
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Успех операции в панели не объявляется сообщением', (
    tester,
  ) async {
    final raw = await _launch(tester);
    final workId = tagFixtureId(lastTagNumber);
    await _tap(tester, find.text('Намерение 1'));
    await _openPanel(tester);

    final row = _panelRow(workId);
    await _tap(tester, row);
    await _until(tester, _checkedRow(row, 'Работа'));
    await _dragToFirst(tester, row);
    await _waitFor(
      tester,
      () =>
          raw.select('SELECT name FROM tags ORDER BY position').first['name'] ==
          'Работа',
    );
    await tester.pumpAndSettle();
    expect(_panelNames(tester), ['Работа', 'Дом']);
    expect(_checkedRow(row, 'Работа'), findsWidgets);
    expect(_assignmentsOf(raw, workId), contains(tagFixtureId(1)));
    expect(find.byType(SnackBar, skipOffstage: false), findsNothing);

    await _tap(tester, find.text('Готово'));
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar, skipOffstage: false), findsNothing);
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
        final row = find.byKey(ValueKey('tags-panel-row-$tagId'));
        await _tap(tester, row);
        await _until(tester, _checkedRow(row, 'Работа'));
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar, skipOffstage: false), findsNothing);
        await _tap(tester, find.text('Готово'));
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
      await tester.pump();
      await _tap(tester, find.byKey(const ValueKey('tag-editor-submit')));
      // Занятость определяет запись, а её отказ предъявляет общая поверхность.
      await _until(
        tester,
        find.textContaining('Тег с таким названием уже есть.'),
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

/// Запускает приложение над фикстурой тегов, к которой [adjust] может
/// добавить изменения, и открывает каталог намерений.
Future<sqlite.Database> _launch(
  WidgetTester tester, {
  void Function(sqlite.Database raw)? adjust,
}) async {
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
  if (adjust != null) seedRawGraph(raw, () => adjust(raw));
  await tester.pumpWidget(MainApp(runtime: runtime));
  await openIntentionGraph(tester, waitFor: _until);
  return raw;
}

/// Ставит в поиске каталога намерений условие «должен быть Дом» и открывает
/// панель тегов со страницы активного намерения с этим тегом.
Future<void> _openRequiredHomeIntention(WidgetTester tester) async {
  await _until(tester, findTextIgnoringInlineWidgets('Теги: Дом'));
  await _tap(
    tester,
    find.byKey(const ValueKey('intention-tag-conditions-add')),
  );
  await _tap(
    tester,
    find.byKey(
      ValueKey(
        'tag-condition-picker-mustBePresent-${tagFixtureId(firstTagNumber)}',
      ),
    ),
  );
  await _until(tester, _conditionLabel);
  await _until(tester, findTextIgnoringInlineWidgets('Теги: Дом'));
  await _tap(tester, find.text('Намерение 1'));
  await _openPanel(tester);
}

Future<void> _openPanel(WidgetTester tester) async {
  await _tap(
    tester,
    find.byKey(const ValueKey('tag-assignments-choose'), skipOffstage: false),
  );
  await _until(tester, find.text('Готово'));
  await tester.pumpAndSettle();
}

/// Закрывает панель кнопкой «Готово», а страницу намерения — «назад».
Future<void> _closePanelAndPage(WidgetTester tester) async {
  await _tap(tester, find.text('Готово'));
  await tester.pumpAndSettle();
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

/// Удерживает строку панели и выбирает пункт меню тега.
Future<void> _chooseFromMenu(
  WidgetTester tester,
  Finder row,
  String action,
) async {
  await _until(tester, row);
  await tester.longPress(row);
  await tester.pumpAndSettle();
  await tester.tap(find.text(action));
  await tester.pumpAndSettle();
}

/// Отправляет лист тега поверх панели и дожидается его закрытия.
Future<void> _submitTagSheet(WidgetTester tester, String action) async {
  await tester.tap(
    find.descendant(
      of: find.byType(Sheet).last,
      matching: find.widgetWithText(FilledButton, action),
    ),
  );
  await tester.pump();
  await _waitFor(tester, () => find.byType(Sheet).evaluate().length == 1);
  await tester.pumpAndSettle();
}

/// Перетаскивает строку панели за ручку выше первой строки и отпускает её.
Future<void> _dragToFirst(WidgetTester tester, Finder row) async {
  final grip = find.descendant(
    of: row,
    matching: find.byWidgetPredicate(
      (widget) => widget is DoableIcon && widget.icon == DoableIconData.grip,
    ),
  );
  final first = find.byType(TagRow).first;
  final distance = tester.getTopLeft(first).dy - tester.getCenter(grip).dy - 20;
  final drag = await tester.startGesture(tester.getCenter(grip));
  for (var step = 0; step < 10; step++) {
    await drag.moveBy(Offset(0, distance / 10));
    await tester.pump();
  }
  await drag.up();
  await tester.pumpAndSettle();
}

Future<void> _waitFor(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 100 && !done(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue);
}

Finder _panelRow(String tagId) => find.byKey(ValueKey('tags-panel-row-$tagId'));

Finder _assignmentRow(String tagId) =>
    find.byKey(ValueKey('tag-assignment-row-$tagId'));

/// Подпись условия по тегу: нажатие на результат прокручивает каталог
/// намерений, и условия уходят за верхний край страницы.
final _conditionLabel = find.byKey(
  const ValueKey('intention-tag-condition-label'),
  skipOffstage: false,
);

/// Поле названия листа тега, открытого поверх панели.
final _tagSheetName = find.descendant(
  of: find.byType(Sheet).last,
  matching: find.byType(TextField),
);

String _tagSheetNameText(WidgetTester tester) =>
    tester.widget<TextField>(_tagSheetName).controller!.text;

List<String> _panelNames(WidgetTester tester) => [
  for (final row in tester.widgetList<TagRow>(find.byType(TagRow))) row.name,
];

Map<String, Object?> _tagRow(sqlite.Database raw, String tagId) => {
  ...raw.select(
    'SELECT creation_sequence, id, name, color, position FROM tags '
    'WHERE id = ?',
    [tagId],
  ).single,
};

List<sqlite.Row> _assignments(sqlite.Database raw) =>
    raw.select('SELECT * FROM tag_assignments ORDER BY rowid');

List<Object?> _assignmentsOf(sqlite.Database raw, String tagId) => [
  for (final row in raw.select(
    'SELECT intention_id FROM tag_assignments WHERE tag_id = ? '
    'ORDER BY intention_id',
    [tagId],
  ))
    row['intention_id'],
];
