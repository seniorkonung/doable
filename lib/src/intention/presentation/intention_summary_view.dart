import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/intention.dart';

/// Представление участника связи на странице её подробностей.
///
/// Сохраняет идентичность намерения: название показывается без изменения, а
/// архивное состояние остаётся отдельной системной подписью с доступной
/// семантикой и показывается всегда.
final class IntentionSummaryView extends StatelessWidget {
  const IntentionSummaryView({
    required this.title,
    required this.archiveState,
    this.onTap,
    this.tapHint,
    super.key,
  });

  final String title;
  final IntentionArchiveState archiveState;

  final VoidCallback? onTap;

  /// Назначение перехода для экранного диктора; звучит вместе с названием
  /// и архивным состоянием.
  final String? tapHint;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return MergeSemantics(
      child: Semantics(
        hint: tapHint,
        child: ListTile(
          onTap: onTap,
          isThreeLine: true,
          title: Text(title),
          subtitle: Text(_archiveStateLabel(localizations)),
        ),
      ),
    );
  }

  String _archiveStateLabel(AppLocalizations localizations) =>
      switch (archiveState) {
        IntentionArchiveState.active => localizations.detailsActive,
        IntentionArchiveState.archived => localizations.detailsArchived,
      };
}
