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
import '../../../intention/presentation/catalog/intention_catalog_status_views.dart';
import '../../../intention/presentation/catalog/intention_catalog_view_model.dart';
import '../../../intention/presentation/catalog/intention_search_layout.dart';
import '../../../intention/presentation/catalog/intention_tag_conditions_section.dart';
import '../../../intention/presentation/catalog/intention_tag_conditions_view_model.dart';
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
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _filterController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final catalog = ref.watch(intentionCatalogViewModelProvider(_purpose));
    // Добавление, переключение и снятие условия начинают новую выдачу;
    // переименование и удаление тега меняют только предъявление условия.
    ref.listen(intentionTagConditionsViewModelProvider(_purpose), (
      previous,
      next,
    ) {
      if (previous?.tagFilter != next.tagFilter) {
        _scrollToTop();
      }
    });
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
                  onChanged: (value) {
                    _scrollToTop();
                    notifier.changeTitleFilter(value);
                  },
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
          results: catalog.when(
            skipLoadingOnReload: false,
            skipLoadingOnRefresh: false,
            data: (state) => switch (state) {
              IntentionCatalogDebouncing() => IntentionCatalogStatusView(
                message: l10n.sourcePickerLoading,
                progressIndicator: true,
              ),
              IntentionCatalogInvalidFilter() => const SizedBox.shrink(),
              final IntentionCatalogLoaded loaded => _SourceOptions(
                state: loaded,
                scrollController: _scrollController,
              ),
              final IntentionCatalogEmpty empty => _EmptySources(
                refresh: empty.refresh,
                // Условия по тегам сужают охват: пустая выдача не
                // означает, что в нём нет намерений.
                message: empty.query.tagFilter != IntentionTagFilter.empty
                    ? l10n.catalogTagConditionsEmpty
                    : selection.titleFilterText.trim().isEmpty
                    ? l10n.sourcePickerEmpty
                    : l10n.sourcePickerNoMatches,
              ),
              IntentionCatalogUnavailable() => IntentionCatalogStatusView(
                message: l10n.sourcePickerUnavailable,
                retryLabel: l10n.commonRetry,
                onRetry: () => unawaited(notifier.retry()),
              ),
              IntentionCatalogCorruption() => IntentionCatalogStatusView(
                message: l10n.sourcePickerCorruption,
              ),
              IntentionCatalogUnexpected() => IntentionCatalogStatusView(
                message: l10n.sourcePickerUnexpected,
              ),
            },
            error: (_, _) => IntentionCatalogStatusView(
              message: l10n.sourcePickerUnexpected,
            ),
            loading: () => IntentionCatalogStatusView(
              message: l10n.sourcePickerLoading,
              progressIndicator: true,
            ),
          ),
        ),
      ),
    );
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }
}

/// Пустая выдача поиска исходного намерения с состоянием её обновления.
///
/// Отказ обновления стоит над сообщением о пустоте, поэтому не обновлённую
/// выдачу нельзя принять за успешное отсутствие совпадений.
final class _EmptySources extends StatelessWidget {
  const _EmptySources({required this.refresh, required this.message});

  final IntentionCatalogRefreshState refresh;
  final String message;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IntentionCatalogRefreshStatusArea(
          availableHeight: constraints.maxHeight,
          child: IntentionCatalogRefreshStatusView(
            purpose: _purpose,
            refresh: refresh,
          ),
        ),
        Expanded(child: IntentionCatalogStatusView(message: message)),
      ],
    ),
  );
}

final class _SourceOptions extends ConsumerWidget {
  const _SourceOptions({required this.state, required this.scrollController});

  final IntentionCatalogLoaded state;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final hasContinuationStatus =
        state.continuation is! IntentionCatalogContinuationIdle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            l10n.sourcePickerTotalCount(state.totalCount),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Отказ обновления стоит над списком и не заменяет сохранённую выдачу.
                IntentionCatalogRefreshStatusArea(
                  availableHeight: constraints.maxHeight,
                  child: IntentionCatalogRefreshStatusView(
                    purpose: _purpose,
                    refresh: state.refresh,
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    key: const PageStorageKey<String>(
                      'daily-choice-source-list',
                    ),
                    controller: scrollController,
                    itemCount:
                        state.items.length + (hasContinuationStatus ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == state.items.length) {
                        return IntentionCatalogContinuationStatusView(
                          purpose: _purpose,
                          continuation: state.continuation,
                        );
                      }
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!context.mounted) return;
                        unawaited(
                          ref
                              .read(
                                intentionCatalogViewModelProvider(_purpose)
                                    .notifier,
                              )
                              .loadNextPageIfNeeded(visibleIndex: index),
                        );
                      });
                      final summary = state.items[index];
                      return Row(
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
                                  IntentionReadiness.notReady =>
                                    l10n.catalogNotReady,
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
                              onTap: () => unawaited(
                                context.router.maybePop(summary.id),
                              ),
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
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
