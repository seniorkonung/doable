import 'dart:async';

import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/home/home_page.dart';
import 'package:doable/src/app/settings/settings_page.dart';
import 'package:doable/src/daily_choice/application/confirmed_choice_path.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/application/daily_choice_result.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
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
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_root_pages.dart';
import '../support/daily_choice_catalog_controls.dart';
import '../support/daily_choice_durability_fixture.dart';
import '../support/daily_choice_local_date.dart';
import '../support/file_document_access.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/in_memory_quick_creation_mode_store.dart';
import '../support/local_database_harness.dart';
import '../support/temporary_graph_files.dart';

/// Локальное сегодня каталога дневных выборов и дата выбора графа.
final _today = CalendarDate.fromParts(2026, 10, 18);

void main() {
  testWidgets('пока экспорт, начатый на странице «Настройки», задержан, выбор '
      'в каталоге дневных выборов, открытом пунктом панели, отмечается '
      'выполненным, а после окончания экспорта появляется «Данные сохранены '
      'в файл»', (tester) async {
    final held = _HeldStateWrite();
    final app = await _ExportApp.start(tester, held: held);
    await app.openSettings();
    await app.startExport();
    await _waitFor(tester, () => held.isReached);

    await openDailyChoices(tester);
    final completion = find.byKey(
      ValueKey('daily-choice-completion-${app.choice.toCanonicalString()}'),
    );
    await _until(tester, completion);
    await tester.tap(completion);
    await _until(tester, dailyChoiceCatalogDayMark(_today, mark: DayMark.done));

    expect(await app.isChoiceCompleted(), isTrue);
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
/// между ними и невыполненного дневного выбора на [_today]. Документы
/// экспорта — файлы временного каталога без системных диалогов.
final class _ExportApp {
  _ExportApp._(
    this._tester,
    this._harness,
    this._ready,
    this._files,
    this.choice,
  );

  final WidgetTester _tester;
  final LocalDatabaseHarness _harness;
  final AppRuntimeReady _ready;
  final TemporaryGraphFiles _files;
  final DailyChoiceId choice;

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
    final choice = (await tester.runAsync(() async {
      final database = await harness.openReadyDatabase();
      final choice = await _seedGraph(database);
      await harness.closePersistenceObjectGraph();
      return choice;
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
      dailyChoiceLocalDateSource: ControlledDailyChoiceLocalDate(_today).read,
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
    return _ExportApp._(tester, harness, ready, files, choice);
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

  /// Выполнен ли дневной выбор графа в подтверждённом состоянии хранилища.
  Future<bool> isChoiceCompleted() async {
    final read =
        (await _tester.runAsync(
              () => _ready.container
                  .read(personalGraphRepositoryProvider)
                  .getDailyChoice(choice),
            ))!
            as DailyChoiceReadSuccess;
    return read.value.value!.choice.isCompleted;
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

/// Создаёт граф командами, поэтому он полностью отражён в логе фактов, и
/// возвращает его невыполненный дневной выбор.
Future<DailyChoiceId> _seedGraph(AppDatabase database) async {
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

  Future<Intention> createIntention(
    String title,
    IntentionReadiness readiness,
  ) async => (await confirm<IntentionSaved>(
    CreateIntention.withInitialState(
      title: title,
      description: null,
      readiness: readiness,
      tagIds: const {},
    ),
  )).intention;

  final health = await createIntention('Здоровье', IntentionReadiness.notReady);
  final running = await createIntention('Бегать', IntentionReadiness.ready);
  final relation = (await confirm<LongTermRelationCreated>(
    CreateLongTermRelation(
      sourceIntentionId: health.id,
      relatedIntentionId: running.id,
      type: LongTermRelationType.need,
      priority: RelationPriority.p2,
      description: null,
    ),
  )).relation;
  final created = await confirm<DailyChoiceCreated>(
    CreateDailyChoice(
      sourceIntentionId: health.id,
      selectedIntentionId: running.id,
      path: ConfirmedChoicePath([
        ConfirmedChoicePathStep(
          relationId: relation.id,
          sourceIntentionId: health.id,
          type: relation.type,
          relatedIntentionId: running.id,
        ),
      ]),
      date: _today,
      description: null,
      isCompleted: false,
    ),
  );
  return created.choice.id;
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
