import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/home/home_page.dart';
import 'package:doable/src/app/settings/settings_page.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_local_date_provider.dart';
import 'package:doable/src/data/local/app_database.dart'
    show
        LocalDatabaseConnectionObserver,
        LocalDatabaseSqlStatement,
        observeConfiguredLocalDatabaseConnection,
        openFileBackedLocalDatabase;
import 'package:doable/src/data_transfer/application/document_access.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph_backups/graph_backup_registry.dart';
import 'package:doable/src/graph_backups/graph_backups_provider.dart';
import 'package:doable/src/graph_format/graph_format_codec.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/daily_choice_durability_fixture.dart';
import '../support/file_document_access.dart';
import '../support/graph_import_files.dart';
import '../support/graph_log_completeness_reference.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/in_memory_quick_creation_mode_store.dart';
import '../support/local_database_harness.dart';
import '../support/temporary_graph_files.dart';

/// Отказ импорта файла, который не является экспортом Doable или повреждён.
const _invalidFile =
    'Не удалось импортировать файл. Это не экспорт Doable, или он повреждён. '
    'Ничего не изменено';

/// Отказ импорта файла более новой версии формата.
const _newerVersion =
    'Файл создан более новой версией Doable. Обновите приложение, чтобы '
    'импортировать его. Ничего не изменено';

/// Отказ импорта, которому не хватило места на устройстве.
const _storageFull =
    'Недостаточно места на устройстве. Освободите место и повторите. '
    'Ничего не изменено';

/// Заголовок прогресса импорта.
const _importRunning = 'Импорт данных…';

