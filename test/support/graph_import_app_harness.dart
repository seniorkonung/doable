import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/home/home_page.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:doable/src/app/settings/settings_page.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_local_date_provider.dart';
import 'package:doable/src/data/local/app_database.dart'
    show openFileBackedLocalDatabase;
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph_backups/graph_backup_registry.dart';
import 'package:doable/src/graph_backups/graph_backups_provider.dart';
import 'package:doable/src/graph_format/graph_format_codec.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'app_flow_wait.dart' as app_flow;
import 'daily_choice_durability_fixture.dart';
import 'file_document_access.dart';
import 'graph_log_completeness_reference.dart';
import 'in_memory_diagnostics_sink.dart';
import 'in_memory_quick_creation_mode_store.dart';
import 'local_database_harness.dart';
import 'temporary_graph_files.dart';

/// Приложение над файловым хранилищем своей установки с часами устройства
/// [now]. Его можно перезапустить над тем же хранилищем и каталогом снимков.
/// Документы экспорта и импорта — файлы без системных диалогов.
final class ImportAppHarness {
  ImportAppHarness._(
    this.tester,
    this._harness,
    this._files,
    this._modes,
    this.now,
  );

  final WidgetTester tester;
  final LocalDatabaseHarness _harness;
  final TemporaryGraphFiles _files;
  final diagnostics = InMemoryDiagnosticsSink();

  /// Соединение приложения с файлом хранилища.
  late sqlite.Database _storage;

  /// Настройка установки — режим быстрого создания.
  final InMemoryQuickCreationModeStore _modes;

  /// Показание часов устройства для графа, экспорта, копий и местного
  /// сегодня.
  DateTime now;

  late AppRuntime _runtime;
  late ProviderContainer container;
  var _isRunning = false;
  StreamSubscription<GraphBackupsRead>? _watching;
  List<GraphBackupEntry> _backups = const [];

  /// Запускает приложение новой установки в момент [at] с режимом быстрого
  /// создания [quickCreationMode]. [seed] создаёт граф командами, поэтому он
  /// полностью отражён в логе фактов; без [seed] граф пуст.
  static Future<ImportAppHarness> start(
    WidgetTester tester, {
    required DateTime at,
    QuickCreationMode quickCreationMode = QuickCreationMode.intention,
    Future<void> Function(PersonalGraphRepository graph)? seed,
  }) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.platformDispatcher.localesTestValue = const [Locale('ru')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    final harness = (await tester.runAsync(LocalDatabaseHarness.fileBacked))!;
    addTearDown(() => tester.runAsync(harness.dispose));
    final app = ImportAppHarness._(
      tester,
      harness,
      TemporaryGraphFiles(),
      InMemoryQuickCreationModeStore()..mode = quickCreationMode,
      at,
    );
    if (seed != null) {
      await tester.runAsync(() async {
        await seed(
          DriftPersonalGraphRepository(
            await harness.openReadyDatabase(),
            UuidV7IntentionIdGenerator(),
            () => app.now.toUtc(),
            InMemoryDiagnosticsSink(),
          ),
        );
        await harness.closePersistenceObjectGraph();
      });
    }
    addTearDown(app.shutDown);
    await app._launch();
    return app;
  }

  /// Завершает приложение и в момент [at] запускает его заново.
  Future<void> restart({required DateTime at}) async {
    await shutDown();
    now = at;
    await _launch();
  }

