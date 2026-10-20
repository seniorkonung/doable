import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/home/home_page.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/app/settings/settings_page.dart';
import 'package:doable/src/daily_choice/application/confirmed_choice_path.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_result.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_local_date_provider.dart';
import 'package:doable/src/data/local/app_database.dart'
    show openFileBackedLocalDatabase;
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph_backups/graph_backup_registry.dart';
import 'package:doable/src/graph_backups/graph_backups_provider.dart';
import 'package:doable/src/graph_format/graph_format_codec.dart';
import 'package:doable/src/graph_format/graph_format_records.dart';
import 'package:doable/src/intention/application/intention_catalog.dart'
    show IntentionSaved;
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart';
import 'package:doable/src/intention/presentation/catalog/tag_condition_picker_page.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/statistics/application/statistics_period.dart';
import 'package:doable/src/statistics/presentation/home_statistics_state.dart';
import 'package:doable/src/statistics/presentation/home_statistics_view_model.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_flow_wait.dart' as app_flow;
import '../support/app_root_pages.dart';
import '../support/daily_choice_durability_fixture.dart';
import '../support/file_document_access.dart';
import '../support/graph_import_files.dart';
import '../support/graph_log_completeness_reference.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/in_memory_quick_creation_mode_store.dart';
import '../support/local_database_harness.dart';
import '../support/quick_creation.dart';
import '../support/temporary_graph_files.dart';

