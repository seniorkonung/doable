import 'dart:async';

import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../intention/presentation/details/details_test_support.dart';

void main() {
  test('подготовка импорта не мешает командам, а на время замены новые '
      'команды не принимаются, и принятые раньше завершаются до её '
      'начала', () async {
    final harness = _Harness();
    final published = <GraphCommandCompletion>[];
    final subscription = harness.coordinator.completions.listen(published.add);
    final beforeImport = harness.startDelete(1);
    final preparation = Completer<void>();
    final replacement = Completer<ConfirmedGraphReplacement>();
    var isReplacing = false;
    final accepted = harness.coordinator.acceptImport((exclusive) async {
      await preparation.future;
      return exclusive.replace(() {
        isReplacing = true;
        return replacement.future;
      });
    }) as GraphImportAccepted;

    final duringPreparation = harness.startDelete(2);
    preparation.complete();
    await pumpEventQueue();
    expect(harness.startDeleteOf(3), isA<GraphCommandCoordinatorDraining>());
    expect(isReplacing, isFalse);

    harness.completeDeleted(beforeImport, 1);
    await pumpEventQueue();
    expect(isReplacing, isFalse);
    harness.completeDeleted(duringPreparation, 2);
    await pumpEventQueue();
    expect(isReplacing, isTrue);
    expect(harness.startDeleteOf(4), isA<GraphCommandCoordinatorDraining>());

    replacement.complete(ConfirmedGraphReplacement(_newEpochRevision));
    expect(await accepted.future, isA<GraphImported>());
    expect(published, [
      same(await beforeImport.future),
      same(await duringPreparation.future),
      isA<GraphImportCompletion>().having(
        (completion) => completion.confirmedChange?.changes,
        'изменения',
        [isA<GraphReplaced>()],
      ),
    ]);
    final afterImport = harness.startDeleteOf(5);
    expect(afterImport, isA<IntentionCommandAccepted>());

    harness.completeDeleted(afterImport as IntentionCommandAccepted, 5);
    await subscription.cancel();
    await harness.coordinator.shutdown();
  });

  test('пока идёт импорт или восстановление копии, вторая замена графа не '
      'принимается', () async {
    final harness = _Harness();
    final import = Completer<GraphImportOutcome>();
    final importAccepted = harness.coordinator.acceptImport(
      (_) => import.future,
    ) as GraphImportAccepted;

    expect(
      harness.coordinator.acceptImport(
        (_) => fail('Второй импорт не должен запускаться'),
      ),
      isA<GraphReplacementAlreadyRunning>(),
    );
    expect(
      harness.coordinator.acceptBackupRestore(
        (_) => fail('Восстановление не должно запускаться'),
      ),
      isA<GraphReplacementAlreadyRunning>(),
    );

    import.complete(const GraphImportCancelled());
    await importAccepted.future;
    final restore = Completer<GraphBackupRestoreOutcome>();
    final restoreAccepted = harness.coordinator.acceptBackupRestore(
      (_) => restore.future,
    ) as GraphBackupRestoreAccepted;
    expect(
      harness.coordinator.acceptImport(
        (_) => fail('Импорт не должен запускаться'),
      ),
      isA<GraphReplacementAlreadyRunning>(),
    );

    restore.complete(const GraphBackupRestoreCancelled());
    await restoreAccepted.future;
    expect(
      harness.coordinator.acceptImport(
        (_) async => const GraphImportCancelled(),
      ),
      isA<GraphImportAccepted>(),
    );
    await harness.coordinator.shutdown();
  });

  test('исход, известный до замены, сразу публикуется завершением импорта '
      'без изменения графа', () async {
    final harness = _Harness();
    final published = <GraphCommandCompletion>[];
    final subscription = harness.coordinator.completions.listen(published.add);

    final accepted = harness.coordinator.acceptImport(
      (_) async =>
          const GraphImportFailed(GraphImportFailure.documentUnreadable),
    ) as GraphImportAccepted;

    final outcome = await accepted.future;
    expect(published, [
      isA<GraphImportCompletion>()
          .having((completion) => completion.result, 'исход', same(outcome))
          .having(
            (completion) => completion.confirmedChange,
            'изменения',
            null,
          ),
    ]);

    await subscription.cancel();
    await harness.coordinator.shutdown();
  });

  test('отмена импорта не публикует завершения и не оставляет результата ни '
      'инициатору, ни общей поверхности', () async {
    final harness = _Harness();
    final published = <GraphCommandCompletion>[];
    final subscription = harness.coordinator.completions.listen(published.add);
    final registration = harness.coordinator.registerAppPresentation();
    var claimed = false;
    unawaited(registration.nextClaim().then((_) => claimed = true));
    final accepted = harness.coordinator.acceptImport(
      (_) async => const GraphImportCancelled(),
    ) as GraphImportAccepted;

    expect(await accepted.future, isA<GraphImportCancelled>());
    harness.coordinator.releaseInitiatorPresentation(accepted.token);
    await pumpEventQueue();
    expect(published, isEmpty);
    expect(claimed, isFalse);
    expect(harness.coordinator.claimInitiatorFailure(accepted.token), isNull);

    registration.release();
    await subscription.cancel();
    await harness.coordinator.shutdown();
  });

  test('во время завершения работы импорт не принимается, а принятый '
      'дожидаются', () async {
    final harness = _Harness();
    final import = Completer<GraphImportOutcome>();
    final accepted = harness.coordinator.acceptImport(
      (_) => import.future,
    ) as GraphImportAccepted;

    var isShutDown = false;
    final shutdown = harness.coordinator.shutdown().then(
      (_) => isShutDown = true,
    );
    expect(
      harness.coordinator.acceptImport(
        (_) => fail('Импорт не должен запускаться'),
      ),
      isA<GraphCommandCoordinatorDraining>(),
    );
    await pumpEventQueue();
    expect(isShutDown, isFalse);

    import.complete(const GraphImportCancelled());
    await accepted.future;
    await shutdown;
    expect(isShutDown, isTrue);
  });

  test('исключение замены становится отказом импорта по неизвестной причине, '
      'и команды снова принимаются', () async {
    final harness = _Harness();
    final accepted = harness.coordinator.acceptImport(
      (exclusive) =>
          exclusive.replace(() => Future.error(StateError('Отказ хранилища.'))),
    ) as GraphImportAccepted;

    expect(
      await accepted.future,
      isA<GraphImportFailed>().having(
        (outcome) => outcome.failure,
        'категория',
        GraphImportFailure.unknown,
      ),
    );
    final afterImport = harness.startDeleteOf(1);
    expect(afterImport, isA<IntentionCommandAccepted>());

    harness.completeDeleted(afterImport as IntentionCommandAccepted, 1);
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