void main() {
  testWidgets('принятая отмена чтения имеет приоритет над поздним отказом '
      'копирования: после «Отмена…» прогресс закрывается без подтверждения, '
      'сообщения, операции координатора и события отказа', (tester) async {
    final app = await _ImportApp.start(tester);
    await app.openSettings();
    final before = app.storedState();
    final completions = <GraphCommandCompletion>[];
    final subscription = app._container
        .read(graphCommandCoordinatorProvider.notifier)
        .completions
        .listen(completions.add);
    addTearDown(subscription.cancel);
    final providerAnswer = Completer<void>();
    final cancellationAnswer = Completer<void>();
    app.documents
      ..beforeCopy = (() => providerAnswer.future)
      ..beforeCancellationAnswer = (() => cancellationAnswer.future)
      ..copyFailure = const DocumentNotRead();
    app.chooseForImport(_document(_referenceFile()));

    await app.startImport();
    await _until(tester, find.text(_importRunning));
    await tester.tap(find.text('Отменить'));
    await tester.pump();
    expect(find.text('Отмена…'), findsOneWidget);

    providerAnswer.complete();
    await app.waitForProgressEnd();
    cancellationAnswer.complete();
    await _settle(tester);

    expect(find.text('Импортировать эту копию?'), findsNothing);
    expect(find.byKey(const ValueKey('graph-operation-message')), findsNothing);
    expect(find.textContaining('Ничего не изменено'), findsNothing);
    expect(completions, isEmpty);
    expect(
      app._diagnostics.events.whereType<GraphImportDiagnosticsEvent>(),
      isEmpty,
    );
    expect(app.storedState(), before);
  });

  testWidgets('сценарий «Выбран чужой файл»: фотография без чтения остатка '
      'и попытки записи при нехватке места без подтверждения даёт '
      'под строкой «Импорт данных» отказ с действием «Выбрать другой файл», '
      'которое снова открывает системный диалог, а отказ от подтверждения '
      'выбранного в нём файла ничего не меняет и сообщения не даёт', (
    tester,
  ) async {
    final documents = _PhotoDocumentAccess();
    final app = await _ImportApp.start(tester, documents: documents);
    await app.openSettings();
    final before = app.storedState();

    await app.startImport();
    await _until(tester, find.text(_invalidFile));

    expect(find.text('Импортировать эту копию?'), findsNothing);
    expect(find.text(_storageFull), findsNothing);
    expect(find.byKey(const ValueKey('graph-operation-message')), findsNothing);
    expect(documents.remainderRequested, isFalse);
    expect(documents.copyAttempts, 0);
    expect(documents.finished, isTrue);
    expect(app.storedState(), before);

    // Подтверждение откроется, только если новый диалог выбрал исправный
    // файл.
    app.chooseForImport(_document(_referenceFile()));
    documents.followingDocuments = app.documents;
    await tester.tap(find.text('Выбрать другой файл'));
    await app.waitForConfirmation();
    await tester.tap(find.text('Отмена'));
    await tester.pump();
    // Прогресс и сообщение появились бы за это время.
    await _settle(tester);

    expect(find.text('Импортировать эту копию?'), findsNothing);
    expect(find.text(_importRunning), findsNothing);
    expect(find.byKey(const ValueKey('graph-operation-message')), findsNothing);
    expect(find.text(_invalidFile), findsNothing);
    expect(app.storedState(), before);
  });

  testWidgets('сценарий «Файл более новой версии»: без подтверждения под '
      'строкой «Импорт данных» отказ предлагает обновить приложение и не '
      'предлагает действия, а граф и копии остаются прежними', (tester) async {
    final app = await _ImportApp.start(tester);
    await app.openSettings();
    final before = app.storedState();
    app.chooseForImport(_document(newerFormatVersionFile()));

    await app.startImport();
    await _until(tester, find.text(_newerVersion));

    expect(find.text('Импортировать эту копию?'), findsNothing);
    expect(find.text('Выбрать другой файл'), findsNothing);
    expect(find.text('Повторить'), findsNothing);
    expect(find.byKey(const ValueKey('graph-operation-message')), findsNothing);
    expect(app.storedState(), before);
  });

  testWidgets('сценарий «Повреждение обнаружено после подтверждения»: после '
      'подтверждения файла, обрезанного посередине, замена отменяется, граф и '
      'копии остаются прежними, а под строкой «Импорт данных» показан отказ '
      'повреждённого файла', (tester) async {
    final app = await _ImportApp.start(tester);
    await app.openSettings();
    final before = app.storedState();
    app.chooseForImport(_document(truncatedGraphExportFile()));
    await app.startImport();
    await app.waitForConfirmation();

    await app.confirmImport();
    await _until(tester, find.text(_invalidFile));

    expect(find.text(_importRunning), findsNothing);
    expect(find.byKey(const ValueKey('graph-operation-message')), findsNothing);
    expect(app.storedState(), before);
  });

  testWidgets('сценарий «Не хватает места на устройстве»: замена откатывается, '
      'граф и копии остаются прежними, а «Повторить» под строкой «Импорт '
      'данных» снова открывает системный диалог и после освобождения места '
      'импортирует выбранный в нём файл', (tester) async {
    final app = await _ImportApp.start(tester);
    await app.openSettings();
    app.fillStorage();
    final before = app.storedState();
    app.chooseForImport(_document(_fileWithLongDescriptions()));
    await app.startImport();
    await app.waitForConfirmation();

    await app.confirmImport();
    await _until(tester, find.text(_storageFull));

    expect(find.text(_importRunning), findsNothing);
    expect(find.byKey(const ValueKey('graph-operation-message')), findsNothing);
    expect(app.storedState(), before);

    app.freeStorage();
    // Граф заменит эталонный файл, только если новый диалог выбрал его.
    app.chooseForImport(_document(_referenceFile()));
    await tester.tap(find.text('Повторить'));
    await app.waitForConfirmation();
    await app.confirmImport();
    await _until(tester, find.text('Данные импортированы'));

    expect(find.text(_storageFull), findsNothing);
    expect(await app.graphState(), referenceGraphFileLines().skip(1));
  });
}

/// Показание часов устройства для графа, копий и местного сегодня.
final _now = DateTime(2026, 10, 6, 8, 15);

/// Приложение над файловым хранилищем с непустым графом из тега «Дом».
/// Документы импорта — файлы без системных диалогов. Замену графа можно
/// задержать на её первом операторе удаления прежнего графа, а файлу
/// хранилища — запретить расти, как при нехватке места.
final class _ImportApp {
  _ImportApp._(this._tester, this._harness, this._files, this._documents);

  final WidgetTester _tester;
  final LocalDatabaseHarness _harness;
  final TemporaryGraphFiles _files;
  final DocumentAccess? _documents;
  final _statements = _HeldReplacement();
  final _diagnostics = InMemoryDiagnosticsSink();

  late AppRuntime _runtime;
  late ProviderContainer _container;

  /// Соединение приложения с файлом хранилища.
  late sqlite.Database _storage;
  StreamSubscription<GraphBackupsRead>? _watching;
  List<GraphBackupEntry> _backups = const [];

