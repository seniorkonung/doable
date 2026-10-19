import 'dart:async';

import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/home/home_page.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/settings/settings_page.dart';
import 'package:doable/src/data/local/app_database.dart'
    show
        LocalDatabaseConnectionObserver,
        LocalDatabaseSqlOperation,
        LocalDatabaseSqlStatement,
        observeConfiguredLocalDatabaseConnection,
        openInMemoryLocalDatabase;
import 'package:doable/src/data_transfer/application/graph_restore_provider.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph_backups/graph_backup_registry.dart';
import 'package:doable/src/graph_backups/graph_backups.dart';
import 'package:doable/src/graph_backups/graph_backups_provider.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/app_root_pages.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/in_memory_quick_creation_mode_store.dart';
import '../../support/temporary_graph_files.dart';

void main() {
  for (final (language, settings, title, progress, cancel, export) in [
    (
      'ru',
      'Настройки',
      'Восстановление копии…',
      '30 %',
      'Отменить',
      'Экспорт данных',
    ),
    ('en', 'Settings', 'Restoring the copy…', '30%', 'Cancel', 'Export data'),
  ]) {
    testWidgets('$language: пока идёт восстановление копии, над страницей '
        '«Настройки» открыт прогресс с ходом и кнопкой «Отменить», а '
        'страница и панель навигации недоступны', (tester) async {
      final semantics = tester.ensureSemantics();
      final app = await _RestoreApp.open(
        tester,
        language: language,
        settings: settings,
      );

      app.startRestore();
      await _waitFor(tester, () => app.replacement.isHolding);
      await tester.pumpAndSettle();

      // Запись снимка замены завершена, а замена ещё ничего не удалила.
      expect(
        tester.getSemantics(find.text(title)),
        isSemantics(label: title, value: progress),
      );
      expect(
        tester.getSemantics(find.text(cancel)),
        isSemantics(
          label: cancel,
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      await tester.tap(
        appNavigationDestination(AppDestination.intentionGraph),
        warnIfMissed: false,
      );
      await tester.tap(find.text(export), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(
        tester.widget<AppNavigationBar>(find.byType(AppNavigationBar)).selected,
        AppDestination.home,
      );
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(find.text(title), findsOneWidget);

      app.replacement.proceed();
      await _waitFor(tester, () => app.outcome != null);
      semantics.dispose();
    });
  }

  testWidgets('«назад» не закрывает прогресс и не прерывает восстановление, '
      'а после успеха прогресс закрывается, страница «Настройки» остаётся '
      'открытой и появляется «Копия восстановлена»', (tester) async {
    final app = await _RestoreApp.open(tester);
    app.startRestore();
    await _waitFor(tester, () => app.replacement.isHolding);
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Восстановление копии…'), findsOneWidget);

    app.replacement.proceed();
    await _waitFor(
      tester,
      () => find.text('Копия восстановлена').evaluate().isNotEmpty,
    );
    expect(app.outcome, isA<GraphBackupRestored>());
    expect(find.text('Восстановление копии…'), findsNothing);
    expect(find.byType(SettingsPage), findsOneWidget);
  });

  for (final (language, settings, title, cancel, cancelling) in [
    ('ru', 'Настройки', 'Восстановление копии…', 'Отменить', 'Отмена…'),
    ('en', 'Settings', 'Restoring the copy…', 'Cancel', 'Cancelling…'),
  ]) {
    testWidgets('$language: «Отменить» показывает «Отмена…» экранному '
        'диктору до конца отката замены, а затем прогресс закрывается без '
        'сообщения', (tester) async {
      final semantics = tester.ensureSemantics();
      final app = await _RestoreApp.open(
        tester,
        language: language,
        settings: settings,
      );
      app.startRestore();
      await _waitFor(tester, () => app.replacement.isHolding);
      await tester.pumpAndSettle();

      await tester.tap(find.text(cancel));
      await tester.pump();

      expect(
        tester.getSemantics(find.text(cancelling)),
        isSemantics(
          label: cancelling,
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
          isLiveRegion: true,
        ),
      );
      // Откат не измеряется, поэтому прежний ход больше не сообщается.
      expect(tester.getSemantics(find.text(title)).value, isEmpty);

      // Замена ещё не заметила отмену и не откатилась.
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(cancelling), findsOneWidget);

      app.replacement.proceed();
      await _waitFor(tester, () => app.outcome != null);
      await tester.pumpAndSettle();
      expect(app.outcome, isA<GraphBackupRestoreCancelled>());
      expect(find.text(title), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(SettingsPage), findsOneWidget);
      semantics.dispose();
    });
  }

  testWidgets('после точки невозврата замены «Отменить» недоступна, экранный '
      'диктор сообщает о её недоступности, а нажатие не показывает '
      '«Отмена…», и восстановление завершается сообщением «Копия '
      'восстановлена»', (tester) async {
    final semantics = tester.ensureSemantics();
    final app = await _RestoreApp.open(tester, hold: _ReplacementHold.commit);
    app.startRestore();
    await _waitFor(tester, () => app.replacement.isHolding);
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(find.text('Отменить')),
      isSemantics(
        label: 'Отменить',
        isButton: true,
        hasEnabledState: true,
        isEnabled: false,
        hasTapAction: false,
      ),
    );
    await tester.tap(find.text('Отменить'), warnIfMissed: false);
    await tester.pump();
    expect(find.text('Отмена…'), findsNothing);
    expect(find.text('Отменить'), findsOneWidget);

    app.replacement.proceed();
    await _waitFor(
      tester,
      () => find.text('Копия восстановлена').evaluate().isNotEmpty,
    );
    expect(app.outcome, isA<GraphBackupRestored>());
    expect(find.text('Восстановление копии…'), findsNothing);
    semantics.dispose();
  });

  testWidgets('после отказа восстановления прогресс закрывается, а страница '
      '«Настройки» остаётся открытой', (tester) async {
    final app = await _RestoreApp.open(tester);
    app.startRestore();
    await _waitFor(tester, () => app.replacement.isHolding);
    await tester.pumpAndSettle();
    expect(find.text('Восстановление копии…'), findsOneWidget);

    app.replacement.reject();
    await _waitFor(tester, () => app.outcome != null);
    await tester.pumpAndSettle();

    expect(app.outcome, isA<GraphBackupRestoreFailed>());
    expect(find.text('Восстановление копии…'), findsNothing);
    expect(find.byType(SettingsPage), findsOneWidget);
  });
}

/// Приложение новой установки с тегом и ручной копией, открытое на странице
/// «Настройки» на языке [language]. Замена графа ждёт [replacement] там,
/// где её задерживает [hold].
final class _RestoreApp {
  _RestoreApp._(this._tester, this._container, this._backup, this.replacement);

  final WidgetTester _tester;
  final ProviderContainer _container;
  final GraphBackupEntry _backup;
  final _ReplacementControl replacement;

  /// Исход начатого восстановления; `null`, пока оно идёт.
  GraphBackupRestoreOutcome? outcome;

  static Future<_RestoreApp> open(
    WidgetTester tester, {
    String language = 'ru',
    String settings = 'Настройки',
    _ReplacementHold hold = _ReplacementHold.previousGraphDeletion,
  }) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.platformDispatcher.localesTestValue = [Locale(language)];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    final replacement = _ReplacementControl(hold);
    final files = TemporaryGraphFiles();
    final runtime = AppRuntime(
      connectionFactory: () => observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(),
        replacement,
      ),
      diagnosticsSink: InMemoryDiagnosticsSink(),
      quickCreationModeStore: InMemoryQuickCreationModeStore(),
      graphFilesFactory: files.create,
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(runtime.shutdown);
    });
    final ready = (await tester.runAsync(runtime.bootstrap)) as AppRuntimeReady;
    final container = ready.container;
    final backup = await tester.runAsync(() async {
      final repository = container.read(personalGraphRepositoryProvider);
      expect(
        await repository.execute(CreateTag(TagName.fromInput('Дом'))),
        isA<GraphCommandSucceeded>(),
      );
      expect(
        await container.read(graphBackupsProvider).makeManualBackup(),
        ManualGraphBackupOutcome.made,
      );
      // Ежедневная копия при запуске могла застать уже непустой граф.
      return (await (repository as GraphBackupRegistry).readBackups())
          .singleWhere((backup) => backup.kind == GraphBackupKind.manual);
    });
    await tester.pumpWidget(MainApp(runtime: runtime));
    await _waitFor(tester, () => find.byType(HomePage).evaluate().isNotEmpty);
    await _waitFor(
      tester,
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(settings));
    await _waitFor(
      tester,
      () => find.byType(SettingsPage).evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();
    return _RestoreApp._(tester, container, backup!, replacement);
  }

  /// Начинает восстановление копии, как его начнёт подтверждение
  /// восстановления.
  void startRestore() {
    final start =
        _container.read(graphRestoreControllerProvider.notifier).start(_backup)
            as GraphBackupRestoreAccepted;
    unawaited(start.future.then((value) => outcome = value));
    // Выключение дожидается восстановления, а задержанная замена продолжается
    // только кадрами проверки. Поэтому и после отказа проверки замена
    // продолжается до выключения.
    addTearDown(() async {
      replacement.proceed();
      await _waitFor(_tester, () => outcome != null);
    });
  }
}

