import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:doable/src/design_system/components/button.dart';
import 'package:doable/src/design_system/components/option_tiles.dart';
import 'package:doable/src/design_system/components/top_bar.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/intention/presentation/edit/intention_edit_page.dart';
import 'package:doable/src/tag/application/tag_assignments.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/presentation/assignments/tag_assignments_view_model.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/daily_choice/application/daily_choice_catalog.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_priority.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_schedule.dart';
import 'package:doable/src/daily_choice/presentation/details/daily_choice_details_page.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/design_system/doable_theme.dart';
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
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/design_system/components/page_head.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/app_root_pages.dart';
import '../../../support/ordinary_page_test_app.dart';
import '../../../support/tag_positions.dart';
import 'details_test_support.dart';

import '../../../support/in_memory_quick_creation_mode_store.dart';

void main() {
  setUp(() {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  testWidgets(
    'страница активного и архивированного намерения не предлагает избранное',
    (tester) async {
      final semantics = tester.ensureSemantics();
      for (final archiveState in IntentionArchiveState.values) {
        final repository = ControlledDetailsRepository();
        final intention = testDetailsIntention(archiveState: archiveState);
        await _pumpDetailsPage(tester, repository, intention.id);
        await waitForDetailRequests(repository, 1);
        repository.detailRequests.single.add(ResultSuccess(intention));
        await tester.pumpAndSettle();

        expect(find.text(intention.title), findsOneWidget);
        expect(find.byTooltip('Mark as favorite'), findsNothing);
        expect(find.byTooltip('Remove favorite mark'), findsNothing);
        expect(
          find.bySemanticsLabel(RegExp('favorite', caseSensitive: false)),
          findsNothing,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
      semantics.dispose();
    },
  );

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
            schedule: const DailyChoiceAllDay(),
            priority: DailyChoicePriority.p4,
            description: null,
            pathIntentionCount: 2,
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
          theme: doableTheme(Brightness.light),
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
    await tester.tap(find.text('Связи'));
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
    expect(_selectedType(tester), IntentionReadiness.ready);
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
    expect(find.text('Add a description'), findsOneWidget);
    expect(_selectedType(tester), IntentionReadiness.notReady);
  });

  testWidgets('подробный просмотр проходит accessibility guidelines', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    // Обзор целиком помещается под закреплёнными вкладками: срезанные ими
    // элементы правило области нажатия считает слишком малыми.
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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
    // Шапка уходит под верхнюю панель, а весь обзор остаётся видимым.
    tester
        .state<ScrollableState>(_detailsScrollable)
        .position
        .jumpTo(tester.getSize(find.byType(PageHead)).height);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('intention-details-delete')).hitTestable(),
      findsOneWidget,
    );

    // Контракт дизайн-системы задаёт область нажатия 44.
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    semantics.dispose();
  });

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

      final intentionTile = find.descendant(
        of: find.byType(OptionTiles<IntentionReadiness>),
        matching: find.text('Intention'),
      );
      await tester.ensureVisible(intentionTile);
      await tester.tap(intentionTile);
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
      expect(find.byType(SnackBar), findsNothing);
      expect(_selectedType(tester), IntentionReadiness.notReady);

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
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Archived', skipOffstage: false), findsOneWidget);
      expect(_selectedType(tester), IntentionReadiness.notReady);

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
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Active', skipOffstage: false), findsOneWidget);
    },
  );

  testWidgets(
    'отдаёт отказы перехода общей поверхности, а повтор — новое нажатие',
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

        final (failure, message, retries) = scenarios[index];
        repository.completeCommand(0, ResultFailure(failure));
        await tester.pumpAndSettle();

        expect(find.textContaining(message), findsOneWidget);
        expect(
          find.text('Archive — “${intention.title}”: $message'),
          findsOneWidget,
        );
        expect(find.text('Active', skipOffstage: false), findsOneWidget);
        if (retries) {
          await _closeOperationMessage(tester);
          await tester.ensureVisible(archive);
          await tester.pump();
          await tester.tap(archive);
          await tester.pump();
          expect(repository.commands, hasLength(2));
          expect(repository.commands.last, isA<ArchiveIntention>());
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
    expect(tester.widget<PageHead>(find.byType(PageHead)).onEdit, isNull);

    repository.completeCommand(
      0,
      const ResultFailure(IntentionUnavailableFailure()),
    );
    await (start as IntentionCommandAccepted).future;
    await tester.pump();
  });

  testWidgets('строка каталога открывает подробности намерения', (
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
          theme: doableTheme(Brightness.light),
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
          theme: doableTheme(Brightness.light),
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

      // Успех архивирования не объявляется и после закрытия чужого отказа.
      await _closeOperationMessage(tester);
      expect(find.text(busyMessage), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
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

      // Кнопка стоит в конце «Обзора» под сообщением общей поверхности,
      // поэтому её нажимают напрямую.
      tester
          .widget<ButtonStyleButton>(
            find.byKey(const ValueKey('intention-details-delete')),
          )
          .onPressed!();
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

  testWidgets('сохранение, начатое экраном изменения, закрывает действия, '
      'теги и вход в правку после возвращения, а успех их открывает', (
    tester,
  ) async {
    final repository = ControlledDetailsRepository();
    final before = testDetailsIntention(index: 95, title: 'Бегать');
    final saved = testDetailsIntention(index: 95, title: 'Бегать по утрам');
    await _pumpEditablePage(tester, repository, before);

    await _sendTitleAndLeave(tester, saved.title);
    _expectPageControls(tester, enabled: false);
    await tester.tap(_headName(before.title));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(IntentionEditPage), findsNothing);

    repository.completeCommand(
      0,
      testDetailsSavedResult(saved, before: before),
    );
    await tester.pump();
    await waitForDetailRequests(repository, 2);
    repository.detailRequests.last.add(ResultSuccess(saved));
    await tester.pumpAndSettle();
    _expectPageControls(tester, enabled: true);
    expect(tester.widget<PageHead>(find.byType(PageHead)).name, saved.title);
  });

  testWidgets('после сохранения с экрана изменения вход в правку недоступен, '
      'пока страница не получит снимок с сохранённым текстом', (tester) async {
    final repository = ControlledDetailsRepository();
    final before = testDetailsIntention(index: 97, title: 'Бегать');
    final saved = testDetailsIntention(index: 97, title: 'Бегать по утрам');
    await _pumpEditablePage(tester, repository, before);

    await tester.tap(_headName(before.title));
    await tester.pumpAndSettle();
    await tester.enterText(_editTitleField, saved.title);
    await tester.pump();
    await tester.tap(_editSave);
    await tester.pump();
    repository.completeCommand(
      0,
      testDetailsSavedResult(saved, before: before),
    );
    await tester.pump();
    await waitForDetailRequests(repository, 2);
    await tester.pumpAndSettle();
    expect(find.byType(IntentionEditPage), findsNothing);
    final staleHead = tester.widget<PageHead>(find.byType(PageHead));
    expect(staleHead.name, before.title);
    expect(staleHead.onEdit, isNull);

    await tester.tap(_headName(before.title));
    await tester.pumpAndSettle();
    expect(find.byType(IntentionEditPage), findsNothing);

    repository.detailRequests.last.add(ResultSuccess(saved));
    await tester.pumpAndSettle();
    await tester.tap(_headName(saved.title));
    await tester.pumpAndSettle();
    expect(_editText(tester, _editTitleField), saved.title);
    await tester.enterText(_editDescriptionField, 'Новое описание');
    await tester.pump();
    await tester.tap(_editSave);
    await tester.pump();
    expect(
      repository.commands.last,
      isA<UpdateIntention>()
          .having((command) => command.title, 'название', saved.title)
          .having(
            (command) => command.description,
            'описание',
            'Новое описание',
          ),
    );
  });

  testWidgets('после отказа сохранения, начатого экраном изменения, вход в '
      'правку снова доступен с прежним подтверждённым текстом', (tester) async {
    final repository = ControlledDetailsRepository();
    final intention = testDetailsIntention(index: 96, title: 'Бегать');
    await _pumpEditablePage(tester, repository, intention);

    await _sendTitleAndLeave(tester, 'Бегать по утрам');
    _expectPageControls(tester, enabled: false);
    repository.completeCommand(
      0,
      const ResultFailure(IntentionUnavailableFailure()),
    );
    await tester.pump();
    await _closeOperationMessage(tester);
    _expectPageControls(tester, enabled: true);

    await tester.tap(_headName(intention.title));
    await tester.pumpAndSettle();
    expect(find.byType(IntentionEditPage), findsOneWidget);
    expect(_editText(tester, _editTitleField), intention.title);
    expect(_editText(tester, _editDescriptionField), intention.description);
  });
}

void _expectNavigation(WidgetTester tester) {
  expect(find.byType(AppNavigationBar), findsOneWidget);
  expect(
    tester.widget<AppNavigationBar>(find.byType(AppNavigationBar)).selected,
    AppDestination.home,
  );
}

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

final _editTitleField = find.byKey(const ValueKey('intention-edit-title'));
final _editDescriptionField = find.byKey(
  const ValueKey('intention-edit-description'),
);
final _editSave = find.descendant(
  of: find.byType(TopBar),
  matching: find.byType(Button),
);
final _editBack = find.descendant(
  of: find.byType(TopBar),
  matching: find.byType(DoableIcon),
);

Finder _headName(String title) =>
    find.descendant(of: find.byType(PageHead), matching: find.text(title));

String _editText(WidgetTester tester, Finder field) => tester
    .widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    )
    .controller
    .text;

