import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/presentation/graph_operation_presenter.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/details/intention_details_state.dart';
import 'package:doable/src/intention/presentation/details/intention_details_view_model.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/presentation/neighborhood/relation_neighborhood_paging_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'details_test_support.dart';

void main() {
  setUp(() {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  testWidgets(
    'удаляет активное и архивированное намерение только после подтверждения',
    (tester) async {
      for (final archiveState in IntentionArchiveState.values) {
        final repository = ControlledDetailsRepository();
        final intention = testDetailsIntention(
          index: 120 + archiveState.index,
          archiveState: archiveState,
        );
        await _pumpDetailsPage(tester, repository, intention.id);
        await waitForDetailRequests(repository, 1);
        repository.detailRequests[0].add(ResultSuccess(intention));
        await tester.pumpAndSettle();

        final delete = find.byKey(const ValueKey('intention-details-delete'));
        await tester.ensureVisible(delete);
        await tester.tap(delete);
        await tester.pumpAndSettle();

        expect(find.text('Delete intention permanently?'), findsOneWidget);
        expect(
          find.text(
            'This can’t be undone. The intention and its description will be permanently deleted.',
          ),
          findsOneWidget,
        );
        await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
        await tester.pumpAndSettle();
        expect(repository.commands, isEmpty);

        await tester.tap(delete);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('intention-details-confirm-delete')),
        );
        await tester.pump();

        expect(repository.commands.single, isA<DeleteIntention>());
        expect(find.text(intention.title, skipOffstage: false), findsOneWidget);
        expect(find.text('Saving changes…'), findsOneWidget);

        repository.completeCommand(
          0,
          const ResultFailure(IntentionUnavailableFailure()),
        );
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
  );

  testWidgets(
    'безопасно показывает отказы удаления и повторяет только недоступный',
    (tester) async {
      final scenarios = <(IntentionFailure Function(IntentionId), String, bool)>[
        (
          (_) => const IntentionNotFoundFailure(),
          'The intention no longer exists. It wasn’t deleted.',
          false,
        ),
        (
          IntentionHasBlockingRelationsFailure.new,
          'The intention wasn’t deleted: its relations still block deletion. '
              'Archived relations and relations that aren’t loaded yet block '
              'it too.',
          false,
        ),
        (
          (_) => const IntentionUnavailableFailure(),
          'The intention couldn’t be deleted. Try again.',
          true,
        ),
        (
          (_) => const IntentionCorruptionFailure(),
          'Stored data is damaged. The intention wasn’t deleted.',
          false,
        ),
        (
          (_) => const IntentionUnexpectedFailure(),
          'The intention couldn’t be deleted because of an unexpected error.',
          false,
        ),
      ];

      for (var index = 0; index < scenarios.length; index += 1) {
        final repository = ControlledDetailsRepository();
        final intention = testDetailsIntention(index: 130 + index);
        await _pumpDetailsPage(tester, repository, intention.id);
        await waitForDetailRequests(repository, 1);
        repository.detailRequests[0].add(ResultSuccess(intention));
        await tester.pumpAndSettle();

        final delete = find.byKey(const ValueKey('intention-details-delete'));
        await tester.ensureVisible(delete);
        await tester.tap(delete);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('intention-details-confirm-delete')),
        );
        await tester.pump();

        final (failureFor, message, canRetry) = scenarios[index];
        repository.completeCommand(0, ResultFailure(failureFor(intention.id)));
        await tester.pumpAndSettle();

        expect(find.text(message), findsOneWidget);
        expect(find.text(intention.title, skipOffstage: false), findsOneWidget);
        final retry = find.byKey(
          const ValueKey('intention-details-state-change-retry'),
        );
        expect(retry, canRetry ? findsOneWidget : findsNothing);
        if (canRetry) {
          await tester.ensureVisible(retry);
          await tester.drag(find.byType(Scrollable), const Offset(0, 100));
          await tester.pumpAndSettle();
          await tester.tap(retry);
          await tester.pump();
          expect(repository.commands, hasLength(2));
          expect(repository.commands.last, isA<DeleteIntention>());
          repository.completeCommand(
            1,
            const ResultFailure(IntentionUnexpectedFailure()),
          );
          await tester.pumpAndSettle();
        }

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
  );

  test(
    'failure сохраняет снимок, а успешный retry не оставляет прежнюю ошибку',
    () async {
      final scenarios = <(IntentionFailure Function(IntentionId), bool)>[
        ((_) => const IntentionNotFoundFailure(), false),
        (IntentionHasBlockingRelationsFailure.new, false),
        ((_) => const IntentionUnavailableFailure(), true),
        ((_) => const IntentionCorruptionFailure(), false),
        ((_) => const IntentionUnexpectedFailure(), false),
      ];

      for (var index = 0; index < scenarios.length; index += 1) {
        final repository = ControlledDetailsRepository();
        final container = _detailsContainer(repository);
        final intention = testDetailsIntention(
          index: 140 + index,
          archiveState: index.isEven
              ? IntentionArchiveState.active
              : IntentionArchiveState.archived,
        );
        final provider = intentionDetailsViewModelProvider(intention.id);
        final subscription = container.listen(
          provider,
          (_, _) {},
          fireImmediately: true,
        );
        await waitForDetailRequests(repository, 1);
        repository.detailRequests[0].add(ResultSuccess(intention));
        await pumpEventQueue();

        final tokens = <IntentionOperationToken>[];
        final coordinator = container.read(
          graphCommandCoordinatorProvider.notifier,
        );
        final presenter = coordinator.registerAppPresentation();
        final coordinatorSubscription = coordinator.intentionCompletions.listen(
          (completion) {
            tokens.add(completion.token);
          },
        );

        final details = container.read(provider.notifier)..delete();
        details.delete();
        expect(repository.commands, hasLength(1));
        expect(repository.commands.single, isA<DeleteIntention>());
        expect(
          container.read(provider),
          isA<IntentionDetailsLoaded>()
              .having(
                (state) => state.intention,
                'последний подтверждённый снимок',
                same(intention),
              )
              .having(
                (state) => state.stateChange?.kind,
                'вид операции',
                IntentionDetailsStateChangeKind.delete,
              )
              .having(
                (state) => state.isOperationRunning,
                'общий барьер',
                isTrue,
              ),
        );

        final (failureFor, canRetry) = scenarios[index];
        repository.completeCommand(0, ResultFailure(failureFor(intention.id)));
        await pumpEventQueue();

        expect(
          container.read(provider),
          isA<IntentionDetailsLoaded>()
              .having(
                (state) => state.intention,
                'снимок после отказа',
                same(intention),
              )
              .having(
                (state) => state.stateChange?.canRetry,
                'доступность обычного повтора',
                canRetry,
              )
              .having(
                (state) => state.isOperationRunning,
                'освобождённый барьер',
                isFalse,
              ),
        );

        final shownFailure = (container.read(
          provider,
        ) as IntentionDetailsLoaded).stateChange!.failurePresentation;
        expect(shownFailure, isA<GraphInitiatorPresentationClaim>());
        coordinator.confirmPresentation(shownFailure!);

        details.retryStateChange();
        expect(repository.commands, hasLength(canRetry ? 2 : 1));
        if (canRetry) {
          expect(repository.commands.last, isA<DeleteIntention>());
          repository.completeCommand(1, testDetailsDeletedResult(intention));
          await pumpEventQueue();
          expect(container.read(provider), isA<IntentionDetailsDeleted>());
        }

        expect(tokens, hasLength(canRetry ? 2 : 1));
        if (canRetry) {
          expect(identical(tokens.first, tokens.last), isFalse);
        }
        if (canRetry) {
          final successClaim = await presenter.nextClaim();
          expect(successClaim!.token, same(tokens.last));
          coordinator.confirmPresentation(successClaim);
        }
        GraphAppPresentationClaim? staleFailure;
        unawaited(presenter.nextClaim().then((claim) => staleFailure = claim));
        await pumpEventQueue();
        expect(staleFailure, isNull);

        await coordinatorSubscription.cancel();
        subscription.close();
        container.dispose();
      }
    },
  );

  testWidgets('после Back оболочка становится fallback-владельцем удаления', (
    tester,
  ) async {
    final repository = ControlledDetailsRepository();
    final intention = testDetailsIntention(
      index: 72,
      title: 'Удаляемое намерение',
    );
    repository.catalogResult = ResultSuccess(
      IntentionCatalogFirstPage(
        items: [testDetailsSummary(intention)],
        totalCount: 1,
        nextCursor: null,
        revision: const _DeleteTestRevision(),
      ),
    );
    final router = AppRouter();
    final container = _detailsContainer(repository);
    addTearDown(router.dispose);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router.config(),
          builder: (context, child) =>
              GraphOperationPresenter(child: child ?? const SizedBox.shrink()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(intention.title));
    await tester.pump();
    await waitForDetailRequests(repository, 1);
    repository.detailRequests[0].add(ResultSuccess(intention));
    await tester.pumpAndSettle();

    final delete = find.byKey(const ValueKey('intention-details-delete'));
    await tester.ensureVisible(delete);
    await tester.tap(delete);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('intention-details-confirm-delete')),
    );
    await tester.pump();
    expect(repository.commands.single, isA<DeleteIntention>());

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(router.current.name, IntentionCatalogRoute.name);

    repository.completeCommand(
      0,
      const ResultFailure(IntentionUnavailableFailure()),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Delete — “Удаляемое намерение”: The intention couldn’t be deleted. Try again.',
      ),
      findsOneWidget,
    );
    expect(find.text(intention.title), findsOneWidget);
  });

  testWidgets(
    'успешное удаление после Back предъявляется оболочкой и обновляет каталог',
    (tester) async {
      final repository = ControlledDetailsRepository();
      final intention = testDetailsIntention(
        index: 73,
        title: 'Удаляемое после ухода намерение',
      );
      repository.catalogResult = ResultSuccess(
        IntentionCatalogFirstPage(
          items: [testDetailsSummary(intention)],
          totalCount: 1,
          nextCursor: null,
          revision: const _DeleteTestRevision(),
        ),
      );
      final router = AppRouter();
      final container = _detailsContainer(repository);
      addTearDown(router.dispose);
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router.config(),
            builder: (context, child) => GraphOperationPresenter(
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(intention.title));
      await tester.pump();
      await waitForDetailRequests(repository, 1);
      repository.detailRequests[0].add(ResultSuccess(intention));
      await tester.pumpAndSettle();

      final delete = find.byKey(const ValueKey('intention-details-delete'));
      await tester.ensureVisible(delete);
      await tester.tap(delete);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('intention-details-confirm-delete')),
      );
      await tester.pump();

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      repository.catalogResult = ResultSuccess(
        IntentionCatalogFirstPage(
          items: const [],
          totalCount: 0,
          nextCursor: null,
          revision: const _DeleteTestRevision(),
        ),
      );
      repository.completeCommand(0, testDetailsDeletedResult(intention));
      await tester.pumpAndSettle();

      expect(router.current.name, IntentionCatalogRoute.name);
      expect(
        find.text(
          'Delete — “Удаляемое после ухода намерение”: Intention deleted.',
        ),
        findsOneWidget,
      );
      expect(find.text(intention.title), findsNothing);
    },
  );
  testWidgets(
    'конфликт удаления сохраняет намерение и открывает блокирующие группы',
    (tester) async {
      final repository = ControlledDetailsRepository();
      final intention = testDetailsIntention(index: 160);
      // Свободных активных связей нет: удаление блокирует только архив.
      final counts = testRelationCounts(archivedCanIncoming: 1);
      repository.onRelationGroupPage = (query) => GraphResultSuccess(
        RelationGroupFirstPage(
          items: query.scope == RelationScope.archived
              ? [
                  testDetailsRelationRow(
                    ownerId: intention.id,
                    index: 1,
                    type: LongTermRelationType.can,
                    direction: RelationDirection.incoming,
                    scope: RelationScope.archived,
                  ),
                ]
              : const [],
          counts: counts,
          nextCursor: null,
          revision: const TestDetailsRevision(0),
        ),
      );
      await _pumpDetailsPage(tester, repository, intention.id);
      await waitForDetailRequests(repository, 1);
      repository.detailRequests[0].add(
        ResultSuccess(intention),
        relationCounts: counts,
      );
      await tester.pumpAndSettle();

      final delete = find.byKey(const ValueKey('intention-details-delete'));
      await tester.ensureVisible(delete);
      await tester.tap(delete);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('intention-details-confirm-delete')),
      );
      await tester.pump();
      repository.completeCommand(
        0,
        ResultFailure(IntentionHasBlockingRelationsFailure(intention.id)),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'The intention wasn’t deleted: its relations still block deletion. '
          'Archived relations and relations that aren’t loaded yet block it too.',
        ),
        findsOneWidget,
      );
      expect(find.text(intention.title, skipOffstage: false), findsOneWidget);
      expect(
        find.byKey(const ValueKey('intention-details-state-change-retry')),
        findsNothing,
      );
      // Ноль активных связей не объявляет намерение свободным от зависимостей.
      expect(
        find.text('Active relations: 0', skipOffstage: false),
        findsWidgets,
      );
      expect(
        find.text('Total relations: 1', skipOffstage: false),
        findsOneWidget,
      );

      final showBlocking = find.byKey(
        const ValueKey('intention-details-show-blocking-relations'),
      );
      await tester.ensureVisible(showBlocking);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 100));
      await tester.pumpAndSettle();
      await tester.tap(showBlocking);
      await tester.pumpAndSettle();

      final reveal = repository.relationGroupQueries.last;
      expect(reveal.scope, RelationScope.archived);
      expect(reveal.type, LongTermRelationType.can);
      expect(reveal.direction, RelationDirection.incoming);
      expect(reveal.cursor, isNull);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'To Исходное 1, you can Намерение-владелец',
          skipOffstage: false,
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'незагруженные связи и отказ их чтения не снимают блокировку удаления',
    (tester) async {
      final repository = ControlledDetailsRepository();
      final intention = testDetailsIntention(index: 161);
      final counts = testRelationCounts(activeNeedOutgoing: 250);
      var continuationReads = 0;
      repository.onRelationGroupPage = (query) {
        if (query.cursor != null) {
          continuationReads += 1;
          return const GraphResultFailure(RelationGroupUnavailableFailure());
        }
        return GraphResultSuccess(
          RelationGroupFirstPage(
            items: [
              testDetailsRelationRow(ownerId: intention.id, index: 1),
              testDetailsRelationRow(ownerId: intention.id, index: 2),
            ],
            counts: counts,
            nextCursor: const _DeleteTestCursor(),
            revision: const TestDetailsRevision(0),
          ),
        );
      };
      await _pumpDetailsPage(
        tester,
        repository,
        intention.id,
        pagingPolicy: RelationNeighborhoodPagingPolicy(
          pageSize: 2,
          prefetchRemaining: 0,
        ),
      );
      await waitForDetailRequests(repository, 1);
      repository.detailRequests[0].add(
        ResultSuccess(intention),
        relationCounts: counts,
      );
      await tester.pumpAndSettle();

      // Полное количество группы не подменяется числом загруженных строк.
      expect(
        find.text('In the whole selected group: 250', skipOffstage: false),
        findsOneWidget,
      );

      // Продолжение группы запрашивается только при показе её конца.
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(continuationReads, greaterThan(0));
      expect(
        find.text(
          'The next relations couldn’t be loaded.',
          skipOffstage: false,
        ),
        findsOneWidget,
      );

      await tester.drag(find.byType(CustomScrollView), const Offset(0, 2000));
      await tester.pumpAndSettle();
      final delete = find.byKey(const ValueKey('intention-details-delete'));
      await tester.ensureVisible(delete);
      await tester.tap(delete);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('intention-details-confirm-delete')),
      );
      await tester.pump();
      repository.completeCommand(
        0,
        ResultFailure(IntentionHasBlockingRelationsFailure(intention.id)),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'The intention wasn’t deleted: its relations still block deletion. '
          'Archived relations and relations that aren’t loaded yet block it too.',
        ),
        findsOneWidget,
      );
      expect(find.text(intention.title, skipOffstage: false), findsOneWidget);

      final showBlocking = find.byKey(
        const ValueKey('intention-details-show-blocking-relations'),
      );
      await tester.ensureVisible(showBlocking);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 100));
      await tester.pumpAndSettle();
      await tester.tap(showBlocking);
      await tester.pumpAndSettle();

      expect(
        find.text('In the whole selected group: 250', skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.text(
          'The intention wasn’t deleted: its relations still block deletion. '
          'Archived relations and relations that aren’t loaded yet block it too.',
          skipOffstage: false,
        ),
        findsOneWidget,
      );
    },
  );
}

final class _DeleteTestCursor implements RelationGroupCursor {
  const _DeleteTestCursor();
}

Future<void> _pumpDetailsPage(
  WidgetTester tester,
  ControlledDetailsRepository repository,
  IntentionId intentionId, {
  RelationNeighborhoodPagingPolicy? pagingPolicy,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
        if (pagingPolicy case final policy?)
          relationNeighborhoodPagingPolicyProvider.overrideWithValue(policy),
      ],
      retry: (retryCount, error) => null,
      child: _localizedApp(IntentionDetailsPage(intentionId: intentionId)),
    ),
  );
  await tester.pump();
}

ProviderContainer _detailsContainer(ControlledDetailsRepository repository) =>
    ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
      retry: (retryCount, error) => null,
    );

Widget _localizedApp(Widget home) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

final class _DeleteTestRevision implements GraphRevision {
  const _DeleteTestRevision();

  @override
  GraphRevisionOrder compareTo(GraphRevision other) =>
      other is _DeleteTestRevision
      ? GraphRevisionOrder.same
      : GraphRevisionOrder.differentEpoch;
}
