import 'dart:async';

import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/home/home_page.dart';
import 'package:doable/src/app/settings/settings_page.dart';
import 'package:doable/src/action/application/action_details.dart';
import 'package:doable/src/action/domain/action_id.dart';
import 'package:doable/src/data/local/app_database.dart'
    show AppDatabase, openFileBackedLocalDatabase;
import 'package:doable/src/data_transfer/application/document_access.dart';
import 'package:doable/src/design_system/components/day_mark.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph_snapshots/graph_log_compaction.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/long_term_relation/application/intention_relation_group.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_root_pages.dart';
import '../support/controlled_local_date.dart';
import '../support/action_day_controls.dart';
import '../support/action_seed.dart';
import '../support/file_document_access.dart';
import '../support/graph_durability_fixture.dart';
import '../support/graph_seed.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/in_memory_quick_creation_mode_store.dart';
import '../support/local_database_harness.dart';
import '../support/temporary_graph_files.dart';

/// Локальное сегодня экрана дня и дата действия графа.
final _today = CalendarDate.fromParts(2026, 10, 18);

void main() {
  testWidgets('пока экспорт, начатый на странице «Настройки», задержан, '
      'действие на экране дня, открытом пунктом панели, отмечается '
      'выполненным, а после окончания экспорта появляется «Данные сохранены '
      'в файл»', (tester) async {
    final held = _HeldStateWrite();
    final app = await _ExportApp.start(tester, held: held);
    await app.openSettings();
    await app.startExport();
    await _waitFor(tester, () => held.isReached);

    await openActions(tester);
    final completion = find.byKey(
      ValueKey('action-day-completion-${app.action.toCanonicalString()}'),
    );
    await _until(tester, completion);
    // Флажок стоит у левого края и уходит за него, пока идёт переход страницы.
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(completion);
    await _until(tester, actionDayDayMark(_today, mark: DayMark.done));

    expect(await app.isActionCompleted(), isTrue);
    expect(app.documents.created.single.lengthSync(), 0);
    expect(find.text('Данные сохранены в файл'), findsNothing);
    // Сброс истории закрыл «Настройки»; экспорт завершается после того, как
    // страница освобождена.
    await _waitFor(
      tester,
      () => find.byType(SettingsPage, skipOffstage: false).evaluate().isEmpty,
    );

    held.release();
    await _until(tester, find.text('Данные сохранены в файл'));

    expect(app.documents.created.single.lengthSync(), isPositive);
  });

  testWidgets('экспорт продолжается после закрытия страницы «Настройки», при '
      'возвращении на неё строка показывает его ход, а результат появляется '
      'на Главной', (tester) async {
    final held = _HeldStateWrite();
    final app = await _ExportApp.start(tester, held: held);
    await app.openSettings();
    await app.startExport();
    await _waitFor(tester, () => held.isReached);

    final settings = find.byType(SettingsPage, skipOffstage: false);
    await tester.binding.handlePopRoute();
    await _waitFor(tester, () => settings.evaluate().isEmpty);
    await app.openSettings();

    expect(find.text('Сохраняется в файл…'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await _waitFor(tester, () => settings.evaluate().isEmpty);
    held.release();
    await _until(tester, find.text('Данные сохранены в файл'));

    expect(find.byType(HomePage), findsOneWidget);
    expect(app.documents.created.single.lengthSync(), isPositive);
  });

  testWidgets('отказ записи документа показывает «Не удалось сохранить файл» '
      'с «Повторить», которое снова открывает системный диалог, а отмена '
      'диалога ничего не меняет', (tester) async {
    final app = await _ExportApp.start(tester);
    final graphBefore = app.storedState();
    app.documents.failsWrites = true;
    await app.openSettings();
    await app.startExport();
    await _until(tester, find.text('Не удалось сохранить файл'));
    await tester.pumpAndSettle();

    app.documents.dialog = () async => const DocumentCreationCancelled();
    await tester.tap(find.text('Повторить'));
    await _waitFor(tester, () => app.documents.suggestedNames.length == 2);
    // Сообщение после отмены появилось бы за это время и ещё не закрылось бы.
    for (var step = 0; step < 10; step++) {
      await _advance(tester);
    }

    expect(find.byKey(const ValueKey('graph-operation-message')), findsNothing);
    expect(find.text('Сохранить копию всего в файл'), findsOneWidget);
    expect(app.documents.created, hasLength(1));
    expect(app.storedState(), graphBefore);
  });
}

/// Приложение над файловым хранилищем с графом из двух намерений, связи
/// между ними и невыполненного действия на [_today]. Документы
/// экспорта — файлы временного каталога без системных диалогов.
final class _ExportApp {
  _ExportApp._(
    this._tester,
    this._harness,
    this._ready,
    this._files,
    this.action,
  );

  final WidgetTester _tester;
  final LocalDatabaseHarness _harness;
  final AppRuntimeReady _ready;
  final TemporaryGraphFiles _files;
  final ActionId action;

  FileDocumentAccess get documents => _files.documents;

  /// Запускает приложение и ждёт загруженную Главную. [held] задерживает
  /// запись состояния графа для экспорта.
  static Future<_ExportApp> start(
    WidgetTester tester, {
    _HeldStateWrite? held,
  }) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.platformDispatcher.localesTestValue = const [Locale('ru')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    final harness = (await tester.runAsync(LocalDatabaseHarness.fileBacked))!;
    addTearDown(() => tester.runAsync(harness.dispose));
    final action = (await tester.runAsync(() async {
      final database = await harness.openReadyDatabase();
      final action = await _seedGraph(database);
      await harness.closePersistenceObjectGraph();
      return action;
    }))!;
    final files = TemporaryGraphFiles(
      stateWriteRunner: held?.run ?? runGraphStateWriteInIsolate,
    );
    final runtime = AppRuntime(
      connectionFactory: () =>
          openFileBackedLocalDatabase(harness.databaseFile),
      diagnosticsSink: InMemoryDiagnosticsSink(),
      quickCreationModeStore: InMemoryQuickCreationModeStore(),
      graphFilesFactory: files.create,
      localDateSource: ControlledLocalDate(_today).read,
    );
    addTearDown(() async {
      held?.release();
      await tester.pumpWidget(const SizedBox.shrink());
      // Выключение дожидается экспорта, который продолжается и в реальном
      // ожидании, и в кадрах проверки.
      var isShutDown = false;
      unawaited(runtime.shutdown().whenComplete(() => isShutDown = true));
      await _waitFor(tester, () => isShutDown);
    });
    final ready =
        (await tester.runAsync(runtime.bootstrap))! as AppRuntimeReady;
    await tester.pumpWidget(MainApp(runtime: runtime));
    await _until(tester, find.byType(HomePage));
    await _waitFor(
      tester,
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
    return _ExportApp._(tester, harness, ready, files, action);
  }

  /// Открывает с Главной страницу «Настройки» и ждёт прочитанный состав
  /// графа в строке «Экспорт данных».
  Future<void> openSettings() async {
    await _tester.tap(find.byTooltip('Настройки'));
    await _until(_tester, find.byType(SettingsPage));
    await _waitFor(
      _tester,
      () =>
          find.text('Сохранить копию всего в файл').evaluate().isNotEmpty ||
          find.text('Сохраняется в файл…').evaluate().isNotEmpty,
    );
    await _tester.pumpAndSettle();
  }

  /// Открывает панель «Экспорт данных» и сохраняет граф в документ, который
  /// выбирает системный диалог.
  Future<void> startExport() async {
    await _tester.tap(find.text('Экспорт данных'));
    await _until(_tester, find.text('Сохранить в файл'));
    await _tester.pumpAndSettle();
    await _tester.tap(find.text('Сохранить в файл'));
    await _tester.pump();
  }

  /// Выполнено ли действие графа в подтверждённом состоянии хранилища.
  Future<bool> isActionCompleted() async {
    final read =
        (await _tester.runAsync(
              () => _ready.container
                  .read(personalGraphRepositoryProvider)
                  .watchAction(action)
                  .first,
            ))!
            as ActionReadSuccess;
    return read.value.value!.action.isCompleted;
  }

  /// Всё содержимое файла хранилища, включая лог фактов и реестр снимков.
  Map<String, Object?> storedState() =>
      durabilityFileState(_harness.databaseFile);
}

/// Запись состояния графа для экспорта, которая начинается только после
/// [release].
final class _HeldStateWrite {
  final _reached = Completer<void>();
  final _released = Completer<void>();

  /// Экспорт зафиксировал позицию и ждёт начала записи.
  bool get isReached => _reached.isCompleted;

  void release() {
    if (!_released.isCompleted) _released.complete();
  }

  Future<void> run(GraphStateWrite write) async {
    _reached.complete();
    await _released.future;
    return runGraphStateWriteInIsolate(write);
  }
}

/// Создаёт намерения и связь командами, поэтому они отражены в логе фактов, и
/// возвращает идентификатор невыполненного действия с путём по этой связи.
/// Команды создания действия нет, поэтому действие записывается напрямую.
Future<ActionId> _seedGraph(AppDatabase database) async {
  final repository = DriftPersonalGraphRepository(
    database,
    UuidV7IntentionIdGenerator(),
    () => DateTime.now().toUtc(),
    InMemoryDiagnosticsSink(),
  );
  Future<T> confirm<T extends GraphCommandOutcome>(
    GraphCommand<GraphCommandOutcome, GraphCommandFailure> command,
  ) async {
    final result = await repository.execute(command);
    final confirmed =
        (result as GraphResultSuccess<Object?, GraphCommandFailure>).value!
            as ConfirmedGraphResult;
    return confirmed.value as T;
  }

  Future<Intention> createIntention(String title) async =>
      (await confirm<IntentionSaved>(
        CreateIntention.withInitialState(
          title: title,
          description: null,
          tagIds: const {},
        ),
      )).intention;

  final health = await createIntention('Здоровье');
  final running = await createIntention('Бегать');
  final relation = (await confirm<LongTermRelationsAdded>(
    AddLongTermRelations(
      pageIntentionId: health.id,
      candidateIds: [running.id],
      group: IntentionRelationGroup.needs,
    ),
  )).relations.single;

  await confirm<LongTermRelationUpdated>(
    UpdateLongTermRelation(
      relationId: relation.id,
      patch: LongTermRelationPatch(
        priority: const LongTermRelationFieldSet(RelationPriority.p2),
        description: LongTermRelationDescriptionPatch.fromInput(
          'Описание связи',
        ),
      ),
    ),
  );
  final action = seedUuid(1);
  await seedGraph(database, () async {
    await database.customStatement(
      '''INSERT INTO actions
         (id, title, description, date, scheduled_hour, priority, is_completed,
          created_at, updated_at)
         VALUES (?, 'Пробежка', NULL, ?, NULL, 4, 0, 1, 1)''',
      [action, _today.toCanonicalString()],
    );
    for (final (position, intention) in [health.id, running.id].indexed) {
      await database.customStatement(insertActionPathItem, [
        action,
        position,
        intention.toCanonicalString(),
        position == 0 ? null : health.id.toCanonicalString(),
        actionPathRole(position, 2),
      ]);
    }
  });
  return (ActionId.decode(action) as ActionIdDecodingSuccess).id;
}

Future<void> _until(WidgetTester tester, Finder finder) =>
    _waitFor(tester, () => finder.evaluate().isNotEmpty);

/// Продвигает время, пока не выполнится [done]. Шагов хватает, чтобы
/// показанное сообщение общей поверхности закрылось по таймеру.
Future<void> _waitFor(WidgetTester tester, bool Function() done) async {
  for (var step = 0; step < 100 && !done(); step++) {
    await _advance(tester);
  }
  expect(done(), isTrue);
}

/// Один шаг времени: реальное ожидание, в котором идут файловые операции и
/// изолят записи состояния, и кадр через 100 мс.
Future<void> _advance(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pump(const Duration(milliseconds: 100));
}
