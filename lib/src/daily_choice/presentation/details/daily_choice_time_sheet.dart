import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/sheet.dart';
import '../../../design_system/components/time_dial.dart';
import '../../domain/daily_choice_schedule.dart';
import 'daily_choice_field_labels.dart';

/// Показывает лист времени дневного выбора с отметкой [current].
///
/// Возвращает выбранное время либо null, если лист закрыт без выбора. Час
/// даёт время с нулевыми минутами: запрет минут живёт только здесь, домен не
/// сужается. Результат приходит после закрытия листа, поэтому действие над
/// выбранным значением начинается уже без листа на экране.
Future<DailyChoiceSchedule?> showDailyChoiceTimeSheet(
  BuildContext context,
  DailyChoiceSchedule current,
) => showDoableSheet<DailyChoiceSchedule>(
  context: context,
  builder: (_, sheet) => _DailyChoiceTimeSheet(sheet, current: current),
);

final class _DailyChoiceTimeSheet extends StatelessWidget {
  const _DailyChoiceTimeSheet(this.sheet, {required this.current});

  final SheetPresentation sheet;
  final DailyChoiceSchedule current;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final allDayLabel = dailyChoiceTimeValue(
      context,
      const DailyChoiceAllDay(),
    );
    return Sheet.untitled(
      sheet,
      label: localizations.dailyChoiceTimeSheetLabel,
      child: TimeDial(
        clock: _clock(context, localizations),
        selection: switch (current) {
          DailyChoiceAllDay() => const TimeDialSelectedAllDay(),
          DailyChoiceTime(:final hour, minute: 0) => TimeDialSelectedHour(hour),
          // Время с минутами не лежит на циферблате: не отмечено ничего.
          DailyChoiceTime() => const TimeDialNothingSelected(),
        },
        allDayLabel: allDayLabel,
        allDayHint: allDayLabel,
        hourLabel: (hour) => dailyChoiceTimeValue(
          context,
          DailyChoiceTime(hour: hour, minute: 0),
        ),
        onPickHour: (hour) =>
            sheet.closeWithChoice(DailyChoiceTime(hour: hour, minute: 0)),
        onAllDay: () => sheet.closeWithChoice(const DailyChoiceAllDay()),
      ),
    );
  }

  /// Формат циферблата следует настройке 24-часового времени устройства, а
  /// 12-часовой открывается на половине суток текущего времени.
  TimeDialClock _clock(BuildContext context, AppLocalizations localizations) {
    if (MediaQuery.alwaysUse24HourFormatOf(context)) {
      return const TimeDialClock24();
    }
    final material = MaterialLocalizations.of(context);
    return TimeDialClock12(
      initialHalf: switch (current) {
        DailyChoiceTime(:final hour) when hour >= 12 => TimeDialHalf.pm,
        DailyChoiceTime() || DailyChoiceAllDay() => TimeDialHalf.am,
      },
      switchLabel: localizations.dailyChoiceTimeHalfSwitchLabel,
      am: TimeDialHalfLabel(
        text: material.anteMeridiemAbbreviation,
        semanticLabel: localizations.dailyChoiceTimeAmLabel,
      ),
      pm: TimeDialHalfLabel(
        text: material.postMeridiemAbbreviation,
        semanticLabel: localizations.dailyChoiceTimePmLabel,
      ),
    );
  }
}
