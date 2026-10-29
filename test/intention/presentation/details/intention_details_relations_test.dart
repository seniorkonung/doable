import 'dart:async';
import 'dart:ui' show CheckedState;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/design_system/components/archived_fold.dart';
import 'package:doable/src/design_system/components/option_tiles.dart';
import 'package:doable/src/design_system/components/top_bar.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/details/intention_page_target.dart';
import 'package:doable/src/long_term_relation/application/intention_relation_group.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/presentation/editor/relation_editor_page.dart';
import 'package:doable/src/long_term_relation/presentation/editor/relation_editor_state.dart';
import 'package:doable/src/long_term_relation/presentation/relation_group_paging_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/in_memory_quick_creation_mode_store.dart';
import 'details_test_support.dart';

void main() {
  for (final (scenario, readiness, group) in [
    (
      'Открытие намерения загружает только активную группу «нужно»',
      IntentionReadiness.notReady,
      IntentionRelationGroup.needs,
    ),
    (
      'Действие открывает группу «Нужно для»',
      IntentionReadiness.ready,
      IntentionRelationGroup.neededFor,
    ),
  ]) {
    _testWidgets(scenario, (tester) async {
      final graph = _Graph();
      final owner = graph.addIntention(1, 'Быть здоровым', readiness);
      for (final (index, type, direction, scope) in [
        (1, LongTermRelationType.need, RelationDirection.outgoing, null),
        (2, LongTermRelationType.can, RelationDirection.outgoing, null),
        (3, LongTermRelationType.can, RelationDirection.outgoing, null),
        (4, LongTermRelationType.need, RelationDirection.incoming, null),
        (
          5,
          LongTermRelationType.need,
          RelationDirection.outgoing,
          RelationScope.archived,
        ),
      ]) {
        graph.addRelation(
          owner,
          index: index,
          type: type,
          direction: direction,
          scope: scope ?? RelationScope.active,
        );
      }
      await _openPage(tester, graph, owner);
      await _chooseTab(tester, 'Relations');

      final query = graph.repository.relationGroupQueries.single;
      expect(query.intentionId, owner.id);
      expect(query.type, group.type);
      expect(query.direction, group.direction);
      expect(query.scope, RelationScope.active);
      expect(query.cursor, isNull);
      _expectSelectedGroup(tester, group);
      // Числа остальных групп доступны без чтения их содержимого.
      expect(find.bySemanticsLabel('Can use: 2 active'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Needs: 1 active, some archived'),
        findsOneWidget,
      );
    });
  }

  _testWidgets('Возвращение к связям сохраняет настройки и начинает список '
      'заново', (tester) async {
    final graph = _Graph();
    final owner = graph.addIntention(1, 'Быть здоровым');
    // Активная часть на одну связь длиннее порции, а конец первой порции
    // не строится без прокрутки.
    for (var index = 1; index <= _pageSize + 1; index += 1) {
      graph.addRelation(owner, index: index, type: LongTermRelationType.can);
    }
    graph.addRelation(
      owner,
      index: 100,
      type: LongTermRelationType.can,
      scope: RelationScope.archived,
    );
    final queries = graph.repository.relationGroupQueries;
    await _openPage(tester, graph, owner);
    await _chooseTab(tester, 'Relations');
    await _tapGroup(tester, IntentionRelationGroup.canUse);
    await _scrollToArchive(tester);
    expect(queries.where((query) => query.cursor != null), hasLength(1));
    await tester.tap(_foldButton);
    await tester.pumpAndSettle();
    expect(_fold(tester).open, isTrue);
    expect(
      queries.where((query) => query.scope == RelationScope.archived),
      hasLength(1),
    );
    final readsBeforeLeaving = queries.length;

    await _chooseTab(tester, 'Overview');
    await _chooseTab(tester, 'Relations');

    _expectSelectedGroup(tester, IntentionRelationGroup.canUse);
    final rereads = queries.skip(readsBeforeLeaving).toList();
    expect(
      [
        for (final query in rereads)
          (query.type, query.direction, query.scope, query.cursor),
      ],
      unorderedEquals([
        (
          LongTermRelationType.can,
          RelationDirection.outgoing,
          RelationScope.active,
          null,
        ),
        (
          LongTermRelationType.can,
          RelationDirection.outgoing,
          RelationScope.archived,
          null,
        ),
      ]),
    );
    await _scrollToArchive(tester);
    expect(_fold(tester).open, isTrue);
  });

  _testWidgets('число вкладки берётся из модели «Связей», пока она есть, '
      'а без неё — из подробных данных', (tester) async {
    final graph = _Graph();
    final owner = graph.addIntention(1, 'Быть здоровым');
    graph.addRelation(owner, index: 1);
    await _openPage(tester, graph, owner);
    // Подтверждённая позже связь ещё не дошла до подробных данных страницы.
    graph.addRelation(owner, index: 2);

    await _chooseTab(tester, 'Relations');
    expect(
      find.bySemanticsLabel('Relations: 2 active, 0 archived'),
      findsOneWidget,
    );

    await _chooseTab(tester, 'Overview');
    expect(
      find.bySemanticsLabel('Relations: 1 active, 0 archived'),
      findsOneWidget,
    );
  });

  _testWidgets('Стрелка открывает соседа на той же группе', (tester) async {
    final graph = _Graph();
    final owner = graph.addIntention(1, 'Быть здоровым');
    // Действие без цели открылось бы на группе «Нужно для».
    final neighbor = graph.addIntention(
      2,
      'Наращивать силу',
      IntentionReadiness.ready,
    );
    graph.addRelation(owner, index: 1, neighbor: neighbor);
    await _openPage(tester, graph, owner);
    await _chooseTab(tester, 'Relations');

    await _walk(tester, 'Open the action page: Наращивать силу');

    final page = tester.widget<IntentionDetailsPage>(
      find.byType(IntentionDetailsPage),
    );
    expect(page.intentionId, neighbor.id);
    expect(
      page.target,
      isA<RelationsTarget>().having(
        (target) => target.group,
        'group',
        IntentionRelationGroup.needs,
      ),
    );
    _expectSelectedGroup(tester, IntentionRelationGroup.needs);
    final query = graph.repository.relationGroupQueries.last;
    expect(query.intentionId, neighbor.id);
    expect(query.type, LongTermRelationType.need);
    expect(query.direction, RelationDirection.outgoing);
    expect(find.text('Needs nothing yet'), findsOneWidget);
  });

  _testWidgets('Две страницы одного намерения не влияют друг на друга', (
    tester,
  ) async {
    final graph = _Graph();
    final a = graph.addIntention(1, 'А');
    final b = graph.addIntention(2, 'Б');
    graph.addRelation(a, index: 1, neighbor: b);
    graph.addRelation(b, index: 2, type: LongTermRelationType.can, neighbor: a);
    await _openPage(tester, graph, a);
    await _chooseTab(tester, 'Relations');
    _expectSelectedGroup(tester, IntentionRelationGroup.needs);

    await _walk(tester, 'Open the intention page: Б');
    await _tapGroup(tester, IntentionRelationGroup.canUse);
    await _walk(tester, 'Open the intention page: А');

    _expectPage(tester, a.id);
    _expectSelectedGroup(tester, IntentionRelationGroup.canUse);
    await _back(tester);
    _expectPage(tester, b.id);
    _expectSelectedGroup(tester, IntentionRelationGroup.canUse);
    await _back(tester);
    _expectPage(tester, a.id);
    _expectSelectedGroup(tester, IntentionRelationGroup.needs);
  });

  _testWidgets('Вход из исходящей группы, а после созданной связи «Связи» '
      'остаются на прежней группе с новой связью', (tester) async {
    final graph = _Graph();
    final owner = graph.addIntention(1, 'Быть здоровым');
    final router = await _openPage(tester, graph, owner);
    await _chooseTab(tester, 'Relations');
    await _tapGroup(tester, IntentionRelationGroup.canUse);

    await tester.tap(find.byKey(const ValueKey('intention-relations-add')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<RelationEditorPage>(find.byType(RelationEditorPage))
          .editorContext,
      RelationCreationContext(
        participant: RelationParticipantSummary(
          id: owner.id,
          title: owner.title,
          archiveState: owner.archiveState,
        ),
        group: IntentionRelationGroup.canUse,
      ),
    );

    // Созданная связь подтверждается после возвращения на страницу.
    await router.maybePop();
    await tester.pumpAndSettle();
    final created = graph.addRelation(
      owner,
      index: 1,
      type: LongTermRelationType.can,
    );
    graph.confirmChange(owner.id);
    await tester.pumpAndSettle();

    _expectSelectedGroup(tester, IntentionRelationGroup.canUse);
    expect(_row(created), findsOneWidget);
  });

  _testWidgets('смена готовности на «Обзоре» не меняет группу «Связей»', (
    tester,
  ) async {
    final graph = _Graph();
    final before = graph.addIntention(1, 'Быть здоровым');
    await _openPage(tester, graph, before);
    await _chooseTab(tester, 'Relations');
    _expectSelectedGroup(tester, IntentionRelationGroup.needs);

    await _chooseTab(tester, 'Overview');
    await tester.tap(
      find.descendant(
        of: find.byType(OptionTiles<IntentionReadiness>),
        matching: find.text('Action'),
      ),
    );
    await tester.pump();
    expect(graph.repository.commands.single, isA<EnableIntentionReadiness>());
    final saved = graph.addIntention(
      1,
      'Быть здоровым',
      IntentionReadiness.ready,
    );
    graph.repository.completeCommand(
      0,
      testDetailsSavedResult(
        saved,
        before: before,
        revision: const TestDetailsRevision(1),
      ),
    );
    await tester.pump();
    graph.confirmChange(saved.id);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(TopBar), matching: find.text('Action')),
      findsOneWidget,
    );

    await _chooseTab(tester, 'Relations');
    _expectSelectedGroup(tester, IntentionRelationGroup.needs);
    final query = graph.repository.relationGroupQueries.last;
    expect(query.type, LongTermRelationType.need);
    expect(query.direction, RelationDirection.outgoing);
  });

  _testWidgets('подробности связи над вкладкой «Связи» сохраняют её строки', (
    tester,
  ) async {
    final graph = _Graph();
    final owner = graph.addIntention(1, 'Быть здоровым');
    final rows = [
      graph.addRelation(owner, index: 1),
      graph.addRelation(owner, index: 2),
    ];
    final relationWatches = StreamController<LongTermRelationReadResult>();
    addTearDown(relationWatches.close);
    graph.repository.onWatchRelation = (_) => relationWatches.stream;
    await _openPage(tester, graph, owner);
    await _chooseTab(tester, 'Relations');
    final reads = graph.repository.relationGroupQueries.length;

    await tester.tap(_row(rows.first));
    // Открытая связь читается: индикатор чтения не даёт дождаться покоя.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await _back(tester, settle: false);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(graph.repository.relationGroupQueries, hasLength(reads));
    for (final row in rows) {
      expect(_row(row), findsOneWidget);
    }
  });
}

