import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/button.dart';
import '../../../design_system/components/sheet.dart';
import '../../../design_system/components/top_bar.dart';
import '../../../design_system/doable_metrics.dart';

/// Назначение экрана выбора, которое строит открывшая его страница: поток,
/// который открыл поиск, и роль, которая в нём выбирается.
///
/// Экран выбора не знает потоков: тексты и тело листа приходят готовыми.
final class IntentionPickerPurposeDescription {
  const IntentionPickerPurposeDescription({
    required this.subtitle,
    required this.sheetLine,
    required this.buildSheetBody,
    this.subtitleMark,
  });

  /// Строка под заголовком шапки: поток и выбираемая роль.
  final String subtitle;

  /// Отметка перед строкой шапки, когда выбирается поле связи.
  final TopBarPurposeMark? subtitleMark;

  /// Строка под заголовком листа «Что вы выбираете»: поток.
  final String sheetLine;

  /// Тело листа, которое показывает поток целиком.
  final WidgetBuilder buildSheetBody;
}

/// Показывает над корневым навигатором лист «Что вы выбираете». Лист только
/// напоминает назначение и ничего не меняет в поиске под ним.
Future<void> showIntentionPickerPurposeSheet(
  BuildContext context,
  IntentionPickerPurposeDescription description,
) => showDoableSheet<void>(
  context: context,
  builder: (context, sheet) {
    final l10n = AppLocalizations.of(context);
    return Sheet(
      sheet,
      title: l10n.intentionPickerPurposeSheetTitle,
      text: description.sheetLine,
      footer: Button.primary(
        label: l10n.intentionPickerPurposeSheetBack,
        onPressed: () => Navigator.pop(context),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: DoableMetrics.space2),
        child: Builder(builder: description.buildSheetBody),
      ),
    );
  },
);