void main() {
  testWidgets('сценарии «Импорт экспорта воспроизводит граф», «Настройки '
      'установки не переносятся» и «Импорт в пустой граф без подтверждения»: '
      'новая установка без подтверждения импортирует файл экспорта другой '
      'установки с теми же сущностями, данными, порядками и путём дневного '
      'выбора, а её режим быстрого создания остаётся прежним', (tester) async {
    late _ExportedGraph exported;
    final source = await _ImportApp.start(
      tester,
      at: DateTime(2026, 10, 3, 12),
      quickCreationMode: QuickCreationMode.dailyChoice,
      seed: (graph) async => exported = await _seedExportedGraph(graph),
    );
    final sourceGraph = await source.graphState();
    await source.openSettings();
    expectQuickCreationMode(tester, QuickCreationMode.dailyChoice);
    final file = await source.export();
    await source.shutDown();

    final target = await _ImportApp.start(
      tester,
      at: DateTime(2026, 10, 6, 9),
      quickCreationMode: QuickCreationMode.intention,
    );
    await target.openSettings();
    target.chooseForImport(file);
    // Импорт в пустой граф не ждёт подтверждения: без него замена не
    // началась бы, и сообщения об успехе не было бы.
    await target.startImport();
    await app_flow.until(tester, find.text('Данные импортированы'));

    expect(find.byType(SettingsPage), findsOneWidget);
    expect(await target.graphState(), sourceGraph);
    expectQuickCreationMode(tester, QuickCreationMode.intention);
    await target.openTagNavigation(
      exported.tag,
      intention: exported.assignedSecond,
    );
    expect(
      tester.getTopLeft(find.byKey(ValueKey(exported.assignedFirst))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(ValueKey(exported.assignedSecond))).dy,
      ),
    );
  });

  testWidgets('сценарии «Подтверждение показывает дату и состав файла», '
      '«Копия после замены графа» и «Ошибочный импорт отменяется '
      'восстановлением»: подтверждение называет дату и состав файла, пока '
      'граф не изменён, ежедневная копия после импорта показывает «Данные '
      'заменены», а восстановление копии перед импортом возвращает прежний '
      'граф', (tester) async {
    final app = await _ImportApp.start(
      tester,
      at: DateTime(2026, 10, 5, 9),
      seed: (graph) => _createTag(graph, 'Дом'),
    );
    await app.waitForBackups(1);
    app.now = DateTime(2026, 10, 5, 14);
    await app.execute(CreateTag(TagName.fromInput('Сад')));
    final beforeImport = await app.graphState();
    final stored = app.storedState();
    await app.openSettings();
    app.chooseForImport(_document(_referenceFileSavedOnOctober3()));

    await app.startImport();
    await app.waitForConfirmation();

    expect(
      find.text(
        'Она сохранена 3 октября 2026 года и содержит 4 намерения, 3 связи, '
        '2 дневных выбора и 2 тега.',
      ),
      findsOneWidget,
    );
    expect(app.storedState(), stored);

    await app.confirmImport();
    await app_flow.until(tester, find.text('Данные импортированы'));
    expect(find.byType(SettingsPage), findsOneWidget);
    await app.waitForBackups(2);

    await app.restart(at: DateTime(2026, 10, 6, 9, 10));
    await app.waitForBackups(3);
    await app.openSettings();
    await app.openBackupsSheet();
    expect(_sheetBackups(tester), [
      'Сегодня, 09:10',
      'Данные заменены',
      'Вчера, 14:00',
      '1 добавлено',
      'Вчера, 09:00',
      '1 добавлено',
    ]);

    await app.chooseBackup(
      'Вчера, 14:00',
      since:
          'Она сделана вчера в 14:00. С тех пор данные заменялись. '
          'Восстановление отменит все изменения.',
    );
    await app.restoreChosenBackup();
    await app_flow.until(tester, find.text('Копия восстановлена'));

    expect(await app.graphState(), beforeImport);
  });

  testWidgets('сценарий «Замена графа сбрасывает корневые страницы»: после '
      'импорта файла экспорта страница «Настройки» остаётся открытой с '
      'выбранным пунктом «Главная», а после её закрытия Главная и каталог '
      'намерений открываются как при новом запуске', (tester) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late Tag health;
    final app = await _ImportApp.start(
      tester,
      at: DateTime(2026, 10, 6, 8, 15),
      seed: (graph) async {
        health = await _createTag(graph, 'Здоровье');
        for (var number = 1; number <= 40; number++) {
          await _createIntention(graph, 'Намерение $number', tags: {health.id});
        }
      },
    );
    // Файл содержит тот же граф, поэтому без сброса каталог сохранил бы
    // условие по тегу и позицию прокрутки.
    await app.openSettings();
    final file = await app.export();
    await tester.binding.handlePopRoute();
    await app_flow.waitFor(
      tester,
      () => find.byType(SettingsPage).evaluate().isEmpty,
    );
    await _filterIntentionCatalogByTag(tester, health);
    await openHome(tester, waitFor: app_flow.until);
    await _tap(tester, find.text('Год'));
    await _tap(tester, find.byTooltip('Предыдущий год'));
    expect(
      (app.homeSelection.tab, app.homeSelection.period),
      (HomeStatisticsTab.year, StatisticsYear(2025)),
    );
    await app.openSettings();
    app.chooseForImport(file);
    await app.startImport();
    await app.waitForConfirmation();

    await app.confirmImport();
    await app_flow.until(tester, find.text('Данные импортированы'));

    expect(find.byType(SettingsPage), findsOneWidget);
    expect(
      tester.widget<AppNavigationBar>(find.byType(AppNavigationBar)).selected,
      AppDestination.home,
    );
    await tester.binding.handlePopRoute();
    await app_flow.waitFor(
      tester,
      () => find.byType(SettingsPage).evaluate().isEmpty,
    );
    expect(
      (app.homeSelection.tab, app.homeSelection.period),
      (HomeStatisticsTab.month, StatisticsMonth(2026, 10)),
    );
    await openIntentionGraph(
      tester,
      waitFor: app_flow.until,
      content: _catalogList,
    );
    expect(_tagConditions(), isEmpty);
    expect(_catalogPosition(tester).pixels, 0);
    expect(_catalogPagePosition(tester).pixels, 0);
  });
}

/// Приложение над файловым хранилищем своей установки с часами устройства
/// [now]. Его можно перезапустить над тем же хранилищем и каталогом снимков.
/// Документы экспорта и импорта — файлы без системных диалогов.
final class _ImportApp {
  _ImportApp._(this._tester, this._harness, this._files, this._modes, this.now);

  final WidgetTester _tester;
  final LocalDatabaseHarness _harness;
  final TemporaryGraphFiles _files;

  /// Настройка установки — режим быстрого создания.
  final InMemoryQuickCreationModeStore _modes;

  /// Показание часов устройства для графа, экспорта, копий и местного
  /// сегодня.
  DateTime now;

  late AppRuntime _runtime;
  late ProviderContainer _container;
  var _isRunning = false;
  StreamSubscription<GraphBackupsRead>? _watching;
  List<GraphBackupEntry> _backups = const [];