const _pageSize = 15;

/// Плитки и стрелки строк проверяются по их доступным названиям.
void _testWidgets(String description, WidgetTesterCallback body) =>
    testWidgets(description, (tester) async {
      final semantics = tester.ensureSemantics();
      await body(tester);
      semantics.dispose();
    });

/// Граф с намерениями и связями, на которых репозиторий отвечает страницам.
///
/// Подробные данные намерения получают снимок при первом наблюдении. Модели
/// вкладок наблюдают то же намерение и узнают об изменениях из
/// [confirmChange], как из подтверждённого изменения графа.
final class _Graph {
  _Graph() {
    repository.onRelationGroupPage = _answer;
    repository.onWatchIntention = (id) {
      final request = repository.detailRequests.last;
      final isFirst = _watches.every((watch) => watch.$1 != id);
      _watches.add((id, request));
      if (isFirst) _emit(id, request);
    };
  }

  final repository = ControlledDetailsRepository();
  final _intentions = <IntentionId, Intention>{};
  final _relations = <LongTermRelation>[];
  final _watches = <(IntentionId, ControlledDetailRequest)>[];
  var _revision = 0;

  Intention addIntention(
    int index,
    String title, [
    IntentionReadiness readiness = IntentionReadiness.notReady,
  ]) => _intentions[testDetailsIntentionId(index)] = testDetailsIntention(
    index: index,
    title: title,
    readiness: readiness,
  );

