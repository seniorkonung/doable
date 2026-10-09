import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/daily_choice/application/daily_choice_catalog.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/presentation/details/daily_choice_details_page.dart';
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
import 'package:doable/src/intention/domain/intention_text.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/presentation/neighborhood/blocking_relations_selection_view_model.dart';
import 'package:doable/src/long_term_relation/presentation/neighborhood/relation_neighborhood_sliver.dart';
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

  testWidgets('дневная зависимость намерения открывает свой полный путь', (
    tester,
  ) async {
    final repository = ControlledDetailsRepository();
    repository.catalogResult = ResultSuccess(
      IntentionCatalogFirstPage(
        items: const [],
        totalCount: 0,
        nextCursor: null,
        revision: const TestDetailsRevision(0),
      ),
    );
    final intention = testDetailsIntention(index: 120, title: 'Основание');
    final action = testDetailsIntention(index: 121, title: 'Действие');
    final choiceId = (DailyChoiceId.decode(
      '00000000-0000-4000-8000-000000000120',
    ) as DailyChoiceIdDecodingSuccess).id;
    final counts = testRelationCounts(dailySource: 1);
    repository.onRelationGroupPage = (_) => GraphResultSuccess(
      RelationGroupFirstPage(
        items: const [],
        counts: counts,
        nextCursor: null,
        revision: const TestDetailsRevision(0),
      ),
    );
    repository.onDailyChoiceGroupPage = (_) => GraphResultSuccess(
      DailyChoiceGroupFirstPage(
        items: [
          DailyChoiceCatalogItem(
            id: choiceId,
            source: DailyChoiceCatalogParticipant(
              id: intention.id,
              title: intention.title,
              archiveState: IntentionArchiveState.active,
              readiness: IntentionReadiness.notReady,
            ),
            selected: DailyChoiceCatalogParticipant(
              id: action.id,
              title: action.title,
              archiveState: IntentionArchiveState.active,
              readiness: IntentionReadiness.ready,
            ),
            date: CalendarDate.fromParts(2026, 9, 24),
            isCompleted: false,
          ),
        ],
        counts: counts,
        nextCursor: null,
        revision: const TestDetailsRevision(0),
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
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router.config(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await openIntentionGraph(tester);
    unawaited(router.push(IntentionDetailsRoute(intentionId: intention.id)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await waitForDetailRequests(repository, 1);
    repository.detailRequests[0].add(
      ResultSuccess(intention),
      relationCounts: counts,
    );
    await tester.pumpAndSettle();
    final dailyGroup = find.byKey(
      const ValueKey('relation-neighborhood-daily-source'),
    );
    await tester.scrollUntilVisible(
      dailyGroup,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(dailyGroup);
    await tester.pumpAndSettle();
    expect(
      repository.dailyChoiceGroupQueries.single.role,
      DailyChoiceRelationRole.source,
    );
    final row = find.byKey(
      ValueKey(
        'relation-neighborhood-daily-row-${choiceId.toCanonicalString()}',
      ),
    );
    await Scrollable.ensureVisible(tester.element(row), alignment: 0.3);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(router.current.name, DailyChoiceDetailsRoute.name);
    expect(find.byType(DailyChoiceDetailsPage), findsOneWidget);
  });

  testWidgets(
    'конфликт удаления открывает выбор блокирующих связей в соседстве',
    (tester) async {
      final repository = ControlledDetailsRepository();
      final intention = testDetailsIntention(index: 101, title: 'Намерение');
      final counts = testRelationCounts(activeNeedOutgoing: 1);
      final relation = testDetailsRelationRow(ownerId: intention.id, index: 1);
      repository.onRelationGroupPage = (query) => GraphResultSuccess(
        RelationGroupFirstPage(
          items: [relation],
          counts: counts,
          nextCursor: null,
          revision: const TestDetailsRevision(0),
        ),
      );
      await _pumpDetailsPage(tester, repository, intention.id);
      await waitForDetailRequests(repository, 1);
      repository.detailRequests.single.add(
        ResultSuccess(intention),
        relationCounts: counts,
      );
      await tester.pumpAndSettle();

      final delete = find.byKey(const ValueKey('intention-details-delete'));
      await tester.ensureVisible(delete);
      await tester.pumpAndSettle();
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

      final show = find.byKey(
        const ValueKey('intention-details-show-blocking-relations'),
      );
      await Scrollable.ensureVisible(tester.element(show), alignment: 0.3);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 180));
      await tester.pumpAndSettle();
      await tester.tap(show);
      await tester.pump();
      await tester.pump();
      expect(find.byType(RelationNeighborhoodSliver), findsOneWidget);
      expect(find.text('Selected relations: 0'), findsOneWidget);
      final row = find.byKey(
        ValueKey(
          'relation-neighborhood-select-${relation.relation.id.toCanonicalString()}',
        ),
      );
      await tester.scrollUntilVisible(
        row,
        300,
        scrollable: find.byType(Scrollable),
      );
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -250));
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(RelationNeighborhoodSliver)),
      );
      expect(
        container
            .read(blockingRelationsSelectionViewModelProvider(intention.id))
            .selected
            .keys,
        {relation.relation.id},
      );
      expect(repository.relationGroupQueries, hasLength(2));
      _expectNavigation(tester);
    },
  );

  test('маршрут подробного просмотра хранит предметный идентификатор', () {
    final id = testDetailsIntentionId(1);

    final route = IntentionDetailsRoute(intentionId: id);

    expect(route, isA<PageRouteInfo<IntentionDetailsRouteArgs>>());
    expect(route.args!.intentionId, same(id));
  });

  testWidgets('показывает загрузку и пользовательский текст без перевода', (
    tester,
  ) async {
    final repository = ControlledDetailsRepository();
    final intention = testDetailsIntention(
      title: 'Сохранить русский заголовок',
      description: '  Описание\nбез преобразования  ',
      readiness: IntentionReadiness.ready,
    );
    await _pumpDetailsPage(tester, repository, intention.id);
    await waitForDetailRequests(repository, 1);

    expect(find.text('Loading intention…'), findsOneWidget);
    _expectNavigation(tester);
    repository.detailRequests.single.add(ResultSuccess(intention));
    await tester.pump();

    expect(find.text('Сохранить русский заголовок'), findsOneWidget);
    expect(find.text('  Описание\nбез преобразования  '), findsOneWidget);
    expect(find.text('Ready for action'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    _expectNavigation(tester);
  });

  testWidgets('показывает архивное состояние и отсутствие описания', (
    tester,
  ) async {
    final repository = ControlledDetailsRepository();
    final intention = testDetailsIntention(
      index: 2,
      title: 'Архивное намерение',
      description: null,
      archiveState: IntentionArchiveState.archived,
    );
    await _pumpDetailsPage(tester, repository, intention.id);
    await waitForDetailRequests(repository, 1);

    repository.detailRequests.single.add(ResultSuccess(intention));
    await tester.pump();

    expect(find.text('Archived'), findsOneWidget);
    expect(find.text('No description'), findsOneWidget);
    expect(find.text('Not ready for action'), findsOneWidget);
  });

  testWidgets('смена локали не изменяет пользовательский текст', (
    tester,
  ) async {
    final repository = ControlledDetailsRepository();
    final locale = ValueNotifier(const Locale('en'));
    addTearDown(locale.dispose);
    final intention = testDetailsIntention(
      title: 'Сохранить русский заголовок',
      description: '  Пользовательское описание\nбез преобразования  ',
      readiness: IntentionReadiness.ready,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inMemoryQuickCreationModeOverride,
          personalGraphRepositoryProvider.overrideWithValue(repository),
        ],
        retry: (retryCount, error) => null,
        child: ValueListenableBuilder<Locale>(
          valueListenable: locale,
          builder: (context, value, child) => _localizedApp(
            IntentionDetailsPage(intentionId: intention.id),
            locale: value,
          ),
        ),
      ),
    );
    await tester.pump();
    await waitForDetailRequests(repository, 1);
    repository.detailRequests.single.add(ResultSuccess(intention));
    await tester.pumpAndSettle();

    expect(find.text('Intention details'), findsOneWidget);
    expect(find.text(intention.title), findsOneWidget);
    expect(find.text(intention.description!), findsOneWidget);

    locale.value = const Locale('ru');
    await tester.pumpAndSettle();

    expect(find.text('Подробности намерения'), findsOneWidget);
    expect(find.text('Intention details'), findsNothing);
    expect(find.text(intention.title), findsOneWidget);
    expect(find.text(intention.description!), findsOneWidget);
  });

  testWidgets(
    'подробный просмотр проходит accessibility guidelines при масштабе 200%',
    (tester) async {
      final semantics = tester.ensureSemantics();
      tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
      );
      final repository = ControlledDetailsRepository();
      final intention = testDetailsIntention(
        title: 'Доступное намерение',
        description: 'Описание доступного намерения',
        readiness: IntentionReadiness.ready,
        archiveState: IntentionArchiveState.archived,
      );
      await _pumpDetailsPage(tester, repository, intention.id);
      await waitForDetailRequests(repository, 1);
      repository.detailRequests.single.add(ResultSuccess(intention));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('intention-details-delete')),
        200,
        scrollable: _detailsScrollable,
      );
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantics.dispose();
    },
  );

  testWidgets(
    'объясняет оба критерия готовности и не запускает команду после отмены',
    (tester) async {
      final repository = ControlledDetailsRepository();
      final before = testDetailsIntention(index: 20);
      final saved = testDetailsIntention(
        index: 20,
        readiness: IntentionReadiness.ready,
      );
      await _pumpDetailsPage(tester, repository, before.id);
      await waitForDetailRequests(repository, 1);
      repository.detailRequests[0].add(ResultSuccess(before));
      await tester.pumpAndSettle();

      final enableReadiness = find.byKey(
        const ValueKey('intention-details-enable-readiness'),
      );
      await tester.ensureVisible(enableReadiness);
      await tester.tap(enableReadiness);
      await tester.pumpAndSettle();

      expect(find.text('Ready for action?'), findsOneWidget);
      expect(
        find.text('It can be completed fully within one day.'),
        findsOneWidget,
      );
      expect(
        find.text('It is clear enough for a person to carry out.'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(repository.commands, isEmpty);
      expect(
        find.text('Not ready for action', skipOffstage: false),
        findsOneWidget,
      );

      await tester.tap(enableReadiness);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Mark as ready'));
      await tester.pump();

      expect(repository.commands.single, isA<EnableIntentionReadiness>());
      expect(
        find.text('Not ready for action', skipOffstage: false),
        findsOneWidget,
      );
      expect(find.text('Saving changes…'), findsOneWidget);

      repository.completeCommand(
        0,
        testDetailsSavedResult(saved, before: before),
      );
      await tester.pump();
      await waitForDetailRequests(repository, 2);
      repository.detailRequests[1].add(ResultSuccess(saved));
      await tester.pump();
      await tester.pump();

      expect(
        find.textContaining('Marked as ready for action.'),
        findsOneWidget,
      );
      expect(
        find.text('Ready for action', skipOffstage: false),
        findsOneWidget,
      );
      repository.detailRequests[0].add(ResultSuccess(before));
      await tester.pump();
      expect(
        find.text('Ready for action', skipOffstage: false),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'явно выключает готовность, архивирует и восстанавливает намерение',
    (tester) async {
      final repository = ControlledDetailsRepository();
      final ready = testDetailsIntention(
        index: 21,
        readiness: IntentionReadiness.ready,
      );
      final notReady = testDetailsIntention(index: 21);
      final archived = testDetailsIntention(
        index: 21,
        archiveState: IntentionArchiveState.archived,
      );
      final restored = testDetailsIntention(index: 21);
      await _pumpDetailsPage(tester, repository, ready.id);
      await waitForDetailRequests(repository, 1);
      repository.detailRequests[0].add(ResultSuccess(ready));
      await tester.pumpAndSettle();

      final disableReadiness = find.byKey(
        const ValueKey('intention-details-disable-readiness'),
      );
      await tester.ensureVisible(disableReadiness);
      await tester.tap(disableReadiness);
      await tester.pump();
      expect(repository.commands[0], isA<DisableIntentionReadiness>());
      repository.completeCommand(
        0,
        testDetailsSavedResult(notReady, before: ready),
      );
      await tester.pump();
      await waitForDetailRequests(repository, 2);
      repository.detailRequests[1].add(ResultSuccess(notReady));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Marked as not ready for action.'),
        findsOneWidget,
      );
      await _closeOperationMessage(tester);

      final archive = find.byKey(const ValueKey('intention-details-archive'));
      await tester.ensureVisible(archive);
      await tester.pump();
      await tester.tap(archive);
      await tester.pump();
      expect(repository.commands[1], isA<ArchiveIntention>());
      repository.completeCommand(
        1,
        testDetailsSavedResult(archived, before: notReady),
      );
      await tester.pump();
      await waitForDetailRequests(repository, 3);
      repository.detailRequests[2].add(ResultSuccess(archived));
      await tester.pumpAndSettle();
      expect(find.textContaining('Intention archived.'), findsOneWidget);
      expect(find.text('Archived', skipOffstage: false), findsOneWidget);
      expect(
        find.text('Not ready for action', skipOffstage: false),
        findsOneWidget,
      );
      await _closeOperationMessage(tester);

      final restore = find.byKey(const ValueKey('intention-details-restore'));
      await tester.ensureVisible(restore);
      await tester.tap(restore);
      await tester.pump();
      expect(repository.commands[2], isA<RestoreIntention>());
      repository.completeCommand(
        2,
        testDetailsSavedResult(restored, before: archived),
      );
      await tester.pump();
      await waitForDetailRequests(repository, 4);
      repository.detailRequests[3].add(ResultSuccess(restored));
      await tester.pumpAndSettle();
      expect(find.textContaining('Intention restored.'), findsOneWidget);
      expect(find.text('Active', skipOffstage: false), findsOneWidget);
    },
  );

  testWidgets(
    'безопасно показывает отказы перехода и повторяет только недоступный',
    (tester) async {
      final scenarios = <(IntentionFailure, String, bool)>[
        (
          const IntentionNotFoundFailure(),
          'The intention no longer exists. Its state wasn’t changed.',
          false,
        ),
        (
          const IntentionUnavailableFailure(),
          'The intention state couldn’t be changed. Try again.',
          true,
        ),
        (
          const IntentionCorruptionFailure(),
          'Stored data is damaged. The intention state wasn’t changed.',
          false,
        ),
        (
          const IntentionUnexpectedFailure(),
          'The intention state couldn’t be changed because of an unexpected error.',
          false,
        ),
      ];

      for (var index = 0; index < scenarios.length; index += 1) {
        final repository = ControlledDetailsRepository();
        final intention = testDetailsIntention(index: 30 + index);
        await _pumpDetailsPage(tester, repository, intention.id);
        await waitForDetailRequests(repository, 1);
        repository.detailRequests[0].add(ResultSuccess(intention));
        await tester.pumpAndSettle();
        final archive = find.byKey(const ValueKey('intention-details-archive'));
        await tester.ensureVisible(archive);
        await tester.pump();
        await tester.tap(archive);
        await tester.pump();

        final (failure, message, canRetry) = scenarios[index];
        repository.completeCommand(0, ResultFailure(failure));
        await tester.pumpAndSettle();

        expect(find.text(message), findsOneWidget);
        expect(find.text('Active', skipOffstage: false), findsOneWidget);
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
    'объясняет каскад до архивирования и сохранённый архив после него',
    (tester) async {
      final repository = ControlledDetailsRepository();
      // Намерение в цикле: одна исходящая и одна входящая связь «нужно».
      final active = testDetailsIntention(index: 26);
      final archived = testDetailsIntention(
        index: 26,
        archiveState: IntentionArchiveState.archived,
      );
      final activeCounts = testRelationCounts(
        activeNeedIncoming: 1,
        activeNeedOutgoing: 1,
      );
      final archivedCounts = testRelationCounts(
        archivedNeedIncoming: 1,
        archivedNeedOutgoing: 1,
      );
      var counts = activeCounts;
      repository.onRelationGroupPage = (query) => GraphResultSuccess(
        RelationGroupFirstPage(
          items: query.scope == RelationScope.archived
              ? [
                  testDetailsRelationRow(
                    ownerId: active.id,
                    index: 1,
                    scope: RelationScope.archived,
                  ),
                ]
              : const [],
          counts: counts,
          nextCursor: null,
          revision: const TestDetailsRevision(0),
        ),
      );
      await _pumpDetailsPage(tester, repository, active.id);
      await waitForDetailRequests(repository, 1);
      repository.detailRequests[0].add(
        ResultSuccess(active),
        relationCounts: activeCounts,
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Archiving also archives the intention’s direct relations. '
          'Neighbouring intentions and their other relations stay unchanged.',
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('intention-details-restore-explanation')),
        findsNothing,
      );

      final archive = find.byKey(const ValueKey('intention-details-archive'));
      await tester.ensureVisible(archive);
      await tester.pump();
      await tester.tap(archive);
      await tester.pump();
      counts = archivedCounts;
      repository.completeCommand(
        0,
        testDetailsSavedResult(archived, before: active),
      );
      await tester.pump();
      await waitForDetailRequests(repository, 2);
      repository.detailRequests[1].add(
        ResultSuccess(archived),
        revision: const TestDetailsRevision(1),
        relationCounts: archivedCounts,
      );
      await tester.pumpAndSettle();
      await _closeOperationMessage(tester);

      // Восстановление не обещает обратного каскада.
      expect(
        find.text(
          'Restoring returns only the intention. '
          'Its relations stay archived: 2.',
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('intention-details-archive-explanation')),
        findsNothing,
      );

      // Архивное соседство доступно после каскада.
      final showArchived = find.byKey(
        const ValueKey('intention-details-show-archived-relations'),
      );
      await tester.ensureVisible(showArchived);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 100));
      await tester.pumpAndSettle();
      await tester.tap(showArchived);
      await tester.pumpAndSettle();

      expect(
        repository.relationGroupQueries.last.scope,
        RelationScope.archived,
      );
      expect(
        find.text('Archived relations: 2', skipOffstage: false),
        findsWidgets,
      );
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'To Намерение-владелец, you need Связанное 1',
          skipOffstage: false,
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'объясняет влияние связей на обоих языках и объявляет объяснение',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = ControlledDetailsRepository();
      final locale = ValueNotifier(const Locale('en'));
      addTearDown(locale.dispose);
      final archived = testDetailsIntention(
        index: 27,
        archiveState: IntentionArchiveState.archived,
      );
      final counts = testRelationCounts(archivedCanIncoming: 3);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inMemoryQuickCreationModeOverride,
            personalGraphRepositoryProvider.overrideWithValue(repository),
          ],
          retry: (retryCount, error) => null,
          child: ValueListenableBuilder<Locale>(
            valueListenable: locale,
            builder: (context, value, child) => _localizedApp(
              IntentionDetailsPage(intentionId: archived.id),
              locale: value,
            ),
          ),
        ),
      );
      await tester.pump();
      await waitForDetailRequests(repository, 1);
      repository.detailRequests.single.add(
        ResultSuccess(archived),
        relationCounts: counts,
      );
      await tester.pumpAndSettle();

      const explanationKey = ValueKey('intention-details-restore-explanation');
      expect(
        tester.getSemantics(find.byKey(explanationKey)),
        matchesSemantics(
          label:
              'Restoring returns only the intention. '
              'Its relations stay archived: 3.',
        ),
      );
      expect(
        find.widgetWithText(
          OutlinedButton,
          'Show archived relations',
          skipOffstage: false,
        ),
        findsOneWidget,
      );

      locale.value = const Locale('ru');
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.byKey(explanationKey)),
        matchesSemantics(
          label:
              'Восстановление возвращает только само намерение. '
              'Его связи остаются в архиве: 3.',
        ),
      );
      expect(
        find.widgetWithText(
          OutlinedButton,
          'Показать архив связей',
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      semantics.dispose();
    },
  );

  testWidgets('отличает подтверждённое отсутствие от загрузки', (tester) async {
    final repository = ControlledDetailsRepository();
    final id = testDetailsIntentionId(3);
    await _pumpDetailsPage(tester, repository, id);
    await waitForDetailRequests(repository, 1);
    repository.detailRequests.single.add(const ResultSuccess(null));
    await tester.pump();

    expect(find.text('Intention not found.'), findsOneWidget);
    _expectNavigation(tester);
    expect(find.widgetWithText(FilledButton, 'Try again'), findsNothing);
  });

  testWidgets('показывает терминальные отказы без обычного повтора', (
    tester,
  ) async {
    final scenarios = <(IntentionFailure, String)>[
      (
        const IntentionCorruptionFailure(),
        'Stored intention data is damaged and can’t be shown.',
      ),
      (
        const IntentionUnexpectedFailure(),
        'The intention couldn’t be loaded because of an unexpected error.',
      ),
    ];

    for (var index = 0; index < scenarios.length; index += 1) {
      final repository = ControlledDetailsRepository();
      final id = testDetailsIntentionId(index + 60);
      await _pumpDetailsPage(tester, repository, id);
      await waitForDetailRequests(repository, 1);
      final (failure, message) = scenarios[index];

      repository.detailRequests.single.add(ResultFailure(failure));
      await tester.pump();

      expect(find.text(message), findsOneWidget);
      _expectNavigation(tester);
      expect(find.widgetWithText(FilledButton, 'Try again'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  testWidgets('повторяет только устранимое чтение подробных данных', (
    tester,
  ) async {
    final repository = ControlledDetailsRepository();
    final intention = testDetailsIntention(index: 4);
    await _pumpDetailsPage(tester, repository, intention.id);
    await waitForDetailRequests(repository, 1);
    repository.detailRequests.single.add(
      const ResultFailure(IntentionUnavailableFailure()),
    );
    await tester.pump();

    expect(
      find.text('The intention couldn’t be loaded. Try again.'),
      findsOneWidget,
    );
    _expectNavigation(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
    await tester.pump();
    await waitForDetailRequests(repository, 2);
    expect(find.text('Loading intention…'), findsOneWidget);

    repository.detailRequests[1].add(ResultSuccess(intention));
    await tester.pump();
    expect(find.text(intention.title), findsOneWidget);
  });

  testWidgets('показывает сохраняющийся gate намерения отдельно от чтения', (
    tester,
  ) async {
    final repository = ControlledDetailsRepository();
    final intention = testDetailsIntention(index: 5);
    final container = _detailsContainer(repository);
    addTearDown(container.dispose);
    final coordinator = container.read(
      graphCommandCoordinatorProvider.notifier,
    );
    final start = coordinator.acceptExisting(
      DeleteIntention(intention.id),
      presentationTitle: intention.title,
    );
    expect(start, isA<IntentionCommandAccepted>());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _localizedApp(IntentionDetailsPage(intentionId: intention.id)),
      ),
    );
    await tester.pump();
    await waitForDetailRequests(repository, 1);

    expect(find.text('Saving changes…'), findsOneWidget);
    expect(find.text('Loading intention…'), findsOneWidget);

    repository.detailRequests.single.add(ResultSuccess(intention));
    await tester.pump();
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('intention-details-edit')),
          )
          .onPressed,
      isNull,
    );

    repository.completeCommand(
      0,
      const ResultFailure(IntentionUnavailableFailure()),
    );
    await (start as IntentionCommandAccepted).future;
    await tester.pump();
  });

  testWidgets(
    'изменяет поля без optimistic state и блокирует mutating controls на время записи',
    (tester) async {
      final repository = ControlledDetailsRepository();
      final intention = testDetailsIntention(
        index: 50,
        title: 'Прежнее название',
        description: 'Прежнее описание',
      );
      await _pumpDetailsPage(tester, repository, intention.id);
      await waitForDetailRequests(repository, 1);
      repository.detailRequests[0].add(ResultSuccess(intention));
      await tester.pump();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Edit'));
      await tester.pump();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('intention-details-edit-title')),
            )
            .controller
            ?.text,
        'Прежнее название',
      );
      await tester.enterText(
        find.byKey(const ValueKey('intention-details-edit-title')),
        '  Новое название  ',
      );
      await tester.enterText(
        find.byKey(const ValueKey('intention-details-edit-description')),
        '  Новое описание\n',
      );
      await _tapEditSubmit(tester);
      await tester.pump();

      expect(repository.commands, hasLength(1));
      expect(
        repository.commands.single,
        isA<UpdateIntention>()
            .having(
              (command) => command.title,
              'исходное название',
              '  Новое название  ',
            )
            .having(
              (command) => command.description,
              'исходное описание',
              '  Новое описание\n',
            ),
      );
      expect(
        find.text('Прежнее название', skipOffstage: false),
        findsOneWidget,
      );
      expect(find.text('Saving changes…'), findsNWidgets(2));
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('intention-details-edit-title')),
            )
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.byKey(const ValueKey('intention-details-edit-submit')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.byKey(const ValueKey('intention-details-edit-cancel')),
            )
            .onPressed,
        isNull,
      );

      repository.completeCommand(
        0,
        const ResultFailure(IntentionUnexpectedFailure()),
      );
      await tester.pumpAndSettle();
    },
  );

  testWidgets('прикрепляет ошибки текста к полю и сохраняет исправимый ввод', (
    tester,
  ) async {
    final scenarios =
        <(IntentionTextField, IntentionTextValidationReason, String)>[
          (
            IntentionTextField.title,
            IntentionTextValidationReason.empty,
            'Enter a title.',
          ),
          (
            IntentionTextField.title,
            IntentionTextValidationReason.tooLong,
            'Use no more than 255 characters.',
          ),
          (
            IntentionTextField.title,
            IntentionTextValidationReason.invalidUnicodeRepertoire,
            'Enter valid Unicode text without NUL.',
          ),
          (
            IntentionTextField.description,
            IntentionTextValidationReason.tooLong,
            'Use no more than 4096 characters.',
          ),
          (
            IntentionTextField.description,
            IntentionTextValidationReason.invalidUnicodeRepertoire,
            'Enter valid Unicode text without NUL.',
          ),
        ];

    for (var index = 0; index < scenarios.length; index += 1) {
      final repository = ControlledDetailsRepository();
      final intention = testDetailsIntention(index: 60 + index);
      await _pumpDetailsPage(tester, repository, intention.id);
      await waitForDetailRequests(repository, 1);
      repository.detailRequests[0].add(ResultSuccess(intention));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Edit'));
      await tester.pump();

      final (field, reason, message) = scenarios[index];
      final key = switch (field) {
        IntentionTextField.title => const ValueKey(
          'intention-details-edit-title',
        ),
        IntentionTextField.description => const ValueKey(
          'intention-details-edit-description',
        ),
        IntentionTextField.titleFilter => throw StateError(
          'Фильтр каталога не относится к форме подробного представления.',
        ),
      };
      final entered = 'Исправляемый ввод $index';
      await tester.enterText(find.byKey(key), entered);
      await _tapEditSubmit(tester);
      repository.completeCommand(
        0,
        ResultFailure(
          IntentionTextInputValidationFailure(
            IntentionTextValidationFailure(field: field, reason: reason),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(message), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byKey(key)).controller?.text,
        entered,
      );
      expect(tester.widget<TextField>(find.byKey(key)).enabled, isTrue);
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.byKey(const ValueKey('intention-details-edit-submit')),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byKey(key), '$entered исправлен');
      await tester.pump();
      expect(find.text(message), findsNothing);
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.byKey(const ValueKey('intention-details-edit-submit')),
            )
            .onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  testWidgets(
    'отмена редактирования до пригодного кадра передаёт ошибку оболочке',
    (tester) async {
      final repository = ControlledDetailsRepository();
      final intention = testDetailsIntention(index: 66, title: 'Редактируемое');
      await _pumpDetailsPage(tester, repository, intention.id);
      await waitForDetailRequests(repository, 1);
      repository.detailRequests[0].add(ResultSuccess(intention));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Edit'));
      await tester.pump();
      await _tapEditSubmit(tester);
      await tester.pump();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      repository.completeCommand(
        0,
        const ResultFailure(
          IntentionTextInputValidationFailure(
            IntentionTextValidationFailure(
              field: IntentionTextField.title,
              reason: IntentionTextValidationReason.tooLong,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Use no more than 255 characters.'), findsOneWidget);

      final cancel = find.byKey(
        const ValueKey('intention-details-edit-cancel'),
      );
      await tester.ensureVisible(cancel);
      await tester.pumpAndSettle();
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(find.text('Use no more than 255 characters.'), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(
        find.text('Edit — “Редактируемое”: Check the entered data.'),
        findsOneWidget,
      );
      expect(repository.commands, hasLength(1));
    },
  );

  testWidgets(
    'read failure или absence до кадра не оставляют claim без renderer',
    (tester) async {
      final scenarios = <Result<Intention?>>[
        const ResultSuccess(null),
        const ResultFailure(IntentionUnavailableFailure()),
      ];

      for (var index = 0; index < scenarios.length; index += 1) {
        final repository = ControlledDetailsRepository();
        final intention = testDetailsIntention(
          index: 67 + index,
          title: 'Наблюдаемое $index',
        );
        await _pumpDetailsPage(tester, repository, intention.id);
        await waitForDetailRequests(repository, 1);
        repository.detailRequests[0].add(ResultSuccess(intention));
        await tester.pumpAndSettle();
        final archive = find.byKey(const ValueKey('intention-details-archive'));
        await tester.ensureVisible(archive);
        await tester.pump();
        await tester.tap(archive);
        await tester.pump();

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        repository.completeCommand(
          0,
          const ResultFailure(IntentionUnavailableFailure()),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('The intention state couldn’t be changed. Try again.'),
          findsOneWidget,
        );

        repository.detailRequests[0].add(scenarios[index]);
        await tester.pumpAndSettle();
        expect(
          find.text('The intention state couldn’t be changed. Try again.'),
          findsNothing,
        );
        if (scenarios[index] is ResultFailure<Intention?>) {
          await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
          await tester.pump();
          await waitForDetailRequests(repository, 2);
        }

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        await tester.pump();
        expect(
          find.text(
            'Archive — “Наблюдаемое $index”: '
            'The intention state couldn’t be changed. Try again.',
          ),
          findsOneWidget,
        );
        expect(repository.commands, hasLength(1));

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
  );

  testWidgets('показывает confirmed success только после completion', (
    tester,
  ) async {
    final repository = ControlledDetailsRepository();
    final before = testDetailsIntention(index: 70, title: 'До изменения');
    final saved = testDetailsIntention(index: 70, title: 'После изменения');
    await _pumpDetailsPage(tester, repository, before.id);
    await waitForDetailRequests(repository, 1);
    repository.detailRequests[0].add(ResultSuccess(before));
    await tester.pump();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Edit'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('intention-details-edit-title')),
      saved.title,
    );
    await _tapEditSubmit(tester);
    await tester.pump();

    expect(find.text('До изменения', skipOffstage: false), findsOneWidget);
    expect(find.text('После изменения'), findsOneWidget);
    repository.completeCommand(
      0,
      testDetailsSavedResult(saved, before: before),
    );
    await tester.pump();
    await waitForDetailRequests(repository, 2);
    repository.detailRequests[1].add(ResultSuccess(saved));
    await tester.pump();
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(
        const ValueKey('intention-details-title'),
        skipOffstage: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Changes saved.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('intention-details-edit-title')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('intention-details-title')),
      findsOneWidget,
    );
    expect(find.text('После изменения'), findsOneWidget);
  });

  testWidgets(
    'оставляет уход доступным и передаёт поздний update outcome оболочке',
    (tester) async {
      final repository = ControlledDetailsRepository();
      final intention = testDetailsIntention(
        index: 71,
        title: 'Изменяемое намерение',
      );
      repository.catalogResult = ResultSuccess(
        IntentionCatalogFirstPage(
          items: [testDetailsSummary(intention)],
          totalCount: 1,
          nextCursor: null,
          revision: const _DetailsTestRevision(),
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
      await openIntentionGraph(tester, content: find.text(intention.title));
      await tester.tap(find.text(intention.title));
      await tester.pump();
      await waitForDetailRequests(repository, 1);
      repository.detailRequests[0].add(ResultSuccess(intention));
      await tester.pump();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Edit'));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('intention-details-edit-title')),
        'Позднее изменение',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('intention-details-edit-submit')),
      );
      await tester.pumpAndSettle();
      await _tapEditSubmit(tester);
      await tester.pump();
      expect(find.text('Saving changes…'), findsNWidgets(2));

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expectIntentionGraphRootPage(router);

      repository.completeCommand(
        0,
        const ResultFailure(IntentionUnavailableFailure()),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Edit — “Изменяемое намерение”: The changes couldn’t be saved. Try again.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('строка каталога открывает generated details route', (
    tester,
  ) async {
    final repository = ControlledDetailsRepository();
    final intention = testDetailsIntention(
      index: 6,
      title: 'Открываемое намерение',
      archiveState: IntentionArchiveState.archived,
    );
    repository.catalogResult = ResultSuccess(
      IntentionCatalogFirstPage(
        items: [testDetailsSummary(intention)],
        totalCount: 1,
        nextCursor: null,
        revision: const _DetailsTestRevision(),
      ),
    );
    final router = AppRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inMemoryQuickCreationModeOverride,
          personalGraphRepositoryProvider.overrideWithValue(repository),
        ],
        retry: (retryCount, error) => null,
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
    await openIntentionGraph(tester);

    await tester.tap(find.byKey(const ValueKey('catalog-scope-control')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archived').last);
    await tester.pumpAndSettle();
    expect(repository.catalogQueries.last.scope, IntentionScope.archived);

    await tester.tap(find.text('Открываемое намерение'));
    await tester.pump();
    await waitForDetailRequests(repository, 1);
    await tester.pump(const Duration(milliseconds: 500));

    expect(router.current.name, IntentionDetailsRoute.name);
    expect(find.byType(IntentionDetailsPage), findsOneWidget);
    expect(repository.detailIds, hasLength(2));
    expect(repository.detailIds, everyElement(intention.id));
  });

  testWidgets('IntentionDeleted завершает открытый details route', (
    tester,
  ) async {
    final repository = ControlledDetailsRepository();
    repository.catalogResult = ResultSuccess(
      IntentionCatalogFirstPage(
        items: const [],
        totalCount: 0,
        nextCursor: null,
        revision: const _DetailsTestRevision(),
      ),
    );
    final intention = testDetailsIntention(index: 70);
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
    await openIntentionGraph(tester);
    unawaited(router.push(IntentionDetailsRoute(intentionId: intention.id)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await waitForDetailRequests(repository, 1);
    repository.detailRequests[0].add(ResultSuccess(intention));
    await tester.pumpAndSettle();
    expect(router.current.name, IntentionDetailsRoute.name);

    final delete = find.byKey(const ValueKey('intention-details-delete'));
    await tester.ensureVisible(delete);
    await tester.pump();
    await tester.tap(delete);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('intention-details-confirm-delete')),
    );
    await tester.pump();
    expect(repository.commands.single, isA<DeleteIntention>());

    repository.completeCommand(0, testDetailsDeletedResult(intention));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expectIntentionGraphRootPage(router);
    expect(find.byType(IntentionDetailsPage), findsNothing);

    repository.detailRequests[0].add(ResultSuccess(intention));
    await tester.pump();
    expectIntentionGraphRootPage(router);
    expect(find.text(intention.title), findsNothing);
  });

  testWidgets(
    'success подробного просмотра не снимает fallback другой операции',
    (tester) async {
      const busyMessage =
          'Delete — “Другое намерение”: The intention couldn’t be deleted. Try again.';
      final repository = ControlledDetailsRepository();
      final intention = testDetailsIntention(index: 90, title: 'Открытое');
      final archived = testDetailsIntention(
        index: 90,
        title: 'Открытое',
        archiveState: IntentionArchiveState.archived,
      );
      await _pumpDetailsPage(tester, repository, intention.id);
      await waitForDetailRequests(repository, 1);
      repository.detailRequests[0].add(ResultSuccess(intention));
      await tester.pumpAndSettle();

      final coordinator = ProviderScope.containerOf(
        tester.element(find.byType(IntentionDetailsPage)),
      ).read(graphCommandCoordinatorProvider.notifier);
      final other = testDetailsIntention(index: 91, title: 'Другое намерение');
      final busy = coordinator.acceptExisting(
        DeleteIntention(other.id),
        presentationTitle: other.title,
      ) as IntentionCommandAccepted;
      coordinator.releaseInitiatorPresentation(busy.token);
      repository.completeCommand(
        0,
        const ResultFailure(IntentionUnavailableFailure()),
      );
      await tester.pumpAndSettle();
      expect(find.text(busyMessage), findsOneWidget);

      final archive = find.byKey(const ValueKey('intention-details-archive'));
      await tester.ensureVisible(archive);
      await tester.pump();
      await tester.tap(archive);
      await tester.pump();
      repository.completeCommand(
        1,
        testDetailsSavedResult(archived, before: intention),
      );
      await tester.pump();
      await waitForDetailRequests(repository, 2);
      repository.detailRequests[1].add(ResultSuccess(archived));
      await tester.pumpAndSettle();

      expect(find.text('Archived', skipOffstage: false), findsOneWidget);
      expect(find.text(busyMessage), findsOneWidget);
      expect(find.textContaining('Intention archived.'), findsNothing);

      await _closeOperationMessage(tester);
      expect(find.text(busyMessage), findsNothing);
      expect(
        find.text('Archive — “Открытое”: Intention archived.'),
        findsOneWidget,
      );

      await _closeOperationMessage(tester);
      expect(find.textContaining('Intention archived.'), findsNothing);
    },
  );

  testWidgets(
    'удаление закрывает маршрут при занятой поверхности и предъявляется один раз',
    (tester) async {
      const busyMessage =
          'Delete — “Другое намерение”: The intention couldn’t be deleted. Try again.';
      final repository = ControlledDetailsRepository();
      repository.catalogResult = ResultSuccess(
        IntentionCatalogFirstPage(
          items: const [],
          totalCount: 0,
          nextCursor: null,
          revision: const _DetailsTestRevision(),
        ),
      );
      final intention = testDetailsIntention(index: 92, title: 'Удаляемое');
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
      await openIntentionGraph(tester);
      unawaited(router.push(IntentionDetailsRoute(intentionId: intention.id)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await waitForDetailRequests(repository, 1);
      repository.detailRequests[0].add(ResultSuccess(intention));
      await tester.pumpAndSettle();

      final coordinator = container.read(
        graphCommandCoordinatorProvider.notifier,
      );
      final other = testDetailsIntention(index: 93, title: 'Другое намерение');
      final busy = coordinator.acceptExisting(
        DeleteIntention(other.id),
        presentationTitle: other.title,
      ) as IntentionCommandAccepted;
      coordinator.releaseInitiatorPresentation(busy.token);
      repository.completeCommand(
        0,
        const ResultFailure(IntentionUnavailableFailure()),
      );
      await tester.pumpAndSettle();
      expect(find.text(busyMessage), findsOneWidget);

      final delete = find.byKey(const ValueKey('intention-details-delete'));
      await Scrollable.ensureVisible(tester.element(delete), alignment: 0.3);
      await tester.pumpAndSettle();
      await tester.tap(delete);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('intention-details-confirm-delete')),
      );
      await tester.pump();
      repository.completeCommand(1, testDetailsDeletedResult(intention));
      await tester.pumpAndSettle();

      expectIntentionGraphRootPage(router);
      expect(find.text(busyMessage), findsOneWidget);
      expect(find.textContaining('Intention deleted.'), findsNothing);

      await _closeOperationMessage(tester);
      expect(
        find.text('Delete — “Удаляемое”: Intention deleted.'),
        findsOneWidget,
      );
      await _closeOperationMessage(tester);
      expect(find.textContaining('Intention deleted.'), findsNothing);
    },
  );

  testWidgets(
    'ошибка перехода без фокуса передаётся оболочке при уходе до кадра',
    (tester) async {
      const inlineFailure =
          'The intention state couldn’t be changed. Try again.';
      final repository = ControlledDetailsRepository();
      final intention = testDetailsIntention(index: 94, title: 'Архивируемое');
      repository.catalogResult = ResultSuccess(
        IntentionCatalogFirstPage(
          items: [testDetailsSummary(intention)],
          totalCount: 1,
          nextCursor: null,
          revision: const _DetailsTestRevision(),
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
      await openIntentionGraph(tester, content: find.text(intention.title));
      await tester.tap(find.text(intention.title));
      await tester.pump();
      await waitForDetailRequests(repository, 1);
      repository.detailRequests[0].add(ResultSuccess(intention));
      await tester.pumpAndSettle();

      final archive = find.byKey(const ValueKey('intention-details-archive'));
      await tester.ensureVisible(archive);
      await tester.pump();
      await tester.tap(archive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      repository.completeCommand(
        0,
        const ResultFailure(IntentionUnavailableFailure()),
      );
      await tester.pumpAndSettle();
      expect(find.text(inlineFailure), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expectIntentionGraphRootPage(router);
      expect(find.textContaining(inlineFailure), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(
        find.text('Archive — “Архивируемое”: $inlineFailure'),
        findsOneWidget,
      );
      await _closeOperationMessage(tester);
      expect(find.textContaining(inlineFailure), findsNothing);
    },
  );

  testWidgets(
    'шапка показывает управление отметкой только при полученных подробных данных',
    (tester) async {
      final outcomes = <Result<Intention?>>[
        const ResultSuccess(null),
        const ResultFailure(IntentionUnavailableFailure()),
        const ResultFailure(IntentionCorruptionFailure()),
        const ResultFailure(IntentionUnexpectedFailure()),
      ];
      for (var index = 0; index < outcomes.length; index += 1) {
        final repository = ControlledDetailsRepository();
        await _pumpDetailsPage(
          tester,
          repository,
          testDetailsIntentionId(60 + index),
        );
        await waitForDetailRequests(repository, 1);

        // Загрузка не изображает отметку отсутствующей.
        expect(find.text('Loading intention…'), findsOneWidget);
        expect(find.byKey(_favoriteMarkKey), findsNothing);
        expect(find.byIcon(Icons.star_border), findsNothing);

        repository.detailRequests.single.add(outcomes[index]);
        await tester.pumpAndSettle();

        expect(find.byKey(_favoriteMarkKey), findsNothing);
        expect(find.byIcon(Icons.star_border), findsNothing);
        expect(find.byIcon(Icons.star), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
  );

  testWidgets(
    'шапка различает подтверждённую отметку формой значка у активного и архивированного намерения',
    (tester) async {
      final scenarios = <(IntentionArchiveState, FavoriteMark, IconData)>[
        (
          IntentionArchiveState.active,
          FavoriteMark.notFavorite,
          Icons.star_border,
        ),
        (IntentionArchiveState.active, FavoriteMark.favorite, Icons.star),
        (
          IntentionArchiveState.archived,
          FavoriteMark.notFavorite,
          Icons.star_border,
        ),
        (IntentionArchiveState.archived, FavoriteMark.favorite, Icons.star),
      ];
      for (var index = 0; index < scenarios.length; index += 1) {
        final (archiveState, favoriteMark, icon) = scenarios[index];
        final repository = ControlledDetailsRepository();
        final intention = testDetailsIntention(
          index: 70 + index,
          archiveState: archiveState,
        );
        await _pumpDetailsPage(tester, repository, intention.id);
        await waitForDetailRequests(repository, 1);
        repository.detailRequests.single.add(
          ResultSuccess(intention),
          favoriteMark: favoriteMark,
        );
        await tester.pumpAndSettle();

        final control = find.byKey(_favoriteMarkKey);
        expect(
          find.descendant(of: find.byType(AppBar), matching: control),
          findsOneWidget,
        );
        expect(
          find.descendant(of: control, matching: find.byType(Icon)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: control, matching: find.byIcon(icon)),
          findsOneWidget,
        );
        expect(tester.widget<IconButton>(control).onPressed, isNotNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
  );

  testWidgets(
    'нажатие отправляет отметку либо её снятие и показывает только подтверждённое состояние',
    (tester) async {
      final repository = ControlledDetailsRepository();
      final intention = testDetailsIntention(index: 80, title: 'Гулять');
      await _pumpDetailsPage(tester, repository, intention.id);
      await waitForDetailRequests(repository, 1);
      repository.detailRequests[0].add(ResultSuccess(intention));
      await tester.pumpAndSettle();
      final control = find.byKey(_favoriteMarkKey);

      await tester.tap(control);
      await tester.pump();

      expect(
        repository.commands.single,
        isA<MarkIntentionFavorite>().having(
          (command) => command.id,
          'id',
          intention.id,
        ),
      );
      // Пока операция выполняется, видна последняя подтверждённая отметка.
      expect(find.text('Saving changes…'), findsOneWidget);
      expect(
        find.descendant(of: control, matching: find.byIcon(Icons.star_border)),
        findsOneWidget,
      );
      expect(tester.widget<IconButton>(control).onPressed, isNull);
      await tester.tap(control, warnIfMissed: false);
      await tester.pump();
      expect(repository.commands, hasLength(1));

      repository.completeCommand(
        0,
        testDetailsSavedResult(
          intention,
          before: intention,
          revision: const TestDetailsRevision(1),
          favoriteMark: FavoriteMark.favorite,
        ),
      );
      await tester.pump();
      await waitForDetailRequests(repository, 2);
      repository.detailRequests[1].add(
        ResultSuccess(intention),
        revision: const TestDetailsRevision(1),
        favoriteMark: FavoriteMark.favorite,
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: control, matching: find.byIcon(Icons.star)),
        findsOneWidget,
      );
      // Успех предъявляет только общая поверхность.
      expect(
        find.text('Mark as favorite — “Гулять”: Intention marked as favorite.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('intention-details-state-change-failure')),
        findsNothing,
      );
      await _closeOperationMessage(tester);
      expect(find.text('Гулять'), findsOneWidget);
      expect(find.text('Not ready for action'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);

      await tester.tap(control);
      await tester.pump();

      expect(repository.commands, hasLength(2));
      expect(
        repository.commands.last,
        isA<UnmarkIntentionFavorite>().having(
          (command) => command.id,
          'id',
          intention.id,
        ),
      );
      expect(
        find.descendant(of: control, matching: find.byIcon(Icons.star)),
        findsOneWidget,
      );

      repository.completeCommand(
        1,
        testDetailsSavedResult(
          intention,
          before: intention,
          revision: const TestDetailsRevision(2),
          beforeFavoriteMark: FavoriteMark.favorite,
        ),
      );
      await tester.pump();
      await waitForDetailRequests(repository, 3);
      repository.detailRequests[2].add(
        ResultSuccess(intention),
        revision: const TestDetailsRevision(2),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: control, matching: find.byIcon(Icons.star_border)),
        findsOneWidget,
      );
      await _closeOperationMessage(tester);
    },
  );

  testWidgets(
    'управление отметкой недоступно при открытой форме изменения и другой операции намерения',
    (tester) async {
      final repository = ControlledDetailsRepository();
      final intention = testDetailsIntention(index: 81);
      await _pumpDetailsPage(tester, repository, intention.id);
      await waitForDetailRequests(repository, 1);
      repository.detailRequests[0].add(
        ResultSuccess(intention),
        favoriteMark: FavoriteMark.favorite,
      );
      await tester.pumpAndSettle();
      final control = find.byKey(_favoriteMarkKey);

      final edit = find.byKey(const ValueKey('intention-details-edit'));
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();

      expect(tester.widget<IconButton>(control).onPressed, isNull);
      expect(
        find.descendant(of: control, matching: find.byIcon(Icons.star)),
        findsOneWidget,
      );
      await tester.tap(control, warnIfMissed: false);
      await tester.pump();
      expect(repository.commands, isEmpty);

      final cancel = find.byKey(
        const ValueKey('intention-details-edit-cancel'),
      );
      await tester.ensureVisible(cancel);
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(control).onPressed, isNotNull);

      final archive = find.byKey(const ValueKey('intention-details-archive'));
      await Scrollable.ensureVisible(tester.element(archive), alignment: 0.3);
      await tester.pumpAndSettle();
      await tester.tap(archive);
      await tester.pump();

      expect(repository.commands.single, isA<ArchiveIntention>());
      expect(tester.widget<IconButton>(control).onPressed, isNull);
      await tester.tap(control, warnIfMissed: false);
      await tester.pump();
      expect(repository.commands, hasLength(1));

      repository.completeCommand(
        0,
        const ResultFailure(IntentionUnexpectedFailure()),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(control).onPressed, isNotNull);
    },
  );

  testWidgets(
    'отказ отметки и её снятия показан под шапкой вне прокрутки с повтором только при недоступности',
    (tester) async {
      final scenarios = <(Locale, FavoriteMark, IntentionFailure, String, bool)>[
        (
          const Locale('en'),
          FavoriteMark.notFavorite,
          const IntentionNotFoundFailure(),
          'The intention no longer exists. The favorite mark wasn’t changed.',
          false,
        ),
        (
          const Locale('en'),
          FavoriteMark.notFavorite,
          const IntentionUnavailableFailure(),
          'The favorite mark couldn’t be changed. Try again.',
          true,
        ),
        (
          const Locale('en'),
          FavoriteMark.favorite,
          const IntentionCorruptionFailure(),
          'Stored data is damaged. The favorite mark wasn’t changed.',
          false,
        ),
        (
          const Locale('en'),
          FavoriteMark.favorite,
          const IntentionUnexpectedFailure(),
          'The favorite mark couldn’t be changed because of an unexpected error.',
          false,
        ),
        (
          const Locale('ru'),
          FavoriteMark.favorite,
          const IntentionUnavailableFailure(),
          'Не удалось изменить отметку избранного. Повторите попытку.',
          true,
        ),
        (
          const Locale('ru'),
          FavoriteMark.notFavorite,
          const IntentionCorruptionFailure(),
          'Сохранённые данные повреждены. Отметка избранного не изменена.',
          false,
        ),
      ];

      for (var index = 0; index < scenarios.length; index += 1) {
        final (locale, favoriteMark, failure, message, canRetry) =
            scenarios[index];
        final isFavorite = favoriteMark == FavoriteMark.favorite;
        final confirmedIcon = isFavorite ? Icons.star : Icons.star_border;
        final repository = ControlledDetailsRepository();
        final intention = testDetailsIntention(
          index: 90 + index,
          description: _longDescription,
        );
        await _pumpDetailsPage(
          tester,
          repository,
          intention.id,
          locale: locale,
        );
        await waitForDetailRequests(repository, 1);
        repository.detailRequests[0].add(
          ResultSuccess(intention),
          favoriteMark: favoriteMark,
        );
        await tester.pumpAndSettle();
        final control = find.byKey(_favoriteMarkKey);

        // Страница прокручена внутри длинного описания: область действий
        // находится вне видимой части.
        final position = tester.state<ScrollableState>(_detailsScrollable);
        position.position.jumpTo(_scrolledOffset);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('intention-details-edit')).hitTestable(),
          findsNothing,
        );

        await tester.tap(control);
        await tester.pump();
        repository.completeCommand(0, ResultFailure(failure));
        await tester.pumpAndSettle();

        // Ошибку предъявляет полоса под шапкой: область действий и общая
        // поверхность её не повторяют, а прокрутка остаётся на месте.
        final banner = find.byKey(_favoriteMarkFailureKey);
        expect(find.text(message), findsOneWidget);
        expect(
          find.descendant(of: banner, matching: find.text(message)),
          findsOneWidget,
        );
        expect(find.text(message).hitTestable(), findsOneWidget);
        expect(
          tester.getRect(banner).bottom,
          lessThanOrEqualTo(tester.getRect(_detailsScrollable).top),
        );
        expect(position.position.pixels, _scrolledOffset);
        expect(find.byKey(_stateChangeFailureKey), findsNothing);
        expect(find.byKey(_stateChangeRetryKey), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        expect(
          find.descendant(of: control, matching: find.byIcon(confirmedIcon)),
          findsOneWidget,
        );
        expect(tester.widget<IconButton>(control).onPressed, isNotNull);
        final retry = find.byKey(_favoriteMarkRetryKey);
        expect(retry, canRetry ? findsOneWidget : findsNothing);
        if (canRetry) {
          // Повтор виден без прокрутки и отправляет новую команду.
          expect(retry.hitTestable(), findsOneWidget);
          expect(
            tester.getRect(retry).bottom,
            lessThanOrEqualTo(tester.getRect(_detailsScrollable).top),
          );
          await tester.tap(retry);
          await tester.pump();
          expect(repository.commands, hasLength(2));
          expect(
            repository.commands.last,
            isFavorite
                ? isA<UnmarkIntentionFavorite>()
                : isA<MarkIntentionFavorite>(),
          );
          expect(banner, findsNothing);
          repository.completeCommand(
            1,
            const ResultFailure(IntentionUnexpectedFailure()),
          );
          await tester.pumpAndSettle();
          expect(banner, findsOneWidget);
          expect(retry, findsNothing);
          expect(position.position.pixels, _scrolledOffset);
        }

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
  );

  testWidgets(
    'полосы отказа отметки нет после отказа другой операции намерения и после успеха отметки',
    (tester) async {
      final repository = ControlledDetailsRepository();
      final intention = testDetailsIntention(index: 100);
      await _pumpDetailsPage(tester, repository, intention.id);
      await waitForDetailRequests(repository, 1);
      repository.detailRequests[0].add(ResultSuccess(intention));
      await tester.pumpAndSettle();
      final control = find.byKey(_favoriteMarkKey);
      final banner = find.byKey(_favoriteMarkFailureKey);

      await tester.tap(control);
      await tester.pump();
      repository.completeCommand(
        0,
        const ResultFailure(IntentionUnavailableFailure()),
      );
      await tester.pumpAndSettle();
      expect(banner, findsOneWidget);
      expect(find.byKey(_favoriteMarkRetryKey), findsOneWidget);

      // Отказ архивирования остаётся в области действий и убирает полосу.
      final archive = find.byKey(const ValueKey('intention-details-archive'));
      await tester.ensureVisible(archive);
      await tester.pump();
      await tester.tap(archive);
      await tester.pump();
      expect(repository.commands.last, isA<ArchiveIntention>());
      repository.completeCommand(
        1,
        const ResultFailure(IntentionUnavailableFailure()),
      );
      await tester.pumpAndSettle();
      expect(banner, findsNothing);
      expect(find.byKey(_favoriteMarkRetryKey), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(_stateChangeFailureKey),
          matching: find.text(
            'The intention state couldn’t be changed. Try again.',
          ),
        ),
        findsOneWidget,
      );
      expect(find.byKey(_stateChangeRetryKey), findsOneWidget);

      await tester.tap(control);
      await tester.pump();
      repository.completeCommand(
        2,
        const ResultFailure(IntentionUnavailableFailure()),
      );
      await tester.pumpAndSettle();
      expect(banner, findsOneWidget);
      expect(find.byKey(_stateChangeFailureKey), findsNothing);
      expect(find.byKey(_stateChangeRetryKey), findsNothing);

      // Успешный повтор убирает полосу.
      await tester.tap(find.byKey(_favoriteMarkRetryKey));
      await tester.pump();
      repository.completeCommand(
        3,
        testDetailsSavedResult(
          intention,
          before: intention,
          revision: const TestDetailsRevision(1),
          favoriteMark: FavoriteMark.favorite,
        ),
      );
      await tester.pump();
      await waitForDetailRequests(repository, 2);
      repository.detailRequests[1].add(
        ResultSuccess(intention),
        revision: const TestDetailsRevision(1),
        favoriteMark: FavoriteMark.favorite,
      );
      await tester.pumpAndSettle();
      expect(banner, findsNothing);
      expect(find.byKey(_favoriteMarkRetryKey), findsNothing);
      expect(
        find.descendant(of: control, matching: find.byIcon(Icons.star)),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'управление отметкой недоступно от подтверждения до снимка и затем предлагает обратное действие',
    (tester) async {
      final scenarios =
          <(FavoriteMark, FavoriteMark, IconData, String, String)>[
            (
              FavoriteMark.notFavorite,
              FavoriteMark.favorite,
              Icons.star_border,
              'Not marked',
              'Remove favorite mark',
            ),
            (
              FavoriteMark.favorite,
              FavoriteMark.notFavorite,
              Icons.star,
              'Marked',
              'Mark as favorite',
            ),
          ];

      for (var index = 0; index < scenarios.length; index += 1) {
        final (before, after, confirmedIcon, confirmedValue, reverseAction) =
            scenarios[index];
        final semantics = tester.ensureSemantics();
        final repository = ControlledDetailsRepository();
        final intention = testDetailsIntention(index: 130 + index);
        await _pumpDetailsPage(tester, repository, intention.id);
        await waitForDetailRequests(repository, 1);
        repository.detailRequests[0].add(
          ResultSuccess(intention),
          revision: const TestDetailsRevision(1),
          favoriteMark: before,
        );
        await tester.pumpAndSettle();
        final control = find.byKey(_favoriteMarkKey);

        await tester.tap(control);
        await tester.pump();
        repository.completeCommand(
          0,
          testDetailsSavedResult(
            intention,
            before: intention,
            revision: const TestDetailsRevision(2),
            beforeFavoriteMark: before,
            favoriteMark: after,
          ),
        );
        await tester.pump();
        await waitForDetailRequests(repository, 2);
        await tester.pump();

        // Операция завершена, а подробные данные несут прежнюю отметку.
        expect(find.text('Saving changes…'), findsNothing);
        expect(tester.widget<IconButton>(control).onPressed, isNull);
        expect(
          find.descendant(of: control, matching: find.byIcon(confirmedIcon)),
          findsOneWidget,
        );
        expect(
          tester.getSemantics(control),
          isSemantics(value: confirmedValue, isEnabled: false),
        );
        await tester.tap(control, warnIfMissed: false);
        await tester.pump();
        expect(repository.commands, hasLength(1));

        repository.detailRequests[1].add(
          ResultSuccess(intention),
          revision: const TestDetailsRevision(2),
          favoriteMark: after,
        );
        await tester.pump();
        await tester.pump();
        expect(tester.widget<IconButton>(control).onPressed, isNotNull);
        expect(tester.widget<IconButton>(control).tooltip, reverseAction);

        await tester.tap(control);
        await tester.pump();
        expect(repository.commands, hasLength(2));
        expect(
          repository.commands.last,
          after == FavoriteMark.favorite
              ? isA<UnmarkIntentionFavorite>()
              : isA<MarkIntentionFavorite>(),
        );

        repository.completeCommand(
          1,
          const ResultFailure(IntentionUnexpectedFailure()),
        );
        await tester.pumpAndSettle();
        semantics.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        await _closeOperationMessage(tester);
      }
    },
  );

  testWidgets(
    'экранный диктор получает название, состояние и доступность управления отметкой на обоих языках',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final scenarios = <(Locale, FavoriteMark, String, String, String)>[
        (
          const Locale('en'),
          FavoriteMark.notFavorite,
          'Favorite intention',
          'Not marked',
          'Mark as favorite',
        ),
        (
          const Locale('en'),
          FavoriteMark.favorite,
          'Favorite intention',
          'Marked',
          'Remove favorite mark',
        ),
        (
          const Locale('ru'),
          FavoriteMark.notFavorite,
          'Избранное намерение',
          'Не отмечено',
          'Отметить избранным',
        ),
        (
          const Locale('ru'),
          FavoriteMark.favorite,
          'Избранное намерение',
          'Отмечено',
          'Снять отметку избранного',
        ),
      ];

      for (var index = 0; index < scenarios.length; index += 1) {
        final (locale, favoriteMark, label, value, action) = scenarios[index];
        final repository = ControlledDetailsRepository();
        final intention = testDetailsIntention(index: 110 + index);
        await _pumpDetailsPage(
          tester,
          repository,
          intention.id,
          locale: locale,
        );
        await waitForDetailRequests(repository, 1);
        repository.detailRequests[0].add(
          ResultSuccess(intention),
          favoriteMark: favoriteMark,
        );
        await tester.pumpAndSettle();
        final control = find.byKey(_favoriteMarkKey);

        expect(
          tester.getSemantics(control),
          matchesSemantics(
            label: label,
            value: value,
            tooltip: action,
            isButton: true,
            hasEnabledState: true,
            isEnabled: true,
            isFocusable: true,
            hasTapAction: true,
            hasFocusAction: true,
          ),
        );
        expect(find.byTooltip(action), findsOneWidget);

        await tester.tap(control);
        await tester.pump();

        // Недоступное управление сохраняет название и подтверждённое состояние.
        expect(
          tester.getSemantics(control),
          matchesSemantics(
            label: label,
            value: value,
            tooltip: action,
            isButton: true,
            hasEnabledState: true,
            isFocusable: true,
            hasFocusAction: true,
          ),
        );

        repository.completeCommand(
          0,
          const ResultFailure(IntentionUnexpectedFailure()),
        );
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
      semantics.dispose();
    },
  );
}

Future<void> _tapEditSubmit(WidgetTester tester) async {
  final submit = find.byKey(const ValueKey('intention-details-edit-submit'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(submit);
  await tester.pumpAndSettle();
  await tester.tap(submit);
}

const _favoriteMarkKey = ValueKey('intention-details-favorite-mark');

void _expectNavigation(WidgetTester tester) {
  expect(find.byType(AppNavigationBar), findsOneWidget);
  expect(
    tester.widget<AppNavigationBar>(find.byType(AppNavigationBar)).selected,
    AppDestination.home,
  );
}

const _favoriteMarkFailureKey = ValueKey(
  'intention-details-favorite-mark-failure',
);
const _favoriteMarkRetryKey = ValueKey('intention-details-favorite-mark-retry');
const _stateChangeFailureKey = ValueKey(
  'intention-details-state-change-failure',
);
const _stateChangeRetryKey = ValueKey('intention-details-state-change-retry');

/// Описание, при котором область действий лежит далеко за видимой частью.
final _longDescription = List.filled(
  120,
  'Длинное описание намерения.',
).join('\n');

/// Положение прокрутки внутри длинного описания.
const _scrolledOffset = 240.0;

/// Прокрутка содержимого страницы намерения.
final _detailsScrollable = find
    .descendant(
      of: find.byType(CustomScrollView),
      matching: find.byType(Scrollable),
    )
    .first;

Future<void> _pumpDetailsPage(
  WidgetTester tester,
  ControlledDetailsRepository repository,
  IntentionId intentionId, {
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        inMemoryQuickCreationModeOverride,
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
      retry: (retryCount, error) => null,
      child: _localizedApp(
        IntentionDetailsPage(intentionId: intentionId),
        locale: locale,
      ),
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

Widget _localizedApp(Widget home, {Locale locale = const Locale('en')}) =>
    OrdinaryPageTestApp(
      locale: locale,
      builder: (context, child) =>
          GraphOperationPresenter(child: child ?? const SizedBox.shrink()),
      home: home,
    );

Future<void> _closeOperationMessage(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

final class _DetailsTestRevision implements GraphRevision {
  const _DetailsTestRevision();

  @override
  GraphRevisionOrder compareTo(GraphRevision other) =>
      other is _DetailsTestRevision
      ? GraphRevisionOrder.same
      : GraphRevisionOrder.differentEpoch;
}
