import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/design_system/components/catalog_header.dart';
import 'package:doable/src/design_system/components/filter_button.dart';
import 'package:doable/src/design_system/components/path_glyph.dart';
import 'package:doable/src/design_system/components/sheet.dart';
import 'package:doable/src/design_system/components/top_bar.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_catalog.dart'
    hide IntentionCatalogPage;
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/catalog/catalog_paging_policy.dart';
import 'package:doable/src/intention/presentation/catalog/intention_tag_conditions_view_model.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/picker/intention_picker_view.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/application/relation_pair_probe.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/presentation/participant_picker/relation_participant_choice.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../intention/presentation/catalog/catalog_reconciliation_test_support.dart';
import '../../../intention/presentation/catalog/catalog_test_support.dart'
    show ControlledCatalogRepository, TestCatalogRevision, testSummary;
import '../../../intention/presentation/picker/intention_picker_test_support.dart';
import '../../../support/app_root_pages.dart';
import 'participant_picker_test_support.dart';

import '../../../support/in_memory_quick_creation_mode_store.dart';
import '../../../support/tag_positions.dart';
import '../../../support/tag_condition_cycles.dart';
import '../editor/relation_form_test_support.dart' show testFormRelationId;

void main() {
  _defineTagSearchTests();
  _definePurposeTests();
  _defineRestoreOfferTests();

  for (final (language, title, cancelLabel, emptyMessage) in const [
    (
      'ru',
      'Выбор намерения',
      'Отменить выбор намерения',
      'Других намерений для выбора нет.',
    ),
    (
      'en',
      'Choose an intention',
      'Cancel intention selection',
      'No other intentions are available to select.',
    ),
  ]) {
    testWidgets('$language: открывается экраном выбора намерения с подписью '
        'крестика и сообщением пустого охвата', (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = ControlledParticipantPickerRepository();
      addTearDown(repository.dispose);
      final router = await _pumpAppWithCatalog(
        tester,
        repository,
        locale: Locale(language),
      );
      addTearDown(router.dispose);

      unawaited(_pushPicker(router, _activeRelation.choice));
      await _settleRoute(tester);
      _completePage(repository, 1, const []);
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: find.byType(TopBar), matching: find.text(title)),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(_cancel),
        isSemantics(label: cancelLabel, isButton: true, hasTapAction: true),
      );
      expect(find.byKey(const ValueKey('participant-picker-filter')), findsOne);
      expect(find.text(emptyMessage), findsOneWidget);
      semantics.dispose();
    });
  }

  testWidgets('крестик и системное «назад» закрывают поиск без результата', (
    tester,
  ) async {
    final repository = ControlledParticipantPickerRepository();
    addTearDown(repository.dispose);
    final router = await _pumpAppWithCatalog(tester, repository);
    addTearDown(router.dispose);

    for (final (index, close) in <Future<void> Function()>[
      () => tester.tap(_cancel),
      () => tester.binding.handlePopRoute(),
    ].indexed) {
      final selection = _pushPicker(router, _activeRelation.choice);
      await _settleRoute(tester);
      _completePage(repository, index + 1, [
        testSummary(index: 1, title: 'Ходить'),
      ]);
      await tester.pumpAndSettle();

      await close();
      await tester.pumpAndSettle();
      expect(await selection, isNull);
      expect(find.byType(IntentionPickerView), findsNothing);
    }
  });

  testWidgets('стрелка открывает подробные данные намерения поверх поиска без '
      'выбора', (tester) async {
    final repository = ControlledParticipantPickerRepository();
    addTearDown(repository.dispose);
    final router = await _pumpAppWithCatalog(tester, repository);
    addTearDown(router.dispose);

    var selectionCompleted = false;
    final selection = _pushPicker(router, _activeRelation.choice)
      ..whenComplete(() => selectionCompleted = true);
    await _settleRoute(tester);
    final pickerId = router.current.matchId;
    _completePage(repository, 1, [
      testSummary(index: 2, title: 'Позвонить'),
      testSummary(index: 1, title: 'Позвонить'),
    ]);
    await tester.pumpAndSettle();

    await tester.tap(intentionPickerArrow(intentionPickerRows.last));
    await _settleRoute(tester);
    expect(find.byType(IntentionDetailsPage), findsOneWidget);
    expect(
      router.current.argsAs<IntentionDetailsRouteArgs>().intentionId,
      _id(1),
    );
    expect(router.stackData[router.stackData.length - 2].matchId, pickerId);
    expect(selectionCompleted, isFalse);

    await router.maybePop();
    await _settleRoute(tester);
    expect(router.current.matchId, pickerId);
    expect(selectionCompleted, isFalse);
    await tester.tap(find.text('Позвонить').last);
    await tester.pumpAndSettle();
    expect((await selection)?.value.id, _id(1));
  });

  // Нажатие на текст отмеченной строки открывает занимающую связь, кроме
  // архивной связи при создании: её восстановление проверяет
  // _defineRestoreOfferTests.
  for (final (flow, choice, scope) in [
    ('создания', _activeRelation.choice, RelationScope.active),
    ('изменения', _archivedRelation.choice, RelationScope.active),
    ('изменения', _archivedRelation.choice, RelationScope.archived),
  ]) {
    testWidgets('в потоке $flow нажатие на текст строки со связью '
        '${scope.name} открывает её поверх поиска без выбора, а «назад» '
        'возвращает в поиск', (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = ControlledParticipantPickerRepository();
      addTearDown(repository.dispose);
      final router = await _pumpAppWithCatalog(tester, repository);
      addTearDown(router.dispose);

      var selectionCompleted = false;
      final selection = _pushPicker(router, choice)
        ..whenComplete(() => selectionCompleted = true);
      await _settleRoute(tester);
      final pickerId = router.current.matchId;
      final occupied = testSummary(index: 2, title: 'Много ходить');
      final free = testSummary(index: 1, title: 'Высыпаться');
      final occupantId = testFormRelationId(5);
      _completePage(
        repository,
        1,
        [occupied, free],
        pairOccupants: {
          occupied.id: PairOccupant(relationId: occupantId, scope: scope),
        },
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel(RegExp('tapping opens the existing relation')),
        findsOneWidget,
      );
      await tester.tap(find.text('Много ходить'));
      await _settleRoute(tester);

      expect(
        router.current.argsAs<RelationDetailsRouteArgs>().relationId,
        occupantId,
      );
      expect(repository.watchedRelations, [occupantId]);
      expect(router.stackData[router.stackData.length - 2].matchId, pickerId);
      expect(selectionCompleted, isFalse);

      await router.maybePop();
      await _settleRoute(tester);
      expect(router.current.matchId, pickerId);
      expect(selectionCompleted, isFalse);

      await tester.tap(intentionPickerArrow(intentionPickerRows.first));
      await _settleRoute(tester);
      expect(
        router.current.argsAs<IntentionDetailsRouteArgs>().intentionId,
        occupied.id,
      );
      await router.maybePop();
      await _settleRoute(tester);

      await tester.tap(find.text('Высыпаться'));
      await tester.pumpAndSettle();
      expect((await selection)?.value.id, free.id);
      semantics.dispose();
    });
  }

  // Пока форма создания не может продолжаться, например пока выполняется
  // восстановление, поиск не принимает выбор и нажатия на отмеченные строки.
  testWidgets('пока поток создания не может продолжаться, нажатия на текст '
      'свободной и отмеченной строк ничего не делают, а после возобновления '
      'работают', (tester) async {
    final repository = ControlledParticipantPickerRepository();
    addTearDown(repository.dispose);
    final router = await _pumpAppWithCatalog(tester, repository);
    addTearDown(router.dispose);
    final restore = ControlledRelationRestore();

    var selectionCompleted = false;
    final selection = _pushPicker(router, _creationChoice(restore))
      ..whenComplete(() => selectionCompleted = true);
    await _settleRoute(tester);
    final pickerId = router.current.matchId;
    final occupied = testSummary(index: 2, title: 'Много ходить');
    final free = testSummary(index: 1, title: 'Высыпаться');
    _completePage(
      repository,
      1,
      [occupied, free],
      pairOccupants: {
        occupied.id: PairOccupant(
          relationId: testFormRelationId(5),
          scope: RelationScope.active,
        ),
      },
    );
    await tester.pumpAndSettle();

    restore.canContinue = false;
    await tester.tap(find.text('Высыпаться'));
    await tester.tap(find.text('Много ходить'));
    await tester.pumpAndSettle();

    expect(router.current.matchId, pickerId);
    expect(selectionCompleted, isFalse);
    expect(repository.watchedRelations, isEmpty);

    restore.canContinue = true;
    await tester.tap(find.text('Много ходить'));
    await _settleRoute(tester);
    expect(
      router.current.argsAs<RelationDetailsRouteArgs>().relationId,
      testFormRelationId(5),
    );
    await router.maybePop();
    await _settleRoute(tester);

    await tester.tap(find.text('Высыпаться'));
    await tester.pumpAndSettle();
    expect((await selection)?.value.id, free.id);
  });

  testWidgets('пока поток создания не может продолжаться, стрелка, лист '
      'назначения и закрытие работают', (tester) async {
    final repository = ControlledParticipantPickerRepository();
    addTearDown(repository.dispose);
    final router = await _pumpAppWithCatalog(tester, repository);
    addTearDown(router.dispose);
    final restore = ControlledRelationRestore();

    final selection = _pushPicker(router, _creationChoice(restore));
    await _settleRoute(tester);
    final pickerId = router.current.matchId;
    final summary = testSummary(index: 1, title: 'Высыпаться');
    _completePage(repository, 1, [summary]);
    await tester.pumpAndSettle();
    restore.canContinue = false;

    await tester.tap(intentionPickerArrow(intentionPickerRows.first));
    await _settleRoute(tester);
    expect(
      router.current.argsAs<IntentionDetailsRouteArgs>().intentionId,
      summary.id,
    );
    await router.maybePop();
    await _settleRoute(tester);
    expect(router.current.matchId, pickerId);

    await tester.tap(find.text('New relation: related intention'));
    await tester.pumpAndSettle();
    expect(find.byType(Sheet), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(Sheet), findsNothing);

    await tester.tap(_cancel);
    await tester.pumpAndSettle();
    expect(await selection, isNull);
    expect(find.byType(IntentionPickerView), findsNothing);
  });

  // Заменяемый участник выбираемой роли не исключается.
  for (final (name, choice, pairProbe) in [
    (
      'новой связи без участника другой роли',
      RelationParticipantChoice(
        role: RelationParticipantRole.source,
        flow: testRelationCreationFlow,
        type: null,
        source: _participant(3),
        related: null,
      ),
      null,
    ),
    (
      'активной изменяемой связи',
      RelationParticipantChoice(
        role: RelationParticipantRole.related,
        flow: RelationChangeChoiceFlow(
          relationId: _editedRelation,
          relationScope: RelationScope.active,
        ),
        type: LongTermRelationType.need,
        source: _participant(3),
        related: _participant(4),
      ),
      RelationPairProbe(
        counterpartId: _id(3),
        candidateRole: RelationParticipantRole.related,
        ignoredRelationId: _editedRelation,
      ),
    ),
  ]) {
    testWidgets('описание выбора $name задаёт активный охват и исключение '
        'только другой роли', (tester) async {
      final repository = ControlledParticipantPickerRepository();
      addTearDown(repository.dispose);
      final router = await _pumpAppWithCatalog(tester, repository);
      addTearDown(router.dispose);

      unawaited(_pushPicker(router, choice));
      await _settleRoute(tester);

      final query = repository.queryAt(1);
      expect(query.scope, IntentionScope.active);
      expect(query.pairProbe, pairProbe);
    });
  }
}

