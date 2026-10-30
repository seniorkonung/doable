import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/routing/app_router.gr.dart';
import '../../application/intention_catalog.dart';
import '../search/intention_list_header.dart';
import '../search/intention_search_bar.dart';
import 'intention_catalog_purpose.dart';
import 'intention_catalog_row.dart';
import 'intention_catalog_view_model.dart';
import 'intention_search_layout.dart';
import 'intention_search_results.dart';
import 'intention_tag_conditions_section.dart';

/// Назначение общего просмотра каталога намерений.
///
/// Выбор участника связи ведёт отдельное состояние того же каталога: их
/// охваты, фильтры и загруженные части не смешиваются.
const _purpose = BrowseIntentionCatalog();

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
    return Scaffold(
      appBar: AppBar(title: Text(localizations.appDestinationIntentionGraph)),
      body: IntentionSearchLayout(
        // Загруженная выдача получает всю высоту тела страницы: прокрученные
        // до конца параметры и список оставляют последнюю строку и состояние
        // продолжения над панелью навигации при любой высоте параметров.
        // Начальные состояния и пустая выдача остаются под параметрами.
        resultsExtent: IntentionSearchResults.showsList(catalog)
            ? IntentionSearchResultsExtent.fullViewport
            : IntentionSearchResultsExtent.remainingWhenSufficient,
        controls: _CatalogControls(filterController: _filterController),
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
          itemBuilder: (context, results, summary) => IntentionCatalogRow(
            summary: summary,
            requiredTagIds: results.query.tagFilter.requiredTagIds,
            onOpen: () {
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
  const _CatalogControls({required this.filterController});

  final TextEditingController filterController;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        children: [
          IntentionSearchBar(purpose: _purpose, controller: filterController),
          const SizedBox(height: 12),
          const Align(
            alignment: AlignmentDirectional.centerStart,
            child: IntentionTagConditionsSection(purpose: _purpose),
          ),
          const SizedBox(height: 12),
          const IntentionListHeader(purpose: _purpose),
        ],
      ),
    );
  }
}
