import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/daily_choice/application/daily_choice_catalog.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_priority.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_schedule.dart';
import 'package:doable/src/daily_choice/application/choice_path_draft.dart';
import 'package:doable/src/daily_choice/presentation/path/choice_path_page.dart';
import 'package:doable/src/design_system/components/add_row.dart';
import 'package:doable/src/design_system/components/tabs.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/details/intention_details_tabs.dart';
import 'package:doable/src/intention/presentation/details/intention_page_target.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/presentation/relation_group_paging_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../long_term_relation/presentation/neighborhood/neighborhood_test_support.dart'
    show TestRelationGroupCursor;
import '../../../support/in_memory_quick_creation_mode_store.dart';
import 'details_test_support.dart';

void main() {
  for (final (locale, labels) in [
    ('ru', const ['Обзор', 'Связи', 'Выборы', 'Статистика']),
    ('en', const ['Overview', 'Relations', 'Choices', 'Statistics']),
  ]) {
    testWidgets('$locale: «Выборы» стоят третьей вкладкой без числа', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final repository = ControlledDetailsRepository();
      await _openPage(tester, repository, locale: Locale(locale));
      repository.detailRequests.single.add(
        ResultSuccess(testDetailsIntention()),
        relationCounts: testRelationCounts(
          activeNeedOutgoing: 2,
          dailySource: 7,
          dailySelected: 4,
        ),
      );
      await tester.pumpAndSettle();

      final tabs = find.byType(Tabs<IntentionDetailsTab>);
      final positions = [
        for (final label in labels)
          tester
              .getCenter(find.descendant(of: tabs, matching: find.text(label)))
              .dx,
      ];
      expect(positions, [...positions]..sort());
      expect(find.bySemanticsLabel(labels[2]), findsOneWidget);
      for (final count in ['4', '7', '11']) {
        expect(
          find.descendant(of: tabs, matching: find.text(count)),
          findsNothing,
        );
      }
      expect(repository.dailyChoiceGroupQueries, isEmpty);
      semantics.dispose();
    });
  }

  testWidgets('возвращение к выборам сохраняет роль и начинает список заново', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final repository = ControlledDetailsRepository();
    final owner = testDetailsIntention();
    repository.onDailyChoiceGroupPage = (query) =>
        _pagedChoices(owner.id, query);
    await _openPage(tester, repository);
    repository.detailRequests.single.add(ResultSuccess(owner));
    await tester.pumpAndSettle();
    final pageWatches = repository.detailRequests.length;

    await tester.tap(find.text('Choices'));
    await tester.pumpAndSettle();
    expect(
      repository.dailyChoiceGroupQueries.single.role,
      DailyChoiceRelationRole.source,
    );
    final choicesWatch = repository.detailRequests[pageWatches];
    await tester.tap(
      find.byKey(const ValueKey('intention-choices-role-selected')),
    );
    await tester.pumpAndSettle();
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -3000),
      3000,
    );
    await tester.pumpAndSettle();
    final selectedQueries = repository.dailyChoiceGroupQueries
        .where((query) => query.role == DailyChoiceRelationRole.selected)
        .toList();
    expect(selectedQueries.length, greaterThan(1));

    await tester.tap(find.text('Overview'));
    await tester.pumpAndSettle();
    expect(choicesWatch.cancellationCount, 1);
    final queriesBeforeReturn = repository.dailyChoiceGroupQueries.length;

    await tester.tap(find.text('Choices'));
    await tester.pumpAndSettle();
    final returnQuery = repository.dailyChoiceGroupQueries
        .skip(queriesBeforeReturn)
        .single;
    expect(returnQuery.role, DailyChoiceRelationRole.selected);
    expect(returnQuery.cursor, isNull);
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('intention-choices-role-selected')),
          )
          .getSemanticsData()
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
    );
    semantics.dispose();
  });

  testWidgets('пустая роль не скрывает число выборов другой роли', (
    tester,
  ) async {
    final repository = ControlledDetailsRepository();
    final owner = testDetailsIntention();
    final counts = testRelationCounts(activeNeedOutgoing: 1, dailySelected: 1);
    final selectedChoice = _choice(
      owner.id,
      role: DailyChoiceRelationRole.selected,
      index: 1,
    );
    repository.onDailyChoiceGroupPage = (query) => GraphResultSuccess(
      DailyChoiceGroupFirstPage(
        items: switch (query.role) {
          DailyChoiceRelationRole.source => const [],
          DailyChoiceRelationRole.selected => [selectedChoice],
        },
        counts: counts,
        nextCursor: null,
        revision: const TestDetailsRevision(0),
      ),
    );
    await _openPage(tester, repository);
    repository.detailRequests.single.add(ResultSuccess(owner));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Choices'));
    await tester.pumpAndSettle();
    expect(find.text('There are no relations in this group.'), findsOneWidget);
    expect(find.text('Daily choices: 1'), findsOneWidget);
    expect(find.text('Selected action: 1'), findsOneWidget);

    await tester.tap(find.text('Selected action: 1'));
    await tester.pumpAndSettle();
    expect(find.text('Not completed'), findsOneWidget);
  });

  testWidgets(
    'строка дневного выбора читается диктором и открывает подробности над вкладкой',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = ControlledDetailsRepository();
      final owner = testDetailsIntention(title: 'Намерение-владелец');
      final choice = _choice(
        owner.id,
        role: DailyChoiceRelationRole.source,
        index: 1,
      );
      repository.onDailyChoiceGroupPage = (_) => GraphResultSuccess(
        DailyChoiceGroupFirstPage(
          items: [choice],
          counts: testRelationCounts(dailySource: 1),
          nextCursor: null,
          revision: const TestDetailsRevision(0),
        ),
      );
      final router = await _openPage(
        tester,
        repository,
        locale: const Locale('ru'),
      );
      repository.detailRequests.single.add(ResultSuccess(owner));
      await tester.pumpAndSettle();
      final pageWatches = repository.detailRequests.length;
      await tester.tap(find.text('Выборы'));
      await tester.pumpAndSettle();
      final choicesWatch = repository.detailRequests[pageWatches];

      final row = find.byKey(
        ValueKey('intention-choices-row-${choice.id.toCanonicalString()}'),
      );
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      final label = tester.getSemantics(row).label;
      expect(label, contains('Исходное намерение'));
      expect(label, contains('Чтобы Намерение-владелец, я сегодня Действие 1'));
      expect(label, contains('Выполнено'));

      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(router.current.name, DailyChoiceDetailsRoute.name);
      // Вкладка остаётся выбранной под открытой страницей, и модель живёт.
      expect(choicesWatch.cancellationCount, 0);
      semantics.dispose();
    },
  );
  testWidgets(
    'две страницы одного намерения не меняют друг у друга роль и строки выборов',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = ControlledDetailsRepository();
      final owner = testDetailsIntention();
      final choices = {
        for (final role in DailyChoiceRelationRole.values)
          role: _choice(owner.id, role: role, index: 1),
      };
      repository.onDailyChoiceGroupPage = (query) => GraphResultSuccess(
        DailyChoiceGroupFirstPage(
          items: [choices[query.role]!],
          counts: testRelationCounts(dailySource: 1, dailySelected: 1),
          nextCursor: null,
          revision: const TestDetailsRevision(0),
        ),
      );
      final router = await _openPage(
        tester,
        repository,
        target: const ChoicesTarget(),
      );
      // Страницу и модель «Выборов» питают отдельные наблюдения намерения.
      for (final request in repository.detailRequests) {
        request.add(ResultSuccess(owner));
      }
      await tester.pumpAndSettle();

      unawaited(
        router.push(
          IntentionDetailsRoute(
            intentionId: owner.id,
            target: const ChoicesTarget(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(repository.dailyChoiceGroupQueries.map((query) => query.role), [
        DailyChoiceRelationRole.source,
        DailyChoiceRelationRole.source,
      ]);
      await tester.tap(
        find.byKey(const ValueKey('intention-choices-role-selected')),
      );
      await tester.pumpAndSettle();
      _expectRows(tester, choices, shown: DailyChoiceRelationRole.selected);
      final queriesBeforeBack = repository.dailyChoiceGroupQueries.length;

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(router.stack, hasLength(2));
      _expectRows(tester, choices, shown: DailyChoiceRelationRole.source);
      expect(repository.dailyChoiceGroupQueries, hasLength(queriesBeforeBack));
      semantics.dispose();
    },
  );

  testWidgets('вход со страницы намерения не требует поиска', (tester) async {
    final repository = ControlledDetailsRepository();
    final owner = testDetailsIntention();
    repository.onDailyChoiceGroupPage = (_) => _rolePage(const []);
    await _openPage(tester, repository, target: const ChoicesTarget());
    for (final request in repository.detailRequests) {
      request.add(ResultSuccess(owner));
    }
    await tester.pumpAndSettle();
    // Пустой список роли оставляет одно «Добавить» без подсказки.
    expect(
      find.text('Daily choices that start from this intention.'),
      findsNothing,
    );

    await tester.tap(find.byKey(_add));
    await _pumpRouteTransition(tester);
    _expectChoicePath(tester, owner.id, ChoicePathDraftDirection.topDown);
  });

  testWidgets('вход со страницы действия идёт снизу вверх', (tester) async {
    final repository = ControlledDetailsRepository();
    final owner = testDetailsIntention(readiness: IntentionReadiness.ready);
    repository.onDailyChoiceGroupPage = (query) =>
        _rolePage([_choice(owner.id, role: query.role, index: 1)]);
    await _openPage(tester, repository, target: const ChoicesTarget());
    for (final request in repository.detailRequests) {
      request.add(ResultSuccess(owner));
    }
    await tester.pumpAndSettle();
    expect(
      find.text('Daily choices that start from this intention.'),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('intention-choices-role-selected')),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Daily choices that end in this intention.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(_add));
    await _pumpRouteTransition(tester);
    _expectChoicePath(tester, owner.id, ChoicePathDraftDirection.bottomUp);
  });

  testWidgets('у архивированного намерения нет «Добавить» ни в одной роли', (
    tester,
  ) async {
    final repository = ControlledDetailsRepository();
    final owner = testDetailsIntention(
      readiness: IntentionReadiness.ready,
      archiveState: IntentionArchiveState.archived,
    );
    repository.onDailyChoiceGroupPage = (query) =>
        _rolePage([_choice(owner.id, role: query.role, index: 1)]);
    await _openPage(tester, repository, target: const ChoicesTarget());
    for (final request in repository.detailRequests) {
      request.add(ResultSuccess(owner));
    }
    await tester.pumpAndSettle();
    expect(
      find.text('Daily choices that start from this intention.'),
      findsOneWidget,
    );
    expect(find.byKey(_add), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('intention-choices-role-selected')),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Daily choices that end in this intention.'),
      findsOneWidget,
    );
    expect(find.byKey(_add), findsNothing);
  });

  testWidgets(
    'у роли «выбранное» неготового намерения нет «Добавить», а пустая роль '
    'остаётся без строки',
    (tester) async {
      final repository = ControlledDetailsRepository();
      final owner = testDetailsIntention();
      var selectedItems = [
        _choice(owner.id, role: DailyChoiceRelationRole.selected, index: 1),
      ];
      repository.onDailyChoiceGroupPage = (query) =>
          _rolePage(switch (query.role) {
            DailyChoiceRelationRole.source => const [],
            DailyChoiceRelationRole.selected => selectedItems,
          });
      await _openPage(tester, repository, target: const ChoicesTarget());
      for (final request in repository.detailRequests) {
        request.add(ResultSuccess(owner));
      }
      await tester.pumpAndSettle();
      expect(find.byKey(_add), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('intention-choices-role-selected')),
      );
      await tester.pumpAndSettle();
      // Утрата готовности сохраняет прежние выборы с этим действием.
      expect(
        find.text('Daily choices that end in this intention.'),
        findsOneWidget,
      );
      expect(find.byKey(_add), findsNothing);

      selectedItems = const [];
      await tester.tap(
        find.byKey(const ValueKey('intention-choices-role-source')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('intention-choices-role-selected')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AddRow), findsNothing);
    },
  );

  for (final (locale, sourceLabel, selectedLabel) in [
    (
      'ru',
      'Создать дневной выбор, который начинается с этого намерения',
      'Создать дневной выбор, который заканчивается этим действием',
    ),
    (
      'en',
      'Create a daily choice that starts from this intention',
      'Create a daily choice that ends in this action',
    ),
  ]) {
    testWidgets('$locale: «Добавить» называет начало дневного выбора', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final repository = ControlledDetailsRepository();
      final owner = testDetailsIntention(readiness: IntentionReadiness.ready);
      repository.onDailyChoiceGroupPage = (_) => _rolePage(const []);
      await _openPage(
        tester,
        repository,
        locale: Locale(locale),
        target: const ChoicesTarget(),
      );
      for (final request in repository.detailRequests) {
        request.add(ResultSuccess(owner));
      }
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(sourceLabel), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('intention-choices-role-selected')),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(selectedLabel), findsOneWidget);
      semantics.dispose();
    });
  }
}

