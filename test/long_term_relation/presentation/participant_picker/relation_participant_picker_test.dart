import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_catalog.dart'
    hide IntentionCatalogPage;
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/catalog/catalog_paging_policy.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_tag_conditions_section.dart';
import 'package:doable/src/intention/presentation/catalog/intention_tag_conditions_view_model.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/intention_summary_view.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../intention/presentation/catalog/catalog_reconciliation_test_support.dart';
import '../../../intention/presentation/catalog/catalog_test_support.dart'
    show ControlledCatalogRepository, TestCatalogRevision, testSummary;
import '../../../support/app_root_pages.dart';
import '../../../support/inline_text.dart';
import 'participant_picker_test_support.dart';

import '../../../support/in_memory_quick_creation_mode_store.dart';
import '../../../support/tag_positions.dart';
import '../../../support/tag_condition_cycles.dart';

void main() {
  _defineTagSearchTests();

  testWidgets(
    'для архивной связи выбирает активные и архивированные намерения',
    (tester) async {
      final repository = ControlledParticipantPickerRepository();
      addTearDown(repository.dispose);
      final router = await _pumpAppWithCatalog(tester, repository);
      addTearDown(router.dispose);

      final selection = _pushPicker(
        router,
        excludedIndex: 9,
        selectionContext: RelationParticipantSelectionContext.archivedRelation,
      );
      await _settleRoute(tester);

      expect(repository.queryAt(1).scope, IntentionScope.all);
      _completePage(repository, 1, [
        testSummary(index: 1, title: 'Активное'),
        testSummary(
          index: 2,
          title: 'Архивное',
          archiveState: IntentionArchiveState.archived,
        ),
      ]);
      await tester.pumpAndSettle();

      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Archived'), findsOneWidget);
      await tester.tap(find.text('Архивное'));
      await tester.pumpAndSettle();

      expect(
        await selection,
        isA<GraphSnapshot<RelationParticipantSummary>>()
            .having(
              (snapshot) => snapshot.value.id,
              'идентификатор',
              _testIntentionId(2),
            )
            .having(
              (snapshot) => snapshot.value.archiveState,
              'архивное состояние',
              IntentionArchiveState.archived,
            ),
      );
    },
  );

  testWidgets('применяет буквальный фильтр названия к тому же каталогу', (
    tester,
  ) async {
    final repository = ControlledParticipantPickerRepository();
    addTearDown(repository.dispose);
    final router = await _pumpAppWithCatalog(tester, repository);
    addTearDown(router.dispose);

    unawaited(_pushPicker(router, excludedIndex: 9));
    await _settleRoute(tester);
    _completePage(repository, 1, [testSummary(index: 1, title: 'Ходить')]);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('participant-picker-filter-field')),
      '100%',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(repository.queries, hasLength(3));
    expect(repository.queryAt(2).titleFilter?.map((value) => value), '100%');
    expect(repository.queryAt(2).scope, IntentionScope.active);
  });

  for (final (language, markLabel) in [('en', 'Favorite intention')]) {
    testWidgets('$language: одноимённые участники показаны без отметки '
        'избранного и выбираются по идентификатору', (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = ControlledParticipantPickerRepository();
      addTearDown(repository.dispose);
      final router = await _pumpAppWithCatalog(
        tester,
        repository,
        locale: Locale(language),
      );
      addTearDown(router.dispose);

      final selection = _pushPicker(router, excludedIndex: 9);
      await _settleRoute(tester);
      expect(repository.queryAt(1).titleFilter, isNull);
      expect(repository.queryAt(1).tagFilter, IntentionTagFilter.empty);
      _completePage(repository, 1, [
        testSummary(index: 1, title: 'Гулять'),
        testSummary(index: 2, title: 'Гулять'),
      ]);
      await tester.pumpAndSettle();

      final rows = find.byType(IntentionSummaryView);
      expect(rows, findsNWidgets(2));
      expect(find.byIcon(Icons.star), findsNothing);
      expect(tester.getSemantics(rows.at(0)).label, isNot(contains(markLabel)));
      expect(tester.getSemantics(rows.at(1)).label, isNot(contains(markLabel)));

      expect(find.byIcon(Icons.star_border), findsNothing);
      expect(find.text(markLabel), findsNothing);
      expect(find.byTooltip(markLabel), findsNothing);

      // Выбор по-прежнему возвращает участника строки по идентификатору.
      await tester.tap(find.text('Гулять').first);
      await tester.pumpAndSettle();
      expect(
        await selection,
        isA<GraphSnapshot<RelationParticipantSummary>>().having(
          (snapshot) => snapshot.value.id,
          'идентификатор',
          _testIntentionId(1),
        ),
      );

      semantics.dispose();
    });
  }

  testWidgets('открывает подробные данные намерения без завершения выбора', (
    tester,
  ) async {
    final repository = ControlledParticipantPickerRepository();
    addTearDown(repository.dispose);
    final router = await _pumpAppWithCatalog(tester, repository);
    addTearDown(router.dispose);

    var selectionCompleted = false;
    final selection = _pushPicker(router, excludedIndex: 9)
      ..whenComplete(() => selectionCompleted = true);
    await _settleRoute(tester);
    _completePage(repository, 1, [
      testSummary(index: 1, title: 'Позвонить'),
      testSummary(index: 2, title: 'Позвонить'),
    ]);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open intention details').first);
    await _settleRoute(tester);

    expect(find.byType(IntentionDetailsPage), findsOneWidget);
    expect(selectionCompleted, isFalse);

    await router.maybePop();
    await _settleRoute(tester);
    await tester.tap(find.text('Позвонить').first);
    await tester.pumpAndSettle();

    final selected = await selection;
    expect(selected?.value.id, _testIntentionId(1));
    expect(selected?.value.title, 'Позвонить');
  });

  testWidgets('возвращает идентичность и снимок после явного выбора', (
    tester,
  ) async {
    final repository = ControlledParticipantPickerRepository();
    addTearDown(repository.dispose);
    final router = await _pumpAppWithCatalog(tester, repository);
    addTearDown(router.dispose);

    final selection = _pushPicker(router, excludedIndex: 9);
    await _settleRoute(tester);
    _completePage(repository, 1, [
      testSummary(index: 1, title: 'Быть здоровым'),
      testSummary(index: 2, title: 'Много ходить'),
    ]);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Много ходить'));
    await tester.pumpAndSettle();

    expect(
      await selection,
      isA<GraphSnapshot<RelationParticipantSummary>>()
          .having(
            (snapshot) =>
                snapshot.revision.compareTo(const TestPickerRevision(1)),
            'ревизия каталога',
            GraphRevisionOrder.same,
          )
          .having(
            (snapshot) => snapshot.value.id,
            'идентификатор',
            _testIntentionId(2),
          )
          .having(
            (snapshot) => snapshot.value.title,
            'название снимка',
            'Много ходить',
          ),
    );
  });

  testWidgets('отмена возвращает пустой результат', (tester) async {
    final repository = ControlledParticipantPickerRepository();
    addTearDown(repository.dispose);
    final router = await _pumpAppWithCatalog(tester, repository);
    addTearDown(router.dispose);

    final selection = _pushPicker(router, excludedIndex: 9);
    await _settleRoute(tester);
    _completePage(repository, 1, [testSummary(index: 1, title: 'Ходить')]);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('participant-picker-cancel')));
    await tester.pumpAndSettle();

    expect(await selection, isNull);
  });

  testWidgets('архивный выбор подгружает следующую порцию полного каталога', (
    tester,
  ) async {
    final repository = ControlledParticipantPickerRepository();
    addTearDown(repository.dispose);
    final router = await _pumpAppWithCatalog(
      tester,
      repository,
      pageSize: 2,
      prefetchRemaining: 1,
    );
    addTearDown(router.dispose);

    unawaited(
      _pushPicker(
        router,
        excludedIndex: 9,
        selectionContext: RelationParticipantSelectionContext.archivedRelation,
      ),
    );
    await _settleRoute(tester);
    repository.complete(
      1,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: [
            testSummary(index: 1, title: 'Первое'),
            testSummary(index: 2, title: 'Второе'),
          ],
          totalCount: 3,
          nextCursor: const TestPickerCursor(),
          revision: const TestPickerRevision(1),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.queries, hasLength(3));
    expect(repository.queryAt(2).cursor, isNotNull);
    expect(repository.queryAt(2).pageSize, 2);
    expect(repository.queryAt(2).scope, IntentionScope.all);

    repository.complete(
      2,
      ResultSuccess(
        IntentionCatalogContinuationPage(
          items: [
            testSummary(
              index: 3,
              title: 'Третье архивное',
              archiveState: IntentionArchiveState.archived,
            ),
          ],
          nextCursor: null,
          revision: const TestPickerRevision(1),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Третье архивное'), findsOneWidget);
    expect(find.text('Archived'), findsOneWidget);
  });

  testWidgets('предлагает повторить получение после устранимой ошибки', (
    tester,
  ) async {
    final repository = ControlledParticipantPickerRepository();
    addTearDown(repository.dispose);
    final router = await _pumpAppWithCatalog(tester, repository);
    addTearDown(router.dispose);

    unawaited(_pushPicker(router, excludedIndex: 9));
    await _settleRoute(tester);
    repository.complete(1, const ResultFailure(IntentionUnavailableFailure()));
    await tester.pumpAndSettle();

    expect(
      find.text('Intentions couldn’t be loaded. Try again.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump();

    expect(repository.queries, hasLength(3));
  });

  testWidgets('показывает выбор участника на русском языке', (tester) async {
    final repository = ControlledParticipantPickerRepository();
    addTearDown(repository.dispose);
    final router = await _pumpAppWithCatalog(
      tester,
      repository,
      locale: const Locale('ru'),
    );
    addTearDown(router.dispose);

    unawaited(_pushPicker(router, excludedIndex: 1));
    await _settleRoute(tester);
    _completePage(repository, 1, [testSummary(index: 1, title: 'Ходить')]);
    await tester.pumpAndSettle();

    expect(find.text('Выбор участника'), findsOneWidget);
    expect(find.text('Других намерений для выбора нет.'), findsOneWidget);
  });

  testWidgets('сохраняет выбор доступным', (tester) async {
    final repository = ControlledParticipantPickerRepository();
    addTearDown(repository.dispose);
    final router = await _pumpAppWithCatalog(tester, repository);
    addTearDown(router.dispose);

    final selection = _pushPicker(router, excludedIndex: 9);
    await _settleRoute(tester);
    _completePage(repository, 1, [testSummary(index: 1, title: 'Ходить')]);
    await tester.pumpAndSettle();

    expect(find.text('Ходить'), findsOneWidget);
    await tester.tap(find.text('Ходить'));
    await tester.pumpAndSettle();

    expect((await selection)?.value.id, _testIntentionId(1));
  });

  testWidgets('сообщает экранному диктору назначение выбора и перехода', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final repository = ControlledParticipantPickerRepository();
    addTearDown(repository.dispose);
    final router = await _pumpAppWithCatalog(tester, repository);
    addTearDown(router.dispose);

    unawaited(_pushPicker(router, excludedIndex: 9));
    await _settleRoute(tester);
    _completePage(repository, 1, [testSummary(index: 1, title: 'Ходить')]);
    await tester.pumpAndSettle();

    final option = tester.getSemantics(find.byType(IntentionSummaryView));
    expect(option.label, contains('Ходить'));
    expect(option.hint, 'Selects this intention as a relation participant');
    final details = tester.getSemantics(
      find.byTooltip('Open intention details'),
    );
    expect(details.tooltip, 'Open intention details');
    expect(details.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    handle.dispose();
  });
}

/// Завершает переход к выбору участника, не ожидая подтверждённой порции.
///
/// Ожидание первой порции показывает бесконечный индикатор, поэтому кадры
/// перехода продвигаются явно.
Future<void> _settleRoute(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

IntentionId _testIntentionId(int index) => testSummary(index: index).id;

Future<GraphSnapshot<RelationParticipantSummary>?> _pushPicker(
  AppRouter router, {
  required int excludedIndex,
  RelationParticipantSelectionContext selectionContext =
      RelationParticipantSelectionContext.activeRelation,
}) => router.push<GraphSnapshot<RelationParticipantSummary>>(
  RelationParticipantPickerRoute(
    excludedIntentionId: _testIntentionId(excludedIndex),
    selectionContext: selectionContext,
  ),
);

void _completePage(
  ControlledParticipantPickerRepository repository,
  int index,
  List<IntentionSummary> items,
) => repository.complete(
  index,
  ResultSuccess(
    IntentionCatalogFirstPage(
      items: items,
      totalCount: items.length,
      nextCursor: null,
      revision: const TestPickerRevision(1),
    ),
  ),
);

Future<AppRouter> _pumpAppWithCatalog(
  WidgetTester tester,
  ControlledParticipantPickerRepository repository, {
  Locale locale = const Locale('en'),
  int pageSize = 100,
  int prefetchRemaining = 30,
}) async {
  final router = AppRouter();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        inMemoryQuickCreationModeOverride,
        personalGraphRepositoryProvider.overrideWithValue(repository),
        catalogPagingPolicyProvider.overrideWithValue(
          CatalogPagingPolicy(
            pageSize: pageSize,
            prefetchRemaining: prefetchRemaining,
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

/// Проверки подключения поиска по тегам к странице выбора участника.
void _defineTagSearchTests() {
  // Охват архивированной связи проверяет отказ обновления ниже.
  testWidgets('для активной связи условие добавляется в панели тегов, '
      'переключается и снимается с прежним охватом, а отмена ничего не '
      'возвращает', (tester) async {
    final purpose = _activeRelation;
    final repository = ControlledCatalogRepository();
    final health = _tag(1, 'Здоровье');
    final sport = _tag(2, 'Спорт');
    repository.tagCatalogItems = [health, sport];
    final opened = await _openTagSearchPicker(tester, repository, purpose);
    repository.complete(1, _tagSearchPage(_summaries(const [], count: 3)));
    await tester.pumpAndSettle();

    await tester.tap(_addCondition);
    await tester.pumpAndSettle();
    expect(find.text('Filter by tags'), findsOneWidget);
    // Первое нажатие требует тег, второе исключает его.
    await tester.tap(_panelRow(sport));
    await _pumpUntilQueries(tester, repository, 3);
    _expectParticipantQuery(
      repository.queryAt(2),
      purpose,
      IntentionTagFilter(requiredTagIds: [sport.id]),
    );
    await tester.tap(_panelRow(sport));
    await _pumpUntilQueries(tester, repository, 4);
    _expectParticipantQuery(
      repository.queryAt(3),
      purpose,
      IntentionTagFilter(excludedTagIds: [sport.id]),
    );
    repository.complete(3, _tagSearchPage(_summaries([health], count: 2)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(opened.router.current.name, RelationParticipantPickerRoute.name);
    expect(_shownConditions(tester), ['not Спорт']);
    expect(findTextIgnoringInlineWidgets('Tags: Здоровье'), findsNWidgets(2));

    await tester.tap(_conditionToggle(sport));
    await _pumpUntilQueries(tester, repository, 5);
    _expectParticipantQuery(
      repository.queryAt(4),
      purpose,
      IntentionTagFilter(requiredTagIds: [sport.id]),
    );
    repository.complete(4, _tagSearchPage(_summaries([sport], count: 1)));
    await tester.pumpAndSettle();
    expect(_shownConditions(tester), ['Спорт']);
    expect(findTextIgnoringInlineWidgets('Tags: Спорт'), findsOneWidget);

    await tester.tap(_conditionRemove(sport));
    await _pumpUntilQueries(tester, repository, 6);
    _expectParticipantQuery(
      repository.queryAt(5),
      purpose,
      IntentionTagFilter.empty,
    );
    repository.complete(5, _tagSearchPage(_summaries(const [], count: 3)));
    await tester.pumpAndSettle();
    expect(_shownConditions(tester), isEmpty);
    expect(find.text('No tags'), findsNWidgets(3));

    await tester.tap(find.byKey(const ValueKey('participant-picker-cancel')));
    await tester.pumpAndSettle();
    expect(await opened.selection, isNull);
    _expectNoCommands(repository);
  });

  testWidgets('пустая выдача при условиях по тегам сообщает об '
      'отсутствии совпадений по условиям, а не о пустом охвате', (
    tester,
  ) async {
    const byConditions = 'No intentions match the tag conditions.';
    const byScope = 'No other intentions are available to select.';
    final repository = ControlledCatalogRepository();
    final opened = await _openTagSearchPicker(
      tester,
      repository,
      _activeRelation,
    );
    repository.complete(1, _tagSearchPage(const []));
    await tester.pumpAndSettle();
    expect(find.text(byScope), findsOneWidget);
    expect(find.text(byConditions), findsNothing);

    await _applyConditions(
      tester,
      opened.container,
      repository,
      _activeRelation,
      [(_tag(1, 'Здоровье'), IntentionTagRequirement.mustBePresent)],
      _tagSearchPage(const []),
    );

    expect(find.text(byConditions), findsOneWidget);
    expect(find.text(byScope), findsNothing);
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
    await _applyConditions(
      tester,
      opened.container,
      repository,
      _archivedRelation,
      [
        (health, IntentionTagRequirement.mustBePresent),
        (rest, IntentionTagRequirement.mustBeAbsent),
      ],
      _tagSearchPage(_summaries([health], count: 3), revision: 1),
    );
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

    final message = find.text('Intentions couldn’t be loaded. Try again.');
    expect(message, findsOneWidget);
    expect(find.byType(IntentionSummaryView), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
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

    expect(message, findsNothing);
    expect(find.byType(IntentionSummaryView), findsNWidgets(4));
    _expectNoCommands(repository, tagCommands: 1);
  });
}

/// Индекс намерения, уже занятого вторым участником связи.
const _excludedIndex = 9;

final _activeRelation = SelectRelationParticipant(
  session: IntentionSearchSession(),
  excludedIntentionId: _testIntentionId(_excludedIndex),
  selectionContext: RelationParticipantSelectionContext.activeRelation,
);

final _archivedRelation = SelectRelationParticipant(
  session: IntentionSearchSession(),
  excludedIntentionId: _testIntentionId(_excludedIndex),
  selectionContext: RelationParticipantSelectionContext.archivedRelation,
);

RelationParticipantPickerRoute _participantRoute(
  SelectRelationParticipant purpose,
) => RelationParticipantPickerRoute(
  excludedIntentionId: purpose.excludedIntentionId,
  selectionContext: purpose.selectionContext,
);

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
  SelectRelationParticipant purpose,
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
    _participantRoute(purpose),
  );
  await _settleRoute(tester);
  return (container: container, router: router, selection: selection);
}

/// Передаёт модели условий выбор так же, как его возвращает экран поиска
/// тега. Каждое условие сразу начинает новую выдачу; [result] отвечает на
/// последнюю.
Future<void> _applyConditions(
  WidgetTester tester,
  ProviderContainer container,
  ControlledCatalogRepository repository,
  SelectRelationParticipant purpose,
  List<(Tag, IntentionTagRequirement)> conditions,
  Result<IntentionCatalogFirstPage> result,
) async {
  final model = container.read(
    intentionTagConditionsViewModelProvider(
      tester
          .widget<IntentionTagConditionsSection>(
            find.byType(IntentionTagConditionsSection),
          )
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
  SelectRelationParticipant purpose,
  IntentionTagFilter tagFilter,
) {
  expect(query.scope, purpose.selectionContext.catalogScope);
  expect(query.readinessFilter, IntentionReadinessFilter.all);
  expect(query.excludedIntentionId, purpose.excludedIntentionId);
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

final _addCondition = find.byKey(
  const ValueKey('intention-tag-conditions-add'),
);

Finder _conditionToggle(Tag tag) => find.byKey(
  ValueKey('intention-tag-condition-toggle-${tag.id.toCanonicalString()}'),
);

Finder _conditionRemove(Tag tag) => find.byKey(
  ValueKey('intention-tag-condition-remove-${tag.id.toCanonicalString()}'),
);

Finder _panelRow(Tag tag) =>
    find.byKey(ValueKey('tags-panel-row-${tag.id.toCanonicalString()}'));

/// Тексты чипов раздела условий в порядке показа.
List<String> _shownConditions(WidgetTester tester) => [
  for (final text in tester.widgetList<Text>(
    find.descendant(
      of: find.byType(IntentionTagConditionsSection),
      matching: find.byKey(const ValueKey('intention-tag-condition-label')),
    ),
  ))
    textIgnoringInlineWidgets(text),
];

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
