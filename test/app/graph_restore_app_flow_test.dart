import 'dart:async';
import 'dart:convert';

import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/home/home_page.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/settings/settings_page.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_local_date_provider.dart';
import 'package:doable/src/data/local/app_database.dart'
    show
        LocalDatabaseConnectionObserver,
        LocalDatabaseSqlStatement,
        observeConfiguredLocalDatabaseConnection,
        openFileBackedLocalDatabase;
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph_backups/graph_backup_registry.dart';
import 'package:doable/src/graph_backups/graph_backups_provider.dart';
import 'package:doable/src/graph_format/graph_format_codec.dart';
import 'package:doable/src/intention/application/intention_catalog.dart'
    show IntentionSaved;
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart';
import 'package:doable/src/intention/presentation/catalog/tag_condition_picker_page.dart';
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
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/app_root_pages.dart';
import '../support/daily_choice_durability_fixture.dart';
import '../support/graph_log_completeness_reference.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/in_memory_quick_creation_mode_store.dart';
import '../support/local_database_harness.dart';
import '../support/temporary_graph_files.dart';

/// Сообщение о нехватке места под строкой «Резервные копии».
const _storageFull =
    'Недостаточно места на устройстве. Освободите место и повторите. '
    'Ничего не изменено';

void main() {
  testWidgets('сценарий «Восстановление отменяет изменения после копии»: '
      'граф совпадает с копией «Сегодня, 08:15», появляется «Копия '
      'восстановлена», а первой в списке стоит копия состояния перед '
      'восстановлением', (tester) async {
    late Intention running;
    final app = await _RestoreApp.start(
      tester,
      at: DateTime(2026, 10, 6, 8, 15),
      seed: (graph) async => running = await _createIntention(graph, 'Бегать'),
    );
    await app.waitForBackups(1);
    final backupState = await app.graphState();
    app.now = DateTime(2026, 10, 6, 8, 40);
    await app.execute(
      const CreateIntention(title: 'Плавать', description: null),
    );
    await app.execute(
      const CreateIntention(title: 'Читать', description: null),
    );
    await app.execute(
      UpdateIntention(
        id: running.id,
        title: running.title,
        description: 'Вечером',
      ),
    );
    await app.openSettings();
    await app.openBackupsSheet();

    await app.chooseBackup(
      'Сегодня, 08:15',
      since:
          'Она сделана сегодня в 08:15. С тех пор: 2 добавлено, 1 изменено. '
          'Восстановление отменит всё это.',
    );
    await app.restoreChosenBackup();
    await _until(tester, find.text('Копия восстановлена'));

    expect(await app.graphState(), backupState);
    await app.openBackupsSheet();
    expect(_sheetBackups(tester), [
      'Сегодня, 08:40',
      '2 добавлено, 1 изменено',
      'Сегодня, 08:15',
      '1 добавлено',
    ]);
  });

  testWidgets('восстановление копии перед заменой возвращает граф к '
      'состоянию до восстановления, как сценарий «Ошибочный импорт '
      'отменяется восстановлением» требует для импорта', (tester) async {
    final app = await _RestoreApp.start(
      tester,
      at: DateTime(2026, 10, 6, 8, 15),
      seed: (graph) => _createTag(graph, 'Дом'),
    );
    await app.waitForBackups(1);
    app.now = DateTime(2026, 10, 6, 8, 40);
    await app.execute(
      const CreateIntention(title: 'Бегать', description: null),
    );
    final beforeRestore = await app.graphState();
    await app.openSettings();
    await app.openBackupsSheet();
    await app.chooseBackup(
      'Сегодня, 08:15',
      since:
          'Она сделана сегодня в 08:15. С тех пор: 1 добавлено. '
          'Восстановление отменит всё это.',
    );
    await app.restoreChosenBackup();
    await app.waitForBackups(2);
    await app.waitForRestoreEnd();
    app.now = DateTime(2026, 10, 6, 8, 50);
    await app.openBackupsSheet();

    await app.chooseBackup(
      'Сегодня, 08:40',
      since:
          'Она сделана сегодня в 08:40. С тех пор данные заменялись. '
          'Восстановление отменит все изменения.',
    );
    await app.restoreChosenBackup();
    await app.waitForBackups(3);
    await app.waitForRestoreEnd();

    expect(await app.graphState(), beforeRestore);
  });

  testWidgets('сценарий «Копия переживает обновление»: вчерашняя копия, '
      'сделанная прежним запуском приложения, после нового запуска '
      'восстанавливает ровно своё состояние', (tester) async {
    final app = await _RestoreApp.start(
      tester,
      at: DateTime(2026, 10, 5, 9),
      seed: (graph) => _createTag(graph, 'Дом'),
    );
    await app.waitForBackups(1);
    final backupState = await app.graphState();
    await app.execute(CreateTag(TagName.fromInput('Сад')));

    // Обновление — новый запуск над тем же хранилищем и каталогом снимков:
    // версия схемы и формата данных у обновлённого приложения та же.
    await app.restart(at: DateTime(2026, 10, 6, 10));
    await app.waitForBackups(2);
    await app.openSettings();
    await app.openBackupsSheet();
    await app.chooseBackup(
      'Вчера, 09:00',
      since:
          'Она сделана вчера в 09:00. С тех пор: 1 добавлено. '
          'Восстановление отменит всё это.',
    );
    await app.restoreChosenBackup();
    await _until(tester, find.text('Копия восстановлена'));

    expect(await app.graphState(), backupState);
  });

  testWidgets('сценарий «Копия после замены графа»: ежедневная копия, '
      'сделанная при запуске на следующий день после восстановления, '
      'показывает «Данные заменены», а копия перед восстановлением — '
      'обычную сводку', (tester) async {
    final app = await _RestoreApp.start(
      tester,
      at: DateTime(2026, 10, 5, 9),
      seed: (graph) => _createTag(graph, 'Дом'),
    );
    await app.waitForBackups(1);
    app.now = DateTime(2026, 10, 5, 14);
    await app.execute(CreateTag(TagName.fromInput('Сад')));
    await app.openSettings();
    await app.openBackupsSheet();
    await app.chooseBackup(
      'Сегодня, 09:00',
      since:
          'Она сделана сегодня в 09:00. С тех пор: 1 добавлено. '
          'Восстановление отменит всё это.',
    );
    await app.restoreChosenBackup();
    await app.waitForBackups(2);
    await app.waitForRestoreEnd();

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
  });

  testWidgets('сценарий «Замена графа сбрасывает корневые страницы»: после '
      'восстановления копии страница «Настройки» остаётся открытой с '
      'выбранным пунктом «Главная», а после её закрытия Главная и каталог '
      'намерений открываются как при новом запуске', (tester) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late Tag health;
    final app = await _RestoreApp.start(
      tester,
      at: DateTime(2026, 10, 6, 8, 15),
      seed: (graph) async {
        health = await _createTag(graph, 'Здоровье');
        for (var number = 1; number <= 40; number++) {
          await _createIntention(graph, 'Намерение $number', tags: {health.id});
        }
      },
    );
    await app.waitForBackups(1);
    await _filterIntentionCatalogByTag(tester, health);
    await openHome(tester, waitFor: _until);
    await _tap(tester, find.text('Год'));
    await _tap(tester, find.byTooltip('Предыдущий год'));
    expect(
      (app.homeSelection.tab, app.homeSelection.period),
      (HomeStatisticsTab.year, StatisticsYear(2025)),
    );
    await app.openSettings();
    await app.openBackupsSheet();
    await app.chooseBackup(
      'Сегодня, 08:15',
      since: 'Она сделана сегодня в 08:15. С тех пор ничего не изменилось.',
    );

    await app.restoreChosenBackup();
    await _until(tester, find.text('Копия восстановлена'));

    expect(find.byType(SettingsPage), findsOneWidget);
    expect(
      tester.widget<AppNavigationBar>(find.byType(AppNavigationBar)).selected,
      AppDestination.home,
    );
    await tester.binding.handlePopRoute();
    await _waitFor(tester, () => find.byType(SettingsPage).evaluate().isEmpty);
    expect(
      (app.homeSelection.tab, app.homeSelection.period),
      (HomeStatisticsTab.month, StatisticsMonth(2026, 10)),
    );
    await openIntentionGraph(tester, waitFor: _until, content: _catalogList);
    expect(_tagConditions(), isEmpty);
    expect(_catalogPosition(tester).pixels, 0);
    expect(_catalogPagePosition(tester).pixels, 0);
  });

  testWidgets('сценарий «Отмена замены»: «Отменить» показывает «Отмена…», '
      'затем прогресс закрывается без сообщения, а граф и список копий '
      'остаются прежними', (tester) async {
    final app = await _RestoreApp.start(
      tester,
      at: DateTime(2026, 10, 6, 8, 15),
      seed: (graph) => _createTag(graph, 'Дом'),
    );
    await app.waitForBackups(1);
    app.now = DateTime(2026, 10, 6, 8, 40);
    await app.execute(CreateTag(TagName.fromInput('Сад')));
    await app.openSettings();
    await app.openBackupsSheet();
    await app.chooseBackup(
      'Сегодня, 08:15',
      since:
          'Она сделана сегодня в 08:15. С тех пор: 1 добавлено. '
          'Восстановление отменит всё это.',
    );
    final before = app.storedState();
    final replacement = app.holdReplacement();
    await app.restoreChosenBackup();
    await _waitFor(tester, () => replacement.isReached);
    await tester.pump();

    await tester.tap(find.text('Отменить'));
    await tester.pump();
    expect(find.text('Отмена…'), findsOneWidget);
    replacement.release();
    await app.waitForRestoreEnd();
    // Сообщение появилось бы за это время и ещё не закрылось бы.
    await _settle(tester);

    expect(find.byKey(const ValueKey('graph-operation-message')), findsNothing);
    expect(app.storedState(), before);
    await app.openBackupsSheet();
    expect(_sheetBackups(tester), ['Сегодня, 08:15', '1 добавлено']);
  });

  testWidgets('сценарии «Прогресс замены читается экранным диктором» и '
      '«„Назад“ не прерывает замену»: диктор сообщает о восстановлении, его '
      'ходе и доступной кнопке «Отменить», а после «назад» прогресс '
      'остаётся открытым и восстановление завершается', (tester) async {
    final semantics = tester.ensureSemantics();
    final app = await _RestoreApp.start(
      tester,
      at: DateTime(2026, 10, 6, 8, 15),
      seed: (graph) => _createTag(graph, 'Дом'),
    );
    await app.waitForBackups(1);
    final backupState = await app.graphState();
    app.now = DateTime(2026, 10, 6, 8, 40);
    await app.execute(CreateTag(TagName.fromInput('Сад')));
    await app.openSettings();
    await app.openBackupsSheet();
    await app.chooseBackup(
      'Сегодня, 08:15',
      since:
          'Она сделана сегодня в 08:15. С тех пор: 1 добавлено. '
          'Восстановление отменит всё это.',
    );
    final replacement = app.holdReplacement();
    await app.restoreChosenBackup();
    await _waitFor(tester, () => replacement.isReached);
    await tester.pump();

    // Снимок замены записан, а замена ещё ничего не удалила.
    expect(
      tester.getSemantics(find.text('Восстановление копии…')),
      isSemantics(label: 'Восстановление копии…', value: '30\u00a0%'),
    );
    expect(
      tester.getSemantics(find.text('Отменить')),
      isSemantics(
        label: 'Отменить',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Восстановление копии…'), findsOneWidget);

    replacement.release();
    await _until(tester, find.text('Копия восстановлена'));

    expect(find.byType(SettingsPage), findsOneWidget);
    expect(await app.graphState(), backupState);
    semantics.dispose();
  });

  testWidgets('сценарий «Не хватает места на устройстве»: восстановление '
      'откатывается, граф и копии остаются прежними, а «Повторить» под '
      'строкой «Резервные копии» снова открывает подтверждение и после '
      'освобождения места восстанавливает копию', (tester) async {
    // Копия с длинными описаниями занимает страницы переполнения, которых
    // после их удаления и сжатия файла в хранилище нет.
    final long = <Intention>[];
    final app = await _RestoreApp.start(
      tester,
      at: DateTime(2026, 10, 6, 8, 15),
      seed: (graph) async {
        for (var number = 1; number <= 4; number++) {
          long.add(
            await _createIntention(
              graph,
              'Намерение $number',
              description: 'ж' * 4000,
            ),
          );
        }
      },
    );
    await app.waitForBackups(1);
    final backupState = await app.graphState();
    app.now = DateTime(2026, 10, 6, 8, 40);
    for (final intention in long) {
      await app.execute(DeleteIntention(intention.id));
    }
    await app.execute(CreateTag(TagName.fromInput('Дом')));
    await app.openSettings();
    app.fillStorage();
    final before = app.storedState();
    const since =
        'Она сделана сегодня в 08:15. С тех пор: 1 добавлено, 4 удалено. '
        'Восстановление отменит всё это.';
    await app.openBackupsSheet();
    await app.chooseBackup('Сегодня, 08:15', since: since);

    await app.restoreChosenBackup();
    await _until(tester, find.text(_storageFull));

    expect(find.text('Восстановление копии…'), findsNothing);
    expect(app.storedState(), before);

    app.freeStorage();
    await tester.tap(find.text('Повторить'));
    await _until(tester, find.text(since));
    await tester.pumpAndSettle();
    await app.restoreChosenBackup();
    await _until(tester, find.text('Копия восстановлена'));

    expect(find.text(_storageFull), findsNothing);
    expect(await app.graphState(), backupState);
  });
}

/// Приложение над файловым хранилищем с часами устройства [now]. Его можно
/// перезапустить над тем же хранилищем и каталогом снимков. Замену графа
/// можно задержать на её первом операторе удаления прежнего графа, а файлу
/// хранилища — запретить расти, как при нехватке места.
final class _RestoreApp {
  _RestoreApp._(this._tester, this._harness, this._files, this.now);

  final WidgetTester _tester;
  final LocalDatabaseHarness _harness;
  final TemporaryGraphFiles _files;
  final _statements = _HeldReplacement();

  /// Показание часов устройства для графа, копий и местного сегодня.
  DateTime now;

  late AppRuntime _runtime;
  late ProviderContainer _container;

  /// Соединение приложения с файлом хранилища.
  late sqlite.Database _storage;
  StreamSubscription<GraphBackupsRead>? _watching;
  List<GraphBackupEntry> _backups = const [];

  /// Запускает приложение в момент [at] над графом, который [seed] создаёт
  /// командами, поэтому он полностью отражён в логе фактов.
  static Future<_RestoreApp> start(
    WidgetTester tester, {
    required DateTime at,
    required Future<void> Function(PersonalGraphRepository graph) seed,
  }) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.platformDispatcher.localesTestValue = const [Locale('ru')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    final harness = (await tester.runAsync(LocalDatabaseHarness.fileBacked))!;
    addTearDown(() => tester.runAsync(harness.dispose));
    final app = _RestoreApp._(tester, harness, TemporaryGraphFiles(), at);
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
    addTearDown(app._shutDown);
    await app._launch();
    return app;
  }

  /// Завершает приложение и в момент [at] запускает его заново.
  Future<void> restart({required DateTime at}) async {
    await _shutDown();
    now = at;
    await _launch();
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
      diagnosticsSink: InMemoryDiagnosticsSink(),
      quickCreationModeStore: InMemoryQuickCreationModeStore(),
      graphFilesFactory: _files.create,
      dailyChoiceLocalDateSource: () => DailyChoiceLocalDay(
        date: CalendarDate.fromParts(now.year, now.month, now.day),
        untilNextDate: const Duration(hours: 12),
      ),
      clock: () => now.toUtc(),
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
    // Выключение дожидается восстановления, а задержанная замена
    // продолжается только после освобождения, в том числе после отказа
    // проверки.
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

  /// Ждёт, пока хранится [count] копий.
  Future<void> waitForBackups(int count) =>
      _waitFor(_tester, () => _backups.length == count);

  /// Выбор Главной: вкладка, период и вид статистики.
  HomeStatisticsSelection get homeSelection =>
      _container.read(homeStatisticsViewModelProvider).selection;

  /// Подтверждает команду графа [command] в хранилище приложения, минуя
  /// экраны, поэтому её результат не занимает общую поверхность сообщений.
  ///
  /// Команда идёт в управляемом времени проверки, как и чтения экранов:
  /// очередь хранилища продолжает её после их завершения.
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
    await _waitFor(_tester, () => result != null);
    expect(result, isA<GraphCommandSucceeded>());
  }

  /// Граф в хранилище: эталонная выгрузка таблиц графа отдельным
  /// соединением, без механизма фактов.
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

  /// Открывает с Главной страницу «Настройки».
  Future<void> openSettings() async {
    await _tester.tap(find.byTooltip('Настройки'));
    await _until(_tester, find.byType(SettingsPage));
    await _tester.pumpAndSettle();
  }

  /// Открывает панель строкой «Резервные копии» и ждёт прочитанный список.
  Future<void> openBackupsSheet() async {
    await _tester.tap(find.text('Резервные копии'));
    await _until(_tester, find.text('Сделать копию сейчас'));
    await _tester.pumpAndSettle();
  }

  /// Выбирает в открытой панели копию [label] и ждёт подтверждения её
  /// восстановления с тем, что изменилось с тех пор, — [since].
  Future<void> chooseBackup(String label, {required String since}) async {
    await _tester.tap(find.text(label));
    await _until(_tester, find.text(since));
    await _tester.pumpAndSettle();
  }

  /// Подтверждает восстановление выбранной копии.
  Future<void> restoreChosenBackup() async {
    await _tester.tap(find.text('Восстановить копию'));
    await _tester.pump();
  }

  /// Ждёт, пока закроется прогресс восстановления.
  Future<void> waitForRestoreEnd() => _waitFor(
    _tester,
    () => find.text('Восстановление копии…').evaluate().isEmpty,
  );
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
  String? description,
  Set<TagId> tags = const {},
}) async => (await _confirm<IntentionSaved>(
  graph,
  CreateIntention.withInitialState(
    title: title,
    description: description,
    readiness: IntentionReadiness.notReady,
    tagIds: tags,
  ),
)).intention;

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
  await openIntentionGraph(tester, waitFor: _until, content: _catalogList);
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
  await _waitFor(
    tester,
    () => find.byType(TagConditionPickerPage).evaluate().isEmpty,
  );
  // Выдача с условием прочитана за эти шаги.
  await _settle(tester);
  for (final position in [
    _catalogPosition(tester),
    _catalogPagePosition(tester),
  ]) {
    position.jumpTo(position.maxScrollExtent / 2);
  }
  await _advance(tester);

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
  await _until(tester, finder);
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
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

/// Один шаг времени: реальное ожидание, в котором идут операции хранилища и
/// изолят записи снимка замены, и кадр через 100 мс.
Future<void> _advance(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pump(const Duration(milliseconds: 100));
}
