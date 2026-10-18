import 'dart:async';

import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../intention/presentation/details/details_test_support.dart';

void main() {
  test('подготовка восстановления не мешает командам, а на время замены '
      'новые команды не принимаются, и принятые раньше завершаются до её '
      'начала', () async {
    final harness = _Harness();
    final published = <GraphCommandCompletion>[];
    final subscription = harness.coordinator.completions.listen(published.add);
    final beforeRestore = harness.startDelete(1);
    final preparation = Completer<void>();
    final replacement = Completer<ConfirmedGraphReplacement>();
    var isReplacing = false;
    final accepted = harness.coordinator.acceptBackupRestore((exclusive) async {
      await preparation.future;
      return exclusive.replace(() {
        isReplacing = true;
        return replacement.future;
      });
    }) as GraphBackupRestoreAccepted;

    final duringPreparation = harness.startDelete(2);
    preparation.complete();
    await pumpEventQueue();
    expect(harness.startDeleteOf(3), isA<GraphCommandCoordinatorDraining>());
    expect(isReplacing, isFalse);

    harness.completeDeleted(beforeRestore, 1);
    await pumpEventQueue();
    expect(isReplacing, isFalse);
    harness.completeDeleted(duringPreparation, 2);
    await pumpEventQueue();
    expect(isReplacing, isTrue);
    expect(harness.startDeleteOf(4), isA<GraphCommandCoordinatorDraining>());

    replacement.complete(ConfirmedGraphReplacement(_newEpochRevision));
    final outcome = await accepted.future;
    expect(outcome, isA<GraphBackupRestored>());
    expect(published, [
      same(await beforeRestore.future),
      same(await duringPreparation.future),
      isA<GraphBackupRestoreCompletion>().having(
        (completion) => completion.confirmedChange?.changes,
        'изменения',
        [isA<GraphReplaced>()],
      ),
    ]);
    final afterRestore = harness.startDeleteOf(5);
    expect(afterRestore, isA<IntentionCommandAccepted>());

    harness.completeDeleted(afterRestore as IntentionCommandAccepted, 5);
    await subscription.cancel();
    await harness.coordinator.shutdown();
  });

  test('второе восстановление во время первого не принимается', () async {
    final harness = _Harness();
    final first = Completer<GraphBackupRestoreOutcome>();
    final accepted = harness.coordinator.acceptBackupRestore(
      (_) => first.future,
    ) as GraphBackupRestoreAccepted;

    expect(
      harness.coordinator.acceptBackupRestore(
        (_) => fail('Второе восстановление не должно запускаться'),
      ),
      isA<GraphBackupRestoreAlreadyRunning>(),
    );

    first.complete(const GraphBackupRestoreFailed());
    await accepted.future;
    expect(
      harness.coordinator.acceptBackupRestore(
        (_) async => const GraphBackupRestoreFailed(),
      ),
      isA<GraphBackupRestoreAccepted>(),
    );
    await harness.coordinator.shutdown();
  });

  test('во время завершения работы восстановление не принимается, а '
      'принятое дожидаются', () async {
    final harness = _Harness();
    final restore = Completer<GraphBackupRestoreOutcome>();
    final accepted = harness.coordinator.acceptBackupRestore(
      (_) => restore.future,
    ) as GraphBackupRestoreAccepted;

    var isShutDown = false;
    final shutdown = harness.coordinator.shutdown().then(
      (_) => isShutDown = true,
    );
    expect(
      harness.coordinator.acceptBackupRestore(
        (_) => fail('Восстановление не должно запускаться'),
      ),
      isA<GraphCommandCoordinatorDraining>(),
    );
    await pumpEventQueue();
    expect(isShutDown, isFalse);

    restore.complete(const GraphBackupRestoreCancelled());
    await accepted.future;
    await shutdown;
    expect(isShutDown, isTrue);
  });

  test('отмена восстановления не публикует завершения и не оставляет '
      'результата ни инициатору, ни общей поверхности', () async {
    final harness = _Harness();
    final published = <GraphCommandCompletion>[];
    final subscription = harness.coordinator.completions.listen(published.add);
    final registration = harness.coordinator.registerAppPresentation();
    var claimed = false;
    unawaited(registration.nextClaim().then((_) => claimed = true));
    final accepted = harness.coordinator.acceptBackupRestore(
      (_) async => const GraphBackupRestoreCancelled(),
    ) as GraphBackupRestoreAccepted;

    expect(await accepted.future, isA<GraphBackupRestoreCancelled>());
    harness.coordinator.releaseInitiatorPresentation(accepted.token);
    await pumpEventQueue();
    expect(published, isEmpty);
    expect(claimed, isFalse);
    expect(harness.coordinator.claimInitiatorFailure(accepted.token), isNull);

    registration.release();
    await subscription.cancel();
    await harness.coordinator.shutdown();
  });

  test('исключение замены становится отказом восстановления, и команды '
      'снова принимаются', () async {
    final harness = _Harness();
    final accepted = harness.coordinator.acceptBackupRestore(
      (exclusive) =>
          exclusive.replace(() => Future.error(StateError('Отказ хранилища.'))),
    ) as GraphBackupRestoreAccepted;

    expect(await accepted.future, isA<GraphBackupRestoreFailed>());
    final afterRestore = harness.startDeleteOf(1);
    expect(afterRestore, isA<IntentionCommandAccepted>());

    harness.completeDeleted(afterRestore as IntentionCommandAccepted, 1);
    await harness.coordinator.shutdown();
  });
}

const _newEpochRevision = TestDetailsRevision(0, epoch: 1);

final class _Harness {
  _Harness() {
    final container = ProviderContainer.test(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    coordinator = container.read(graphCommandCoordinatorProvider.notifier);
  }

  final repository = ControlledDetailsRepository();
  late final GraphCommandCoordinator coordinator;
  final _commandIndexes = <IntentionCommandAccepted, int>{};

  IntentionCommandStart startDeleteOf(int index) {
    final intention = testDetailsIntention(index: index);
    final commandIndex = repository.commands.length;
    final start = coordinator.acceptExisting(
      DeleteIntention(intention.id),
      presentationTitle: intention.title,
    );
    if (start case IntentionCommandAccepted(:final token)) {
      coordinator.releaseInitiatorPresentation(token);
      _commandIndexes[start] = commandIndex;
    }
    return start;
  }

  IntentionCommandAccepted startDelete(int index) =>
      startDeleteOf(index) as IntentionCommandAccepted;

  void completeDeleted(IntentionCommandAccepted accepted, int index) =>
      repository.completeCommand(
        _commandIndexes[accepted]!,
        testDetailsDeletedResult(testDetailsIntention(index: index)),
      );
}
