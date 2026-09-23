import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/intention.dart';

/// Количество активных непосредственных связей намерения в его представлении.
///
/// Отсутствие связей выражается подтверждённым нулём, а неизвестное или
/// устаревшее количество — отдельными вариантами, поэтому ошибка получения
/// не может быть изображена нулём.
sealed class ActiveRelationCountView {
  const ActiveRelationCountView();
}

/// Точное количество активных связей, подтверждённое последним чтением.
final class ConfirmedActiveRelationCount extends ActiveRelationCountView {
  ConfirmedActiveRelationCount(this.value)
    : assert(
        value >= 0,
        'Количество активных связей не может быть отрицательным.',
      );

  final int value;
}

/// Прежнее подтверждённое количество, обновить которое не удалось.
final class OutdatedActiveRelationCount extends ActiveRelationCountView {
  OutdatedActiveRelationCount(this.value)
    : assert(
        value >= 0,
        'Количество активных связей не может быть отрицательным.',
      );

  final int value;
}

/// Количество ещё не получено.
final class LoadingActiveRelationCount extends ActiveRelationCountView {
  const LoadingActiveRelationCount();
}

/// Количество неизвестно из-за ошибки получения.
final class UnknownActiveRelationCount extends ActiveRelationCountView {
  const UnknownActiveRelationCount();
}

/// Переиспользуемое представление намерения.
///
/// Сохраняет идентичность намерения: название показывается без изменения, а
/// количество активных связей и архивное состояние остаются отдельными
/// системными подписями с доступной семантикой.
final class IntentionSummaryView extends StatelessWidget {
  const IntentionSummaryView({
    required this.title,
    required this.archiveState,
    required this.activeRelationCount,
    required this.showArchiveState,
    this.traits = const <String>[],
    this.onTap,
    this.tapHint,
    super.key,
  });

  final String title;
  final IntentionArchiveState archiveState;
  final ActiveRelationCountView activeRelationCount;

  /// Показывать ли архивное состояние; представление участника связи
  /// показывает его всегда.
  final bool showArchiveState;

  /// Дополнительные локализованные подписи представления, например готовность
  /// к действию в строке каталога.
  final List<String> traits;

  final VoidCallback? onTap;

  /// Назначение перехода для экранного диктора; звучит вместе с названием,
  /// архивным состоянием и количеством активных связей.
  final String? tapHint;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return MergeSemantics(
      child: Semantics(
        hint: tapHint,
        child: ListTile(
          onTap: onTap,
          isThreeLine: true,
          title: Text(title),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 12,
                children: [
                  for (final trait in traits) Text(trait),
                  if (showArchiveState) Text(_archiveStateLabel(localizations)),
                ],
              ),
              ..._activeRelationCountLines(localizations, theme),
            ],
          ),
        ),
      ),
    );
  }

  String _archiveStateLabel(AppLocalizations localizations) =>
      switch (archiveState) {
        IntentionArchiveState.active => localizations.detailsActive,
        IntentionArchiveState.archived => localizations.detailsArchived,
      };

  List<Widget> _activeRelationCountLines(
    AppLocalizations localizations,
    ThemeData theme,
  ) => switch (activeRelationCount) {
    ConfirmedActiveRelationCount(:final value) => [
      Text(localizations.intentionActiveRelationCount(value)),
    ],
    OutdatedActiveRelationCount(:final value) => [
      Text(localizations.intentionActiveRelationCount(value)),
      Text(
        localizations.intentionActiveRelationCountRefreshFailed,
        style: TextStyle(color: theme.colorScheme.error),
      ),
    ],
    LoadingActiveRelationCount() => [
      Text(localizations.intentionActiveRelationCountLoading),
    ],
    UnknownActiveRelationCount() => [
      Text(
        localizations.intentionActiveRelationCountUnknown,
        style: TextStyle(color: theme.colorScheme.error),
      ),
    ],
  };
}
