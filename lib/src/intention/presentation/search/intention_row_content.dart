import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/badge.dart';
import '../../../design_system/components/tag_chip.dart';
import '../../../design_system/doable_icon.dart';
import '../../../tag/domain/tag_id.dart';
import '../../../tag/presentation/tag_color_presentation.dart';
import '../../application/intention_catalog.dart';
import '../../application/intention_holding.dart';
import '../../domain/intention.dart';

/// Содержание строки результата поиска: название, начало описания, метки
/// вспомогательного намерения и архива, теги и доступное название. Строки экрана выбора и
/// каталога строятся из него, а не повторяют правило каждая.
final class IntentionRowContent {
  const IntentionRowContent._({
    required this.name,
    required this.description,
    required this.archived,
    required this.marks,
    required this.tags,
    required this.label,
  });

  /// [requiredTagIds] — обязательные теги применённого запроса, который
  /// отобрал строку, а не текущих условий: пока новая порция загружается, они
  /// уже могут быть другими. [currentPathStart] — намерение стоит в начале
  /// пути, корень которого меняет поиск начала пути. [holding] — удержание
  /// намерения на текущей ревизии; `null` — оно ещё не получено или его
  /// чтение отказало, и метка вспомогательного не краснеет (D5).
  factory IntentionRowContent.of(
    AppLocalizations l10n, {
    required IntentionSummary summary,
    required Set<TagId> requiredTagIds,
    required IntentionHolding? holding,
    bool currentPathStart = false,
  }) {
    final archived = switch (summary.archiveState) {
      IntentionArchiveState.active => false,
      IntentionArchiveState.archived => true,
    };
    final kind = switch ((summary.kind, archived, holding)) {
      (IntentionKind.main, _, _) => _RowKind.main,
      (IntentionKind.supporting, false, IntentionHolding.notHeld) =>
        _RowKind.unheldSupporting,
      (IntentionKind.supporting, _, _) => _RowKind.supporting,
    };
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
      marks: [
        if (currentPathStart) Badge.word(word: l10n.pathStartPickerCurrentRoot),
        ?switch (kind) {
          _RowKind.main => null,
          _RowKind.supporting => const Badge.mark(
            icon: DoableIconData.supporting,
            tone: BadgeTone.muted,
          ),
          _RowKind.unheldSupporting => const Badge.mark(
            icon: DoableIconData.supporting,
            tone: BadgeTone.accent,
          ),
        },
        if (archived)
          const Badge.mark(icon: DoableIconData.archive, tone: BadgeTone.muted),
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
        if (currentPathStart) l10n.pathStartPickerCurrentRoot,
        switch (kind) {
          _RowKind.main => l10n.intentionPickerKindMain,
          _RowKind.supporting => l10n.intentionPickerKindSupporting,
          _RowKind.unheldSupporting => l10n.intentionPickerKindSupportingUnheld,
        },
        if (archived) l10n.intentionPickerArchived,
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

  /// Отметка начала пути, метка вспомогательного и метка архива в порядке
  /// показа.
  final List<Badge> marks;

  /// Все теги в порядке показа: обязательные первыми.
  final List<TagChip> tags;

  /// Доступное название: название, отметка начала пути, вид, архив, начало
  /// описания и теги.
  final String label;
}

/// Вид строки с удержанием: красной бывает только метка активного
/// вспомогательного намерения, которого не удерживает ни одно главное.
enum _RowKind { main, supporting, unheldSupporting }
