import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/presentation/action_picker/daily_choice_action_picker_page.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_page.dart';
import 'package:doable/src/daily_choice/presentation/details/daily_choice_details_page.dart';
import 'package:doable/src/daily_choice/presentation/editor/daily_choice_creation_page.dart';
import 'package:doable/src/daily_choice/presentation/editor/daily_choice_edit_page.dart';
import 'package:doable/src/daily_choice/presentation/editor/daily_choice_path_replace_page.dart';
import 'package:doable/src/daily_choice/presentation/editor/daily_choice_path_replacement_flow.dart';
import 'package:doable/src/daily_choice/presentation/path/choice_path_page.dart';
import 'package:doable/src/daily_choice/presentation/source_picker/daily_choice_source_picker_page.dart';
import 'package:doable/src/data/local/app_database.dart'
    show openInMemoryLocalDatabase;
import 'package:doable/src/favorite/presentation/home/home_page.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart';
import 'package:doable/src/intention/presentation/catalog/tag_condition_picker_page.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_page.dart';
import 'package:doable/src/intention/presentation/intention_summary_view.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/long_term_relation/presentation/details/relation_details_page.dart';
import 'package:doable/src/long_term_relation/presentation/editor/relation_editor_page.dart';
import 'package:doable/src/long_term_relation/presentation/participant_picker/relation_participant_picker_page.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_page.dart';
import 'package:doable/src/tag/presentation/editor/tag_editor_page.dart';
import 'package:doable/src/tag/presentation/navigation/tag_navigation_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/daily_choice_local_date.dart';
import '../../support/favorite_storage_fixture.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/tag_storage_fixture.dart';

