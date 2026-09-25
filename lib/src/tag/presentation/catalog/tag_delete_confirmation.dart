import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/tag.dart';

/// Подтверждение привязано к выбранному тегу, а не к загруженным назначениям.
Future<bool> confirmTagDeletion(BuildContext context, Tag tag) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      scrollable: true,
      title: Text(l10n.tagDeleteConfirmationTitle(tag.name.value)),
      content: Semantics(
        container: true,
        child: Text(
          l10n.tagDeleteConfirmationScope,
          key: const ValueKey('tag-delete-scope'),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('tag-delete-cancel'),
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.tagDeleteCancel),
        ),
        FilledButton(
          key: const ValueKey('tag-delete-confirm'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(dialogContext).colorScheme.error,
            foregroundColor: Theme.of(dialogContext).colorScheme.onError,
          ),
          child: Text(l10n.tagDeleteConfirm),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