  /// Добавляет связь [owner] с соседом и возвращает её строку для [owner].
  RelationGroupEntry addRelation(
    Intention owner, {
    required int index,
    LongTermRelationType type = LongTermRelationType.need,
    RelationDirection direction = RelationDirection.outgoing,
    RelationScope scope = RelationScope.active,
    Intention? neighbor,
  }) {
    final row = testDetailsRelationRow(
      ownerId: owner.id,
      index: index,
      type: type,
      direction: direction,
      scope: scope,
      neighborId: neighbor?.id,
      neighborTitle: neighbor?.title,
      neighborReadiness: neighbor?.readiness ?? IntentionReadiness.notReady,
    );
    _relations.add(row.relation);
    return row;
  }

  /// Подтверждает новую ревизию намерения [id] всем его наблюдателям.
  void confirmChange(IntentionId id) {
    _revision += 1;
    for (final (watched, request) in _watches) {
      if (watched == id) _emit(id, request);
    }
  }

  void _emit(IntentionId id, ControlledDetailRequest request) => request.add(
    ResultSuccess(_intentions[id]),
    revision: TestDetailsRevision(_revision),
    relationCounts: _counts(id),
  );

  RelationCounts _counts(IntentionId id) {
    int count(
      RelationScope scope,
      LongTermRelationType type,
      RelationDirection direction,
    ) => _groupOf(id, scope, type, direction).length;
    return testRelationCounts(
      activeNeedIncoming: count(
        RelationScope.active,
        LongTermRelationType.need,
        RelationDirection.incoming,
      ),
      activeNeedOutgoing: count(
        RelationScope.active,
        LongTermRelationType.need,
        RelationDirection.outgoing,
      ),
      activeCanIncoming: count(
        RelationScope.active,
        LongTermRelationType.can,
        RelationDirection.incoming,
      ),
      activeCanOutgoing: count(
        RelationScope.active,
        LongTermRelationType.can,
        RelationDirection.outgoing,
      ),
      archivedNeedIncoming: count(
        RelationScope.archived,
        LongTermRelationType.need,
        RelationDirection.incoming,
      ),
      archivedNeedOutgoing: count(
        RelationScope.archived,
        LongTermRelationType.need,
        RelationDirection.outgoing,
      ),
      archivedCanIncoming: count(
        RelationScope.archived,
        LongTermRelationType.can,
        RelationDirection.incoming,
      ),
      archivedCanOutgoing: count(
        RelationScope.archived,
        LongTermRelationType.can,
        RelationDirection.outgoing,
      ),
    );
  }

