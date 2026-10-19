import 'dart:async';
import 'dart:io';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/home/home_page.dart';
import 'package:doable/src/app/settings/settings_page.dart';
import 'package:doable/src/data/local/app_database.dart' hide GraphBackups;
import 'package:doable/src/data_transfer/presentation/backups_sheet.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph/presentation/graph_operation_presenter.dart';
import 'package:doable/src/graph_backups/graph_backup_registry.dart';
import 'package:doable/src/graph_backups/graph_backups.dart';
import 'package:doable/src/graph_backups/graph_backups_provider.dart';
import 'package:doable/src/graph_backups/graph_change_summary.dart';
import 'package:doable/src/graph_snapshots/graph_log_compaction.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/in_memory_quick_creation_mode_store.dart';
import '../../support/temporary_graph_files.dart';

/// Текущий момент проверок со списком копий: 7 октября 2026 года, полдень.
final _now = DateTime(2026, 10, 7, 12);

void main() {
  // Общая поверхность показывает сообщения только в приложении с фокусом.
  setUp(() {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  for (final (language, texts) in [
    (
      'ru',
      [
        'Резервные копии',
        'Копия делается каждый день, если данные менялись, и хранится на этом '
            'устройстве. Остаются 7 последних ежедневных копий. Выберите '
            'копию, чтобы восстановить её.',
        'Сегодня, 08:15',
        '3 добавлено, 2 изменено, 1 удалено',
        'Вчера, 21:40',
        '4 добавлено, 1 удалено',
        '5 октября, 09:05',
        'Нет изменений',
        '4 октября, 14:00',
        'Данные заменены',
        '3 октября 2025, 10:00',
        '2 изменено',
        'Сделать копию сейчас',
      ],
    ),
    (
      'en',
      [
        'Backups',
        'A copy is made each day your data changes and stays on this device. '
            'The 7 most recent daily copies are kept. Choose a copy to '
            'restore it.',
        'Today, 8:15\u202fAM',
        '3 added, 2 changed, 1 removed',
        'Yesterday, 9:40\u202fPM',
        '4 added, 1 removed',
        '5 October, 9:05\u202fAM',
        'No changes',
        '4 October, 2:00\u202fPM',
        'Data replaced',
        '3 October 2025, 10:00\u202fAM',
        '2 changed',
        'Back up now',
      ],
    ),
  ]) {
    testWidgets('$language: панель показывает пояснение, копии от новых к '
        'старым с моментами и сводками без нулевых частей и кнопку', (
      tester,
    ) async {
      await _openListedSheet(
        tester,
        language: language,
        backups: [
          _backup(DateTime(2026, 10, 7, 8, 15), _counts(3, 2, 1)),
          _backup(DateTime(2026, 10, 6, 21, 40), _counts(4, 0, 1)),
          _backup(DateTime(2026, 10, 5, 9, 5), _counts(0, 0, 0)),
          _backup(DateTime(2026, 10, 4, 14), const GraphDataReplaced()),
          _backup(DateTime(2025, 10, 3, 10), _counts(0, 2, 0)),
        ],
      );

      expect(_sheetTexts(tester), texts);
    });
  }

  for (final (language, summaries) in [
    (
      'ru',
      [
        '1 добавлено, 2 изменено, 5 удалено',
        '2 добавлено, 5 изменено, 21 удалено',
        '5 добавлено, 21 изменено, 1 удалено',
        '21 добавлено, 1 изменено, 2 удалено',
      ],
    ),
    (
      'en',
      [
        '1 added, 2 changed, 5 removed',
        '2 added, 5 changed, 21 removed',
        '5 added, 21 changed, 1 removed',
        '21 added, 1 changed, 2 removed',
      ],
    ),
  ]) {
    testWidgets('$language: сводки согласуют числа 1, 2, 5 и 21 по правилам '
        'языка', (tester) async {
      await _openListedSheet(
        tester,
        language: language,
        backups: [
          _backup(DateTime(2026, 10, 7, 11), _counts(1, 2, 5)),
          _backup(DateTime(2026, 10, 7, 10), _counts(2, 5, 21)),
          _backup(DateTime(2026, 10, 7, 9), _counts(5, 21, 1)),
          _backup(DateTime(2026, 10, 7, 8), _counts(21, 1, 2)),
        ],
      );

      for (final summary in summaries) {
        expect(find.text(summary), findsOneWidget);
      }
    });
  }

  testWidgets('после перевода часов назад панель сохраняет порядок создания '
      'копий, а не их моментов', (tester) async {
    await _openListedSheet(
      tester,
      backups: [
        _backup(DateTime(2026, 10, 6, 21, 40), _counts(1, 0, 0)),
        _backup(DateTime(2026, 10, 7, 8, 15), _counts(0, 1, 0)),
      ],
    );

    expect(_sheetTexts(tester).skip(2), [
      'Вчера, 21:40',
      '1 добавлено',
      'Сегодня, 08:15',
      '1 изменено',
      'Сделать копию сейчас',
    ]);
  });

  testWidgets('en: при 24-часовом формате устройства время копии '
      'показывается в 24-часовом формате', (tester) async {
    await _openListedSheet(
      tester,
      language: 'en',
      alwaysUse24HourFormat: true,
      backups: [_backup(DateTime(2026, 10, 6, 21, 40), _counts(1, 0, 0))],
    );

    expect(find.text('Yesterday, 21:40'), findsOneWidget);
  });

  for (final (language, labels) in [
    (
      'ru',
      [
        'Восстановить копию от сегодня, 08:15\nНет изменений',
        'Восстановить копию от вчера, 21:40\n'
            '4 добавлено, 1 изменено, 1 удалено',
        'Восстановить копию от 5 октября, 09:05\nДанные заменены',
      ],
    ),
    (
      'en',
      [
        'Restore the copy from today, 8:15\u202fAM\nNo changes',
        'Restore the copy from yesterday, 9:40\u202fPM\n'
            '4 added, 1 changed, 1 removed',
        'Restore the copy from 5 October, 9:05\u202fAM\nData replaced',
      ],
    ),
  ]) {
    testWidgets('$language: сценарий «Копия читается экранным диктором»: '
        'диктор называет восстановление копии от её момента и изменения', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _openListedSheet(
        tester,
        language: language,
        backups: [
          _backup(DateTime(2026, 10, 7, 8, 15), _counts(0, 0, 0)),
          _backup(DateTime(2026, 10, 6, 21, 40), _counts(4, 1, 1)),
          _backup(DateTime(2026, 10, 5, 9, 5), const GraphDataReplaced()),
        ],
      );

      for (final label in labels) {
        expect(
          tester.getSemantics(find.text(label.split('\n').last)),
          isSemantics(label: label, isButton: true, hasTapAction: true),
        );
      }
      semantics.dispose();
    });
  }

  testWidgets('при отказе чтения копий панель вместо списка показывает '
      '«Не удалось загрузить копии» и кнопку', (tester) async {
    await _openSheet(
      tester,
      overrides: [
        graphBackupListProvider.overrideWith(
          (ref) => Stream.value(const GraphBackupsReadFailed()),
        ),
        graphBackupsClockProvider.overrideWithValue(() => _now),
      ],
    );

    expect(_sheetTexts(tester).skip(2), [
      'Не удалось загрузить копии',
      'Сделать копию сейчас',
    ]);
  });

  testWidgets('сценарий «Первая копия делается вручную»: «Сделать копию '
      'сейчас», нажатое дважды, делает одну копию, которая появляется в '
      'списке без прогресса и сообщения', (tester) async {
    final app = await _BackupsApp.open(tester);
    await app.createTag('Дом');
    final insert = app.storage.holdBackupInsert();

    await tester.tap(find.text('Сделать копию сейчас'));
    await tester.pump();
    await tester.tap(find.text('Сделать копию сейчас'));
    await tester.pump();
    expect(find.byType(ProgressIndicator), findsNothing);
    insert.release();
    await tester.pumpAndSettle();

    expect(_sheetTexts(tester).skip(2), [
      'Сегодня, 09:00',
      '1 добавлено',
      'Сделать копию сейчас',
    ]);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('отказ ручной копии оставляет список и кнопку прежними, а '
      '«Не удалось сделать копию» появляется только после закрытия панели', (
    tester,
  ) async {
    final app = await _BackupsApp.open(tester);
    await app.createTag('Дом');
    await tester.tap(find.text('Сделать копию сейчас'));
    await tester.pumpAndSettle();
    await app.createTag('Сад');
    app.storage.failsBackupInsert = true;

    await tester.tap(find.text('Сделать копию сейчас'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(_sheetTexts(tester).skip(2), [
      'Сегодня, 09:00',
      '1 добавлено',
      'Сделать копию сейчас',
    ]);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Сделать копию сейчас'),
          )
          .onPressed,
      isNotNull,
    );
    expect(find.text('Не удалось сделать копию').hitTestable(), findsNothing);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Не удалось сделать копию').hitTestable(), findsOneWidget);
  });

  testWidgets('выбор копии открывает над панелью подтверждение с тем, что '
      'изменилось с тех пор, а «Отмена» оставляет панель и граф прежними', (
    tester,
  ) async {
    final app = await _RestoreFromSheetApp.open(tester);

    await app.chooseBackup();

    expect(
      find.text(
        'Она сделана сегодня в 09:00. С тех пор: 1 добавлено. '
        'Восстановление отменит всё это.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(_sheetTexts(tester).skip(2), [
      'Сегодня, 09:00',
      '1 добавлено',
      'Сделать копию сейчас',
    ]);
    expect(await app.backupKinds(), [GraphBackupKind.daily]);
    expect(await app.tagNames(), ['Дом', 'Сад']);
  });

  testWidgets('«Восстановить копию», нажатое дважды, закрывает подтверждение '
      'и панель и один раз восстанавливает копию под прогрессом над '
      'страницей «Настройки»', (tester) async {
    final app = await _RestoreFromSheetApp.open(tester);
    await app.chooseBackup();

    await tester.tap(find.text('Восстановить копию'));
    await tester.pump();
    await tester.tap(find.text('Восстановить копию'), warnIfMissed: false);
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Восстановить эту копию?'), findsNothing);
    expect(find.text('Восстановление копии…'), findsOneWidget);
    expect(find.byType(SettingsPage), findsOneWidget);
    await _waitFor(
      tester,
      () => find.text('Копия восстановлена').evaluate().isNotEmpty,
    );
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(await app.backupKinds(), [
      GraphBackupKind.beforeReplacement,
      GraphBackupKind.daily,
    ]);
    expect(await app.tagNames(), ['Дом']);
  });
}

GraphChangeCounts _counts(int added, int changed, int deleted) =>
    GraphChangeCounts(added: added, changed: changed, deleted: deleted);

var _nextBackupId = 0;

GraphBackupEntry _backup(DateTime madeAt, GraphChangeSummary summary) {
  final id = ++_nextBackupId;
  return GraphBackupEntry(
    id: GraphBackupId(id),
    kind: GraphBackupKind.daily,
    position: id,
    madeAt: madeAt,
    summary: summary,
  );
}

/// Тексты открытой панели сверху вниз.
List<String?> _sheetTexts(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(Text),
      ),
    )
    .map((text) => text.data)
    .toList();

/// Открывает панель со списком копий [backups] в момент [_now].
Future<void> _openListedSheet(
  WidgetTester tester, {
  required List<GraphBackupEntry> backups,
  String language = 'ru',
  bool alwaysUse24HourFormat = false,
}) => _openSheet(
  tester,
  language: language,
  alwaysUse24HourFormat: alwaysUse24HourFormat,
  overrides: [
    graphBackupListProvider.overrideWith(
      (ref) => Stream.value(GraphBackupsReadSucceeded(backups)),
    ),
    graphBackupsClockProvider.overrideWithValue(() => _now),
  ],
);

/// Страница с общей поверхностью результатов, открывающая панель копий, на
/// устройстве с форматом времени [alwaysUse24HourFormat].
Future<void> _openSheet(
  WidgetTester tester, {
  required List<Override> overrides,
  String language = 'ru',
  bool alwaysUse24HourFormat = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: doableTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(alwaysUse24HourFormat: alwaysUse24HourFormat),
          child: GraphOperationPresenter(
            child: child ?? const SizedBox.shrink(),
          ),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showBackupsSheet(context),
                child: const Text('Открыть панель'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Открыть панель'));
  await tester.pumpAndSettle();
  expect(find.byType(BottomSheet), findsOneWidget);
}

/// Панель копий над настоящим хранилищем графа в памяти с часами,
/// остановленными 7 октября 2026 года в 09:00.
final class _BackupsApp {
  _BackupsApp._(this._repository, this.storage);

  final DriftPersonalGraphRepository _repository;
  final _BackupInsertControl storage;

  static Future<_BackupsApp> open(WidgetTester tester) async {
    final storage = _BackupInsertControl();
    final database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(),
        storage,
      ),
    );
    await database.open();
    addTearDown(database.close);
    DateTime clock() => DateTime(2026, 10, 7, 9);
    final repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      clock,
      InMemoryDiagnosticsSink(),
    );
    final backups = GraphBackups(
      registry: repository,
      // Ручная копия читает через сжатие только пакеты лога, а снимков не
      // пишет.
      compaction: GraphLogCompaction(
        log: repository,
        directory: Directory.systemTemp,
        clock: clock,
        diagnosticsSink: InMemoryDiagnosticsSink(),
      ),
      clock: clock,
      diagnosticsSink: InMemoryDiagnosticsSink(),
    );
    await _openSheet(
      tester,
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
        graphBackupsProvider.overrideWithValue(backups),
        graphBackupsClockProvider.overrideWithValue(clock),
      ],
    );
    return _BackupsApp._(repository, storage);
  }

  Future<void> createTag(String name) async {
    expect(
      await _repository.execute(CreateTag(TagName.fromInput(name))),
      isA<GraphCommandSucceeded>(),
    );
  }
}

