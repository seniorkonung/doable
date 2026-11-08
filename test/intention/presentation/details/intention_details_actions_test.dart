import 'dart:async';
import 'dart:ui' show CheckedState;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/action/application/action_list_item.dart';
import 'package:doable/src/action/application/intention_actions.dart';
import 'package:doable/src/action/domain/action_id.dart';
import 'package:doable/src/action/domain/action_priority.dart';
import 'package:doable/src/action/domain/action_schedule.dart';
import 'package:doable/src/action/domain/action_text.dart';
import 'package:doable/src/action/presentation/panel/action_panel.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/design_system/components/action_row.dart';
import 'package:doable/src/design_system/components/tabs.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/presentation/details/intention_details_tabs.dart';
import 'package:doable/src/intention/presentation/details/intention_page_target.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/controlled_local_date.dart';
import '../../../support/in_memory_quick_creation_mode_store.dart';
import 'details_test_support.dart';

final _today = CalendarDate.fromParts(2026, 10, 8);

void main() {
  for (final (locale, labels) in [
    ('ru', const ['Обзор', 'Связи', 'Действия', 'Статистика']),
    ('en', const ['Overview', 'Relations', 'Actions', 'Statistics']),
  ]) {
    testWidgets('$locale: «Действия» стоят третьей вкладкой с числом', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final repository = ControlledDetailsRepository()
        ..onIntentionActionsPage = (query) => _page(query, root: 2, total: 5);
      await _openPage(tester, repository, locale: Locale(locale));
      repository.detailRequests.single.add(
        ResultSuccess(testDetailsIntention()),
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
      expect(
        find.descendant(of: tabs, matching: find.text('5')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(locale == 'ru' ? 'Действия: 5' : 'Actions: 5'),
        findsOneWidget,
      );
      // Под «Обзором» читаются только числа, но не строки списка.
      expect(repository.intentionActionsListQueries, isEmpty);
      semantics.dispose();
    });
  }

  testWidgets('плитки показывают числа ролей, а открыта плитка с наибольшим', (
    tester,
  ) async {
    final repository = ControlledDetailsRepository()
      ..onIntentionActionsPage = (query) => _page(
        query,
        root: 1,
        intermediate: 3,
        terminal: 2,
        total: 5,
        items: [for (var id = 1; id <= 3; id++) _item(id)],
      );
    await _openPage(tester, repository, target: const ActionsTarget());
    repository.detailRequests.single.add(ResultSuccess(testDetailsIntention()));
    await tester.pumpAndSettle();

    for (final (role, name, count) in [
      (IntentionActionRole.root, 'Root', '1'),
      (IntentionActionRole.intermediate, 'Intermediate', '3'),
      (IntentionActionRole.terminal, 'Final', '2'),
    ]) {
      final tile = find.byKey(ValueKey('intention-actions-role-${role.name}'));
      expect(
        find.descendant(of: tile, matching: find.text(name)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tile, matching: find.text(count)),
        findsOneWidget,
      );
    }
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('intention-actions-role-intermediate')),
          )
          .getSemanticsData()
          .flagsCollection
          .isChecked,
      CheckedState.isTrue,
    );
    expect(find.byType(ActionRow), findsNWidgets(3));
    expect(
      repository.intentionActionsListQueries.last.role,
      IntentionActionRole.intermediate,
    );
  });

  testWidgets('строки идут группами, дата и время стоят в первой линии, а '
      'корень — только под «Промежуточным» и «Конечным»', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final items = [
      _item(1, date: _today.plusDays(4), hour: 9),
      _item(2, date: _today, hour: 18),
      _item(3, date: _today.plusDays(-1), hour: 7),
      _item(4, date: CalendarDate.fromParts(2026, 9, 20)),
      _item(5, date: CalendarDate.fromParts(2025, 8, 3)),
    ];
    final repository = ControlledDetailsRepository()
      ..onIntentionActionsPage = (query) => _page(
        query,
        root: 5,
        intermediate: 5,
        terminal: 5,
        total: 5,
        items: items,
      );
    await _openPage(tester, repository, target: const ActionsTarget());
    repository.detailRequests.single.add(ResultSuccess(testDetailsIntention()));
    await tester.pumpAndSettle();

    // При равных числах открыта корневая плитка: корень пути — сама страница.
    expect(find.text('Основание'), findsNothing);
    for (final text in [
      'Today and later',
      'September',
      'August 2025',
      'Mon 12 Oct · 9:00 AM',
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    expect(find.text('Today · 6:00 PM'), findsOneWidget);
    expect(find.text('Yesterday · 7:00 AM'), findsOneWidget);
    expect(find.text('Sun 20'), findsOneWidget);
    expect(find.text('Sun 3'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('intention-actions-role-terminal')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Основание'), findsNWidgets(items.length));
  });

  testWidgets('флажок строки только показывает выполнение, а нажатие на '
      'строку открывает панель действия', (tester) async {
    final done = _item(1, completed: true);
    final repository = ControlledDetailsRepository()
      ..onIntentionActionsPage = (query) =>
          _page(query, root: 1, total: 1, items: [done]);
    await _openPage(tester, repository, target: const ActionsTarget());
    repository.detailRequests.single.add(ResultSuccess(testDetailsIntention()));
    await tester.pumpAndSettle();

    final row = tester.widget<ActionRow>(find.byType(ActionRow));
    expect(row.onToggle, isNull);
    expect(row.done, isTrue);

    await tester.tap(
      find.byKey(
        ValueKey('intention-actions-row-${done.id.toCanonicalString()}'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ActionPanel), findsOneWidget);
    expect(
      tester.widget<ActionPanel>(find.byType(ActionPanel)).actionId,
      done.id,
    );
  });

  for (final (role, key, text) in [
    (
      IntentionActionRole.root,
      'root',
      'An action whose path starts with this intention will appear here.',
    ),
    (
      IntentionActionRole.intermediate,
      'intermediate',
      'An action whose path goes through this intention will appear here.',
    ),
    (
      IntentionActionRole.terminal,
      'terminal',
      'An action whose path ends with this intention will appear here.',
    ),
  ]) {
    testWidgets('пустая плитка «$key» объясняет, что здесь появится', (
      tester,
    ) async {
      final repository = ControlledDetailsRepository()
        ..onIntentionActionsPage = (query) => _page(
          query,
          root: role == IntentionActionRole.root ? 0 : 1,
          intermediate: role == IntentionActionRole.intermediate ? 0 : 1,
          terminal: role == IntentionActionRole.terminal ? 0 : 1,
          total: 2,
          items: query.role == role ? const [] : [_item(1)],
        );
      await _openPage(tester, repository, target: const ActionsTarget());
      repository.detailRequests.single.add(
        ResultSuccess(testDetailsIntention()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('intention-actions-role-$key')));
      await tester.pumpAndSettle();

      expect(find.text(text), findsOneWidget);
      expect(find.byType(ActionRow), findsNothing);
      // Остальные плитки сохраняют свои числа.
      expect(
        find.byKey(const ValueKey('intention-actions-role-root')),
        findsOneWidget,
      );
    });
  }

  testWidgets('возвращение на вкладку сохраняет плитку и читает список с '
      'первой порции', (tester) async {
    final repository = ControlledDetailsRepository()
      ..onIntentionActionsPage = (query) => _page(
        query,
        root: 1,
        intermediate: 3,
        terminal: 2,
        total: 5,
        items: [_item(1)],
      );
    await _openPage(tester, repository, target: const ActionsTarget());
    repository.detailRequests.single.add(ResultSuccess(testDetailsIntention()));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('intention-actions-role-terminal')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Overview'));
    await tester.pumpAndSettle();
    final readsBefore = repository.intentionActionsListQueries.length;
    expect(find.byType(ActionRow), findsNothing);

    await tester.tap(find.text('Actions'));
    await tester.pumpAndSettle();

    final returnQuery = repository.intentionActionsListQueries
        .skip(readsBefore)
        .first;
    expect(returnQuery.role, IntentionActionRole.terminal);
    expect(returnQuery.cursor, isNull);
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('intention-actions-role-terminal')),
          )
          .getSemanticsData()
          .flagsCollection
          .isChecked,
      CheckedState.isTrue,
    );
  });

  testWidgets('архивированное намерение показывает свои действия так же', (
    tester,
  ) async {
    final repository = ControlledDetailsRepository()
      ..onIntentionActionsPage = (query) =>
          _page(query, root: 1, total: 1, items: [_item(1)]);
    await _openPage(tester, repository, target: const ActionsTarget());
    repository.detailRequests.single.add(
      ResultSuccess(
        testDetailsIntention(archiveState: IntentionArchiveState.archived),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ActionRow), findsOneWidget);
    expect(
      find.text(
        'Archived intentions stay in saved paths and are not offered in new ones.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('отказ первого чтения не выдаётся за пустой список', (
    tester,
  ) async {
    final repository = ControlledDetailsRepository();
    await _openPage(tester, repository, target: const ActionsTarget());
    repository.detailRequests.single.add(ResultSuccess(testDetailsIntention()));
    await tester.pumpAndSettle();

    expect(find.byType(ActionRow), findsNothing);
    expect(
      find.text('Could not load the actions because of an unexpected error.'),
      findsOneWidget,
    );
    expect(find.text('No actions yet'), findsNothing);
  });
}

extension on CalendarDate {
  CalendarDate plusDays(int days) {
    final value = DateTime.utc(year, month, day).add(Duration(days: days));
    return CalendarDate.fromParts(value.year, value.month, value.day);
  }
}

/// Страница ответа: числа на первой странице, строки — только своей роли.
IntentionActionsPageResult _page(
  IntentionActionsQuery query, {
  int root = 0,
  int intermediate = 0,
  int terminal = 0,
  required int total,
  List<ActionListItem> items = const [],
}) => IntentionActionsPageSuccess(
  IntentionActionsFirstPage(
    items: query.pageSize == IntentionActionsQuery.minPageSize
        ? const []
        : items,
    counts: IntentionActionCounts(
      root: root,
      intermediate: intermediate,
      terminal: terminal,
      total: total,
    ),
    nextCursor: null,
    revision: const TestDetailsRevision(0),
  ),
);

ActionListItem _item(
  int id, {
  CalendarDate? date,
  int? hour,
  bool completed = false,
}) => ActionListItem(
  id: _actionId(id),
  title: ActionTitle('Действие $id'),
  description: null,
  date: date ?? _today,
  schedule: hour == null ? const ActionAllDay() : ActionAtHour(hour),
  priority: ActionPriority.p4,
  isCompleted: completed,
  rootIntentionId: testDetailsIntention().id,
  rootTitle: 'Основание',
  pathIntentionCount: 2,
);

ActionId _actionId(int value) => switch (ActionId.decode(
  '018f1400-0000-7000-8000-${value.toString().padLeft(12, '0')}',
)) {
  ActionIdDecodingSuccess(:final id) => id,
  InvalidActionIdDecoding() => throw StateError(
    'Неверный идентификатор фикстуры',
  ),
};

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
        ControlledLocalDate(_today).override,
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
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
