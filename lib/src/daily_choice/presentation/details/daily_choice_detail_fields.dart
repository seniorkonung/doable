import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/detail_row.dart';
import '../../../design_system/components/priority_picker.dart';
import '../../../design_system/doable_icon.dart';
import '../../../shared/domain/calendar_date.dart';
import '../../../shared/presentation/local_day/local_date_provider.dart';
import '../../../shared/presentation/local_day/local_day_observer.dart';
import '../../domain/daily_choice_priority.dart';
import '../../domain/daily_choice_schedule.dart';
import 'daily_choice_date_sheet.dart';
import 'daily_choice_field_labels.dart';
import 'daily_choice_time_sheet.dart';

/// Поля даты, времени и приоритета дневного выбора: строки «Дата», «Время» и
/// «Приоритет» одинаковы в нижней панели и на подтверждении создания.
///
/// Блок сам открывает листы даты и времени, а о выбранном значении сообщает
/// колбэком. Выбор уже показанного значения ничего не сообщает. Показанное
/// значение меняет потребитель: панель после подтверждённой записи,
/// подтверждение создания — в своём черновике. Без [enabled] листы не
/// открываются, а приоритет не меняется.
final class DailyChoiceDetailFields extends ConsumerStatefulWidget {
  const DailyChoiceDetailFields({
    required this.date,
    required this.schedule,
    required this.priority,
    required this.enabled,
    required this.onDateChanged,
    required this.onScheduleChanged,
    required this.onPriorityChanged,
    super.key,
  });

  final CalendarDate date;
  final DailyChoiceSchedule schedule;
  final DailyChoicePriority priority;
  final bool enabled;
  final ValueChanged<CalendarDate> onDateChanged;
  final ValueChanged<DailyChoiceSchedule> onScheduleChanged;
  final ValueChanged<DailyChoicePriority> onPriorityChanged;

  @override
  ConsumerState<DailyChoiceDetailFields> createState() =>
      _DailyChoiceDetailFieldsState();
}

final class _DailyChoiceDetailFieldsState
    extends ConsumerState<DailyChoiceDetailFields> {
  /// Последняя пилюля приоритета выходит за край содержимого.
  static const double _pickerShift = 2;

  /// Блок может оставаться на экране после местной полуночи, и тогда «Сегодня»
  /// в поле даты стало бы неверным.
  late final LocalDayObserver _localDay;

  @override
  void initState() {
    super.initState();
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

  Future<void> _pickDate() async {
    final date = await showDailyChoiceDateSheet(context, widget.date);
    if (!mounted || date == null || date == widget.date) return;
    widget.onDateChanged(date);
  }

  Future<void> _pickSchedule() async {
    final schedule = await showDailyChoiceTimeSheet(context, widget.schedule);
    if (!mounted || schedule == null || schedule == widget.schedule) return;
    widget.onScheduleChanged(schedule);
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final time = dailyChoiceTimeValue(context, widget.schedule);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DetailRow(
          label: localizations.dailyChoiceFieldDate,
          icon: DoableIconData.calendar,
          value: dailyChoiceDateValue(
            context,
            widget.date,
            today: _localDay.today,
          ),
          valueLabel: localizations.dailyChoiceFieldDateLabel(
            dailyChoiceFullDate(context, widget.date),
          ),
          onPressed: widget.enabled ? () => unawaited(_pickDate()) : null,
        ),
        DetailRow(
          label: localizations.dailyChoiceFieldTime,
          icon: DoableIconData.clock,
          value: time,
          valueLabel: localizations.dailyChoiceFieldTimeLabel(time),
          onPressed: widget.enabled ? () => unawaited(_pickSchedule()) : null,
        ),
        DetailRow.slot(
          label: localizations.dailyChoicePriorityLabel,
          shift: _pickerShift,
          child: PriorityPicker(
            value: dailyChoiceDesignPriority(widget.priority),
            onChange: widget.enabled
                ? (priority) =>
                      widget.onPriorityChanged(dailyChoicePriority(priority))
                : null,
            label: localizations.dailyChoicePriorityLabel,
            name: dailyChoicePriorityName,
            itemLabel: (priority) =>
                dailyChoicePriorityItemLabel(localizations, priority),
          ),
        ),
      ],
    );
  }
}
