import 'dart:async';
import 'dart:io';

import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/quick_creation/file_quick_creation_mode_store.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode_controller.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode_store.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../support/in_memory_diagnostics_sink.dart';
import '../quick_creation/controlled_mode_io.dart';

void main() {
  late Directory localData;
  late File modeFile;
  late InMemoryDiagnosticsSink diagnostics;

  FileQuickCreationModeStore store() => FileQuickCreationModeStore(
    localDataDirectory: localData,
    diagnosticsSink: diagnostics,
  );

  AppRuntime runtime(QuickCreationModeStore modeStore) {
    final runtime = AppRuntime(
      connectionFactory: openInMemoryLocalDatabase,
      diagnosticsSink: diagnostics,
      quickCreationModeStore: modeStore,
    );
    addTearDown(runtime.shutdown);
    return runtime;
  }

  setUp(() async {
    localData = await Directory.systemTemp.createTemp('doable_runtime_режимы ');
    modeFile = File.fromUri(
      localData.uri.resolve('settings/quick_creation_mode'),
    );
    diagnostics = InMemoryDiagnosticsSink();
  });

  tearDown(() => localData.delete(recursive: true));

  test(
    'отказ получения каталога не мешает запуску и следующей записи',
    () async {
      var directoryAvailable = false;
      final modeStore = FileQuickCreationModeStore.withDirectoryProvider(
        localDataDirectoryProvider: () async {
          if (!directoryAvailable) {
            throw StateError('Недоступен каталог платформы');
          }
          return localData;
        },
        diagnosticsSink: diagnostics,
      );

      final first = runtime(modeStore);
      final ready = await first.bootstrap() as AppRuntimeReady;

      expect(
        ready.container.read(quickCreationModeControllerProvider),
        QuickCreationMode.intention,
      );
      _expectReadFailure(diagnostics, DiagnosticsFailureCode.unavailable);
      final controller = ready.container.read(
        quickCreationModeControllerProvider.notifier,
      );
      expect(
        await controller.select(QuickCreationMode.relation),
        isA<QuickCreationModeSaveFailed>(),
      );
      expect(
        ready.container.read(quickCreationModeControllerProvider),
        QuickCreationMode.relation,
      );

      directoryAvailable = true;
      expect(
        await controller.select(QuickCreationMode.dailyChoice),
        isA<QuickCreationModeSaved>(),
      );
      await first.shutdown();
      final restored = await runtime(store()).bootstrap() as AppRuntimeReady;
      expect(
        restored.container.read(quickCreationModeControllerProvider),
        QuickCreationMode.dailyChoice,
      );
      expect(_modeFailures(diagnostics).map((event) => event.stage), [
        QuickCreationModeDiagnosticsStage.read,
        QuickCreationModeDiagnosticsStage.write,
      ]);
    },
  );

  test('подготовка графа и чтение режима начинаются параллельно', () async {
    final modeStore = _ControlledModeStore();
    final graphOpening = _ControlledOpening();
    final runtime = AppRuntime(
      connectionFactory: () => observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(),
        graphOpening,
      ),
      diagnosticsSink: diagnostics,
      quickCreationModeStore: modeStore,
    );
    addTearDown(() async {
      modeStore.completeRead();
      graphOpening.release();
      await runtime.shutdown();
    });

    final bootstrapping = runtime.bootstrap();
    // Оба чтения начались, пока ни одно не завершилось.
    await modeStore.readStarted.future;
    await graphOpening.started.future;

    graphOpening.release();
    modeStore.completeRead(QuickCreationMode.dailyChoice);
    final ready = await bootstrapping as AppRuntimeReady;

    expect(
      ready.container.read(quickCreationModeControllerProvider),
      QuickCreationMode.dailyChoice,
    );
    // Повторный запрос готового запуска сохраняет прочитанный режим.
    final repeated = await runtime.bootstrap() as AppRuntimeReady;
    expect(
      repeated.container.read(quickCreationModeControllerProvider),
      QuickCreationMode.dailyChoice,
    );
  });

  test(
    'повтор подготовки графа использует то же хранилище и очередь',
    () async {
      final modeStore = _ControlledModeStore();
      var attempts = 0;
      final runtime = AppRuntime(
        connectionFactory: () {
          attempts += 1;
          return openInMemoryLocalDatabase(
            setup: attempts == 1
                ? (_) => throw SqliteException(
                    extendedResultCode: SqlError.SQLITE_BUSY,
                    message: 'Временная недоступность графа',
                  )
                : null,
          );
        },
        diagnosticsSink: diagnostics,
        quickCreationModeStore: modeStore,
      );
      addTearDown(() async {
        modeStore.completeRead();
        await runtime.shutdown();
      });

      expect(await runtime.bootstrap(), isA<AppRuntimeRetryableFailure>());
      modeStore.completeRead(QuickCreationMode.relation);
      final ready = await runtime.bootstrap() as AppRuntimeReady;

      expect(
        ready.container.read(quickCreationModeControllerProvider),
        QuickCreationMode.relation,
      );
      await ready.container
          .read(quickCreationModeControllerProvider.notifier)
          .select(QuickCreationMode.dailyChoice);
      expect(modeStore.savedModes, [QuickCreationMode.dailyChoice]);
    },
  );

  test('позднее чтение после shutdown не создаёт контейнер', () async {
    final modeStore = _ControlledModeStore();
    final graphOpening = _ControlledOpening()..release();
    var repositoryCreations = 0;
    final runtime = AppRuntime(
      connectionFactory: () => observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(),
        graphOpening,
      ),
      diagnosticsSink: diagnostics,
      quickCreationModeStore: modeStore,
      repositoryFactory: (_) {
        repositoryCreations += 1;
        throw StateError('Поздний результат не должен создавать граф');
      },
    );
    addTearDown(() async {
      modeStore.completeRead();
      await runtime.shutdown();
    });

    final bootstrapping = runtime.bootstrap();
    final rejected = expectLater(bootstrapping, throwsStateError);
    await graphOpening.started.future;
    // Готовая база ещё не означает, что загружен режим или создан контейнер.
    await runtime.shutdown();
    expect(graphOpening.closeCalls, 1);
    modeStore.completeRead(QuickCreationMode.relation);
    await rejected;

    expect(repositoryCreations, 0);
    expect(() => runtime.commandCoordinator, throwsStateError);
    expect(runtime.bootstrap, throwsStateError);
  });

  test('ожидание режима после готовности базы защищено от shutdown', () async {
    final modeStore = _ControlledModeStore();
    final graphReady = Completer<void>();
    final sink = _BootstrapReadyDiagnostics(graphReady);
    final runtime = AppRuntime(
      connectionFactory: openInMemoryLocalDatabase,
      diagnosticsSink: sink,
      quickCreationModeStore: modeStore,
    );
    addTearDown(() async {
      modeStore.completeRead();
      await runtime.shutdown();
    });

    final bootstrapping = runtime.bootstrap();
    final rejected = expectLater(bootstrapping, throwsStateError);
    await graphReady.future;
    // Пропускаем продолжение bootstrap до ожидания настройки после open().
    await Future<void>(() {});
    await runtime.shutdown();
    modeStore.completeRead(QuickCreationMode.dailyChoice);

    await rejected;
    expect(() => runtime.commandCoordinator, throwsStateError);
  });

  for (final fails in [false, true]) {
    test('поздний ${fails ? 'отказ' : 'успех'} записи не использует '
        'освобождённый контейнер и не считается сохранённым заранее', () async {
      await modeFile.parent.create();
      await modeFile.writeAsString(QuickCreationMode.relation.storageKey);
      final attempt = ModeWriteAttempt(
        holdAt: ModeWriteStep.rename,
        failAt: fails ? ModeWriteStep.rename : null,
      );
      final io = ControlledModeIo(modeFile, [attempt]);

      await io.run(() async {
        final first = runtime(store());
        final ready = await first.bootstrap() as AppRuntimeReady;
        final saving = ready.container
            .read(quickCreationModeControllerProvider.notifier)
            .select(QuickCreationMode.dailyChoice);
        addTearDown(() async {
          if (!attempt.release.isCompleted) attempt.release.complete();
          await saving;
        });
        await attempt.held.future;
        await first.shutdown();
        expect(
          () => ready.container.read(quickCreationModeControllerProvider),
          throwsStateError,
        );

        final beforeRuntime = runtime(store());
        final before = await beforeRuntime.bootstrap() as AppRuntimeReady;
        expect(
          before.container.read(quickCreationModeControllerProvider),
          QuickCreationMode.relation,
        );
        attempt.release.complete();
        expect(
          await saving,
          fails
              ? isA<QuickCreationModeSaveFailed>()
              : isA<QuickCreationModeSaved>(),
        );
        expect(
          before.container.read(quickCreationModeControllerProvider),
          QuickCreationMode.relation,
        );
        await beforeRuntime.shutdown();

        final after = await runtime(store()).bootstrap() as AppRuntimeReady;
        expect(
          after.container.read(quickCreationModeControllerProvider),
          fails ? QuickCreationMode.relation : QuickCreationMode.dailyChoice,
        );
      });
    });
  }
}