const _add = ValueKey('intention-choices-add');

RelationGroupPageResult _rolePage(List<DailyChoiceCatalogItem> items) =>
    GraphResultSuccess(
      DailyChoiceGroupFirstPage(
        items: items,
        counts: testRelationCounts(
          dailySource: items.length,
          dailySelected: items.length,
        ),
        nextCursor: null,
        revision: const TestDetailsRevision(0),
      ),
    );

/// Пошаговый выбор продолжает читать продолжения, поэтому переход
/// прокручивается на время анимации, а не до покоя.
Future<void> _pumpRouteTransition(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

void _expectChoicePath(
  WidgetTester tester,
  IntentionId sourceIntentionId,
  ChoicePathDraftDirection direction,
) {
  final page = tester.widget<ChoicePathPage>(find.byType(ChoicePathPage));
  expect(page.sourceIntentionId, sourceIntentionId);
  expect(page.direction, direction);
}

/// Выбранная роль отмечена в переключателе, а в списке только её строка.
void _expectRows(
  WidgetTester tester,
  Map<DailyChoiceRelationRole, DailyChoiceCatalogItem> choices, {
  required DailyChoiceRelationRole shown,
}) {
  for (final MapEntry(key: role, value: choice) in choices.entries) {
    expect(
      tester
          .getSemantics(
            find.byKey(ValueKey('intention-choices-role-${role.name}')),
          )
          .getSemanticsData()
          .flagsCollection
          .isSelected,
      role == shown ? Tristate.isTrue : Tristate.isFalse,
    );
    expect(
      find.byKey(
        ValueKey('intention-choices-row-${choice.id.toCanonicalString()}'),
      ),
      role == shown ? findsOneWidget : findsNothing,
    );
  }
}

const _pageLength = 10;
const _roleTotal = 30;

/// Роль из трёх порций; строки порции не помещаются в видимую часть страницы,
/// поэтому следующая порция запрашивается только прокруткой.
RelationGroupPageResult _pagedChoices(
  IntentionId owner,
  DailyChoiceGroupQuery query,
) {
  final offset = switch (query.cursor) {
    null => 0,
    final TestRelationGroupCursor cursor => cursor.offset,
    _ => throw StateError('Неизвестное продолжение в тесте.'),
  };
  final end = offset + _pageLength;
  final items = [
    for (var index = offset; index < end; index += 1)
      _choice(owner, role: query.role, index: index),
  ];
  final nextCursor = end < _roleTotal ? TestRelationGroupCursor(end) : null;
  final counts = testRelationCounts(
    dailySource: _roleTotal,
    dailySelected: _roleTotal,
  );
  const revision = TestDetailsRevision(0);
  return GraphResultSuccess(
    query.cursor == null
        ? DailyChoiceGroupFirstPage(
            items: items,
            counts: counts,
            nextCursor: nextCursor,
            revision: revision,
          )
        : DailyChoiceGroupContinuationPage(
            items: items,
            nextCursor: nextCursor,
            revision: revision,
          ),
  );
}

DailyChoiceCatalogItem _choice(
  IntentionId owner, {
  required DailyChoiceRelationRole role,
  required int index,
}) {
  final roleDigit = role == DailyChoiceRelationRole.source ? 1 : 2;
  final id = (DailyChoiceId.decode(
    '00000000-0000-4000-8000-$roleDigit${index.toString().padLeft(11, '0')}',
  ) as DailyChoiceIdDecodingSuccess).id;
  final other = testDetailsIntentionId(500 + index);
  final ownerParticipant = DailyChoiceCatalogParticipant(
    id: owner,
    title: 'Намерение-владелец',
    archiveState: IntentionArchiveState.active,
    readiness: IntentionReadiness.notReady,
  );
  return DailyChoiceCatalogItem(
    id: id,
    source: role == DailyChoiceRelationRole.source
        ? ownerParticipant
        : DailyChoiceCatalogParticipant(
            id: other,
            title: 'Основание $index',
            archiveState: IntentionArchiveState.active,
            readiness: IntentionReadiness.notReady,
          ),
    selected: role == DailyChoiceRelationRole.selected
        ? ownerParticipant
        : DailyChoiceCatalogParticipant(
            id: other,
            title: 'Действие $index',
            archiveState: IntentionArchiveState.active,
            readiness: IntentionReadiness.ready,
          ),
    date: CalendarDate.fromParts(2026, 9, 24),
    isCompleted: role == DailyChoiceRelationRole.source,
    schedule: const DailyChoiceAllDay(),
    priority: DailyChoicePriority.p4,
    description: null,
    pathIntentionCount: 2,
  );
}

Future<AppRouter> _openPage(
  WidgetTester tester,
  ControlledDetailsRepository repository, {
  Locale locale = const Locale('en'),
  IntentionPageTarget target = const OverviewTarget(),
}) async {
  final router = AppRouter();
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        inMemoryQuickCreationModeOverride,
        personalGraphRepositoryProvider.overrideWithValue(repository),
        relationGroupPagingPolicyProvider.overrideWithValue(
          RelationGroupPagingPolicy(
            pageSize: _pageLength,
            prefetchRemaining: 0,
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
  await tester.pumpAndSettle();
  unawaited(
    router.push(
      IntentionDetailsRoute(
        intentionId: testDetailsIntention().id,
        target: target,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  return router;
}
