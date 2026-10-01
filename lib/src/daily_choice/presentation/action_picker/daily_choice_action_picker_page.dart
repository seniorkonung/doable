import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/routing/app_router.gr.dart';
import '../../../intention/application/intention_catalog.dart';
import '../../../intention/presentation/catalog/intention_catalog_purpose.dart';
import '../../../intention/presentation/catalog/intention_catalog_state.dart';
import '../../../intention/presentation/catalog/intention_catalog_status_views.dart';
import '../../../intention/presentation/catalog/intention_catalog_view_model.dart';
import '../../../intention/presentation/catalog/intention_tag_conditions_section.dart';
import '../../../intention/presentation/intention_summary_view.dart';

const _purpose = SelectDailyChoiceAction();

/// Выбор активного действия перед поиском основания дневного выбора.
///
/// Список использует отдельную сессию ограниченного каталога. Только открытие
/// подробностей читает полный текст выбранного намерения; результат выбора —
/// его идентификатор, поэтому одноимённые действия не смешиваются.
@RoutePage()
final class DailyChoiceActionPickerPage extends ConsumerStatefulWidget {
  const DailyChoiceActionPickerPage({super.key});

  @override
  ConsumerState<DailyChoiceActionPickerPage> createState() =>
      _DailyChoiceActionPickerPageState();
}

final class _DailyChoiceActionPickerPageState
    extends ConsumerState<DailyChoiceActionPickerPage> {
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
    final notifier = ref.read(
      intentionCatalogViewModelProvider(_purpose).notifier,
    );
    final selection = catalog.value?.selection ?? notifier.selection;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.actionPickerTitle),
        leading: IconButton(
          key: const ValueKey('daily-choice-action-cancel'),
          icon: const Icon(Icons.close),
          tooltip: l10n.actionPickerCancel,
          onPressed: () => unawaited(context.router.maybePop()),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                key: const ValueKey('daily-choice-action-filter'),
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
                  if (_scrollController.hasClients) _scrollController.jumpTo(0);
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
            Expanded(
              child: catalog.when(
                skipLoadingOnReload: false,
                skipLoadingOnRefresh: false,
                data: (state) => switch (state) {
                  IntentionCatalogDebouncing() => IntentionCatalogStatusView(
                    message: l10n.actionPickerLoading,
                    progressIndicator: true,
                  ),
                  IntentionCatalogInvalidFilter() => const SizedBox.shrink(),
                  final IntentionCatalogLoaded loaded => _ActionOptions(
                    state: loaded,
                    scrollController: _scrollController,
                  ),
                  final IntentionCatalogEmpty empty =>
                    IntentionCatalogStatusView(
                      // Условия по тегам сужают охват: пустая выдача не
                      // означает, что в нём нет намерений.
                      message: empty.query.tagFilter != IntentionTagFilter.empty
                          ? l10n.catalogTagConditionsEmpty
                          : selection.titleFilterText.trim().isEmpty
                          ? l10n.actionPickerEmpty
                          : l10n.actionPickerNoMatches,
                    ),
                  IntentionCatalogUnavailable() => IntentionCatalogStatusView(
                    message: l10n.actionPickerUnavailable,
                    retryLabel: l10n.commonRetry,
                    onRetry: () => unawaited(notifier.retry()),
                  ),
                  IntentionCatalogCorruption() => IntentionCatalogStatusView(
                    message: l10n.actionPickerCorruption,
                  ),
                  IntentionCatalogUnexpected() => IntentionCatalogStatusView(
                    message: l10n.actionPickerUnexpected,
                  ),
                },
                error: (_, _) => IntentionCatalogStatusView(
                  message: l10n.actionPickerUnexpected,
                ),
                loading: () => IntentionCatalogStatusView(
                  message: l10n.actionPickerLoading,
                  progressIndicator: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _ActionOptions extends ConsumerWidget {
  const _ActionOptions({required this.state, required this.scrollController});

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
            l10n.actionPickerTotalCount(state.totalCount),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        // Отказ обновления стоит над списком и не заменяет сохранённую выдачу.
        IntentionCatalogRefreshStatusView(
          purpose: _purpose,
          refresh: state.refresh,
        ),
        Expanded(
          child: ListView.builder(
            key: const PageStorageKey<String>('daily-choice-action-list'),
            controller: scrollController,
            itemCount: state.items.length + (hasContinuationStatus ? 1 : 0),
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
                        intentionCatalogViewModelProvider(_purpose).notifier,
                      )
                      .loadNextPageIfNeeded(visibleIndex: index),
                );
              });
              final summary = state.items[index];
              return Row(
                key: ValueKey(
                  'daily-choice-action-${summary.id.toCanonicalString()}',
                ),
                children: [
                  Expanded(
                    child: IntentionSummaryView(
                      title: summary.title,
                      archiveState: summary.archiveState,
                      showArchiveState: false,
                      traits: [
                        summary.hasDescription
                            ? l10n.catalogHasDescription
                            : l10n.catalogNoDescription,
                      ],
                      confirmedTags: summary.tags,
                      activeRelationCount: ConfirmedActiveRelationCount(
                        summary.activeRelationCount,
                      ),
                      tapHint: l10n.actionPickerSelectHint,
                      onTap: () =>
                          unawaited(context.router.maybePop(summary.id)),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.info_outline),
                    tooltip: l10n.actionPickerOpenDetails,
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
    );
  }
}