/// Активное готовое избранное намерение «Читать» с тегом «Дом»: исходный
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

  testWidgets('панель видна на каждой корневой странице', (tester) async {
    final router = await _start(tester);

    for (final destination in AppDestination.values) {
      await _select(tester, destination);
      _expectRootPage(tester, router, destination);
    }
  });

  testWidgets('с Главной страница намерения и подробный просмотр его связи '
      'закрывают панель, а закрытие обеих возвращает на Главную', (
    tester,
  ) async {
    final router = await _start(tester);
    _expectRootPage(tester, router, AppDestination.home);

    await _open(tester, find.byType(HomeIntentionRow), IntentionDetailsPage);
    _expectAboveShell(tester, IntentionDetailsPage, AppDestination.home);
    expect(
      router.current.argsAs<IntentionDetailsRouteArgs>().intentionId,
      _intentionId(_read),
    );

    await _open(tester, _relationRow, RelationDetailsPage);
    _expectAboveShell(tester, RelationDetailsPage, AppDestination.home);
    expect(
      router.current.argsAs<RelationDetailsRouteArgs>().relationId,
      _relationId,
    );

    // «Назад» закрывает только верхнюю страницу и не меняет выбранный пункт.
    await _close(tester, RelationDetailsPage);
    _expectAboveShell(tester, IntentionDetailsPage, AppDestination.home);
    await _close(tester, IntentionDetailsPage);
    _expectRootPage(tester, router, AppDestination.home);
    expect(tester.takeException(), isNull);
  });

  testWidgets('поиск действия из каталога дневных выборов занимает весь '
      'экран без панели, а его закрытие возвращает в каталог дневных '
      'выборов', (tester) async {
    final router = await _start(tester);
    await _select(tester, AppDestination.dailyChoices);
    _expectRootPage(tester, router, AppDestination.dailyChoices);

    await _open(tester, _createDailyChoice, DailyChoiceActionPickerPage);
    _expectAboveShell(
      tester,
      DailyChoiceActionPickerPage,
      AppDestination.dailyChoices,
    );
    expect(router.current.name, DailyChoiceActionPickerRoute.name);
    // Поиск показывает выдачу намерений, но корневой страницей не является.
    expect(_summary(DailyChoiceActionPickerPage, 'Бегать'), findsOneWidget);
    expect(find.byType(IntentionCatalogPage), findsNothing);

    await _tap(
      tester,
      find.byKey(const ValueKey('daily-choice-action-cancel')),
    );
    await _gone(tester, DailyChoiceActionPickerPage);
    _expectRootPage(tester, router, AppDestination.dailyChoices);
    expect(tester.takeException(), isNull);
  });

  testWidgets('каталог тегов из каталога намерений занимает весь экран без '
      'панели, а его закрытие возвращает в каталог намерений', (tester) async {
    final router = await _start(tester);
    await _select(tester, AppDestination.intentionGraph);
    _expectRootPage(tester, router, AppDestination.intentionGraph);

    await _open(tester, _openTags, TagCatalogPage);
    _expectAboveShell(tester, TagCatalogPage, AppDestination.intentionGraph);
    expect(router.current.name, TagCatalogRoute.name);

    await _close(tester, TagCatalogPage);
    _expectRootPage(tester, router, AppDestination.intentionGraph);
    expect(tester.takeException(), isNull);
  });

  testWidgets('страницы, открытые из каталога намерений, занимают весь экран '
      'без панели', (tester) async {
    const graph = AppDestination.intentionGraph;
    final router = await _start(tester);
    await _select(tester, graph);

    // Форма создания намерения.
    await _open(
      tester,
      find.byKey(const ValueKey('catalog-create-intention')),
      IntentionEditorPage,
    );
    _expectAboveShell(tester, IntentionEditorPage, graph);
    await _close(tester, IntentionEditorPage);
    _expectRootPage(tester, router, graph);

    // Выбор условия по тегу.
    await _open(
      tester,
      find.byKey(const ValueKey('intention-tag-conditions-add')),
      TagConditionPickerPage,
    );
    _expectAboveShell(tester, TagConditionPickerPage, graph);
    await _close(tester, TagConditionPickerPage);
    _expectRootPage(tester, router, graph);

    // Каталог тегов, форма создания тега и навигация по тегу.
    await _open(tester, _openTags, TagCatalogPage);
    await _open(
      tester,
      find.byKey(const ValueKey('tag-catalog-create')),
      TagEditorPage,
    );
    _expectAboveShell(tester, TagEditorPage, graph);
    await _close(tester, TagEditorPage);
    await _open(
      tester,
      find.byKey(ValueKey('tag-catalog-open-${tagFixtureId(_tag)}')),
      TagNavigationPage,
    );
    _expectAboveShell(tester, TagNavigationPage, graph);

    // Страница намерения из навигации по тегу и её форма изменения.
    await _open(
      tester,
      find.byKey(ValueKey(_intentionId(_read))),
      IntentionDetailsPage,
    );
    _expectAboveShell(tester, IntentionDetailsPage, graph);
    await _tap(tester, find.byKey(const ValueKey('intention-details-edit')));
    await _until(
      tester,
      find.byKey(const ValueKey('intention-details-edit-title')),
    );
    await tester.pumpAndSettle();
    _expectAboveShell(tester, IntentionDetailsPage, graph);
    await _tap(
      tester,
      find.byKey(const ValueKey('intention-details-edit-cancel')),
    );

    // Каталог тегов как выбор тегов намерения.
    await _open(
      tester,
      find.byKey(const ValueKey('tag-assignments-choose')),
      TagCatalogPage,
    );
    _expectAboveShell(tester, TagCatalogPage, graph);
    await _close(tester, TagCatalogPage);

    // Форма создания связи и выбор её участника.
    await _open(
      tester,
      find.byKey(const ValueKey('relation-neighborhood-create-relation')),
      RelationEditorPage,
    );
    _expectAboveShell(tester, RelationEditorPage, graph);
    await _open(
      tester,
      find.byKey(const ValueKey('relation-editor-select-related')),
      RelationParticipantPickerPage,
    );
    _expectAboveShell(tester, RelationParticipantPickerPage, graph);
    // Поиск участника показывает выдачу намерений, но корневой страницей
    // не является.
    expect(_summary(RelationParticipantPickerPage, 'Бегать'), findsOneWidget);
    expect(find.byType(IntentionCatalogPage), findsNothing);
    await _tap(tester, find.byKey(const ValueKey('participant-picker-cancel')));
    await _gone(tester, RelationParticipantPickerPage);
    await _close(tester, RelationEditorPage);

    // Подробный просмотр связи и форма её изменения.
    await _open(tester, _relationRow, RelationDetailsPage);
    await _open(
      tester,
      find.byKey(const ValueKey('relation-details-edit-relation')),
      RelationEditorPage,
    );
    _expectAboveShell(tester, RelationEditorPage, graph);
    await _close(tester, RelationEditorPage);
    await _close(tester, RelationDetailsPage);

    // Выбор пути от намерения.
    await _open(
      tester,
      find.byKey(const ValueKey('intention-details-choose-path')),
      ChoicePathPage,
    );
    _expectAboveShell(tester, ChoicePathPage, graph);
    expect(router.current.name, ChoicePathRoute.name);

    await _closeAll(tester);
    _expectRootPage(tester, router, graph);
    expect(tester.takeException(), isNull);
  });

  testWidgets('страницы, открытые из каталога дневных выборов, занимают весь '
      'экран без панели', (tester) async {
    const daily = AppDestination.dailyChoices;
    final router = await _start(tester);
    await _select(tester, daily);

    // Подробный просмотр дневного выбора и форма его изменения.
    await _open(
      tester,
      find.byKey(const ValueKey('daily-choice-row-1')),
      DailyChoiceDetailsPage,
    );
    _expectAboveShell(tester, DailyChoiceDetailsPage, daily);
    await _open(
      tester,
      find.byKey(const ValueKey('daily-choice-edit-open')),
      DailyChoiceEditPage,
    );
    _expectAboveShell(tester, DailyChoiceEditPage, daily);
    await _close(tester, DailyChoiceEditPage);

    // Замена пути: поиск действия, поиск исходного намерения, выбор пути и
    // подтверждение замены.
    await _open(
      tester,
      find.byKey(const ValueKey('daily-choice-replace-open')),
      DailyChoicePathReplacementFlow,
    );
    _expectAboveShell(tester, DailyChoicePathReplacementFlow, daily);
    await _open(
      tester,
      find.byKey(const ValueKey('daily-choice-replace-bottom-up')),
      DailyChoiceActionPickerPage,
    );
    _expectAboveShell(tester, DailyChoiceActionPickerPage, daily);
    await _tap(
      tester,
      find.byKey(const ValueKey('daily-choice-action-cancel')),
    );
    await _gone(tester, DailyChoiceActionPickerPage);
    await _open(
      tester,
      find.byKey(const ValueKey('daily-choice-replace-top-down')),
      DailyChoiceSourcePickerPage,
    );
    _expectAboveShell(tester, DailyChoiceSourcePickerPage, daily);
    // Поиск исходного намерения показывает выдачу намерений, но корневой
    // страницей не является.
    expect(find.byType(IntentionCatalogPage), findsNothing);
    await _open(
      tester,
      _summary(DailyChoiceSourcePickerPage, 'Читать'),
      ChoicePathPage,
    );
    _expectAboveShell(tester, ChoicePathPage, daily);
    await _tap(tester, _continuePath);
    await _tap(tester, find.byKey(const ValueKey('choice-path-select-action')));
    await _open(
      tester,
      find.byKey(const ValueKey('choice-path-open-confirmation')),
      DailyChoicePathReplacePage,
    );
    _expectAboveShell(tester, DailyChoicePathReplacePage, daily);

    await _closeAll(tester);
    _expectRootPage(tester, router, daily);

    // Создание дневного выбора: выбор пути и форма создания открываются
    // прямо из корневой страницы и тоже закрывают панель.
    await _open(tester, _createDailyChoice, DailyChoiceActionPickerPage);
    await _open(
      tester,
      _summary(DailyChoiceActionPickerPage, 'Бегать'),
      ChoicePathPage,
    );
    _expectAboveShell(tester, ChoicePathPage, daily);
    await _tap(tester, _continuePath);
    await _tap(tester, find.byKey(const ValueKey('choice-path-select-source')));
    await _open(
      tester,
      find.byKey(const ValueKey('choice-path-open-confirmation')),
      DailyChoiceCreationPage,
    );
    _expectAboveShell(tester, DailyChoiceCreationPage, daily);

    await _closeAll(tester);
    _expectRootPage(tester, router, daily);
    expect(tester.takeException(), isNull);
  });

  testWidgets('подробные представления открывают конкретные дневной выбор, '
      'намерения и связь поверх оболочки', (tester) async {
    const home = AppDestination.home;
    final router = await _start(tester);

    await _open(tester, find.byType(HomeIntentionRow), IntentionDetailsPage);

    // Дневной выбор, прямо использующий намерение, — со страницы намерения.
    await _tap(
      tester,
      find.byKey(const ValueKey('relation-neighborhood-daily-source')),
    );
    await _open(
      tester,
      find.byKey(
        ValueKey('relation-neighborhood-daily-row-${tagFixtureId(_choice)}'),
      ),
      DailyChoiceDetailsPage,
    );
    _expectAboveShell(tester, DailyChoiceDetailsPage, home);
    expect(router.current.name, DailyChoiceDetailsRoute.name);
    expect(
      router.current.argsAs<DailyChoiceDetailsRouteArgs>().choiceId,
      _choiceId,
    );

    // Намерение пути — из подробного просмотра дневного выбора.
    await _open(
      tester,
      find.byKey(const ValueKey('daily-choice-intention-2')),
      IntentionDetailsPage,
    );
    _expectAboveShell(tester, IntentionDetailsPage, home);
    expect(router.current.name, IntentionDetailsRoute.name);
    expect(
      router.current.argsAs<IntentionDetailsRouteArgs>().intentionId,
      _intentionId(_run),
    );
    await _close(tester, IntentionDetailsPage);
    _expectAboveShell(tester, DailyChoiceDetailsPage, home);

    // Связь пути — из подробного просмотра дневного выбора.
    await _open(
      tester,
      find.byKey(const ValueKey('daily-choice-relation-1')),
      RelationDetailsPage,
    );
    _expectAboveShell(tester, RelationDetailsPage, home);
    expect(router.current.name, RelationDetailsRoute.name);
    expect(
      router.current.argsAs<RelationDetailsRouteArgs>().relationId,
      _relationId,
    );

    // Участник связи — из подробного просмотра связи.
    await _open(
      tester,
      find.byKey(const ValueKey('relation-details-related-participant')),
      IntentionDetailsPage,
    );
    _expectAboveShell(tester, IntentionDetailsPage, home);
    expect(
      router.current.argsAs<IntentionDetailsRouteArgs>().intentionId,
      _intentionId(_run),
    );

    await _closeAll(tester);
    _expectRootPage(tester, router, home);
    expect(tester.takeException(), isNull);
  });
}

