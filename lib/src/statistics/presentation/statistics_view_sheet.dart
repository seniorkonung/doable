import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../design_system/components/option_row.dart';
import '../../design_system/components/sheet.dart';
import '../../design_system/doable_icon.dart';
import '../application/statistics_read_contract.dart';

/// Представление вида статистики: название, поясняющая строка и значок.
extension StatisticsViewPresentation on StatisticsView {
  String title(AppLocalizations texts) => switch (this) {
    StatisticsView.rootIntentions => texts.statisticsRootIntentions,
    StatisticsView.intermediateIntentions =>
      texts.statisticsIntermediateIntentions,
    StatisticsView.terminalIntentions => texts.statisticsTerminalIntentions,
    StatisticsView.throughRelations => texts.statisticsThroughRelations,
  };

  String hint(AppLocalizations texts) => switch (this) {
    StatisticsView.rootIntentions => texts.statisticsRootIntentionsHint,
    StatisticsView.intermediateIntentions =>
      texts.statisticsIntermediateIntentionsHint,
    StatisticsView.terminalIntentions => texts.statisticsTerminalIntentionsHint,
    StatisticsView.throughRelations => texts.statisticsThroughRelationsHint,
  };

  DoableIconData get icon => switch (this) {
    StatisticsView.rootIntentions => DoableIconData.intention,
    StatisticsView.intermediateIntentions => DoableIconData.relation,
    StatisticsView.terminalIntentions => DoableIconData.fromAction,
    StatisticsView.throughRelations => DoableIconData.graph,
  };
}

/// Показывает над корневым навигатором лист «Считать действия по» с видами в
/// порядке [StatisticsView.values]. Выбор применяется сразу и закрывает лист;
/// закрытие без выбора ничего не меняет.
Future<void> showStatisticsViewSheet(
  BuildContext context, {
  required StatisticsView selected,
  required ValueChanged<StatisticsView> onSelected,
}) => showDoableSheet<void>(
  context: context,
  builder: (context, sheet) {
    final texts = AppLocalizations.of(context);
    return Sheet(
      sheet,
      title: texts.statisticsViewSheetTitle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final view in StatisticsView.values)
            OptionRow(
              icon: view.icon,
              name: view.title(texts),
              hint: view.hint(texts),
              trailing: view == selected
                  ? OptionRowTrailing.selected
                  : OptionRowTrailing.none,
              autofocus: view == selected,
              onPressed: () {
                onSelected(view);
                Navigator.of(context).pop();
              },
            ),
        ],
      ),
    );
  },
);
