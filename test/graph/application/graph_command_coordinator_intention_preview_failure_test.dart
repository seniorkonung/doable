import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/cascade/intention_cascade.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../intention/presentation/details/details_test_support.dart';

void main() {
  group('GraphCommandCoordinator — отказ чтения предпросмотра каскада', () {
    for (final (operation, kind) in [
      (CascadeOperation.archive, IntentionCommandKind.archive),
      (CascadeOperation.restore, IntentionCommandKind.restore),
      (CascadeOperation.delete, IntentionCommandKind.delete),
    ]) {
      test('${operation.name} завершается отказом предпросмотра без команды и '
          'публикуется один раз', () async {
        final repository = ControlledDetailsRepository();
        final coordinator = _coordinator(repository);
        final completions = <GraphCommandCompletion>[];
        final subscription = coordinator.completions.listen(completions.add);
        addTearDown(subscription.cancel);
        const cause = CascadePreviewUnavailable();

        final start = coordinator.acceptIntentionPreviewFailure(
          intentionId: testDetailsIntentionId(1),
          operation: operation,
          failure: cause,
          presentationTitle: 'Намерение',
        ) as IntentionCommandAccepted;
        final completion = await start.future;
        await Future<void>.delayed(Duration.zero);

        expect(repository.commands, isEmpty);
        expect(completions, [same(completion)]);
        expect(completion, isA<IntentionPresentableCompletion>());
        expect(completion.kind, kind);
        expect(completion.presentationTitle, 'Намерение');
        expect(
          completion.result,
          isA<ResultFailure<IntentionCommandSuccess>>().having(
            (result) => result.failure,
            'отказ',
            isA<IntentionCascadePreviewFailure>().having(
              (failure) => failure.cause,
              'причина',
              same(cause),
            ),
          ),
        );
        expect(coordinator.isRunning(testDetailsIntentionId(1)), isFalse);
        await coordinator.shutdown();
      });
    }

    test('отказ сразу принадлежит оболочке, а повтор становится отдельным '
        'результатом', () async {
      final coordinator = _coordinator(ControlledDetailsRepository());
      final registration = coordinator.registerAppPresentation();
      addTearDown(registration.release);

      IntentionCommandAccepted accept() =>
          coordinator.acceptIntentionPreviewFailure(
            intentionId: testDetailsIntentionId(1),
            operation: CascadeOperation.delete,
            failure: const CascadePreviewCorruption(),
            presentationTitle: 'Намерение',
          ) as IntentionCommandAccepted;
      final first = accept();
      await first.future;
      final retry = accept();
      await retry.future;

      expect(coordinator.claimInitiatorFailure(first.token), isNull);
      expect(coordinator.claimInitiatorFailure(retry.token), isNull);
      final claim = await registration.nextClaim();
      expect(claim!.completions.map((completion) => completion.token), [
        same(first.token),
        same(retry.token),
      ]);
      await coordinator.shutdown();
    });
  });
}

GraphCommandCoordinator _coordinator(ControlledDetailsRepository repository) {
  final container = ProviderContainer(
    overrides: [personalGraphRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);
  return container.read(graphCommandCoordinatorProvider.notifier);
}
