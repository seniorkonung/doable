/// Изменения полей, вкладка пути, вход в изменение пути и удаление открытой
/// панели действия так, как их делает человек в приложении.
///
/// Панель открывает сценарий; шаги называют намерение человека и не знают,
/// какими листами и кнопками панель его выполняет. Исход записи шаги не ждут,
/// кроме удаления: его подтверждение закрывает вопрос, а закрытие панели
/// дожидается сценарий.
library;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/design_system/components/action_path.dart' as ui;
import 'package:doable/src/design_system/components/button.dart';
import 'package:doable/src/design_system/components/date_grid.dart';
import 'package:doable/src/design_system/components/detail_row.dart';
import 'package:doable/src/design_system/components/sheet.dart';
import 'package:doable/src/design_system/components/top_bar.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'action_panel_controls.dart';
import 'app_root_pages.dart';

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(actionPanel));

/// Изменение названия и описания на весь экран: пока оно видно, текст не
/// сохранён.
Finder actionPanelTextEdit(WidgetTester tester) =>
    find.widgetWithText(TopBar, _l10n(tester).actionTextEditTitle);

/// Выбирает в листе даты панели [date], когда действие стоит на [from]. Лист
/// закрывается выбором, и запись начинается сама; её исход шаг не ждёт.
/// [tap] нажимает поле «Дата»; остальное происходит внутри листа.
Future<void> chooseActionPanelDate(
  WidgetTester tester,
  CalendarDate date, {
  required CalendarDate from,
  RootPageTap tap = tapWhenFound,
}) async {
  final semantics = tester.ensureSemantics();
  try {
    final l10n = _l10n(tester);
    await tap(
      tester,
      find.descendant(
        of: find.widgetWithText(DetailRow, l10n.actionFieldDate),
        matching: find.byType(Button),
      ),
    );
    await tester.pumpAndSettle();
    // Под листом стоят экран дня и панель с такими же подписями дней.
    final grid = find.descendant(
      of: find.byType(Sheet).last,
      matching: find.byType(DateGrid),
    );
    // Лист открывается на месяце текущей даты действия.
    final months = (date.year - from.year) * 12 + (date.month - from.month);
    for (var step = 0; step < months.abs(); step++) {
      await tester.tap(
        find.descendant(
          of: grid,
          matching: find.bySemanticsLabel(
            months > 0
                ? l10n.actionCalendarNextMonth
                : l10n.actionCalendarPreviousMonth,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }
    final fullDate = MaterialLocalizations.of(tester.element(grid))
        .formatFullDate(DateTime.utc(date.year, date.month, date.day));
    // Подпись дня продолжают «Сегодня» и отметка дня.
    await tester.tap(
      find.descendant(
        of: grid,
        matching: find.bySemanticsLabel(RegExp('^${RegExp.escape(fullDate)}')),
      ),
    );
    await tester.pump();
  } finally {
    semantics.dispose();
  }
}

/// Меняет описание: открывает изменение пунктом меню «Действие», вводит
/// [text] и нажимает «Сохранить». Исход записи шаг не ждёт: изменение
/// скрывается, когда запись подтверждена.
Future<void> saveActionPanelDescription(
  WidgetTester tester,
  String text, {
  RootPageWait waitFor = pumpUntilFound,
  RootPageTap tap = tapWhenFound,
}) async {
  final l10n = _l10n(tester);
  await _chooseOption(tester, tap, l10n.actionOptionEditText);
  await waitFor(tester, actionPanelTextEdit(tester));
  await tester.pumpAndSettle();
  // Первое поле — название, второе — описание.
  await tester.enterText(find.byType(EditableText).at(1), text);
  await tester.pump();
  await tap(tester, find.widgetWithText(Button, l10n.actionTextEditSave));
}

/// Начинает удаление действия: выбирает пункт меню «Действие» и подтверждает
/// вопрос. Закрытие панели после подтверждённого удаления шаг не ждёт.
Future<void> startActionPanelDeletion(
  WidgetTester tester, {
  RootPageTap tap = tapWhenFound,
}) async {
  final l10n = _l10n(tester);
  await _chooseOption(tester, tap, l10n.actionOptionDelete);
  await tap(tester, find.text(l10n.actionDeleteDialogAction));
}

/// Открывает экран «Изменить путь» пунктом меню «Действие».
Future<void> openActionPanelPathEdit(
  WidgetTester tester, {
  RootPageTap tap = tapWhenFound,
}) => _chooseOption(tester, tap, _l10n(tester).actionOptionEditPath);

/// Показывает вкладку сохранённого пути.
Future<void> showActionPanelPath(
  WidgetTester tester, {
  RootPageWait waitFor = pumpUntilFound,
  RootPageTap tap = tapWhenFound,
}) async {
  await waitFor(tester, actionPanelReady);
  // Панель могла ещё въезжать, и нажатие пришлось бы мимо вкладки.
  await tester.pumpAndSettle();
  await tap(
    tester,
    find.descendant(
      of: actionPanel,
      matching: find.text(_l10n(tester).actionPanelPathTab),
    ),
  );
  await tester.pumpAndSettle();
}

/// Названия намерений показанного сохранённого пути от корневого до
/// конечного.
List<String> shownActionPanelPathNames(WidgetTester tester) {
  final path = tester.widget<ui.ActionPath>(find.byType(ui.ActionPath));
  return [path.root.name, for (final link in path.links) link.step.name];
}

/// Открывает страницу намерения [title] нажатием на него в сохранённом пути.
Future<void> openActionPanelPathIntention(
  WidgetTester tester,
  String title, {
  RootPageTap tap = tapWhenFound,
}) => tap(
  tester,
  find.descendant(of: find.byType(ui.ActionPath), matching: find.text(title)),
);

/// Выбирает пункт [name] меню «Действие» в шапке панели.
Future<void> _chooseOption(
  WidgetTester tester,
  RootPageTap tap,
  String name,
) async {
  final semantics = tester.ensureSemantics();
  try {
    await tap(
      tester,
      find.bySemanticsLabel(_l10n(tester).actionPanelOptionsLabel),
    );
    await tester.pumpAndSettle();
    await tap(tester, find.text(name));
  } finally {
    semantics.dispose();
  }
}
