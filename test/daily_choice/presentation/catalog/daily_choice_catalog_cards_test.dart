import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_description.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_priority.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_schedule.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'daily_choice_calendar_test_support.dart';
import 'daily_choice_catalog_page_test_support.dart';

void main() {
  for (final locale in const [Locale('ru'), Locale('en')]) {
    testWidgets(
      'группы учитывают весь остаток своей секции, продолжение не повторяет заголовок (${locale.languageCode})',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final repository = CatalogPageRepository();
        final day = date(2026, 10, 8);
        await pumpCatalogPage(
          tester,
          repository,
          today: day,
          locale: locale,
          size: const Size(360, 900),
        );
        final context = tester.element(find.byType(DailyChoiceCalendar));
        final l10n = AppLocalizations.of(context);
        final morning = DailyChoiceTime(hour: 9, minute: 0);
        repository.completeFirst(
          0,
          [
            for (var number = 1; number <= 50; number++)
              catalogPageItem(number, date: day),
            catalogPageItem(201, date: day, isCompleted: true),
          ],
          total: 103,
          cursor: const CatalogPageCursor(),
          hasTimedChoices: true,
        );
        await tester.pumpAndSettle();
        expect(
          find.text(l10n.dailyChoiceCatalogTotalCount(103)),
          findsOneWidget,
        );
        expect(
          find.semantics
              .byLabel(l10n.dailyChoiceAllDay)
              .evaluate()
              .single
              .flagsCollection
              .isHeader,
          isTrue,
        );
        await tester.tap(
          find.byKey(const ValueKey('daily-choice-section-false')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('daily-choice-section-true')),
        );
        await tester.pumpAndSettle();
        // Выполненные относятся ко всему дню: собственной дополнительной группы нет.
        expect(
          find.semantics.byLabel(l10n.dailyChoiceAllDay).evaluate(),
          isEmpty,
        );
        await tester.tap(
          find.byKey(const ValueKey('daily-choice-section-false')),
        );
        await tester.pumpAndSettle();
        final scrollable = find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first;
        final more = find.byKey(const ValueKey('daily-choice-load-more-false'));
        await tester.scrollUntilVisible(more, 1000, scrollable: scrollable);
        await tester.tap(more);
        repository.completeMore(1, [
          for (var number = 51; number <= 100; number++)
            catalogPageItem(number, date: day, schedule: morning),
        ], cursor: const CatalogPageCursor());
        await tester.pumpAndSettle();
        final time = const TimeOfDay(hour: 9, minute: 0).format(context);
        expect(
          find.semantics
              .byLabel(time)
              .evaluate()
              .single
              .flagsCollection
              .isHeader,
          isTrue,
        );
        await tester.scrollUntilVisible(more, 1000, scrollable: scrollable);
        await tester.tap(more);
        repository.completeMore(2, [
          catalogPageItem(101, date: day, schedule: morning),
          catalogPageItem(
            102,
            date: day,
            schedule: DailyChoiceTime(hour: 18, minute: 0),
          ),
        ]);
        await tester.pumpAndSettle();
        expect(find.semantics.byLabel(time).evaluate(), isEmpty);
        expect(
          find.semantics
              .byLabel(const TimeOfDay(hour: 18, minute: 0).format(context))
              .evaluate()
              .single
              .flagsCollection
              .isHeader,
          isTrue,
        );
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );

    testWidgets(
      'крупная карточка показывает время, приоритет и размер пути, ограничивая только описание (${locale.languageCode})',
      (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final repository = CatalogPageRepository();
        final day = date(2026, 10, 8);
        final description = DailyChoiceDescription.fromInput(
          List.filled(60, 'Полное описание выбора').join(' '),
        );
        await pumpCatalogPage(
          tester,
          repository,
          today: day,
          locale: locale,
          size: const Size(360, 900),
        );
        repository.completeFirst(0, [
          catalogPageItem(
            1,
            date: day,
            schedule: DailyChoiceTime(hour: 18, minute: 0),
            priority: DailyChoicePriority.p2,
            description: description,
            pathIntentionCount: 4,
          ),
        ], total: 1);
        await tester.pumpAndSettle();
        final context = tester.element(find.byType(DailyChoiceCalendar));
        final l10n = AppLocalizations.of(context);
        final scrollable = find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first;
        final text = find.text(description!.value);
        await tester.scrollUntilVisible(text, 300, scrollable: scrollable);
        expect(tester.widget<Text>(text).maxLines, 2);
        expect(tester.widget<Text>(text).overflow, TextOverflow.ellipsis);
        expect(find.text(l10n.dailyChoicePriorityOption('P2')), findsOneWidget);
        expect(
          find.text(
            locale.languageCode == 'ru'
                ? '4 намерения в пути'
                : '4 intentions in path',
          ),
          findsOneWidget,
        );
        final row = tester.widget<Semantics>(
          find.byKey(const ValueKey('daily-choice-row-1')),
        );
        expect(
          row.properties.label,
          contains(const TimeOfDay(hour: 18, minute: 0).format(context)),
        );
        expect(
          row.properties.label,
          contains(l10n.dailyChoicePriorityOption('P2')),
        );
        expect(row.properties.label, contains(description.value));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
