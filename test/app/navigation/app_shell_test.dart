import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/navigation/app_shell_page.dart';
import 'package:doable/src/app/navigation/app_shell_tab_insets.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_page.dart';
import 'package:doable/src/data/local/app_database.dart'
    show openInMemoryLocalDatabase;
import 'package:doable/src/favorite/presentation/home/home_page.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_page.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/in_memory_quick_creation_mode_store.dart';

void main() {
  test('каждый пункт определяет собственный дочерний маршрут оболочки', () {
    expect(
      [for (final destination in AppDestination.values) destination.page.name],
      [
        HomeRoute.name,
        DailyChoiceCatalogRoute.name,
        IntentionCatalogRoute.name,
      ],
    );
  });

  testWidgets('после подготовки хранилища открыта Главная с выбранным '
      'пунктом «Главная»', (tester) async {
    final app = await _start(tester);

    expect(find.byType(HomePage), findsOneWidget);
    expect(_selected(tester), AppDestination.home);
    expect(app.router.current.name, AppShellRoute.name);
    expect(app.router.topRoute.name, HomeRoute.name);
    expect(app.router.canPop(), isFalse);
  });

  testWidgets('оболочка — колонка из области вкладок и панели без '
      'собственного Scaffold', (tester) async {
    await _start(tester);

    final shell = find.byType(AppShellPage);
    final bar = find.byType(AppNavigationBar);
    expect(find.descendant(of: shell, matching: bar), findsOneWidget);
    expect(
      find.ancestor(of: bar, matching: find.byType(Scaffold)),
      findsNothing,
    );
    // Корневая страница сохраняет собственный Scaffold.
    expect(
      find.descendant(
        of: find.byType(HomePage),
        matching: find.byType(Scaffold),
      ),
      findsOneWidget,
    );
    // Область вкладок получает замену нижних вставок под высоту панели.
    final insets = tester.widget<AppShellTabInsets>(
      find.ancestor(
        of: find.byType(HomePage),
        matching: find.byType(AppShellTabInsets),
      ),
    );
    expect(insets.barHeight, AppNavigationBar.height);
    // Панель стоит под областью вкладок у нижнего края.
    expect(
      tester.getBottomLeft(find.byType(HomePage)).dy,
      tester.getTopLeft(bar).dy,
    );
    expect(
      tester.getBottomLeft(bar).dy,
      tester.view.physicalSize.height / tester.view.devicePixelRatio,
    );
  });

  testWidgets('вкладка строится при первом выборе', (tester) async {
    await _start(tester);

    expect(_built(DailyChoiceCatalogPage), findsNothing);
    expect(_built(IntentionCatalogPage), findsNothing);

    await _select(tester, AppDestination.dailyChoices);
    expect(_built(DailyChoiceCatalogPage), findsOneWidget);
    expect(_built(IntentionCatalogPage), findsNothing);

    await _select(tester, AppDestination.intentionGraph);
    expect(_built(IntentionCatalogPage), findsOneWidget);
  });

  testWidgets('пункт календаря открывает каталог дневных выборов', (
    tester,
  ) async {
    final app = await _start(tester);

    await _select(tester, AppDestination.dailyChoices);

    expect(find.byType(DailyChoiceCatalogPage), findsOneWidget);
    expect(find.byType(HomePage), findsNothing);
    expect(_selected(tester), AppDestination.dailyChoices);
    expect(app.router.current.name, AppShellRoute.name);
    expect(app.router.topRoute.name, DailyChoiceCatalogRoute.name);
    // Создание дневного выбора остаётся действием каталога.
    expect(
      find.byKey(const ValueKey('daily-choice-create-from-action')),
      findsOneWidget,
    );
  });

  testWidgets('пункт графа открывает каталог намерений с охватом, поиском и '
      'созданием намерения', (tester) async {
    final app = await _start(tester);

    await _select(tester, AppDestination.intentionGraph);

    expect(find.byType(IntentionCatalogPage), findsOneWidget);
    expect(find.byType(HomePage), findsNothing);
    expect(_selected(tester), AppDestination.intentionGraph);
    expect(app.router.topRoute.name, IntentionCatalogRoute.name);
    expect(find.byKey(const ValueKey('catalog-scope-control')), findsOneWidget);
    expect(find.byKey(const ValueKey('catalog-filter-field')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('catalog-create-intention')),
      findsOneWidget,
    );
  });

  testWidgets('шапка каталога намерений ведёт к каталогу тегов и не ведёт к '
      'каталогу дневных выборов', (tester) async {
    final app = await _start(tester);
    await _select(tester, AppDestination.intentionGraph);

    final catalog = find.byType(IntentionCatalogPage);
    final appBar = find.descendant(of: catalog, matching: find.byType(AppBar));
    expect(
      find.descendant(of: appBar, matching: find.byType(IconButton)),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('catalog-open-daily-choices')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('catalog-open-tags')));
    await tester.pumpAndSettle();

    // Просмотр каталога тегов сохраняет постоянную навигацию.
    expect(app.router.current.name, TagCatalogRoute.name);
    expect(find.byType(TagCatalogPage), findsOneWidget);
    expect(find.byType(AppNavigationBar), findsOneWidget);
  });

  testWidgets('построенная вкладка остаётся в дереве, а невыбранная '
      'исключена из переходов Hero и анимаций', (tester) async {
    await _start(tester);
    await _select(tester, AppDestination.intentionGraph);
    final catalogState = tester.state(find.byType(IntentionCatalogPage));

    await _select(tester, AppDestination.home);

    expect(find.byType(IntentionCatalogPage), findsNothing);
    expect(_built(IntentionCatalogPage), findsOneWidget);
    expect(tester.state(_built(IntentionCatalogPage)), same(catalogState));
    expect(_heroMode(tester, IntentionCatalogPage).enabled, isFalse);
    expect(_tickerMode(tester, IntentionCatalogPage).enabled, isFalse);
    expect(_heroMode(tester, HomePage).enabled, isTrue);
    expect(_tickerMode(tester, HomePage).enabled, isTrue);

    await _select(tester, AppDestination.intentionGraph);

    expect(tester.state(find.byType(IntentionCatalogPage)), same(catalogState));
    expect(_heroMode(tester, IntentionCatalogPage).enabled, isTrue);
    expect(_tickerMode(tester, IntentionCatalogPage).enabled, isTrue);
    expect(_heroMode(tester, HomePage).enabled, isFalse);
    expect(_tickerMode(tester, HomePage).enabled, isFalse);
  });

  testWidgets('переключение пунктов идёт без анимации перехода', (
    tester,
  ) async {
    await _start(tester);

    // Один кадр без продвижения времени: страница уже показана целиком.
    await tester.tap(find.byIcon(AppDestination.dailyChoices.icon));
    await tester.pump();

    expect(find.byType(DailyChoiceCatalogPage), findsOneWidget);
    expect(find.byType(HomePage), findsNothing);
    // Между оболочкой и страницей нет перехода затуханием.
    var fades = 0;
    tester.element(find.byType(DailyChoiceCatalogPage)).visitAncestorElements((
      ancestor,
    ) {
      if (ancestor.widget is AppShellPage) return false;
      if (ancestor.widget is FadeTransition) fades += 1;
      return true;
    });
    expect(fades, 0);
  });

  testWidgets('переход с пустой Главной открывает каталог намерений с '
      'выбранным пунктом «Граф намерений»', (tester) async {
    final app = await _start(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Open intention graph'));
    await tester.pumpAndSettle();

    expect(find.byType(IntentionCatalogPage), findsOneWidget);
    expect(_selected(tester), AppDestination.intentionGraph);
    expect(app.router.current.name, AppShellRoute.name);
    expect(app.router.topRoute.name, IntentionCatalogRoute.name);
    expect(find.byType(AppNavigationBar), findsOneWidget);
  });

  for (final MapEntry(key: locale, value: names)
      in _namesBySystemLocale.entries) {
    group('системная локаль ${locale.toLanguageTag()}', () {
      testWidgets('заголовок каждой корневой страницы совпадает с названием '
          'её пункта', (tester) async {
        await _start(tester, locale: locale);

        for (final destination in AppDestination.values) {
          // Нажатие по самому пункту: значок уже выбранной Главной залит.
          await tester.tap(_destination(destination));
          await tester.pumpAndSettle();

          final appBar = find.descendant(
            of: find.byType(_rootPages[destination]!),
            matching: find.byType(AppBar),
          );
          expect(appBar, findsOneWidget, reason: destination.name);
          final title = tester.widget<AppBar>(appBar).title;
          expect(
            title,
            isA<Text>().having((text) => text.data, 'data', names[destination]),
            reason: destination.name,
          );
        }
      });

      testWidgets('долгое нажатие на пункт показывает подсказку с его '
          'названием', (tester) async {
        await _start(tester, locale: locale);

        for (final destination in AppDestination.values) {
          final name = names[destination]!;
          final gesture = await tester.startGesture(
            tester.getCenter(_destination(destination)),
          );
          await tester.pump(kLongPressTimeout + kPressTimeout);
          await gesture.up();
          await tester.pump();

          // Подсказка рисуется форматированным текстом в слое поверх
          // страницы: заголовок и скрытая подпись пункта под условие не
          // попадают.
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Text &&
                  widget.data == null &&
                  widget.textSpan?.toPlainText() == name,
            ),
            findsOneWidget,
            reason: name,
          );

          // Подсказка скрывается до проверки следующего пункта.
          await tester.pumpAndSettle(const Duration(seconds: 2));
        }
      });

      testWidgets('экранный диктор получает название пункта, а видимых '
          'подписей в панели нет', (tester) async {
        final semantics = tester.ensureSemantics();
        await _start(tester, locale: locale);

        for (final destination in AppDestination.values) {
          final name = names[destination]!;
          expect(
            tester.getSemantics(_destination(destination)).label,
            startsWith('$name\n'),
            reason: name,
          );
          // Подпись остаётся в дереве ради семантики, но не рисуется: её
          // непрозрачность равна нулю.
          final fade = tester.widget<FadeTransition>(
            find
                .ancestor(
                  of: find.descendant(
                    of: _destination(destination),
                    matching: find.text(name),
                  ),
                  matching: find.byType(FadeTransition),
                )
                .first,
          );
          expect(fade.opacity.value, 0, reason: name);
        }
        semantics.dispose();
      });
    });
  }
}

