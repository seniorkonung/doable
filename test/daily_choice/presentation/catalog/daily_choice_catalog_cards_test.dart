import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_description.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_priority.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_schedule.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar.dart';
import 'package:doable/src/design_system/components/choice_check.dart';
import 'package:doable/src/design_system/components/choice_row.dart';
import 'package:doable/src/design_system/components/reason_chain.dart';
import 'package:doable/src/design_system/components/section_header.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_priority.dart';
import 'package:doable/src/design_system/doable_type.dart';
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
        // Время есть в невыполненных, поэтому выполненные на весь день тоже
        // стоят под своей подписью.
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
      'время среди выполненных подписывает невыполненные на весь день (${locale.languageCode})',
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
        repository.completeFirst(0, [
          catalogPageItem(1, date: day),
          catalogPageItem(2, date: day),
          catalogPageItem(
            201,
            date: day,
            isCompleted: true,
            schedule: DailyChoiceTime(hour: 18, minute: 0),
          ),
        ], total: 3);
        await tester.pumpAndSettle();
        final context = tester.element(find.byType(DailyChoiceCalendar));
        final l10n = AppLocalizations.of(context);
        // Выбор на весь день есть только среди невыполненных.
        expect(_headers(l10n.dailyChoiceAllDay), 1);
        expect(
          _headers(const TimeOfDay(hour: 18, minute: 0).format(context)),
          1,
        );
        semantics.dispose();
      },
    );

    testWidgets(
      'время в неполученной порции выполненных подписывает оба набора на весь день (${locale.languageCode})',
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
        repository.completeFirst(
          0,
          [
            catalogPageItem(1, date: day),
            catalogPageItem(201, date: day, isCompleted: true),
          ],
          total: 2,
          completedHasTimedChoices: true,
        );
        await tester.pumpAndSettle();
        final l10n = AppLocalizations.of(
          tester.element(find.byType(DailyChoiceCalendar)),
        );
        expect(_headers(l10n.dailyChoiceAllDay), 2);
        semantics.dispose();
      },
    );

    testWidgets(
      'без времени во всём дне подписи на весь день нет ни в одной секции (${locale.languageCode})',
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
        repository.completeFirst(0, [
          catalogPageItem(1, date: day),
          catalogPageItem(201, date: day, isCompleted: true),
        ], total: 2);
        await tester.pumpAndSettle();
        final l10n = AppLocalizations.of(
          tester.element(find.byType(DailyChoiceCalendar)),
        );
        expect(
          find.byKey(const ValueKey('daily-choice-row-1')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('daily-choice-row-2')),
          findsOneWidget,
        );
        expect(_headers(l10n.dailyChoiceAllDay), 0);
        semantics.dispose();
      },
    );

    testWidgets(
      'крупная карточка показывает путь цепочкой и только свои тексты, а время, шаги и приоритет называет диктору (${locale.languageCode})',
      (tester) async {
        final semantics = tester.ensureSemantics();
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final repository = CatalogPageRepository();
        final day = date(2026, 10, 8);
        final description = DailyChoiceDescription.fromInput(
          List.filled(60, 'Полное описание выбора').join(' '),
        );
        final item = catalogPageItem(
          1,
          date: day,
          schedule: DailyChoiceTime(hour: 18, minute: 0),
          priority: DailyChoicePriority.p2,
          description: description,
          pathIntentionCount: 4,
        );
        await pumpCatalogPage(
          tester,
          repository,
          today: day,
          locale: locale,
          size: const Size(360, 900),
        );
        repository.completeFirst(0, [item], total: 1);
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
        expect(
          tester
              .widgetList<Text>(
                find.descendant(
                  of: find.byType(ChoiceRow),
                  matching: find.byType(Text),
                ),
              )
              .map((text) => text.data),
          ['Основание', 'Действие', description.value],
        );
        final chain = tester.widget<ReasonChain>(find.byType(ReasonChain));
        expect(chain.reasons, 3);
        expect(chain.priority, DoablePriority.p2);
        expect(
          tester.widget<ChoiceCheck>(find.byType(ChoiceCheck)).priority,
          DoablePriority.p2,
        );
        final row = tester
            .getSemantics(find.byKey(const ValueKey('daily-choice-row-1')))
            .label;
        final time = const TimeOfDay(hour: 18, minute: 0).format(context);
        expect(row, contains(l10n.dailyChoiceCatalogRowTime(time)));
        expect(row, contains(l10n.dailyChoiceCatalogPathStepCount(3)));
        expect(row, contains(description.value));
        expect(
          tester
              .getSemantics(
                find.byKey(
                  ValueKey(
                    'daily-choice-completion-${item.id.toCanonicalString()}',
                  ),
                ),
              )
              .label,
          contains(l10n.dailyChoicePriorityOption('P2')),
        );
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );
  }

  testWidgets('заголовок секции показывает число её выборов за день, '
      'включая неполученные порции, а свёрнутая секция его сохраняет', (
    tester,
  ) async {
    final repository = CatalogPageRepository();
    final day = date(2026, 10, 8);
    await pumpCatalogPage(
      tester,
      repository,
      today: day,
      locale: const Locale('ru'),
      size: const Size(360, 900),
    );
    repository.completeFirst(
      0,
      [
        catalogPageItem(1, date: day),
        catalogPageItem(2, date: day),
        catalogPageItem(201, date: day, isCompleted: true),
      ],
      total: 6,
      cursor: const CatalogPageCursor(),
    );
    await tester.pumpAndSettle();

    expect(_count(tester, completed: false), '5');
    expect(_count(tester, completed: true), '1');
    expect(find.byType(ChoiceRow), findsNWidgets(3));

    await tester.tap(find.byKey(const ValueKey('daily-choice-section-false')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SectionHeader>(
            find.byKey(const ValueKey('daily-choice-section-false')),
          )
          .open,
      isFalse,
    );
    expect(_count(tester, completed: false), '5');
    expect(find.byType(ChoiceRow), findsOneWidget);
  });

  testWidgets('секция без выборов сохраняет заголовок с числом 0 и не '
      'показывает карточек', (tester) async {
    final repository = CatalogPageRepository();
    final day = date(2026, 10, 8);
    await pumpCatalogPage(
      tester,
      repository,
      today: day,
      locale: const Locale('ru'),
      size: const Size(360, 900),
    );
    repository.completeFirst(0, [
      catalogPageItem(201, date: day, isCompleted: true),
    ], total: 1);
    await tester.pumpAndSettle();

    expect(_count(tester, completed: false), '0');
    expect(_count(tester, completed: true), '1');
    expect(find.byType(ChoiceRow), findsOneWidget);
    expect(
      tester
          .widget<SectionHeader>(
            find.byKey(const ValueKey('daily-choice-section-false')),
          )
          .open,
      isTrue,
    );
  });

  testWidgets('верхняя секция называется «Невыполненные», а нижняя — '
      '«Выполненные»', (tester) async {
    final repository = CatalogPageRepository();
    final day = date(2026, 10, 8);
    await pumpCatalogPage(
      tester,
      repository,
      today: day,
      locale: const Locale('ru'),
      size: const Size(360, 900),
    );
    repository.completeFirst(0, [catalogPageItem(1, date: day)], total: 1);
    await tester.pumpAndSettle();

    expect(
      [
        for (final completed in [false, true])
          tester
              .widget<SectionHeader>(
                find.byKey(ValueKey('daily-choice-section-$completed')),
              )
              .title,
      ],
      ['Невыполненные', 'Выполненные'],
    );
  });

  testWidgets('подпись группы стоит на 6 над первой строкой, строки группы — '
      'через 8, группы — через 16, а первая группа идёт сразу за заголовком '
      'секции', (tester) async {
    final repository = CatalogPageRepository();
    final day = date(2026, 10, 8);
    final morning = DailyChoiceTime(hour: 9, minute: 0);
    final evening = DailyChoiceTime(hour: 18, minute: 0);
    await pumpCatalogPage(
      tester,
      repository,
      today: day,
      locale: const Locale('ru'),
      size: const Size(360, 900),
    );
    repository.completeFirst(0, [
      catalogPageItem(1, date: day, schedule: morning),
      catalogPageItem(2, date: day, schedule: morning),
      catalogPageItem(3, date: day, schedule: evening),
    ], total: 3);
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(DailyChoiceCalendar));
    final morningLabel = find.text(
      const TimeOfDay(hour: 9, minute: 0).format(context),
    );
    final eveningLabel = find.text(
      const TimeOfDay(hour: 18, minute: 0).format(context),
    );
    Rect row(int number) =>
        tester.getRect(find.byKey(ValueKey('daily-choice-row-$number')));

    expect(
      tester.getTopLeft(morningLabel).dy,
      tester
          .getBottomLeft(
            find.byKey(const ValueKey('daily-choice-section-false')),
          )
          .dy,
    );
    expect(row(1).top - tester.getBottomLeft(morningLabel).dy, 6);
    expect(row(2).top - row(1).bottom, 8);
    expect(tester.getTopLeft(eveningLabel).dy - row(2).bottom, 16);
    expect(row(3).top - tester.getBottomLeft(eveningLabel).dy, 6);

    final style = tester.widget<Text>(morningLabel).style!;
    expect(style.fontSize, DoableType.label.fontSize);
    expect(style.fontWeight, DoableType.label.fontWeight);
    expect(style.height, DoableType.label.height);
    expect(style.color, DoableColors.light.muted);
    expect(style.fontFeatures, const [FontFeature.tabularFigures()]);
  });
}

/// Число подписей групп с названием [label] в дереве семантики.
int _headers(String label) => find.semantics
    .byLabel(label)
    .evaluate()
    .where((node) => node.flagsCollection.isHeader)
    .length;

/// Число в счётчике заголовка секции.
String _count(WidgetTester tester, {required bool completed}) {
  final header = find.byKey(ValueKey('daily-choice-section-$completed'));
  return tester
      .widget<Text>(
        find.descendant(
          of: header,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Text &&
                widget.data != null &&
                int.tryParse(widget.data!) != null,
          ),
        ),
      )
      .data!;
}