/// Описание выбора связанного участника при создании связи с дескриптором
/// [restore].
RelationParticipantChoice _creationChoice(RelationCreationRestore restore) =>
    RelationParticipantChoice(
      role: RelationParticipantRole.related,
      flow: RelationCreationChoiceFlow(
        restore: restore,
        priority: null,
        description: '',
      ),
      type: null,
      source: _participant(_excludedIndex),
      related: null,
    );

/// Завершает переход к выбору участника, не ожидая подтверждённой порции.
///
/// Ожидание первой порции показывает бесконечный индикатор, поэтому кадры
/// перехода продвигаются явно.
Future<void> _settleRoute(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

final _cancel = find.byKey(const ValueKey('participant-picker-cancel'));

Future<GraphSnapshot<RelationParticipantSummary>?> _pushPicker(
  AppRouter router,
  RelationParticipantChoice choice,
) => router.push<GraphSnapshot<RelationParticipantSummary>>(
  RelationParticipantPickerRoute(choice: choice),
);

void _completePage(
  ControlledParticipantPickerRepository repository,
  int index,
  List<IntentionSummary> items, {
  Map<IntentionId, PairOccupant>? pairOccupants,
}) => repository.complete(
  index,
  ResultSuccess(
    IntentionCatalogFirstPage(
      items: items,
      totalCount: items.length,
      nextCursor: null,
      revision: const TestPickerRevision(1),
      pairOccupants: pairOccupants,
    ),
  ),
);

Future<AppRouter> _pumpAppWithCatalog(
  WidgetTester tester,
  ControlledParticipantPickerRepository repository, {
  Locale locale = const Locale('en'),
}) async {
  final router = AppRouter();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        inMemoryQuickCreationModeOverride,
        personalGraphRepositoryProvider.overrideWithValue(repository),
        catalogPagingPolicyProvider.overrideWithValue(
          CatalogPagingPolicy(
            pageSize: 100,
            prefetchRemaining: 30,
            filterDebounce: const Duration(milliseconds: 250),
          ),
        ),
      ],
      retry: (retryCount, error) => null,
      child: MaterialApp.router(
        theme: doableTheme(Brightness.light),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router.config(),
      ),
    ),
  );
  await tester.pump();
  await openIntentionGraph(tester);
  _completePage(repository, 0, [testSummary(index: 1, title: 'Ходить')]);
  await tester.pumpAndSettle();
  return router;
}

