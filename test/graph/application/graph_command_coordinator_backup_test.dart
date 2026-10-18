import 'dart:async';

import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph_backups/graph_backups.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../intention/presentation/details/details_test_support.dart';

void main() {
  test('успех ручной копии публикуется для согласования и не оставляет '
      'результата общей поверхности', () async {
    final coordinator = _coordinator();
    final published = <GraphCommandCompletion>[];
    final subscription = coordinator.completions.listen(published.add);
    final registration = coordinator.registerAppPresentation();
    var claimed = false;
    unawaited(registration.nextClaim().then((_) => claimed = true));

    final accepted = coordinator.acceptManualBackup(
      () async => ManualGraphBackupOutcome.made,
    ) as GraphManualBackupAccepted;

    expect(await accepted.future, isA<GraphManualBackupMadeCompletion>());
    await pumpEventQueue();
    expect(published, [isA<GraphManualBackupMadeCompletion>()]);
    expect(claimed, isFalse);

    registration.release();
    await subscription.cancel();
    await coordinator.shutdown();
  });

  test('вторая ручная копия во время первой не принимается', () async {
    final coordinator = _coordinator();
    final first = Completer<ManualGraphBackupOutcome>();
    final accepted = coordinator.acceptManualBackup(
      () => first.future,
    ) as GraphManualBackupAccepted;

    expect(
      coordinator.acceptManualBackup(
        () => fail('Вторая копия не должна запускаться'),
      ),
      isA<GraphManualBackupAlreadyRunning>(),
    );

    first.complete(ManualGraphBackupOutcome.made);
    await accepted.future;
    expect(
      coordinator.acceptManualBackup(() async => ManualGraphBackupOutcome.made),
      isA<GraphManualBackupAccepted>(),
    );
    await coordinator.shutdown();
  });

  test('во время завершения работы ручная копия не принимается, а принятую '
      'дожидаются', () async {
    final coordinator = _coordinator();
    final backup = Completer<ManualGraphBackupOutcome>();
    final accepted = coordinator.acceptManualBackup(
      () => backup.future,
    ) as GraphManualBackupAccepted;

    var isShutDown = false;
    final shutdown = coordinator.shutdown().then((_) => isShutDown = true);
    expect(
      coordinator.acceptManualBackup(() => fail('Копия не должна запускаться')),
      isA<GraphCommandCoordinatorDraining>(),
    );
    await pumpEventQueue();
    expect(isShutDown, isFalse);

    backup.complete(ManualGraphBackupOutcome.failed);
    await accepted.future;
    await shutdown;
    expect(isShutDown, isTrue);
  });
}

GraphCommandCoordinator _coordinator() {
  final container = ProviderContainer.test(
    overrides: [
      personalGraphRepositoryProvider.overrideWithValue(
        ControlledDetailsRepository(),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container.read(graphCommandCoordinatorProvider.notifier);
}
