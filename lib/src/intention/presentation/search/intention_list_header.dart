import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/catalog_header.dart';
import '../../application/intention_catalog.dart';
import '../catalog/intention_catalog_purpose.dart';
import '../catalog/intention_catalog_state.dart';
import '../catalog/intention_catalog_view_model.dart';
import 'show_and_sort_sheet.dart';

/// Заголовок списка поиска назначения [purpose]: слова выбранного типа,
/// количество подтверждённой выдачи и сводка сортировки.
///
/// Количество показывается только для подтверждённой выдачи текущих
/// параметров. Весь заголовок — одна кнопка, которая открывает лист «Показать
/// и упорядочить»; пока лист открыт, заголовок объявляется раскрытым. Отступы
/// вокруг заголовка задаёт страница.
final class IntentionListHeader extends ConsumerStatefulWidget {
  const IntentionListHeader({required this.purpose, super.key});

  final IntentionCatalogPurpose purpose;

  @override
  ConsumerState<IntentionListHeader> createState() =>
      _IntentionListHeaderState();
}

final class _IntentionListHeaderState
    extends ConsumerState<IntentionListHeader> {
  bool _expanded = false;

  Future<void> _openShowAndSort() async {
    setState(() => _expanded = true);
    await showShowAndSortSheet(context, widget.purpose);
    if (mounted) setState(() => _expanded = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final provider = intentionCatalogViewModelProvider(widget.purpose);
    final catalog = ref.watch(provider);
    final selection = ref.read(provider.notifier).selection;
    final title = switch (selection.type) {
      IntentionTypeOpen(selected: IntentionTypeChoice.all) =>
        l10n.intentionPickerAllHeader,
      IntentionTypeOpen(selected: IntentionTypeChoice.intentions) =>
        l10n.intentionPickerIntentionsHeader,
      IntentionTypeOpen(selected: IntentionTypeChoice.actions) ||
      IntentionTypePinnedToActions() => l10n.intentionPickerActionsHeader,
    };
    final summary = _orderSummary(l10n, selection.order);
    final count = switch (catalog) {
      AsyncData(
        isLoading: false,
        value: IntentionCatalogConfirmedState(:final totalCount),
      ) =>
        totalCount,
      _ => null,
    };
    return CatalogHeader(
      title: title,
      count: count,
      summary: summary,
      label: count == null
          ? l10n.intentionPickerHeaderLabel(title, summary)
          : l10n.intentionPickerHeaderCountLabel(title, count, summary),
      expanded: _expanded,
      onOpen: () => unawaited(_openShowAndSort()),
    );
  }
}

String _orderSummary(
  AppLocalizations l10n,
  IntentionCatalogOrder order,
) => switch ((order.field, order.direction)) {
  (
    IntentionCatalogSortField.createdAt,
    IntentionCatalogSortDirection.descending,
  ) =>
    l10n.intentionPickerOrderCreatedNewest,
  (
    IntentionCatalogSortField.createdAt,
    IntentionCatalogSortDirection.ascending,
  ) =>
    l10n.intentionPickerOrderCreatedOldest,
  (
    IntentionCatalogSortField.updatedAt,
    IntentionCatalogSortDirection.descending,
  ) =>
    l10n.intentionPickerOrderUpdatedNewest,
  (
    IntentionCatalogSortField.updatedAt,
    IntentionCatalogSortDirection.ascending,
  ) =>
    l10n.intentionPickerOrderUpdatedOldest,
  (IntentionCatalogSortField.title, IntentionCatalogSortDirection.ascending) =>
    l10n.intentionPickerOrderTitleAscending,
  (IntentionCatalogSortField.title, IntentionCatalogSortDirection.descending) =>
    l10n.intentionPickerOrderTitleDescending,
};