/// Проверки охвата, исключения и результата поиска участника по названию и
/// тегам.
void _defineTagSearchTests() {
  testWidgets('поиск для архивированной связи допускает оба состояния, а '
      'выбор возвращает снимок строки с ревизией её выдачи', (tester) async {
    final semantics = tester.ensureSemantics();
    final repository = ControlledCatalogRepository();
    final health = _tag(1, 'Здоровье');
    final sport = _tag(2, 'Спорт');
    final opened = await _openTagSearchPicker(
      tester,
      repository,
      _archivedRelation,
    );
    await _filterByTitle(tester, repository, 'Гулять');
    await _applyConditions(
      tester,
      opened.container,
      repository,
      [
        (health, IntentionTagRequirement.mustBePresent),
        (sport, IntentionTagRequirement.mustBeAbsent),
      ],
      _tagSearchPage([
        testSummary(index: 2, title: 'Гулять', tags: [health]),
        testSummary(
          index: 1,
          title: 'Гулять',
          archiveState: IntentionArchiveState.archived,
          tags: [health],
        ),
      ], revision: 3),
    );
    _expectParticipantQuery(
      repository.queries.last,
      _archivedRelation,
      IntentionTagFilter(
        requiredTagIds: [health.id],
        excludedTagIds: [sport.id],
      ),
      title: 'Гулять',
    );

    expect(intentionPickerRows, findsNWidgets(2));
    expect(
      find.bySemanticsLabel('Гулять, intention, Tags: Здоровье'),
      findsOneWidget,
    );
    const archivedLabel = 'Гулять, archived, intention, Tags: Здоровье';
    expect(find.bySemanticsLabel(archivedLabel), findsOneWidget);

    await tester.tap(find.bySemanticsLabel(archivedLabel));
    await tester.pumpAndSettle();
    expect(
      await opened.selection,
      isA<GraphSnapshot<RelationParticipantSummary>>()
          .having(
            (snapshot) =>
                snapshot.revision.compareTo(const TestCatalogRevision(3)),
            'ревизия выдачи',
            GraphRevisionOrder.same,
          )
          .having((snapshot) => snapshot.value.id, 'идентификатор', _id(1))
          .having((snapshot) => snapshot.value.title, 'название', 'Гулять')
          .having(
            (snapshot) => snapshot.value.archiveState,
            'архивное состояние',
            IntentionArchiveState.archived,
          ),
    );
    _expectNoCommands(repository);
    semantics.dispose();
  });

  testWidgets('совпадение тегов не разрешает самосвязь: второго участника '
      'исключает запрос, а одноимённое намерение выбирается явно', (
    tester,
  ) async {
    final repository = ControlledCatalogRepository();
    final health = _tag(1, 'Здоровье');
    final opened = await _openTagSearchPicker(
      tester,
      repository,
      _activeRelation,
    );
    await _filterByTitle(tester, repository, 'Гулять');
    await _applyConditions(
      tester,
      opened.container,
      repository,
      [(health, IntentionTagRequirement.mustBePresent)],
      // Репозиторий не отдаёт исключённое запросом намерение.
      _tagSearchPage([
        testSummary(index: 2, title: 'Гулять', tags: [health]),
      ]),
    );
    _expectParticipantQuery(
      repository.queries.last,
      _activeRelation,
      IntentionTagFilter(requiredTagIds: [health.id]),
      title: 'Гулять',
    );

    expect(intentionPickerRows, findsOneWidget);
    await tester.tap(
      find.descendant(of: intentionPickerRows, matching: find.text('Гулять')),
    );
    await tester.pumpAndSettle();
    expect((await opened.selection)?.value.id, _id(2));
  });

  testWidgets('кнопка фильтра открывает панель тегов, где условие '
      'добавляется, переключается и снимается с прежними охватом и '
      'исключением, а закрытие ничего не возвращает', (tester) async {
    final choiceCase = _activeRelation;
    final repository = ControlledCatalogRepository();
    final sport = _tag(2, 'Спорт');
    repository.tagCatalogItems = [_tag(1, 'Здоровье'), sport];
    final opened = await _openTagSearchPicker(tester, repository, choiceCase);
    repository.complete(1, _tagSearchPage(_summaries(const [], count: 3)));
    await tester.pumpAndSettle();

    await tester.tap(_filterButton);
    await tester.pumpAndSettle();
    expect(find.text('Filter by tags'), findsOneWidget);
    // Первое нажатие требует тег, второе исключает его.
    await tester.tap(_panelRow(sport));
    await _pumpUntilQueries(tester, repository, 3);
    _expectParticipantQuery(
      repository.queryAt(2),
      choiceCase,
      IntentionTagFilter(requiredTagIds: [sport.id]),
    );
    await tester.tap(_panelRow(sport));
    await _pumpUntilQueries(tester, repository, 4);
    _expectParticipantQuery(
      repository.queryAt(3),
      choiceCase,
      IntentionTagFilter(excludedTagIds: [sport.id]),
    );
    repository.complete(3, _tagSearchPage(_summaries(const [], count: 2)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(opened.router.current.name, RelationParticipantPickerRoute.name);
    expect(tester.widget<FilterButton>(_filterButton).count, 1);
    expect(intentionPickerRows, findsNWidgets(2));

    // Третье нажатие снимает условие.
    await tester.tap(_filterButton);
    await tester.pumpAndSettle();
    await tester.tap(_panelRow(sport));
    await _pumpUntilQueries(tester, repository, 5);
    _expectParticipantQuery(
      repository.queryAt(4),
      choiceCase,
      IntentionTagFilter.empty,
    );
    repository.complete(4, _tagSearchPage(_summaries(const [], count: 3)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilterButton>(_filterButton).count, 0);
    expect(intentionPickerRows, findsNWidgets(3));

    await tester.tap(_cancel);
    await tester.pumpAndSettle();
    expect(await opened.selection, isNull);
    _expectNoCommands(repository);
  });

  testWidgets('отказ новой выдачи после удаления исключённого тега показан '
      'отказом первой порции, а повтор показывает выдачу без его условия с '
      'прежними охватом и исключением', (tester) async {
    final repository = ControlledCatalogRepository();
    final health = _tag(1, 'Здоровье');
    final rest = _tag(2, 'Отдых');
    final remaining = IntentionTagFilter(requiredTagIds: [health.id]);
    final opened = await _openTagSearchPicker(
      tester,
      repository,
      _archivedRelation,
    );
    await _applyConditions(tester, opened.container, repository, [
      (health, IntentionTagRequirement.mustBePresent),
      (rest, IntentionTagRequirement.mustBeAbsent),
    ], _tagSearchPage(_summaries([health], count: 3), revision: 1));
    final restarted = repository.queries.length;

    final accepted = acceptTagCommand(
      opened.container,
      repository,
      DeleteTag(rest.id),
      tagDeletionSuccess(
        tagId: rest.id,
        revision: const TestCatalogRevision(2),
      ),
    );
    await accepted.future;
    await _pumpUntilQueries(tester, repository, restarted + 1);
    _expectParticipantQuery(
      repository.queryAt(restarted),
      _archivedRelation,
      remaining,
    );
    repository.complete(
      restarted,
      const ResultFailure(IntentionUnavailableFailure()),
    );
    await tester.pumpAndSettle();

    const message = 'Intentions couldn’t be loaded. Try again.';
    expect(find.text(message), findsOneWidget);
    expect(intentionPickerRows, findsNothing);

    await tester.tap(find.text('Try again'));
    await _pumpUntilQueries(tester, repository, restarted + 2);
    _expectParticipantQuery(
      repository.queryAt(restarted + 1),
      _archivedRelation,
      remaining,
    );
    repository.complete(
      restarted + 1,
      _tagSearchPage(_summaries([health], count: 4), revision: 2),
    );
    await tester.pumpAndSettle();

    expect(find.text(message), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is CatalogHeader &&
            widget.title == 'All' &&
            widget.count == 4,
      ),
      findsOneWidget,
    );
    expect(intentionPickerRows, findsNWidgets(4));
    _expectNoCommands(repository, tagCommands: 1);
  });
}

/// Индекс намерения, уже занятого вторым участником связи.
const _excludedIndex = 9;

final _editedRelation = testFormRelationId(1);

/// Описание выбора и ограничения запроса каталога, которые из него следуют.
typedef _ParticipantChoiceCase = ({
  RelationParticipantChoice choice,
  IntentionScope scope,
  RelationPairProbe? pairProbe,
});

/// Новая связь: исходный участник уже выбран и исключается из поиска
/// связанного.
final _ParticipantChoiceCase _activeRelation = (
  choice: RelationParticipantChoice(
    role: RelationParticipantRole.related,
    flow: testRelationCreationFlow,
    type: null,
    source: _participant(_excludedIndex),
    related: null,
  ),
  scope: IntentionScope.active,
  pairProbe: RelationPairProbe(
    counterpartId: _id(_excludedIndex),
    candidateRole: RelationParticipantRole.related,
  ),
);

/// Изменение архивной связи: заменяемый исходный участник остаётся в выдаче,
/// а связанный исключается.
final _ParticipantChoiceCase _archivedRelation = (
  choice: RelationParticipantChoice(
    role: RelationParticipantRole.source,
    flow: RelationChangeChoiceFlow(
      relationId: _editedRelation,
      relationScope: RelationScope.archived,
    ),
    type: LongTermRelationType.can,
    source: _participant(5),
    related: _participant(_excludedIndex),
  ),
  scope: IntentionScope.all,
  pairProbe: RelationPairProbe(
    counterpartId: _id(_excludedIndex),
    candidateRole: RelationParticipantRole.source,
    ignoredRelationId: _editedRelation,
  ),
);

IntentionId _id(int index) => testSummary(index: index).id;

RelationParticipantSummary _participant(int index) {
  final summary = testSummary(index: index);
  return RelationParticipantSummary(
    id: summary.id,
    title: summary.title,
    archiveState: summary.archiveState,
  );
}

typedef _OpenedTagSearchPicker = ({
  ProviderContainer container,
  AppRouter router,
  Future<GraphSnapshot<RelationParticipantSummary>?> selection,
});

/// Открывает выбор участника поверх каталога; запрос 0 принадлежит каталогу,
/// запрос 1 — первой порции страницы выбора.
Future<_OpenedTagSearchPicker> _openTagSearchPicker(
  WidgetTester tester,
  ControlledCatalogRepository repository,
  _ParticipantChoiceCase choiceCase,
) async {
  final container = reconciliationCatalogContainer(repository);
  final router = AppRouter();
  addTearDown(container.dispose);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: doableTheme(Brightness.light),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router.config(),
      ),
    ),
  );
  await tester.pump();
  await openIntentionGraph(tester);
  repository.complete(0, _tagSearchPage(const []));
  await tester.pumpAndSettle();
  final selection = router.push<GraphSnapshot<RelationParticipantSummary>>(
    RelationParticipantPickerRoute(choice: choiceCase.choice),
  );
  await _settleRoute(tester);
  return (container: container, router: router, selection: selection);
}