/// Где проверка задерживает замену графа.
enum _ReplacementHold {
  /// На первом операторе удаления прежнего графа, до точки невозврата.
  previousGraphDeletion,

  /// На подтверждении транзакции замены, после точки невозврата.
  commit,
}

/// Задерживает замену графа там, где её задерживает [_hold], пока проверка
/// не продолжит замену или не отклонит первый оператор удаления прежнего
/// графа отказом хранилища.
final class _ReplacementControl extends LocalDatabaseConnectionObserver {
  _ReplacementControl(this._hold);

  final _ReplacementHold _hold;
  final _release = Completer<void>();
  var _isReached = false;

  /// Замена выполнила последний оператор перед точкой невозврата, и её
  /// транзакции осталось только подтверждение.
  var _isCommitNext = false;

  /// Замена дошла до места задержки и ждёт.
  bool get isHolding => _isReached && !_release.isCompleted;

  void proceed() {
    if (!_release.isCompleted) _release.complete();
  }

  void reject() => _release.completeError(
    sqlite.SqliteException(
      extendedResultCode: sqlite.SqlError.SQLITE_IOERR,
      message: 'disk I/O error',
    ),
  );

  @override
  FutureOr<void> beforeStatement(LocalDatabaseSqlStatement statement) {
    if (_hold != _ReplacementHold.previousGraphDeletion ||
        _isReached ||
        !statement.statements.any(
          (sql) => sql.startsWith('DELETE FROM daily_choices '),
        )) {
      return null;
    }
    _isReached = true;
    return _release.future;
  }

  @override
  void afterStatement(LocalDatabaseSqlStatement statement) {
    // Включение захвата фактов — последний оператор транзакции замены перед
    // её точкой невозврата.
    if (_hold == _ReplacementHold.commit &&
        statement.operation == LocalDatabaseSqlOperation.update &&
        statement.statements.single.contains('SET "capture"') &&
        statement.arguments.single == 1) {
      _isCommitNext = true;
    }
  }

  @override
  FutureOr<void> beforeTransactionCommit() {
    if (!_isCommitNext || _isReached) return null;
    _isReached = true;
    return _release.future;
  }
}

/// Чередует реальное ожидание хранилища и изолята записи снимка с кадрами,
/// пока не выполнится [done].
Future<void> _waitFor(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 100 && !done(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue);
}
