import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/calendar_date.dart';

/// Ячейка допустимого дня встроенного календаря каталога.
///
/// Часть реализации `DailyChoiceCalendar`: признаки ячейки вычисляет календарь
/// из своих входов, а нажатие ячейка передаёт в [onSelected]. Выбранность и
/// «сегодня» отмечаются независимо, поэтому при совпадении дней сохраняются оба
/// признака: на экране выбранный день залит кругом, а сегодняшний обведён, то
/// есть признаки различаются формой, а не только цветом.
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
            padding: const EdgeInsets.all(4),
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? colors.primary : null,
                    border: isToday
                        ? Border.all(
                            color: isSelected
                                ? colors.onPrimary
                                : colors.primary,
                            width: 2,
                          )
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      '${date.day}',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: foreground,
                        fontWeight: isToday ? FontWeight.bold : null,
                      ),
                    ),
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