const _russianNames = {
  AppDestination.home: 'Главная',
  AppDestination.dailyChoices: 'Дневные выборы',
  AppDestination.intentionGraph: 'Граф намерений',
};

const _englishNames = {
  AppDestination.home: 'Home',
  AppDestination.dailyChoices: 'Daily choices',
  AppDestination.intentionGraph: 'Intention graph',
};

/// Названия пунктов по системной локали: любая нерусская даёт английские.
final _namesBySystemLocale = {
  const Locale('ru', 'RU'): _russianNames,
  const Locale('en', 'US'): _englishNames,
  const Locale('de', 'DE'): _englishNames,
};

/// Корневая страница каждого пункта.
const _rootPages = {
  AppDestination.home: HomePage,
  AppDestination.dailyChoices: DailyChoiceCatalogPage,
  AppDestination.intentionGraph: IntentionCatalogPage,
};

/// Запущенное приложение с готовым локальным хранилищем.
final class _App {
  _App(this.router);

  final AppRouter router;
}

/// Запускает приложение на пустом хранилище и ждёт корневую страницу.
Future<_App> _start(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
}) async {
  tester.binding.platformDispatcher.localesTestValue = [locale];
  addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
  final runtime = AppRuntime(
    quickCreationModeStore: InMemoryQuickCreationModeStore(),
    connectionFactory: () => openInMemoryLocalDatabase(),
    diagnosticsSink: InMemoryDiagnosticsSink(),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await runtime.shutdown();
  });
  await tester.pumpWidget(MainApp(runtime: runtime));
  await tester.pumpAndSettle();
  final ready = await runtime.bootstrap() as AppRuntimeReady;
  return _App(ready.container.read(appRouterProvider));
}

