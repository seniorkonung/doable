import 'package:doable/src/daily_choice/domain/daily_choice_priority.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_schedule.dart';
import 'package:doable/src/daily_choice/presentation/details/daily_choice_details_page.dart';
import 'package:doable/src/daily_choice/presentation/editor/daily_choice_edit_page.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/design_system/components/day_mark.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/daily_choice_durability_fixture.dart';
import '../../../support/daily_choice_catalog_controls.dart';
import 'daily_choice_catalog_page_test_support.dart';

void main() {
  for (final onDate in [false, true]) {
    testWidgets(
      '${onDate ? "каталог на дату" : "корневой каталог"}: флажок согласует секции и отметку дня, подробности и правку выбора 18:00/P2',
      (tester) async {
        final database = AppDatabase(openInMemoryLocalDatabase());
        await database.open();
        addTearDown(database.close);
        await seedDurabilityGraph(database);
        final repository = durabilityRepository(database);
        final description = List.filled(
          50,
          'Полное описание многошагового выбора',
        ).join(' ');
        expect(
          await repository.execute(
            durabilityCreate(
              completed: false,
              description: description,
              schedule: DailyChoiceTime(hour: 18, minute: 0),
              priority: DailyChoicePriority.p2,
            ),
          ),
          isA<GraphCommandSucceeded>(),
        );
        final router = await pumpCatalogPage(
          tester,
          repository,
          today: durabilityChoiceDate,
          locale: const Locale('ru'),
          size: const Size(360, 900),
          catalogDate: onDate ? durabilityChoiceDate : null,
        );
        await _until(
          tester,
          () => find.text('Приоритет P2').evaluate().isNotEmpty,
        );
        final text = find.text(description);
        expect(tester.widget<Text>(text).maxLines, 2);
        expect(tester.widget<Text>(text).overflow, TextOverflow.ellipsis);
        expect(find.text('18:00'), findsNWidgets(2));
        expect(find.text('3 намерения в пути'), findsOneWidget);
        await expandDailyChoiceCatalogCalendar(tester);
        final viewport = shownDailyChoiceCatalogViewport(tester);
        final route = router.current.name;
        final checkbox = find.byKey(
          ValueKey(
            'daily-choice-completion-${durabilityChoice(201).toCanonicalString()}',
          ),
        );
        expect(tester.widget<Checkbox>(checkbox).value, isFalse);
        final done = dailyChoiceCatalogDayMark(
          durabilityChoiceDate,
          mark: DayMark.done,
        );
        final todo = dailyChoiceCatalogDayMark(
          durabilityChoiceDate,
          mark: DayMark.todo,
        );
        await _until(tester, () => todo.evaluate().isNotEmpty);
        await tester.ensureVisible(checkbox);
        await tester.pumpAndSettle();
        await tester.tap(checkbox);
        await _until(
          tester,
          () => done.evaluate().isNotEmpty && checkbox.evaluate().isEmpty,
        );
        expect(router.current.name, route);
        expect(find.byType(DailyChoiceDetailsPage), findsNothing);
        expect(shownDailyChoiceCatalogDate(tester), durabilityChoiceDate);
        expect(shownDailyChoiceCatalogViewport(tester), viewport);
        final completedSection = find.byKey(
          const ValueKey('daily-choice-section-true'),
        );
        await tester.ensureVisible(completedSection);
        await tester.pumpAndSettle();
        await tester.tap(completedSection);
        await tester.pumpAndSettle();
        expect(tester.widget<Checkbox>(checkbox).value, isTrue);
        await tester.ensureVisible(
          find.byKey(const ValueKey('daily-choice-row-1')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('daily-choice-row-1')));
        await _until(
          tester,
          () => find
              .byKey(const ValueKey('daily-choice-edit-open'))
              .evaluate()
              .isNotEmpty,
        );
        await tester.pumpAndSettle();
        final details = find.byType(DailyChoiceDetailsPage);
        expect(
          find.descendant(of: details, matching: find.text(description)),
          findsOneWidget,
        );
        expect(find.text('Время: 18:00'), findsOneWidget);
        expect(
          find.descendant(of: details, matching: find.text('Выполнено')),
          findsOneWidget,
        );
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('daily-choice-relation-2')),
          400,
        );
        expect(
          find.byKey(const ValueKey('daily-choice-relation-1')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('daily-choice-relation-2')),
          findsOneWidget,
        );
        final edit = find.byKey(const ValueKey('daily-choice-edit-open'));
        await tester.scrollUntilVisible(edit, 300);
        await tester.tap(edit);
        await _until(
          tester,
          () => find.byType(DailyChoiceEditPage).evaluate().isNotEmpty,
        );
        await tester.pumpAndSettle();
        final priority = find.widgetWithText(ChoiceChip, 'Приоритет P1');
        await tester.ensureVisible(priority);
        await tester.tap(priority);
        await tester.pumpAndSettle();
        final submit = find.byKey(const ValueKey('daily-choice-edit-submit'));
        await tester.ensureVisible(submit);
        await tester.tap(submit);
        await _until(
          tester,
          () => find.byType(DailyChoiceEditPage).evaluate().isEmpty,
        );
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        await _until(
          tester,
          () => find.text('Приоритет P1').evaluate().isNotEmpty,
        );
        expect(find.text('18:00'), findsNWidgets(2));
        expect(find.text('3 намерения в пути'), findsOneWidget);
        expect(find.text(description), findsOneWidget);
        expect(tester.widget<Checkbox>(checkbox).value, isTrue);
        expect(done, findsOneWidget);
        expect(shownDailyChoiceCatalogDate(tester), durabilityChoiceDate);
        expect(shownDailyChoiceCatalogViewport(tester), viewport);
        await tester.ensureVisible(checkbox);
        await tester.pumpAndSettle();
        await tester.tap(checkbox);
        await _until(
          tester,
          () =>
              todo.evaluate().isNotEmpty &&
              checkbox.evaluate().isNotEmpty &&
              !tester.widget<Checkbox>(checkbox).value!,
        );
        expect(done, findsNothing);
        expect(find.text('Приоритет P1'), findsOneWidget);
        expect(find.text('3 намерения в пути'), findsOneWidget);
        expect(find.text(description), findsOneWidget);
        expect(router.current.name, route);
        expect(shownDailyChoiceCatalogViewport(tester), viewport);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}

Future<void> _until(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 200 && !condition(); attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(condition(), isTrue);
}
