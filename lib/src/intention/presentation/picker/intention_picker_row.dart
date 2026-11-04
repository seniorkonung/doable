import 'package:flutter/widgets.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/picker_row.dart';
import '../../../tag/domain/tag_id.dart';
import '../../application/intention_catalog.dart';
import '../catalog/intention_catalog_purpose.dart';
import '../search/intention_row_content.dart';
import '../search/intention_search_kind.dart';

/// Строка экрана выбора для найденного намерения: название, начало описания,
/// метка архива у архивированного намерения, молния у действия и теги, где
/// обязательные для выдачи идут первыми.
final class IntentionPickerRow extends StatelessWidget {
  IntentionPickerRow({
    required this.purpose,
    required this.summary,
    required this.requiredTagIds,
    required VoidCallback onPick,
    required this.onOpenPage,
    super.key,
  }) : _behavior = _Pick(onPick);

  IntentionPickerRow.checkable({
    required this.purpose,
    required this.summary,
    required this.requiredTagIds,
    required bool chosen,
    required VoidCallback onPick,
    required this.onOpenPage,
    super.key,
  }) : _behavior = _Check(onPick, chosen);

  IntentionPickerRow.occupied({
    required this.purpose,
    required this.summary,
    required String reason,
    required this.onOpenPage,
    super.key,
  }) : requiredTagIds = const {},
       _behavior = _Occupied(reason);

  final IntentionPickerPurpose purpose;
  final IntentionSummary summary;

  /// Обязательные теги применённого запроса, который отобрал строку, а не
  /// текущих условий: пока новая порция загружается, они уже могут быть
  /// другими.
  final Set<TagId> requiredTagIds;

  final _PickerBehavior _behavior;
  final VoidCallback onOpenPage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final content = IntentionRowContent.of(
      l10n,
      summary: summary,
      requiredTagIds: requiredTagIds,
      namesKind: IntentionSearchKind.of(purpose).namesKind,
    );

    final pageLabel = content.isAction
        ? l10n.intentionPickerOpenActionPage(content.name)
        : l10n.intentionPickerOpenIntentionPage(content.name);
    return switch (_behavior) {
      _Occupied(:final reason) => PickerRow.occupied(
        name: content.name,
        reason: reason,
        pageLabel: pageLabel,
        onOpenPage: onOpenPage,
      ),
      _Check(:final onPick, :final chosen) => PickerRow.checkable(
        name: content.name,
        description: content.description,
        archived: content.archived,
        marks: content.marks,
        tags: content.tags,
        label: content.label,
        chosen: chosen,
        onPick: onPick,
        pageLabel: pageLabel,
        onOpenPage: onOpenPage,
      ),
      _Pick(:final onPick) => PickerRow(
        name: content.name,
        description: content.description,
        archived: content.archived,
        marks: content.marks,
        tags: content.tags,
        label: content.label,
        onPick: onPick,
        pageLabel: pageLabel,
        onOpenPage: onOpenPage,
      ),
    };
  }
}

sealed class _PickerBehavior {
  const _PickerBehavior();
}

final class _Pick extends _PickerBehavior {
  const _Pick(this.onPick);
  final VoidCallback onPick;
}

final class _Check extends _PickerBehavior {
  const _Check(this.onPick, this.chosen);
  final VoidCallback onPick;
  final bool chosen;
}

final class _Occupied extends _PickerBehavior {
  const _Occupied(this.reason);
  final String reason;
}