List<QuickCreationModeDiagnosticsEvent> _modeFailures(
  InMemoryDiagnosticsSink diagnostics,
) => diagnostics.events.whereType<QuickCreationModeDiagnosticsEvent>().toList();

void _expectReadFailure(
  InMemoryDiagnosticsSink diagnostics,
  DiagnosticsFailureCode code,
) {
  final event = _modeFailures(diagnostics).single;
  expect(event.stage, QuickCreationModeDiagnosticsStage.read);
  expect(
    event.status,
    isA<DiagnosticsFailed>().having(
      (failure) => failure.code,
      'категория',
      code,
    ),
  );
}

final class _ControlledModeStore implements QuickCreationModeStore {
  final readStarted = Completer<void>();
  final _reading = Completer<QuickCreationMode>();
  final savedModes = <QuickCreationMode>[];

  @override
  Future<QuickCreationMode> read() {
    if (!readStarted.isCompleted) readStarted.complete();
    return _reading.future;
  }

  void completeRead([QuickCreationMode mode = QuickCreationMode.intention]) {
    if (!_reading.isCompleted) _reading.complete(mode);
  }

  @override
  Future<QuickCreationModeSaveResult> save(QuickCreationMode mode) async {
    savedModes.add(mode);
    return const QuickCreationModeSaved();
  }
}

final class _ControlledOpening extends LocalDatabaseConnectionObserver {
  final started = Completer<void>();
  final _allowed = Completer<void>();
  var closeCalls = 0;

  @override
  Future<void> beforeOpen() async {
    if (!started.isCompleted) started.complete();
    await _allowed.future;
  }

  void release() {
    if (!_allowed.isCompleted) _allowed.complete();
  }

  @override
  void beforeClose() => closeCalls += 1;
}

final class _BootstrapReadyDiagnostics implements DiagnosticsSink {
  _BootstrapReadyDiagnostics(this.ready);

  final Completer<void> ready;

  @override
  void record(DiagnosticsEvent event) {
    if (event case BootstrapDiagnosticsEvent(status: DiagnosticsSucceeded())) {
      if (!ready.isCompleted) ready.complete();
    }
  }
}
