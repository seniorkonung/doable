import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar_viewport.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_page.dart';
import 'package:doable/src/daily_choice/presentation/details/daily_choice_details_page.dart';
import 'package:doable/src/data/local/app_database.dart'
    show openInMemoryLocalDatabase;
import 'package:doable/src/favorite/presentation/home/home_page.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/intention_summary_view.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/daily_choice_catalog_controls.dart';
import '../../support/daily_choice_local_date.dart';
import '../../support/favorite_storage_fixture.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/tag_storage_fixture.dart';

/// Намерения «Намерение 01» … «Намерение 40»: выдача каталога намерений
/// длиннее экрана. Первое — избранное, исходное намерение дневных выборов.
const _intentionCount = 40;

/// Намерение «Прочее», которое фильтр названия «Намерение» исключает.
const _other = 41;

/// Связь «Намерение 01» → «Намерение 02» — путь обоих дневных выборов.
const _relation = 101;
const _earlierChoice = 201;
const _laterChoice = 202;
final _earlierDate = CalendarDate.fromParts(2026, 9, 25);

/// День более позднего дневного выбора — локальное сегодня приложения:
/// каталог открывается на нём, а более ранний день выбирается отдельно.
final _laterDate = CalendarDate.fromParts(2026, 9, 26);

/// Сигнал framework платформе выводится только при целевой платформе Android.
final _android = TargetPlatformVariant.only(TargetPlatform.android);