/// Вводит фильтр названия и отвечает пустой выдачей на его запрос.
Future<void> _filterByTitle(
  WidgetTester tester,
  ControlledCatalogRepository repository,
  String title,
) async {
  final expectedQueries = repository.queries.length + 1;
  await tester.enterText(
    find.byKey(const ValueKey('participant-picker-filter')),
    title,
  );
  await tester.pump(const Duration(milliseconds: 300));
  await _pumpUntilQueries(tester, repository, expectedQueries);
  repository.complete(expectedQueries - 1, _tagSearchPage(const []));
  await tester.pumpAndSettle();
}

/// Передаёт модели условий выбор так же, как его возвращает панель тегов.
/// Каждое условие сразу начинает новую выдачу; [result] отвечает на
/// последнюю.
Future<void> _applyConditions(
  WidgetTester tester,
  ProviderContainer container,
  ControlledCatalogRepository repository,
  List<(Tag, IntentionTagRequirement)> conditions,
  Result<IntentionCatalogFirstPage> result,
) async {
  final model = container.read(
    intentionTagConditionsViewModelProvider(
      tester
          .widget<IntentionPickerView>(find.byType(IntentionPickerView))
          .purpose,
    ).notifier,
  );
  var expectedQueries = repository.queries.length;
  for (final (tag, requirement) in conditions) {
    for (var i = 0; i < tagConditionCycles(requirement); i++) {
      model.cycle(tag, snapshotRevision: const TestCatalogRevision(0));
      expectedQueries++;
      await tester.pump();
    }
  }
  await _pumpUntilQueries(tester, repository, expectedQueries);
  repository.complete(expectedQueries - 1, result);
  await tester.pumpAndSettle();
}

