import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/routing/app_router.gr.dart';
import '../../application/intention_catalog.dart';
import '../../domain/intention.dart';
import '../intention_summary_view.dart';
import 'intention_catalog_purpose.dart';
import 'intention_catalog_state.dart';
import 'intention_catalog_view_model.dart';
import 'intention_search_layout.dart';
import 'intention_search_results.dart';
import 'intention_tag_conditions_section.dart';

/// Назначение общего просмотра каталога намерений.
///
/// Выбор участника связи ведёт отдельное состояние того же каталога: их
/// охваты, фильтры и загруженные части не смешиваются.
const _purpose = BrowseIntentionCatalog();

/// Высота кнопки создания намерения вместе с отступами над нижним краем.
const _createActionExtent = 56 + 2 * kFloatingActionButtonMargin;

@RoutePage()
final class IntentionCatalogPage extends ConsumerStatefulWidget {
  const IntentionCatalogPage({super.key});

  @override
  ConsumerState<IntentionCatalogPage> createState() =>
      _IntentionCatalogPageState();
}

final class _IntentionCatalogPageState
    extends ConsumerState<IntentionCatalogPage> {
  final _filterController = TextEditingController();

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final catalog = ref.watch(intentionCatalogViewModelProvider(_purpose));
    final notifier = ref.read(
      intentionCatalogViewModelProvider(_purpose).notifier,
    );
    final selection = catalog.value?.selection ?? notifier.selection;
    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.catalogTitle),
        actions: [
          IconButton(
            key: const ValueKey('catalog-open-tags'),
            tooltip: localizations.tagCatalogTitle,
            onPressed: () => context.router.push(TagCatalogRoute()),
            icon: const Icon(Icons.label_outline),
          ),
          IconButton(
            key: const ValueKey('catalog-open-daily-choices'),
            tooltip: localizations.dailyChoiceCatalogTitle,
            onPressed: () =>
                context.router.push(const DailyChoiceCatalogRoute()),
            icon: const Icon(Icons.today),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('catalog-create-intention'),
        onPressed: () {
          context.router.push(const IntentionEditorRoute());
        },
        icon: const Icon(Icons.add),
        label: Text(localizations.editorCreateAction),
      ),
      body: IntentionSearchLayout(
        controls: _CatalogControls(
          selection: selection,
          filterController: _filterController,
          onScopeChanged: notifier.changeScope,
          onFilterChanged: notifier.changeTitleFilter,
          onOrderChanged: notifier.changeOrder,
        ),
        results: IntentionSearchResults(
          purpose: _purpose,
          catalog: catalog,
          listKey: const PageStorageKey<String>('intention-catalog-list'),
          messages: IntentionSearchResultsMessages(
            loading: localizations.catalogLoading,
            unavailable: localizations.catalogUnavailable,
            corruption: localizations.catalogCorruption,
            unexpected: localizations.catalogUnexpectedFailure,
          ),
          emptyMessage: (empty) => _emptyMessage(localizations, empty.query),
          totalCountLabel: localizations.catalogTotalCount,
          // Якорь видимого намерения и место под кнопку создания намерения —
          // единственные отличия выдачи каталога от страниц выбора.
          viewAnchor: IntentionSearchResultsViewAnchor.visibleIntention,
          trailingInset: _createActionExtent,
          itemBuilder: (context, results, summary) => _IntentionSummaryTile(
            summary: summary,
            showArchiveState: results.query.scope == IntentionScope.all,
            onTap: () {
              context.router.push(
                IntentionDetailsRoute(intentionId: summary.id),
              );
            },
          ),
        ),
      ),
    );
  }

  String _emptyMessage(
    AppLocalizations localizations,
    IntentionCatalogQuery query,
  ) {
    // Условия по тегам сужают охват: пустая выдача не означает, что в нём
    // нет намерений.
    if (query.tagFilter != IntentionTagFilter.empty) {
      return localizations.catalogTagConditionsEmpty;
    }
    return switch (query.scope) {
      IntentionScope.active => localizations.catalogActiveEmpty,
      IntentionScope.archived => localizations.catalogArchivedEmpty,
      IntentionScope.all => localizations.catalogAllEmpty,
    };
  }
}

final class _CatalogControls extends StatelessWidget {
  const _CatalogControls({
    required this.selection,
    required this.filterController,
    required this.onScopeChanged,
    required this.onFilterChanged,
    required this.onOrderChanged,
  });