/// Задерживает или отклоняет запись копии в реестр.
final class _BackupInsertControl extends LocalDatabaseConnectionObserver {
  var failsBackupInsert = false;
  Completer<void>? _held;

  /// Задерживает следующую запись копии до `release`.
  ({void Function() release}) holdBackupInsert() {
    final held = _held = Completer<void>();
    return (release: held.complete);
  }

  @override
  FutureOr<void> beforeStatement(LocalDatabaseSqlStatement statement) {
    if (statement.operation != LocalDatabaseSqlOperation.insert ||
        !statement.statements.single.contains('"graph_backups"')) {
      return null;
    }
    if (failsBackupInsert) {
      throw sqlite.SqliteException(
        extendedResultCode: sqlite.SqlError.SQLITE_FULL,
        message: 'database or disk is full',
      );
    }
    final held = _held;
    _held = null;
    return held?.future;
  }
}

/// Приложение новой установки на странице «Настройки» с панелью копий,
/// открытой строкой «Резервные копии». В панели одна ежедневная копия с тегом
/// «Дом», а после неё создан тег «Сад». Часы остановлены 7 октября 2026 года
/// в 09:00.
final class _RestoreFromSheetApp {
  _RestoreFromSheetApp._(this._tester, this._container);

  final WidgetTester _tester;
  final ProviderContainer _container;

