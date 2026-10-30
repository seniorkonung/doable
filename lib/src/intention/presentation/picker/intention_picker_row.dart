import 'package:flutter/widgets.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/badge.dart';
import '../../../design_system/components/picker_row.dart';
import '../../../long_term_relation/domain/long_term_relation.dart';
import '../../../tag/domain/tag_id.dart';
import '../../application/intention_catalog.dart';
import '../catalog/intention_catalog_purpose.dart';
import '../search/intention_row_content.dart';
import '../search/intention_search_kind.dart';

/// Отметка занятой пары в строке поиска участника: архивное состояние
/// занимающей связи и действие нажатия на текст строки.
final class OccupiedPairMark {
  const OccupiedPairMark({required this.scope, required this.onOpenRelation});

  final RelationScope scope;

  /// Открывает занимающую связь вместо выбора намерения.
  final VoidCallback onOpenRelation;
}

/// Строка экрана выбора для найденного намерения: название, начало описания,
/// метка архива у архивированного намерения, молния у действия и теги, где
/// обязательные для выдачи идут первыми.
///
/// У строки с [occupiedPair] первой стоит метка-слово занятой пары, а нажатие
/// на текст открывает занимающую связь и намерение не выбирает.
final class IntentionPickerRow extends StatelessWidget {
  const IntentionPickerRow({
    required this.purpose,
    required this.summary,
    required this.requiredTagIds,
    required this.onPick,
    required this.onOpenPage,
    this.occupiedPair,
    super.key,
  });

  final IntentionPickerPurpose purpose;
  final IntentionSummary summary;

  /// Обязательные теги применённого запроса, который отобрал строку, а не
  /// текущих условий: пока новая порция загружается, они уже могут быть
  /// другими.
  final Set<TagId> requiredTagIds;

  final VoidCallback onPick;
  final VoidCallback onOpenPage;

  /// Отметка занятой пары; без неё строка выбирается как обычно.
  final OccupiedPairMark? occupiedPair;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final content = IntentionRowContent.of(
      l10n,
      summary: summary,
      requiredTagIds: requiredTagIds,
      namesKind: IntentionSearchKind.of(purpose).namesKind,
    );

    final pairWord = switch (occupiedPair?.scope) {
      null => null,
      RelationScope.active => l10n.intentionPickerPairLinked,
      RelationScope.archived => l10n.intentionPickerPairArchived,
    };

    return PickerRow(
      name: content.name,
      description: content.description,
      archived: content.archived,
      marks: [
        if (pairWord != null) Badge.word(word: pairWord),
        ...content.marks,
      ],
      tags: content.tags,
      label: pairWord == null
          ? content.label
          : [
              content.label,
              pairWord,
              l10n.intentionPickerPairOpensRelation,
            ].join(', '),
      onPick: occupiedPair?.onOpenRelation ?? onPick,
      pageLabel: content.isAction
          ? l10n.intentionPickerOpenActionPage(content.name)
          : l10n.intentionPickerOpenIntentionPage(content.name),
      onOpenPage: onOpenPage,
    );
  }
}