/// Запрос выбора участника сохраняет охват связи и исключение второго
/// участника при любых условиях; готовность поиск не ограничивает.
void _expectParticipantQuery(
  IntentionCatalogQuery query,
  _ParticipantChoiceCase expected,
  IntentionTagFilter tagFilter, {
  String? title,
}) {
  expect(query.scope, expected.scope);
  expect(query.readinessFilter, IntentionReadinessFilter.all);
  expect(query.pairProbe, expected.pairProbe);
  expect(query.titleFilter?.map((value) => value), title);
  expect(query.tagFilter, tagFilter);
  expect(query.cursor, isNull);
}

/// Поиск и изменение условий не выполняют команд графа: связь и назначения
/// остаются прежними.
void _expectNoCommands(
  ControlledCatalogRepository repository, {
  int tagCommands = 0,
}) {
  expect(repository.tagCommands, hasLength(tagCommands));
  expect(repository.commands, isEmpty);
  expect(repository.relationCommands, isEmpty);
  expect(repository.dailyChoiceCommands, isEmpty);
}

final _filterButton = find.byType(FilterButton);

Finder _panelRow(Tag tag) =>
    find.byKey(ValueKey('tags-panel-row-${tag.id.toCanonicalString()}'));

Result<IntentionCatalogFirstPage> _tagSearchPage(
  List<IntentionSummary> items, {
  int revision = 0,
}) => ResultSuccess(
  IntentionCatalogFirstPage(
    items: items,
    totalCount: items.length,
    nextCursor: null,
    revision: TestCatalogRevision(revision),
  ),
);

List<IntentionSummary> _summaries(List<Tag> tags, {required int count}) => [
  for (var index = count; index >= 1; index--)
    testSummary(index: index, title: 'Намерение $index', tags: tags),
];

Tag _tag(int index, String name) => Tag(
  id: switch (TagId.decode(
    '00000000-0000-4000-8000-${index.toString().padLeft(12, '0')}',
  )) {
    TagIdDecodingSuccess(:final id) => id,
    InvalidTagIdDecoding() => throw StateError(
      'Некорректный идентификатор тега в тесте.',
    ),
  },
  name: TagName.fromInput(name),
  color: null,
  position: tagPositionAt(index),
);

Future<void> _pumpUntilQueries(
  WidgetTester tester,
  ControlledCatalogRepository repository,
  int count,
) async {
  for (var attempt = 0; attempt < 1000; attempt++) {
    await tester.pump(const Duration(milliseconds: 1));
    if (repository.queries.length >= count) {
      return;
    }
  }
  fail('Не дождались $count запросов каталога.');
}

/// Занимающая связь строки «Плавать» в проверках восстановления.
final _archivedOccupant = testFormRelationId(5);

/// Поиск при создании связи со строкой «Плавать», пару которой занимает
/// архивная связь, и свободной строкой «Высыпаться».
typedef _RestoreOffer = ({
  ControlledParticipantPickerRepository repository,
  AppRouter router,
  ControlledRelationRestore restore,
  LocalKey pickerId,
  bool Function() selectionCompleted,
});

Future<_RestoreOffer> _openRestoreOffer(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
}) async {
  final repository = ControlledParticipantPickerRepository();
  addTearDown(repository.dispose);
  final router = await _pumpAppWithCatalog(tester, repository, locale: locale);
  addTearDown(router.dispose);
  final restore = ControlledRelationRestore();
  var selectionCompleted = false;
  unawaited(
    _pushPicker(
      router,
      _creationChoice(restore),
    ).whenComplete(() => selectionCompleted = true),
  );
  await _settleRoute(tester);
  final pickerId = router.current.matchId;
  final occupied = testSummary(index: 2, title: 'Плавать');
  _completePage(
    repository,
    1,
    [occupied, testSummary(index: 1, title: 'Высыпаться')],
    pairOccupants: {
      occupied.id: PairOccupant(
        relationId: _archivedOccupant,
        scope: RelationScope.archived,
      ),
    },
  );
  await tester.pumpAndSettle();
  return (
    repository: repository,
    router: router,
    restore: restore,
    pickerId: pickerId,
    selectionCompleted: () => selectionCompleted,
  );
}

/// Успешное чтение архивной связи «быть здоровым» → «плавать» вида [type].
LongTermRelationReadResult _archivedRelationRead(LongTermRelationType type) =>
    LongTermRelationReadSuccess(
      GraphSnapshot(
        revision: const TestPickerRevision(1),
        value: LongTermRelationDetails(
          relation: LongTermRelation(
            id: _archivedOccupant,
            sourceIntentionId: _id(_excludedIndex),
            relatedIntentionId: _id(2),
            type: type,
            priority: RelationPriority.p2,
            scope: RelationScope.archived,
            creationSequence: RelationCreationSequence(1),
          ),
          source: _named(_excludedIndex, 'быть здоровым'),
          related: _named(2, 'плавать'),
          description: null,
        ),
      ),
    );

