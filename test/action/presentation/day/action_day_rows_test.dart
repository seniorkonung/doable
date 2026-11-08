import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/action/application/action_day.dart';
import 'package:doable/src/action/domain/action_priority.dart';
import 'package:doable/src/action/domain/action_schedule.dart';
import 'package:doable/src/action/domain/action_text.dart';
import 'package:doable/src/action/presentation/day/action_day_calendar.dart';
import 'package:doable/src/design_system/components/action_check.dart';
import 'package:doable/src/design_system/components/action_row.dart';
import 'package:doable/src/design_system/components/reason_chain.dart';
import 'package:doable/src/design_system/components/section_header.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_priority.dart';
import 'package:doable/src/design_system/doable_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/action_day_controls.dart';
import 'action_day_calendar_test_support.dart';
import 'action_day_page_test_support.dart';

void main() {
  for (final locale in const [Locale('ru'), Locale('en')]) {
    testWidgets(
      'группы учитывают весь остаток своей секции, продолжение не повторяет заголовок (${locale.languageCode})',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final repository = ActionDayRepository();
        final day = date(2026, 10, 8);
        await pumpActionDay(
          tester,
          repository,
          today: day,
          locale: locale,
          size: const Size(360, 900),
        );
        final context = tester.element(find.byType(ActionDayCalendar));
        final l10n = AppLocalizations.of(context);
        final morning = ActionAtHour(9);
        repository.completeFirst(
          0,
          [
            for (var number = 1; number <= 50; number++)
              actionDayItem(number, date: day),
            actionDayItem(201, date: day, isCompleted: true),
          ],
          total: 103,
          cursor: const ActionDayTestCursor(),
          hasTimedActions: true,
        );
        await tester.pumpAndSettle();
        expect(
          actionDaySectionCount(tester, section: ActionDaySection.incomplete),
          '102',
        );
        expect(
          find.semantics
              .byLabel(l10n.actionAllDay)
              .evaluate()
              .single
              .flagsCollection
              .isHeader,
          isTrue,
        );
        await tester.tap(
          find.byKey(const ValueKey('action-day-section-incomplete')),
        );
        await tester.pumpAndSettle();
        // Время есть в невыполненных, поэтому выполненные на весь день тоже
        // стоят под своей подписью.
        expect(
          find.semantics
              .byLabel(l10n.actionAllDay)
              .evaluate()
              .single
              .flagsCollection
              .isHeader,
          isTrue,
        );
        await tester.tap(
          find.byKey(const ValueKey('action-day-section-incomplete')),
        );
        await tester.pumpAndSettle();
        await scrollToActionDayEnd(tester, ActionDaySection.incomplete);
        repository.completeMore(1, [
          for (var number = 51; number <= 100; number++)
            actionDayItem(number, date: day, schedule: morning),
        ], cursor: const ActionDayTestCursor());
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
        await scrollToActionDayEnd(tester, ActionDaySection.incomplete);
        repository.completeMore(2, [
          actionDayItem(101, date: day, schedule: morning),
          actionDayItem(102, date: day, schedule: ActionAtHour(18)),
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
        final repository = ActionDayRepository();
        final day = date(2026, 10, 8);
        await pumpActionDay(
          tester,
          repository,
          today: day,
          locale: locale,
          size: const Size(360, 900),
        );
        repository.completeFirst(0, [
          actionDayItem(1, date: day),
          actionDayItem(2, date: day),
          actionDayItem(
            201,
            date: day,
            isCompleted: true,
            schedule: ActionAtHour(18),
          ),
        ], total: 3);
        await tester.pumpAndSettle();
        final context = tester.element(find.byType(ActionDayCalendar));
        final l10n = AppLocalizations.of(context);
        // Действие на весь день есть только среди невыполненных.
        expect(_headers(l10n.actionAllDay), 1);
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
        final repository = ActionDayRepository();
        final day = date(2026, 10, 8);
        await pumpActionDay(
          tester,
          repository,
          today: day,
          locale: locale,
          size: const Size(360, 900),
        );
        repository.completeFirst(
          0,
          [
            actionDayItem(1, date: day),
            actionDayItem(201, date: day, isCompleted: true),
          ],
          total: 2,
          hasTimedActions: true,
        );
        await tester.pumpAndSettle();
        final l10n = AppLocalizations.of(
          tester.element(find.byType(ActionDayCalendar)),
        );
        expect(_headers(l10n.actionAllDay), 2);
        semantics.dispose();
      },
    );

    testWidgets(
      'без времени во всём дне подписи на весь день нет ни в одной секции (${locale.languageCode})',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final repository = ActionDayRepository();
        final day = date(2026, 10, 8);
        await pumpActionDay(
          tester,
          repository,
          today: day,
          locale: locale,
          size: const Size(360, 900),
        );
        repository.completeFirst(0, [
          actionDayItem(1, date: day),
          actionDayItem(201, date: day, isCompleted: true),
        ], total: 2);
        await tester.pumpAndSettle();
        final l10n = AppLocalizations.of(
          tester.element(find.byType(ActionDayCalendar)),
        );
        expect(find.byKey(const ValueKey('action-day-row-1')), findsOneWidget);
        expect(find.byKey(const ValueKey('action-day-row-2')), findsOneWidget);
        expect(_headers(l10n.actionAllDay), 0);
        semantics.dispose();
      },
    );

    testWidgets(
      'крупная карточка показывает путь цепочкой и только свои тексты, а время, шаги и приоритет называет диктору (${locale.languageCode})',
      (tester) async {
        final semantics = tester.ensureSemantics();
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final repository = ActionDayRepository();
        final day = date(2026, 10, 8);
        final description = ActionDescription.fromInput(
          List.filled(60, 'Полное описание действия').join(' '),
        );
        final item = actionDayItem(
          1,
          date: day,
          schedule: ActionAtHour(18),
          priority: ActionPriority.p2,
          description: description,
          pathIntentionCount: 4,
        );
        await pumpActionDay(
          tester,
          repository,
          today: day,
          locale: locale,
          size: const Size(360, 900),
        );
        repository.completeFirst(0, [item], total: 1);
        await tester.pumpAndSettle();
        final context = tester.element(find.byType(ActionDayCalendar));
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
                  of: find.byType(ActionRow),
                  matching: find.byType(Text),
                ),
              )
              .map((text) => text.data),
          ['Основание', 'Действие', description.value],
        );
        final chain = tester.widget<ReasonChain>(find.byType(ReasonChain));
        expect(chain.reasons, 4);
        expect(chain.priority, DoablePriority.p2);
        expect(
          tester.widget<ActionCheck>(find.byType(ActionCheck)).priority,
          DoablePriority.p2,
        );
        final row = tester
            .getSemantics(find.byKey(const ValueKey('action-day-row-1')))
            .label;
        final time = const TimeOfDay(hour: 18, minute: 0).format(context);
        expect(row, contains(l10n.actionDayRowTime(time)));
        expect(row, contains(l10n.actionDayPathIntentionCount(4)));
        expect(row, contains(description.value));
        expect(
          tester
              .getSemantics(
                find.byKey(
                  ValueKey(
                    'action-day-completion-${item.id.toCanonicalString()}',
                  ),
                ),
              )
              .label,
          contains(l10n.actionPriorityOption('P2')),
        );
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );
  }

  testWidgets('заголовок секции показывает число её действий за день, '
      'включая неполученные порции, а свёрнутая секция его сохраняет', (
    tester,
  ) async {
    final repository = ActionDayRepository();
    final day = date(2026, 10, 8);
    await pumpActionDay(
      tester,
      repository,
      today: day,
      locale: const Locale('ru'),
      size: const Size(360, 900),
    );
    repository.completeFirst(
      0,
      [
        actionDayItem(1, date: day),
        actionDayItem(2, date: day),
        actionDayItem(201, date: day, isCompleted: true),
      ],
      total: 6,
      cursor: const ActionDayTestCursor(),
    );
    await tester.pump();
    await tester.pump();

    expect(
      actionDaySectionCount(tester, section: ActionDaySection.incomplete),
      '5',
    );
    expect(
      actionDaySectionCount(tester, section: ActionDaySection.completed),
      '1',
    );
    expect(find.byType(ActionRow), findsNWidgets(3));

    await tester.tap(
      find.byKey(const ValueKey('action-day-section-incomplete')),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SectionHeader>(
            find.byKey(const ValueKey('action-day-section-incomplete')),
          )
          .open,
      isFalse,
    );
    expect(
      actionDaySectionCount(tester, section: ActionDaySection.incomplete),
      '5',
    );
    expect(find.byType(ActionRow), findsOneWidget);
  });

  testWidgets('секция без действий сохраняет заголовок с числом 0 и не '
      'показывает карточек', (tester) async {
    final repository = ActionDayRepository();
    final day = date(2026, 10, 8);
    await pumpActionDay(
      tester,
      repository,
      today: day,
      locale: const Locale('ru'),
      size: const Size(360, 900),
    );
    repository.completeFirst(0, [
      actionDayItem(201, date: day, isCompleted: true),
    ], total: 1);
    await tester.pumpAndSettle();

    expect(
      actionDaySectionCount(tester, section: ActionDaySection.incomplete),
      '0',
    );
    expect(
      actionDaySectionCount(tester, section: ActionDaySection.completed),
      '1',
    );
    expect(find.byType(ActionRow), findsOneWidget);
    expect(
      tester
          .widget<SectionHeader>(
            find.byKey(const ValueKey('action-day-section-incomplete')),
          )
          .open,
      isTrue,
    );
  });

  testWidgets('верхняя секция называется «Невыполненные», а нижняя — '
      '«Выполненные»', (tester) async {
    final repository = ActionDayRepository();
    final day = date(2026, 10, 8);
    await pumpActionDay(
      tester,
      repository,
      today: day,
      locale: const Locale('ru'),
      size: const Size(360, 900),
    );
    repository.completeFirst(0, [actionDayItem(1, date: day)], total: 1);
    await tester.pumpAndSettle();

    expect(
      [
        for (final section in ActionDaySection.values)
          tester
              .widget<SectionHeader>(
                find.byKey(ValueKey('action-day-section-${section.name}')),
              )
              .title,
      ],
      ['Невыполненные', 'Выполненные'],
    );
  });

  testWidgets('подпись группы стоит на 6 над первой строкой, строки группы — '
      'через 8, группы — через 16, а первая группа идёт сразу за заголовком '
      'секции', (tester) async {
    final repository = ActionDayRepository();
    final day = date(2026, 10, 8);
    final morning = ActionAtHour(9);
    final evening = ActionAtHour(18);
    await pumpActionDay(
      tester,
      repository,
      today: day,
      locale: const Locale('ru'),
      size: const Size(360, 900),
    );
    repository.completeFirst(0, [
      actionDayItem(1, date: day, schedule: morning),
      actionDayItem(2, date: day, schedule: morning),
      actionDayItem(3, date: day, schedule: evening),
    ], total: 3);
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(ActionDayCalendar));
    final morningLabel = find.text(
      const TimeOfDay(hour: 9, minute: 0).format(context),
    );
    final eveningLabel = find.text(
      const TimeOfDay(hour: 18, minute: 0).format(context),
    );
    Rect row(int number) =>
        tester.getRect(find.byKey(ValueKey('action-day-row-$number')));

    expect(
      tester.getTopLeft(morningLabel).dy,
      tester
          .getBottomLeft(
            find.byKey(const ValueKey('action-day-section-incomplete')),
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
