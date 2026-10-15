import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/calendar_header.dart';
import '../../../design_system/components/period_picker.dart';
import '../../domain/calendar_date.dart';
import 'daily_choice_calendar_paging.dart';

/// Открытый выбор периода: шапка и сетка заменяют дни календаря.
///
/// Страницы лет и месяцы года живут только в этом виджете. Промежуточные
/// переходы не меняют [focusedDate]; только выбор месяца сообщает его первое
/// число через [onMonthSelected]. Закрытие сообщает [onClose] без выбора.
final class DailyChoiceCalendarPeriodPicker extends StatefulWidget {
  const DailyChoiceCalendarPeriodPicker({
    super.key,
    required this.focusedDate,
    required this.today,
    required this.onMonthSelected,
    required this.onClose,
  });

  final CalendarDate focusedDate;
  final CalendarDate today;
  final ValueChanged<CalendarDate> onMonthSelected;
  final VoidCallback onClose;

  @override
  State<DailyChoiceCalendarPeriodPicker> createState() =>
      _DailyChoiceCalendarPeriodPickerState();
}

final class _DailyChoiceCalendarPeriodPickerState
    extends State<DailyChoiceCalendarPeriodPicker> {
  late _PickerPage _page = _YearsPage.containing(widget.focusedDate.year);

  @override
  void dispose() {
    _page.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (
      title,
      previousLabel,
      nextLabel,
      canGoBack,
      canGoForward,
    ) = switch (_page) {
      _YearsPage(:final firstYear) => (
        '${math.max(firstYear, CalendarDate.earliest.year)}–'
            '${math.min(firstYear + 11, CalendarDate.latest.year)}',
        l10n.dailyChoiceCalendarPreviousYears,
        l10n.dailyChoiceCalendarNextYears,
        firstYear > CalendarDate.earliest.year,
        firstYear + 11 < CalendarDate.latest.year,
      ),
      _MonthsPage(:final year) => (
        '$year',
        l10n.dailyChoiceCalendarPreviousYear,
        l10n.dailyChoiceCalendarNextYear,
        year > CalendarDate.earliest.year,
        year < CalendarDate.latest.year,
      ),
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CalendarHeader(
          title: title,
          previousLabel: previousLabel,
          nextLabel: nextLabel,
          onPrevious: canGoBack ? () => _shiftPage(-1) : null,
          onNext: canGoForward ? () => _shiftPage(1) : null,
          titleAction: (
            semanticLabel: l10n.dailyChoiceCalendarBackToMonthDays,
            isExpanded: true,
            onTap: widget.onClose,
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final layout = PeriodPicker.layoutFor(
              context,
              width: constraints.maxWidth,
              texts: switch (_page) {
                // Цифры PeriodPicker равноширинные: самый длинный год
                // задаёт размер всех страниц, включая крайние блоки.
                // https://api.flutter.dev/flutter/dart-ui/FontFeature/FontFeature.tabularFigures.html
                _YearsPage() => ['${CalendarDate.latest.year}'],
                _MonthsPage(:final year) => _monthCells(
                  context,
                  year,
                  l10n,
                ).map((cell) => cell.text),
              },
            );
            return SizedBox(
              height: layout.height,
              child: switch (_page) {
                final _YearsPage page => PageView.builder(
                  key: ObjectKey(page),
                  controller: page.controller,
                  itemCount: _yearPageCount,
                  onPageChanged: (index) =>
                      setState(() => page.firstYear = _firstYear + index * 12),
                  itemBuilder: (context, index) => PeriodPicker(
                    cells: _yearCells(_firstYear + index * 12, l10n),
                    layout: layout,
                  ),
                ),
                final _MonthsPage page => PageView.builder(
                  key: ObjectKey(page),
                  controller: page.controller,
                  itemCount: _monthPageCount,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (index) => setState(
                    () => page.year = CalendarDate.earliest.year + index,
                  ),
                  itemBuilder: (context, index) => PeriodPicker(
                    cells: _monthCells(
                      context,
                      CalendarDate.earliest.year + index,
                      l10n,
                    ),
                    layout: layout,
                  ),
                ),
              },
            );
          },
        ),
      ],
    );
  }

  void _shiftPage(int direction) {
    final controller = _page.controller;
    final pageCount = switch (_page) {
      _YearsPage() => _yearPageCount,
      _MonthsPage() => _monthPageCount,
    };
    final target = (controller.page!.round() + direction).clamp(
      0,
      pageCount - 1,
    );
    unawaited(
      controller.animateToPage(
        target,
        duration: calendarPageAnimationDuration,
        curve: calendarPageAnimationCurve,
      ),
    );
  }

  List<PeriodPickerCell?> _yearCells(int firstYear, AppLocalizations l10n) => [
    for (var year = firstYear; year < firstYear + 12; year++)
      if (year < CalendarDate.earliest.year || year > CalendarDate.latest.year)
        null
      else
        _yearCell(year, l10n),
  ];

  PeriodPickerCell _yearCell(int year, AppLocalizations l10n) {
    final isCurrent = year == widget.today.year;
    return PeriodPickerCell(
      text: '$year',
      semanticLabel: _periodLabel('$year', isCurrent, l10n),
      isShown: year == widget.focusedDate.year,
      isCurrent: isCurrent,
      onTap: () {
        _page.controller.dispose();
        setState(() => _page = _MonthsPage(year));
      },
    );
  }

  List<PeriodPickerCell> _monthCells(
    BuildContext context,
    int year,
    AppLocalizations l10n,
  ) => [
    for (var month = 1; month <= 12; month++)
      _monthCell(context, year, month, l10n),
  ];

  PeriodPickerCell _monthCell(
    BuildContext context,
    int year,
    int month,
    AppLocalizations l10n,
  ) {
    final date = CalendarDate.fromParts(year, month, 1);
    // Самостоятельное название месяца, как в шапке календаря:
    // https://pub.dev/documentation/intl/latest/intl/DateFormat-class.html
    final name = DateFormat(
      'LLLL',
      Localizations.localeOf(context).toLanguageTag(),
    ).format(DateTime.utc(year, month));
    final title = name[0].toUpperCase() + name.substring(1);
    final isCurrent = year == widget.today.year && month == widget.today.month;
    return PeriodPickerCell(
      text: title,
      semanticLabel: _periodLabel('$title $year', isCurrent, l10n),
      isShown:
          year == widget.focusedDate.year && month == widget.focusedDate.month,
      isCurrent: isCurrent,
      onTap: () => widget.onMonthSelected(date),
    );
  }
}