  /// Запускает приложение новой установки в момент [at] с режимом быстрого
  /// создания [quickCreationMode]. [seed] создаёт граф командами, поэтому он
  /// полностью отражён в логе фактов; без [seed] граф пуст.
  static Future<_ImportApp> start(
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
    final app = _ImportApp._(
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
      connectionFactory: () =>
          openFileBackedLocalDatabase(_harness.databaseFile),
      diagnosticsSink: InMemoryDiagnosticsSink(),
      quickCreationModeStore: _modes,
      graphFilesFactory: _files.create,
      dailyChoiceLocalDateSource: () => DailyChoiceLocalDay(
        date: CalendarDate.fromParts(now.year, now.month, now.day),
        untilNextDate: const Duration(hours: 12),
      ),
      clock: () => now.toUtc(),
    );
    final ready =
        (await _tester.runAsync(runtime.bootstrap))! as AppRuntimeReady;
    _isRunning = true;
    _container = ready.container;
    _watching = _container.read(graphBackupsProvider).watchBackups().listen((
      read,
    ) {
      if (read case GraphBackupsReadSucceeded(:final backups)) {
        _backups = backups;
      }
    });
    await _tester.pumpWidget(MainApp(runtime: runtime));
    await app_flow.until(_tester, find.byType(HomePage));
    await app_flow.waitFor(
      _tester,
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
  }

  /// Завершает приложение; завершённое приложение ничего не делает.
  Future<void> shutDown() async {
    if (!_isRunning) return;
    _isRunning = false;
    // Отмена наблюдения завершается вне управляемого времени проверки, и
    // ожидание продолжило бы проверку вне него.
    if (_watching case final watching?) unawaited(watching.cancel());
    _watching = null;
    await _tester.pumpWidget(const SizedBox.shrink());
    var isShutDown = false;
    unawaited(_runtime.shutdown().whenComplete(() => isShutDown = true));
    await app_flow.waitFor(_tester, () => isShutDown);
  }

  /// Ждёт, пока хранится [count] копий.
  Future<void> waitForBackups(int count) =>
      app_flow.waitFor(_tester, () => _backups.length == count);

  /// Выбор Главной: вкладка, период и вид статистики.
  HomeStatisticsSelection get homeSelection =>
      _container.read(homeStatisticsViewModelProvider).selection;

  /// Подтверждает команду графа [command] в хранилище приложения, минуя
  /// экраны, поэтому её результат не занимает общую поверхность сообщений.
  Future<void> execute(
    GraphCommand<GraphCommandOutcome, GraphCommandFailure> command,
  ) async {
    Object? result;
    unawaited(
      _container
          .read(personalGraphRepositoryProvider)
          .execute(command)
          .then((value) => result = value),
    );
    await app_flow.waitFor(_tester, () => result != null);
    expect(result, isA<GraphCommandSucceeded>());
  }

  /// Граф в хранилище: эталонная выгрузка таблиц графа отдельным
  /// соединением, без механизма фактов. Записи идут по последовательностям
  /// создания, поэтому выгрузки совпадают, только если совпадают и порядки.
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

  FileDocumentAccess get _documents => _files.documents;

  /// Открывает с Главной страницу «Настройки».
  Future<void> openSettings() async {
    await _tester.tap(find.byTooltip('Настройки'));
    await app_flow.until(_tester, find.byType(SettingsPage));
    await _tester.pumpAndSettle();
  }

  /// Сохраняет граф в новый документ панелью «Экспорт данных» и возвращает
  /// файл документа после сообщения об успехе.
  Future<File> export() async {
    // Пока состав графа не прочитан, строка недоступна.
    await app_flow.until(_tester, find.text('Сохранить копию всего в файл'));
    await _tester.tap(find.text('Экспорт данных'));
    await app_flow.until(_tester, find.text('Сохранить в файл'));
    await _tester.pumpAndSettle();
    await _tester.tap(find.text('Сохранить в файл'));
    await app_flow.until(_tester, find.text('Данные сохранены в файл'));
    return _documents.created.single;
  }

  /// В системном диалоге выбора человек выбирает документ [file].
  void chooseForImport(File file) =>
      _documents.openingDialog = () async => _documents.chosen(file);

  /// Начинает импорт строкой «Импорт данных».
  Future<void> startImport() async {
    await _tester.tap(find.text('Импорт данных'));
    await _tester.pump();
  }

  /// Ждёт подтверждения импорта прочитанного файла.
  Future<void> waitForConfirmation() async {
    await app_flow.until(_tester, find.text('Импортировать эту копию?'));
    await _tester.pumpAndSettle();
  }

  /// Подтверждает замену графа файлом.
  Future<void> confirmImport() async {
    await _tester.tap(find.text('Импортировать и заменить'));
    await _tester.pump();
  }

  /// Открывает навигацию по тегу [tag] и ждёт в её выдаче намерение
  /// [intention].
  Future<void> openTagNavigation(
    TagId tag, {
    required IntentionId intention,
  }) async {
    unawaited(
      _container.read(appRouterProvider).push(TagNavigationRoute(tagId: tag)),
    );
    await app_flow.until(_tester, find.byKey(ValueKey(intention)));
    await _tester.pumpAndSettle();
  }

  /// Открывает панель строкой «Резервные копии» и ждёт прочитанный список.
  Future<void> openBackupsSheet() async {
    await _tester.tap(find.text('Резервные копии'));
    await app_flow.until(_tester, find.text('Сделать копию сейчас'));
    await _tester.pumpAndSettle();
  }

  /// Выбирает в открытой панели копию [label] и ждёт подтверждения её
  /// восстановления с тем, что изменилось с тех пор, — [since].
  Future<void> chooseBackup(String label, {required String since}) async {
    await _tester.tap(find.text(label));
    await app_flow.until(_tester, find.text(since));
    await _tester.pumpAndSettle();
  }

  /// Подтверждает восстановление выбранной копии.
  Future<void> restoreChosenBackup() async {
    await _tester.tap(find.text('Восстановить копию'));
    await _tester.pump();
  }
}

/// Граф файла экспорта сценария «Импорт экспорта воспроизводит граф»: тег
/// [tag] назначен сначала намерению [assignedFirst], а затем намерению
/// [assignedSecond], созданному раньше него.
typedef _ExportedGraph = ({
  TagId tag,
  IntentionId assignedFirst,
  IntentionId assignedSecond,
});

/// Создаёт командами граф сценария «Импорт экспорта воспроизводит граф»:
/// архивированное намерение «Читать», две связи «нужно» намерения «Здоровье»
/// с P2, созданные одна за другой, сначала к «Бегать», затем к созданному
/// раньше «Плавать», дневной выбор, путь которого проходит через ныне
/// архивированную связь «Здоровье» → «Бегать», и тег «Утро», назначенный
/// сначала «Бегать», затем «Плавать».
Future<_ExportedGraph> _seedExportedGraph(PersonalGraphRepository graph) async {
  final health = await _createIntention(graph, 'Здоровье');
  final swimming = await _createIntention(
    graph,
    'Плавать',
    readiness: IntentionReadiness.ready,
  );
  final running = await _createIntention(
    graph,
    'Бегать',
    readiness: IntentionReadiness.ready,
  );
  final reading = await _createIntention(graph, 'Читать');
  await _execute(graph, ArchiveIntention(reading.id));
  final needsRunning = await _createNeed(graph, health, running);
  await _createNeed(graph, health, swimming);
  await _confirm<DailyChoiceCreated>(
    graph,
    CreateDailyChoice(
      sourceIntentionId: health.id,
      selectedIntentionId: running.id,
      path: ConfirmedChoicePath([
        ConfirmedChoicePathStep(
          relationId: needsRunning.id,
          sourceIntentionId: health.id,
          type: LongTermRelationType.need,
          relatedIntentionId: running.id,
        ),
      ]),
      date: CalendarDate.fromParts(2026, 10, 3),
      description: null,
      isCompleted: false,
    ),
  );
  await _execute(graph, ArchiveLongTermRelation(needsRunning.id));
  final morning = await _createTag(graph, 'Утро');
  await _execute(graph, AssignTag(tagId: morning.id, intentionId: running.id));
  await _execute(graph, AssignTag(tagId: morning.id, intentionId: swimming.id));
  return (
    tag: morning.id,
    assignedFirst: running.id,
    assignedSecond: swimming.id,
  );
}

/// Эталонный файл экспорта, сохранённый в полдень 3 октября 2026 года по
/// местному времени, — в этот день в любом часовом поясе проверки.
List<int> _referenceFileSavedOnOctober3() {
  final lines = referenceGraphFileLines();
  final (:header, version: _) = GraphFormatCodec.decodeHeader(
    utf8.encode(lines.first),
  );
  return graphExportFileOf([
    utf8.decode(
      GraphFormatCodec.encodeHeader(
        GraphFormatHeader(
          writtenAt: DateTime(2026, 10, 3, 12),
          counts: header.counts,
        ),
      ),
    ),
    ...lines.skip(1),
  ]);
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

Future<void> _execute(
  PersonalGraphRepository graph,
  GraphCommand<GraphCommandOutcome, GraphCommandFailure> command,
) async => expect(await graph.execute(command), isA<GraphCommandSucceeded>());

Future<T> _confirm<T extends GraphCommandOutcome>(
  PersonalGraphRepository graph,
  GraphCommand<GraphCommandOutcome, GraphCommandFailure> command,
) async {
  final result = await graph.execute(command);
  final confirmed =
      (result as GraphResultSuccess<Object?, GraphCommandFailure>).value!
          as ConfirmedGraphResult;
  return confirmed.value as T;
}

Future<Tag> _createTag(PersonalGraphRepository graph, String name) async =>
    (await _confirm<TagCreated>(graph, CreateTag(TagName.fromInput(name)))).tag;

Future<Intention> _createIntention(
  PersonalGraphRepository graph,
  String title, {
  IntentionReadiness readiness = IntentionReadiness.notReady,
  Set<TagId> tags = const {},
}) async => (await _confirm<IntentionSaved>(
  graph,
  CreateIntention.withInitialState(
    title: title,
    description: null,
    readiness: readiness,
    tagIds: tags,
  ),
)).intention;

/// Создаёт связь «нужно» с приоритетом P2 от [source] к [related].
Future<LongTermRelation> _createNeed(
  PersonalGraphRepository graph,
  Intention source,
  Intention related,
) async => (await _confirm<LongTermRelationCreated>(
  graph,
  CreateLongTermRelation(
    sourceIntentionId: source.id,
    relatedIntentionId: related.id,
    type: LongTermRelationType.need,
    priority: RelationPriority.p2,
    description: null,
  ),
)).relation;

/// Моменты и сводки копий в открытой панели по порядку, без заголовка,
/// пояснения и кнопки ручной копии.
List<String?> _sheetBackups(WidgetTester tester) {
  final texts = tester
      .widgetList<Text>(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Text),
        ),
      )
      .map((text) => text.data)
      .toList();
  return texts.sublist(2, texts.length - 1);
}

