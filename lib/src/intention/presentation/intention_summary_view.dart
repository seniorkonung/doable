import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../tag/domain/tag.dart';
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

/// Узел семантики, которым экранный диктор объявляет представление намерения.
enum IntentionSummarySemanticsNode {
  /// Представление объявляется собственным узлом.
  own,

  /// Название, подписи и переход представления дополняют узел ближайшего
  /// предка, который добавляет к ним свои действия, например строку
  /// переставляемого списка с действиями перемещения: экранный диктор
  /// получает их одним узлом.
  enclosing,
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
    this.confirmedTags,
    this.confirmedFavoriteMark,
    this.onTap,
    this.tapHint,
    this.semanticsNode = IntentionSummarySemanticsNode.own,
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

  /// Подтверждённые собственные теги намерения в порядке сводки.
  ///
  /// Строка тегов выводится только при явной передаче: пустой список означает
  /// проверенное отсутствие назначений, а `null` — представление, которое
  /// теги не показывает.
  final List<Tag>? confirmedTags;

  /// Подтверждённая отметка избранного намерения.
  ///
  /// Звезда выводится только при явной передаче отметки избранного намерения:
  /// неизбранное намерение звезды не получает, а `null` — представление,
  /// которое отметку не показывает.
  final FavoriteMark? confirmedFavoriteMark;

  final VoidCallback? onTap;

  /// Назначение перехода для экранного диктора; звучит вместе с названием,
  /// архивным состоянием и количеством активных связей.
  final String? tapHint;

  /// По умолчанию представление объявляется собственным узлом.
  final IntentionSummarySemanticsNode semanticsNode;

  @override
  Widget build(BuildContext context) {
    final summary = _summary(context);
    return switch (semanticsNode) {
      IntentionSummarySemanticsNode.own => MergeSemantics(child: summary),
      IntentionSummarySemanticsNode.enclosing => summary,
    };
  }

  Widget _summary(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Semantics(
      hint: tapHint,
      child: ListTile(
        onTap: onTap,
        isThreeLine: true,
        title: Text(title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (confirmedTags case final tags?)
              Text(_tagsLabel(localizations, tags)),
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
        trailing: switch (confirmedFavoriteMark) {
          // Звезда — подпись строки, а не управление: отметка различима
          // наличием значка и ставится только на странице намерения.
          FavoriteMark.favorite => Icon(
            Icons.star,
            applyTextScaling: true,
            semanticLabel: localizations.intentionSummaryFavoriteMark,
          ),
          FavoriteMark.notFavorite || null => null,
        },
      ),
    );
  }

  String _tagsLabel(AppLocalizations localizations, List<Tag> tags) =>
      tags.isEmpty
      ? localizations.intentionSummaryNoTags
      : localizations.intentionSummaryTags(
          tags.map((tag) => tag.name.value).join(', '),
        );

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
