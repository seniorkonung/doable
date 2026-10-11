import 'dart:async';

import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_text.dart';
import 'package:doable/src/intention/presentation/details/intention_details_state.dart';
import 'package:doable/src/intention/presentation/details/intention_details_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'details_test_support.dart';
import '../../../support/daily_choice_reconciliation_fixture.dart';

void main() {
  test(
    'старый снимок не снимает новую дневную блокировку удаления намерения',
    () async {
      final repository = ControlledDetailsRepository(shareSecondWatch: false);
      final container = _detailsContainer(repository);
      addTearDown(container.dispose);
      final intention = testDetailsIntention(index: 73);
      final selected = testDetailsIntentionId(74);
      final relation = testDetailsRelationRow(ownerId: intention.id, index: 73);
      final choice = reconciliationChoice(
        source: intention.id,
        selected: selected,
      );
      final provider = intentionDetailsViewModelProvider(intention.id);
      final subscription = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await waitForDetailRequests(repository, 1);
      repository.detailRequests[0].add(
        ResultSuccess(intention),
        revision: const TestDetailsRevision(1),
      );
      await pumpEventQueue();

      final start =
          container
                  .read(graphCommandCoordinatorProvider.notifier)
                  .acceptDailyChoiceCreation(
                    DailyChoiceCreationFormKey(),
                    reconciliationCreateCommand(choice, relation.relation.id),
                  )
              as DailyChoiceCommandAccepted;
      repository.completeDailyChoiceCommand(
        0,
        reconciliationChoiceCreated(
          choice: choice,
          pathRelationId: relation.relation.id,
          revision: const TestDetailsRevision(3),
          counts: {
            intention.id: testRelationCounts(dailySource: 1),
            selected: testRelationCounts(dailySelected: 1),
          },
        ),
      );
      await start.future;
      await waitForDetailRequests(repository, 2);

      repository.detailRequests[1].add(
        ResultSuccess(testDetailsIntention(index: 73, title: 'Устаревшее')),
        revision: const TestDetailsRevision(2),
      );
      await pumpEventQueue();
      expect(
        (container.read(provider) as IntentionDetailsLoaded).intention.title,
        intention.title,
      );

      repository.detailRequests[1].add(
        ResultSuccess(intention),
        revision: const TestDetailsRevision(3),
        relationCounts: testRelationCounts(dailySource: 1),
      );
      await pumpEventQueue();
      var current = container.read(provider) as IntentionDetailsLoaded;
      expect(current.details.relationCounts.total, 1);
      expect(current.details.relationCounts.dailySource, 1);

      repository.detailRequests[1].add(
        ResultSuccess(intention),
        revision: const TestDetailsRevision(2),
      );
      await pumpEventQueue();
      current = container.read(provider) as IntentionDetailsLoaded;
      expect(current.details.relationCounts.dailySource, 1);
      expect(current.details.relationCounts.total, 1);
    },
  );

  test('завершение удаления дневного выбора удерживает актуальный запрет намерения', () async {
    final repository = ControlledDetailsRepository(shareSecondWatch: false);
    final container = _detailsContainer(repository);
    addTearDown(container.dispose);
    final intention = testDetailsIntention(index: 71);
    final selected = testDetailsIntentionId(72);
    final relation = testDetailsRelationRow(ownerId: intention.id, index: 71);
    final choice = reconciliationChoice(
      source: intention.id,
      selected: selected,
    );
    final provider = intentionDetailsViewModelProvider(intention.id);
    final subscription = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await waitForDetailRequests(repository, 1);
    repository.detailRequests[0].add(
      ResultSuccess(intention),
      revision: const TestDetailsRevision(1),
      relationCounts: testRelationCounts(activeNeedOutgoing: 1, dailySource: 1),
    );
    await pumpEventQueue();

    final start =
        container
                .read(graphCommandCoordinatorProvider.notifier)
                .acceptDailyChoiceDelete(DeleteDailyChoice(choice.id))
            as DailyChoiceCommandAccepted;
    repository.completeDailyChoiceCommand(
      0,
      reconciliationChoiceDeleted(
        choice: choice,
        pathRelationId: relation.relation.id,
        revision: const TestDetailsRevision(3),
        counts: {
          intention.id: testRelationCounts(activeNeedOutgoing: 1),
          selected: testRelationCounts(),
        },
      ),
    );
    await start.future;
    await waitForDetailRequests(repository, 2);

    repository.detailRequests[1].add(
      ResultSuccess(intention),
      revision: const TestDetailsRevision(2),
      relationCounts: testRelationCounts(activeNeedOutgoing: 1, dailySource: 1),
    );
    await pumpEventQueue();
    var current = container.read(provider) as IntentionDetailsLoaded;
    expect(current.revision, const TestDetailsRevision(1));
    expect(current.details.relationCounts.total, 2);

    repository.detailRequests[1].add(
      ResultSuccess(intention),
      revision: const TestDetailsRevision(3),
      relationCounts: testRelationCounts(activeNeedOutgoing: 1),
    );
    await pumpEventQueue();
    current = container.read(provider) as IntentionDetailsLoaded;
    expect(current.revision, const TestDetailsRevision(3));
    expect(current.details.relationCounts.dailyTotal, 0);
    expect(current.details.relationCounts.total, 1);
  });

  test('повтор недоступного чтения игнорирует позднее старое чтение и не затрагивает другое намерение', () async {
    final repository = ControlledDetailsRepository();
    final container = _detailsContainer(repository);
    final firstId = testDetailsIntentionId(21);
    final secondId = testDetailsIntentionId(22);
    final firstSubscription = container.listen(
      intentionDetailsViewModelProvider(firstId),
      (_, _) {},
      fireImmediately: true,
    );
    final secondSubscription = container.listen(
      intentionDetailsViewModelProvider(secondId),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(firstSubscription.close);
    addTearDown(secondSubscription.close);
    addTearDown(container.dispose);
    await waitForDetailRequests(repository, 2);

    repository.detailRequests[0].add(
      const ResultFailure(IntentionUnavailableFailure()),
    );
    await pumpEventQueue();
    container.read(intentionDetailsViewModelProvider(firstId).notifier).retry();
    await waitForDetailRequests(repository, 3);

    expect(
      container.read(intentionDetailsViewModelProvider(firstId)),
      isA<IntentionDetailsLoading>(),
    );

    final stale = testDetailsIntention(index: 21, title: 'Устаревшее');
    repository.detailRequests[0].add(ResultSuccess(stale));
    await pumpEventQueue();
    expect(
      container.read(intentionDetailsViewModelProvider(firstId)),
      isA<IntentionDetailsLoading>(),
    );

    final current = testDetailsIntention(index: 21, title: 'Актуальное');
    repository.detailRequests[2].add(ResultSuccess(current));
    await pumpEventQueue();
    expect(
      container.read(intentionDetailsViewModelProvider(firstId)),
      isA<IntentionDetailsLoaded>().having(
        (state) => state.intention.title,
        'актуальное намерение',
        'Актуальное',
      ),
    );
    expect(
      container.read(intentionDetailsViewModelProvider(secondId)),
      isA<IntentionDetailsLoading>(),
    );
  });

  test(
    'уход последнего слушателя отменяет чтение, а повтор открывает новое',
    () async {
      final repository = ControlledDetailsRepository();
      final container = _detailsContainer(repository);
      addTearDown(container.dispose);
      final id = testDetailsIntentionId(40);
      final firstSubscription = container.listen(
        intentionDetailsViewModelProvider(id),
        (_, _) {},
        fireImmediately: true,
      );
      await waitForDetailRequests(repository, 1);

      firstSubscription.close();
      await pumpEventQueue();
      expect(repository.detailRequests[0].cancellationCount, 1);

      final secondSubscription = container.listen(
        intentionDetailsViewModelProvider(id),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(secondSubscription.close);
      await waitForDetailRequests(repository, 2);
    },
  );

  test('сохраняет поля и snapshot для всех failures изменения', () async {
    // Любой отказ сохраняет форму одной ветвью; обычный повтор отличает
    // только устранимую недоступность.
    final scenarios = <(IntentionFailure, bool)>[
      (
        const IntentionTextInputValidationFailure(
          IntentionTextValidationFailure(
            field: IntentionTextField.title,
            reason: IntentionTextValidationReason.empty,
          ),
        ),
        false,
      ),
      (const IntentionUnavailableFailure(), true),
    ];

    for (var index = 0; index < scenarios.length; index += 1) {
      final repository = ControlledDetailsRepository();
      final container = _detailsContainer(repository);
      final intention = testDetailsIntention(index: index + 70);
      final provider = intentionDetailsViewModelProvider(intention.id);
      final subscription = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      await waitForDetailRequests(repository, 1);
      repository.detailRequests.single.add(ResultSuccess(intention));
      await pumpEventQueue();
      container.read(provider.notifier)
        ..beginEditing()
        ..changeTitle('Введённое название $index')
        ..changeDescription('Введённое описание $index')
        ..saveChanges();

      final (failure, canRetry) = scenarios[index];
      repository.completeCommand(0, ResultFailure(failure));
      await pumpEventQueue();

      expect(
        container.read(provider),
        isA<IntentionDetailsLoaded>()
            .having(
              (state) => state.intention.title,
              'последний подтверждённый snapshot',
              intention.title,
            )
            .having(
              (state) => state.edit?.title,
              'введённое название',
              'Введённое название $index',
            )
            .having(
              (state) => state.edit?.description,
              'введённое описание',
              'Введённое описание $index',
            )
            .having(
              (state) => state.edit?.canRetry,
              'доступность обычного повтора',
              canRetry,
            )
            .having(
              (state) => state.isOperationRunning,
              'освобождённый gate',
              isFalse,
            ),
      );

      subscription.close();
      container.dispose();
    }
  });

  test('retry изменения не предъявляет прежний отказ повторно', () async {
    final repository = ControlledDetailsRepository();
    final container = _detailsContainer(repository);
    addTearDown(container.dispose);
    final intention = testDetailsIntention(index: 82);
    final provider = intentionDetailsViewModelProvider(intention.id);
    final subscription = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await waitForDetailRequests(repository, 1);
    repository.detailRequests[0].add(ResultSuccess(intention));
    await pumpEventQueue();
    final coordinator = container.read(
      graphCommandCoordinatorProvider.notifier,
    );
    final presenter = coordinator.registerAppPresentation();

    final details = container.read(provider.notifier)
      ..beginEditing()
      ..changeTitle('Исправленное намерение')
      ..saveChanges();
    repository.completeCommand(
      0,
      const ResultFailure(IntentionUnavailableFailure()),
    );
    await pumpEventQueue();
    expect(
      (container.read(provider) as IntentionDetailsLoaded).edit?.canRetry,
      isTrue,
    );
    final shownFailure = (container.read(
      provider,
    ) as IntentionDetailsLoaded).edit!.failurePresentation;
    expect(shownFailure, isNotNull);
    coordinator.confirmPresentation(shownFailure!);

    details.saveChanges();
    repository.completeCommand(
      1,
      testDetailsSavedResult(
        testDetailsIntention(index: 82, title: 'Исправленное намерение'),
        before: intention,
      ),
    );
    await waitForDetailRequests(repository, 2);

    final successClaim = await presenter.nextClaim();
    expect(
      successClaim!.completions.single,
      isA<IntentionCommandCompletion>().having(
        (completion) => completion.result,
        'результат повтора',
        isA<ResultSuccess<IntentionCommandSuccess>>(),
      ),
    );
    coordinator.confirmAppPresentation(
      successClaim,
      successClaim.completions.map((completion) => completion.token),
    );
    GraphAppPresentationClaim? staleFailure;
    unawaited(presenter.nextClaim().then((claim) => staleFailure = claim));
    await pumpEventQueue();
    expect(staleFailure, isNull);
  });

  test('барьер перехода переживает закрытие модели и не блокирует другое намерение', () async {
    final repository = ControlledDetailsRepository();
    final container = _detailsContainer(repository);
    addTearDown(container.dispose);
    final first = testDetailsIntention(index: 94);
    final second = testDetailsIntention(index: 95);
    final firstProvider = intentionDetailsViewModelProvider(first.id);
    final firstSubscription = container.listen(
      firstProvider,
      (_, _) {},
      fireImmediately: true,
    );
    await waitForDetailRequests(repository, 1);
    repository.detailRequests[0].add(ResultSuccess(first));
    await pumpEventQueue();
    container.read(firstProvider.notifier).enableReadiness();
    firstSubscription.close();
    await pumpEventQueue();

    final reopenedSubscription = container.listen(
      firstProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(reopenedSubscription.close);
    final secondProvider = intentionDetailsViewModelProvider(second.id);
    final secondSubscription = container.listen(
      secondProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(secondSubscription.close);
    await waitForDetailRequests(repository, 3);
    repository.detailRequests[1].add(ResultSuccess(first));
    repository.detailRequests[2].add(ResultSuccess(second));
    await pumpEventQueue();

    container.read(firstProvider.notifier).archive();
    container.read(secondProvider.notifier).archive();
    expect(repository.commands, hasLength(2));
    expect(repository.commands[0], isA<EnableIntentionReadiness>());
    expect(repository.commands[1], isA<ArchiveIntention>());
    expect(
      (container.read(
        firstProvider,
      ) as IntentionDetailsLoaded).isOperationRunning,
      isTrue,
    );

    repository.completeCommand(
      0,
      const ResultFailure(IntentionUnavailableFailure()),
    );
    repository.completeCommand(
      1,
      const ResultFailure(IntentionUnexpectedFailure()),
    );
    await pumpEventQueue();
  });

  test(
    'каскад публикуется только после цельного снимка новой ревизии',
    () async {
      final repository = ControlledDetailsRepository();
      final container = _detailsContainer(repository);
      addTearDown(container.dispose);
      final before = testDetailsIntention(index: 60);
      final archived = testDetailsIntention(
        index: 60,
        archiveState: IntentionArchiveState.archived,
      );
      final beforeCounts = testRelationCounts(activeNeedOutgoing: 2);
      final archivedCounts = testRelationCounts(archivedNeedOutgoing: 2);
      final provider = intentionDetailsViewModelProvider(before.id);
      final subscription = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await waitForDetailRequests(repository, 1);
      repository.detailRequests[0].add(
        ResultSuccess(before),
        revision: const TestDetailsRevision(1),
        relationCounts: beforeCounts,
      );
      await pumpEventQueue();

      container.read(provider.notifier).archive();
      repository.completeCommand(
        0,
        testDetailsSavedResult(
          archived,
          before: before,
          revision: const TestDetailsRevision(3),
        ),
      );
      await waitForDetailRequests(repository, 2);

      expect(
        container.read(provider),
        isA<IntentionDetailsLoaded>()
            .having(
              (state) => state.intention.archiveState,
              'прежнее намерение до цельного снимка',
              IntentionArchiveState.active,
            )
            .having(
              (state) => state.details.relationCounts.activeNeedOutgoing,
              'согласованная прежняя сводка',
              2,
            ),
      );

      repository.detailRequests[1].add(
        ResultSuccess(archived),
        revision: const TestDetailsRevision(2),
        relationCounts: archivedCounts,
      );
      await pumpEventQueue();
      expect(
        container.read(provider),
        isA<IntentionDetailsLoaded>()
            .having(
              (state) => state.intention.archiveState,
              'намерение после снимка ниже барьера',
              IntentionArchiveState.active,
            )
            .having(
              (state) => state.details.relationCounts.activeNeedOutgoing,
              'сводка после снимка ниже барьера',
              2,
            ),
      );

      repository.detailRequests[1].add(
        const ResultFailure(IntentionUnavailableFailure()),
      );
      await pumpEventQueue();
      expect(container.read(provider), isA<IntentionDetailsUnavailable>());

      repository.detailRequests[1].add(
        ResultSuccess(archived),
        revision: const TestDetailsRevision(3),
        relationCounts: archivedCounts,
      );
      await pumpEventQueue();
      expect(
        container.read(provider),
        isA<IntentionDetailsLoaded>()
            .having(
              (state) => state.intention.archiveState,
              'архивированное намерение',
              IntentionArchiveState.archived,
            )
            .having(
              (state) => state.details.relationCounts.archivedNeedOutgoing,
              'сводка после каскада',
              2,
            ),
      );
      expect(repository.commands, hasLength(1));
      expect(repository.relationGroupQueries, isEmpty);
    },
  );

  test(
    'снимок старше подтверждённой ревизии не возвращает прежние поля',
    () async {
      final repository = ControlledDetailsRepository();
      final container = _detailsContainer(repository);
      addTearDown(container.dispose);
      final before = testDetailsIntention(index: 65, title: 'Прежнее');
      final saved = testDetailsIntention(index: 65, title: 'Сохранённое');
      final stale = testDetailsIntention(index: 65, title: 'Устаревшее');
      final refreshed = testDetailsIntention(index: 65, title: 'Актуальное');
      final provider = intentionDetailsViewModelProvider(before.id);
      final subscription = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await waitForDetailRequests(repository, 1);
      repository.detailRequests[0].add(
        ResultSuccess(before),
        revision: const TestDetailsRevision(1),
      );
      await pumpEventQueue();

      container.read(provider.notifier)
        ..beginEditing()
        ..changeTitle(saved.title)
        ..saveChanges();
      repository.completeCommand(
        0,
        testDetailsSavedResult(
          saved,
          before: before,
          revision: const TestDetailsRevision(3),
        ),
      );
      await waitForDetailRequests(repository, 2);

      repository.detailRequests[1].add(
        ResultSuccess(stale),
        revision: const TestDetailsRevision(2),
      );
      await pumpEventQueue();
      expect(
        (container.read(provider) as IntentionDetailsLoaded).intention.title,
        before.title,
      );

      repository.detailRequests[1].add(
        ResultSuccess(refreshed),
        revision: const TestDetailsRevision(4),
      );
      await pumpEventQueue();
      expect(
        (container.read(provider) as IntentionDetailsLoaded).intention.title,
        refreshed.title,
      );
    },
  );

  test('первый снимок нового чтения принимает новую эпоху', () async {
    final repository = ControlledDetailsRepository();
    final container = _detailsContainer(repository);
    addTearDown(container.dispose);
    final before = testDetailsIntention(index: 66, title: 'Прежнее');
    final saved = testDetailsIntention(index: 66, title: 'Сохранённое');
    final reopened = testDetailsIntention(index: 66, title: 'Новая эпоха');
    final provider = intentionDetailsViewModelProvider(before.id);
    final subscription = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await waitForDetailRequests(repository, 1);
    repository.detailRequests[0].add(
      ResultSuccess(before),
      revision: const TestDetailsRevision(1),
    );
    await pumpEventQueue();

    container.read(provider.notifier)
      ..beginEditing()
      ..changeTitle(saved.title)
      ..saveChanges();
    repository.completeCommand(
      0,
      testDetailsSavedResult(
        saved,
        before: before,
        revision: const TestDetailsRevision(2),
      ),
    );
    await waitForDetailRequests(repository, 2);

    repository.detailRequests[1].add(
      ResultSuccess(reopened),
      revision: const TestDetailsRevision(0, epoch: 1),
    );
    await pumpEventQueue();

    expect(
      (container.read(provider) as IntentionDetailsLoaded).intention.title,
      reopened.title,
    );
  });

  test('сохранение без изменений заново читает подробные данные', () async {
    final repository = ControlledDetailsRepository();
    final container = _detailsContainer(repository);
    addTearDown(container.dispose);
    final intention = testDetailsIntention(index: 61);
    final subscription = container.listen(
      intentionDetailsViewModelProvider(intention.id),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await waitForDetailRequests(repository, 1);
    repository.detailRequests[0].add(ResultSuccess(intention));
    await pumpEventQueue();

    final start = container
        .read(graphCommandCoordinatorProvider.notifier)
        .acceptExisting(
          UpdateIntention(
            id: intention.id,
            title: intention.title,
            description: intention.description,
          ),
          presentationTitle: intention.title,
        );
    repository.completeCommand(0, testDetailsSavedResult(intention));
    await (start as IntentionCommandAccepted).future;
    await waitForDetailRequests(repository, 2);

    repository.detailRequests[1].add(
      ResultSuccess(testDetailsIntention(index: 61, title: 'Перечитанное')),
    );
    await pumpEventQueue();

    expect(
      container.read(intentionDetailsViewModelProvider(intention.id)),
      isA<IntentionDetailsLoaded>().having(
        (state) => state.intention.title,
        'перечитанное намерение',
        'Перечитанное',
      ),
    );
  });

  test(
    'единый пакет обновляет подробные данные нескольких участников',
    () async {
      final repository = ControlledDetailsRepository();
      final container = _detailsContainer(repository);
      addTearDown(container.dispose);
      final first = testDetailsIntention(index: 71);
      final second = testDetailsIntention(index: 72);
      final firstProvider = intentionDetailsViewModelProvider(first.id);
      final secondProvider = intentionDetailsViewModelProvider(second.id);
      final firstSubscription = container.listen(firstProvider, (_, _) {});
      final secondSubscription = container.listen(secondProvider, (_, _) {});
      addTearDown(firstSubscription.close);
      addTearDown(secondSubscription.close);
      await waitForDetailRequests(repository, 2);
      repository.detailRequests[0].add(
        ResultSuccess(first),
        revision: const TestDetailsRevision(1),
      );
      repository.detailRequests[1].add(
        ResultSuccess(second),
        revision: const TestDetailsRevision(1),
      );
      await pumpEventQueue();

      final start =
          container
                  .read(graphCommandCoordinatorProvider.notifier)
                  .acceptExisting(
                    ArchiveIntention(first.id),
                    presentationTitle: first.title,
                  )
              as IntentionCommandAccepted;
      repository.completeCommand(
        0,
        testDetailsSavedResult(
          first,
          revision: const TestDetailsRevision(3),
          additionalChanges: [
            IntentionRelationCountsChanged(
              revision: const TestDetailsRevision(3),
              intentionId: first.id,
              counts: testRelationCounts(),
            ),
            IntentionRelationCountsChanged(
              revision: const TestDetailsRevision(3),
              intentionId: second.id,
              counts: testRelationCounts(activeNeedOutgoing: 2),
            ),
          ],
        ),
      );
      await start.future;
      await waitForDetailRequests(repository, 4);

      repository.detailRequests[2].add(
        ResultSuccess(testDetailsIntention(index: 71, title: 'Устаревшее 1')),
        revision: const TestDetailsRevision(2),
      );
      repository.detailRequests[3].add(
        ResultSuccess(testDetailsIntention(index: 72, title: 'Устаревшее 2')),
        revision: const TestDetailsRevision(2),
      );
      await pumpEventQueue();
      expect(
        (container.read(
          firstProvider,
        ) as IntentionDetailsLoaded).intention.title,
        first.title,
      );
      expect(
        (container.read(
          secondProvider,
        ) as IntentionDetailsLoaded).intention.title,
        second.title,
      );

      repository.detailRequests[2].add(
        ResultSuccess(first),
        revision: const TestDetailsRevision(3),
        relationCounts: testRelationCounts(activeNeedOutgoing: 1),
      );
      repository.detailRequests[3].add(
        ResultSuccess(second),
        revision: const TestDetailsRevision(3),
        relationCounts: testRelationCounts(activeNeedOutgoing: 2),
      );
      await pumpEventQueue();
      expect(
        (container.read(
          firstProvider,
        ) as IntentionDetailsLoaded).details.activeRelationCount,
        1,
      );
      expect(
        (container.read(
          secondProvider,
        ) as IntentionDetailsLoaded).details.activeRelationCount,
        2,
      );
    },
  );

  test(
    'повторно открытый details ждёт сводку после completion до первого чтения',
    () async {
      final repository = ControlledDetailsRepository();
      final container = _detailsContainer(repository);
      addTearDown(container.dispose);
      final before = testDetailsIntention(index: 64, title: 'Прежнее');
      final saved = testDetailsIntention(index: 64, title: 'Сохранённое');
      final start = container
          .read(graphCommandCoordinatorProvider.notifier)
          .acceptExisting(
            UpdateIntention(
              id: before.id,
              title: saved.title,
              description: saved.description,
            ),
            presentationTitle: before.title,
          );
      expect(start, isA<IntentionCommandAccepted>());
      repository.onWatchIntention = (id) {
        repository.onWatchIntention = null;
        repository.completeCommand(
          0,
          testDetailsSavedResult(saved, before: before),
        );
      };

      final subscription = container.listen(
        intentionDetailsViewModelProvider(before.id),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await (start as IntentionCommandAccepted).future;
      await waitForDetailRequests(repository, 2);

      expect(
        container.read(intentionDetailsViewModelProvider(before.id)),
        isA<IntentionDetailsLoading>(),
      );

      repository.detailRequests[1].add(ResultSuccess(saved));
      await pumpEventQueue();

      expect(
        container.read(intentionDetailsViewModelProvider(before.id)),
        isA<IntentionDetailsLoaded>().having(
          (state) => state.intention.title,
          'подтверждённое намерение',
          saved.title,
        ),
      );
    },
  );

  test('отказ изменения сохраняет последний подтверждённый снимок', () async {
    final repository = ControlledDetailsRepository();
    final container = _detailsContainer(repository);
    addTearDown(container.dispose);
    final intention = testDetailsIntention(index: 62);
    final subscription = container.listen(
      intentionDetailsViewModelProvider(intention.id),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await waitForDetailRequests(repository, 1);
    repository.detailRequests[0].add(ResultSuccess(intention));
    await pumpEventQueue();

    final start = container
        .read(graphCommandCoordinatorProvider.notifier)
        .acceptExisting(
          DeleteIntention(intention.id),
          presentationTitle: intention.title,
        );
    repository.completeCommand(
      0,
      const ResultFailure(IntentionUnavailableFailure()),
    );
    final completion = await (start as IntentionCommandAccepted).future;
    expect(completion.confirmedChange, isNull);
    await pumpEventQueue();

    expect(
      container.read(intentionDetailsViewModelProvider(intention.id)),
      isA<IntentionDetailsLoaded>().having(
        (state) => state.intention.title,
        'последний подтверждённый snapshot',
        intention.title,
      ),
    );
  });

  test(
    'IntentionDeleted завершает details и отбрасывает прежний snapshot',
    () async {
      final repository = ControlledDetailsRepository();
      final container = _detailsContainer(repository);
      addTearDown(container.dispose);
      final intention = testDetailsIntention(index: 63);
      final subscription = container.listen(
        intentionDetailsViewModelProvider(intention.id),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await waitForDetailRequests(repository, 1);
      repository.detailRequests[0].add(ResultSuccess(intention));
      await pumpEventQueue();

      final coordinator = container.read(
        graphCommandCoordinatorProvider.notifier,
      );
      final presenter = coordinator.registerAppPresentation();

      container
          .read(intentionDetailsViewModelProvider(intention.id).notifier)
          .delete();
      repository.completeCommand(0, testDetailsDeletedResult(intention));
      await pumpEventQueue();

      expect(
        container.read(intentionDetailsViewModelProvider(intention.id)),
        isA<IntentionDetailsDeleted>(),
      );
      final deleteClaim = await presenter.nextClaim();
      expect(
        deleteClaim!.completions.single,
        isA<IntentionCommandCompletion>().having(
          (completion) => completion.result,
          'результат',
          isA<ResultSuccess<IntentionCommandSuccess>>(),
        ),
      );
      coordinator.confirmAppPresentation(
        deleteClaim,
        deleteClaim.completions.map((completion) => completion.token),
      );
      expect(repository.detailRequests[0].cancellationCount, 1);

      repository.detailRequests[0].add(ResultSuccess(intention));
      await pumpEventQueue();
      expect(
        container.read(intentionDetailsViewModelProvider(intention.id)),
        isA<IntentionDetailsDeleted>(),
      );
    },
  );
}

ProviderContainer _detailsContainer(ControlledDetailsRepository repository) {
  repository.shareSecondWatch = false;
  return ProviderContainer(
    overrides: [personalGraphRepositoryProvider.overrideWithValue(repository)],
    retry: (retryCount, error) => null,
  );
}