/// Выбирает пункт панели нажатием его значка.
Future<void> _select(WidgetTester tester, AppDestination destination) async {
  await tester.tap(
    find.descendant(
      of: find.byType(AppNavigationBar),
      matching: find.byIcon(destination.icon),
    ),
  );
  await tester.pumpAndSettle();
}

/// Пункт панели на своём месте слева направо.
Finder _destination(AppDestination destination) => find.descendant(
  of: find.byType(AppNavigationBar),
  matching: find.byType(NavigationDestination).at(destination.index),
);

/// Пункт, который панель показывает выбранным.
AppDestination _selected(WidgetTester tester) =>
    tester.widget<AppNavigationBar>(find.byType(AppNavigationBar)).selected;

/// Страница в дереве, включая невыбранную вкладку.
Finder _built(Type page) => find.byType(page, skipOffstage: false);

HeroMode _heroMode(WidgetTester tester, Type page) => tester.widget<HeroMode>(
  find
      .ancestor(
        of: _built(page),
        matching: find.byType(HeroMode, skipOffstage: false),
      )
      .first,
);

TickerMode _tickerMode(WidgetTester tester, Type page) =>
    tester.widget<TickerMode>(
      find
          .ancestor(
            of: _built(page),
            matching: find.byType(TickerMode, skipOffstage: false),
          )
          .first,
    );
