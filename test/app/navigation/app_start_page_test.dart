import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_page.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/favorite/presentation/home/home_page.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/app_root_pages.dart';
import '../../support/favorite_storage_fixture.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/local_database_harness.dart';
import '../../support/tag_storage_fixture.dart';
import '../../support/in_memory_quick_creation_mode_store.dart';

/// Намерение «Гулять»: в зависимости от состава графа оно активное или
/// архивированное, с отметкой избранного или без неё.
const _walk = 1;
const _walkTitle = 'Гулять';

/// Второе активное намерение без отметки.
const _read = 2;
const _readTitle = 'Читать';

const _favoriteControl = ValueKey('intention-details-favorite-mark');

void main() {
  for (final locale in const [Locale('ru'), Locale('en')]) {
    testWidgets('первый запуск в новой установке без намерений открывает '
        'Главную с объяснением отсутствия избранных намерений на '
        '${locale.languageCode}', (tester) async {
      final harness = await _harness(tester, locale);
      final l10n = lookupAppLocalizations(locale);
      // Новая установка: хранилища ещё нет, его создаёт подготовка.
      expect(harness.databaseFile.existsSync(), isFalse);

      final app = await _launch(tester, harness);
      await _until(tester, find.text(l10n.homeEmptyNoFavorites));
      await tester.pumpAndSettle();

      _expectStartPage(tester, app);
      expect(
        find.descendant(
          of: find.byType(HomePage),
          matching: find.text(l10n.homeEmptyNoFavorites),
        ),
        findsOneWidget,
      );
      expect(_intentionCount(app.raw), 0);
      expect(tester.takeException(), isNull);
    });
  }

  group('начальная страница не зависит от намерений и избранных намерений', () {
    testWidgets('намерения без избранных', (tester) async {
      final harness = await _harness(tester, const Locale('ru'));
      final l10n = lookupAppLocalizations(const Locale('ru'));
      await _prepareStorage(tester, harness, (database) {
        _storeIntention(database, _walk, _walkTitle, archived: false);
        _storeIntention(database, _read, _readTitle, archived: false);
      });

      final app = await _launch(tester, harness);
      await _until(tester, find.text(l10n.homeEmptyNoFavorites));
      await tester.pumpAndSettle();

      _expectStartPage(tester, app);
      expect(_intentionCount(app.raw), 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('активное избранное намерение', (tester) async {
      final harness = await _harness(tester, const Locale('ru'));
      await _prepareStorage(tester, harness, (database) {
        _storeIntention(database, _walk, _walkTitle, archived: false);
        _storeIntention(database, _read, _readTitle, archived: false);
        storeFavoriteMark(
          database,
          intentionId: tagFixtureId(_walk),
          position: 1,
        );
      });

      final app = await _launch(tester, harness);
      final row = find.descendant(
        of: find.byType(HomePage),
        matching: find.text(_walkTitle),
      );
      await _until(tester, row);
      await tester.pumpAndSettle();

      _expectStartPage(tester, app);
      expect(row, findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(HomePage),
          matching: find.text(_readTitle),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('все избранные намерения архивированы', (tester) async {
      final harness = await _harness(tester, const Locale('ru'));
      final l10n = lookupAppLocalizations(const Locale('ru'));
      await _prepareStorage(tester, harness, (database) {
        _storeIntention(database, _walk, _walkTitle, archived: true);
        storeFavoriteMark(
          database,
          intentionId: tagFixtureId(_walk),
          position: 1,
        );
      });

      final app = await _launch(tester, harness);
      await _until(tester, find.text(l10n.homeEmptyAllArchived));
      await tester.pumpAndSettle();

      _expectStartPage(tester, app);
      expect(tester.takeException(), isNull);
    });
  });

  group('новый запуск на том же хранилище', () {
    testWidgets('после выбора пункта «Граф намерений» и открытой страницы '
        'намерения открывает Главную без этой страницы', (tester) async {
      final harness = await _harness(tester, const Locale('ru'));
      await _prepareStorage(tester, harness, (database) {
        _storeIntention(database, _walk, _walkTitle, archived: false);
        storeFavoriteMark(
          database,
          intentionId: tagFixtureId(_walk),
          position: 1,
        );
      });
      final homeRow = find.descendant(
        of: find.byType(HomePage),
        matching: find.text(_walkTitle),
      );

      // Первый запуск: граф намерений и страница намерения поверх него.
      final first = await _launch(tester, harness);
      await _until(tester, homeRow);
      await openIntentionGraph(
        tester,
        waitFor: _until,
        content: find.descendant(
          of: find.byType(IntentionCatalogPage),
          matching: find.text(_walkTitle),
        ),
      );
      await _tap(
        tester,
        find.descendant(
          of: find.byType(IntentionCatalogPage),
          matching: find.text(_walkTitle),
        ),
      );
      await _until(tester, find.byKey(_favoriteControl));
      await tester.pumpAndSettle();
      expect(find.byType(IntentionDetailsPage), findsOneWidget);
      expect(first.router.topRoute.name, IntentionDetailsRoute.name);
      expect(find.byType(AppNavigationBar), findsOneWidget);
      expect(_selected(tester), AppDestination.intentionGraph);

      // Полное завершение и новый запуск на том же хранилище.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(first.runtime.shutdown);
      final second = await _launch(tester, harness);
      await _until(tester, homeRow);
      await tester.pumpAndSettle();

      _expectStartPage(tester, second);
      // Список Главной прочитан из того же хранилища.
      expect(homeRow, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('после выбора пункта «Дневные выборы» открывает Главную', (
      tester,
    ) async {
      final harness = await _harness(tester, const Locale('ru'));
      final l10n = lookupAppLocalizations(const Locale('ru'));
      final explanation = find.text(l10n.homeEmptyNoFavorites);

      final first = await _launch(tester, harness);
      await _until(tester, explanation);
      await openDailyChoices(tester);
      await _until(tester, find.byType(DailyChoiceCatalogPage));
      await tester.pumpAndSettle();
      expect(_selected(tester), AppDestination.dailyChoices);
      expect(first.router.topRoute.name, DailyChoiceCatalogRoute.name);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(first.runtime.shutdown);
      final second = await _launch(tester, harness);
      await _until(tester, explanation);
      await tester.pumpAndSettle();

      _expectStartPage(tester, second);
      expect(tester.takeException(), isNull);
    });
  });
}

/// Запуск приложения на файловом хранилище [LocalDatabaseHarness].
final class _App {
  _App(this.runtime, this.raw, this.router);

  final AppRuntime runtime;
  final sqlite.Database raw;
  final AppRouter router;
}

Future<LocalDatabaseHarness> _harness(
  WidgetTester tester,
  Locale locale,
) async {
  tester.binding.platformDispatcher.localesTestValue = [locale];
  addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
  final harness = (await tester.runAsync(LocalDatabaseHarness.fileBacked))!;
  addTearDown(harness.dispose);
  return harness;
}

/// Готовит хранилище до запуска приложения: создаёт схему, записывает
/// данные [seed] и закрывает хранилище.
Future<void> _prepareStorage(
  WidgetTester tester,
  LocalDatabaseHarness harness,
  void Function(sqlite.Database database) seed,
) async {
  await tester.runAsync(() async {
    late sqlite.Database raw;
    await harness.openReadyDatabase(setup: (database) => raw = database);
    seed(raw);
    await harness.closePersistenceObjectGraph();
  });
}

/// Запускает приложение так же, как запуск процесса: подготовка хранилища
/// начинается из [MainApp], а не заранее.
Future<_App> _launch(WidgetTester tester, LocalDatabaseHarness harness) async {
  late sqlite.Database raw;
  final runtime = AppRuntime(
    quickCreationModeStore: InMemoryQuickCreationModeStore(),
    connectionFactory: () => openFileBackedLocalDatabase(
      harness.databaseFile,
      setup: (database) => raw = database,
    ),
    diagnosticsSink: InMemoryDiagnosticsSink(),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await runtime.shutdown();
  });
  final ready = await tester.runAsync(() async {
    await tester.pumpWidget(MainApp(runtime: runtime));
    return runtime.bootstrap();
  });
  final router = (ready! as AppRuntimeReady).container.read(appRouterProvider);
  return _App(runtime, raw, router);
}

/// Открыта Главная с видимой панелью и выбранным пунктом «Главная»: страниц
/// поверх оболочки нет, а каталоги в этом запуске ещё не построены.
void _expectStartPage(WidgetTester tester, _App app) {
  expect(find.byType(HomePage), findsOneWidget);
  expect(find.byType(AppNavigationBar), findsOneWidget);
  expect(_selected(tester), AppDestination.home);
  expect(app.router.current.name, AppShellRoute.name);
  expect(app.router.topRoute.name, HomeRoute.name);
  expect(app.router.stack, hasLength(1));
  expect(app.router.canPop(), isFalse);
  for (final page in [
    IntentionDetailsPage,
    IntentionCatalogPage,
    DailyChoiceCatalogPage,
  ]) {
    expect(
      find.byType(page, skipOffstage: false),
      findsNothing,
      reason: '$page',
    );
  }
}

/// Пункт, который панель показывает выбранным.
AppDestination _selected(WidgetTester tester) =>
    tester.widget<AppNavigationBar>(find.byType(AppNavigationBar)).selected;

void _storeIntention(
  sqlite.Database database,
  int number,
  String title, {
  required bool archived,
}) {
  database.execute(
    'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
    [tagFixtureId(number), title, 1, archived ? 1 : 0, number, number],
  );
}

int _intentionCount(sqlite.Database database) =>
    database.select('SELECT COUNT(*) AS count FROM intentions').single['count']
        as int;

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
