import 'package:doable/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../../daily_choice/application/choice_path_draft.dart';
import '../../design_system/components/action_sheet.dart';
import '../../design_system/components/option_row.dart';
import '../../design_system/components/sheet.dart';
import '../../design_system/doable_icon.dart';

/// Возвращает направление либо null при отмене, не запуская создание.
/// Результат передаётся через закрытие маршрута листа:
/// https://api.flutter.dev/flutter/widgets/Navigator/pop.html
Future<ChoicePathDraftDirection?> showQuickCreationDailyChoiceStartSheet(
  BuildContext context,
) => showDoableSheet<ChoicePathDraftDirection>(
  context: context,
  builder: (context, sheet) => QuickCreationDailyChoiceStartSheet(
    sheet,
    onSelected: (direction) =>
        Navigator.pop<ChoicePathDraftDirection>(context, direction),
  ),
);

/// Выбор начала дневного выбора; продолжением управляет вызывающая сторона.
final class QuickCreationDailyChoiceStartSheet extends StatelessWidget {
  const QuickCreationDailyChoiceStartSheet(
    this.sheet, {
    required this.onSelected,
    super.key,
  });

  final SheetPresentation sheet;

  final ValueChanged<ChoicePathDraftDirection> onSelected;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return ActionSheet(
      sheet,
      title: localizations.quickCreationModeDailyChoice,
      text: localizations.quickCreationDailyChoiceStartPrompt,
      options: [
        OptionRow(
          icon: DoableIconData.fromIntention,
          name: localizations.quickCreationDailyChoiceFromIntention,
          hint: localizations.quickCreationDailyChoiceFromIntentionHint,
          trailing: OptionRowTrailing.forward,
          onPressed: () => onSelected(ChoicePathDraftDirection.topDown),
        ),
        OptionRow(
          icon: DoableIconData.fromAction,
          name: localizations.quickCreationDailyChoiceFromAction,
          hint: localizations.quickCreationDailyChoiceFromActionHint,
          trailing: OptionRowTrailing.forward,
          onPressed: () => onSelected(ChoicePathDraftDirection.bottomUp),
        ),
      ],
    );
  }
}
