import 'package:flutter/material.dart' hide Badge;

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/badge.dart';
import '../../../design_system/components/picker_row.dart';
import '../../../design_system/components/tag_chip.dart';
import '../../../design_system/doable_icon.dart';
import '../../../tag/domain/tag_id.dart';
import '../../../tag/presentation/tag_color_presentation.dart';
import '../../application/intention_catalog.dart';
import '../../domain/intention.dart';
import '../catalog/intention_catalog_purpose.dart';
import '../search/intention_search_kind.dart';

/// Строка экрана выбора для найденного намерения: название, начало описания,
/// метка архива у архивированного намерения, молния у действия и теги, где
/// обязательные для выдачи идут первыми.
final class IntentionPickerRow extends StatelessWidget {
  const IntentionPickerRow({
    required this.purpose,
    required this.summary,
    required this.requiredTagIds,
    required this.onPick,
    required this.onOpenPage,
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isAction = switch (summary.readiness) {
      IntentionReadiness.ready => true,
      IntentionReadiness.notReady => false,
    };
    final archived = switch (summary.archiveState) {
      IntentionArchiveState.active => false,
      IntentionArchiveState.archived => true,
    };
    final markTone = archived ? BadgeTone.muted : BadgeTone.ink;
    // Внутри обеих групп сохраняется ручной порядок сводки.
    final tags = [
      ...summary.tags.where((tag) => requiredTagIds.contains(tag.id)),
      ...summary.tags.where((tag) => !requiredTagIds.contains(tag.id)),
    ];
    final description = summary.descriptionPreview?.text;
    final namesKind = IntentionSearchKind.of(purpose).namesKind;

    return PickerRow(
      name: summary.title,
      description: description,
      archived: archived,
      marks: [
        if (archived)
          const Badge.mark(icon: DoableIconData.archive, tone: BadgeTone.muted),
        if (isAction) Badge.mark(icon: DoableIconData.bolt, tone: markTone),
      ],
      tags: [
        for (final tag in tags)
          TagChip.small(
            name: tag.name.value,
            color: tagColorPresentation(tag.color),
            // В строке архивированного намерения обязательные теги не
            // выделяются.
            strong: !archived && requiredTagIds.contains(tag.id),
          ),
      ],
      label: [
        summary.title,
        if (archived) l10n.intentionPickerArchived,
        if (namesKind)
          isAction
              ? l10n.intentionPickerKindAction
              : l10n.intentionPickerKindIntention,
        ?description,
        tags.isEmpty
            ? l10n.intentionSummaryNoTags
            : l10n.intentionSummaryTags(
                tags.map((tag) => tag.name.value).join(', '),
              ),
      ].join(', '),
      onPick: onPick,
      pageLabel: isAction
          ? l10n.intentionPickerOpenActionPage(summary.title)
          : l10n.intentionPickerOpenIntentionPage(summary.title),
      onOpenPage: onOpenPage,
    );
  }
}
