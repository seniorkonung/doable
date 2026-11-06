import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/date_grid.dart';
import '../../../design_system/components/day_mark.dart';
import '../../../design_system/components/sheet.dart';
import '../../../graph/application/graph_command_result.dart';
import '../../../graph/application/personal_graph_repository.dart';
import '../../../graph/application/personal_graph_repository_provider.dart';
import '../../../shared/domain/calendar_date.dart';
import '../../../shared/presentation/local_day/local_date_provider.dart';
import '../../../shared/presentation/local_day/local_day_observer.dart';
import '../../application/action_day_statuses.dart';

/// Показывает лист даты действия с месяцем [current].
///
/// Возвращает выбранную дату либо null, если лист закрыт без выбора. Выбор дня,
/// в том числе дня соседнего месяца, закрывает лист. Результат приходит после
/// закрытия листа, поэтому действие над выбранной датой начинается уже без
/// листа на экране.
Future<CalendarDate?> showActionDateSheet(
  BuildContext context,
  CalendarDate current,
) => showDoableSheet<CalendarDate>(
  context: context,
  builder: (_, sheet) => _ActionDateSheet(sheet, current: current),
);

final class _ActionDateSheet extends ConsumerStatefulWidget {
  const _ActionDateSheet(this.sheet, {required this.current});

  final SheetPresentation sheet;
  final CalendarDate current;

  @override
  ConsumerState<_ActionDateSheet> createState() => _ActionDateSheetState();
}

final class _ActionDateSheetState extends ConsumerState<_ActionDateSheet> {
  late final PersonalGraphRepository _repository;

  /// Лист может остаться открытым после местной полуночи, и тогда прежний день
  /// был бы неверно назван сегодняшним.
  late final LocalDayObserver _localDay;

  /// Первое число показанного месяца.
  late CalendarDate _month;

  /// Состояния дней, полученные для показанных месяцев. Дни без полученного
  /// состояния остаются без отметки, в том числе после отказа чтения.
  var _statuses = const <CalendarDate, ActionDayStatus>{};
  var _readGeneration = 0;

  @override
  void initState() {
    super.initState();
    _repository = ref.read(personalGraphRepositoryProvider);
    _month = CalendarDate.fromParts(
      widget.current.year,
      widget.current.month,
      1,
    );
    _localDay = LocalDayObserver(
      readLocalDay: ref.read(localDateSourceProvider),
      onTodayChanged: () => setState(() {}),
    );
    unawaited(_readMarks());
  }

  @override
  void dispose() {
    _localDay.dispose();
    super.dispose();
  }

  /// Читает состояния дней сетки показанного месяца. Ответ на уже
  /// пролистанный месяц не заменяет более новый.
  Future<void> _readMarks() async {
    final generation = ++_readGeneration;
    final first = _gridStart(_month);
    final result = await _repository.getActionDayStatuses(
      ActionDayStatusQuery(
        firstDate: _clamped(first),
        lastDate: _clamped(first.add(const Duration(days: _gridDays - 1))),
      ),
    );
    if (!mounted || generation != _readGeneration) return;
    if (result case GraphResultSuccess(:final value)) {
      setState(() => _statuses = {..._statuses, ...value.value.statuses});
    }
  }

  void _showMonth(int offset) {
    final month = DateTime.utc(_month.year, _month.month + offset);
    setState(() {
      _month = CalendarDate.fromParts(month.year, month.month, 1);
    });
    unawaited(_readMarks());
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final month = DateTime.utc(_month.year, _month.month);
    final first = _gridStart(_month);
    return Sheet.untitled(
      widget.sheet,
      label: localizations.actionDateSheetLabel,
      child: DateGrid(
        title: _monthTitle(context, month),
        previousLabel: localizations.actionCalendarPreviousMonth,
        nextLabel: localizations.actionCalendarNextMonth,
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
            _weekdayLabel(
              context,
              // Названия не зависят от недели: подойдёт любая с понедельника.
              DateTime.utc(2024, 1, 1 + offset),
            ),
        ],
        days: [
          for (var index = 0; index < _gridDays; index++)
            _day(context, first.add(Duration(days: index))),
        ],
      ),
    );
  }

  DateGridDay _day(BuildContext context, DateTime day) {
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
    final status = _statuses[date];
    final isOutsideMonth = day.year != _month.year || day.month != _month.month;
    final isToday = date == _localDay.today;
    return DateGridDay(
      text: '${date.day}',
      semanticLabel: _dayLabel(
        context,
        date: date,
        isToday: isToday,
        status: status,
      ),
      onTap: () => widget.sheet.closeWithChoice(date),
      isSelected: date == widget.current,
      isToday: isToday,
      isOutsideMonth: isOutsideMonth,
      mark: switch (status) {
        null => DayMark.none,
        ActionDayStatus.hasIncomplete => DayMark.todo,
        ActionDayStatus.allCompleted => DayMark.done,
      },
    );
  }

  /// Полная дата с днём недели и, у сегодняшнего дня, слово «сегодня», затем
  /// состояние дня, если оно известно.
  String _dayLabel(
    BuildContext context, {
    required CalendarDate date,
    required bool isToday,
    required ActionDayStatus? status,
  }) {
    final localizations = AppLocalizations.of(context);
    return [
      MaterialLocalizations.of(context).formatFullDate(_technical(date)),
      if (isToday) localizations.actionDateToday,
      ?switch (status) {
        null => null,
        ActionDayStatus.allCompleted =>
          localizations.actionCalendarDayAllCompleted,
        ActionDayStatus.hasIncomplete =>
          localizations.actionCalendarDayHasIncomplete,
      },
    ].join(', ');
  }
}

/// Шесть недель постоянно, как в [DateGrid].
const _gridDays = DateTime.daysPerWeek * 6;

/// Понедельник недели, с которой начинается сетка месяца [month].
DateTime _gridStart(CalendarDate month) {
  final first = _technical(month);
  return DateTime.utc(
    first.year,
    first.month,
    1 - (first.weekday - DateTime.monday),
  );
}

CalendarDate _clamped(DateTime day) {
  if (day.isBefore(_technical(CalendarDate.earliest))) {
    return CalendarDate.earliest;
  }
  if (day.isAfter(_technical(CalendarDate.latest))) {
    return CalendarDate.latest;
  }
  return CalendarDate.fromParts(day.year, day.month, day.day);
}

/// Технический день в UTC нужен только для расчёта периодов и не задаёт
/// часовой пояс даты.
DateTime _technical(CalendarDate date) =>
    DateTime.utc(date.year, date.month, date.day);

String _weekdayLabel(BuildContext context, DateTime day) {
  final label = DateFormat.E(Localizations.localeOf(context).toLanguageTag())
      .format(day);
  return label[0].toUpperCase() + label.substring(1);
}

/// Заголовок месяца: «Октябрь 2026».
String _monthTitle(BuildContext context, DateTime month) {
  // L — самостоятельная форма названия месяца, без суффикса года:
  // https://pub.dev/documentation/intl/latest/intl/DateFormat-class.html
  final title = DateFormat(
    'LLLL y',
    Localizations.localeOf(context).toLanguageTag(),
  ).format(month);
  return title[0].toUpperCase() + title.substring(1);
}
