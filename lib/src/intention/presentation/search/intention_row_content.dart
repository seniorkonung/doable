import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/badge.dart';
import '../../../design_system/components/tag_chip.dart';
import '../../../design_system/doable_icon.dart';
import '../../../tag/domain/tag_id.dart';
import '../../../tag/presentation/tag_color_presentation.dart';
import '../../application/intention_catalog.dart';
import '../../domain/intention.dart';

/// Содержание строки результата поиска: название, начало описания, метки
/// архива и действия, теги и доступное название. Строки экрана выбора и
/// каталога строятся из него, а не повторяют правило каждая.
final class IntentionRowContent {
  const IntentionRowContent._({
    required this.name,
    required this.description,
    required this.archived,
    required this.isAction,
    required this.marks,
    required this.tags,
    required this.label,
  });

  /// [requiredTagIds] — обязательные теги применённого запроса, который
  /// отобрал строку, а не текущих условий: пока новая порция загружается, они
  /// уже могут быть другими. [namesKind] — называет ли доступное название
  /// тип найденного, см. `IntentionSearchKind.namesKind`.
  factory IntentionRowContent.of(
    AppLocalizations l10n, {
    required IntentionSummary summary,
    required Set<TagId> requiredTagIds,
    required bool namesKind,
  }) {
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
    final orderedTags = [
      ...summary.tags.where((tag) => requiredTagIds.contains(tag.id)),
      ...summary.tags.where((tag) => !requiredTagIds.contains(tag.id)),
    ];
    final description = summary.descriptionPreview?.text;

    return IntentionRowContent._(
      name: summary.title,
      description: description,
      archived: archived,
      isAction: isAction,
      marks: [
        if (archived)
          const Badge.mark(icon: DoableIconData.archive, tone: BadgeTone.muted),
        if (isAction) Badge.mark(icon: DoableIconData.bolt, tone: markTone),
      ],
      tags: [
        for (final tag in orderedTags)
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
        orderedTags.isEmpty
            ? l10n.intentionSummaryNoTags
            : l10n.intentionSummaryTags(
                orderedTags.map((tag) => tag.name.value).join(', '),
              ),
      ].join(', '),
    );
  }

  final String name;

  /// Начало описания, если оно есть.
  final String? description;

  /// Архивированное намерение: название приглушено, обязательные теги не
  /// выделены.
  final bool archived;

  /// Готово ли намерение к выполнению, то есть является ли оно действием.
  final bool isAction;

  /// Метка архива и молния действия в порядке показа.
  final List<Badge> marks;

  /// Все теги в порядке показа: обязательные первыми.
  final List<TagChip> tags;

  /// Доступное название: название, архив, тип, начало описания и теги.
  final String label;
}
