import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/quick_creation/quick_creation_daily_choice_start_sheet.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode_presentation.dart';
import 'package:doable/src/design_system/components/action_sheet.dart';
import 'package:doable/src/design_system/components/option_row.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_metrics.dart';
import 'package:flutter/material.dart';
import 'package:widgetbook/widgetbook.dart';

/// Листы с данными представления приложения, без его маршрутизатора и хранилища.
List<WidgetbookUseCase> quickCreationSheetsUseCases() => [
  WidgetbookUseCase(
    name: 'Меню режимов',
    builder: (context) {
      final localizations = AppLocalizations.of(context);
      // https://docs.widgetbook.io/knobs/object/dropdown
      final selected = context.knobs.object.dropdown(
        label: 'Текущий режим',
        options: QuickCreationMode.values,
        labelBuilder: (mode) => mode.title(localizations),
      );
      return _sheetPreview(
        ActionSheet(
          title: localizations.quickCreationMenuTitle,
          text: localizations.quickCreationMenuPrompt,
          options: [
            for (final mode in QuickCreationMode.values)
              OptionRow(
                icon: mode.icon,
                name: mode.title(localizations),
                hint: mode.hint(localizations),
                trailing: mode == selected
                    ? OptionRowTrailing.selected
                    : OptionRowTrailing.none,
                autofocus: mode == selected,
                onPressed: () {},
              ),
          ],
        ),
      );
    },
  ),
  WidgetbookUseCase(
    name: 'Выбор начала дневного выбора',
    builder: (context) =>
        _sheetPreview(QuickCreationDailyChoiceStartSheet(onSelected: (_) {})),
  ),
];

/// Три состояния, используемые меню режимов и выбором начала дневного выбора.
List<WidgetbookUseCase> optionRowUseCases() => [
  for (final trailing in OptionRowTrailing.values)
    WidgetbookUseCase(
      name: switch (trailing) {
        OptionRowTrailing.none => 'Обычная',
        OptionRowTrailing.selected => 'Выбранная',
        OptionRowTrailing.forward => 'Ведущая дальше',
      },
      builder: (context) {
        final localizations = AppLocalizations.of(context);
        final forward = trailing == OptionRowTrailing.forward;
        const mode = QuickCreationMode.intention;
        return Center(
          child: SizedBox(
            width: 390,
            child: Material(
              color: Theme.of(context).extension<DoableColors>()!.raised,
              child: Padding(
                padding: const EdgeInsets.all(DoableMetrics.space3),
                child: OptionRow(
                  icon: forward ? Icons.arrow_downward_outlined : mode.icon,
                  name: forward
                      ? localizations.quickCreationDailyChoiceFromIntention
                      : mode.title(localizations),
                  hint: forward
                      ? localizations.quickCreationDailyChoiceFromIntentionHint
                      : mode.hint(localizations),
                  trailing: trailing,
                  onPressed: () {},
                ),
              ),
            ),
          ),
        );
      },
    ),
];

/// Ширина макетов ActionMenu и ChoiceSheet; лист прижат к низу области просмотра.
Widget _sheetPreview(Widget sheet) => Scaffold(
  body: Align(
    alignment: Alignment.bottomCenter,
    child: SizedBox(width: 390, child: sheet),
  ),
);