void main() {
  testWidgets('«назад» с каталога дневных выборов выбирает Главную и '
      'сохраняет состояние каталога и его календаря', (tester) async {
    final app = await _start(tester);
    await _select(tester, AppDestination.dailyChoices);
    await selectDailyChoiceCatalogDate(tester, _earlierDate, tap: _tap);
    await _waitFor(
      tester,
      () =>
          _dailyRows.evaluate().length == 1 &&
          _dailyRowOn(_earlierDate).evaluate().length == 1,
    );
    // Раскрытый календарь показывает предыдущий месяц.
    await expandDailyChoiceCatalogCalendar(tester, tap: _tap);
    await showDailyChoiceCatalogPeriod(
      tester,
      CalendarDate.fromParts(2026, 8, 15),
      tap: _tap,
    );
    final catalog = tester.state(find.byType(DailyChoiceCatalogPage));
    final calendar = tester.state(_built(DailyChoiceCalendar));
    final viewport = shownDailyChoiceCatalogViewport(tester);
    expect(viewport.mode, DailyChoiceCalendarMode.month);
    expect(viewport.focusedDate.month, 8);

    // Framework готов обработать «назад»: платформа передаст его приложению.
    expect(app.platform.frameworkHandlesBack, isTrue);
    await _back(tester);

    _expectRootPage(tester, app.router, AppDestination.home);
    expect(app.platform.exits, 0);
    expect(app.platform.frameworkHandlesBack, isFalse);
    // Покинутая страница остаётся в дереве со своим состоянием.
    expect(tester.state(_built(DailyChoiceCatalogPage)), same(catalog));

    await _select(tester, AppDestination.dailyChoices);

    expect(tester.state(find.byType(DailyChoiceCatalogPage)), same(catalog));
    expect(tester.state(_built(DailyChoiceCalendar)), same(calendar));
    expect(shownDailyChoiceCatalogDate(tester), _earlierDate);
    expect(shownDailyChoiceCatalogViewport(tester), viewport);
    expect(_dailyRows, findsOneWidget);
    expect(_dailyRowOn(_earlierDate), findsOneWidget);
    expect(app.platform.frameworkHandlesBack, isTrue);
    expect(tester.takeException(), isNull);
  }, variant: _android);

  testWidgets('«назад» с каталога намерений выбирает Главную и сохраняет '
      'параметры и позицию каталога', (tester) async {
    final app = await _start(tester);
    await _select(tester, AppDestination.intentionGraph);
    await tester.enterText(_titleFilter, 'Намерение');
    await _until(tester, find.text('Total intentions: $_intentionCount'));
    await tester.pumpAndSettle();
    await tester.drag(_catalogList, const Offset(0, -300));
    await tester.pumpAndSettle();
    final catalog = tester.state(find.byType(IntentionCatalogPage));
    final offset = _catalogOffset(tester);
    final rows = _catalogRows(tester);
    expect(offset, greaterThan(0));
    expect(rows, isNotEmpty);

    // Framework готов обработать «назад»: платформа передаст его приложению.
    expect(app.platform.frameworkHandlesBack, isTrue);
    await _back(tester);

    _expectRootPage(tester, app.router, AppDestination.home);
    expect(app.platform.exits, 0);
    expect(app.platform.frameworkHandlesBack, isFalse);
    // Покинутая страница остаётся в дереве со своим состоянием.
    expect(tester.state(_built(IntentionCatalogPage)), same(catalog));

    await _select(tester, AppDestination.intentionGraph);

    expect(tester.state(find.byType(IntentionCatalogPage)), same(catalog));
    expect(
      tester.widget<TextField>(_titleFilter).controller!.text,
      'Намерение',
    );
    expect(find.text('Total intentions: $_intentionCount'), findsOneWidget);
    expect(_catalogOffset(tester), offset);
    expect(_catalogRows(tester), rows);
    expect(app.platform.frameworkHandlesBack, isTrue);
    expect(tester.takeException(), isNull);
  }, variant: _android);

  testWidgets('«назад» на Главной покидает приложение без перехода на другую '
      'корневую страницу', (tester) async {
    final app = await _start(tester);

    // Готовность не объявлена: «назад» остаётся платформенным выходом.
    expect(app.platform.frameworkHandlesBack, isFalse);
    await _back(tester);

    expect(app.platform.exits, 1);
    _expectRootPage(tester, app.router, AppDestination.home);
    expect(_built(DailyChoiceCatalogPage), findsNothing);
    expect(_built(IntentionCatalogPage), findsNothing);
    expect(app.platform.frameworkHandlesBack, isFalse);
    expect(tester.takeException(), isNull);
  }, variant: _android);

  for (final catalog in _catalogs) {
    testWidgets('после возврата с пункта «${_names[catalog]}» на Главную '
        'следующее «назад» покидает приложение', (tester) async {
      final app = await _start(tester);
      await _select(tester, catalog);
      expect(app.platform.frameworkHandlesBack, isTrue);

      await _back(tester);

      _expectRootPage(tester, app.router, AppDestination.home);
      expect(app.platform.exits, 0);
      // Сигнал снят: на Главной «назад» снова платформенный выход.
      expect(app.platform.frameworkHandlesBack, isFalse);

      await _back(tester);

      expect(app.platform.exits, 1);
      _expectRootPage(tester, app.router, AppDestination.home);
      expect(app.platform.frameworkHandlesBack, isFalse);
      expect(tester.takeException(), isNull);
    }, variant: _android);
  }

  testWidgets('«назад» на странице поверх Главной закрывает только её', (
    tester,
  ) async {
    final app = await _start(tester);

    await _open(tester, find.byType(HomeIntentionRow), IntentionDetailsPage);
    expect(app.platform.frameworkHandlesBack, isTrue);
    await _back(tester);

    expect(find.byType(IntentionDetailsPage), findsNothing);
    _expectRootPage(tester, app.router, AppDestination.home);
    expect(app.platform.exits, 0);
    // Страница закрыта: на Главной «назад» снова платформенный выход.
    expect(app.platform.frameworkHandlesBack, isFalse);
    expect(tester.takeException(), isNull);
  }, variant: _android);

  testWidgets('«назад» в подробном просмотре дневного выбора закрывает только '
      'его и не меняет выбранный пункт', (tester) async {
    final app = await _start(tester);
    await _select(tester, AppDestination.dailyChoices);

    await _open(
      tester,
      find.byKey(const ValueKey('daily-choice-row-1')),
      DailyChoiceDetailsPage,
    );
    expect(app.platform.frameworkHandlesBack, isTrue);
    await _back(tester);

    expect(find.byType(DailyChoiceDetailsPage), findsNothing);
    _expectRootPage(tester, app.router, AppDestination.dailyChoices);
    expect(app.platform.exits, 0);
    // Каталог без страниц поверх по-прежнему получает «назад».
    expect(app.platform.frameworkHandlesBack, isTrue);

    await _back(tester);

    _expectRootPage(tester, app.router, AppDestination.home);
    expect(app.platform.exits, 0);
    expect(app.platform.frameworkHandlesBack, isFalse);
    expect(tester.takeException(), isNull);
  }, variant: _android);

  testWidgets('«назад» в каталоге тегов поверх каталога намерений закрывает '
      'только его и не меняет выбранный пункт', (tester) async {
    final app = await _start(tester);
    await _select(tester, AppDestination.intentionGraph);

    await _open(
      tester,
      find.byKey(const ValueKey('catalog-open-tags')),
      TagCatalogPage,
    );
    expect(app.platform.frameworkHandlesBack, isTrue);
    await _back(tester);

    expect(find.byType(TagCatalogPage), findsNothing);
    _expectRootPage(tester, app.router, AppDestination.intentionGraph);
    expect(app.platform.exits, 0);
    // Каталог без страниц поверх по-прежнему получает «назад».
    expect(app.platform.frameworkHandlesBack, isTrue);

    await _back(tester);

    _expectRootPage(tester, app.router, AppDestination.home);
    expect(app.platform.exits, 0);
    expect(app.platform.frameworkHandlesBack, isFalse);
    expect(tester.takeException(), isNull);
  }, variant: _android);

  testWidgets('оболочка объявляет готовность из выбранного пункта и сама '
      'перехода не выполняет', (tester) async {
    final app = await _start(tester);

    for (final destination in [
      AppDestination.home,
      AppDestination.dailyChoices,
      AppDestination.intentionGraph,
      AppDestination.home,
    ]) {
      await _select(tester, destination);

      final declaration = _declaration(tester);
      expect(
        declaration.canPop,
        destination == AppDestination.home,
        reason: destination.name,
      );
      // Переход на Главную выполняет только маршрутизатор вкладок.
      expect(declaration.onPopInvokedWithResult, isNull);
      expect(
        app.platform.frameworkHandlesBack,
        destination != AppDestination.home,
        reason: destination.name,
      );
    }

    // Пункт выбран типизированным маршрутом, а не нажатием панели.
    await app.router.navigate(
      const AppShellRoute(children: [IntentionCatalogRoute()]),
    );
    await tester.pumpAndSettle();

    _expectRootPage(tester, app.router, AppDestination.intentionGraph);
    expect(_declaration(tester).canPop, isFalse);
    expect(app.platform.frameworkHandlesBack, isTrue);
    expect(tester.takeException(), isNull);
  }, variant: _android);
}

