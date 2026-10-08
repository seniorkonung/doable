import 'dart:async';

import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_shell_page.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_page.dart';
import 'package:doable/src/data/local/app_database.dart'
    show
        AppDatabase,
        LocalDatabaseConnectionObserver,
        observeConfiguredLocalDatabaseConnection,
        openInMemoryLocalDatabase;
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/favorite/presentation/home/home_page.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/in_memory_quick_creation_mode_store.dart';

const _unsupportedSchemaVersion = AppDatabase.currentSchemaVersion + 1;

void main() {
  testWidgets(
    'не монтирует начальный route до ready и передаёт runtime container',
    (tester) async {
      _useEnglishLocale(tester);
      final openingStarted = Completer<void>();
      final allowOpening = Completer<void>();
      final runtime = AppRuntime(
        quickCreationModeStore: InMemoryQuickCreationModeStore(),
        connectionFactory: () => observeConfiguredLocalDatabaseConnection(
          openInMemoryLocalDatabase(),
          _ControlledOpenObserver(openingStarted, allowOpening),
        ),
        diagnosticsSink: InMemoryDiagnosticsSink(),
      );
      addTearDown(() async {
        if (!allowOpening.isCompleted) allowOpening.complete();
        await runtime.shutdown();
      });

      await tester.pumpWidget(MainApp(runtime: runtime));
      await openingStarted.future;

      expect(find.text('Preparing local data…'), findsOneWidget);
      _expectNoRootPages();

      allowOpening.complete();
      await tester.pumpAndSettle();

      final ready = await runtime.bootstrap() as AppRuntimeReady;
      _expectHome(tester, ready);
      final featureContext = tester.element(find.byType(HomePage));
      expect(
        ProviderScope.containerOf(featureContext, listen: false),
        same(ready.container),
      );
    },
  );

  testWidgets('retryable bootstrap сохраняет явный retry до успеха, а '
      'повторная подготовка показана без панели', (tester) async {
    _useEnglishLocale(tester);
    var attempts = 0;
    final retryStarted = Completer<void>();
    final allowRetry = Completer<void>();
    final runtime = AppRuntime(
      quickCreationModeStore: InMemoryQuickCreationModeStore(),
      connectionFactory: () {
        attempts += 1;
        if (attempts == 1) {
          return openInMemoryLocalDatabase(
            setup: (_) => throw SqliteException(
              extendedResultCode: SqlError.SQLITE_BUSY,
              message: 'временная недоступность',
            ),
          );
        }
        return observeConfiguredLocalDatabaseConnection(
          openInMemoryLocalDatabase(),
          _ControlledOpenObserver(retryStarted, allowRetry),
        );
      },
      diagnosticsSink: InMemoryDiagnosticsSink(),
    );
    addTearDown(() async {
      if (!allowRetry.isCompleted) allowRetry.complete();
      await runtime.shutdown();
    });

    await tester.pumpWidget(MainApp(runtime: runtime));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Local data couldn’t be prepared. Your data wasn’t changed. Try again.',
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);
    _expectNoRootPages();

    await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
    await tester.pump();
    await retryStarted.future;
    await tester.pump();

    // Повторная подготовка снова показывает загрузку без оболочки.
    expect(find.text('Preparing local data…'), findsOneWidget);
    _expectNoRootPages();

    allowRetry.complete();
    await tester.pumpAndSettle();

    expect(attempts, 2);
    _expectHome(tester, await runtime.bootstrap() as AppRuntimeReady);
  });

  testWidgets('corruption имеет terminal-состояние без retry', (tester) async {
    _useEnglishLocale(tester);
    final runtime = AppRuntime(
      quickCreationModeStore: InMemoryQuickCreationModeStore(),
      connectionFactory: () => openInMemoryLocalDatabase(
        setup: (_) => throw SqliteException(
          extendedResultCode: SqlError.SQLITE_NOTADB,
          message: 'повреждение',
        ),
      ),
      diagnosticsSink: InMemoryDiagnosticsSink(),
    );
    addTearDown(runtime.shutdown);

    await tester.pumpWidget(MainApp(runtime: runtime));
    await tester.pumpAndSettle();

    expect(
      find.text('Local data is damaged and can’t be opened.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Try again'), findsNothing);
    _expectNoRootPages();
  });

  testWidgets('incompatible schema требует обновление без retry', (
    tester,
  ) async {
    _useEnglishLocale(tester);
    final runtime = AppRuntime(
      quickCreationModeStore: InMemoryQuickCreationModeStore(),
      connectionFactory: () => openInMemoryLocalDatabase(
        setup: (database) => database.execute(
          'PRAGMA user_version = $_unsupportedSchemaVersion',
        ),
      ),
      diagnosticsSink: InMemoryDiagnosticsSink(),
    );
    addTearDown(runtime.shutdown);

    await tester.pumpWidget(MainApp(runtime: runtime));
    await tester.pumpAndSettle();

    expect(
      find.text('Install a compatible Doable update to continue.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Try again'), findsNothing);
    _expectNoRootPages();
  });

  testWidgets('unexpected failure имеет отдельное состояние без retry', (
    tester,
  ) async {
    _useEnglishLocale(tester);
    final runtime = AppRuntime(
      quickCreationModeStore: InMemoryQuickCreationModeStore(),
      connectionFactory: () => openInMemoryLocalDatabase(
        setup: (_) => throw StateError('неожиданный отказ'),
      ),
      diagnosticsSink: InMemoryDiagnosticsSink(),
    );
    addTearDown(runtime.shutdown);

    await tester.pumpWidget(MainApp(runtime: runtime));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Local data couldn’t be opened because of an unexpected error.',
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Try again'), findsNothing);
    _expectNoRootPages();
  });

  testWidgets('отказ сборки графа над готовым хранилищем показан '
      'неожиданным отказом без панели', (tester) async {
    _useEnglishLocale(tester);
    final runtime = AppRuntime(
      quickCreationModeStore: InMemoryQuickCreationModeStore(),
      connectionFactory: () => openInMemoryLocalDatabase(),
      diagnosticsSink: InMemoryDiagnosticsSink(),
      repositoryFactory: (_) => throw StateError('неожиданный отказ'),
    );
    addTearDown(runtime.shutdown);

    // Отказ сборки закрывает уже открытое хранилище: подготовка идёт с
    // реальным ожиданием.
    await tester.runAsync(() async {
      await tester.pumpWidget(MainApp(runtime: runtime));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Local data couldn’t be opened because of an unexpected error.',
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Try again'), findsNothing);
    _expectNoRootPages();
  });
}

/// Состояние подготовки хранилища показано без оболочки корневых страниц:
/// нет ни панели, ни одной корневой страницы, в том числе невыбранной.
void _expectNoRootPages() {
  for (final widget in [
    AppShellPage,
    AppNavigationBar,
    HomePage,
    DailyChoiceCatalogPage,
    IntentionCatalogPage,
  ]) {
    expect(
      find.byType(widget, skipOffstage: false),
      findsNothing,
      reason: '$widget',
    );
  }
}

/// После готовности хранилища открыта Главная с видимой панелью и выбранным
/// пунктом «Главная» без страниц поверх оболочки.
void _expectHome(WidgetTester tester, AppRuntimeReady ready) {
  final router = ready.container.read(appRouterProvider);
  expect(find.byType(HomePage), findsOneWidget);
  expect(find.byType(AppNavigationBar), findsOneWidget);
  expect(
    tester.widget<AppNavigationBar>(find.byType(AppNavigationBar)).selected,
    AppDestination.home,
  );
  expect(router.current.name, AppShellRoute.name);
  expect(router.topRoute.name, HomeRoute.name);
  expect(router.canPop(), isFalse);
}

void _useEnglishLocale(WidgetTester tester) {
  tester.binding.platformDispatcher.localesTestValue = const [Locale('en')];
  addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
}

final class _ControlledOpenObserver extends LocalDatabaseConnectionObserver {
  _ControlledOpenObserver(this.openingStarted, this.allowOpening);

  final Completer<void> openingStarted;
  final Completer<void> allowOpening;

  @override
  Future<void> beforeOpen() async {
    if (!openingStarted.isCompleted) openingStarted.complete();
    await allowOpening.future;
  }
}
