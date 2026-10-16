import 'package:doable/src/daily_choice/domain/daily_choice_priority.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_schedule.dart';
import 'package:doable/src/daily_choice/presentation/details/daily_choice_details_page.dart';
import 'package:doable/src/daily_choice/presentation/editor/daily_choice_edit_page.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/daily_choice_durability_fixture.dart';
import 'daily_choice_catalog_page_test_support.dart';

void main() {
  testWidgets(
    'сохранённый выбор 18:00/P2 открывает полное описание и путь из карточки и согласует правку приоритета',
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
      await pumpCatalogPage(
        tester,
        repository,
        today: durabilityChoiceDate,
        locale: const Locale('ru'),
        size: const Size(360, 900),
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
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

Future<void> _until(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 200 && !condition(); attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(condition(), isTrue);
}
