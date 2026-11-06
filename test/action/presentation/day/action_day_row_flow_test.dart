import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/design_system/components/action_path.dart' as ui;
import 'package:doable/src/design_system/components/action_row.dart';
import 'package:doable/src/design_system/components/day_mark.dart';
import 'package:doable/src/design_system/components/priority_picker.dart';
import 'package:doable/src/design_system/doable_priority.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../../support/action_day_controls.dart';
import '../../../support/action_panel_controls.dart';
import '../../../support/action_seed.dart';
import '../../../support/graph_seed.dart';
import '../../../support/in_memory_diagnostics_sink.dart';
import 'action_day_page_test_support.dart';

/// Локальное сегодня и дата действия, засеянного в базу.
final _day = CalendarDate.fromParts(2026, 10, 8);

void main() {
  for (final onDate in [false, true]) {
    testWidgets(
      '${onDate ? "экран дня на дату" : "корневой экран дня"}: флажок '
      'согласует секции и отметку дня, а панель действия 18:00/P2 меняет '
      'приоритет и показывает путь',
      (tester) async {
        late sqlite.Database raw;
        final database = AppDatabase(
          openInMemoryLocalDatabase(setup: (db) => raw = db),
        );
        await database.open();
        addTearDown(database.close);
        final description = List.filled(
          50,
          'Полное описание многошагового действия',
        ).join(' ');
        seedRawGraph(raw, () {
          for (final (number, title) in [
            (1, 'Быть здоровым'),
            (2, 'Больше двигаться'),
            (3, 'Бегать по утрам'),
          ]) {
            seedIntention(raw, seedUuid(number), title);
          }
          seedRelation(raw, seedUuid(101), seedUuid(1), seedUuid(2));
          seedRelation(raw, seedUuid(102), seedUuid(2), seedUuid(3));
          seedAction(
            raw,
            id: seedUuid(11),
            path: [seedUuid(1), seedUuid(2), seedUuid(3)],
            description: description,
            hour: 18,
            priority: 2,
          );
        });
        final repository = DriftPersonalGraphRepository(
          database,
          UuidV7IntentionIdGenerator(),
          () => DateTime.utc(2026, 10, 8),
          InMemoryDiagnosticsSink(),
        );
        final router = await pumpActionDay(
          tester,
          repository,
          today: _day,
          locale: const Locale('ru'),
          size: const Size(360, 900),
          catalogDate: onDate ? _day : null,
        );
        await _until(
          tester,
          () => _rowWith(DoablePriority.p2).evaluate().isNotEmpty,
        );
        final text = find.text(description);
        expect(tester.widget<Text>(text).maxLines, 2);
        expect(tester.widget<Text>(text).overflow, TextOverflow.ellipsis);
        expect(find.text('18:00'), findsOneWidget);
        await expandActionDayCalendar(tester);
        final viewport = shownActionDayViewport(tester);
        final route = router.current.name;
        final checkbox = find.byKey(
          ValueKey('action-day-completion-${seedUuid(11)}'),
        );
        expect(actionCompletionState(tester, checkbox).completed, isFalse);
        final done = actionDayDayMark(_day, mark: DayMark.done);
        final todo = actionDayDayMark(_day, mark: DayMark.todo);
        await _until(tester, () => todo.evaluate().isNotEmpty);
        await tester.ensureVisible(checkbox);
        await tester.pumpAndSettle();
        await tester.tap(checkbox);
        await _until(
          tester,
          () =>
              done.evaluate().isNotEmpty &&
              checkbox.evaluate().isNotEmpty &&
              actionCompletionState(tester, checkbox).completed,
        );
        expect(router.current.name, route);
        expect(actionPanel, findsNothing);
        expect(shownActionDayDate(tester), _day);
        expect(shownActionDayViewport(tester), viewport);
        await tester.ensureVisible(
          find.byKey(const ValueKey('action-day-row-1')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('action-day-row-1')));
        await _until(tester, () => actionPanelReady.evaluate().isNotEmpty);
        await tester.pumpAndSettle();
        expect(actionPanelField(description), findsOneWidget);
        expect(actionPanelField('18:00'), findsOneWidget);
        expect(shownActionHead(tester).done, isTrue);
        await _tap(
          tester,
          find.descendant(
            of: find.byType(PriorityPicker),
            matching: find.text('P1'),
          ),
        );
        await _until(
          tester,
          () => shownActionHead(tester).priority == DoablePriority.p1,
        );
        await _tap(
          tester,
          find.descendant(of: actionPanel, matching: find.text('Путь')),
        );
        await tester.pumpAndSettle();
        final path = tester.widget<ui.ActionPath>(find.byType(ui.ActionPath));
        expect(
          [path.root.name, for (final link in path.links) link.step.name],
          ['Быть здоровым', 'Больше двигаться', 'Бегать по утрам'],
        );
        expect(
          [for (final link in path.links) link.relation],
          everyElement(
            isA<ui.ActionPathExistingRelation>().having(
              (relation) => relation.kind,
              'вид связи',
              ui.ActionPathRelationKind.need,
            ),
          ),
        );
        await closeActionPanel(tester);
        await _until(
          tester,
          () => _rowWith(DoablePriority.p1).evaluate().isNotEmpty,
        );
        expect(find.text('18:00'), findsOneWidget);
        expect(find.text(description), findsOneWidget);
        expect(actionCompletionState(tester, checkbox).completed, isTrue);
        expect(done, findsOneWidget);
        expect(shownActionDayDate(tester), _day);
        expect(shownActionDayViewport(tester), viewport);
        await tester.ensureVisible(checkbox);
        await tester.pumpAndSettle();
        await tester.tap(checkbox);
        await _until(
          tester,
          () =>
              todo.evaluate().isNotEmpty &&
              checkbox.evaluate().isNotEmpty &&
              !actionCompletionState(tester, checkbox).completed,
        );
        expect(done, findsNothing);
        expect(_rowWith(DoablePriority.p1), findsOneWidget);
        expect(find.text(description), findsOneWidget);
        expect(router.current.name, route);
        expect(shownActionDayViewport(tester), viewport);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}

/// Карточка с приоритетом [priority].
Finder _rowWith(DoablePriority priority) => find.byWidgetPredicate(
  (widget) => widget is ActionRow && widget.priority == priority,
);

/// Прокрутка к элементу сдвигает его только к следующему кадру.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _until(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 200 && !condition(); attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(condition(), isTrue);
}
