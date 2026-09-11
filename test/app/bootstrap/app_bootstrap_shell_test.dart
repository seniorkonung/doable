import 'dart:async';

import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/data/local/app_database.dart'
    show
        LocalDatabaseConnectionObserver,
        observeConfiguredLocalDatabaseConnection,
        openInMemoryLocalDatabase;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../support/in_memory_diagnostics_sink.dart';

const _featureKey = Key('готовая возможность');

void main() {
  testWidgets(
    'не монтирует возможность до ready и передаёт runtime container',
    (tester) async {
      _useEnglishLocale(tester);
      final openingStarted = Completer<void>();
      final allowOpening = Completer<void>();
      final runtime = AppRuntime(
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

      await tester.pumpWidget(
        MainApp(
          runtime: runtime,
          readyChild: const SizedBox(key: _featureKey),
        ),
      );
      await openingStarted.future;

      expect(find.text('Preparing local data…'), findsOneWidget);
      expect(find.byKey(_featureKey), findsNothing);

      allowOpening.complete();
      await tester.pumpAndSettle();

      final ready = await runtime.bootstrap() as AppRuntimeReady;
      final featureContext = tester.element(find.byKey(_featureKey));
      expect(
        ProviderScope.containerOf(featureContext, listen: false),
        same(ready.container),
      );
    },
  );

  testWidgets('retryable bootstrap сохраняет явный retry до успеха', (
    tester,
  ) async {
    _useEnglishLocale(tester);
    var attempts = 0;
    final runtime = AppRuntime(
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
        return openInMemoryLocalDatabase();
      },
      diagnosticsSink: InMemoryDiagnosticsSink(),
    );
    addTearDown(runtime.shutdown);

    await tester.pumpWidget(
      MainApp(
        runtime: runtime,
        readyChild: const SizedBox(key: _featureKey),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Local data couldn’t be prepared. Your data wasn’t changed. Try again.',
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);
    expect(find.byKey(_featureKey), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.byKey(_featureKey), findsOneWidget);
  });

  testWidgets('corruption имеет terminal-состояние без retry', (tester) async {
    _useEnglishLocale(tester);
    final runtime = AppRuntime(
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
  });

  testWidgets('incompatible schema требует обновление без retry', (
    tester,
  ) async {
    _useEnglishLocale(tester);
    final runtime = AppRuntime(
      connectionFactory: () => openInMemoryLocalDatabase(
        setup: (database) => database.execute('PRAGMA user_version = 2'),
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
  });

  testWidgets('unexpected failure имеет отдельное состояние без retry', (
    tester,
  ) async {
    _useEnglishLocale(tester);
    final runtime = AppRuntime(
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
  });
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
