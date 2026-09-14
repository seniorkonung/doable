import 'dart:async';

import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/presentation/operation_failure_presentation.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../intention/presentation/details/details_test_support.dart';

void main() {
  setUp(() {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  testWidgets(
    'рисует конкретное сообщение с live-region семантикой и подтверждает его кадр',
    (tester) async {
      final harness = _FailureHarness();
      addTearDown(harness.dispose);
      final claim = await harness.createClaim(index: 1);

      await tester.pumpWidget(
        harness.app(
          OperationFailurePresentation(
            claim: claim,
            message: 'Ошибка сохранения',
            messageKey: const ValueKey('operation-failure-message'),
          ),
        ),
      );

      expect(find.text('Ошибка сохранения'), findsOneWidget);
      expect(
        tester.getSemantics(
          find.byKey(const ValueKey('operation-failure-message')),
        ),
        matchesSemantics(
          label: 'Ошибка сохранения',
          isLiveRegion: true,
          textDirection: TextDirection.ltr,
        ),
      );
      expect(harness.claimAgain(claim), isNull);
    },
  );

  testWidgets(
    'не подменяет область ошибки видимым полем и освобождает исчезнувший renderer',
    (tester) async {
      final harness = _FailureHarness();
      addTearDown(harness.dispose);
      final claim = await harness.createClaim(index: 2);
      final showError = ValueNotifier(true);
      addTearDown(showError.dispose);
      IntentionAppPresentationClaim? fallback;
      unawaited(
        harness.registration.nextClaim().then((value) => fallback = value),
      );

      await tester.pumpWidget(
        harness.app(
          Column(
            children: [
              const TextField(decoration: InputDecoration(labelText: 'Поле')),
              ValueListenableBuilder<bool>(
                valueListenable: showError,
                builder: (context, visible, _) => visible
                    ? ClipRect(
                        child: Align(
                          heightFactor: 0,
                          child: OperationFailurePresentation(
                            claim: claim,
                            message: 'Скрытая ошибка',
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Поле'), findsOneWidget);
      expect(harness.claimAgain(claim), same(claim));
      expect(fallback, isNull);

      showError.value = false;
      await tester.pump();
      await tester.pump();

      expect(fallback?.token, same(claim.token));
    },
  );

  testWidgets('удерживает claim при временной прозрачности renderer', (
    tester,
  ) async {
    final harness = _FailureHarness();
    addTearDown(harness.dispose);
    final claim = await harness.createClaim(index: 3);
    final opacity = ValueNotifier(0.0);
    addTearDown(opacity.dispose);

    await tester.pumpWidget(
      harness.app(
        ValueListenableBuilder<double>(
          valueListenable: opacity,
          builder: (context, value, _) => Opacity(
            opacity: value,
            child: OperationFailurePresentation(
              claim: claim,
              message: 'Временно скрытая ошибка',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(harness.claimAgain(claim), same(claim));

    opacity.value = 1;
    await tester.pump();

    expect(harness.claimAgain(claim), isNull);
  });

  testWidgets('не подтверждает claim без фокуса до возвращения в resumed', (
    tester,
  ) async {
    final harness = _FailureHarness();
    addTearDown(harness.dispose);
    final claim = await harness.createClaim(index: 4);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);

    await tester.pumpWidget(
      harness.app(
        OperationFailurePresentation(claim: claim, message: 'Ошибка'),
      ),
    );
    await tester.pump();

    expect(harness.claimAgain(claim), same(claim));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(harness.claimAgain(claim), isNull);
  });

  testWidgets('удерживает renderer на скрытом маршруте до его возвращения', (
    tester,
  ) async {
    final harness = _FailureHarness();
    addTearDown(harness.dispose);
    final claim = await harness.createClaim(index: 7);
    final currentClaim = ValueNotifier<IntentionInitiatorPresentationClaim?>(
      null,
    );
    addTearDown(currentClaim.dispose);

    await tester.pumpWidget(
      harness.app(
        Builder(
          builder: (context) => Column(
            children: [
              TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const AlertDialog(content: Text('Диалог')),
                ),
                child: const Text('Открыть диалог'),
              ),
              ValueListenableBuilder<IntentionInitiatorPresentationClaim?>(
                valueListenable: currentClaim,
                builder: (context, value, _) => OperationFailurePresentation(
                  claim: value,
                  message: 'Ошибка под диалогом',
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Открыть диалог'));
    await tester.pumpAndSettle();

    currentClaim.value = claim;
    await tester.pumpAndSettle();
    expect(harness.claimAgain(claim), same(claim));

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();

    expect(find.text('Диалог'), findsNothing);
    expect(harness.claimAgain(claim), isNull);
  });

  testWidgets('исчезновение после подтверждения не возвращает результат', (
    tester,
  ) async {
    final harness = _FailureHarness();
    addTearDown(harness.dispose);
    final claim = await harness.createClaim(index: 8);
    final showError = ValueNotifier(true);
    addTearDown(showError.dispose);
    IntentionAppPresentationClaim? fallback;
    unawaited(
      harness.registration.nextClaim().then((value) => fallback = value),
    );

    await tester.pumpWidget(
      harness.app(
        ValueListenableBuilder<bool>(
          valueListenable: showError,
          builder: (context, visible, _) => visible
              ? OperationFailurePresentation(
                  claim: claim,
                  message: 'Предъявленная ошибка',
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
    expect(harness.claimAgain(claim), isNull);

    showError.value = false;
    await tester.pump();
    await tester.pump();

    expect(fallback, isNull);
  });

  testWidgets(
    'замена renderer освобождает прежний claim и не даёт старому callback подтвердить новый',
    (tester) async {
      final harness = _FailureHarness();
      addTearDown(harness.dispose);
      final first = await harness.createClaim(index: 5);
      final second = await harness.createClaim(index: 6);
      final current = ValueNotifier((claim: first, message: 'Первая ошибка'));
      addTearDown(current.dispose);
      IntentionAppPresentationClaim? fallback;
      unawaited(
        harness.registration.nextClaim().then((value) => fallback = value),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);

      await tester.pumpWidget(
        harness.app(
          ValueListenableBuilder<
            ({IntentionInitiatorPresentationClaim claim, String message})
          >(
            valueListenable: current,
            builder: (context, value, _) => OperationFailurePresentation(
              claim: value.claim,
              message: value.message,
            ),
          ),
        ),
      );
      await tester.pump();

      current.value = (claim: second, message: 'Вторая ошибка');
      await tester.pump();
      await tester.pump();

      expect(fallback?.token, same(first.token));
      expect(harness.claimAgain(second), same(second));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(harness.claimAgain(second), isNull);
    },
  );
}

final class _FailureHarness {
  _FailureHarness._(this.repository, this.container) {
    registration = coordinator.registerAppPresentation();
  }

  factory _FailureHarness() {
    final repository = ControlledDetailsRepository();
    return _FailureHarness._(
      repository,
      ProviderContainer(
        overrides: [
          personalGraphRepositoryProvider.overrideWithValue(repository),
        ],
        retry: (retryCount, error) => null,
      ),
    );
  }

  final ControlledDetailsRepository repository;
  final ProviderContainer container;
  late final GraphAppPresentationRegistration registration;

  GraphCommandCoordinator get coordinator =>
      container.read(graphCommandCoordinatorProvider.notifier);

  Future<IntentionInitiatorPresentationClaim> createClaim({
    required int index,
  }) async {
    final intention = testDetailsIntention(index: index);
    final accepted = coordinator.acceptExisting(
      DeleteIntention(intention.id),
      presentationTitle: intention.title,
    ) as IntentionCommandAccepted;
    repository.completeCommand(
      repository.commands.length - 1,
      const ResultFailure(IntentionUnavailableFailure()),
    );
    await accepted.future;
    return coordinator.claimInitiatorFailure(accepted.token)!;
  }

  IntentionInitiatorPresentationClaim? claimAgain(
    IntentionInitiatorPresentationClaim claim,
  ) => coordinator.claimInitiatorFailure(claim.token);

  Widget app(Widget body) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(home: Scaffold(body: body)),
  );

  void dispose() {
    registration.release();
    container.dispose();
  }
}
