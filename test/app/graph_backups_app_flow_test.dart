import 'dart:async';

import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/home/home_page.dart';
import 'package:doable/src/app/settings/settings_page.dart';
import 'package:doable/src/data/local/app_database.dart'
    show openFileBackedLocalDatabase;
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph_backups/graph_backup_registry.dart';
import 'package:doable/src/graph_backups/graph_backups.dart';
import 'package:doable/src/graph_backups/graph_backups_provider.dart';
import 'package:doable/src/graph_snapshots/graph_fact_log.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/forwarding_graph_fact_log.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/in_memory_quick_creation_mode_store.dart';
import '../support/local_database_harness.dart';
import '../support/temporary_graph_files.dart';

void main() {
  testWidgets('сценарий «Ежедневная копия при первом открытии за день»: при '
      'запуске 6 октября в 08:15 появляется копия с намерением, созданным '
      'накануне в 20:00', (tester) async {
    final app = await _BackupsApp.start(
      tester,
      at: DateTime(2026, 10, 5, 9),
      seed: (graph) => _createTag(graph, 'Дом'),
    );
    await app.waitForBackups(1);
    app.now = DateTime(2026, 10, 5, 20);
    await app.createIntention('Бегать');

    await app.restart(at: DateTime(2026, 10, 6, 8, 15));
    await app.openSettings();
    await _until(tester, find.text('Последняя копия только что'));
    await app.openBackupsSheet();

    expect(_sheetBackups(tester), [
      'Сегодня, 08:15',
      '1 добавлено',
      'Вчера, 09:00',
      '1 добавлено',
    ]);
    // Копия содержит намерение: с её позиции граф не изменялся.
    await tester.tap(find.text('Сегодня, 08:15'));
    await _until(
      tester,
      find.text('Она сделана сегодня в 08:15. С тех пор ничего не изменилось.'),
    );
  });

  testWidgets('сценарий «Изменения описываются по сущностям»: копия '
      'появляется при возвращении в приложение, а не после команд и '
      'открытия списка', (tester) async {
    late Intention running;
    late Tag home;
    final app = await _BackupsApp.start(
      tester,
      at: DateTime(2026, 10, 5, 9),
      seed: (graph) async {
        running = await _createIntention(graph, 'Бегать', description: 'Утром');
        home = await _createTag(graph, 'Дом');
      },
    );
    await app.waitForBackups(1);

    // День сменился, пока приложение открыто: с изменениями копия нужна,
    // но команды и открытие списка её не делают.
    app.now = DateTime(2026, 10, 6, 9);
    await app.updateIntention(running, description: 'Вечером');
    await app.deleteTag(home);
    await app.createTag('Дача');
    await app.openSettings();
    await _until(tester, find.text('Последняя копия вчера в 09:00'));
    await app.openBackupsSheet();
    await _settle(tester);
    expect(_sheetBackups(tester), ['Вчера, 09:00', '2 добавлено']);

    app.returnToForeground();
    await _until(tester, find.text('Сегодня, 09:00'));

    expect(_sheetBackups(tester), [
      'Сегодня, 09:00',
      '1 добавлено, 1 изменено, 1 удалено',
      'Вчера, 09:00',
      '2 добавлено',
    ]);
    await app.closeBackupsSheet();
    expect(find.text('Последняя копия только что'), findsOneWidget);
  });

  testWidgets('команда, выполненная, пока ежедневная копия при возвращении в '
      'приложение считает сводку, подтверждается без ожидания и входит в '
      'копию', (tester) async {
    final app = await _BackupsApp.start(
      tester,
      at: DateTime(2026, 10, 5, 9),
      seed: (graph) => _createTag(graph, 'Дом'),
    );
    await app.waitForBackups(1);
    await app.createTag('Дача');
    app.now = DateTime(2026, 10, 6, 8, 15);
    final summary = app.holdNextPackageRead();
    app.returnToForeground();
    await _waitFor(tester, () => summary.isReached);

    await app.createTag('Сад');

    expect(app.backups, hasLength(1));
    summary.release();
    await app.waitForBackups(2);
    await app.openSettings();
    await app.openBackupsSheet();
    expect(_sheetBackups(tester), [
      'Сегодня, 08:15',
      '2 добавлено',
      'Вчера, 09:00',
      '1 добавлено',
    ]);
  });

  testWidgets('сценарий «Перерыв в использовании не удаляет копии»: после '
      'запуска 15 октября в списке только копия «1 октября, 09:30»', (
    tester,
  ) async {
    final app = await _BackupsApp.start(
      tester,
      at: DateTime(2026, 10, 1, 9, 30),
      seed: (graph) => _createTag(graph, 'Дом'),
    );
    await app.waitForBackups(1);

    await app.restart(at: DateTime(2026, 10, 15, 10));
    expect(await app.settleDailyBackup(), DailyGraphBackupOutcome.notDue);
    await app.openSettings();
    await _until(tester, find.text('Последняя копия 1 октября в 09:30'));
    await app.openBackupsSheet();

    expect(_sheetBackups(tester), ['1 октября, 09:30', '1 добавлено']);
  });

  testWidgets('сценарий «Новая ежедневная копия вытесняет более старые '
      'копии»: восьмая ежедневная копия удаляет самую старую ежедневную и '
      'ручную копию после неё', (tester) async {
    final app = await _BackupsApp.start(
      tester,
      at: DateTime(2026, 10, 1, 9),
      seed: (graph) => _createTag(graph, 'Тег 1'),
    );
    await app.waitForBackups(1);
    await app.openSettings();
    await app.openBackupsSheet();
    await tester.tap(find.text('Сделать копию сейчас'));
    await _until(tester, find.text('Нет изменений'));
    await app.closeBackupsSheet();

    for (var day = 2; day <= 7; day++) {
      await app.createTag('Тег $day');
      app.now = DateTime(2026, 10, day, 9);
      app.returnToForeground();
      await app.waitForBackups(day + 1);
    }
    expect(app.backups.map((backup) => backup.kind), [
      ...List.filled(6, GraphBackupKind.daily),
      GraphBackupKind.manual,
      GraphBackupKind.daily,
    ]);
    await app.createTag('Тег 8');
    app.now = DateTime(2026, 10, 8, 9);
    app.returnToForeground();
    await _waitFor(
      tester,
      () => app.backups.first.madeAt.toLocal() == DateTime(2026, 10, 8, 9),
    );
    await app.openBackupsSheet();

    expect(_sheetBackups(tester), [
      'Сегодня, 09:00',
      '1 добавлено',
      'Вчера, 09:00',
      '1 добавлено',
      for (var day = 6; day >= 2; day--) ...[
        '$day октября, 09:00',
        '1 добавлено',
      ],
    ]);
  });

  testWidgets('сценарий «Первая копия делается вручную»: после создания '
      'тега в приложении копий нет, пока её не сделали в панели, а затем '
      'строка сообщает «Последняя копия только что»', (tester) async {
    final app = await _BackupsApp.start(tester, at: DateTime(2026, 10, 7, 9));
    expect(await app.settleDailyBackup(), DailyGraphBackupOutcome.notDue);
    await app.createTag('Дом');
    await app.openSettings();
    await _until(tester, find.text('Пока нет копий'));
    await app.openBackupsSheet();
    await _settle(tester);
    expect(_sheetBackups(tester), isEmpty);

    await tester.tap(find.text('Сделать копию сейчас'));
    await _until(tester, find.text('Сегодня, 09:00'));

    expect(_sheetBackups(tester), ['Сегодня, 09:00', '1 добавлено']);
    await app.closeBackupsSheet();
    expect(find.text('Последняя копия только что'), findsOneWidget);
  });
}

