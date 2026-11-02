import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/relation_batch.dart';
import '../../../design_system/components/relation_head.dart';
import '../../../design_system/doable_colors.dart';
import '../../../design_system/doable_metrics.dart';
import '../../../design_system/doable_type.dart';
import '../../../intention/domain/intention_id.dart';
import '../../../intention/presentation/picker/intention_picker_purpose_sheet.dart';
import '../../application/intention_relation_group.dart';
import '../../domain/long_term_relation.dart';
import '../relation_group_name.dart';
import 'relation_batch_view_model.dart';

IntentionPickerPurposeDescription relationBatchPickerPurpose(
  AppLocalizations l10n,
  IntentionRelationGroup group,
  RelationBatchViewModelProvider provider,
  int count,
) {
  final groupName = relationGroupName(l10n, group);
  final outgoing = group.direction == RelationDirection.outgoing;
  final note = switch (group) {
    IntentionRelationGroup.needs => l10n.batchNoteNeeds,
    IntentionRelationGroup.canUse => l10n.batchNoteCanUse,
    IntentionRelationGroup.neededFor => l10n.batchNoteNeededFor,
    IntentionRelationGroup.canBeUsedFor => l10n.batchNoteCanBeUsedFor,
  };
  return IntentionPickerPurposeDescription(
    subtitle: count == 0
        ? l10n.batchSubtitle(groupName)
        : l10n.batchSubtitleSelected(groupName, count),
    sheetLine: l10n.batchSheetLine(groupName),
    buildSheetBody: (context) => Consumer(
      builder: (context, ref, _) {
        final batch = ref.watch(provider);
        final style = DoableType.body.copyWith(
          color: Theme.of(context).extension<DoableColors>()!.muted,
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DoableMetrics.space3,
          children: [
            Text(note, style: style),
            Text(l10n.batchDefaults, style: style),
            RelationBatch<IntentionId>(
              anchor: batch.pageTitle,
              kind: switch (group.type) {
                LongTermRelationType.need => RelationHeadKind.need,
                LongTermRelationType.can => RelationHeadKind.can,
              },
              direction: outgoing
                  ? RelationBatchDirection.outgoing
                  : RelationBatchDirection.incoming,
              items: [
                for (final item in batch.selected)
                  RelationBatchItem(value: item.id, name: item.title),
              ],
              onRemove: ref.read(provider.notifier).remove,
              anchorNote: l10n.batchAnchorNote,
              emptyText: l10n.batchEmpty,
              needLabel: l10n.relationEditorTypeNeed,
              canLabel: l10n.relationEditorTypeCan,
              listLabel: l10n.batchSelected,
              anchorSemanticLabel: outgoing
                  ? l10n.batchSourceSemantic(batch.pageTitle)
                  : l10n.batchRelatedSemantic(batch.pageTitle),
              itemSemanticLabel: outgoing
                  ? l10n.batchRelatedSemantic
                  : l10n.batchSourceSemantic,
              removeLabel: l10n.batchRemove,
            ),
          ],
        );
      },
    ),
  );
}
