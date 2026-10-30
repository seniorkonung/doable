import 'package:flutter/widgets.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/catalog_row.dart';
import '../../../tag/domain/tag_id.dart';
import '../../application/intention_catalog.dart';
import '../search/intention_row_content.dart';
import '../search/intention_search_kind.dart';

/// Строка каталога для найденного намерения: вся карточка открывает его
/// страницу, а содержание то же, что у строки экрана выбора.
final class IntentionCatalogRow extends StatelessWidget {
  const IntentionCatalogRow({
    required this.summary,
    required this.requiredTagIds,
    required this.onOpen,
    super.key,
  });

  final IntentionSummary summary;

  /// Обязательные теги применённого запроса, который отобрал строку, а не
  /// текущих условий: пока новая порция загружается, они уже могут быть
  /// другими.
  final Set<TagId> requiredTagIds;

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final content = IntentionRowContent.of(
      l10n,
      summary: summary,
      requiredTagIds: requiredTagIds,
      namesKind: IntentionSearchKind.catalog.namesKind,
    );

    return CatalogRow(
      name: content.name,
      description: content.description,
      archived: content.archived,
      marks: content.marks,
      tags: content.tags,
      label: l10n.intentionCatalogRowLabel(content.label),
      onOpen: onOpen,
    );
  }
}