/// Приложение над файловым хранилищем с часами устройства [now]. Его можно
/// перезапустить над тем же хранилищем, а команды оно выполняет через
/// координатор команд графа, как экраны.
final class _BackupsApp {
  _BackupsApp._(this._tester, this._harness, this._files, this.now);

  final WidgetTester _tester;
  final LocalDatabaseHarness _harness;
  final TemporaryGraphFiles _files;

  /// Показание часов устройства для графа и копий.
  DateTime now;

  late AppRuntime _runtime;
  late GraphBackups _graphBackups;
  StreamSubscription<GraphBackupsRead>? _watching;
  List<GraphBackupEntry> _backups = const [];
  _PackageReadHold? _nextPackageRead;

  /// Хранимые копии от новых к старым по созданию.
  List<GraphBackupEntry> get backups => _backups;

  /// Запускает приложение в момент [at] над графом, который [seed] создаёт
  /// командами, поэтому он полностью отражён в логе фактов.
  static Future<_BackupsApp> start(
    WidgetTester tester, {
    required DateTime at,
    Future<void> Function(PersonalGraphRepository graph)? seed,
  }) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.platformDispatcher.localesTestValue = const [Locale('ru')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    final harness = (await tester.runAsync(LocalDatabaseHarness.fileBacked))!;
    addTearDown(() => tester.runAsync(harness.dispose));
    final app = _BackupsApp._(tester, harness, TemporaryGraphFiles(), at);
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
      connectionFactory: () =>
          openFileBackedLocalDatabase(_harness.databaseFile),
      diagnosticsSink: InMemoryDiagnosticsSink(),
      quickCreationModeStore: InMemoryQuickCreationModeStore(),
      graphFilesFactory: (log) =>
          _files.create(_HeldPackageReads(log, takeHold: _takeHold)),
      clock: () => now.toUtc(),
    );
    final ready =
        (await _tester.runAsync(runtime.bootstrap))! as AppRuntimeReady;
    _graphBackups = ready.container.read(graphBackupsProvider);
    _watching = _graphBackups.watchBackups().listen((read) {
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
      _waitFor(_tester, () => backups.length == count);

  /// Ждёт проверки ежедневной копии, начатой при запуске или возвращении в
  /// приложение, и возвращает исход ещё одной проверки: копии делаются по
  /// одной, поэтому она завершается после начатой.
  Future<DailyGraphBackupOutcome> settleDailyBackup() async {
    DailyGraphBackupOutcome? outcome;
    unawaited(
      _graphBackups.makeDailyBackupIfDue().then((value) => outcome = value),
    );
    await _waitFor(_tester, () => outcome != null);
    return outcome!;
  }

  /// Задерживает следующее чтение пакетов лога — подсчёт сводки копии.
  _PackageReadHold holdNextPackageRead() =>
      _nextPackageRead = _PackageReadHold();

  _PackageReadHold? _takeHold() {
    final hold = _nextPackageRead;
    _nextPackageRead = null;
    return hold;
  }

  /// Уводит приложение в фон и возвращает его на передний план.
  void returnToForeground() {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      _tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  GraphCommandCoordinator get _coordinator => _runtime.commandCoordinator;

  Future<void> createTag(String name) =>
      _confirmed(switch (_coordinator.acceptTagCreation(
        TagCreationFormKey(),
        CreateTag(
          name: TagName.fromInput(name),
          color: null,
          placement: TagPlacement.first,
        ),
      )) {
        TagCommandAccepted(:final future) => future,
        final start => fail('Создание тега не принято: $start'),
      });

  Future<void> deleteTag(Tag tag) =>
      _confirmed(switch (_coordinator.acceptTagDelete(DeleteTag(tag.id))) {
        TagCommandAccepted(:final future) => future,
        final start => fail('Удаление тега не принято: $start'),
      });

  Future<void> createIntention(String title) =>
      _confirmed(switch (_coordinator.acceptCreation(
        IntentionCreationFormKey(),
        CreateIntention(title: title, description: null),
      )) {
        IntentionCommandAccepted(:final future) => future,
        final start => fail('Создание намерения не принято: $start'),
      });

  Future<void> updateIntention(
    Intention intention, {
    required String description,
  }) => _confirmed(switch (_coordinator.acceptExisting(
    UpdateIntention(
      id: intention.id,
      title: intention.title,
      description: description,
    ),
    presentationTitle: intention.title,
  )) {
    IntentionCommandAccepted(:final future) => future,
    final start => fail('Изменение намерения не принято: $start'),
  });

  /// Ждёт подтверждения принятой команды.
  Future<void> _confirmed(Future<GraphCommandCompletion> completion) async {
    GraphCommandCompletion? completed;
    unawaited(completion.then((value) => completed = value));
    await _waitFor(_tester, () => completed != null);
    expect(completed!.isFailure, isFalse);
  }

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

  Future<void> closeBackupsSheet() async {
    await _tester.tapAt(const Offset(10, 10));
    await _tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
  }
}

/// Задержка чтения пакетов лога: [isReached] — чтение начато, а
/// продолжается оно после [release].
final class _PackageReadHold {
  final _reached = Completer<void>();
  final _released = Completer<void>();

  bool get isReached => _reached.isCompleted;

  void release() => _released.complete();
}

/// Лог фактов сжатия, в котором чтение пакетов ждёт задержку, взятую
/// [takeHold], а остальные операции выполняет исходный лог.
final class _HeldPackageReads extends ForwardingGraphFactLog {
  const _HeldPackageReads(super.source, {required this.takeHold});

  final _PackageReadHold? Function() takeHold;

  @override
  Future<List<StoredGraphLogPackage>> readPackages({
    required int after,
    required int upTo,
  }) async {
    if (takeHold() case final hold?) {
      hold._reached.complete();
      await hold._released.future;
    }
    return super.readPackages(after: after, upTo: upTo);
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
    (await _confirm<TagCreated>(
      graph,
      CreateTag(
        name: TagName.fromInput(name),
        color: null,
        placement: TagPlacement.first,
      ),
    )).tag;

Future<Intention> _createIntention(
  PersonalGraphRepository graph,
  String title, {
  required String description,
}) async => (await _confirm<IntentionSaved>(
  graph,
  CreateIntention(title: title, description: description),
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

Future<void> _until(WidgetTester tester, Finder finder) =>
    _waitFor(tester, () => finder.evaluate().isNotEmpty);

/// Даёт фоновой работе, начатой по ошибке, время завершиться: копия,
/// сделанная после команды или открытия списка, появилась бы за эти шаги.
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
/// и кадр через 100 мс.
Future<void> _advance(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pump(const Duration(milliseconds: 100));
}