/// Предложение восстановить архивную занимающую связь при создании.
void _defineRestoreOfferTests() {
  for (final (language, type, label, title, text, action) in const [
    (
      'ru',
      LongTermRelationType.need,
      'нажатие предложит восстановить связь',
      'Восстановить связь?',
      'Вернётся связь «Чтобы быть здоровым, нужно плавать» с приоритетом P2.',
      'Восстановить',
    ),
    (
      'en',
      LongTermRelationType.can,
      'tapping offers to restore the relation',
      'Restore this relation?',
      'The relation “To быть здоровым, you can плавать” returns with '
          'priority P2.',
      'Restore',
    ),
  ]) {
    testWidgets('$language: строка «Связь в архиве» при создании называет '
        'предложение восстановить связь, подтверждение показывает формулировку '
        'и приоритет, а согласие передаёт связь дескриптору', (tester) async {
      final semantics = tester.ensureSemantics();
      final offer = await _openRestoreOffer(tester, locale: Locale(language));

      expect(find.bySemanticsLabel(RegExp(label)), findsOneWidget);
      await tester.tap(find.text('Плавать'));
      await tester.pump();
      expect(offer.repository.watchedRelations, [_archivedOccupant]);
      offer.repository.answerRelationRead(_archivedRelationRead(type));
      await tester.pumpAndSettle();

      expect(find.text(title), findsOneWidget);
      expect(find.text(text, findRichText: true), findsOneWidget);
      expect(offer.restore.accepted, isEmpty);

      await tester.tap(find.text(action));
      await tester.pumpAndSettle();

      expect(offer.restore.accepted, [_archivedOccupant]);
      expect(find.text(title), findsNothing);
      expect(offer.router.current.matchId, offer.pickerId);
      expect(offer.selectionCompleted(), isFalse);
      semantics.dispose();
    });
  }

  testWidgets('отмена подтверждения возвращает поиск без команды и выбора, а '
      'строка снова предлагает восстановление', (tester) async {
    final offer = await _openRestoreOffer(tester);

    await tester.tap(find.text('Плавать'));
    await tester.pump();
    offer.repository.answerRelationRead(
      _archivedRelationRead(LongTermRelationType.need),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Restore this relation?'), findsNothing);
    expect(offer.restore.accepted, isEmpty);
    expect(offer.router.current.matchId, offer.pickerId);
    expect(offer.selectionCompleted(), isFalse);

    await tester.tap(find.text('Плавать'));
    await tester.pump();
    offer.repository.answerRelationRead(
      _archivedRelationRead(LongTermRelationType.need),
    );
    await tester.pumpAndSettle();
    expect(find.text('Restore this relation?'), findsOneWidget);
  });

  for (final (name, read) in <(String, LongTermRelationReadResult)>[
    (
      'связи больше нет',
      const LongTermRelationReadSuccess(
        GraphSnapshot(revision: TestPickerRevision(1), value: null),
      ),
    ),
    (
      'чтение отказало',
      const LongTermRelationReadError(LongTermRelationReadUnavailableFailure()),
    ),
  ]) {
    testWidgets('если $name, подтверждения нет, а поверх поиска открыт '
        'подробный просмотр этой связи', (tester) async {
      final offer = await _openRestoreOffer(tester);

      await tester.tap(find.text('Плавать'));
      await tester.pump();
      offer.repository.answerRelationRead(read);
      await _settleRoute(tester);

      expect(find.text('Restore this relation?'), findsNothing);
      expect(
        offer.router.current.argsAs<RelationDetailsRouteArgs>().relationId,
        _archivedOccupant,
      );
      expect(
        offer.router.stackData[offer.router.stackData.length - 2].matchId,
        offer.pickerId,
      );
      expect(offer.restore.accepted, isEmpty);
    });
  }

  testWidgets('ответ чтения после закрытия поиска не открывает ни '
      'подтверждения, ни связи', (tester) async {
    final offer = await _openRestoreOffer(tester);

    await tester.tap(find.text('Плавать'));
    await tester.pump();
    await tester.tap(_cancel);
    await tester.pumpAndSettle();
    expect(offer.selectionCompleted(), isTrue);

    offer.repository.answerRelationRead(
      _archivedRelationRead(LongTermRelationType.need),
    );
    await tester.pumpAndSettle();

    expect(find.text('Restore this relation?'), findsNothing);
    expect(offer.router.current.name, isNot(RelationDetailsRoute.name));
  });

  testWidgets('ответ чтения под страницей поверх поиска ничего не открывает, а '
      'после возврата строка снова предлагает восстановление', (tester) async {
    final offer = await _openRestoreOffer(tester);

    await tester.tap(find.text('Плавать'));
    await tester.pump();
    await tester.tap(intentionPickerArrow(intentionPickerRows.first));
    await _settleRoute(tester);
    offer.repository.answerRelationRead(
      _archivedRelationRead(LongTermRelationType.need),
    );
    await _settleRoute(tester);

    expect(find.text('Restore this relation?'), findsNothing);
    expect(find.byType(IntentionDetailsPage), findsOneWidget);

    await offer.router.maybePop();
    await _settleRoute(tester);
    expect(offer.router.current.matchId, offer.pickerId);
    await tester.tap(find.text('Плавать'));
    await tester.pump();
    offer.repository.answerRelationRead(
      _archivedRelationRead(LongTermRelationType.need),
    );
    await tester.pumpAndSettle();
    expect(find.text('Restore this relation?'), findsOneWidget);
  });

  testWidgets('ответ чтения под листом назначения ничего не открывает', (
    tester,
  ) async {
    final offer = await _openRestoreOffer(tester);

    await tester.tap(find.text('Плавать'));
    await tester.pump();
    await tester.tap(find.text('New relation: related intention'));
    await tester.pumpAndSettle();
    offer.repository.answerRelationRead(
      _archivedRelationRead(LongTermRelationType.need),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Sheet), findsOneWidget);
    expect(find.text('Restore this relation?'), findsNothing);
    expect(offer.router.current.matchId, offer.pickerId);
  });

  testWidgets('пока поток создания не может продолжаться, строка «Связь в '
      'архиве» не предлагает восстановление', (tester) async {
    final offer = await _openRestoreOffer(tester);
    offer.restore.canContinue = false;

    await tester.tap(find.text('Плавать'));
    await tester.pumpAndSettle();

    expect(offer.repository.watchedRelations, isEmpty);
    expect(offer.router.current.matchId, offer.pickerId);
  });

  testWidgets('повторное нажатие до ответа чтения не открывает второго '
      'подтверждения', (tester) async {
    final offer = await _openRestoreOffer(tester);

    await tester.tap(find.text('Плавать'));
    await tester.tap(find.text('Плавать'));
    await tester.pump();
    expect(offer.repository.watchedRelations, [_archivedOccupant]);

    offer.repository.answerRelationRead(
      _archivedRelationRead(LongTermRelationType.need),
    );
    await tester.pumpAndSettle();
    expect(find.text('Restore this relation?'), findsOneWidget);
  });
}