/// Открывает правку нажатием на название, отправляет новое название и уходит
/// с экрана до результата сохранения.
Future<void> _sendTitleAndLeave(WidgetTester tester, String title) async {
  final name = tester.widget<PageHead>(find.byType(PageHead)).name;
  await tester.tap(_headName(name));
  await tester.pumpAndSettle();
  await tester.enterText(_editTitleField, title);
  await tester.pump();
  await tester.tap(_editSave);
  await tester.pump();
  await tester.tap(_editBack);
  await tester.pump();
  // Индикатор выполняющейся команды не даёт кадрам успокоиться.
  await tester.pump(const Duration(seconds: 1));
  expect(find.byType(IntentionEditPage), findsNothing);
}

IntentionReadiness _selectedType(WidgetTester tester) => tester
    .widget<OptionTiles<IntentionReadiness>>(
      find.byType(OptionTiles<IntentionReadiness>, skipOffstage: false),
    )
    .value;

/// Доступность изменяющих действий страницы, тегов и входа в правку.
void _expectPageControls(WidgetTester tester, {required bool enabled}) {
  final matcher = enabled ? isNotNull : isNull;
  expect(tester.widget<PageHead>(find.byType(PageHead)).onEdit, matcher);
  expect(
    tester
        .widget<OptionTiles<IntentionReadiness>>(
          find.byType(OptionTiles<IntentionReadiness>, skipOffstage: false),
        )
        .onChange,
    matcher,
  );
  for (final key in [
    'intention-details-choose-path',
    'intention-details-archive',
    'intention-details-delete',
    'tag-assignments-choose',
  ]) {
    expect(
      tester
          .widget<ButtonStyleButton>(
            find.byKey(ValueKey(key), skipOffstage: false),
          )
          .onPressed,
      matcher,
      reason: key,
    );
  }
  expect(
    tester
        .widget<InkWell>(
          find.descendant(
            of: find.byKey(
              ValueKey(
                'tag-assignment-remove-${_pageTag.id.toCanonicalString()}',
              ),
              skipOffstage: false,
            ),
            matching: find.byType(InkWell, skipOffstage: false),
          ),
        )
        .onTap,
    matcher,
    reason: 'крестик тега',
  );
}

