import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/calendar_date.dart';
import 'daily_choice_calendar_text_metrics.dart';

/// Ячейка допустимого дня встроенного календаря каталога.
///
/// Часть реализации `DailyChoiceCalendar`: признаки ячейки вычисляет календарь
/// из своих входов, а нажатие ячейка передаёт в [onSelected]. Выбранность и
/// «сегодня» отмечаются независимо, поэтому при совпадении дней сохраняются оба
/// признака: на экране выбранный день залит, а сегодняшний обведён, то есть
/// признаки различаются формой, а не только цветом.
///
/// Выделение занимает ячейку за вычетом небольшого зазора и скруглено по
/// короткой стороне: на телефоне при обычном тексте это круг, а когда крупное
/// число переносится на несколько строк, выделение вытягивается по высоте
/// вместе со строкой дней и число остаётся на нём. Высоту строки задаёт
/// [rowHeight].
///
/// Для вспомогательных технологий ячейка — одна кнопка выбора с полной датой
/// и днём недели, состоянием выбранности и отдельной отметкой «сегодня».
/// Доступная активация выполняет то же нажатие, что и касание; число в ячейке
/// остаётся оформлением и отдельно не читается.
final class DailyChoiceCalendarDay extends StatelessWidget {
  const DailyChoiceCalendarDay({
    super.key,
    required this.date,
    required this.isSelected,
    required this.isToday,
    required this.isOutsideMonth,
    required this.onSelected,
  });

  final CalendarDate date;
  final bool isSelected;
  final bool isToday;

  /// День соседнего месяца в месячном представлении.
  final bool isOutsideMonth;

  final VoidCallback onSelected;

  /// Высота строки дней при ширине колонки [columnWidth].
  ///
  /// Число любого дня месяца, в том числе выделенное как сегодняшнее,
  /// помещается в ячейку целиком в текущем масштабе текста: если ширины не
  /// хватает, число переносится, а строка становится выше. Ячейка не ниже
  /// области нажатия.
  static double rowHeight(BuildContext context, {required double columnWidth}) {
    final theme = Theme.of(context);
    final numbers = [for (var day = 1; day <= 31; day++) '$day'];
    final numberHeight = [
      for (final isToday in [false, true])
        tallestTextHeight(
          context,
          texts: numbers,
          style: _numberStyle(theme, isToday: isToday),
          maxWidth: columnWidth - _inset.horizontal - _padding.horizontal,
        ),
    ].reduce(math.max);
    return math.max(
      _minHeight,
      numberHeight + _inset.vertical + _padding.vertical,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final foreground = isSelected
        ? colors.onPrimary
        : isOutsideMonth
        ? colors.onSurfaceVariant
        : colors.onSurface;
    return Semantics(
      container: true,
      button: true,
      selected: isSelected,
      label: _label(context),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onSelected,
        child: ExcludeSemantics(
          child: Padding(
            padding: _inset,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: isSelected ? colors.primary : null,
                shape: StadiumBorder(
                  side: isToday
                      ? BorderSide(
                          color: isSelected ? colors.onPrimary : colors.primary,
                          width: 2,
                        )
                      : BorderSide.none,
                ),
              ),
              child: Padding(
                padding: _padding,
                child: Center(
                  child: Text(
                    '${date.day}',
                    textAlign: TextAlign.center,
                    style: _numberStyle(
                      theme,
                      isToday: isToday,
                    )?.copyWith(color: foreground),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Полная дата с днём недели по текущей локали и, у сегодняшнего дня,
  /// отметка «сегодня».
  String _label(BuildContext context) {
    // Технический `DateTime` в UTC нужен только для форматирования
    // календарных частей и не задаёт часовой пояс даты.
    final fullDate = MaterialLocalizations.of(context)
        .formatFullDate(DateTime.utc(date.year, date.month, date.day));
    return isToday
        ? '$fullDate, ${AppLocalizations.of(context).dailyChoiceCalendarToday}'
        : fullDate;
  }
}

/// Наименьшая высота строки дней: при обычном тексте выделение на телефоне —
/// круг, а ячейка не меньше области нажатия.
const _minHeight = 52.0;

/// Зазор между выделениями соседних дней.
const _inset = EdgeInsets.all(2);

/// Отступ числа от верхнего и нижнего края выделения.
const _padding = EdgeInsets.symmetric(vertical: 4);

TextStyle? _numberStyle(ThemeData theme, {required bool isToday}) => theme
    .textTheme
    .bodyLarge
    ?.copyWith(fontWeight: isToday ? FontWeight.bold : null);
