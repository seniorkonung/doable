import 'dart:async';
import 'dart:io';

import 'package:doable/src/app/quick_creation/file_quick_creation_mode_store.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode_controller.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode_store.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'controlled_mode_io.dart';

void main() {
  late Directory localData;
  late File modeFile;
  late File graphFile;
  late _Diagnostics diagnostics;

  FileQuickCreationModeStore store() => FileQuickCreationModeStore(
    localDataDirectory: localData,
    diagnosticsSink: diagnostics,
  );

  setUp(() async {
    localData = await Directory.systemTemp.createTemp('doable_режимы ');
    modeFile = File.fromUri(
      localData.uri.resolve('settings/quick_creation_mode'),
    );
    graphFile = File.fromUri(localData.uri.resolve('graph.sqlite'));
    await graphFile.writeAsString('Данные графа');
    diagnostics = _Diagnostics();
  });

  tearDown(() async {
    expect(await graphFile.readAsString(), 'Данные графа');
    await localData.delete(recursive: true);
  });

  test(
    'отсутствующая настройка не создаёт файлов и не диагностируется',
    () async {
      expect(await store().read(), QuickCreationMode.intention);
      expect(await modeFile.parent.exists(), isFalse);
      expect(diagnostics.events, isEmpty);
    },
  );

  for (final mode in QuickCreationMode.values) {
    test('сохраняет устойчивый ключ и читает $mode новым хранилищем', () async {
      expect(await store().save(mode), isA<QuickCreationModeSaved>());
      expect(await modeFile.readAsString(), mode.storageKey);
      expect(await store().read(), mode);
      expect(
        await modeFile.parent.list().map((entity) => entity.path).toList(),
        [modeFile.path],
      );
      expect(diagnostics.events, isEmpty);
    });
  }

  test(
    'неизвестный ключ возвращает начальный режим с категорией повреждения',
    () async {
      await modeFile.parent.create();
      await modeFile.writeAsString(
        'Содержимое, которое нельзя диагностировать',
      );

      expect(await store().read(), QuickCreationMode.intention);
      expect(
        diagnostics.events.single.stage,
        QuickCreationModeDiagnosticsStage.read,
      );
      expect(
        diagnostics.events.single.status,
        isA<DiagnosticsFailed>().having(
          (failure) => failure.code,
          'категория',
          DiagnosticsFailureCode.corruption,
        ),
      );
    },
  );

  for (final contents in [
    <int>[],
    [0xff, 0xfe],
    'relation\n'.codeUnits,
  ]) {
    test('непригодное содержимое $contents не становится режимом', () async {
      await modeFile.parent.create();
      await modeFile.writeAsBytes(contents);
      diagnostics.throwsOnRecord = true;

      expect(await store().read(), QuickCreationMode.intention);
      _expectFailures(diagnostics, QuickCreationModeDiagnosticsStage.read, [
        DiagnosticsFailureCode.corruption,
      ]);
      expect(await modeFile.readAsBytes(), contents);
    });
  }

  test(
    'нечитаемый файл не затрагивает граф даже при отказе диагностики',
    () async {
      await Directory(modeFile.path).create(recursive: true);
      diagnostics.throwsOnRecord = true;

      expect(await store().read(), QuickCreationMode.intention);
      _expectFailures(diagnostics, QuickCreationModeDiagnosticsStage.read, [
        DiagnosticsFailureCode.unavailable,
      ]);
      expect(await Directory(modeFile.path).exists(), isTrue);
    },
  );

  test('непредвиденный отказ чтения даёт безопасный начальный режим', () async {
    final io = ControlledModeIo(modeFile, [])
      ..readError = StateError('Секретное содержимое');
    await io.run(() async {
      expect(await store().read(), QuickCreationMode.intention);
      _expectFailures(diagnostics, QuickCreationModeDiagnosticsStage.read, [
        DiagnosticsFailureCode.unexpected,
      ]);
    });
  });

  for (final step in [ModeWriteStep.write, ModeWriteStep.rename]) {
    for (final failFirst in [false, true]) {
      for (final failSecond in [false, true]) {
        test(
          '${step.label}: исходы А=${failFirst ? 'отказ' : 'успех'}, '
          'Б=${failSecond ? 'отказ' : 'успех'} сохраняют последний успех',
          () async {
            const initial = QuickCreationMode.dailyChoiceFromIntention;
            const firstMode = QuickCreationMode.relation;
            const secondMode = QuickCreationMode.dailyChoiceFromAction;
            await modeFile.parent.create();
            await modeFile.writeAsString(initial.storageKey);
            final first = ModeWriteAttempt(
              holdAt: step,
              failAt: failFirst ? step : null,
            );
            final second = ModeWriteAttempt(
              holdAt: step,
              failAt: failSecond ? step : null,
            );
            final io = ControlledModeIo(modeFile, [first, second]);
            // Бросающий получатель не должен мешать следующим попыткам.
            diagnostics.throwsOnRecord = true;

            await io.run(() async {
              final adapter = store();
              final container = _container(
                adapter,
                initialMode: await adapter.read(),
              );
              final controller = container.read(
                quickCreationModeControllerProvider.notifier,
              );
              final observedModes = <QuickCreationMode>[];
              container.listen(
                quickCreationModeControllerProvider,
                (_, next) => observedModes.add(next),
              );
              final savingFirst = controller.select(firstMode);
              expect(
                container.read(quickCreationModeControllerProvider),
                firstMode,
              );
              await _waitUntilHeld(first, savingFirst);
              final savingSecond = controller.select(secondMode);
              expect(
                container.read(quickCreationModeControllerProvider),
                secondMode,
              );
              var secondFinished = false;
              unawaited(savingSecond.then((_) => secondFinished = true));
              await Future<void>(() {});

              expect(io.startedAttempts, [first]);
              expect(second.started.isCompleted, isFalse);
              expect(secondFinished, isFalse);
              expect(await store().read(), initial);
              expect(await modeFile.readAsString(), initial.storageKey);
              expect(await File(first.temporaryPath!).exists(), isTrue);

              first.release.complete();
              _expectOutcome(await savingFirst, failed: failFirst);
              await _waitUntilHeld(second, savingSecond);
              expect(
                container.read(quickCreationModeControllerProvider),
                secondMode,
              );
              final afterFirst = failFirst ? initial : firstMode;
              expect(await store().read(), afterFirst);
              expect(secondFinished, isFalse);
              expect(await File(first.temporaryPath!).exists(), isFalse);

              second.release.complete();
              _expectOutcome(await savingSecond, failed: failSecond);
              expect(
                container.read(quickCreationModeControllerProvider),
                secondMode,
              );
              expect(observedModes, [firstMode, secondMode]);
              expect(
                await store().read(),
                failSecond ? afterFirst : secondMode,
              );
              expect(io.startedAttempts, [first, second]);
              expect(first.temporaryPath, isNot(second.temporaryPath));
              for (final attempt in [first, second]) {
                expect(
                  File(attempt.temporaryPath!).parent.path,
                  modeFile.parent.path,
                );
                expect(attempt.exclusive, isTrue);
                expect(attempt.flushed, isTrue);
              }
              expect(io.committedKeys, [
                if (!failFirst) firstMode.storageKey,
                if (!failSecond) secondMode.storageKey,
              ]);
              _expectFailures(
                diagnostics,
                QuickCreationModeDiagnosticsStage.write,
                [
                  if (failFirst) DiagnosticsFailureCode.unavailable,
                  if (failSecond) DiagnosticsFailureCode.unavailable,
                ],
              );

              if (failFirst && failSecond) {
                io.plan.add(ModeWriteAttempt());
                expect(
                  await controller.select(QuickCreationMode.intention),
                  isA<QuickCreationModeSaved>(),
                );
                expect(
                  container.read(quickCreationModeControllerProvider),
                  QuickCreationMode.intention,
                );
                expect(await store().read(), QuickCreationMode.intention);
                expect(io.startedAttempts, hasLength(3));
                expect(diagnostics.events, hasLength(2));
              }
            });
            expect(await modeFile.parent.list().length, 1);
          },
        );
      }
    }
  }

  test('очередь сохраняет все значения А → Б → А без объединения', () async {
    final attempts = List.generate(
      3,
      (_) => ModeWriteAttempt(holdAt: ModeWriteStep.rename),
    );
    final io = ControlledModeIo(modeFile, attempts);
    const modes = [
      QuickCreationMode.relation,
      QuickCreationMode.dailyChoiceFromAction,
      QuickCreationMode.relation,
    ];

    await io.run(() async {
      final adapter = store();
      final container = _container(adapter);
      final controller = container.read(
        quickCreationModeControllerProvider.notifier,
      );
      final observedModes = <QuickCreationMode>[];
      container.listen(
        quickCreationModeControllerProvider,
        (_, next) => observedModes.add(next),
      );
      final savings = modes.map((mode) {
        final saving = controller.select(mode);
        expect(container.read(quickCreationModeControllerProvider), mode);
        return saving;
      }).toList();
      for (var index = 0; index < attempts.length; index++) {
        final attempt = attempts[index];
        await _waitUntilHeld(attempt, savings[index]);
        expect(io.startedAttempts, attempts.take(index + 1).toList());
        expect(attempt.key, modes[index].storageKey);
        expect(
          await store().read(),
          index == 0 ? QuickCreationMode.intention : modes[index - 1],
        );
        attempt.release.complete();
        expect(await savings[index], isA<QuickCreationModeSaved>());
        expect(container.read(quickCreationModeControllerProvider), modes.last);
        expect(observedModes, modes);
      }
      expect(io.committedKeys, modes.map((mode) => mode.storageKey).toList());
      expect(
        attempts.map((attempt) => attempt.temporaryPath).toSet(),
        hasLength(3),
      );
      expect(await store().read(), modes.last);
      expect(diagnostics.events, isEmpty);
    });
  });

  for (final failCleanup in [false, true]) {
    test('очередь ждёт очистки после отказа и переживает её '
        '${failCleanup ? 'отказ' : 'успех'}', () async {
      final first = ModeWriteAttempt(
        failAt: ModeWriteStep.rename,
        holdAt: ModeWriteStep.cleanup,
        failCleanup: failCleanup,
      );
      final second = ModeWriteAttempt();
      final io = ControlledModeIo(modeFile, [first, second]);
      await io.run(() async {
        final adapter = store();
        final container = _container(adapter);
        final controller = container.read(
          quickCreationModeControllerProvider.notifier,
        );
        final savingFirst = controller.select(QuickCreationMode.relation);
        final savingSecond = controller.select(
          QuickCreationMode.dailyChoiceFromAction,
        );
        await _waitUntilHeld(first, savingFirst);
        expect(
          container.read(quickCreationModeControllerProvider),
          QuickCreationMode.dailyChoiceFromAction,
        );
        expect(io.startedAttempts, [first]);
        expect(await store().read(), QuickCreationMode.intention);

        first.release.complete();
        _expectOutcome(await savingFirst, failed: true);
        expect(await savingSecond, isA<QuickCreationModeSaved>());
        expect(
          container.read(quickCreationModeControllerProvider),
          QuickCreationMode.dailyChoiceFromAction,
        );
        expect(await store().read(), QuickCreationMode.dailyChoiceFromAction);
        _expectFailures(diagnostics, QuickCreationModeDiagnosticsStage.write, [
          DiagnosticsFailureCode.unavailable,
        ]);
      });
    });
  }

  for (final step in [ModeWriteStep.prepare, ModeWriteStep.createTemporary]) {
    test(
      'отказ стадии «${step.label}» не останавливает следующую попытку',
      () async {
        final first = ModeWriteAttempt(holdAt: step, failAt: step);
        final second = ModeWriteAttempt();
        final io = ControlledModeIo(modeFile, [first, second]);
        diagnostics.throwsOnRecord = true;
        await io.run(() async {
          final adapter = store();
          final container = _container(adapter);
          final controller = container.read(
            quickCreationModeControllerProvider.notifier,
          );
          final savingFirst = controller.select(QuickCreationMode.relation);
          final savingSecond = controller.select(
            QuickCreationMode.dailyChoiceFromAction,
          );
          await _waitUntilHeld(first, savingFirst);
          expect(
            container.read(quickCreationModeControllerProvider),
            QuickCreationMode.dailyChoiceFromAction,
          );
          expect(io.startedAttempts, [first]);
          expect(await store().read(), QuickCreationMode.intention);
          first.release.complete();
          _expectOutcome(await savingFirst, failed: true);
          expect(await savingSecond, isA<QuickCreationModeSaved>());
          expect(
            container.read(quickCreationModeControllerProvider),
            QuickCreationMode.dailyChoiceFromAction,
          );
          expect(await store().read(), QuickCreationMode.dailyChoiceFromAction);
          if (step == ModeWriteStep.prepare) {
            expect(first.temporaryPath, isNull);
          } else {
            expect(await File(first.temporaryPath!).exists(), isFalse);
          }
          expect(io.startedAttempts, [first, second]);
          _expectFailures(
            diagnostics,
            QuickCreationModeDiagnosticsStage.write,
            [DiagnosticsFailureCode.unavailable],
          );
        });
      },
    );
  }
}

