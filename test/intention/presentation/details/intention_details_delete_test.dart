import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
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
        expect(find.text(intention.title), findsOneWidget);
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
      final scenarios = <(IntentionFailure, String, bool)>[
        (
          const IntentionNotFoundFailure(),
          'The intention no longer exists. It wasn’t deleted.',
          false,
        ),
        (
          const IntentionConflictFailure(),
          'The intention is still linked and can’t be deleted.',
          false,
        ),
        (
          const IntentionUnavailableFailure(),
          'The intention couldn’t be deleted. Try again.',
          true,
        ),
        (
          const IntentionCorruptionFailure(),
          'Stored data is damaged. The intention wasn’t deleted.',
          false,
        ),
        (
          const IntentionUnexpectedFailure(),
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

        final (failure, message, canRetry) = scenarios[index];
        repository.completeCommand(0, ResultFailure(failure));
        await tester.pumpAndSettle();

        expect(find.text(message), findsOneWidget);
        expect(find.text(intention.title), findsOneWidget);
        final retry = find.byKey(
          const ValueKey('intention-details-state-change-retry'),
        );
        expect(retry, canRetry ? findsOneWidget : findsNothing);
        if (canRetry) {
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
      final scenarios = <(IntentionFailure, bool)>[
        (const IntentionNotFoundFailure(), false),
        (const IntentionConflictFailure(), false),
        (const IntentionUnavailableFailure(), true),
        (const IntentionCorruptionFailure(), false),
        (const IntentionUnexpectedFailure(), false),
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
        final fallbackClaims =
            <Future<IntentionCatalogFallbackPresentationClaim?>>[];
        final coordinator = container.read(
          graphCommandCoordinatorProvider.notifier,
        );
        final coordinatorSubscription = coordinator.completions.listen((
          completion,
        ) {
          tokens.add(completion.token);
          fallbackClaims.add(
            coordinator.claimCatalogFallback(completion.token),
          );
        });

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

        final (failure, canRetry) = scenarios[index];
        repository.completeCommand(0, ResultFailure(failure));
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
        expect(await Future.wait(fallbackClaims), everyElement(isNull));

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
}

Future<void> _pumpDetailsPage(
  WidgetTester tester,
  ControlledDetailsRepository repository,
  IntentionId intentionId,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
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