  /// Запускает приложение над графом, созданным командой, поэтому он
  /// полностью отражён в логе фактов, и ждёт копию, которую запуск делает
  /// фоном: проверки сравнивают хранилище после неё.
  static Future<_ImportApp> start(
    WidgetTester tester, {
    DocumentAccess? documents,
  }) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.platformDispatcher.localesTestValue = const [Locale('ru')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    final harness = (await tester.runAsync(LocalDatabaseHarness.fileBacked))!;
    addTearDown(() => tester.runAsync(harness.dispose));
    final app = _ImportApp._(tester, harness, TemporaryGraphFiles(), documents);
    await tester.runAsync(() async {
      final graph = DriftPersonalGraphRepository(
        await harness.openReadyDatabase(),
        UuidV7IntentionIdGenerator(),
        () => _now.toUtc(),
        InMemoryDiagnosticsSink(),
      );
      expect(
        await graph.execute(CreateTag(TagName.fromInput('Дом'))),
        isA<GraphCommandSucceeded>(),
      );
      await harness.closePersistenceObjectGraph();
    });
    addTearDown(app._shutDown);
    await app._launch();
    await _waitFor(tester, () => app._backups.length == 1);
    return app;
  }

  Future<void> _launch() async {
    final runtime = _runtime = AppRuntime(
      connectionFactory: () => observeConfiguredLocalDatabaseConnection(
        openFileBackedLocalDatabase(
          _harness.databaseFile,
          setup: (database) => _storage = database,
        ),
        _statements,
      ),
      diagnosticsSink: _diagnostics,
      quickCreationModeStore: InMemoryQuickCreationModeStore(),
      graphFilesFactory: (log) async {
        final files = await _files.create(log);
        return (
          compaction: files.compaction,
          temporaryDirectory: files.temporaryDirectory,
          documents: _documents ?? files.documents,
        );
      },
      dailyChoiceLocalDateSource: () => DailyChoiceLocalDay(
        date: CalendarDate.fromParts(_now.year, _now.month, _now.day),
        untilNextDate: const Duration(hours: 12),
      ),
      clock: () => _now.toUtc(),
    );
    final ready =
        (await _tester.runAsync(runtime.bootstrap))! as AppRuntimeReady;
    _container = ready.container;
    _watching = _container.read(graphBackupsProvider).watchBackups().listen((
      read,
    ) {
      if (read case GraphBackupsReadSucceeded(:final backups)) {
        _backups = backups;
      }
    });
    await _tester.pumpWidget(MainApp(runtime: runtime));
    await _until(_tester, find.byType(HomePage));
    await _waitFor(
      _tester,
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
  }

  Future<void> _shutDown() async {
    // Выключение дожидается импорта, а задержанная замена продолжается
    // только после освобождения, в том числе после отказа проверки.
    _statements.hold?.release();
    // Отмена наблюдения завершается вне управляемого времени проверки, и
    // ожидание продолжило бы проверку вне него.
    if (_watching case final watching?) unawaited(watching.cancel());
    _watching = null;
    await _tester.pumpWidget(const SizedBox.shrink());
    var isShutDown = false;
    unawaited(_runtime.shutdown().whenComplete(() => isShutDown = true));
    await _waitFor(_tester, () => isShutDown);
  }

  /// Граф в хранилище: эталонная выгрузка таблиц графа отдельным
  /// соединением, без механизма фактов, в каноническом порядке файла.
  Future<List<String>> graphState() async => (await _tester.runAsync(() async {
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

  /// Задерживает следующую замену графа на её первом операторе удаления
  /// прежнего графа.
  _ReplacementHold holdReplacement() => _statements.hold = _ReplacementHold();

  FileDocumentAccess get documents => _files.documents;

  /// Открывает с Главной страницу «Настройки».
  Future<void> openSettings() async {
    await _tester.tap(find.byTooltip('Настройки'));
    await _until(_tester, find.byType(SettingsPage));
    await _tester.pumpAndSettle();
  }

  /// В системном диалоге выбора человек выбирает документ [file].
  void chooseForImport(File file) =>
      documents.openingDialog = () async => documents.chosen(file);

  /// Начинает импорт строкой «Импорт данных».
  Future<void> startImport() async {
    await _tester.tap(find.text('Импорт данных'));
    await _tester.pump();
  }

  /// Ждёт подтверждения импорта прочитанного файла.
  Future<void> waitForConfirmation() async {
    await _until(_tester, find.text('Импортировать эту копию?'));
    await _tester.pumpAndSettle();
  }

  /// Подтверждает замену графа файлом.
  Future<void> confirmImport() async {
    await _tester.tap(find.text('Импортировать и заменить'));
    await _tester.pump();
  }

  /// Ждёт, пока закроется прогресс импорта.
  Future<void> waitForProgressEnd() =>
      _waitFor(_tester, () => find.text(_importRunning).evaluate().isEmpty);
}

/// Облачная фотография: доступно только начало, запись копии дала бы
/// нехватку места. Следующий выбор использует обычные файловые документы.
final class _PhotoDocumentAccess implements DocumentAccess, DocumentRead {
  DocumentAccess? followingDocuments;
  var remainderRequested = false;
  var copyAttempts = 0;
  var finished = false;

  @override
  Future<DocumentOpening> openDocument() async =>
      followingDocuments?.openDocument() ??
      const DocumentOpened(OpenedDocument('content://cloud/photo.jpg'));

  @override
  DocumentRead readDocument(
    OpenedDocument document, {
    required File destination,
    required Future<void> cancellation,
  }) =>
      followingDocuments?.readDocument(
        document,
        destination: destination,
        cancellation: cancellation,
      ) ??
      this;

  @override
  Stream<List<int>> get prefix async* {
    yield photoFile();
    remainderRequested = true;
    throw DocumentReadFailure.unreadable;
  }

  @override
  Future<DocumentCopy> copy() async {
    copyAttempts++;
    return const DocumentCopyStorageFull();
  }

  @override
  Future<void> finish() async => finished = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Наблюдатель соединения, который задерживает замену графа по [hold].
final class _HeldReplacement extends LocalDatabaseConnectionObserver {
  /// Задержка замены графа; после её освобождения замены идут без
  /// задержки.
  _ReplacementHold? hold;

  @override
  FutureOr<void> beforeStatement(LocalDatabaseSqlStatement statement) {
    final hold = this.hold;
    if (hold == null ||
        !statement.statements.any(
          (sql) => sql.startsWith('DELETE FROM daily_choices '),
        )) {
      return null;
    }
    hold._isReached = true;
    return hold._released.future;
  }
}

/// Задержка замены графа: [isReached] — замена дошла до удаления прежнего
/// графа, а продолжается она после [release].
final class _ReplacementHold {
  final _released = Completer<void>();
  var _isReached = false;

  bool get isReached => _isReached;

  void release() {
    if (!_released.isCompleted) _released.complete();
  }
}

/// Исправный эталонный файл экспорта.
List<int> _referenceFile() => graphExportFileOf(referenceGraphFileLines());

/// Эталонный файл экспорта, описания намерений которого занимают страницы
/// переполнения, которых в сжатом файле хранилища нет.
List<int> _fileWithLongDescriptions() {
  var lines = referenceGraphFileLines();
  for (var line = 3; line <= 6; line++) {
    lines = withEditedLine(lines, line, (intention) {
      intention['description'] = 'ж' * 4000;
    });
  }
  return graphExportFileOf(lines);
}

/// Документ с байтами [bytes] вне каталогов приложения в новом временном
/// каталоге, который удаляется после теста.
File _document(List<int> bytes) {
  final directory = Directory.systemTemp.createTempSync(
    'doable_import_document_',
  );
  addTearDown(() => directory.deleteSync(recursive: true));
  return File.fromUri(directory.uri.resolve('doable.jsonl.gz'))
    ..writeAsBytesSync(bytes);
}

Future<void> _until(WidgetTester tester, Finder finder) =>
    _waitFor(tester, () => finder.evaluate().isNotEmpty);

/// Даёт фоновой работе завершиться: результат, который она показала бы,
/// появился бы за эти шаги.
Future<void> _settle(WidgetTester tester) async {
  for (var step = 0; step < 10; step++) {
    await _advance(tester);
  }
}

/// Продвигает время, пока не выполнится [done].
Future<void> _waitFor(WidgetTester tester, bool Function() done) async {
  for (var step = 0; step < 100 && !done(); step++) {
    await _advance(tester);
  }
  expect(done(), isTrue);
}

/// Один шаг времени: реальное ожидание, в котором идут операции хранилища,
/// копирование документа и изолят записи снимка замены, и кадр через
/// 100 мс.
Future<void> _advance(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pump(const Duration(milliseconds: 100));
}
