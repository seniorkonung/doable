import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/home/home_page.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/daily_choice/application/choice_path_draft.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/presentation/action_picker/daily_choice_action_picker_page.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_page.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_date_catalog_page.dart';
import 'package:doable/src/daily_choice/presentation/details/daily_choice_details_page.dart';
import 'package:doable/src/daily_choice/presentation/editor/daily_choice_creation_page.dart';
import 'package:doable/src/daily_choice/presentation/editor/daily_choice_edit_page.dart';
import 'package:doable/src/daily_choice/presentation/editor/daily_choice_path_replace_page.dart';
import 'package:doable/src/daily_choice/presentation/editor/daily_choice_path_replacement_flow.dart';
import 'package:doable/src/daily_choice/presentation/path/choice_path_page.dart';
import 'package:doable/src/daily_choice/presentation/source_picker/daily_choice_source_picker_page.dart';
import 'package:doable/src/data/local/app_database.dart'
    show openInMemoryLocalDatabase;
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_tag_conditions_section.dart';
import 'package:doable/src/intention/presentation/catalog/tag_condition_picker_page.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_page.dart';
import 'package:doable/src/intention/presentation/intention_summary_view.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/presentation/details/relation_details_page.dart';
import 'package:doable/src/long_term_relation/presentation/editor/relation_editor_page.dart';
import 'package:doable/src/long_term_relation/presentation/editor/relation_editor_state.dart';
import 'package:doable/src/long_term_relation/presentation/participant_picker/relation_participant_picker_page.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_page.dart';
import 'package:doable/src/tag/presentation/catalog/tag_selection_context.dart';
import 'package:doable/src/tag/presentation/editor/tag_editor_page.dart';
import 'package:doable/src/tag/presentation/editor/tag_editor_state.dart';
import 'package:doable/src/tag/presentation/navigation/tag_navigation_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/app_root_pages.dart';
import '../../support/daily_choice_local_date.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/tag_storage_fixture.dart';
import '../../support/in_memory_quick_creation_mode_store.dart';
import '../../support/quick_creation.dart';

part 'app_shell_page_matrix.dart';
part 'app_shell_unnamed_page_scenarios.dart';

/// Активное готовое намерение «Читать» с тегом «Дом»: исходный
/// участник связи и исходное намерение дневного выбора.
const _read = 1;

/// Активное готовое намерение «Бегать»: связанный участник связи и выбранное
/// действие дневного выбора.
const _run = 2;

/// Связь «Читать» → «Бегать» — единственный шаг пути дневного выбора.
const _relation = 101;
const _choice = 201;
const _tag = 301;

/// День дневного выбора — локальное сегодня приложения: каталог дневных
/// выборов открывается на дне с его строкой.
final _choiceDate = CalendarDate.fromParts(2026, 9, 25);

