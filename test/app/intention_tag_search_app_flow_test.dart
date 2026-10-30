import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/quick_creation/quick_creation_daily_choice_start_sheet.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:doable/src/daily_choice/application/choice_path_draft.dart';
import 'package:doable/src/daily_choice/presentation/action_picker/daily_choice_action_picker_page.dart';
import 'package:doable/src/design_system/components/filter_button.dart';
import 'package:doable/src/design_system/components/picker_row.dart';
import 'package:doable/src/design_system/components/search_field.dart';
import 'package:doable/src/design_system/components/tag_row.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/intention/application/intention_catalog.dart'
    show IntentionScope;
import 'package:doable/src/intention/presentation/catalog/intention_tag_conditions_view_model.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/presentation/assignments/tag_assignments_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/app_root_pages.dart';
import '../support/graph_seed.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/intention_catalog_controls.dart';
import '../support/tag_storage_fixture.dart';
import '../support/in_memory_quick_creation_mode_store.dart';
import '../support/quick_creation.dart';
import '../support/tag_positions.dart';

const _health = 301;
const _sport = 302;
const _rest = 303;

/// Связь сохранённого дневного пути: её участники защищены от замены.
const _pathRelation = 101;
const _archivedRelation = 102;
const _activeRelation = 103;
const _dailyChoice = 201;

/// Строка результата: название и строка тегов так, как они показаны.
typedef _Row = (String title, String tags);

