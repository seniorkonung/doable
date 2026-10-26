import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/option_group.dart';
import '../../../design_system/components/select_row.dart';
import '../../../design_system/components/sheet.dart';
import '../../../design_system/doable_icon.dart';
import '../../../design_system/doable_metrics.dart';
import '../../application/intention_catalog.dart';
import '../catalog/intention_catalog_purpose.dart';
import '../catalog/intention_catalog_state.dart';
import '../catalog/intention_catalog_view_model.dart';

/// Показывает параметры того же поиска над корневым навигатором.
/// Выбор применяется сразу; закрытие листа сохраняет параметры страницы.
Future<void> showIntentionPickerShowAndSortSheet(
  BuildContext context,
  IntentionPickerPurpose purpose,
) => showDoableSheet<void>(
  context: context,
  builder: (_, sheet) => _ShowAndSortSheet(sheet, purpose),
);

final class _ShowAndSortSheet extends ConsumerStatefulWidget {
  const _ShowAndSortSheet(this.sheet, this.purpose);

  final SheetPresentation sheet;
  final IntentionPickerPurpose purpose;

  @override
  ConsumerState<_ShowAndSortSheet> createState() => _ShowAndSortSheetState();
}

final class _ShowAndSortSheetState extends ConsumerState<_ShowAndSortSheet> {
  final _typeMenu = MenuController();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final provider = intentionCatalogViewModelProvider(widget.purpose);
    // Подписка перестраивает лист, а текущий выбор берётся из модели:
    // AsyncValue при загрузке может сохранять прежнюю выдачу.
    // https://riverpod.dev/docs/concepts2/refs#refwatch
    final catalog = ref.watch(provider);
    final model = ref.read(provider.notifier);
    final selection = model.selection;
    final counts = switch (catalog) {
      AsyncData(
        isLoading: false,
        value: IntentionCatalogConfirmedState(:final typeCounts),
      ) =>
        typeCounts,
      _ => null,
    };
    final typeItems = [
      SelectRowItem(
        value: IntentionTypeChoice.all,
        label: l10n.intentionPickerTypeAll,
        count: counts?.all.toString(),
      ),
      SelectRowItem(
        value: IntentionTypeChoice.intentions,
        label: l10n.intentionPickerTypeIntentionsOnly,
        count: counts?.intentions.toString(),
      ),
      SelectRowItem(
        value: IntentionTypeChoice.actions,
        label: l10n.intentionPickerTypeActionsOnly,
        count: counts?.actions.toString(),
      ),
    ];
    final order = selection.order;
    final byTitle = order.field == IntentionCatalogSortField.title;
    final firstDirection = byTitle
        ? IntentionCatalogSortDirection.ascending
        : IntentionCatalogSortDirection.descending;
    final canReset =
        order != IntentionCatalogOrder.createdAtDescending ||
        switch (selection.type) {
          IntentionTypeOpen(:final selected) =>
            selected != IntentionTypeChoice.all,
          IntentionTypePinnedToActions() || IntentionTypeNotOffered() => false,
        };

    return Sheet(
      widget.sheet,
      title: l10n.intentionPickerShowAndSortTitle,
      text: l10n.intentionPickerShowAndSortHint,
      action: canReset
          ? (
              label: l10n.intentionPickerShowAndSortReset,
              semanticLabel: l10n.intentionPickerShowAndSortReset,
              onPressed: () {
                model.changeType(IntentionTypeChoice.all);
                model.changeOrder(IntentionCatalogOrder.createdAtDescending);
              },
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          DoableMetrics.space2,
          0,
          DoableMetrics.space2,
          DoableMetrics.space1,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DoableMetrics.space4,
          children: [
            if (selection.type case IntentionTypeOpen(:final selected))
              SelectRow(
                label: l10n.intentionPickerTypeCaption,
                items: typeItems,
                value: selected,
                onChanged: model.changeType,
                controller: _typeMenu,
              ),
            if (selection.type is IntentionTypePinnedToActions)
              SelectRow<IntentionTypeChoice>.disabled(
                label: l10n.intentionPickerTypeCaption,
                value: l10n.intentionPickerTypeActionsOnly,
                note: l10n.intentionPickerActionTypeNote,
              ),
            OptionGroup(
              caption: l10n.intentionPickerSortCaption,
              items: [
                OptionGroupItem(
                  value: IntentionCatalogSortField.createdAt,
                  label: l10n.intentionPickerSortCreated,
                ),
                OptionGroupItem(
                  value: IntentionCatalogSortField.updatedAt,
                  label: l10n.intentionPickerSortChanged,
                ),
                OptionGroupItem(
                  value: IntentionCatalogSortField.title,
                  label: l10n.intentionPickerSortName,
                ),
              ],
              value: order.field,
              onChanged: (field) {
                final previous = model.selection.order;
                final crossesTitle =
                    (previous.field == IntentionCatalogSortField.title) !=
                    (field == IntentionCatalogSortField.title);
                model.changeOrder(
                  IntentionCatalogOrder(
                    field: field,
                    direction: crossesTitle
                        ? (field == IntentionCatalogSortField.title
                              ? IntentionCatalogSortDirection.ascending
                              : IntentionCatalogSortDirection.descending)
                        : previous.direction,
                  ),
                );
              },
            ),
            OptionGroup(
              caption: l10n.intentionPickerOrderCaption,
              items: [
                OptionGroupItem(
                  value: firstDirection,
                  label: byTitle
                      ? l10n.intentionPickerOrderAToZ
                      : l10n.intentionPickerOrderNewest,
                  icon: DoableIconData.arrowDown,
                ),
                OptionGroupItem(
                  value: byTitle
                      ? IntentionCatalogSortDirection.descending
                      : IntentionCatalogSortDirection.ascending,
                  label: byTitle
                      ? l10n.intentionPickerOrderZToA
                      : l10n.intentionPickerOrderOldest,
                  icon: DoableIconData.arrowUp,
                ),
              ],
              value: order.direction,
              onChanged: (direction) => model.changeOrder(
                IntentionCatalogOrder(
                  field: model.selection.order.field,
                  direction: direction,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