void main() {
  _registerPageMatrixTests();
  _registerUnnamedPageTests();
  test('дочерние маршруты оболочки — только три корневые страницы без '
      'собственных стеков, остальные маршруты корневые', () {
    final router = AppRouter();
    addTearDown(router.dispose);

    final rootPages = [
      for (final destination in AppDestination.values) destination.page.name,
    ];
    // Геттер маршрутов строит список заново: оболочка отличается именем.
    final routes = router.routes;
    final shell = routes.singleWhere(
      (route) => route.name == AppShellRoute.name,
    );
    expect([for (final child in shell.children!) child.name], rootPages);
    for (final child in shell.children!) {
      expect(child.hasSubTree, isFalse, reason: child.name);
    }
    // Каждый остальной маршрут открывается в корневом стеке поверх оболочки.
    final above = [
      for (final route in routes)
        if (route.name != AppShellRoute.name) route,
    ];
    expect(above, isNotEmpty);
    for (final route in above) {
      expect(route.hasSubTree, isFalse, reason: route.name);
      expect(rootPages, isNot(contains(route.name)), reason: route.name);
    }
  });

  test('создание намерения — единственный прозрачный маршрут корневого '
      'стека: он сохраняет состояние и не закрывается фоном сам, а остальные '
      'маршруты открываются непрозрачными страницами', () {
    final router = AppRouter();
    addTearDown(router.dispose);

    for (final route in router.routes) {
      if (route.name == IntentionEditorRoute.name) {
        expect(
          route.type,
          isA<CustomRouteType>()
              .having((type) => type.opaque, 'opaque', isFalse)
              .having(
                (type) => type.barrierDismissible,
                'barrierDismissible',
                isFalse,
              ),
        );
        expect(route.maintainState, isTrue);
      } else {
        expect(route.type?.opaque ?? true, isTrue, reason: route.name);
      }
    }
  });

  // Выбор любого пункта сбрасывает историю одним путём: берём переход на
  // другой пункт.
  const destination = AppDestination.dailyChoices;
  testWidgets(
    'выбор пункта ${destination.index + 1} со страницы участника удаляет '
    'незавершённую форму связи и правку намерения без сохранения',
    (tester) async {
      final router = await _start(tester);
      await _select(tester, AppDestination.intentionGraph);
      await _open(
        tester,
        _summary(IntentionCatalogPage, 'Читать'),
        IntentionDetailsPage,
      );
      await _open(
        tester,
        find.byKey(const ValueKey('relation-neighborhood-create-relation')),
        RelationEditorPage,
      );
      await _open(
        tester,
        find.byKey(const ValueKey('relation-editor-select-related')),
        RelationParticipantPickerPage,
      );
      await _tap(tester, _summary(RelationParticipantPickerPage, 'Бегать'));
      await _gone(tester, RelationParticipantPickerPage);
      await _tap(
        tester,
        find.byKey(const ValueKey('relation-editor-type-need')),
      );
      await _tap(
        tester,
        find.byKey(const ValueKey('relation-editor-priority-p2')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('relation-editor-description')),
        'Несохранённый черновик связи',
      );
      await _open(
        tester,
        find.byKey(const ValueKey('relation-editor-open-source-details')),
        IntentionDetailsPage,
      );
      _expectAboveShell(
        tester,
        IntentionDetailsPage,
        AppDestination.intentionGraph,
      );
      await _tap(tester, find.byKey(const ValueKey('intention-details-edit')));
      await tester.enterText(
        find.byKey(const ValueKey('intention-details-edit-title')),
        'Несохранённое название',
      );
      await tester.enterText(
        find.byKey(const ValueKey('intention-details-edit-description')),
        'Несохранённое описание',
      );
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      _expectAboveShell(
        tester,
        IntentionDetailsPage,
        AppDestination.intentionGraph,
      );

      await _select(tester, destination);

      _expectRootPage(tester, router, destination);
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        find.byType(RelationEditorPage, skipOffstage: false),
        findsNothing,
      );
      expect(
        find.byType(IntentionDetailsPage, skipOffstage: false),
        findsNothing,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      _expectRootPage(tester, router, AppDestination.home);
      await _select(tester, AppDestination.intentionGraph);
      await _open(
        tester,
        _summary(IntentionCatalogPage, 'Читать'),
        IntentionDetailsPage,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('intention-details-title')))
            .data,
        'Читать',
      );
      expect(find.text('Несохранённое название'), findsNothing);
      expect(find.text('Несохранённое описание'), findsNothing);
      await _open(
        tester,
        find.byKey(const ValueKey('relation-neighborhood-create-relation')),
        RelationEditorPage,
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('relation-editor-description')),
            )
            .controller!
            .text,
        isEmpty,
      );
      expect(
        find.byKey(const ValueKey('relation-editor-participant-title-related')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

/// Корневая страница каждого пункта.
const _rootPages = {
  AppDestination.home: HomePage,
  AppDestination.dailyChoices: DailyChoiceCatalogPage,
  AppDestination.intentionGraph: IntentionCatalogPage,
};

final _openTags = find.byKey(const ValueKey('catalog-open-tags'));

/// Строка связи «Читать» → «Бегать» в соседстве намерения.
final _relationRow = find.byKey(
  ValueKey('relation-neighborhood-row-${tagFixtureId(_relation)}'),
);

/// Продолжение пути по связи «Читать» → «Бегать».
final _continuePath = find.byKey(
  ValueKey('choice-path-continue-${tagFixtureId(_relation)}'),
);

IntentionId _intentionId(int number) =>
    (IntentionId.decode(tagFixtureId(number)) as IntentionIdDecodingSuccess).id;

/// Пункты панели, включая панель под открытой страницей.
final _destinations = appNavigationDestinations(skipOffstage: false);

/// Пункты панели, которые получает экранный диктор.
final _announcedDestinations = find.semantics.byPredicate(
  (node) =>
      node.role == SemanticsRole.tab &&
      AppDestination.values.any(
        (destination) =>
            node.label.split('\n').first ==
            destination.title(lookupAppLocalizations(const Locale('en'))),
      ),
  describeMatch: (_) => 'пункты панели для экранного диктора',
);

/// Строка выдачи намерений с названием [title] на странице [page].
Finder _summary(Type page, String title) => find.descendant(
  of: find.byType(page),
  matching: find.byWidgetPredicate(
    (widget) => widget is IntentionSummaryView && widget.title == title,
  ),
);

/// Размер экрана в логических пикселях.
Size _screen(WidgetTester tester) =>
    tester.view.physicalSize / tester.view.devicePixelRatio;

/// Корневая страница пункта [destination] показана без страниц поверх: панель
/// видна, показывает этот пункт выбранным и позволяет сменить его.
void _expectRootPage(
  WidgetTester tester,
  AppRouter router,
  AppDestination destination,
) {
  expect(router.canPop(), isFalse);
  expect(find.byType(_rootPages[destination]!), findsOneWidget);

  final bar = find.byType(AppNavigationBar);
  expect(bar, findsOneWidget);
  expect(tester.widget<AppNavigationBar>(bar).selected, destination);
  expect(tester.getBottomLeft(bar).dy, _screen(tester).height);
  expect(_destinations.hitTestable(), findsExactly(3));
  expect(_announcedDestinations, findsExactly(3));
}

/// Подключённые обычные страницы сохраняют панель над оболочкой.
/// Все панели сохраняют пункт [under].
void _expectAboveShell(
  WidgetTester tester,
  Type page,
  AppDestination under, {
  bool? expectedPanel,
}) {
  final top = find.byType(page);
  expect(top, findsOneWidget, reason: '$page');
  expect(tester.getRect(top), Offset.zero & _screen(tester), reason: '$page');

  final ordinary =
      expectedPanel ??
      (page == IntentionDetailsPage ||
          page == RelationDetailsPage ||
          page == DailyChoiceDetailsPage ||
          page == TagNavigationPage ||
          (page == TagCatalogPage &&
              switch (tester.widget<TagCatalogPage>(top).selectionContext) {
                TagBrowseContext() => true,
                TagAssignmentContext() || TagDraftContext() => false,
              }));
  expect(
    find.byType(AppNavigationBar),
    ordinary ? findsOneWidget : findsNothing,
    reason: '$page',
  );
  for (final rootPage in _rootPages.values) {
    expect(find.byType(rootPage), findsNothing, reason: '$page');
  }
  // Пункты панели под страницей не получают нажатий и не объявляются
  // экранным диктором.
  expect(
    _destinations.hitTestable(),
    ordinary ? findsExactly(3) : findsNothing,
    reason: '$page',
  );
  expect(
    _announcedDestinations,
    ordinary ? findsExactly(3) : findsNothing,
    reason: '$page',
  );
  // Панель под страницей сохраняет пункт корневой страницы, над которой она
  // открыта.
  for (final bar in tester.widgetList<AppNavigationBar>(
    find.byType(AppNavigationBar, skipOffstage: false),
  )) {
    expect(bar.selected, under, reason: '$page');
  }
}

/// Панель создания намерения открыта поверх каталога намерений: каталог и
/// панель основной навигации остаются видны под её модальным фоном, но не
/// принимают нажатий и не объявляются экранным диктором, а выбранным
/// остаётся пункт «Граф намерений».
void _expectCreationSheetAboveCatalog(WidgetTester tester) {
  final catalog = find.byType(IntentionCatalogPage);
  expect(catalog, findsOneWidget);
  // Панель стоит у нижнего края и оставляет шапку каталога видимой.
  final sheet = tester.getRect(
    find.byKey(const ValueKey('intention-creation-sheet')),
  );
  final catalogBar = tester.getRect(
    find.descendant(of: catalog, matching: find.byType(AppBar)),
  );
  expect(sheet.bottom, _screen(tester).height);
  expect(sheet.top, greaterThanOrEqualTo(catalogBar.bottom));

  final bar = find.byType(AppNavigationBar);
  expect(bar, findsOneWidget);
  expect(
    tester.widget<AppNavigationBar>(bar).selected,
    AppDestination.intentionGraph,
  );
  expect(_destinations, findsExactly(3));
  expect(_destinations.hitTestable(), findsNothing);
  expect(_announcedDestinations, findsNothing);
  expect(
    find.byKey(const ValueKey('catalog-filter-field')).hitTestable(),
    findsNothing,
  );
}

/// Запускает приложение на засеянном хранилище и ждёт Главную.
Future<AppRouter> _start(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  tester.binding.platformDispatcher.localesTestValue = const [Locale('en')];
  addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
  // Высокая поверхность держит соседство намерения и подробные представления
  // видимыми без прокрутки.
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  late sqlite.Database raw;
  final runtime = AppRuntime(
    quickCreationModeStore: InMemoryQuickCreationModeStore(),
    connectionFactory: () =>
        openInMemoryLocalDatabase(setup: (database) => raw = database),
    diagnosticsSink: InMemoryDiagnosticsSink(),
    dailyChoiceLocalDateSource: ControlledDailyChoiceLocalDate(_choiceDate)
        .read,
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await runtime.shutdown();
  });
  final ready = (await tester.runAsync(runtime.bootstrap)) as AppRuntimeReady;
  _seed(raw);
  await tester.pumpWidget(MainApp(runtime: runtime));
  await _until(tester, find.byType(HomePage));
  await _waitFor(
    tester,
    () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
  );
  await tester.pumpAndSettle();
  return ready.container.read(appRouterProvider);
}

/// Два намерения, связь между ними, дневной выбор по этой связи и тег:
/// каждая страница приложения получает свои данные.
void _seed(sqlite.Database database) {
  for (final (number, title) in [(_read, 'Читать'), (_run, 'Бегать')]) {
    database.execute(
      'INSERT INTO intentions (id, title, is_action_ready, is_archived, '
      'created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
      [tagFixtureId(number), title, 1, 0, number, number],
    );
  }
  database.execute(
    'INSERT INTO long_term_relations (id, source_intention_id, '
    'related_intention_id, type, priority, is_archived) '
    'VALUES (?, ?, ?, ?, ?, ?)',
    [
      tagFixtureId(_relation),
      tagFixtureId(_read),
      tagFixtureId(_run),
      'need',
      2,
      0,
    ],
  );
  database.execute(
    'INSERT INTO daily_choices (id, source_intention_id, '
    'selected_intention_id, choice_date, is_completed) VALUES (?, ?, ?, ?, ?)',
    [
      tagFixtureId(_choice),
      tagFixtureId(_read),
      tagFixtureId(_run),
      _choiceDate.toCanonicalString(),
      0,
    ],
  );
  database.execute(
    'INSERT INTO daily_choice_path_steps (id, daily_choice_id, '
    'long_term_relation_id) VALUES (?, ?, ?)',
    [tagFixtureId(211), tagFixtureId(_choice), tagFixtureId(_relation)],
  );
  database.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
    tagFixtureId(_tag),
    'Дом',
  ]);
  database.execute(
    'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
    [tagFixtureId(_tag), tagFixtureId(_read)],
  );
}