  static Future<_RestoreFromSheetApp> open(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.platformDispatcher.localesTestValue = [const Locale('ru')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    final files = TemporaryGraphFiles();
    final runtime = AppRuntime(
      connectionFactory: openInMemoryLocalDatabase,
      diagnosticsSink: InMemoryDiagnosticsSink(),
      quickCreationModeStore: InMemoryQuickCreationModeStore(),
      graphFilesFactory: files.create,
      clock: () => DateTime(2026, 10, 7, 9).toUtc(),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(runtime.shutdown);
    });
    final ready = (await tester.runAsync(runtime.bootstrap)) as AppRuntimeReady;
    final container = ready.container;
    await tester.runAsync(() async {
      final repository = container.read(personalGraphRepositoryProvider);
      expect(
        await repository.execute(CreateTag(TagName.fromInput('Дом'))),
        isA<GraphCommandSucceeded>(),
      );
      // Проверка при запуске могла сделать ежедневную копию уже с тегом, и
      // тогда второй копии за день не будет.
      await container.read(graphBackupsProvider).makeDailyBackupIfDue();
      expect(
        await repository.execute(CreateTag(TagName.fromInput('Сад'))),
        isA<GraphCommandSucceeded>(),
      );
    });
    await tester.pumpWidget(MainApp(runtime: runtime));
    await _waitFor(tester, () => find.byType(HomePage).evaluate().isNotEmpty);
    await _waitFor(
      tester,
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Настройки'));
    await _waitFor(
      tester,
      () => find.byType(SettingsPage).evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Резервные копии'));
    await _waitFor(
      tester,
      () => find.text('Сегодня, 09:00').evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();
    return _RestoreFromSheetApp._(tester, container);
  }

  /// Выбирает копию в панели и ждёт подсчёта изменений с тех пор.
  Future<void> chooseBackup() async {
    await _tester.tap(find.text('Сегодня, 09:00'));
    await _waitFor(
      _tester,
      () => find.textContaining('С тех пор').evaluate().isNotEmpty,
    );
    await _tester.pumpAndSettle();
  }

  /// Виды хранимых копий от новых к старым.
  Future<List<GraphBackupKind>> backupKinds() async {
    final backups = await _tester.runAsync(
      () => (_container.read(
        personalGraphRepositoryProvider,
      ) as GraphBackupRegistry).readBackups(),
    );
    return [for (final backup in backups!) backup.kind];
  }

  /// Названия тегов графа в порядке создания.
  Future<List<String>> tagNames() async {
    final catalog = await _tester.runAsync(
      () => _container
          .read(personalGraphRepositoryProvider)
          .getTagCatalog(const TagCatalogBrowseMode()),
    );
    return [
      for (final tag in (catalog! as TagCatalogSuccess).value.items)
        tag.name.value,
    ];
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