void main() {
  testWidgets(
    'каталог совместно применяет название, обязательные и исключённые теги',
    (tester) async {
      final app = await _App.pump(tester, const Locale('ru'));
      final l10n = app.l10n;
      final before = _storedGraph(app.raw);
      final changesBefore = _connectionChanges(app.raw);
      final health = l10n.intentionSummaryTags('Здоровье');
      final healthRest = l10n.intentionSummaryTags('Здоровье, Отдых');
      final all = l10n.intentionSummaryTags('Здоровье, Спорт, Отдых');

      // Теги видны и без условий; одноимённые намерения остаются отдельными.
      await _expectResults(tester, [
        ('Ходить в парк', healthRest),
        ('Гулять без тегов', l10n.intentionSummaryNoTags),
        ('Читать в тишине', healthRest),
        ('Ходить в зал', all),
        ('Ходить до магазина', health),
        ('Ходить в парк', healthRest),
      ]);
      expect(intentionCatalogTotal(6), findsOneWidget);
      expect(shownIntentionCatalogParameters(tester).tagConditions, 0);

      // Поиск только по обязательным тегам.
      await _addCondition(tester, l10n, _health, present: true);
      await _addCondition(tester, l10n, _rest, present: true);
      await _expectResults(tester, [
        ('Ходить в парк', healthRest),
        ('Читать в тишине', healthRest),
        ('Ходить в зал', all),
        ('Ходить в парк', healthRest),
      ]);
      await _addCondition(tester, l10n, _sport, present: false);
      expect(shownIntentionCatalogParameters(tester).tagConditions, 3);
      await _expectResults(tester, [
        ('Ходить в парк', healthRest),
        ('Читать в тишине', healthRest),
        ('Ходить в парк', healthRest),
      ]);

      // Название, обязательные и исключённые теги действуют одновременно.
      await enterIntentionCatalogTitle(tester, 'ходить');
      await _expectResults(tester, [
        ('Ходить в парк', healthRest),
        ('Ходить в парк', healthRest),
      ]);
      expect(intentionCatalogTotal(2), findsOneWidget);

      // Смена охвата сохраняет совместный фильтр.
      await selectIntentionCatalogScope(
        tester,
        IntentionScope.archived,
        tap: _tap,
      );
      await _expectResults(tester, [('Ходить в парк', healthRest)]);
      expect(intentionCatalogTotal(1), findsOneWidget);
      expect(shownIntentionCatalogParameters(tester).tagConditions, 3);
      await selectIntentionCatalogScope(
        tester,
        IntentionScope.active,
        tap: _tap,
      );
      await _expectResults(tester, [
        ('Ходить в парк', healthRest),
        ('Ходить в парк', healthRest),
      ]);

      // Панель отмечает текущие условия, а «назад» закрывает её, не меняя
      // условий.
      await _openFilterPanel(tester);
      expect(_panelMarks(tester), [
        TagRowFilterMark.mustBePresent,
        TagRowFilterMark.mustBeAbsent,
        TagRowFilterMark.mustBePresent,
      ]);
      await tester.binding.handlePopRoute();
      await _waitFor(tester, () => find.byType(TagRow).evaluate().isEmpty);
      await tester.pumpAndSettle();
      expect(shownIntentionCatalogParameters(tester).tagConditions, 3);

      // Панель меняет надобность по кругу: исключённый тег снова становится
      // обязательным через состояние без условия.
      await _openFilterPanel(tester);
      await _cycle(tester, _sport, TagRowFilterMark.none);
      expect(shownIntentionCatalogParameters(tester).tagConditions, 2);
      await _cycle(tester, _sport, TagRowFilterMark.mustBePresent);
      expect(shownIntentionCatalogParameters(tester).tagConditions, 3);
      await _expectResults(tester, [('Ходить в зал', all)]);
      await _cycle(tester, _sport, TagRowFilterMark.mustBeAbsent);
      expect(shownIntentionCatalogParameters(tester).tagConditions, 3);
      await _expectResults(tester, [
        ('Ходить в парк', healthRest),
        ('Ходить в парк', healthRest),
      ]);
      await _closeFilterPanel(tester, l10n);

      // Поиск только с исключением допускает намерение без тегов.
      await enterIntentionCatalogTitle(tester, '');
      await removeIntentionCatalogTagCondition(
        tester,
        _tagId(_health),
        IntentionTagRequirement.mustBePresent,
        tap: _tap,
        waitFor: _until,
      );
      await removeIntentionCatalogTagCondition(
        tester,
        _tagId(_rest),
        IntentionTagRequirement.mustBePresent,
        tap: _tap,
        waitFor: _until,
      );
      expect(shownIntentionCatalogParameters(tester).tagConditions, 1);
      await _expectResults(tester, [
        ('Ходить в парк', healthRest),
        ('Гулять без тегов', l10n.intentionSummaryNoTags),
        ('Читать в тишине', healthRest),
        ('Ходить до магазина', health),
        ('Ходить в парк', healthRest),
      ]);

      // Пустая выдача по условиям отличается от пустого охвата.
      await _openFilterPanel(tester);
      await _cycle(tester, _sport, TagRowFilterMark.none);
      await _cycle(tester, _sport, TagRowFilterMark.mustBePresent);
      await _closeFilterPanel(tester, l10n);
      await _addCondition(tester, l10n, _health, present: false);
      await _until(tester, find.text(l10n.intentionPickerNoIntentionsByTags));
      expect(find.text(l10n.intentionCatalogNoIntentionsTitle), findsNothing);
      expect(intentionCatalogRows, findsNothing);

      // Поиск не выполняет команд тегов и не меняет граф.
      expect(_storedGraph(app.raw), before);
      expect(_connectionChanges(app.raw), changesBefore);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Удаление обязательного тега расширяет выдачу', (tester) async {
    final app = await _App.pump(tester, const Locale('ru'));
    final l10n = app.l10n;
    final healthRest = l10n.intentionSummaryTags('Здоровье, Отдых');
    final rest = l10n.intentionSummaryTags('Отдых');
    final health = tagFixtureId(_health);
    await _addCondition(tester, l10n, _health, present: true);
    await _addCondition(tester, l10n, _sport, present: false);
    await _expectResults(tester, [
      ('Ходить в парк', healthRest),
      ('Читать в тишине', healthRest),
      ('Ходить до магазина', l10n.intentionSummaryTags('Здоровье')),
      ('Ходить в парк', healthRest),
    ]);
    await _tap(tester, find.text('Читать в тишине'));
    await _openPanel(tester, l10n);

    await _chooseFromMenu(tester, _panelRow(_health), l10n.tagsPanelDeleteTag);
    await _tap(tester, find.text(l10n.tagsPanelDeleteConfirm));
    await _waitFor(tester, () => _panelRow(_health).evaluate().isEmpty);
    expect(_panelNames(tester), ['Спорт', 'Отдых']);
    await _waitFor(tester, () => _assignmentRow(_health).evaluate().isEmpty);
    expect(_assignmentRow(_rest), findsOneWidget);
    expect(
      app.raw.select('SELECT * FROM tags WHERE id = ?', [health]),
      isEmpty,
    );
    expect(
      app.raw.select('SELECT * FROM tag_assignments WHERE tag_id = ?', [
        health,
      ]),
      isEmpty,
    );

    await _closePanelAndPage(tester, l10n);
    expect(shownIntentionCatalogParameters(tester).tagConditions, 1);
    await _expectResults(tester, [
      ('Ходить в парк', rest),
      ('Гулять без тегов', l10n.intentionSummaryNoTags),
      ('Читать в тишине', rest),
      ('Ходить до магазина', l10n.intentionSummaryNoTags),
      ('Ходить в парк', rest),
    ]);
    expect(find.byType(SnackBar, skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Нажатия переключают надобность по кругу', (tester) async {
    final app = await _App.pump(tester, const Locale('ru'));
    final l10n = app.l10n;
    final healthRest = l10n.intentionSummaryTags('Здоровье, Отдых');
    final all = l10n.intentionSummaryTags('Здоровье, Спорт, Отдых');
    final health = l10n.intentionSummaryTags('Здоровье');
    await _openFilterPanel(tester);

    await _cycle(tester, _sport, TagRowFilterMark.mustBePresent);
    expect(shownIntentionCatalogParameters(tester).tagConditions, 1);
    await _expectResults(tester, [('Ходить в зал', all)]);

    await _cycle(tester, _sport, TagRowFilterMark.mustBeAbsent);
    expect(shownIntentionCatalogParameters(tester).tagConditions, 1);
    await _expectResults(tester, [
      ('Ходить в парк', healthRest),
      ('Гулять без тегов', l10n.intentionSummaryNoTags),
      ('Читать в тишине', healthRest),
      ('Ходить до магазина', health),
      ('Ходить в парк', healthRest),
    ]);

    await _cycle(tester, _sport, TagRowFilterMark.none);
    expect(shownIntentionCatalogParameters(tester).tagConditions, 0);
    await _expectResults(tester, [
      ('Ходить в парк', healthRest),
      ('Гулять без тегов', l10n.intentionSummaryNoTags),
      ('Читать в тишине', healthRest),
      ('Ходить в зал', all),
      ('Ходить до магазина', health),
      ('Ходить в парк', healthRest),
    ]);
    expect(find.byType(TagRow), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('«Сбросить» снимает все условия по тегам', (tester) async {
    final app = await _App.pump(tester, const Locale('ru'));
    final l10n = app.l10n;
    final healthRest = l10n.intentionSummaryTags('Здоровье, Отдых');
    await enterIntentionCatalogTitle(tester, 'ходить');
    await _openFilterPanel(tester);
    await _cycle(tester, _health, TagRowFilterMark.mustBePresent);
    await _cycle(tester, _sport, TagRowFilterMark.mustBePresent);
    await _cycle(tester, _sport, TagRowFilterMark.mustBeAbsent);
    await _expectResults(tester, [
      ('Ходить в парк', healthRest),
      ('Ходить до магазина', l10n.intentionSummaryTags('Здоровье')),
      ('Ходить в парк', healthRest),
    ]);

    await _tap(tester, find.text(l10n.tagsPanelResetConditions));
    await _waitFor(
      tester,
      () => find.text(l10n.tagsPanelResetConditions).evaluate().isEmpty,
    );

    expect(shownIntentionCatalogParameters(tester).tagConditions, 0);
    expect(_panelMarks(tester), everyElement(TagRowFilterMark.none));
    await _expectResults(tester, [
      ('Ходить в парк', healthRest),
      ('Ходить в зал', l10n.intentionSummaryTags('Здоровье, Спорт, Отдых')),
      ('Ходить до магазина', l10n.intentionSummaryTags('Здоровье')),
      ('Ходить в парк', healthRest),
    ]);
    expect(shownIntentionCatalogParameters(tester).titleFilter, 'ходить');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Созданный в фильтре тег становится условием', (tester) async {
    final app = await _App.pump(tester, const Locale('ru'));
    final l10n = app.l10n;
    final assignmentsBefore = _assignments(app.raw);
    await _openFilterPanel(tester);

    await tester.enterText(
      find.descendant(
        of: find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(SearchField),
        ),
        matching: find.byType(TextField),
      ),
      'Парк',
    );
    await tester.pump();
    await _tap(tester, find.text(l10n.tagsPanelCreateTag('Парк')));
    final createAction = find.widgetWithText(
      FilledButton,
      l10n.tagEditorCreateAction,
    );
    await _until(tester, createAction);
    await tester.pumpAndSettle();
    await _tap(tester, createAction);
    await _waitFor(
      tester,
      () =>
          _panelNames(tester).firstOrNull == 'Парк' &&
          _panelMarks(tester).first == TagRowFilterMark.mustBePresent,
    );
    await tester.pumpAndSettle();

    expect(_panelNames(tester), ['Парк', 'Здоровье', 'Спорт', 'Отдых']);
    expect(shownIntentionCatalogParameters(tester).tagConditions, 1);
    await _until(tester, find.text(l10n.intentionPickerNoIntentionsByTags));
    expect(intentionCatalogRows, findsNothing);
    // Создание в фильтре не назначает тег ни одному намерению.
    expect(_assignments(app.raw), assignmentsBefore);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Удаление снимает условие и в другом открытом поиске', (
    tester,
  ) async {
    final app = await _App.pump(tester, const Locale('ru'));
    final l10n = app.l10n;
    const actions = DailyChoiceActionPickerPage;
    final healthRest = l10n.intentionSummaryTags('Здоровье, Отдых');
    final health = l10n.intentionSummaryTags('Здоровье');
    await _addCondition(tester, l10n, _sport, present: true);
    await _expectResults(tester, [
      ('Ходить в зал', l10n.intentionSummaryTags('Здоровье, Спорт, Отдых')),
    ]);
    await openQuickCreation(
      tester,
      QuickCreationMode.dailyChoice,
      openedPage: find.byType(QuickCreationDailyChoiceStartSheet),
      wait: _until,
    );
    await chooseQuickCreationDailyChoiceStart(
      tester,
      ChoicePathDraftDirection.bottomUp,
      openedPage: find.byKey(const ValueKey('daily-choice-action-filter')),
      wait: _until,
    );
    await _addCondition(
      tester,
      l10n,
      _sport,
      present: false,
      opener: _filterButton,
    );
    expect(tester.widget<FilterButton>(_filterButton).count, 1);

    await _openFilterPanel(tester, opener: _filterButton);
    await _chooseFromMenu(tester, _panelRow(_sport), l10n.tagsPanelDeleteTag);
    await _tap(tester, find.text(l10n.tagsPanelDeleteConfirm));
    await _waitFor(tester, () => _panelRow(_sport).evaluate().isEmpty);
    await _closeFilterPanel(tester, l10n);

    expect(tester.widget<FilterButton>(_filterButton).count, 0);
    await _expectResults(tester, [
      ('Ходить в зал', healthRest),
      ('Ходить до магазина', health),
      ('Ходить в парк', healthRest),
    ], results: _actionResults);
    await _closeTop(tester, actions);
    expect(shownIntentionCatalogParameters(tester).tagConditions, 0);
    await _expectResults(tester, [
      ('Ходить в парк', healthRest),
      ('Гулять без тегов', l10n.intentionSummaryNoTags),
      ('Читать в тишине', healthRest),
      ('Ходить в зал', healthRest),
      ('Ходить до магазина', health),
      ('Ходить в парк', healthRest),
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Перестановка меняет порядок во всех представлениях', (
    tester,
  ) async {
    final app = await _App.pump(tester, const Locale('ru'));
    final l10n = app.l10n;
    final positionsBefore = _positions(app.raw);
    // У «Читать в тишине» назначены «Здоровье» и «Отдых», но не «Спорт».
    await _tap(tester, find.text('Читать в тишине'));
    await _openPanel(tester, l10n);

    await _dragToFirst(tester, _panelRow(_rest));
    await _waitFor(tester, () => _positions(app.raw) != positionsBefore);
    await tester.pumpAndSettle();
    expect(_panelNames(tester), ['Отдых', 'Здоровье', 'Спорт']);
    // Перестановка меняет место только переставленного тега.
    final positions = _positions(app.raw);
    expect(
      {...positions}..remove(tagFixtureId(_rest)),
      {...positionsBefore}..remove(tagFixtureId(_rest)),
    );
    // Чипы тегов идут рядами: раньше стоит чип выше или левее в том же ряду.
    await _waitFor(tester, () {
      final rest = tester.getTopLeft(_assignmentRow(_rest));
      final health = tester.getTopLeft(_assignmentRow(_health));
      return rest.dy < health.dy ||
          (rest.dy == health.dy && rest.dx < health.dx);
    });

    await _closePanelAndPage(tester, l10n);
    final restHealth = l10n.intentionSummaryTags('Отдых, Здоровье');
    await _expectResults(tester, [
      ('Ходить в парк', restHealth),
      ('Гулять без тегов', l10n.intentionSummaryNoTags),
      ('Читать в тишине', restHealth),
      ('Ходить в зал', l10n.intentionSummaryTags('Отдых, Здоровье, Спорт')),
      ('Ходить до магазина', l10n.intentionSummaryTags('Здоровье')),
      ('Ходить в парк', restHealth),
    ]);
    expect(tester.takeException(), isNull);
  });
}

final class _App {
  _App(this.raw, this.l10n);

  final sqlite.Database raw;
  final AppLocalizations l10n;

  static Future<_App> pump(WidgetTester tester, Locale locale) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.platformDispatcher.localesTestValue = [locale];
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
    expect(await tester.runAsync(runtime.bootstrap), isA<AppRuntimeReady>());
    _seed(raw);
    await tester.pumpWidget(MainApp(runtime: runtime));
    await openIntentionGraph(tester, waitFor: _until);
    await _until(tester, intentionCatalogRows);
    await tester.pumpAndSettle();
    return _App(raw, lookupAppLocalizations(locale));
  }
}

/// Намерения с тегами «Здоровье», «Спорт» и «Отдых», связи первого
/// намерения и его дневной выбор с путём по одной из активных связей.
void _seed(sqlite.Database database) {
  seedRawGraph(database, () {
    for (final (number, name) in [
      (_health, 'Здоровье'),
      (_sport, 'Спорт'),
      (_rest, 'Отдых'),
    ]) {
      database.execute(
        'INSERT INTO tags (id, name, position) VALUES (?, ?, ?)',
        [tagFixtureId(number), name, tagPositionKey(number)],
      );
    }
    for (final (number, title, ready, archived, tags) in [
      (1, 'Ходить в парк', 1, 0, [_health, _rest]),
      (2, 'Ходить до магазина', 1, 0, [_health]),
      (3, 'Ходить в зал', 1, 0, [_health, _sport, _rest]),
      (4, 'Читать в тишине', 0, 0, [_health, _rest]),
      (5, 'Ходить в парк', 1, 1, [_health, _rest]),
      (6, 'Гулять без тегов', 0, 0, <int>[]),
      (7, 'Ходить в парк', 0, 0, [_health, _rest]),
    ]) {
      database.execute(
        'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
        [tagFixtureId(number), title, ready, archived, number, number],
      );
      for (final tag in tags) {
        database.execute(
          'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
          [tagFixtureId(tag), tagFixtureId(number)],
        );
      }
    }
    for (final (number, related, archived) in [
      (_pathRelation, 2, 0),
      (_archivedRelation, 5, 1),
      (_activeRelation, 4, 0),
    ]) {
      database.execute(
        'INSERT INTO long_term_relations (id, source_intention_id, related_intention_id, type, priority, is_archived) VALUES (?, ?, ?, ?, ?, ?)',
        [
          tagFixtureId(number),
          tagFixtureId(1),
          tagFixtureId(related),
          'need',
          2,
          archived,
        ],
      );
    }
    database.execute(
      'INSERT INTO daily_choices (id, source_intention_id, selected_intention_id, choice_date, is_completed) VALUES (?, ?, ?, ?, ?)',
      [
        tagFixtureId(_dailyChoice),
        tagFixtureId(1),
        tagFixtureId(2),
        '2026-09-25',
        0,
      ],
    );
    database.execute(
      'INSERT INTO daily_choice_path_steps (id, daily_choice_id, long_term_relation_id) VALUES (?, ?, ?)',
      [
        tagFixtureId(202),
        tagFixtureId(_dailyChoice),
        tagFixtureId(_pathRelation),
      ],
    );
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

/// Назначения тегов хранилища в порядке записи.
List<List<Object?>> _assignments(sqlite.Database raw) => raw
    .select('SELECT * FROM tag_assignments ORDER BY rowid')
    .map((row) => row.values.toList())
    .toList();

Object? _connectionChanges(sqlite.Database raw) =>
    raw.select('SELECT total_changes() AS count').single['count'];

/// Результаты каталога намерений в порядке выдачи.
List<_Row> _catalogResults(WidgetTester tester) => [
  for (final row in shownIntentionCatalogRows(tester)) (row.title, row.tags),
];

/// Результаты экрана выбора действия в порядке выдачи.
///
/// Строка экрана выбора рисует теги линией без текстовых виджетов: их состав
/// сравнивается в той же подписи, что у строки каталога.
List<_Row> _actionResults(WidgetTester tester) {
  final page = find.byType(DailyChoiceActionPickerPage);
  final l10n = AppLocalizations.of(tester.element(page));
  return [
    for (final row in tester.widgetList<PickerRow>(
      find.descendant(of: page, matching: find.byType(PickerRow)),
    ))
      (
        row.name,
        row.tags.isEmpty
            ? l10n.intentionSummaryNoTags
            : l10n.intentionSummaryTags(
                row.tags.map((tag) => tag.name).join(', '),
              ),
      ),
  ];
}

/// Дожидается результатов [expected]; по умолчанию читает выдачу каталога.
Future<void> _expectResults(
  WidgetTester tester,
  List<_Row> expected, {
  List<_Row> Function(WidgetTester tester) results = _catalogResults,
}) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    final actual = results(tester);
    if (actual.length == expected.length &&
        [
          for (var index = 0; index < actual.length; index++)
            actual[index] == expected[index],
        ].every((same) => same)) {
      break;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pumpAndSettle();
  expect(results(tester), expected);
}

/// Добавляет условие в панели фильтра: первое нажатие на тег требует его,
/// второе исключает. Затем панель закрывается кнопкой «Готово».
Future<void> _addCondition(
  WidgetTester tester,
  AppLocalizations l10n,
  int tag, {
  required bool present,
  Finder? opener,
}) async {
  await _openFilterPanel(tester, opener: opener);
  await _cycle(tester, tag, TagRowFilterMark.mustBePresent);
  if (!present) await _cycle(tester, tag, TagRowFilterMark.mustBeAbsent);
  await _closeFilterPanel(tester, l10n);
}

/// Открывает панель фильтра элементом [opener] — по умолчанию элементом
/// каталога — и ждёт строк тегов.
Future<void> _openFilterPanel(WidgetTester tester, {Finder? opener}) async {
  await _tap(tester, opener ?? intentionCatalogTagFilterControl);
  await _until(tester, find.byType(TagRow));
  await tester.pumpAndSettle();
}

/// Нажимает строку тега в панели фильтра и ждёт её отметки [mark].
Future<void> _cycle(WidgetTester tester, int tag, TagRowFilterMark mark) async {
  await _tap(tester, _panelRow(tag));
  await _waitFor(tester, () => _panelMark(tester, tag) == mark);
}

Future<void> _closeFilterPanel(
  WidgetTester tester,
  AppLocalizations l10n,
) async {
  await _tap(tester, find.text(l10n.tagsPanelDone));
  await _waitFor(tester, () => find.byType(TagRow).evaluate().isEmpty);
  await tester.pumpAndSettle();
}

/// Закрывает верхнюю страницу системным действием «назад».
/// Кнопка фильтра экрана выбора.
final _filterButton = find.byType(FilterButton);

Future<void> _closeTop(WidgetTester tester, Type page) async {
  await tester.binding.handlePopRoute();
  await _waitFor(tester, () => find.byType(page).evaluate().isEmpty);
  await tester.pumpAndSettle();
}

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

/// Нажимает элемент [finder], прокручивая к нему, только если он не
/// принимает нажатие: прокрутка к видимой строке выдачи увела бы параметры
/// поиска каталога намерений за верхний край страницы.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _until(tester, finder);
  await tester.pumpAndSettle();
  if (finder.hitTestable().evaluate().isEmpty) {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _openPanel(WidgetTester tester, AppLocalizations l10n) async {
  await _tap(
    tester,
    find.byKey(const ValueKey('tag-assignments-choose'), skipOffstage: false),
  );
  await _until(tester, find.text(l10n.tagsPanelDone));
  await tester.pumpAndSettle();
}

/// Закрывает панель кнопкой «Готово», а страницу намерения — «назад».
Future<void> _closePanelAndPage(
  WidgetTester tester,
  AppLocalizations l10n,
) async {
  await _tap(tester, find.text(l10n.tagsPanelDone));
  await tester.pumpAndSettle();
  await tester.binding.handlePopRoute();
  await _waitFor(
    tester,
    () => find.byType(TagAssignmentsSection).evaluate().isEmpty,
  );
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

TagId _tagId(int tag) =>
    (TagId.decode(tagFixtureId(tag)) as TagIdDecodingSuccess).id;

Finder _panelRow(int tag) =>
    find.byKey(ValueKey('tags-panel-row-${tagFixtureId(tag)}'));

Finder _assignmentRow(int tag) =>
    find.byKey(ValueKey('tag-assignment-row-${tagFixtureId(tag)}'));

List<String> _panelNames(WidgetTester tester) => [
  for (final row in tester.widgetList<TagRow>(find.byType(TagRow))) row.name,
];

List<TagRowMark> _panelMarks(WidgetTester tester) => [
  for (final row in tester.widgetList<TagRow>(find.byType(TagRow))) row.mark,
];

TagRowMark _panelMark(WidgetTester tester, int tag) => tester
    .widget<TagRow>(
      find.descendant(of: _panelRow(tag), matching: find.byType(TagRow)),
    )
    .mark;

/// Места тегов хранилища по их идентификаторам.
Map<String, String> _positions(sqlite.Database raw) => {
  for (final row in raw.select('SELECT id, position FROM tags'))
    row['id'] as String: row['position'] as String,
};
