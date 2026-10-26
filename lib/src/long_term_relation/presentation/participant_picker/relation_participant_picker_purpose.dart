import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/relation_form.dart';
import '../../../design_system/components/top_bar.dart';
import '../../../design_system/doable_colors.dart';
import '../../../design_system/doable_metrics.dart';
import '../../../design_system/doable_type.dart';
import '../../../intention/domain/intention.dart';
import '../../../intention/presentation/picker/intention_picker_purpose_sheet.dart';
import '../../application/long_term_relation_command.dart';
import '../../application/long_term_relation_projection.dart';
import '../../domain/long_term_relation.dart';
import 'relation_participant_choice.dart';

/// Назначение поиска участника: поток и роль из [choice] определяют
/// подзаголовок с отметкой роли и строку листа, а тело листа показывает связь
/// формой только для чтения такой, какой она была при открытии поиска.
IntentionPickerPurposeDescription relationParticipantPickerPurpose(
  AppLocalizations l10n,
  RelationParticipantChoice choice,
) {
  final creation = switch (choice.flow) {
    RelationCreationChoiceFlow() => true,
    RelationChangeChoiceFlow() => false,
  };
  final (subtitle, mark, role, roleNote, chosen, other) = switch (choice.role) {
    RelationParticipantRole.source => (
      creation
          ? l10n.participantPickerPurposeCreationSource
          : l10n.participantPickerPurposeChangeSource,
      TopBarPurposeMark.sourceField,
      RelationFormRole.source,
      l10n.participantPickerRoleSourceNote,
      choice.source,
      choice.related,
    ),
    RelationParticipantRole.related => (
      creation
          ? l10n.participantPickerPurposeCreationRelated
          : l10n.participantPickerPurposeChangeRelated,
      TopBarPurposeMark.relatedField,
      RelationFormRole.related,
      switch (choice.type) {
        LongTermRelationType.need => l10n.participantPickerRoleRelatedNeedNote,
        LongTermRelationType.can => l10n.participantPickerRoleRelatedCanNote,
        null => l10n.participantPickerRoleRelatedUndeterminedNote,
      },
      choice.related,
      choice.source,
    ),
  };
  final (kind, kindWord) = switch (choice.type) {
    LongTermRelationType.need => (
      RelationFormKind.need,
      l10n.relationEditorTypeNeed,
    ),
    LongTermRelationType.can => (
      RelationFormKind.can,
      l10n.relationEditorTypeCan,
    ),
    null => (
      RelationFormKind.undetermined,
      l10n.participantPickerKindUndetermined,
    ),
  };
  final form = RelationForm.choosing(
    role: role,
    chosen: RelationFieldChoosing(replacing: chosen?.title),
    other: _shown(other),
    kind: kind,
    texts: RelationFormTexts(
      sourceRole: l10n.relationEditorSourceLabel,
      relatedRole: l10n.relationEditorRelatedLabel,
      choosingNow: l10n.participantPickerFieldChoosing,
      fromList: l10n.participantPickerFieldFromList,
      replacing: l10n.participantPickerFieldReplacing,
      notChosen: l10n.participantPickerFieldNotChosen,
      archived: l10n.participantPickerFieldArchived,
      kind: kindWord,
    ),
  );
  return IntentionPickerPurposeDescription(
    subtitle: subtitle,
    subtitleMark: mark,
    sheetLine: creation
        ? l10n.participantPickerFlowCreation
        : l10n.participantPickerFlowChange,
    buildSheetBody: (context) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DoableMetrics.space3,
      children: [
        Text(
          roleNote,
          style: DoableType.body.copyWith(
            color: Theme.of(context).extension<DoableColors>()!.muted,
          ),
        ),
        form,
      ],
    ),
  );
}

RelationFieldShown _shown(RelationParticipantSummary? participant) =>
    switch (participant) {
      null => const RelationFieldEmpty(),
      RelationParticipantSummary(:final title, :final archiveState) =>
        RelationFieldFilled(
          title,
          archived: switch (archiveState) {
            IntentionArchiveState.archived => true,
            IntentionArchiveState.active => false,
          },
        ),
    };
