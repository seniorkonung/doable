import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/calendar_header.dart';
import '../../../design_system/components/period_picker.dart';
import '../../domain/calendar_date.dart';

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
    final cells = switch (_page) {
      _YearsPage(:final firstYear) => [
        for (var year = firstYear; year < firstYear + 12; year++)
          if (year < CalendarDate.earliest.year ||
              year > CalendarDate.latest.year)
            null
          else
            _yearCell(year, l10n),
      ],
      _MonthsPage(:final year) => [
        for (var month = 1; month <= 12; month++)
          _monthCell(context, year, month, l10n),
      ],
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
                _MonthsPage() => cells.nonNulls.map((cell) => cell.text),
              },
            );
            return SizedBox(
              height: layout.height,
              child: PeriodPicker(cells: cells, layout: layout),
            );
          },
        ),
      ],
    );
  }

  void _shiftPage(int direction) => setState(() {
    _page = switch (_page) {
      _YearsPage(:final firstYear) => _YearsPage(firstYear + direction * 12),
      _MonthsPage(:final year) => _MonthsPage(year + direction),
    };
  });

  PeriodPickerCell _yearCell(int year, AppLocalizations l10n) {
    final isCurrent = year == widget.today.year;
    return PeriodPickerCell(
      text: '$year',
      semanticLabel: _periodLabel('$year', isCurrent, l10n),
      isShown: year == widget.focusedDate.year,
      isCurrent: isCurrent,
      onTap: () => setState(() => _page = _MonthsPage(year)),
    );
  }

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
}

final class _YearsPage extends _PickerPage {
  const _YearsPage(this.firstYear);

  factory _YearsPage.containing(int year) =>
      _YearsPage(2020 + ((year - 2020) / 12).floor() * 12);

  final int firstYear;
}

final class _MonthsPage extends _PickerPage {
  const _MonthsPage(this.year);

  final int year;
}
