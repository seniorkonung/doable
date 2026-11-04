import 'package:flutter/material.dart';

import 'calendar_header.dart';
import 'day_mark.dart';
import 'month_grid_day.dart';
import 'month_grid_weekday.dart';

/// Готовые данные дня сетки; выбором даты управляет потребитель.
///
/// [semanticLabel] содержит полное доступное название дня: дату с днём недели
/// и «сегодня», если оно есть.
final class DateGridDay {
  const DateGridDay({
    required this.text,
    required this.semanticLabel,
    required this.onTap,
    this.isSelected = false,
    this.isToday = false,
    this.isOutsideMonth = false,
    this.mark = DayMark.none,
  });

  final String text;
  final String semanticLabel;
  final VoidCallback onTap;
  final bool isSelected;
  final bool isToday;

  /// День соседнего месяца: он нажимается, как день показанного.
  final bool isOutsideMonth;

  final DayMark mark;
}

/// Месяц для выбора одной даты: шапка с месяцем и годом, подписи дней недели
/// и шесть недель дней.
///
/// Заголовок шапки — текст, а не кнопка: выбора года и месяца у сетки нет.
/// Стрелки без обработчика недоступны. Подписи дней недели высотой 28 идут
/// с понедельника, а доступные названия дней уже называют день недели, поэтому
/// диктор подписи отдельно не читает. Дни идут по семь в неделе, начиная
/// с понедельника, и занимают всю ширину без боковых полей: поля содержимого
/// задаёт лист. Строки одной высоты по самому широкому числу при текущем
/// масштабе текста.
///
/// Сетка не хранит состояния: тексты, отметки, доступные названия и обработчики
/// задаёт потребитель. Выбор нескольких дат и перенос выделения не реализованы.
final class DateGrid extends StatelessWidget {
  const DateGrid({
    super.key,
    required this.title,
    required this.previousLabel,
    required this.nextLabel,
    required this.onPrevious,
    required this.onNext,
    required this.weekdays,
    required this.days,
  }) : assert(weekdays.length == DateTime.daysPerWeek),
       assert(days.length == DateTime.daysPerWeek * _weeks);

  /// Готовый заголовок: «Октябрь 2026».
  final String title;
  final String previousLabel;
  final String nextLabel;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  /// Семь коротких подписей, начиная с понедельника.
  final List<String> weekdays;

  /// Сорок два дня шести недель, начиная с понедельника первой из них.
  final List<DateGridDay> days;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      CalendarHeader(
        title: title,
        previousLabel: previousLabel,
        nextLabel: nextLabel,
        onPrevious: onPrevious,
        onNext: onNext,
      ),
      LayoutBuilder(
        builder: (context, constraints) {
          // Высоты считаются по ширине колонки, как у календаря каталога.
          final columnWidth = (constraints.maxWidth / DateTime.daysPerWeek)
              .floorToDouble();
          final weekdayHeight = MonthGridWeekday.rowHeight(
            context,
            texts: weekdays,
            columnWidth: columnWidth,
          );
          final dayHeight = MonthGridDay.rowHeight(
            context,
            dayTexts: days.map((day) => day.text),
            columnWidth: columnWidth,
          );
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: weekdayHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final text in weekdays)
                      Expanded(
                        child: ExcludeSemantics(
                          child: MonthGridWeekday(text: text),
                        ),
                      ),
                  ],
                ),
              ),
              for (var week = 0; week < _weeks; week++)
                SizedBox(
                  height: dayHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final day
                          in days
                              .skip(week * DateTime.daysPerWeek)
                              .take(DateTime.daysPerWeek))
                        Expanded(
                          child: MonthGridDay(
                            dayText: day.text,
                            isSelected: day.isSelected,
                            isToday: day.isToday,
                            isOutsideMonth: day.isOutsideMonth,
                            mark: day.mark,
                            semanticLabel: day.semanticLabel,
                            onTap: day.onTap,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    ],
  );
}

/// Шесть недель постоянно: список под сеткой не прыгает между месяцами.
const _weeks = 6;
