import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/daily_choice_details.dart';

/// Отдельное подтверждение относится к идентичности открытого выбора.
Future<bool> confirmDailyChoiceDeletion(
  BuildContext context,
  DailyChoiceDetails details,
) async {
  final l10n = AppLocalizations.of(context);
  final choice = details.choice;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      scrollable: true,
      title: Text(l10n.dailyChoiceDeleteConfirmationTitle),
      content: Semantics(
        container: true,
        child: Text(
          l10n.dailyChoiceDeleteConfirmationMessage(
            l10n.dailyChoiceDetailsPhrase(
              details.source.title,
              details.selected.title,
            ),
            choice.date.toCanonicalString(),
            choice.id.toCanonicalString(),
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('daily-choice-delete-cancel'),
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.detailsCancelEditAction),
        ),
        FilledButton(
          key: const ValueKey('daily-choice-delete-confirm'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(dialogContext).colorScheme.error,
            foregroundColor: Theme.of(dialogContext).colorScheme.onError,
          ),
          child: Text(l10n.dailyChoiceDeleteConfirmAction),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
