import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/confirm_dialog.dart';
import '../../application/daily_choice_details.dart';

/// Подтверждение называет выбор и его дату.
Future<bool> confirmDailyChoiceDeletion(
  BuildContext context,
  DailyChoiceDetails details,
) {
  final l10n = AppLocalizations.of(context);
  return showConfirmDialog(
    context: context,
    title: l10n.dailyChoiceDeleteDialogTitle,
    text: ConfirmDialogText(
      before: l10n.dailyChoiceDeleteDialogBefore,
      name: l10n.dailyChoiceDetailsPhrase(
        details.source.title,
        details.selected.title,
      ),
      after: l10n.dailyChoiceDeleteDialogAfter(
        details.choice.date.toCanonicalString(),
      ),
    ),
    cancelLabel: l10n.detailsCancelEditAction,
    actionLabel: l10n.dailyChoiceDeleteDialogAction,
  );
}
