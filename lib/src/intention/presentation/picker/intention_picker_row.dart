import 'package:flutter/widgets.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/badge.dart';
import '../../../design_system/components/picker_row.dart';
import '../../../tag/domain/tag_id.dart';
import '../../application/intention_catalog.dart';
import '../catalog/intention_catalog_purpose.dart';
import '../search/intention_row_content.dart';
import '../search/intention_search_kind.dart';

/// Вид отметки занятой пары: слово метки и то, что обещает нажатие на текст
/// строки. Предложить восстановление можно только для архивной связи.
enum OccupiedPairKind {
  /// Пару занимает активная связь, нажатие её откроет.
  linked,

  /// Пару занимает архивная связь, нажатие её откроет.
  archived,

  /// Пару занимает архивная связь, нажатие предложит её восстановить.
  restorable,
}

/// Отметка занятой пары в строке поиска участника: её вид и действие нажатия
/// на текст строки.
final class OccupiedPairMark {
  const OccupiedPairMark({required this.kind, required this.onTap});

  final OccupiedPairKind kind;

  /// Выполняется вместо выбора намерения.
  final VoidCallback onTap;
}

/// Строка экрана выбора для найденного намерения: название, начало описания,
/// метка архива у архивированного намерения, молния у действия и теги, где
/// обязательные для выдачи идут первыми.
///
/// У строки с [occupiedPair] первой стоит метка-слово занятой пары, а нажатие
/// на текст выполняет действие отметки и намерение не выбирает.
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

    final pair = switch (occupiedPair?.kind) {
      null => null,
      OccupiedPairKind.linked => (
        word: l10n.intentionPickerPairLinked,
        action: l10n.intentionPickerPairOpensRelation,
      ),
      OccupiedPairKind.archived => (
        word: l10n.intentionPickerPairArchived,
        action: l10n.intentionPickerPairOpensRelation,
      ),
      OccupiedPairKind.restorable => (
        word: l10n.intentionPickerPairArchived,
        action: l10n.intentionPickerPairOffersRestore,
      ),
    };

    return PickerRow(
      name: content.name,
      description: content.description,
      archived: content.archived,
      marks: [
        if (pair != null) Badge.word(word: pair.word),
        ...content.marks,
      ],
      tags: content.tags,
      label: pair == null
          ? content.label
          : [content.label, pair.word, pair.action].join(', '),
      onPick: occupiedPair?.onTap ?? onPick,
      pageLabel: content.isAction
          ? l10n.intentionPickerOpenActionPage(content.name)
          : l10n.intentionPickerOpenIntentionPage(content.name),
      onOpenPage: onOpenPage,
    );
  }
}
