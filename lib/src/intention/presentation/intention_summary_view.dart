import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../design_system/components/tag_dot.dart';
import '../../tag/domain/tag.dart';
import '../../tag/presentation/tag_phrase_text.dart';
import '../domain/intention.dart';

/// Переиспользуемое представление намерения.
///
/// Сохраняет идентичность намерения: название показывается без изменения, а
/// архивное состояние остаётся отдельной системной подписью с доступной
/// семантикой.
final class IntentionSummaryView extends StatelessWidget {
  const IntentionSummaryView({
    required this.title,
    required this.archiveState,
    required this.showArchiveState,
    this.traits = const <String>[],
    this.confirmedTags,
    this.onTap,
    this.tapHint,
    super.key,
  });

  final String title;
  final IntentionArchiveState archiveState;

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
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (confirmedTags case final tags?)
                _tagsLine(localizations, tags),
              Wrap(
                spacing: 12,
                children: [
                  for (final trait in traits) Text(trait),
                  if (showArchiveState) Text(_archiveStateLabel(localizations)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tagsLine(AppLocalizations localizations, List<Tag> tags) =>
      tags.isEmpty
      ? Text(localizations.intentionSummaryNoTags)
      : tagPhraseText(
          phrase: localizations.intentionSummaryTags,
          tags: [
            for (final tag in tags) (name: tag.name.value, color: tag.color),
          ],
          dotSize: TagDotSize.small,
        );

  String _archiveStateLabel(AppLocalizations localizations) =>
      switch (archiveState) {
        IntentionArchiveState.active => localizations.detailsActive,
        IntentionArchiveState.archived => localizations.detailsArchived,
      };
}
