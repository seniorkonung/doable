import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/design_system/doable_theme.dart';
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
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/presentation/neighborhood/relation_neighborhood_paging_policy.dart';
import 'package:doable/src/design_system/components/page_head.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/app_root_pages.dart';
import '../../../support/ordinary_page_test_app.dart';
import 'details_test_support.dart';

import '../../../support/in_memory_quick_creation_mode_store.dart';

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
        await tester.pump();
        await tester.tap(delete);
        await tester.pumpAndSettle();

        expect(find.text('Delete intention permanently?'), findsOneWidget);
        expect(
          find.text(
            'This can’t be undone. The intention, its description, and all its tag assignments, including those not shown here, will be permanently deleted. The tags will remain.',
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
        expect(
          find.widgetWithText(PageHead, intention.title, skipOffstage: false),
          findsOneWidget,
        );
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
    'отдаёт отказы удаления общей поверхности, а повтор — новое удаление',
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
        await tester.pump();
        await tester.tap(delete);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('intention-details-confirm-delete')),
        );
        await tester.pump();

        final (failureFor, message, retries) = scenarios[index];
        repository.completeCommand(0, ResultFailure(failureFor(intention.id)));
        await tester.pumpAndSettle();

        expect(find.textContaining(message), findsOneWidget);
        expect(
          find.text('Delete — “${intention.title}”: $message'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(PageHead, intention.title, skipOffstage: false),
          findsOneWidget,
        );
        if (retries) {
          await _closeOperationMessage(tester);
          await tester.ensureVisible(delete);
          await tester.pump();
          await tester.tap(delete);
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('intention-details-confirm-delete')),
          );
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
            theme: doableTheme(Brightness.light),
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
      await openIntentionGraph(tester, content: find.text(intention.title));
      await tester.tap(find.text(intention.title));
      await tester.pump();
      await waitForDetailRequests(repository, 1);
      repository.detailRequests[0].add(ResultSuccess(intention));
      await tester.pumpAndSettle();

      final delete = find.byKey(const ValueKey('intention-details-delete'));
      await tester.ensureVisible(delete);
      await tester.pump();
      await tester.tap(delete);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('intention-details-confirm-delete')),
      );
      await tester.pump();

      await tester.tap(find.bySemanticsLabel('Back'));
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

      expectIntentionGraphRootPage(router);
      expect(
        find.text(
          'Delete — “Удаляемое после ухода намерение”: Intention deleted.',
        ),
        findsOneWidget,
      );
      expect(find.text(intention.title), findsNothing);
    },
  );
  testWidgets('конфликт удаления сохраняет текст отказа без перехода к связям', (
    tester,
  ) async {
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
    await tester.pump();
    await tester.tap(delete);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('intention-details-confirm-delete')),
    );
    await tester.pump();
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pump();
    expect(find.text(intention.title).hitTestable(), findsOneWidget);
    repository.completeCommand(
      0,
      ResultFailure(IntentionHasBlockingRelationsFailure(intention.id)),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining(
        'The intention wasn’t deleted: its relations still block deletion. '
        'Archived relations and relations that aren’t loaded yet block it too.',
      ),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(PageHead, intention.title, skipOffstage: false),
      findsOneWidget,
    );
    // На обзоре числа доступны без создания соседства.
    expect(find.text('0'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Relations: 0 active, 1 archived'),
      findsOneWidget,
    );

    expect(find.text('Show blocking relations'), findsNothing);
    expect(find.text(intention.title).hitTestable(), findsOneWidget);
    expect(repository.relationGroupQueries, isEmpty);
  });

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

      await tester.tap(find.text('Relations'));
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
      await tester.tap(find.text('Overview'));
      await tester.pumpAndSettle();
      final delete = find.byKey(const ValueKey('intention-details-delete'));
      await tester.ensureVisible(delete);
      await tester.pump();
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
        find.textContaining(
          'The intention wasn’t deleted: its relations still block deletion. '
          'Archived relations and relations that aren’t loaded yet block it too.',
        ),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(PageHead, intention.title, skipOffstage: false),
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
        inMemoryQuickCreationModeOverride,
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
        inMemoryQuickCreationModeOverride,
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
      retry: (retryCount, error) => null,
    );

Widget _localizedApp(Widget home) => OrdinaryPageTestApp(
  locale: const Locale('en'),
  builder: (context, child) =>
      GraphOperationPresenter(child: child ?? const SizedBox.shrink()),
  home: home,
);

Future<void> _closeOperationMessage(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

final class _DeleteTestRevision implements GraphRevision {
  const _DeleteTestRevision();

  @override
  GraphRevisionOrder compareTo(GraphRevision other) =>
      other is _DeleteTestRevision
      ? GraphRevisionOrder.same
      : GraphRevisionOrder.differentEpoch;
}