/// Каталоги — корневые страницы, с которых «назад» ведёт на Главную.
const _catalogs = [AppDestination.dailyChoices, AppDestination.intentionGraph];

const _names = {
  AppDestination.dailyChoices: 'Дневные выборы',
  AppDestination.intentionGraph: 'Граф намерений',
};

/// Корневая страница каждого пункта.
const _rootPages = {
  AppDestination.home: HomePage,
  AppDestination.dailyChoices: DailyChoiceCatalogPage,
  AppDestination.intentionGraph: IntentionCatalogPage,
};

final _dailyRows = find.byWidgetPredicate(
  (widget) => switch (widget.key) {
    ValueKey<String>(:final value) => value.startsWith('daily-choice-row-'),
    _ => false,
  },
);

/// Строка выдачи каталога дневных выборов с дневным выбором на [date].
Finder _dailyRowOn(CalendarDate date) => find.ancestor(
  of: find.textContaining(date.toCanonicalString()),
  matching: _dailyRows,
);

final _titleFilter = find.byKey(const ValueKey('catalog-filter-field'));

final _catalogList = find.byKey(
  const PageStorageKey<String>('intention-catalog-list'),
);

/// Обмен приложения с платформой по системному «назад».
final class _PlatformBack {
  /// Значения, переданные framework в `SystemNavigator.setFrameworkHandlesBack`.
  final handlesBack = <bool>[];

  /// Сколько раз приложение покинуто вызовом `SystemNavigator.pop`.
  var exits = 0;

  /// Последнее объявление готовности: пока оно `false`, платформа не передаёт
  /// «назад» приложению и выполняет выход сама.
  bool get frameworkHandlesBack => handlesBack.last;