final _pageTag = Tag(
  id: (TagId.decode(
    '018f0002-0000-7000-8000-000000000001',
  ) as TagIdDecodingSuccess).id,
  name: TagName.fromInput('Здоровье'),
  color: null,
  position: tagPositionAt(1),
);

/// Страница намерения с назначенным тегом и экраном изменения над ней.
Future<void> _pumpEditablePage(
  WidgetTester tester,
  ControlledDetailsRepository repository,
  Intention intention,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        inMemoryQuickCreationModeOverride,
        personalGraphRepositoryProvider.overrideWithValue(repository),
        tagAssignmentsReaderProvider.overrideWithValue(_PageTagReads()),
      ],
      retry: (retryCount, error) => null,
      child: OrdinaryPageTestApp(
        locale: const Locale('ru'),
        routes: [AutoRoute(page: IntentionEditRoute.page)],
        builder: (context, child) =>
            GraphOperationPresenter(child: child ?? const SizedBox.shrink()),
        home: IntentionDetailsPage(intentionId: intention.id),
      ),
    ),
  );
  await tester.pump();
  await waitForDetailRequests(repository, 1);
  repository.detailRequests.single.add(ResultSuccess(intention));
  await tester.pumpAndSettle();
}

final class _PageTagReads extends Fake implements TagReadContract {
  @override
  Future<TagAssignmentsResult> getTagAssignments(
    IntentionId intentionId,
  ) async => TagAssignmentsSuccess(
    TagAssignmentsSnapshot(
      intentionId: intentionId,
      items: [_pageTag],
      revision: const TestDetailsRevision(0),
    ),
  );
}