  List<RelationGroupEntry> _groupOf(
    IntentionId id,
    RelationScope scope,
    LongTermRelationType type,
    RelationDirection direction,
  ) => [
    for (final relation in _relations)
      if (relation.scope == scope &&
          relation.type == type &&
          switch (direction) {
            RelationDirection.outgoing => relation.sourceIntentionId == id,
            RelationDirection.incoming => relation.relatedIntentionId == id,
          })
        _entry(relation, owner: id),
  ];

  RelationGroupEntry _entry(
    LongTermRelation relation, {
    required IntentionId owner,
  }) {
    final neighborId = relation.sourceIntentionId == owner
        ? relation.relatedIntentionId
        : relation.sourceIntentionId;
    final neighbor = _intentions[neighborId];
    return RelationGroupEntry(
      relation: relation,
      neighbor: RelationNeighbor(
        id: neighborId,
        title: neighbor?.title ?? 'Сосед',
        archiveState: IntentionArchiveState.active,
        readiness: neighbor?.readiness ?? IntentionReadiness.notReady,
      ),
    );
  }

  RelationGroupPageResult _answer(RelationGroupQuery query) {
    final rows = _groupOf(
      query.intentionId,
      query.scope,
      query.type,
      query.direction,
    );
    final start = switch (query.cursor) {
      _Cursor(:final offset) => offset,
      _ => 0,
    };
    final end = rows.length < start + query.pageSize
        ? rows.length
        : start + query.pageSize;
    final items = rows.sublist(start, end);
    final next = end < rows.length ? _Cursor(end) : null;
    final revision = TestDetailsRevision(_revision);
    return GraphResultSuccess(
      query.cursor == null
          ? RelationGroupFirstPage(
              items: items,
              counts: _counts(query.intentionId),
              nextCursor: next,
              revision: revision,
            )
          : RelationGroupContinuationPage(
              items: items,
              nextCursor: next,
              revision: revision,
            ),
    );
  }
}

