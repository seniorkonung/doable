import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/presentation/graph_operation_presenter.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
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

  testWidgets(
    'показывает безопасный конфликт блокирующих связей в общей поверхности',
    (tester) async {
      final harness = await _pumpPresenterApp(tester);
      final operation = harness.startDelete(index: 3, title: 'Связанное');
      harness.completeBlockingRelations(operation);
      await tester.pumpAndSettle();

      expect(find.text(_linkedNotDeleted('Связанное')), findsOneWidget);
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

  testWidgets(
    'успех создания связи ждёт сообщение намерения в той же очереди',
    (tester) async {
      final harness = await _pumpPresenterApp(tester);
      final intention = harness.startDelete(index: 1, title: 'Намерение');
      final relation = harness.startRelationCreation();
      harness.completeDeleted(intention);
      harness.completeRelationCreated(relation);
      await tester.pumpAndSettle();

      expect(find.text(_deleted('Намерение')), findsOneWidget);
      expect(find.text(_relationCreated), findsNothing);

      await tester.pump(const Duration(seconds: 2));
      expect(find.text(_deleted('Намерение')), findsOneWidget);

      await _closeMessage(tester);
      expect(find.text(_relationCreated), findsOneWidget);
      expect(
        tester.getSemantics(
          find.byKey(const ValueKey('graph-operation-message')),
        ),
        matchesSemantics(
          label: _relationCreated,
          isLiveRegion: true,
          textDirection: TextDirection.ltr,
        ),
      );

      await _closeMessage(tester);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets('успех создания связи не предлагается инлайн-владельцу', (
    tester,
  ) async {
    final harness = await _pumpPresenterApp(tester);
    final relation = harness.startRelationCreation(releaseInitiator: false);
    harness.completeRelationCreated(relation);
    await tester.pumpAndSettle();

    expect(harness.claimInitiatorFailure(relation.token), isNull);
    expect(find.text(_relationCreated), findsOneWidget);

    await _closeMessage(tester);
    expect(find.byType(SnackBar), findsNothing);
  });

  for (final scenario in _relationFailures) {
    testWidgets(
      'переданная ошибка создания связи «${scenario.name}» предъявляется безопасным текстом',
      (tester) async {
        final harness = await _pumpPresenterApp(tester);
        final relation = harness.startRelationCreation();
        harness.completeRelationFailure(relation, scenario.failure);
        await tester.pumpAndSettle();

        expect(find.text(_relationOutcome(scenario.outcome)), findsOneWidget);

        await _closeMessage(tester);
        expect(find.byType(SnackBar), findsNothing);
      },
    );
  }

  testWidgets('результат связи без фокуса ждёт возвращения в resumed', (
    tester,
  ) async {
    final harness = await _pumpPresenterApp(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    final relation = harness.startRelationCreation();
    harness.completeRelationCreated(relation);
    await tester.pump();
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text(_relationCreated), findsOneWidget);

    await _closeMessage(tester);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets(
    'пересоздание presenter сохраняет непредъявленный результат связи',
    (tester) async {
      final harness = await _pumpPresenterApp(tester);
      final relation = harness.startRelationCreation();
      harness.completeRelationCreated(relation);
      await tester.idle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.text(_relationCreated), findsOneWidget);

      harness.presenterGeneration.value += 1;
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text(_relationCreated), findsOneWidget);

      await _closeMessage(tester);
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(harness.repository.relationCommands, hasLength(1));
    },
  );
}

const _withoutPresenter = -1;

String _deleted(String title) => 'Delete — “$title”: Intention deleted.';

String _notDeleted(String title) =>
    'Delete — “$title”: The intention couldn’t be deleted. Try again.';

String _linkedNotDeleted(String title) =>
    'Delete — “$title”: The intention wasn’t deleted: its relations still '
    'block deletion. Archived relations and relations that aren’t loaded yet '
    'block it too.';

String _relationOutcome(String outcome) => 'Create — “new relation”: $outcome';

final _relationCreated = _relationOutcome('Relation created.');

final _relationFailures =
    <({String name, LongTermRelationCommandFailure failure, String outcome})>[
      (
        name: 'validation',
        failure: const LongTermRelationCommandValidationFailure(
          CreateLongTermRelationValidationFailure.sameIntention,
        ),
        outcome: 'Check the selected intentions and relation details.',
      ),
      (
        name: 'conflict',
        failure: LongTermRelationPairOccupiedFailure(_relationId),
        outcome:
            'A relation with this direction already exists between the '
            'selected intentions.',
      ),
      (
        name: 'notFound',
        failure: LongTermRelationParticipantNotFoundFailure(
          role: RelationParticipantRole.related,
          intentionId: testDetailsIntentionId(2),
        ),
        outcome: 'One of the selected intentions no longer exists.',
      ),
      (
        name: 'archived',
        failure: LongTermRelationParticipantArchivedFailure(
          role: RelationParticipantRole.source,
          intentionId: testDetailsIntentionId(1),
        ),
        outcome: 'Only active intentions can be linked.',
      ),
      (
        name: 'unavailable',
        failure: const LongTermRelationUnavailableFailure(),
        outcome: 'The relation couldn’t be created. Try again.',
      ),
      (
        name: 'corruption',
        failure: const LongTermRelationCorruptionFailure(),
        outcome: 'Stored data is damaged. The relation wasn’t created.',
      ),
      (
        name: 'unexpected',
        failure: const LongTermRelationUnexpectedFailure(),
        outcome:
            'The relation couldn’t be created because of an unexpected '
            'error.',
      ),
    ];

final _relationId = switch (LongTermRelationId.decode(
  '018f47c2-6b7d-7abc-8def-0123456789ab',
)) {
  LongTermRelationIdDecodingSuccess(:final id) => id,
  InvalidLongTermRelationIdDecoding() => throw StateError(
    'Некорректный fixture связи.',
  ),
};

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
  final _relationIndexes = <LongTermRelationCommandAccepted, int>{};

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

  LongTermRelationCommandAccepted startRelationCreation({
    bool releaseInitiator = true,
  }) {
    final commandIndex = repository.relationCommands.length;
    final accepted = _coordinator.acceptRelationCreation(
      LongTermRelationCreationFormKey(),
      CreateLongTermRelation(
        sourceIntentionId: testDetailsIntentionId(1),
        relatedIntentionId: testDetailsIntentionId(2),
        type: LongTermRelationType.need,
        priority: RelationPriority.p2,
        description: null,
      ),
    ) as LongTermRelationCommandAccepted;
    if (releaseInitiator) {
      _coordinator.releaseInitiatorPresentation(accepted.token);
    }
    _relationIndexes[accepted] = commandIndex;
    return accepted;
  }

  GraphInitiatorPresentationClaim? claimInitiatorFailure(
    GraphOperationToken token,
  ) => _coordinator.claimInitiatorFailure(token);

  void completeRelationCreated(LongTermRelationCommandAccepted accepted) {
    const revision = TestDetailsRevision(1);
    final relation = LongTermRelation(
      id: _relationId,
      sourceIntentionId: testDetailsIntentionId(1),
      relatedIntentionId: testDetailsIntentionId(2),
      type: LongTermRelationType.need,
      priority: RelationPriority.p2,
      scope: RelationScope.active,
      creationSequence: RelationCreationSequence(1),
    );
    repository.completeRelationCommand(
      _relationIndexes[accepted]!,
      GraphCommandSucceeded(
        ConfirmedGraphResult(
          revision: revision,
          value: LongTermRelationCreated(
            relation: relation,
            description: null,
            changes: <GraphChange>[
              LongTermRelationCreatedChange(
                revision: revision,
                relation: relation,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void completeRelationFailure(
    LongTermRelationCommandAccepted accepted,
    LongTermRelationCommandFailure failure,
  ) => repository.completeRelationCommand(
    _relationIndexes[accepted]!,
    GraphCommandFailed(failure),
  );

  void completeBlockingRelations(IntentionCommandAccepted accepted) {
    final (index, _) = _titles[accepted]!;
    final intentionId = testDetailsIntention(index: index).id;
    repository.completeCommand(
      _commandIndexes[accepted]!,
      ResultFailure(IntentionHasBlockingRelationsFailure(intentionId)),
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
