import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/sheet.dart';
import '../../../design_system/components/time_dial.dart';
import '../../domain/action_schedule.dart';
import 'action_field_labels.dart';

/// Показывает лист времени действия с отметкой [current].
///
/// Возвращает выбранное время либо null, если лист закрыт без выбора. Результат
/// приходит после закрытия листа, поэтому действие над выбранным значением
/// начинается уже без листа на экране.
Future<ActionSchedule?> showActionTimeSheet(
  BuildContext context,
  ActionSchedule current,
) => showDoableSheet<ActionSchedule>(
  context: context,
  builder: (_, sheet) => _ActionTimeSheet(sheet, current: current),
);

final class _ActionTimeSheet extends StatelessWidget {
  const _ActionTimeSheet(this.sheet, {required this.current});

  final SheetPresentation sheet;
  final ActionSchedule current;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Sheet.untitled(
      sheet,
      label: localizations.actionTimeSheetLabel,
      child: TimeDial(
        clock: _clock(context, localizations),
        selection: switch (current) {
          ActionAllDay() => const TimeDialSelectedAllDay(),
          ActionAtHour(:final hour) => TimeDialSelectedHour(hour),
        },
        allDayLabel: actionTimeValue(context, const ActionAllDay()),
        hourLabel: (hour) => actionTimeValue(context, ActionAtHour(hour)),
        onPickHour: (hour) => sheet.closeWithChoice(ActionAtHour(hour)),
        onAllDay: () => sheet.closeWithChoice(const ActionAllDay()),
      ),
    );
  }

  /// Формат циферблата следует итоговому формату часов устройства и локали, а
  /// 12-часовой открывается на половине суток текущего времени.
  TimeDialClock _clock(BuildContext context, AppLocalizations localizations) {
    if (!actionUsesTwelveHourClock(context)) {
      return const TimeDialClock24();
    }
    final material = MaterialLocalizations.of(context);
    return TimeDialClock12(
      initialHalf: switch (current) {
        ActionAtHour(:final hour) when hour >= 12 => TimeDialHalf.pm,
        ActionAtHour() || ActionAllDay() => TimeDialHalf.am,
      },
      switchLabel: localizations.actionTimeHalfSwitchLabel,
      am: TimeDialHalfLabel(
        text: material.anteMeridiemAbbreviation,
        semanticLabel: localizations.actionTimeAmLabel,
      ),
      pm: TimeDialHalfLabel(
        text: material.postMeridiemAbbreviation,
        semanticLabel: localizations.actionTimePmLabel,
      ),
    );
  }
}