  final IntentionCatalogSelection selection;
  final TextEditingController filterController;
  final ValueChanged<IntentionScope> onScopeChanged;
  final ValueChanged<String> onFilterChanged;
  final ValueChanged<IntentionCatalogOrder> onOrderChanged;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        children: [
          DropdownButtonFormField<IntentionScope>(
            key: const ValueKey('catalog-scope-control'),
            isExpanded: true,
            initialValue: selection.scope,
            decoration: InputDecoration(
              labelText: localizations.catalogScopeLabel,
            ),
            items: [
              for (final scope in IntentionScope.values)
                DropdownMenuItem(
                  value: scope,
                  child: Text(_scopeLabel(localizations, scope)),
                ),
            ],
            onChanged: (scope) {
              if (scope != null) {
                onScopeChanged(scope);
              }
            },
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('catalog-filter-field'),
            controller: filterController,
            decoration: InputDecoration(
              labelText: localizations.catalogFilterLabel,
              errorText: _filterError(localizations),
            ),
            onChanged: onFilterChanged,
          ),
          const SizedBox(height: 12),
          const Align(
            alignment: AlignmentDirectional.centerStart,
            child: IntentionTagConditionsSection(purpose: _purpose),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<IntentionCatalogOrder>(
            key: const ValueKey('catalog-order-control'),
            isExpanded: true,
            initialValue: selection.order,
            decoration: InputDecoration(
              labelText: localizations.catalogOrderLabel,
            ),
            items: [
              for (final order in _orders)
                DropdownMenuItem(
                  value: order,
                  child: Text(_orderLabel(localizations, order)),
                ),
            ],
            onChanged: (order) {
              if (order != null) {
                onOrderChanged(order);
              }
            },
          ),
        ],
      ),
    );
  }

  String? _filterError(AppLocalizations localizations) =>
      switch (selection.filterValidationFailure) {
        IntentionCatalogFilterValidationFailure.invalidUnicodeRepertoire =>
          localizations.catalogFilterInvalidUnicode,
        IntentionCatalogFilterValidationFailure.tooLong =>
          localizations.catalogFilterTooLong,
        null => null,
      };

  static const _orders = [
    IntentionCatalogOrder.createdAtDescending,
    IntentionCatalogOrder.createdAtAscending,
    IntentionCatalogOrder.updatedAtDescending,
    IntentionCatalogOrder.updatedAtAscending,
  ];

  String _scopeLabel(AppLocalizations localizations, IntentionScope scope) =>
      switch (scope) {
        IntentionScope.active => localizations.catalogScopeActive,
        IntentionScope.archived => localizations.catalogScopeArchived,
        IntentionScope.all => localizations.catalogScopeAll,
      };

  String _orderLabel(
    AppLocalizations localizations,
    IntentionCatalogOrder order,
  ) => switch ((order.field, order.direction)) {
    (
      IntentionCatalogSortField.createdAt,
      IntentionCatalogSortDirection.descending,
    ) =>
      localizations.catalogOrderCreatedNewest,
    (
      IntentionCatalogSortField.createdAt,
      IntentionCatalogSortDirection.ascending,
    ) =>
      localizations.catalogOrderCreatedOldest,
    (
      IntentionCatalogSortField.updatedAt,
      IntentionCatalogSortDirection.descending,
    ) =>
      localizations.catalogOrderUpdatedNewest,
    (
      IntentionCatalogSortField.updatedAt,
      IntentionCatalogSortDirection.ascending,
    ) =>
      localizations.catalogOrderUpdatedOldest,
  };
}

final class _IntentionSummaryTile extends StatelessWidget {
  const _IntentionSummaryTile({
    required this.summary,
    required this.showArchiveState,
    required this.onTap,
  });

  final IntentionSummary summary;
  final bool showArchiveState;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final readiness = switch (summary.readiness) {
      IntentionReadiness.ready => localizations.catalogReady,
      IntentionReadiness.notReady => localizations.catalogNotReady,
    };
    final description = summary.hasDescription
        ? localizations.catalogHasDescription
        : localizations.catalogNoDescription;
    return IntentionSummaryView(
      title: summary.title,
      archiveState: summary.archiveState,
      showArchiveState: showArchiveState,
      traits: [readiness, description],
      confirmedTags: summary.tags,
      activeRelationCount: ConfirmedActiveRelationCount(
        summary.activeRelationCount,
      ),
      onTap: onTap,
    );
  }
}
