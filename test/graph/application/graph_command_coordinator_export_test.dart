import 'dart:async';

import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../intention/presentation/details/details_test_support.dart';

void main() {
  test('второй экспорт во время первого не принимается, а повтор из '
      'отказа — новая операция со своим токеном', () async {
    final harness = _Harness();
    final first = Completer<GraphExportOutcome>();
    GraphExportStart? retried;
    final accepted = harness.coordinator.acceptExport(
      export: () => first.future,
      retry: () => retried = harness.coordinator.acceptExport(
        export: () async => GraphExportOutcome.succeeded,
        retry: () {},
      ),
    ) as GraphExportAccepted;

    expect(
      harness.coordinator.acceptExport(
        export: () => fail('Второй экспорт не должен запускаться'),
        retry: () {},
      ),
      isA<GraphExportAlreadyRunning>(),
    );

    first.complete(GraphExportOutcome.failed);
    final failure = await accepted.future;
    expect(failure.isFailure, isTrue);
    expect(retried, isNull);

    failure.retry();
    final retry = await (retried! as GraphExportAccepted).future;
    expect(retry.isFailure, isFalse);
    expect(retry.token, isNot(same(failure.token)));
    await harness.coordinator.shutdown();
  });

  test('завершение команды, принятой во время экспорта, публикуется и '
      'выдаётся общей поверхности до окончания экспорта', () async {
    final harness = _Harness();
    final published = <GraphCommandCompletion>[];
    final subscription = harness.coordinator.completions.listen(published.add);
    final registration = harness.coordinator.registerAppPresentation();
    final export = Completer<GraphExportOutcome>();
    final exportAccepted = harness.coordinator.acceptExport(
      export: () => export.future,
      retry: () {},
    ) as GraphExportAccepted;
    final command = harness.startDelete(1);

    harness.completeDeleted(command, 1);
    final commandCompletion = await command.future;
    final commandClaim = await registration.nextClaim();
    expect(published, [same(commandCompletion)]);
    expect(commandClaim?.completions, [same(commandCompletion)]);
    harness.coordinator.confirmAppPresentation(commandClaim!, [
      commandCompletion.token,
    ]);

    final exportClaim = registration.nextClaim();
    export.complete(GraphExportOutcome.failed);
    final exportCompletion = await exportAccepted.future;
    expect(published, [same(commandCompletion), same(exportCompletion)]);
    expect((await exportClaim)?.completions, [same(exportCompletion)]);
    expect(
      harness.coordinator.claimInitiatorFailure(exportCompletion.token),
      isNull,
    );

    registration.release();
    await subscription.cancel();
    await harness.coordinator.shutdown();
  });

  test('результаты ждут общую поверхность в порядке публикации, а не '
      'принятия', () async {
    final harness = _Harness();
    final export = Completer<GraphExportOutcome>();
    final exportAccepted = harness.coordinator.acceptExport(
      export: () => export.future,
      retry: () {},
    ) as GraphExportAccepted;
    final command = harness.startDelete(1);

    harness.completeDeleted(command, 1);
    final commandCompletion = await command.future;
    export.complete(GraphExportOutcome.succeeded);
    final exportCompletion = await exportAccepted.future;

    final registration = harness.coordinator.registerAppPresentation();
    final claim = await registration.nextClaim();
    expect(claim?.completions, [
      same(commandCompletion),
      same(exportCompletion),
    ]);
    registration.release();
    await harness.coordinator.shutdown();
  });

  test('во время завершения работы экспорт не принимается, а принятый '
      'дожидаются', () async {
    final harness = _Harness();
    final export = Completer<GraphExportOutcome>();
    final accepted = harness.coordinator.acceptExport(
      export: () => export.future,
      retry: () {},
    ) as GraphExportAccepted;

    var isShutDown = false;
    final shutdown = harness.coordinator.shutdown().then(
      (_) => isShutDown = true,
    );
    expect(
      harness.coordinator.acceptExport(
        export: () => fail('Экспорт не должен запускаться'),
        retry: () {},
      ),
      isA<GraphCommandCoordinatorDraining>(),
    );
    await pumpEventQueue();
    expect(isShutDown, isFalse);

    export.complete(GraphExportOutcome.succeeded);
    expect((await accepted.future).isFailure, isFalse);
    await shutdown;
    expect(isShutDown, isTrue);
  });

  test('исключение экспорта становится отказом и не оставляет экспорт '
      'идущим', () async {
    final harness = _Harness();
    final accepted = harness.coordinator.acceptExport(
      export: () => Future.error(StateError('Текст экспорта.')),
      retry: () {},
    ) as GraphExportAccepted;

    expect((await accepted.future).isFailure, isTrue);
    expect(
      harness.coordinator.acceptExport(
        export: () async => GraphExportOutcome.succeeded,
        retry: () {},
      ),
      isA<GraphExportAccepted>(),
    );
    await harness.coordinator.shutdown();
  });
}

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

  IntentionCommandAccepted startDelete(int index) {
    final intention = testDetailsIntention(index: index);
    final commandIndex = repository.commands.length;
    final accepted = coordinator.acceptExisting(
      DeleteIntention(intention.id),
      presentationTitle: intention.title,
    ) as IntentionCommandAccepted;
    coordinator.releaseInitiatorPresentation(accepted.token);
    _commandIndexes[accepted] = commandIndex;
    return accepted;
  }

  void completeDeleted(IntentionCommandAccepted accepted, int index) =>
      repository.completeCommand(
        _commandIndexes[accepted]!,
        testDetailsDeletedResult(testDetailsIntention(index: index)),
      );
}