final class _Cursor implements RelationGroupCursor {
  const _Cursor(this.offset);

  final int offset;
}

Future<AppRouter> _openPage(
  WidgetTester tester,
  _Graph graph,
  Intention intention,
) async {
  final router = AppRouter();
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        inMemoryQuickCreationModeOverride,
        personalGraphRepositoryProvider.overrideWithValue(graph.repository),
        relationGroupPagingPolicyProvider.overrideWithValue(
          RelationGroupPagingPolicy(pageSize: _pageSize, prefetchRemaining: 0),
        ),
      ],
      retry: (retryCount, error) => null,
      child: MaterialApp.router(
        theme: doableTheme(Brightness.light),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router.config(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  unawaited(router.push(IntentionDetailsRoute(intentionId: intention.id)));
  await tester.pumpAndSettle();
  expect(graph.repository.relationGroupQueries, isEmpty);
  return router;
}

Future<void> _chooseTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).first);
  await tester.pumpAndSettle();
}

Future<void> _tapGroup(
  WidgetTester tester,
  IntentionRelationGroup group,
) async {
  final tile = _groupTile(group);
  await tester.ensureVisible(tile);
  await tester.pumpAndSettle();
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

Future<void> _walk(WidgetTester tester, String label) async {
  final walk = find.bySemanticsLabel(label);
  await tester.ensureVisible(walk);
  await tester.pumpAndSettle();
  await tester.tap(walk);
  await tester.pumpAndSettle();
}

Future<void> _back(WidgetTester tester, {bool settle = true}) async {
  await tester.tap(find.bySemanticsLabel('Back'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

/// Прокручивает к строке архива: она стоит после полностью полученной
/// активной части.
Future<void> _scrollToArchive(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byType(ArchivedFold),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void _expectSelectedGroup(WidgetTester tester, IntentionRelationGroup group) {
  for (final tile in IntentionRelationGroup.values) {
    expect(
      tester
          .getSemantics(_groupTile(tile))
          .getSemanticsData()
          .flagsCollection
          .isChecked,
      tile == group ? CheckedState.isTrue : CheckedState.isFalse,
      reason: tile.name,
    );
  }
}

void _expectPage(WidgetTester tester, IntentionId id) => expect(
  tester
      .widget<IntentionDetailsPage>(find.byType(IntentionDetailsPage))
      .intentionId,
  id,
);

Finder _groupTile(IntentionRelationGroup group) =>
    find.byKey(ValueKey('intention-relations-group-${group.name}'));

Finder _row(RelationGroupEntry row) => find.byKey(
  ValueKey('intention-relations-row-${row.relation.id.toCanonicalString()}'),
);

final _foldButton = find.descendant(
  of: find.byType(ArchivedFold),
  matching: find.byType(TextButton),
);

ArchivedFold _fold(WidgetTester tester) =>
    tester.widget(find.byType(ArchivedFold));
