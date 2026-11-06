import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/date_grid.dart';
import '../../../design_system/components/sheet.dart';
import '../../../shared/domain/calendar_date.dart';
import '../../../shared/presentation/local_day/local_date_provider.dart';
import '../../../shared/presentation/local_day/local_day_observer.dart';
import '../../application/daily_choice_day_statuses.dart';
import '../catalog/daily_choice_calendar_day_marks_view_model.dart';
import '../catalog/daily_choice_calendar_labels.dart';
import '../catalog/daily_choice_calendar_viewport.dart';
import '../catalog/daily_choice_catalog_instance.dart';

/// Показывает лист даты дневного выбора с месяцем [current].
///
/// Возвращает выбранную дату либо null, если лист закрыт без выбора. Выбор дня,
/// в том числе дня соседнего месяца, закрывает лист. Результат приходит после
/// закрытия листа, поэтому действие над выбранной датой начинается уже без
/// листа на экране.
Future<CalendarDate?> showDailyChoiceDateSheet(
  BuildContext context,
  CalendarDate current,
) => showDoableSheet<CalendarDate>(
  context: context,
  builder: (_, sheet) => _DailyChoiceDateSheet(sheet, current: current),
);

final class _DailyChoiceDateSheet extends ConsumerStatefulWidget {
  const _DailyChoiceDateSheet(this.sheet, {required this.current});

  final SheetPresentation sheet;
  final CalendarDate current;

  @override
  ConsumerState<_DailyChoiceDateSheet> createState() =>
      _DailyChoiceDateSheetState();
}

final class _DailyChoiceDateSheetState
    extends ConsumerState<_DailyChoiceDateSheet> {
  /// Лист держит собственный ключ отметок всё время жизни: его отметки не
  /// зависят от каталога и не меняют его (ADR-0028).
  late final DailyChoiceCatalogInstance _instance;

  /// Лист может остаться открытым после местной полуночи, и тогда прежний день
  /// был бы неверно назван сегодняшним.
  late final LocalDayObserver _localDay;

  /// Первое число показанного месяца.
  late CalendarDate _month;

  @override
  void initState() {
    super.initState();
    _instance = DailyChoiceCatalogInstance(initialDate: widget.current);
    _month = CalendarDate.fromParts(
      widget.current.year,
      widget.current.month,
      1,
    );
    _localDay = LocalDayObserver(
      readLocalDay: ref.read(localDateSourceProvider),
      onTodayChanged: () => setState(() {}),
    );
  }

  @override
  void dispose() {
    _localDay.dispose();
    super.dispose();
  }

  void _showMonth(int offset) {
    final month = DateTime.utc(_month.year, _month.month + offset);
    setState(() {
      _month = CalendarDate.fromParts(month.year, month.month, 1);
    });
    ref
        .read(dailyChoiceCalendarDayMarksViewModelProvider(_instance).notifier)
        .setViewport(
          DailyChoiceCalendarViewport(
            focusedDate: _month,
            mode: DailyChoiceCalendarMode.month,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    // Отказ получения отметок ничего не показывает: дни остаются без отметок.
    final statuses = ref
        .watch(dailyChoiceCalendarDayMarksViewModelProvider(_instance))
        .dayStatuses
        ?.statuses;
    final month = DateTime.utc(_month.year, _month.month);
    return Sheet.untitled(
      widget.sheet,
      label: localizations.dailyChoiceDateSheetLabel,
      child: DateGrid(
        title: dailyChoiceCalendarMonthTitle(context, _month),
        previousLabel: localizations.dailyChoiceCalendarPreviousMonth,
        nextLabel: localizations.dailyChoiceCalendarNextMonth,
        onPrevious: _technical(CalendarDate.earliest).isBefore(month)
            ? () => _showMonth(-1)
            : null,
        onNext:
            _technical(CalendarDate.latest)
                .isAfter(DateTime.utc(month.year, month.month + 1, 0))
            ? () => _showMonth(1)
            : null,
        weekdays: [
          for (var offset = 0; offset < DateTime.daysPerWeek; offset++)
            dailyChoiceCalendarWeekdayLabel(
              context,
              // Названия не зависят от недели: подойдёт любая с понедельника.
              DateTime.utc(2024, 1, 1 + offset),
            ),
        ],
        days: [
          for (var index = 0; index < _gridDays; index++)
            _day(
              context,
              DateTime.utc(
                month.year,
                month.month,
                1 - (month.weekday - DateTime.monday) + index,
              ),
              statuses: statuses,
            ),
        ],
      ),
    );
  }

  DateGridDay _day(
    BuildContext context,
    DateTime day, {
    required Map<CalendarDate, DailyChoiceDayStatus>? statuses,
  }) {
    if (day.isBefore(_technical(CalendarDate.earliest)) ||
        day.isAfter(_technical(CalendarDate.latest))) {
      // Сетка всегда в шесть недель, поэтому последний месяц диапазона
      // показывает дни за его пределом. Такой день не называет дату и ничего
      // не выбирает.
      return DateGridDay(
        text: '${day.day}',
        semanticLabel: MaterialLocalizations.of(context).formatFullDate(day),
        onTap: () {},
        isOutsideMonth: true,
      );
    }
    final date = CalendarDate.fromParts(day.year, day.month, day.day);
    final status = statuses?[date];
    final isOutsideMonth = day.year != _month.year || day.month != _month.month;
    final isToday = date == _localDay.today;
    return DateGridDay(
      text: '${date.day}',
      semanticLabel: dailyChoiceCalendarDayLabel(
        context,
        date: date,
        isToday: isToday,
        status: status,
      ),
      onTap: () => widget.sheet.closeWithChoice(date),
      isSelected: date == widget.current,
      isToday: isToday,
      isOutsideMonth: isOutsideMonth,
      mark: dailyChoiceCalendarDayMark(status),
    );
  }
}

/// Шесть недель постоянно, как в [DateGrid].
const _gridDays = DateTime.daysPerWeek * 6;

/// Технический день в UTC нужен только для расчёта периодов и не задаёт
/// часовой пояс даты.
DateTime _technical(CalendarDate date) =>
    DateTime.utc(date.year, date.month, date.day);