  Future<void> _launch() async {
    final runtime = _runtime = AppRuntime(
      connectionFactory: () => openFileBackedLocalDatabase(
        _harness.databaseFile,
        setup: (database) => _storage = database,
      ),
      diagnosticsSink: diagnostics,
      quickCreationModeStore: _modes,
      graphFilesFactory: _files.create,
      dailyChoiceLocalDateSource: () => DailyChoiceLocalDay(
        date: CalendarDate.fromParts(now.year, now.month, now.day),
        untilNextDate: const Duration(hours: 12),
      ),
      clock: () => now.toUtc(),
    );
    final ready =
        (await tester.runAsync(runtime.bootstrap))! as AppRuntimeReady;
    _isRunning = true;
    container = ready.container;
    _watching = container.read(graphBackupsProvider).watchBackups().listen((
      read,
    ) {
      if (read case GraphBackupsReadSucceeded(:final backups)) {
        _backups = backups;
      }
    });
    await tester.pumpWidget(MainApp(runtime: runtime));
    await app_flow.until(tester, find.byType(HomePage));
    await app_flow.waitFor(
      tester,
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
  }

  /// Завершает приложение; завершённое приложение ничего не делает.
  Future<void> shutDown() async {
    if (!_isRunning) return;
    _isRunning = false;
    // Отмена подписки и выключение завершаются вне управляемого времени
    // проверки: ждём оба через продвижение кадров и фоновой работы.
    final watchingCancelled = _watching?.cancel();
    _watching = null;
    await tester.pumpWidget(const SizedBox.shrink());
    var isShutDown = false;
    unawaited(
      Future.wait<void>([?watchingCancelled, _runtime.shutdown()])
          .whenComplete(() => isShutDown = true),
    );
    await app_flow.waitFor(tester, () => isShutDown);
  }

  /// Ждёт, пока хранится [count] копий.
  Future<void> waitForBackups(int count) =>
      app_flow.waitFor(tester, () => _backups.length == count);

  /// Граф в хранилище: эталонная выгрузка таблиц графа отдельным
  /// соединением, без механизма фактов. Записи идут по последовательностям
  /// создания, поэтому выгрузки совпадают, только если совпадают и порядки.
  Future<List<String>> graphState() async => (await tester.runAsync(() async {
    // Второй экземпляр базы читает файл своим соединением, а не делит
    // соединение приложения, о чём предупреждает drift.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final database = await _harness.openReadyDatabase();
    try {
      return [
        for (final record in await referenceGraphRecords(database))
          utf8.decode(GraphFormatCodec.encode(record)),
      ];
    } finally {
      await _harness.closePersistenceObjectGraph();
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
    }
  }))!;

  /// Всё содержимое файла хранилища — граф, копии, лог фактов и реестр
  /// снимков — и имена файлов каталога снимков.
  Object storedState() => [
    durabilityFileState(_harness.databaseFile),
    // Каталог снимков создаёт первая запись снимка.
    [
      if (_files.snapshots.existsSync())
        for (final file in _files.snapshots.listSync())
          file.uri.pathSegments.last,
    ]..sort(),
  ];

  /// Сжимает файл хранилища до занятых страниц и запрещает ему расти, как
  /// если бы на устройстве не осталось места.
  void fillStorage() {
    _storage.execute('VACUUM');
    final pages = _storage.select('PRAGMA page_count').single.values.single;
    _storage.execute('PRAGMA max_page_count = $pages');
  }

  /// Снова позволяет файлу хранилища расти, как после освобождения места.
  void freeStorage() => _storage.execute('PRAGMA max_page_count = 1073741823');

  FileDocumentAccess get documents => _files.documents;

  /// Открывает с Главной страницу «Настройки».
  Future<void> openSettings() async {
    await tester.tap(find.byTooltip('Настройки'));
    await app_flow.until(tester, find.byType(SettingsPage));
    await tester.pumpAndSettle();
  }

  /// В системном диалоге выбора человек выбирает документ [file].
  void chooseForImport(File file) =>
      documents.openingDialog = () async => documents.chosen(file);

  /// Начинает импорт строкой «Импорт данных».
  Future<void> startImport() async {
    await tester.tap(find.text('Импорт данных'));
    await tester.pump();
  }

  /// Ждёт подтверждения импорта прочитанного файла.
  Future<void> waitForConfirmation() async {
    await app_flow.until(tester, find.text('Импортировать эту копию?'));
    await tester.pumpAndSettle();
  }

  /// Подтверждает замену графа файлом.
  Future<void> confirmImport() async {
    await tester.tap(find.text('Импортировать и заменить'));
    await tester.pump();
  }

  /// Ждёт, пока закроется прогресс импорта.
  Future<void> waitForProgressEnd() => app_flow.waitFor(
    tester,
    () => find.text('Импорт данных…').evaluate().isEmpty,
  );
}
