import 'dart:async';

import 'package:doable/src/action/application/action_command.dart';
import 'package:doable/src/action/application/action_details.dart';
import 'package:doable/src/action/application/action_result.dart';
import 'package:doable/src/action/domain/action_priority.dart';
import 'package:doable/src/action/presentation/panel/action_panel_state.dart';
import 'package:doable/src/action/presentation/panel/action_panel_view_model.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/action_panel_fixture.dart';

void main() {
  final id = actionIdOf(1);

  test(
    'наблюдает нужное действие, отклоняет старый снимок и закрывает поток',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final model = harness.model;
      expect(harness.repository.observedId, id);
      harness.repository.emitMissing();
      await pumpEventQueue();
      expect(model.state, isA<ActionPanelNotFound>());
      harness.repository.emit(actionDetailsFixture(), revision: 0);
      await pumpEventQueue();
      expect(model.state, isA<ActionPanelNotFound>());
      model.dispose();
      await pumpEventQueue();
      expect(harness.repository.hasListener, isFalse);
    },
  );

  test('изменение отправляет патч этого действия и завершается успехом только '
      'со снимком записанной ревизии из подписки', () async {
    final harness = await _Harness.loaded();
    addTearDown(harness.dispose);
    final model = harness.model;
    final confirmed = model.state;

    bool? saved;
    unawaited(model.change(_patch).then((value) => saved = value));
    expect(model.operation, isA<ActionPanelOperationWriting>());
    expect(harness.repository.commands.single.actionId, id);
    expect(harness.repository.commands.single.patch, same(_patch));

    harness.repository.succeedUpdate();
    await pumpEventQueue();
    expect(model.operation, isA<ActionPanelOperationAwaitingSnapshot>());
    expect(model.state, same(confirmed));
    expect(saved, isNull);

    harness.repository.emit(
      actionDetailsFixture(priority: ActionPriority.p1),
      revision: 10,
    );
    await pumpEventQueue();
    expect(model.state, isNot(same(confirmed)));
    expect(model.state, isA<ActionPanelLoaded>());
    expect(model.operation, isA<ActionPanelOperationIdle>());
    expect(saved, isTrue);
  });

  for (final (outcome, finish)
      in <(String, void Function(ActionPanelRepository))>[
        ('действие не найдено', (repository) => repository.emitMissing()),
        (
          'отказ чтения',
          (repository) =>
              repository.failRead(const ActionReadUnavailableFailure()),
        ),
      ]) {
    test(
      'исход подписки «$outcome» тоже заканчивает ожидание снимка',
      () async {
        final harness = await _Harness.loaded();
        addTearDown(harness.dispose);
        final model = harness.model;

        final saved = model.change(_patch);
        harness.repository.succeedUpdate();
        await pumpEventQueue();
        expect(model.operation, isA<ActionPanelOperationAwaitingSnapshot>());

        finish(harness.repository);

        expect(await saved, isTrue);
        expect(model.operation, isA<ActionPanelOperationIdle>());
      },
    );
  }

  test('запись без изменения значений не оставляет ожидание снимка', () async {
    final harness = await _Harness.loaded();
    addTearDown(harness.dispose);
    final model = harness.model;
    final shown = actionDetailsFixture().action;

    final saved = model.change(_patch);
    harness.repository.succeedUpdate(written: shown);

    expect(await saved, isTrue);
    expect(model.operation, isA<ActionPanelOperationIdle>());
    expect(model.state, isA<ActionPanelLoaded>());
  });

  test('второе изменение не отправляется, пока идёт запись и ожидание '
      'снимка, и без загруженного действия', () async {
    final unloaded = _Harness();
    addTearDown(unloaded.dispose);
    expect(await unloaded.model.change(_patch), isFalse);
    expect(unloaded.repository.commands, isEmpty);

    final harness = await _Harness.loaded();
    addTearDown(harness.dispose);
    final model = harness.model;

    unawaited(model.change(_patch));
    expect(await model.change(_patch), isFalse);
    harness.repository.succeedUpdate();
    await pumpEventQueue();
    expect(await model.change(_patch), isFalse);
    expect(harness.repository.commands, hasLength(1));

    harness.repository.emit(
      actionDetailsFixture(priority: ActionPriority.p1),
      revision: 10,
    );
    await pumpEventQueue();
    unawaited(model.change(_patch));
    expect(harness.repository.commands, hasLength(2));
  });

  test(
    'отказ оставляет подтверждённый снимок и переживает новые снимки',
    () async {
      final harness = await _Harness.loaded();
      addTearDown(harness.dispose);
      final model = harness.model;
      final confirmed = model.state;

      unawaited(model.change(_patch));
      harness.repository.failCommand(const ActionUnavailableFailure());
      await pumpEventQueue();

      final failed = model.operation as ActionPanelOperationFailed;
      expect(failed.failure, isA<ActionUnavailableFailure>());
      expect(failed.failurePresentation, isNotNull);
      expect(model.state, same(confirmed));

      harness.repository.emit(actionDetailsFixture(), revision: 10);
      await pumpEventQueue();
      expect(model.operation, same(failed));
    },
  );

  for (final closesBeforeResult in [true, false]) {
    final moment = closesBeforeResult ? 'до результата' : 'после отказа';
    test('закрытие $moment отдаёт отказ общей поверхности один раз', () async {
      final harness = await _Harness.loaded();
      addTearDown(harness.dispose);
      final model = harness.model;
      final shell = harness.coordinator.registerAppPresentation();
      addTearDown(shell.release);
      final claim = shell.nextClaim();

      unawaited(model.change(_patch));
      if (closesBeforeResult) model.dispose();
      harness.repository.failCommand(const ActionUnavailableFailure());
      await pumpEventQueue();
      if (!closesBeforeResult) model.dispose();

      expect((await claim)!.completions, hasLength(1));
      expect((await claim)!.completions.single.isFailure, isTrue);
    });
  }

  test('остановка координатора даёт непредвиденный отказ', () async {
    final harness = await _Harness.loaded();
    addTearDown(harness.dispose);
    final model = harness.model;
    unawaited(harness.coordinator.shutdown());

    unawaited(model.change(_patch));
    final failed = model.operation as ActionPanelOperationFailed;
    expect(failed.failure, isA<ActionUnexpectedFailure>());
    expect(failed.failurePresentation, isNull);
    expect(harness.repository.commands, isEmpty);
  });

  group('блокировка флажка выполнения', () {
    test('доказанно временный отказ не блокирует флажок', () async {
      final harness = await _Harness.loaded();
      addTearDown(harness.dispose);
      final model = harness.model;

      unawaited(model.change(_completionPatch));
      harness.repository.failCommand(const ActionUnavailableFailure());
      await pumpEventQueue();

      expect(model.completionLock, isNull);
    });

    test('отказ изменения другого поля не блокирует флажок', () async {
      final harness = await _Harness.loaded();
      addTearDown(harness.dispose);
      final model = harness.model;

      unawaited(model.change(_patch));
      harness.repository.failCommand(const ActionUnexpectedFailure());
      await pumpEventQueue();

      expect(model.completionLock, isNull);
    });

    test('отказ без явного повтора блокирует флажок до перечитывания '
        'действия, а отклонённое изменение заново не отправляется', () async {
      final harness = await _Harness.loaded();
      addTearDown(harness.dispose);
      final model = harness.model;

      unawaited(model.change(_completionPatch));
      harness.repository.failCommand(const ActionUnexpectedFailure());
      await pumpEventQueue();
      expect(model.completionLock, isA<ActionUnexpectedFailure>());

      // Следующая запись другого поля блокировку не снимает.
      unawaited(model.change(_patch));
      harness.repository.succeedUpdate();
      harness.repository.emit(
        actionDetailsFixture(priority: ActionPriority.p1),
        revision: 10,
      );
      await pumpEventQueue();
      expect(model.completionLock, isA<ActionUnexpectedFailure>());

      final watched = harness.repository.watchCount;
      model.refresh();
      expect(harness.repository.watchCount, watched + 1);
      expect(model.completionLock, isNotNull);

      harness.repository.emit(
        actionDetailsFixture(priority: ActionPriority.p1),
        revision: 11,
      );
      await pumpEventQueue();
      expect(model.completionLock, isNull);
      expect(harness.repository.commands, hasLength(2));
    });

    test('отказ перечитывания оставляет блокировку, а успешное повторное '
        'чтение снимает её', () async {
      final harness = await _Harness.loaded();
      addTearDown(harness.dispose);
      final model = harness.model;

      unawaited(model.change(_completionPatch));
      harness.repository.failCommand(const ActionConflictFailure());
      await pumpEventQueue();

      model.refresh();
      harness.repository.failRead(const ActionReadUnavailableFailure());
      await pumpEventQueue();
      expect(model.state, isA<ActionPanelUnavailable>());
      expect(model.completionLock, isNotNull);

      model.retry();
      harness.repository.emit(actionDetailsFixture(), revision: 10);
      await pumpEventQueue();
      expect(model.state, isA<ActionPanelLoaded>());
      expect(model.completionLock, isNull);
    });
  });
}

const _patch = ActionFieldsPatch(priority: ActionFieldSet(ActionPriority.p1));

const _completionPatch = ActionFieldsPatch(isCompleted: ActionFieldSet(true));

final class _Harness {
  _Harness() : repository = ActionPanelRepository() {
    container = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWith((ref) => repository),
      ],
    );
    model = ActionPanelViewModel(repository, coordinator, actionIdOf(1));
  }

  static Future<_Harness> loaded() async {
    final harness = _Harness();
    harness.repository.emit(actionDetailsFixture(), revision: 1);
    await pumpEventQueue();
    return harness;
  }

  final ActionPanelRepository repository;
  late final ProviderContainer container;
  late final ActionPanelViewModel model;

  GraphCommandCoordinator get coordinator =>
      container.read(graphCommandCoordinatorProvider.notifier);

  Future<void> dispose() async {
    await repository.dispose();
    container.dispose();
  }
}
