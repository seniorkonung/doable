import 'package:flutter/widgets.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/picker_row.dart';
import '../../../tag/domain/tag_id.dart';
import '../../application/intention_catalog.dart';
import '../../application/intention_holding.dart';
import '../search/intention_row_content.dart';

/// Строка экрана выбора для найденного намерения: название, начало описания,
/// отметка текущего начала пути, метки вспомогательного и архивированного
/// намерения и теги, где обязательные для выдачи идут первыми.
final class IntentionPickerRow extends StatelessWidget {
  IntentionPickerRow({
    required this.summary,
    required this.requiredTagIds,
    required this.holding,
    required VoidCallback onPick,
    required this.onOpenPage,
    this.currentPathStart = false,
    super.key,
  }) : _behavior = _Pick(onPick);

  IntentionPickerRow.checkable({
    required this.summary,
    required this.requiredTagIds,
    required this.holding,
    required bool chosen,
    required VoidCallback onPick,
    required this.onOpenPage,
    super.key,
  }) : currentPathStart = false,
       _behavior = _Check(onPick, chosen);

  IntentionPickerRow.occupied({
    required this.summary,
    required String reason,
    required this.onOpenPage,
    super.key,
  }) : requiredTagIds = const {},
       holding = null,
       currentPathStart = false,
       _behavior = _Occupied(reason);

  final IntentionSummary summary;

  /// Обязательные теги применённого запроса, который отобрал строку, а не
  /// текущих условий: пока новая порция загружается, они уже могут быть
  /// другими.
  final Set<TagId> requiredTagIds;

  /// Удержание намерения на текущей ревизии; `null` — ещё не получено или
  /// чтение отказало. Занятая строка меток не показывает.
  final IntentionHolding? holding;

  /// Строка текущего корня в поиске начала пути, открытом для смены корня:
  /// первой в линии меток стоит отметка «Сейчас в начале пути».
  final bool currentPathStart;

  final _PickerBehavior _behavior;
  final VoidCallback onOpenPage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final content = IntentionRowContent.of(
      l10n,
      summary: summary,
      requiredTagIds: requiredTagIds,
      holding: holding,
      currentPathStart: currentPathStart,
    );

    final pageLabel = l10n.intentionPickerOpenIntentionPage(content.name);
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
