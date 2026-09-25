import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/routing/app_router.gr.dart';
import '../../../intention/domain/intention.dart';
import '../../../intention/presentation/catalog/intention_catalog_purpose.dart';
import '../../../intention/presentation/catalog/intention_catalog_state.dart';
import '../../../intention/presentation/catalog/intention_catalog_status_views.dart';
import '../../../intention/presentation/catalog/intention_catalog_view_model.dart';
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
        child: Column(
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
                  if (_scrollController.hasClients) _scrollController.jumpTo(0);
                  notifier.changeTitleFilter(value);
                },
              ),
            ),
            Expanded(
              child: catalog.when(
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
                  IntentionCatalogEmpty() => IntentionCatalogStatusView(
                    message: selection.titleFilterText.trim().isEmpty
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
          ],
        ),
      ),
    );
  }
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
          child: ListView.builder(
            key: const PageStorageKey<String>('daily-choice-source-list'),
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
                      activeRelationCount: ConfirmedActiveRelationCount(
                        summary.activeRelationCount,
                      ),
                      tapHint: l10n.sourcePickerSelectHint,
                      onTap: () =>
                          unawaited(context.router.maybePop(summary.id)),
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
    );
  }
}
