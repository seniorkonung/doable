import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/presentation/graph_operation_presenter.dart';
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
    'показывает результаты по одному без вытеснения текущего сообщения',
    (tester) async {
      final harness = await _pumpPresenterApp(tester);
      final first = harness.startDelete(index: 1, title: 'Первое');
      final second = harness.startDelete(index: 2, title: 'Второе');
      harness.completeDeleted(first);
      harness.completeDeleted(second);
      await tester.pumpAndSettle();

      expect(find.text(_deleted('Первое')), findsOneWidget);
      expect(find.text(_deleted('Второе')), findsNothing);
      expect(
        tester.getSemantics(
          find.byKey(const ValueKey('graph-operation-message')),
        ),
        matchesSemantics(
          label: _deleted('Первое'),
          isLiveRegion: true,
          textDirection: TextDirection.ltr,
        ),
      );

      await tester.pump(const Duration(seconds: 2));
      expect(find.text(_deleted('Первое')), findsOneWidget);
      expect(find.text(_deleted('Второе')), findsNothing);

      await _closeMessage(tester);
      expect(find.text(_deleted('Первое')), findsNothing);
      expect(find.text(_deleted('Второе')), findsOneWidget);

      await _closeMessage(tester);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets(
    'success с живым инициатором и fallback-ошибка используют одну очередь',
    (tester) async {
      final harness = await _pumpPresenterApp(tester);
      final success = harness.startDelete(
        index: 1,
        title: 'Успешное',
        releaseInitiator: false,
      );
      final failure = harness.startDelete(index: 2, title: 'Отказное');
      harness.completeDeleted(success);
      harness.completeUnavailable(failure);
      await tester.pumpAndSettle();

      expect(find.text(_deleted('Успешное')), findsOneWidget);
      await _closeMessage(tester);
      expect(find.text(_notDeleted('Отказное')), findsOneWidget);
      await _closeMessage(tester);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  for (final scenario
      in <
        ({
          AppLifecycleState state,
          List<AppLifecycleState> away,
          List<AppLifecycleState> back,
        })
      >[
        (
          state: AppLifecycleState.inactive,
          away: [AppLifecycleState.inactive],
          back: [AppLifecycleState.resumed],
        ),
        (
          state: AppLifecycleState.hidden,
          away: [AppLifecycleState.inactive, AppLifecycleState.hidden],
          back: [AppLifecycleState.inactive, AppLifecycleState.resumed],
        ),
        (
          state: AppLifecycleState.paused,
          away: [
            AppLifecycleState.inactive,
            AppLifecycleState.hidden,
            AppLifecycleState.paused,
          ],
          back: [
            AppLifecycleState.hidden,
            AppLifecycleState.inactive,
            AppLifecycleState.resumed,
          ],
        ),
        (
          state: AppLifecycleState.detached,
          away: [
            AppLifecycleState.inactive,
            AppLifecycleState.hidden,
            AppLifecycleState.paused,
            AppLifecycleState.detached,
          ],
          back: [AppLifecycleState.resumed],
        ),
      ]) {
    testWidgets(
      '${scenario.state.name} удерживает результат до возвращения в resumed',
      (tester) async {
        final harness = await _pumpPresenterApp(tester);
        for (final state in scenario.away) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
        final operation = harness.startDelete(index: 1, title: 'Фоновое');
        harness.completeDeleted(operation);
        await tester.pump();
        await tester.pump();
        expect(find.byType(SnackBar), findsNothing);

        for (final state in scenario.back) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
        await tester.pumpAndSettle();
        expect(find.text(_deleted('Фоновое')), findsOneWidget);

        await _closeMessage(tester);
        expect(find.byType(SnackBar), findsNothing);
      },
    );
  }

  testWidgets('неизвестное исходное lifecycle state не разрешает показ', (
    tester,
  ) async {
    final harness = await _pumpPresenterApp(tester);
    tester.binding.resetInternalState();
    final operation = harness.startDelete(index: 1, title: 'Неизвестное');
    harness.completeDeleted(operation);
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text(_deleted('Неизвестное')), findsOneWidget);
  });

  testWidgets(
    'потеря фокуса до кадра сохраняет результат, исчезнувший до возвращения',
    (tester) async {
      final harness = await _pumpPresenterApp(tester);
      final operation = harness.startDelete(index: 1, title: 'Отложенное');
      harness.completeDeleted(operation);
      await tester.idle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(find.text(_deleted('Отложенное')), findsOneWidget);

      await _closeMessage(tester);
      expect(find.byType(SnackBar), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text(_deleted('Отложенное')), findsOneWidget);

      await _closeMessage(tester);
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets(
    'пересоздание до подтверждения снимает прежнее сообщение и показывает результат один раз',
    (tester) async {
      final harness = await _pumpPresenterApp(tester);
      final operation = harness.startDelete(index: 1, title: 'Пересоздание');
      harness.completeDeleted(operation);
      await tester.idle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.text(_deleted('Пересоздание')), findsOneWidget);

      harness.presenterGeneration.value += 1;
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text(_deleted('Пересоздание')), findsOneWidget);

      await _closeMessage(tester);
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(harness.repository.commands, hasLength(1));
    },
  );

  testWidgets(
    'пересоздание после подтверждения снимает поверхность без повтора и продолжает очередь',
    (tester) async {
      final harness = await _pumpPresenterApp(tester);
      final first = harness.startDelete(index: 1, title: 'Предъявленное');
      final second = harness.startDelete(index: 2, title: 'Следующее');
      harness.completeDeleted(first);
      harness.completeDeleted(second);
      await tester.pumpAndSettle();
      expect(find.text(_deleted('Предъявленное')), findsOneWidget);

      harness.presenterGeneration.value += 1;
      await tester.pumpAndSettle();
      expect(find.text(_deleted('Предъявленное')), findsNothing);
      expect(find.text(_deleted('Следующее')), findsOneWidget);

      await _closeMessage(tester);
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets(
    'новый presenter получает завершения без подписчика в прежнем порядке',
    (tester) async {
      final harness = await _pumpPresenterApp(tester);
      harness.presenterGeneration.value = _withoutPresenter;
      await tester.pumpAndSettle();

      final first = harness.startDelete(index: 1, title: 'Первое');
      final second = harness.startDelete(index: 2, title: 'Второе');
      harness.completeDeleted(first);
      harness.completeUnavailable(second);
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);

      harness.presenterGeneration.value = 1;
      await tester.pumpAndSettle();
      expect(find.text(_deleted('Первое')), findsOneWidget);
      await _closeMessage(tester);
      expect(find.text(_notDeleted('Второе')), findsOneWidget);
      await _closeMessage(tester);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets(
    'досрочное снятие подтверждённого сообщения не возвращает результат',
    (tester) async {
      final harness = await _pumpPresenterApp(tester);
      final first = harness.startDelete(index: 1, title: 'Снятое');
      final second = harness.startDelete(index: 2, title: 'Следующее');
      harness.completeDeleted(first);
      harness.completeDeleted(second);
      await tester.pumpAndSettle();
      expect(find.text(_deleted('Снятое')), findsOneWidget);

      // Имитирует закрытие сообщения пользователем после предъявления.
      ScaffoldMessenger.of(tester.element(find.byType(Scaffold)))
          .removeCurrentSnackBar();
      await tester.pumpAndSettle();
      expect(find.text(_deleted('Снятое')), findsNothing);
      expect(find.text(_deleted('Следующее')), findsOneWidget);

      await _closeMessage(tester);
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    },
  );
}

const _withoutPresenter = -1;

String _deleted(String title) => 'Delete — “$title”: Intention deleted.';

String _notDeleted(String title) =>
    'Delete — “$title”: The intention couldn’t be deleted. Try again.';

Future<void> _closeMessage(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

final class _PresenterHarness {
  _PresenterHarness(this.container, this.repository, this.presenterGeneration);

  final ProviderContainer container;
  final ControlledDetailsRepository repository;
  final ValueNotifier<int> presenterGeneration;
  final _commandIndexes = <IntentionCommandAccepted, int>{};
  final _titles = <IntentionCommandAccepted, (int, String)>{};

  GraphCommandCoordinator get _coordinator =>
      container.read(graphCommandCoordinatorProvider.notifier);

  IntentionCommandAccepted startDelete({
    required int index,
    required String title,
    bool releaseInitiator = true,
  }) {
    final intention = testDetailsIntention(index: index, title: title);
    final commandIndex = repository.commands.length;
    final accepted = _coordinator.acceptExisting(
      DeleteIntention(intention.id),
      presentationTitle: title,
    ) as IntentionCommandAccepted;
    if (releaseInitiator) {
      _coordinator.releaseInitiatorPresentation(accepted.token);
    }
    _commandIndexes[accepted] = commandIndex;
    _titles[accepted] = (index, title);
    return accepted;
  }

  void completeDeleted(IntentionCommandAccepted accepted) {
    final (index, title) = _titles[accepted]!;
    repository.completeCommand(
      _commandIndexes[accepted]!,
      testDetailsDeletedResult(
        testDetailsIntention(index: index, title: title),
      ),
    );
  }

  void completeUnavailable(IntentionCommandAccepted accepted) {
    repository.completeCommand(
      _commandIndexes[accepted]!,
      const ResultFailure(IntentionUnavailableFailure()),
    );
  }
}

Future<_PresenterHarness> _pumpPresenterApp(WidgetTester tester) async {
  final repository = ControlledDetailsRepository();
  final container = ProviderContainer(
    overrides: [personalGraphRepositoryProvider.overrideWithValue(repository)],
    retry: (retryCount, error) => null,
  );
  addTearDown(container.dispose);
  final presenterGeneration = ValueNotifier<int>(0);
  addTearDown(presenterGeneration.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => ValueListenableBuilder<int>(
          valueListenable: presenterGeneration,
          builder: (context, generation, _) {
            final content = child ?? const SizedBox.shrink();
            return generation == _withoutPresenter
                ? content
                : GraphOperationPresenter(
                    key: ValueKey(generation),
                    child: content,
                  );
          },
        ),
        home: const Scaffold(body: SizedBox.expand()),
      ),
    ),
  );
  await tester.pump();
  return _PresenterHarness(container, repository, presenterGeneration);
}
