import 'dart:async';

import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode_controller.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode_store.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Режим быстрого создания', () {
    const storedModes = {
      'intention': QuickCreationMode.intention,
      'relation': QuickCreationMode.relation,
      'daily-choice-from-intention': QuickCreationMode.dailyChoiceFromIntention,
      'daily-choice-from-action': QuickCreationMode.dailyChoiceFromAction,
    };

    test('четыре режима имеют постоянный порядок и явные ключи', () {
      expect(QuickCreationMode.values, storedModes.values.toList());
      expect(
        QuickCreationMode.values.map((mode) => mode.storageKey),
        storedModes.keys.toList(),
      );
    });

    test('каждый сохранённый ключ декодируется в свой режим', () {
      for (final entry in storedModes.entries) {
        expect(QuickCreationMode.fromStorageKey(entry.key), entry.value);
      }
    });

    test('неизвестные ключи, индексы и названия не становятся режимом', () {
      for (final key in [
        '',
        'unknown',
        '0',
        '3',
        'dailyChoiceFromIntention',
        'dailyChoiceFromAction',
        'Новое намерение',
        'New intention',
        'INTENTION',
        ' intention',
        'intention\n',
      ]) {
        expect(QuickCreationMode.fromStorageKey(key), isNull, reason: key);
      }
    });
  });

  group('Контроллер режима быстрого создания', () {
    for (final initialMode in QuickCreationMode.values) {
      test('использует явно переданный начальный режим $initialMode', () {
        final store = _ControlledModeStore();
        final container = _container(store, initialMode: initialMode);

        expect(
          container.read(quickCreationModeControllerProvider),
          initialMode,
        );
        expect(store.readCalls, 0);
        expect(store.writes, isEmpty);
      });
    }

    test(
      'выбор синхронно доступен всем наблюдателям до исхода записи',
      () async {
        final store = _ControlledModeStore();
        final container = _container(store);
        final firstObserver = <QuickCreationMode>[];
        final secondObserver = <QuickCreationMode>[];
        container.listen(
          quickCreationModeControllerProvider,
          (_, next) => firstObserver.add(next),
        );
        container.listen(
          quickCreationModeControllerProvider,
          (_, next) => secondObserver.add(next),
        );

        final saving = container
            .read(quickCreationModeControllerProvider.notifier)
            .select(QuickCreationMode.relation);

        expect(
          container.read(quickCreationModeControllerProvider),
          QuickCreationMode.relation,
        );
        expect(firstObserver, [QuickCreationMode.relation]);
        expect(secondObserver, [QuickCreationMode.relation]);
        expect(store.writes.single.mode, QuickCreationMode.relation);
        expect(store.writes.single.completion.isCompleted, isFalse);

        store.completeNext(const QuickCreationModeSaved());
        expect(await saving, isA<QuickCreationModeSaved>());
        expect(firstObserver, [QuickCreationMode.relation]);
        expect(secondObserver, [QuickCreationMode.relation]);
      },
    );

    const outcomes = [
      QuickCreationModeSaved(),
      QuickCreationModeSaveFailed(DiagnosticsFailureCode.unavailable),
    ];
    for (final firstOutcome in outcomes) {
      for (final secondOutcome in outcomes) {
        test('поздние исходы ${_outcomeName(firstOutcome)} → '
            '${_outcomeName(secondOutcome)} не отменяют новый режим', () async {
          final store = _ControlledModeStore();
          final container = _container(store);
          final controller = container.read(
            quickCreationModeControllerProvider.notifier,
          );
          final first = controller.select(QuickCreationMode.relation);
          final second = controller.select(
            QuickCreationMode.dailyChoiceFromAction,
          );

          expect(_acceptedModes(store), [
            QuickCreationMode.relation,
            QuickCreationMode.dailyChoiceFromAction,
          ]);
          expect(
            container.read(quickCreationModeControllerProvider),
            QuickCreationMode.dailyChoiceFromAction,
          );

          store.completeNext(firstOutcome);
          expect(await first, same(firstOutcome));
          expect(
            container.read(quickCreationModeControllerProvider),
            QuickCreationMode.dailyChoiceFromAction,
          );
          expect(store.writes.last.completion.isCompleted, isFalse);

          store.completeNext(secondOutcome);
          expect(await second, same(secondOutcome));
          expect(
            container.read(quickCreationModeControllerProvider),
            QuickCreationMode.dailyChoiceFromAction,
          );
        });
      }
    }

    test(
      'передаёт каждый выбор А → Б → А без ожидания или объединения',
      () async {
        final store = _ControlledModeStore();
        final container = _container(store);
        final controller = container.read(
          quickCreationModeControllerProvider.notifier,
        );

        final first = controller.select(QuickCreationMode.relation);
        final second = controller.select(
          QuickCreationMode.dailyChoiceFromIntention,
        );
        final third = controller.select(QuickCreationMode.relation);

        expect(_acceptedModes(store), [
          QuickCreationMode.relation,
          QuickCreationMode.dailyChoiceFromIntention,
          QuickCreationMode.relation,
        ]);
        expect(
          store.writes.every((write) => !write.completion.isCompleted),
          isTrue,
        );
        expect(first, isNot(same(third)));

        store.completeNext(
          const QuickCreationModeSaveFailed(DiagnosticsFailureCode.unavailable),
        );
        await first;
        store.completeNext(const QuickCreationModeSaved());
        await second;
        expect(
          container.read(quickCreationModeControllerProvider),
          QuickCreationMode.relation,
        );
        store.completeNext(const QuickCreationModeSaved());
        await third;
        expect(_acceptedModes(store), [
          QuickCreationMode.relation,
          QuickCreationMode.dailyChoiceFromIntention,
          QuickCreationMode.relation,
        ]);
      },
    );

    test(
      'повторный выбор текущего режима получает собственный исход',
      () async {
        final store = _ControlledModeStore();
        final container = _container(store);
        final controller = container.read(
          quickCreationModeControllerProvider.notifier,
        );
        final first = controller.select(QuickCreationMode.intention);
        final second = controller.select(QuickCreationMode.intention);

        expect(_acceptedModes(store), [
          QuickCreationMode.intention,
          QuickCreationMode.intention,
        ]);
        store.completeNext(
          const QuickCreationModeSaveFailed(DiagnosticsFailureCode.unavailable),
        );
        expect(await first, isA<QuickCreationModeSaveFailed>());
        store.completeNext(const QuickCreationModeSaved());
        expect(await second, isA<QuickCreationModeSaved>());
        expect(
          container.read(quickCreationModeControllerProvider),
          QuickCreationMode.intention,
        );
      },
    );

    test('сохраняет общий режим без наблюдателей между страницами', () async {
      final store = _ControlledModeStore();
      final container = _container(store);
      final subscription = container.listen(
        quickCreationModeControllerProvider,
        (_, _) {},
      );
      final controller = container.read(
        quickCreationModeControllerProvider.notifier,
      );
      final saving = controller.select(QuickCreationMode.dailyChoiceFromAction);

      subscription.close();
      await container.pump();
      store.completeNext(const QuickCreationModeSaved());
      await saving;
      await container.pump();

      expect(
        container.read(quickCreationModeControllerProvider.notifier),
        same(controller),
      );
      expect(
        container.read(quickCreationModeControllerProvider),
        QuickCreationMode.dailyChoiceFromAction,
      );
    });

    for (final outcome in outcomes) {
      test('исход «${_outcomeName(outcome)}» после освобождения '
          'не обращается к состоянию', () async {
        final store = _ControlledModeStore();
        final container = _container(store);
        final saving = container
            .read(quickCreationModeControllerProvider.notifier)
            .select(QuickCreationMode.relation);

        container.dispose();
        store.completeNext(outcome);

        expect(await saving, same(outcome));
        expect(_acceptedModes(store), [QuickCreationMode.relation]);
      });
    }
  });
}

String _outcomeName(QuickCreationModeSaveResult outcome) => switch (outcome) {
  QuickCreationModeSaved() => 'успех',
  QuickCreationModeSaveFailed() => 'отказ',
};

ProviderContainer _container(
  _ControlledModeStore store, {
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

List<QuickCreationMode> _acceptedModes(_ControlledModeStore store) =>
    store.writes.map((write) => write.mode).toList();

/// Управляет исходами принятой записи, проверяя только потребителя контракта.
final class _ControlledModeStore implements QuickCreationModeStore {
  final writes =
      <
        ({
          QuickCreationMode mode,
          Completer<QuickCreationModeSaveResult> completion,
        })
      >[];
  var readCalls = 0;
  var _nextCompletion = 0;

  @override
  Future<QuickCreationMode> read() async {
    readCalls += 1;
    return QuickCreationMode.intention;
  }

  @override
  Future<QuickCreationModeSaveResult> save(QuickCreationMode mode) {
    final completion = Completer<QuickCreationModeSaveResult>();
    writes.add((mode: mode, completion: completion));
    return completion.future;
  }

  void completeNext(QuickCreationModeSaveResult result) {
    writes[_nextCompletion++].completion.complete(result);
  }
}
