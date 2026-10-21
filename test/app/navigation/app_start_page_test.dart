import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/home/home_page.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_page.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/app_root_pages.dart';
import '../../support/graph_seed.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/local_database_harness.dart';
import '../../support/tag_storage_fixture.dart';
import '../../support/in_memory_quick_creation_mode_store.dart';

/// Активное намерение «Гулять».
const _walk = 1;
const _walkTitle = 'Гулять';

/// Архивированное намерение «Читать».
const _read = 2;
const _readTitle = 'Читать';

void main() {
  testWidgets('первый запуск в новой установке без намерений открывает '
      'Главную с пустой статистикой', (tester) async {
    const locale = Locale('ru');
    final harness = await _harness(tester, locale);
    // Новая установка: хранилища ещё нет, его создаёт подготовка.
    expect(harness.databaseFile.existsSync(), isFalse);

    final app = await _launch(tester, harness);
    await _until(tester, find.byType(HomePage));
    await tester.pumpAndSettle();

    _expectStartPage(tester);
    await _expectEmptyHome(tester);
    expect(_intentionCount(app.raw), 0);
    expect(tester.takeException(), isNull);
  });

  group('начальная страница не зависит от намерений', () {
    testWidgets('намерения без дневных выборов оставляют статистику пустой', (
      tester,
    ) async {
      final harness = await _harness(tester, const Locale('ru'));
      await _prepareStorage(tester, harness, (database) {
        _storeIntention(database, _walk, _walkTitle, archived: false);
        _storeIntention(database, _read, _readTitle, archived: true);
      });

      await _launch(tester, harness);
      await _until(tester, find.byType(HomePage));
      await tester.pumpAndSettle();

      _expectStartPage(tester);
      await _expectEmptyHome(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('новый запуск на том же хранилище', () {
    testWidgets('после выбора пункта «Граф намерений» и открытой страницы '
        'намерения открывает Главную без этой страницы', (tester) async {
      final harness = await _harness(tester, const Locale('ru'));
      await _prepareStorage(tester, harness, (database) {
        _storeIntention(database, _walk, _walkTitle, archived: false);
      });

      // Первый запуск: граф намерений и страница намерения поверх него.
      final first = await _launch(tester, harness);
      await _until(tester, find.byType(HomePage));
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
      await _until(
        tester,
        find.descendant(
          of: find.byType(IntentionDetailsPage),
          matching: find.text(_walkTitle),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(IntentionDetailsPage), findsOneWidget);
      expect(find.byType(AppNavigationBar), findsOneWidget);
      expect(_selected(tester), AppDestination.intentionGraph);

      // Полное завершение и новый запуск на том же хранилище.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(first.runtime.shutdown);
      await _launch(tester, harness);
      await _until(tester, find.byType(HomePage));
      await tester.pumpAndSettle();

      _expectStartPage(tester);
      await _expectEmptyHome(tester);
      expect(tester.takeException(), isNull);
    });
  });
}

/// Запуск приложения на файловом хранилище [LocalDatabaseHarness].
final class _App {
  _App(this.runtime, this.raw);

  final AppRuntime runtime;
  final sqlite.Database raw;
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
  expect(ready, isA<AppRuntimeReady>());
  return _App(runtime, raw);
}

/// Открыта Главная с видимой панелью и выбранным пунктом «Главная»: страниц
/// поверх оболочки нет, а каталоги в этом запуске ещё не построены.
void _expectStartPage(WidgetTester tester) {
  expect(find.byType(HomePage), findsOneWidget);
  expect(find.byType(AppNavigationBar), findsOneWidget);
  expect(_selected(tester), AppDestination.home);
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

Future<void> _expectEmptyHome(WidgetTester tester) async {
  final home = find.byType(HomePage);
  final l10n = AppLocalizations.of(tester.element(home));
  await _until(tester, find.text(l10n.statisticsPlannedContribution(0)));
  await tester.scrollUntilVisible(
    find.text(l10n.statisticsEmpty),
    200,
    scrollable: find.descendant(of: home, matching: find.byType(Scrollable)),
  );
  expect(find.text(l10n.statisticsEmpty), findsOneWidget);
  expect(find.text(l10n.statisticsPlannedContribution(0)), findsOneWidget);
  expect(find.text(l10n.statisticsContribution(0)), findsOneWidget);
  expect(find.text(l10n.statisticsTotalItems(0)), findsOneWidget);
}

void _storeIntention(
  sqlite.Database database,
  int number,
  String title, {
  required bool archived,
}) {
  seedRawGraph(database, () {
    database.execute(
      'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
      [tagFixtureId(number), title, 1, archived ? 1 : 0, number, number],
    );
  });
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
