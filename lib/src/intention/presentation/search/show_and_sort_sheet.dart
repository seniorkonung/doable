import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/order_button.dart';
import '../../../design_system/components/select_row.dart';
import '../../../design_system/components/sheet.dart';
import '../../application/intention_catalog.dart';
import '../catalog/intention_catalog_purpose.dart';
import '../catalog/intention_catalog_state.dart';
import '../catalog/intention_catalog_view_model.dart';

/// Показывает параметры поиска назначения [purpose] над корневым навигатором.
/// Выбор применяется сразу; закрытие листа сохраняет параметры страницы.
Future<void> showShowAndSortSheet(
  BuildContext context,
  IntentionCatalogPurpose purpose,
) => showDoableSheet<void>(
  context: context,
  builder: (_, sheet) => _ShowAndSortSheet(sheet, purpose),
);

final class _ShowAndSortSheet extends ConsumerStatefulWidget {
  const _ShowAndSortSheet(this.sheet, this.purpose);

  final SheetPresentation sheet;
  final IntentionCatalogPurpose purpose;

  @override
  ConsumerState<_ShowAndSortSheet> createState() => _ShowAndSortSheetState();
}

final class _ShowAndSortSheetState extends ConsumerState<_ShowAndSortSheet> {
  final _scopeMenu = MenuController();
  final _typeMenu = MenuController();
  final _sortMenu = MenuController();

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
    final confirmed = switch (catalog) {
      AsyncData(
        isLoading: false,
        value: final IntentionCatalogConfirmedState state,
      ) =>
        state,
      _ => null,
    };
    final counts = confirmed?.typeCounts;
    final scopeCounts = confirmed?.scopeCounts;
    final scopeItems = [
      SelectRowItem(
        value: IntentionScope.active,
        label: l10n.intentionPickerScopeActive,
        count: scopeCounts?.active.toString(),
      ),
      SelectRowItem(
        value: IntentionScope.archived,
        label: l10n.intentionPickerScopeArchived,
        count: scopeCounts?.archived.toString(),
      ),
      SelectRowItem(
        value: IntentionScope.all,
        label: l10n.intentionPickerScopeAll,
        count: scopeCounts?.all.toString(),
      ),
    ];
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
    final nextDirection = switch (order.direction) {
      IntentionCatalogSortDirection.ascending =>
        IntentionCatalogSortDirection.descending,
      IntentionCatalogSortDirection.descending =>
        IntentionCatalogSortDirection.ascending,
    };
    String directionLabel(IntentionCatalogSortDirection direction) =>
        switch ((byTitle, direction)) {
          (true, IntentionCatalogSortDirection.ascending) =>
            l10n.intentionPickerOrderAToZ,
          (true, IntentionCatalogSortDirection.descending) =>
            l10n.intentionPickerOrderZToA,
          (false, IntentionCatalogSortDirection.ascending) =>
            l10n.intentionPickerOrderOldest,
          (false, IntentionCatalogSortDirection.descending) =>
            l10n.intentionPickerOrderNewest,
        };

    return Sheet(
      widget.sheet,
      title: l10n.intentionPickerShowAndSortTitle,
      text: l10n.intentionPickerShowAndSortHint,
      action: model.canResetShowParameters
          ? (
              label: l10n.intentionPickerShowAndSortReset,
              semanticLabel: l10n.intentionPickerShowAndSortReset,
              onPressed: model.resetShowParameters,
            )
          : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (selection.scope case IntentionScopeOpen(:final selected))
            SelectRow(
              label: l10n.intentionPickerScopeCaption,
              items: scopeItems,
              value: selected,
              onChanged: model.changeScope,
              controller: _scopeMenu,
              onOpen: () {
                _typeMenu.close();
                _sortMenu.close();
              },
            ),
          if (selection.type case IntentionTypeOpen(:final selected))
            SelectRow(
              label: l10n.intentionPickerTypeCaption,
              items: typeItems,
              value: selected,
              onChanged: model.changeType,
              controller: _typeMenu,
              onOpen: () {
                _scopeMenu.close();
                _sortMenu.close();
              },
            ),
          if (selection.type is IntentionTypePinnedToActions)
            SelectRow<IntentionTypeChoice>.disabled(
              label: l10n.intentionPickerTypeCaption,
              value: l10n.intentionPickerTypeActionsOnly,
              note: l10n.intentionPickerActionTypeNote,
            ),
          SelectRow(
            label: l10n.intentionPickerSortCaption,
            items: [
              SelectRowItem(
                value: IntentionCatalogSortField.createdAt,
                label: l10n.intentionPickerSortCreated,
              ),
              SelectRowItem(
                value: IntentionCatalogSortField.updatedAt,
                label: l10n.intentionPickerSortChanged,
              ),
              SelectRowItem(
                value: IntentionCatalogSortField.title,
                label: l10n.intentionPickerSortName,
              ),
            ],
            value: order.field,
            controller: _sortMenu,
            onOpen: () {
              _scopeMenu.close();
              _typeMenu.close();
            },
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
            trailing: OrderButton(
              direction: switch (order.direction) {
                IntentionCatalogSortDirection.ascending =>
                  OrderDirection.ascending,
                IntentionCatalogSortDirection.descending =>
                  OrderDirection.descending,
              },
              label: l10n.intentionPickerOrderButtonSemantics(
                directionLabel(order.direction),
                directionLabel(nextDirection),
              ),
              onPressed: () {
                final current = model.selection.order;
                model.changeOrder(
                  IntentionCatalogOrder(
                    field: current.field,
                    direction: switch (current.direction) {
                      IntentionCatalogSortDirection.ascending =>
                        IntentionCatalogSortDirection.descending,
                      IntentionCatalogSortDirection.descending =>
                        IntentionCatalogSortDirection.ascending,
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