ProviderContainer _container(
  QuickCreationModeStore store, {
  QuickCreationMode initialMode = QuickCreationMode.intention,
}) {
  final container = ProviderContainer(
    overrides: [
      quickCreationModeControllerProvider.overrideWith(
        () =>
            QuickCreationModeController(initialMode: initialMode, store: store),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _waitUntilHeld(
  ModeWriteAttempt attempt,
  Future<QuickCreationModeSaveResult> saving,
) => Future.any([
  attempt.held.future,
  saving.then((result) {
    fail('Попытка завершилась до управляемой стадии: $result');
  }),
]);

void _expectOutcome(
  QuickCreationModeSaveResult result, {
  required bool failed,
}) {
  expect(
    result,
    failed ? isA<QuickCreationModeSaveFailed>() : isA<QuickCreationModeSaved>(),
  );
  if (result case QuickCreationModeSaveFailed(:final code)) {
    expect(code, DiagnosticsFailureCode.unavailable);
  }
}

void _expectFailures(
  _Diagnostics diagnostics,
  QuickCreationModeDiagnosticsStage stage,
  List<DiagnosticsFailureCode> codes,
) {
  expect(
    diagnostics.events.map((event) => event.stage),
    List.filled(codes.length, stage),
  );
  expect(
    diagnostics.events.map((event) => (event.status as DiagnosticsFailed).code),
    codes,
  );
  for (final event in diagnostics.events) {
    expect(
      (event.status as DiagnosticsFailed).duration,
      greaterThanOrEqualTo(Duration.zero),
    );
  }
}

final class _Diagnostics implements DiagnosticsSink {
  final events = <QuickCreationModeDiagnosticsEvent>[];
  var throwsOnRecord = false;

  @override
  void record(DiagnosticsEvent event) {
    events.add(event as QuickCreationModeDiagnosticsEvent);
    if (throwsOnRecord) throw StateError('Отказ диагностики');
  }
}