/// Корневая страница каждого пункта.
const _rootPages = {
  AppDestination.home: HomePage,
  AppDestination.dailyChoices: DailyChoiceCatalogPage,
  AppDestination.intentionGraph: IntentionCatalogPage,
};

final _openTags = find.byKey(const ValueKey('catalog-open-tags'));

final _createDailyChoice = find.byKey(
  const ValueKey('daily-choice-create-from-action'),
);

/// Строка связи «Читать» → «Бегать» в соседстве намерения.
final _relationRow = find.byKey(
  ValueKey('relation-neighborhood-row-${tagFixtureId(_relation)}'),
);

/// Продолжение пути по связи «Читать» → «Бегать».
final _continuePath = find.byKey(
  ValueKey('choice-path-continue-${tagFixtureId(_relation)}'),
);

final _relationId = (LongTermRelationId.decode(
  tagFixtureId(_relation),
) as LongTermRelationIdDecodingSuccess).id;

final _choiceId = (DailyChoiceId.decode(
  tagFixtureId(_choice),
) as DailyChoiceIdDecodingSuccess).id;

IntentionId _intentionId(int number) =>
    (IntentionId.decode(tagFixtureId(number)) as IntentionIdDecodingSuccess).id;

/// Пункты панели, включая панель под открытой страницей.
final _destinations = find.byType(NavigationDestination, skipOffstage: false);

