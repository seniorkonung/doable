import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/routing/app_router.gr.dart';
import '../../../intention/application/intention_catalog.dart';
import '../../../intention/domain/intention.dart';
import '../../../intention/presentation/catalog/intention_catalog_purpose.dart';
import '../../../intention/presentation/catalog/intention_catalog_state.dart';
import '../../../intention/presentation/catalog/intention_catalog_view_model.dart';
import '../../../intention/presentation/catalog/intention_search_layout.dart';
import '../../../intention/presentation/catalog/intention_search_results.dart';
import '../../../intention/presentation/catalog/intention_tag_conditions_section.dart';
import '../../../intention/presentation/intention_summary_view.dart';

const _purpose = SelectDailyChoiceSource();

/// Выбор нового исходного намерения для замены пути дневного выбора.
///
/// Список использует отдельную сессию ограниченного каталога. Только открытие
/// подробностей читает полный текст выбранного намерения; результат выбора —
/// его идентификатор, поэтому одноимённые намерения не смешиваются.
@RoutePage()
final class DailyChoiceSourcePickerPage extends ConsumerStatefulWidget {
  const DailyChoiceSourcePickerPage({super.key});

  @override
  ConsumerState<DailyChoiceSourcePickerPage> createState() =>
      _DailyChoiceSourcePickerPageState();
}

final class _DailyChoiceSourcePickerPageState
    extends ConsumerState<DailyChoiceSourcePickerPage> {
  final _filterController = TextEditingController();

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final catalog = ref.watch(intentionCatalogViewModelProvider(_purpose));
    final notifier = ref.read(
      intentionCatalogViewModelProvider(_purpose).notifier,
    );
    final selection = catalog.value?.selection ?? notifier.selection;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.sourcePickerTitle),
        leading: IconButton(
          key: const ValueKey('daily-choice-source-cancel'),
          icon: const Icon(Icons.close),
          tooltip: l10n.sourcePickerCancel,
          onPressed: () => unawaited(context.router.maybePop()),
        ),
      ),
      body: SafeArea(
        child: IntentionSearchLayout(
          controls: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  key: const ValueKey('daily-choice-source-filter'),
                  controller: _filterController,
                  decoration: InputDecoration(
                    labelText: l10n.catalogFilterLabel,
                    errorText: switch (selection.filterValidationFailure) {
                      IntentionCatalogFilterValidationFailure
                          .invalidUnicodeRepertoire =>
                        l10n.catalogFilterInvalidUnicode,
                      IntentionCatalogFilterValidationFailure.tooLong =>
                        l10n.catalogFilterTooLong,
                      null => null,
                    },
                  ),
                  onChanged: notifier.changeTitleFilter,
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: IntentionTagConditionsSection(purpose: _purpose),
                ),
              ),
            ],
          ),
          results: IntentionSearchResults(
            purpose: _purpose,
            catalog: catalog,
            listKey: const PageStorageKey<String>('daily-choice-source-list'),
            messages: IntentionSearchResultsMessages(
              loading: l10n.sourcePickerLoading,
              unavailable: l10n.sourcePickerUnavailable,
              corruption: l10n.sourcePickerCorruption,
              unexpected: l10n.sourcePickerUnexpected,
            ),
            // Условия по тегам сужают охват: пустая выдача не означает, что
            // в нём нет намерений.
            emptyMessage: (empty) =>
                empty.query.tagFilter != IntentionTagFilter.empty
                ? l10n.catalogTagConditionsEmpty
                : selection.titleFilterText.trim().isEmpty
                ? l10n.sourcePickerEmpty
                : l10n.sourcePickerNoMatches,
            totalCountLabel: l10n.sourcePickerTotalCount,
            itemBuilder: (context, _, summary) => Row(
              key: ValueKey(
                'daily-choice-source-${summary.id.toCanonicalString()}',
              ),
              children: [
                Expanded(
                  child: IntentionSummaryView(
                    title: summary.title,
                    archiveState: summary.archiveState,
                    showArchiveState: false,
                    traits: [
                      switch (summary.readiness) {
                        IntentionReadiness.ready => l10n.catalogReady,
                        IntentionReadiness.notReady => l10n.catalogNotReady,
                      },
                      summary.hasDescription
                          ? l10n.catalogHasDescription
                          : l10n.catalogNoDescription,
                    ],
                    confirmedTags: summary.tags,
                    activeRelationCount: ConfirmedActiveRelationCount(
                      summary.activeRelationCount,
                    ),
                    tapHint: l10n.sourcePickerSelectHint,
                    onTap: () => unawaited(context.router.maybePop(summary.id)),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.info_outline),
                  tooltip: l10n.sourcePickerOpenDetails,
                  onPressed: () => unawaited(
                    context.router.push(
                      IntentionDetailsRoute(intentionId: summary.id),
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
}
