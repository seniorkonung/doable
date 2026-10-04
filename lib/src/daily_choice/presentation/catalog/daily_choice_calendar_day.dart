import 'package:flutter/material.dart';

import '../../domain/calendar_date.dart';

/// Ячейка допустимого дня встроенного календаря каталога.
///
/// Часть реализации `DailyChoiceCalendar`: признаки ячейки вычисляет календарь
/// из своих входов, он же обрабатывает нажатие. Выбранность и «сегодня»
/// отмечаются независимо, поэтому при совпадении дней сохраняются оба
/// признака.
final class DailyChoiceCalendarDay extends StatelessWidget {
  const DailyChoiceCalendarDay({
    super.key,
    required this.date,
    required this.isSelected,
    required this.isToday,
    required this.isOutsideMonth,
  });

  final CalendarDate date;
  final bool isSelected;
  final bool isToday;

  /// День соседнего месяца в месячном представлении.
  final bool isOutsideMonth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final foreground = isSelected
        ? colors.onPrimary
        : isOutsideMonth
        ? colors.onSurfaceVariant
        : colors.onSurface;
    return Padding(
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
                      color: isSelected ? colors.onPrimary : colors.primary,
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
    );
  }
}