/// Выдача каталога намерений.
final _catalogList = find.byKey(
  const PageStorageKey<String>('intention-catalog-list'),
);

/// Открывает каталог намерений, задаёт условие «есть тег» [tag] и
/// прокручивает выдачу и страницу.
Future<void> _filterIntentionCatalogByTag(WidgetTester tester, Tag tag) async {
  await openIntentionGraph(
    tester,
    waitFor: app_flow.until,
    content: _catalogList,
  );
  await _tap(
    tester,
    find.byKey(const ValueKey('intention-tag-conditions-add')),
  );
  await _tap(
    tester,
    find.byKey(
      ValueKey(
        'tag-condition-picker-mustBePresent-${tag.id.toCanonicalString()}',
      ),
    ),
  );
  await app_flow.waitFor(
    tester,
    () => find.byType(TagConditionPickerPage).evaluate().isEmpty,
  );
  // Выдача с условием прочитана за эти шаги.
  await app_flow.settle(tester);
  for (final position in [
    _catalogPosition(tester),
    _catalogPagePosition(tester),
  ]) {
    position.jumpTo(position.maxScrollExtent / 2);
  }
  await app_flow.advance(tester);

  expect(_tagConditions(), [tag.name.value]);
  expect(_catalogPosition(tester).pixels, isPositive);
  expect(_catalogPagePosition(tester).pixels, isPositive);
}

/// Названия тегов в условиях каталога намерений.
List<String?> _tagConditions() => [
  for (final label
      in find
          .descendant(
            of: find.byType(IntentionCatalogPage),
            matching: find.byKey(
              const ValueKey('intention-tag-condition-label'),
            ),
          )
          .evaluate())
    (label.widget as Text).data,
];

ScrollPosition _positionOf(WidgetTester tester, Finder scrollView) => tester
    .state<ScrollableState>(
      find.descendant(of: scrollView, matching: find.byType(Scrollable)).first,
    )
    .position;

/// Позиция прокрутки выдачи каталога намерений.
ScrollPosition _catalogPosition(WidgetTester tester) =>
    _positionOf(tester, _catalogList);

/// Позиция прокрутки страницы каталога намерений: параметры поиска и выдача
/// прокручиваются вместе.
ScrollPosition _catalogPagePosition(WidgetTester tester) => _positionOf(
  tester,
  find.descendant(
    of: find.byType(IntentionCatalogPage),
    matching: find.byType(CustomScrollView),
  ),
);

/// Дожидается элемента [finder], доводит его до видимости и нажимает.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await app_flow.until(tester, finder);
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}
