/// Общие шаги подтверждения создания дневного выбора.
///
/// Сценарий называет намерение человека: дождаться готового подтверждения,
/// задать дату или приоритет, прочитать показанные значения. Какими полями
/// страница их показывает, знает только этот файл, поэтому смена полей
/// страницы не меняет сценарии.
library;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_priority.dart';
import 'package:doable/src/daily_choice/presentation/editor/daily_choice_creation_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_root_pages.dart';

/// Поле даты: пока оно не показано, подтверждение не готово к вводу.
Finder get _dateField => find.byKey(const ValueKey('daily-choice-date'));

/// Дожидается готового подтверждения создания.
///
/// [waitFor] — ожидание сценария; по умолчанию [pumpUntilFound].
Future<void> awaitDailyChoiceConfirmation(
  WidgetTester tester, {
  RootPageWait waitFor = pumpUntilFound,
}) => waitFor(tester, _dateField);

/// Задаёт создаваемому выбору [date]. Подтверждение уже готово.
Future<void> setDailyChoiceCreationDate(
  WidgetTester tester,
  CalendarDate date,
) => tester.enterText(_dateField, date.toCanonicalString());

/// Задаёт создаваемому выбору [priority]. Подтверждение уже готово. [tap]
/// нажимает выбранный вариант.
Future<void> setDailyChoiceCreationPriority(
  WidgetTester tester,
  DailyChoicePriority priority, {
  RootPageTap tap = tapWhenFound,
}) => tap(tester, _priorityOption(tester, priority));

/// Дата и приоритет, которые подтверждение показывает сейчас.
({CalendarDate date, DailyChoicePriority priority}) shownDailyChoiceCreation(
  WidgetTester tester,
) => (
  date: CalendarDate.parseCanonical(
    tester.widget<TextField>(_dateField).controller!.text,
  ),
  priority: DailyChoicePriority.values.singleWhere(
    (priority) =>
        tester.widget<ChoiceChip>(_priorityOption(tester, priority)).selected,
  ),
);

Finder _priorityOption(WidgetTester tester, DailyChoicePriority priority) {
  final l10n = AppLocalizations.of(
    tester.element(find.byType(DailyChoiceCreationPage)),
  );
  return find.widgetWithText(
    ChoiceChip,
    l10n.dailyChoicePriorityOption(priority.name.toUpperCase()),
  );
}
