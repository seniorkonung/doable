import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/detail_row.dart';
import '../../../design_system/components/priority_picker.dart';
import '../../../design_system/doable_icon.dart';
import '../../../shared/domain/calendar_date.dart';
import '../../domain/action_priority.dart';
import '../../domain/action_schedule.dart';
import 'action_date_sheet.dart';
import 'action_field_labels.dart';
import 'action_time_sheet.dart';

/// Поля даты, времени и приоритета действия: строки «Дата», «Время» и
/// «Приоритет» вкладки «Обзор».
///
/// Блок сам открывает листы даты и времени, а о выбранном значении сообщает
/// колбэком. Выбор уже показанного значения ничего не сообщает. Показанное
/// значение меняет потребитель после подтверждённой записи. Без [enabled]
/// листы не открываются, а приоритет не меняется.
final class ActionPanelFields extends StatelessWidget {
  const ActionPanelFields({
    required this.date,
    required this.schedule,
    required this.priority,
    required this.today,
    required this.enabled,
    required this.onDateChanged,
    required this.onScheduleChanged,
    required this.onPriorityChanged,
    super.key,
  });

  final CalendarDate date;
  final ActionSchedule schedule;
  final ActionPriority priority;

  /// Местная дата, от которой поле даты называет «Сегодня» и соседние дни;
  /// потребитель обновляет её после местной полуночи.
  final CalendarDate today;
  final bool enabled;
  final ValueChanged<CalendarDate> onDateChanged;
  final ValueChanged<ActionSchedule> onScheduleChanged;
  final ValueChanged<ActionPriority> onPriorityChanged;

  /// Последняя пилюля приоритета выходит за край содержимого.
  static const double _pickerShift = 2;

  Future<void> _pickDate(BuildContext context) async {
    final picked = await showActionDateSheet(context, date);
    if (!context.mounted || picked == null || picked == date) return;
    onDateChanged(picked);
  }

  Future<void> _pickSchedule(BuildContext context) async {
    final picked = await showActionTimeSheet(context, schedule);
    if (!context.mounted || picked == null || picked == schedule) return;
    onScheduleChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final time = actionTimeValue(context, schedule);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DetailRow(
          label: localizations.actionFieldDate,
          icon: DoableIconData.calendar,
          value: actionDateValue(context, date, today: today),
          valueLabel: localizations.actionFieldDateLabel(
            actionFullDate(context, date),
          ),
          onPressed: enabled ? () => unawaited(_pickDate(context)) : null,
        ),
        DetailRow(
          label: localizations.actionFieldTime,
          icon: DoableIconData.clock,
          value: time,
          valueLabel: localizations.actionFieldTimeLabel(time),
          onPressed: enabled ? () => unawaited(_pickSchedule(context)) : null,
        ),
        DetailRow.slot(
          label: localizations.actionFieldPriority,
          shift: _pickerShift,
          child: PriorityPicker(
            value: actionDesignPriority(priority),
            onChange: enabled
                ? (value) => onPriorityChanged(actionPriority(value))
                : null,
            label: localizations.actionFieldPriority,
            name: actionPriorityName,
            itemLabel: (value) => actionPriorityItemLabel(localizations, value),
          ),
        ),
      ],
    );
  }
}
