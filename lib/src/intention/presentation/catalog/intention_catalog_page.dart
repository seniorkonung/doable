import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/routing/app_router.gr.dart';
import '../../../design_system/doable_colors.dart';
import '../../../design_system/doable_metrics.dart';
import '../../../design_system/doable_type.dart';
import '../../application/intention_catalog.dart';
import '../search/intention_list_header.dart';
import '../search/intention_search_bar.dart';
import '../search/intention_search_kind.dart';
import 'intention_catalog_purpose.dart';
import 'intention_catalog_row.dart';
import 'intention_catalog_view_model.dart';
import 'intention_search_results.dart';

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
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Без AppBar стиль системной строки задаёт страница:
      // https://api.flutter.dev/flutter/services/SystemChrome/setSystemUIOverlayStyle.html
      value: Theme.of(context).brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Scaffold(
        // Низ тела страницы задаёт оболочка: это верхний край панели навигации
        // либо клавиатуры.
        body: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // В низком окне с клавиатурой закреплённые части могут не
                // поместиться: тогда выдача не получает высоты, а они
                // обрезаются снизу.
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: constraints.maxHeight),
                  child: UnconstrainedBox(
                    constrainedAxis: Axis.horizontal,
                    alignment: Alignment.topCenter,
                    clipBehavior: Clip.hardEdge,
                    child: _PinnedParts(filterController: _filterController),
                  ),
                ),
                Expanded(
                  child: IntentionSearchResults(
                    purpose: _purpose,
                    catalog: catalog,
                    listKey: const PageStorageKey<String>(
                      'intention-catalog-list',
                    ),
                    messages: IntentionSearchResultsMessages(
                      loading: localizations.catalogLoading,
                      unavailable: localizations.catalogUnavailable,
                      corruption: localizations.catalogCorruption,
                      unexpected: localizations.catalogUnexpectedFailure,
                    ),
                    emptyMessage: (empty) =>
                        _emptyMessage(localizations, empty.query),
                    itemBuilder: (context, results, summary) =>
                        IntentionCatalogRow(
                          summary: summary,
                          requiredTagIds:
                              results.query.tagFilter.requiredTagIds,
                          onOpen: () {
                            context.router.push(
                              IntentionDetailsRoute(intentionId: summary.id),
                            );
                          },
                        ),
                  ),
                ),
              ],
            ),
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

/// Части страницы над выдачей: заголовок, строка поиска и заголовок списка.
final class _PinnedParts extends StatelessWidget {
  const _PinnedParts({required this.filterController});

  final TextEditingController filterController;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            DoableMetrics.space5,
            DoableMetrics.space4,
            DoableMetrics.space5,
            0,
          ),
          child: Semantics(
            header: true,
            headingLevel: 1,
            namesRoute: true,
            // Одна строка оставляет высоту выдаче при крупном тексте, а
            // экранный диктор получает название целиком.
            child: Text(
              IntentionSearchKind.of(_purpose)
                  .title(AppLocalizations.of(context)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DoableType.display.copyWith(color: colors.ink),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            DoableMetrics.space5,
            DoableMetrics.space3,
            DoableMetrics.space5,
            0,
          ),
          child: IntentionSearchBar(
            purpose: _purpose,
            controller: filterController,
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(
            DoableMetrics.space5,
            2,
            DoableMetrics.space5,
            6,
          ),
          child: IntentionListHeader(purpose: _purpose),
        ),
      ],
    );
  }
}