/// Выбирает пункт панели и ждёт его корневую страницу.
Future<void> _select(WidgetTester tester, AppDestination destination) async {
  await tester.tap(appNavigationDestination(destination));
  await _until(tester, find.byType(_rootPages[destination]!));
  await _waitFor(
    tester,
    () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
  );
  await tester.pumpAndSettle();
}

/// Нажимает [entry] и ждёт, пока страница [page] откроется целиком.
Future<void> _open(WidgetTester tester, Finder entry, Type page) async {
  await _tap(tester, entry);
  await _until(tester, find.byType(page));
  await tester.pumpAndSettle();
}

/// Закрывает верхнюю страницу [page] системным действием «назад».
Future<void> _close(WidgetTester tester, Type page) async {
  await tester.binding.handlePopRoute();
  await _gone(tester, page);
}

/// Закрывает системным действием «назад» все страницы поверх оболочки.
Future<void> _closeAll(WidgetTester tester) async {
  bool hasRootPage() =>
      _rootPages.values.any((page) => find.byType(page).evaluate().isNotEmpty);
  for (var page = 0; page < 12 && !hasRootPage(); page++) {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }
  expect(hasRootPage(), isTrue);
}

Future<void> _gone(WidgetTester tester, Type page) async {
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

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _until(tester, finder);
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}
