import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/action_check.dart';
import '../../../design_system/components/option_row.dart';
import '../../../design_system/components/sheet.dart';
import '../../domain/action_priority.dart';
import '../panel/action_field_labels.dart';

/// Показывает лист приоритета нового действия с отмеченным [current].
///
/// Возвращает выбранный приоритет либо null, если лист закрыт без выбора.
/// Результат приходит после закрытия листа.
Future<ActionPriority?> showActionPrioritySheet(
  BuildContext context,
  ActionPriority current,
) => showDoableSheet<ActionPriority>(
  context: context,
  builder: (_, sheet) => _ActionPrioritySheet(sheet, current: current),
);

final class _ActionPrioritySheet extends StatelessWidget {
  const _ActionPrioritySheet(this.sheet, {required this.current});

  final SheetPresentation sheet;
  final ActionPriority current;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Sheet(
      sheet,
      title: localizations.actionFieldPriority,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final priority in ActionPriority.values)
            OptionRow.marked(
              mark: ActionCheck(priority: actionDesignPriority(priority)),
              name: actionPriorityName(actionDesignPriority(priority)),
              hint: switch (priority) {
                ActionPriority.p1 => localizations.actionPriorityHighest,
                ActionPriority.p4 => localizations.actionPriorityLowest,
                ActionPriority.p2 || ActionPriority.p3 => null,
              },
              trailing: priority == current
                  ? OptionRowTrailing.selected
                  : OptionRowTrailing.none,
              onPressed: () => sheet.closeWithChoice(priority),
            ),
        ],
      ),
    );
  }
}