/// Назначение поиска участника на одном языке: подзаголовок с отметкой роли,
/// строка листа, строка о выбираемой роли и узлы формы связи для диктора.
typedef _PurposeCase = ({
  String name,
  RelationParticipantChoice choice,
  Map<String, _PurposeTexts> texts,
  PathGlyphShape mark,
});

typedef _PurposeTexts = ({
  String subtitle,
  String sheetLine,
  String roleNote,
  String sourceField,
  String relatedField,
  String kind,
});

const _longSource =
    'Сохранить тело функциональным, чтобы в шестьдесят лет ходить в горы с '
    'рюкзаком';

RelationParticipantSummary _named(
  int index,
  String title, {
  IntentionArchiveState archiveState = IntentionArchiveState.active,
}) => RelationParticipantSummary(
  id: _id(index),
  title: title,
  archiveState: archiveState,
);

final List<_PurposeCase> _purposeCases = [
  (
    name: 'лист показывает исходное намерение целиком',
    choice: RelationParticipantChoice(
      role: RelationParticipantRole.related,
      flow: testRelationCreationFlow,
      type: LongTermRelationType.need,
      source: _named(3, _longSource),
      related: null,
    ),
    mark: PathGlyphShape.ring,
    texts: {
      'ru': (
        subtitle: 'Новая связь: связанное намерение',
        sheetLine: 'Новая связь',
        roleNote: 'Связанное намерение — то, что нужно для исходного.',
        sourceField: 'Исходное намерение\n$_longSource',
        relatedField: 'Связанное намерение\nСейчас выбирается\nИз этого списка',
        kind: 'Нужно',
      ),
      'en': (
        subtitle: 'New relation: related intention',
        sheetLine: 'New relation',
        roleNote: 'The related intention is what the source intention needs.',
        sourceField: 'Source intention\n$_longSource',
        relatedField: 'Related intention\nChoosing now\nFrom this list',
        kind: 'Need',
      ),
    },
  ),
  (
    name: 'изменение связи показывает заменяемого участника',
    choice: RelationParticipantChoice(
      role: RelationParticipantRole.related,
      flow: RelationChangeChoiceFlow(
        relationId: _editedRelation,
        relationScope: RelationScope.active,
      ),
      type: LongTermRelationType.need,
      source: _named(3, 'Быть здоровым'),
      related: _named(4, 'много ходить'),
    ),
    mark: PathGlyphShape.ring,
    texts: {
      'ru': (
        subtitle: 'Изменение связи: связанное намерение',
        sheetLine: 'Изменение связи',
        roleNote: 'Связанное намерение — то, что нужно для исходного.',
        sourceField: 'Исходное намерение\nБыть здоровым',
        relatedField:
            'Связанное намерение\nСейчас выбирается\nВместо: много ходить',
        kind: 'Нужно',
      ),
      'en': (
        subtitle: 'Relation change: related intention',
        sheetLine: 'Relation change',
        roleNote: 'The related intention is what the source intention needs.',
        sourceField: 'Source intention\nБыть здоровым',
        relatedField:
            'Related intention\nChoosing now\nInstead of: много ходить',
        kind: 'Need',
      ),
    },
  ),
  (
    name: 'выбор исходного при пустом связанном и невыбранном виде',
    choice: const RelationParticipantChoice(
      role: RelationParticipantRole.source,
      flow: testRelationCreationFlow,
      type: null,
      source: null,
      related: null,
    ),
    mark: PathGlyphShape.diamond,
    texts: {
      'ru': (
        subtitle: 'Новая связь: исходное намерение',
        sheetLine: 'Новая связь',
        roleNote:
            'Исходное намерение — то, для чего нужно или можно связанное.',
        sourceField: 'Исходное намерение\nСейчас выбирается\nИз этого списка',
        relatedField: 'Связанное намерение\nЕщё не выбрано',
        kind: 'Нужно или можно: ещё не выбрано',
      ),
      'en': (
        subtitle: 'New relation: source intention',
        sheetLine: 'New relation',
        roleNote:
            'The source intention is what the related intention is needed '
            'for or can be used for.',
        sourceField: 'Source intention\nChoosing now\nFrom this list',
        relatedField: 'Related intention\nNot chosen yet',
        kind: 'Need or can: not chosen yet',
      ),
    },
  ),
  (
    name: 'архивная изменяемая связь с архивным участником',
    choice: RelationParticipantChoice(
      role: RelationParticipantRole.source,
      flow: RelationChangeChoiceFlow(
        relationId: _editedRelation,
        relationScope: RelationScope.archived,
      ),
      type: LongTermRelationType.can,
      source: _named(3, 'Гулять'),
      related: _named(
        _excludedIndex,
        'Бегать',
        archiveState: IntentionArchiveState.archived,
      ),
    ),
    mark: PathGlyphShape.diamond,
    texts: {
      'ru': (
        subtitle: 'Изменение связи: исходное намерение',
        sheetLine: 'Изменение связи',
        roleNote:
            'Исходное намерение — то, для чего нужно или можно связанное.',
        sourceField: 'Исходное намерение\nСейчас выбирается\nВместо: Гулять',
        relatedField: 'Связанное намерение\nБегать\nВ архиве',
        kind: 'Можно',
      ),
      'en': (
        subtitle: 'Relation change: source intention',
        sheetLine: 'Relation change',
        roleNote:
            'The source intention is what the related intention is needed '
            'for or can be used for.',
        sourceField: 'Source intention\nChoosing now\nInstead of: Гулять',
        relatedField: 'Related intention\nБегать\nArchived',
        kind: 'Can',
      ),
    },
  ),
];

