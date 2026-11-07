import 'dart:async';

import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode_controller.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode_store.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Режим быстрого создания', () {
    test('сохранённый ключ intention декодируется в режим намерения', () {
      expect(
        QuickCreationMode.fromStorageKey('intention'),
        QuickCreationMode.intention,
      );
    });

    test('неизвестные ключи, индексы и названия не становятся режимом', () {
      for (final key in [
        '',
        'unknown',
        'relation',
        '0',
        '3',
        'daily'
            'Choice',
        'daily'
            '-choice',
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
    test('использует явно переданный начальный режим', () {
      final store = _ControlledModeStore();
      final container = _container(store);

      expect(
        container.read(quickCreationModeControllerProvider),
        QuickCreationMode.intention,
      );
      expect(store.writes, isEmpty);
    });

    const failed = QuickCreationModeSaveFailed(
      DiagnosticsFailureCode.unavailable,
    );
    // Исход записи контроллер не читает: отказ — самый вероятный источник отката,
    // поэтому достаточно пары отказов.
    const firstOutcome = failed;
    const secondOutcome = failed;
    test('поздние исходы ${_outcomeName(firstOutcome)} → '
        '${_outcomeName(secondOutcome)} не меняют режим', () async {
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
      expect(
        container.read(quickCreationModeControllerProvider),
        QuickCreationMode.intention,
      );

      store.completeNext(firstOutcome);
      expect(await first, isA<QuickCreationModeSaveFailed>());
      expect(
        container.read(quickCreationModeControllerProvider),
        QuickCreationMode.intention,
      );

      store.completeNext(secondOutcome);
      expect(await second, isA<QuickCreationModeSaveFailed>());
      expect(
        container.read(quickCreationModeControllerProvider),
        QuickCreationMode.intention,
      );
    });

    test(
      'повторный выбор текущего режима получает собственный исход',
      () async {
        final store = _ControlledModeStore();
        final container = _container(store);
        final controller = container.read(
          quickCreationModeControllerProvider.notifier,
        );
        final observed = <QuickCreationMode>[];
        container.listen(
          quickCreationModeControllerProvider,
          (_, next) => observed.add(next),
        );
        final first = controller.select(QuickCreationMode.intention);
        final second = controller.select(QuickCreationMode.intention);

        expect(_acceptedModes(store), [
          QuickCreationMode.intention,
          QuickCreationMode.intention,
        ]);
        // Режим не менялся, поэтому наблюдатели не уведомляются.
        expect(observed, isEmpty);
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

    const outcome = failed;
    test('исход «${_outcomeName(outcome)}» после освобождения '
        'не обращается к состоянию', () async {
      final store = _ControlledModeStore();
      final container = _container(store);
      final saving = container
          .read(quickCreationModeControllerProvider.notifier)
          .select(QuickCreationMode.intention);

      container.dispose();
      store.completeNext(outcome);

      expect(await saving, isA<QuickCreationModeSaveFailed>());
      expect(_acceptedModes(store), [QuickCreationMode.intention]);
    });
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
  var _nextCompletion = 0;

  @override
  Future<QuickCreationMode> read() async {
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
