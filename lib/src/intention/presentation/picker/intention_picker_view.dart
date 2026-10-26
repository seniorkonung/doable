import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/catalog_header.dart';
import '../../../design_system/components/filter_button.dart';
import '../../../design_system/components/search_field.dart';
import '../../../design_system/components/top_bar.dart';
import '../../../design_system/doable_metrics.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../tag/presentation/panel/tags_panel.dart';
import '../../../tag/presentation/panel/tags_panel_context.dart';
import '../../application/intention_catalog.dart';
import '../../domain/intention_id.dart';
import '../catalog/intention_catalog_purpose.dart';
import '../catalog/intention_catalog_state.dart';
import '../catalog/intention_catalog_view_model.dart';
import '../catalog/intention_tag_conditions_view_model.dart';
import 'intention_picker_kind.dart';
import 'intention_picker_purpose_sheet.dart';
import 'intention_picker_results.dart';
import 'intention_picker_show_and_sort_sheet.dart';

/// Экран выбора намерения назначения [purpose]: крестик с заголовком, поле
/// поиска, фильтр по тегам и заголовок списка закреплены над выдачей.
/// С [purposeDescription] под заголовком стоит строка назначения, которая
/// открывает лист «Что вы выбираете».
///
/// Экран не знает маршрутов, права запуска и типа результата: о закрытии,
/// выборе и открытии подробностей страница узнаёт из обработчиков.
final class IntentionPickerView extends ConsumerStatefulWidget {
  const IntentionPickerView({
    required this.purpose,
    required this.closeLabel,
    required this.emptyScopeMessage,
    required this.onClose,
    required this.onPick,
    required this.onOpenDetails,
    this.purposeDescription,
    super.key,
  });

  final IntentionPickerPurpose purpose;

  /// Назначение, которое страница напоминает пользователю; без него шапка
  /// показывает только заголовок.
  final IntentionPickerPurposeDescription? purposeDescription;

  /// Доступное название крестика: его смысл для вызвавшего потока знает
  /// страница.
  final String closeLabel;

  /// Сообщение страницы о том, что допустимый охват пуст.
  final String emptyScopeMessage;

  final VoidCallback onClose;

  /// Получает сводку строки с ревизией выдачи, из которой строка построена.
  final void Function(GraphSnapshot<IntentionSummary> pick) onPick;

  final void Function(IntentionId id) onOpenDetails;

  @override
  ConsumerState<IntentionPickerView> createState() =>
      _IntentionPickerViewState();
}

final class _IntentionPickerViewState
    extends ConsumerState<IntentionPickerView> {
  final _titleController = TextEditingController();
  bool _showAndSortExpanded = false;
  bool _purposeExpanded = false;

  Future<void> _openShowAndSort() async {
    setState(() => _showAndSortExpanded = true);
    await showIntentionPickerShowAndSortSheet(context, widget.purpose);
    if (mounted) setState(() => _showAndSortExpanded = false);
  }

  Future<void> _openPurpose(
    IntentionPickerPurposeDescription description,
  ) async {
    setState(() => _purposeExpanded = true);
    await showIntentionPickerPurposeSheet(context, description);
    if (mounted) setState(() => _purposeExpanded = false);
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final kind = IntentionPickerKind.of(widget.purpose);
    final keyPrefix = intentionPickerKeyPrefix(widget.purpose);
    final catalogProvider = intentionCatalogViewModelProvider(widget.purpose);
    final catalog = ref.watch(catalogProvider);
    final notifier = ref.read(catalogProvider.notifier);
    final selection = notifier.selection;
    final headerTitle = switch (selection.type) {
      IntentionTypeOpen(selected: IntentionTypeChoice.all) ||
      IntentionTypeNotOffered() => l10n.intentionPickerAllHeader,
      IntentionTypeOpen(selected: IntentionTypeChoice.intentions) =>
        l10n.intentionPickerIntentionsHeader,
      IntentionTypeOpen(selected: IntentionTypeChoice.actions) ||
      IntentionTypePinnedToActions() => l10n.intentionPickerActionsHeader,
    };
    final orderSummary = _orderSummary(l10n, selection.order);
    final count = switch (catalog) {
      AsyncData(
        isLoading: false,
        value: IntentionCatalogConfirmedState(:final totalCount),
      ) =>
        totalCount,
      _ => null,
    };
    final conditionsProvider = intentionTagConditionsViewModelProvider(
      widget.purpose,
    );
    final conditionCount = ref.watch(
      conditionsProvider.select((state) => state.conditions.length),
    );
    final title = kind.title(l10n);
    final purposeDescription = widget.purposeDescription;
    return Scaffold(
      appBar: purposeDescription == null
          ? TopBar(
              closeKey: ValueKey('$keyPrefix-cancel'),
              title: title,
              closeLabel: widget.closeLabel,
              onClose: widget.onClose,
            )
          : TopBar.withPurpose(
              context,
              closeKey: ValueKey('$keyPrefix-cancel'),
              title: title,
              closeLabel: widget.closeLabel,
              onClose: widget.onClose,
              purpose: TopBarPurpose(
                subtitle: purposeDescription.subtitle,
                mark: purposeDescription.subtitleMark,
                label: l10n.intentionPickerPurposeLabel(
                  title,
                  purposeDescription.subtitle,
                ),
                expanded: _purposeExpanded,
                onOpen: () => unawaited(_openPurpose(purposeDescription)),
              ),
            ),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                DoableMetrics.space5,
                DoableMetrics.space2,
                DoableMetrics.space5,
                DoableMetrics.space1,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SearchField(
                      key: ValueKey('$keyPrefix-filter'),
                      controller: _titleController,
                      placeholder: l10n.intentionPickerSearchPlaceholder,
                      label: l10n.intentionPickerSearchPlaceholder,
                      clearLabel: l10n.intentionPickerClearSearch,
                      onChanged: notifier.changeTitleFilter,
                      error: switch (selection.filterValidationFailure) {
                        IntentionCatalogFilterValidationFailure
                            .invalidUnicodeRepertoire =>
                          l10n.catalogFilterInvalidUnicode,
                        IntentionCatalogFilterValidationFailure.tooLong =>
                          l10n.catalogFilterTooLong,
                        null => null,
                      },
                    ),
                  ),
                  const SizedBox(width: DoableMetrics.space2),
                  FilterButton(
                    count: conditionCount,
                    label: l10n.intentionPickerFilterLabel(conditionCount),
                    onPressed: () => unawaited(
                      showTagsPanel(
                        context,
                        TagsPanelFilterContext(
                          ref.read(conditionsProvider.notifier),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                DoableMetrics.space5,
                0,
                DoableMetrics.space5,
                DoableMetrics.space1,
              ),
              child: CatalogHeader(
                title: headerTitle,
                count: count,
                summary: orderSummary,
                label: count == null
                    ? l10n.intentionPickerHeaderLabel(headerTitle, orderSummary)
                    : l10n.intentionPickerHeaderCountLabel(
                        headerTitle,
                        count,
                        orderSummary,
                      ),
                expanded: _showAndSortExpanded,
                onOpen: () => unawaited(_openShowAndSort()),
              ),
            ),
            Expanded(
              child: IntentionPickerResults(
                purpose: widget.purpose,
                emptyScopeMessage: widget.emptyScopeMessage,
                onResetFilters: () {
                  _titleController.clear();
                  notifier.clearTitleFilter();
                  ref.read(conditionsProvider.notifier).clear();
                },
                onPick: widget.onPick,
                onOpenDetails: widget.onOpenDetails,
              ),
            ),
          ],
        ),
      ),
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
