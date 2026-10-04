/// Общие шаги управления каталогом дневных выборов в сценариях приложения.
///
/// Сценарий называет только намерение человека — «выбрать день каталога»,
/// «какой день каталог показывает выбранным», «где выбирается день» — и не
/// знает, каким элементом страница позволяет выбрать дату. Шаги действуют и
/// наблюдают через интерфейс каталога и не обращаются к его модели.
///
/// Пока каталог выбирает день текстовым полем с кнопкой применения, шаги
/// используют их. Смена способа выбора дня меняет только этот файл, а не
/// сценарии.
library;

import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_root_pages.dart';

const _dateFieldKey = ValueKey('daily-choice-date-filter');

/// Элемент открытого каталога дневных выборов, которым человек выбирает день.
///
/// Для проверок его размещения на странице: видимости, доступности нажатия и
/// соседства с другими элементами.
final dailyChoiceCatalogDateControl = find.byKey(_dateFieldKey);

/// Выбирает [date] днём открытого каталога дневных выборов.
///
/// Шаг выполняет выбор и не ждёт выдачи этого дня: её дожидается сам
/// сценарий. [tap] — нажатие сценария; по умолчанию [tapWhenFound].
Future<void> selectDailyChoiceCatalogDate(
  WidgetTester tester,
  CalendarDate date, {
  RootPageTap tap = tapWhenFound,
}) async {
  await tap(tester, dailyChoiceCatalogDateControl);
  await tester.enterText(
    dailyChoiceCatalogDateControl,
    date.toCanonicalString(),
  );
  await tap(tester, find.byKey(const ValueKey('daily-choice-apply-date')));
}

/// День, который открытый каталог дневных выборов показывает выбранным.
///
/// Выбор дня прокручивается вместе с выдачей, поэтому шаг читает его и за
/// краем видимой части страницы. Каталог, который не показывает выбранный
/// день, проваливает проверку.
CalendarDate shownDailyChoiceCatalogDate(WidgetTester tester) {
  final shown = tester
      .widget<EditableText>(
        find.descendant(
          of: find.byKey(_dateFieldKey, skipOffstage: false),
          matching: find.byType(EditableText, skipOffstage: false),
        ),
      )
      .controller
      .text;
  try {
    return CalendarDate.parseCanonical(shown);
  } on CalendarDateValidationException {
    fail('Каталог дневных выборов не показывает выбранный день: «$shown».');
  }
}