/// Подзаголовок и лист «Что вы выбираете» напоминают связь, из формы которой
/// открыт поиск.
void _definePurposeTests() {
  for (final purposeCase in _purposeCases) {
    for (final MapEntry(key: language, value: texts)
        in purposeCase.texts.entries) {
      final ru = language == 'ru';
      testWidgets('$language: ${purposeCase.name} — «${texts.subtitle}» '
          'открывает лист с формой связи только для чтения', (tester) async {
        final semantics = tester.ensureSemantics();
        final repository = ControlledParticipantPickerRepository();
        addTearDown(repository.dispose);
        final router = await _pumpAppWithCatalog(
          tester,
          repository,
          locale: Locale(language),
        );
        addTearDown(router.dispose);

        unawaited(_pushPicker(router, purposeCase.choice));
        await _settleRoute(tester);
        _completePage(repository, 1, const []);
        await tester.pumpAndSettle();

        final subtitle = find.descendant(
          of: find.byType(TopBar),
          matching: find.text(texts.subtitle),
        );
        expect(
          tester.getSemantics(subtitle),
          isSemantics(
            label: ru
                ? 'Выбор намерения. ${texts.subtitle}. Показать, что '
                      'выбирается'
                : 'Choose an intention. ${texts.subtitle}. Show what you are '
                      'choosing',
            isButton: true,
            hasTapAction: true,
            hasExpandedState: true,
            isExpanded: false,
          ),
        );
        final mark = find.descendant(
          of: find.byType(TopBar),
          matching: find.byType(PathGlyph),
        );
        expect(tester.widget<PathGlyph>(mark).shape, purposeCase.mark);

        await tester.tap(subtitle);
        await tester.pumpAndSettle();
        final sheet = find.byType(Sheet);
        Finder inSheet(String text) =>
            find.descendant(of: sheet, matching: find.text(text));
        for (final text in [
          ru ? 'Что вы выбираете' : 'What you are choosing',
          texts.sheetLine,
          texts.roleNote,
        ]) {
          expect(inSheet(text), findsOneWidget);
        }
        // Узел каждого поля называет роль, состояние и участника словами;
        // нажать его нельзя.
        for (final label in [texts.sourceField, texts.relatedField]) {
          expect(
            tester.getSemantics(find.bySemanticsLabel(label)),
            isSemantics(label: label, hasTapAction: false),
          );
        }
        expect(
          tester.getSemantics(inSheet(texts.kind)),
          isSemantics(label: texts.kind, hasTapAction: false),
        );
        semantics.dispose();
      });
    }
  }

  testWidgets('название исходного участника в листе показано целиком', (
    tester,
  ) async {
    final repository = ControlledParticipantPickerRepository();
    addTearDown(repository.dispose);
    final router = await _pumpAppWithCatalog(tester, repository);
    addTearDown(router.dispose);

    unawaited(_pushPicker(router, _purposeCases.first.choice));
    await _settleRoute(tester);
    _completePage(repository, 1, const []);
    await tester.pumpAndSettle();
    await tester.tap(find.text('New relation: related intention'));
    await tester.pumpAndSettle();

    final name = find.descendant(
      of: find.byType(Sheet),
      matching: find.text(_longSource),
    );
    expect(tester.renderObject<RenderParagraph>(name).didExceedMaxLines, false);
  });

  testWidgets('архивный участник приглушён, а запрос каталога сохраняет '
      'полный охват и исключение', (tester) async {
    final repository = ControlledParticipantPickerRepository();
    addTearDown(repository.dispose);
    final router = await _pumpAppWithCatalog(tester, repository);
    addTearDown(router.dispose);

    unawaited(_pushPicker(router, _purposeCases.last.choice));
    await _settleRoute(tester);
    final query = repository.queryAt(1);
    expect(query.scope, IntentionScope.all);
    expect(query.pairProbe?.counterpartId, _id(_excludedIndex));
    _completePage(repository, 1, const []);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Relation change: source intention'));
    await tester.pumpAndSettle();

    final archived = find.descendant(
      of: find.byType(Sheet),
      matching: find.text('Бегать'),
    );
    final colors = Theme.of(tester.element(archived))
        .extension<DoableColors>()!;
    expect(tester.widget<Text>(archived).style?.color, colors.muted);
  });

  testWidgets('подробные данные намерения не показывают подзаголовок, а после '
      'возврата он снова на месте', (tester) async {
    final repository = ControlledParticipantPickerRepository();
    addTearDown(repository.dispose);
    final router = await _pumpAppWithCatalog(tester, repository);
    addTearDown(router.dispose);

    unawaited(_pushPicker(router, _activeRelation.choice));
    await _settleRoute(tester);
    final pickerId = router.current.matchId;
    _completePage(repository, 1, [testSummary(index: 1, title: 'Позвонить')]);
    await tester.pumpAndSettle();
    final subtitle = find.text('New relation: related intention');
    expect(subtitle, findsOneWidget);

    await tester.tap(intentionPickerArrow(intentionPickerRows.first));
    await _settleRoute(tester);
    expect(find.byType(IntentionDetailsPage), findsOneWidget);
    expect(subtitle, findsNothing);

    await router.maybePop();
    await _settleRoute(tester);
    expect(router.current.matchId, pickerId);
    expect(subtitle, findsOneWidget);
  });

  testWidgets('экран с подзаголовком и открытый лист назначения доступны '
      'для нажатия и контрастны', (tester) async {
    final semantics = tester.ensureSemantics();
    final repository = ControlledParticipantPickerRepository();
    addTearDown(repository.dispose);
    final router = await _pumpAppWithCatalog(tester, repository);
    addTearDown(router.dispose);

    unawaited(_pushPicker(router, _purposeCases.last.choice));
    await _settleRoute(tester);
    _completePage(repository, 1, const []);
    await tester.pumpAndSettle();

    for (final open in [false, true]) {
      if (open) {
        await tester.tap(find.text('Relation change: source intention'));
        await tester.pumpAndSettle();
        expect(find.byType(Sheet), findsOneWidget);
      }
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
    }
    semantics.dispose();
  });
}