  Future<Object?> handle(MethodCall call) async {
    switch (call.method) {
      case 'SystemNavigator.setFrameworkHandlesBack':
        handlesBack.add(call.arguments as bool);
      case 'SystemNavigator.pop':
        exits += 1;
    }
    return null;
  }
}

/// Запущенное приложение и наблюдаемый обмен с платформой.
final class _App {
  _App(this.router, this.platform);

  final AppRouter router;
  final _PlatformBack platform;
}

/// Запускает приложение на засеянном хранилище и ждёт Главную со списком.
Future<_App> _start(WidgetTester tester) async {
  // Framework сообщает платформе о готовности только работающему приложению.
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  tester.binding.platformDispatcher.localesTestValue = const [Locale('en')];
  addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
  // Высокая поверхность оставляет выдаче каталога намерений собственную
  // прокрутку под параметрами поиска.
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final platform = _PlatformBack();
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, platform.handle);
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
  late sqlite.Database raw;
  final runtime = AppRuntime(
    connectionFactory: () =>
        openInMemoryLocalDatabase(setup: (database) => raw = database),
    diagnosticsSink: InMemoryDiagnosticsSink(),
    dailyChoiceLocalDateSource: ControlledDailyChoiceLocalDate(_laterDate).read,
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
  return _App(ready.container.read(appRouterProvider), platform);
}

/// Намерения, одна отметка избранного, связь и два дневных выбора по ней на
/// разные даты: каждая корневая страница получает содержимое и параметры.
void _seed(sqlite.Database database) {
  for (var number = 1; number <= _intentionCount + 1; number++) {
    final title = number == _other
        ? 'Прочее'
        : 'Намерение ${number.toString().padLeft(2, '0')}';
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
    [tagFixtureId(_relation), tagFixtureId(1), tagFixtureId(2), 'need', 2, 0],
  );
  for (final (choice, date) in [
    (_earlierChoice, _earlierDate),
    (_laterChoice, _laterDate),
  ]) {
    database.execute(
      'INSERT INTO daily_choices (id, source_intention_id, '
      'selected_intention_id, choice_date, is_completed) '
      'VALUES (?, ?, ?, ?, ?)',
      [
        tagFixtureId(choice),
        tagFixtureId(1),
        tagFixtureId(2),
        date.toCanonicalString(),
        0,
      ],
    );
    database.execute(
      'INSERT INTO daily_choice_path_steps (id, daily_choice_id, '
      'long_term_relation_id) VALUES (?, ?, ?)',
      [
        tagFixtureId(choice + 10),
        tagFixtureId(choice),
        tagFixtureId(_relation),
      ],
    );
  }
  storeFavoriteMark(database, intentionId: tagFixtureId(1), position: 1);
}

/// Корневая страница пункта [destination] показана без страниц поверх, а
/// панель показывает этот пункт выбранным.
void _expectRootPage(
  WidgetTester tester,
  AppRouter router,
  AppDestination destination,
) {
  expect(router.current.name, AppShellRoute.name);
  expect(router.topRoute.name, destination.page.name);
  expect(find.byType(_rootPages[destination]!), findsOneWidget);
  final bar = find.byType(AppNavigationBar);
  expect(bar, findsOneWidget);
  expect(tester.widget<AppNavigationBar>(bar).selected, destination);
}

/// Объявление оболочки платформе: `PopScope` вокруг области вкладок и панели.
PopScope<Object?> _declaration(WidgetTester tester) => tester.widget(
  find.ancestor(
    of: find.byType(AppNavigationBar),
    matching: find.byWidgetPredicate((widget) => widget is PopScope),
  ),
);

/// Позиция прокрутки выдачи каталога намерений.
double _catalogOffset(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(of: _catalogList, matching: find.byType(Scrollable))
          .first,
    )
    .position
    .pixels;

/// Названия построенных строк выдачи каталога намерений.
List<String> _catalogRows(WidgetTester tester) => [
  for (final row in tester.widgetList<IntentionSummaryView>(
    find.descendant(
      of: _catalogList,
      matching: find.byType(IntentionSummaryView),
    ),
  ))
    row.title,
];

/// Страница в дереве, включая невыбранную вкладку.
Finder _built(Type page) => find.byType(page, skipOffstage: false);

/// Системное «назад», дошедшее до приложения.
Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
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
