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
    final content = IntentionRowContent.of(
      l10n,
      summary: summary,
      requiredTagIds: requiredTagIds,
      namesKind: IntentionSearchKind.of(purpose).namesKind,
    );

    return PickerRow(
      name: content.name,
      description: content.description,
      archived: content.archived,
      marks: content.marks,
      tags: content.tags,
      label: content.label,
      onPick: onPick,
      pageLabel: content.isAction
          ? l10n.intentionPickerOpenActionPage(content.name)
          : l10n.intentionPickerOpenIntentionPage(content.name),
      onOpenPage: onOpenPage,
    );
  }
}