String _periodLabel(String title, bool isCurrent, AppLocalizations l10n) =>
    isCurrent ? '$title, ${l10n.statisticsCurrentPeriod}' : title;

sealed class _PickerPage {
  const _PickerPage();

  PageController get controller;
}

final class _YearsPage extends _PickerPage {
  _YearsPage(this.firstYear);

  factory _YearsPage.containing(int year) =>
      _YearsPage(2020 + ((year - 2020) / 12).floor() * 12);

  int firstYear;

  // Страница принадлежит открытому выбору, без чтения и записи PageStorage:
  // https://api.flutter.dev/flutter/widgets/PageController/keepPage.html
  @override
  late final controller = PageController(
    initialPage: (firstYear - _firstYear) ~/ 12,
    keepPage: false,
  );
}

final _firstYear = _YearsPage.containing(CalendarDate.earliest.year).firstYear;
final _yearPageCount =
    (_YearsPage.containing(CalendarDate.latest.year).firstYear - _firstYear) ~/
        12 +
    1;

final class _MonthsPage extends _PickerPage {
  _MonthsPage(this.year);

  int year;

  @override
  late final controller = PageController(
    initialPage: year - CalendarDate.earliest.year,
    keepPage: false,
  );
}

final _monthPageCount =
    CalendarDate.latest.year - CalendarDate.earliest.year + 1;