/// Пункты панели, которые получает экранный диктор.
final _announcedDestinations = find.semantics.byPredicate(
  (node) => node.role == SemanticsRole.tab,
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
  expect(router.current.name, AppShellRoute.name);
  expect(router.topRoute.name, destination.page.name);
  expect(router.canPop(), isFalse);
  expect(find.byType(_rootPages[destination]!), findsOneWidget);

  final bar = find.byType(AppNavigationBar);
  expect(bar, findsOneWidget);
  expect(tester.widget<AppNavigationBar>(bar).selected, destination);
  expect(tester.getBottomLeft(bar).dy, _screen(tester).height);
  expect(_destinations.hitTestable(), findsExactly(3));
  expect(_announcedDestinations, findsExactly(3));
}

/// Страница [page] открыта поверх оболочки: занимает весь экран, панель не
/// видна, а сменить пункт нельзя ни нажатием, ни через экранный диктор.
/// Выбранным под страницей остаётся пункт [under].
void _expectAboveShell(WidgetTester tester, Type page, AppDestination under) {
  final top = find.byType(page);
  expect(top, findsOneWidget, reason: '$page');
  expect(tester.getRect(top), Offset.zero & _screen(tester), reason: '$page');

  expect(find.byType(AppNavigationBar), findsNothing, reason: '$page');
  for (final rootPage in _rootPages.values) {
    expect(find.byType(rootPage), findsNothing, reason: '$page');
  }
  // Оболочка остаётся в дереве под страницей, но её пункты не получают
  // нажатий и не объявляются экранным диктором.
  expect(_destinations, findsExactly(3), reason: '$page');
  expect(_destinations.hitTestable(), findsNothing, reason: '$page');
  expect(_announcedDestinations, findsNothing, reason: '$page');
  expect(
    tester
        .widget<AppNavigationBar>(
          find.byType(AppNavigationBar, skipOffstage: false),
        )
        .selected,
    under,
    reason: '$page',
  );
}

/// Запускает приложение на засеянном хранилище и ждёт Главную со списком.
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
  await _until(tester, find.byType(HomeIntentionRow));
  await tester.pumpAndSettle();
  return ready.container.read(appRouterProvider);
}

/// Два намерения, связь между ними, дневной выбор по этой связи, тег и
/// отметка избранного: каждая страница приложения получает свои данные.
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
  storeFavoriteMark(database, intentionId: tagFixtureId(_read), position: 1);
}

/// Выбирает пункт панели и ждёт его корневую страницу.
Future<void> _select(WidgetTester tester, AppDestination destination) async {
  await tester.tap(
    find.descendant(
      of: find.byType(AppNavigationBar),
      matching: find.byType(NavigationDestination).at(destination.index),
    ),
  );
  await _until(tester, find.byType(_rootPages[destination]!));
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
  final bar = find.byType(AppNavigationBar);
  for (var page = 0; page < 12 && bar.evaluate().isEmpty; page++) {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }
  expect(bar, findsOneWidget);
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
