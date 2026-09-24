import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/routing/app_router.gr.dart';
import '../../application/daily_choice_catalog.dart';
import '../../domain/calendar_date.dart';
import 'daily_choice_catalog_state.dart';
import 'daily_choice_catalog_view_model.dart';

@RoutePage()
final class DailyChoiceCatalogPage extends ConsumerStatefulWidget {
  const DailyChoiceCatalogPage({super.key});

  @override
  ConsumerState<DailyChoiceCatalogPage> createState() =>
      _DailyChoiceCatalogPageState();
}

final class _DailyChoiceCatalogPageState
    extends ConsumerState<DailyChoiceCatalogPage> {
  final _dateController = TextEditingController();
  String? _dateError;

  @override
  void dispose() {
    _dateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(dailyChoiceCatalogViewModelProvider);
    final model = ref.read(dailyChoiceCatalogViewModelProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.dailyChoiceCatalogTitle)),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight * 0.55,
                ),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 190,
                          child: TextField(
                            key: const ValueKey('daily-choice-date-filter'),
                            controller: _dateController,
                            keyboardType: TextInputType.datetime,
                            decoration: InputDecoration(
                              labelText: l10n.dailyChoiceCatalogDateFilter,
                              hintText: l10n.dailyChoiceCreationDateHint,
                              errorText: _dateError,
                            ),
                            onSubmitted: (_) => _applyDate(model, l10n),
                          ),
                        ),
                        OutlinedButton(
                          key: const ValueKey('daily-choice-apply-date'),
                          onPressed: () => _applyDate(model, l10n),
                          child: Text(l10n.dailyChoiceCatalogApplyDate),
                        ),
                        SizedBox(
                          key: const ValueKey('daily-choice-completion-filter'),
                          width: 240,
                          child: DropdownButtonFormField<bool?>(
                            key: ValueKey(state.selection.isCompleted),
                            initialValue: state.selection.isCompleted,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText:
                                  l10n.dailyChoiceCatalogCompletionFilter,
                            ),
                            items: [
                              DropdownMenuItem<bool?>(
                                value: null,
                                child: Text(l10n.dailyChoiceCatalogAllStates),
                              ),
                              DropdownMenuItem<bool?>(
                                value: false,
                                child: Text(l10n.dailyChoiceCatalogIncomplete),
                              ),
                              DropdownMenuItem<bool?>(
                                value: true,
                                child: Text(l10n.dailyChoiceCatalogCompleted),
                              ),
                            ],
                            onChanged: model.selectCompletion,
                          ),
                        ),
                        TextButton(
                          key: const ValueKey('daily-choice-clear-filters'),
                          onPressed: () {
                            _dateController.clear();
                            setState(() => _dateError = null);
                            model.clearFilters();
                          },
                          child: Text(l10n.dailyChoiceCatalogClearFilters),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(child: _content(state, model, l10n)),
            ],
          ),
        ),
      ),
    );
  }

  void _applyDate(DailyChoiceCatalogViewModel model, AppLocalizations l10n) {
    final input = _dateController.text.trim();
    if (input.isEmpty) {
      setState(() => _dateError = null);
      model.selectDate(null);
      return;
    }
    try {
      final date = CalendarDate.parseCanonical(input);
      setState(() => _dateError = null);
      model.selectDate(date);
    } on CalendarDateValidationException {
      setState(() => _dateError = l10n.dailyChoiceCatalogDateInvalid);
    }
  }

  Widget _content(
    DailyChoiceCatalogState state,
    DailyChoiceCatalogViewModel model,
    AppLocalizations l10n,
  ) => switch (state) {
    DailyChoiceCatalogInitialLoad() => _Status(
      message: l10n.dailyChoiceCatalogLoading,
      loading: true,
    ),
    DailyChoiceCatalogInitialFailure(:final failure, :final canRetry) =>
      _Status(
        message: _failureMessage(failure, l10n),
        onRetry: canRetry ? model.retryFirstPage : null,
      ),
    DailyChoiceCatalogEmpty() => _loaded(state, model, l10n),
    DailyChoiceCatalogLoaded() => _loaded(state, model, l10n),
  };

  Widget _loaded(
    DailyChoiceCatalogLoaded state,
    DailyChoiceCatalogViewModel model,
    AppLocalizations l10n,
  ) {
    final isRefreshing =
        state.freshness == DailyChoiceCatalogFreshness.refreshing;
    final isStale = state.freshness == DailyChoiceCatalogFreshness.stale;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Semantics(
            liveRegion: true,
            child: Text(l10n.dailyChoiceCatalogTotalCount(state.totalCount)),
          ),
        ),
        if (isRefreshing)
          _Banner(message: l10n.dailyChoiceCatalogRefreshing, loading: true),
        if (isStale)
          _Banner(
            message: _failureMessage(state.refreshFailure!, l10n),
            onRetry:
                state.refreshFailure is DailyChoiceCatalogUnavailableFailure
                ? model.retryRefresh
                : null,
          ),
        Expanded(
          child: state.items.isEmpty
              ? _Status(message: l10n.dailyChoiceCatalogEmpty)
              : ListView.builder(
                  itemCount:
                      state.items.length + (state.nextCursor == null ? 0 : 1),
                  itemBuilder: (context, index) {
                    if (index == state.items.length) {
                      return _pageFooter(state, model, l10n);
                    }
                    final item = state.items[index];
                    final phrase = l10n.dailyChoiceDetailsPhrase(
                      item.source.title,
                      item.selected.title,
                    );
                    final date = item.date.toCanonicalString();
                    final completion = item.isCompleted
                        ? l10n.dailyChoiceDetailsCompleted
                        : l10n.dailyChoiceDetailsNotCompleted;
                    void open() => context.router.push(
                      DailyChoiceDetailsRoute(choiceId: item.id),
                    );
                    return Semantics(
                      key: ValueKey('daily-choice-row-${index + 1}'),
                      button: true,
                      label: l10n.dailyChoiceCatalogRowLabel(
                        index + 1,
                        phrase,
                        date,
                        completion,
                      ),
                      onTap: open,
                      child: ExcludeSemantics(
                        child: ListTile(
                          title: Text(phrase),
                          subtitle: Text(
                            '${l10n.dailyChoiceDetailsDate(date)} · $completion',
                          ),
                          onTap: open,
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _pageFooter(
    DailyChoiceCatalogLoaded state,
    DailyChoiceCatalogViewModel model,
    AppLocalizations l10n,
  ) => switch (state.pageStatus) {
    DailyChoiceCatalogPageLoading() => _Status(
      message: l10n.dailyChoiceCatalogLoadingMore,
      loading: true,
    ),
    DailyChoiceCatalogPageFailure(:final failure, :final canRetry) => _Status(
      message: _failureMessage(failure, l10n),
      onRetry: canRetry ? model.retryLoadMore : null,
    ),
    DailyChoiceCatalogPageIdle() => Center(
      child: TextButton(
        key: const ValueKey('daily-choice-load-more'),
        onPressed: state.freshness == DailyChoiceCatalogFreshness.current
            ? model.loadMore
            : null,
        child: Text(l10n.dailyChoiceCatalogLoadMore),
      ),
    ),
  };

  String _failureMessage(
    DailyChoiceCatalogReadFailure failure,
    AppLocalizations l10n,
  ) => switch (failure) {
    DailyChoiceCatalogUnavailableFailure() =>
      l10n.dailyChoiceCatalogUnavailable,
    DailyChoiceCatalogCorruptionFailure() => l10n.dailyChoiceCatalogCorruption,
    DailyChoiceCatalogSnapshotExpired() => l10n.dailyChoiceCatalogExpired,
    DailyChoiceCatalogValidationFailure() => l10n.dailyChoiceCatalogInvalid,
    DailyChoiceCatalogUnexpectedFailure() => l10n.dailyChoiceCatalogUnexpected,
  };
}

final class _Status extends StatelessWidget {
  const _Status({required this.message, this.loading = false, this.onRetry});

  final String message;
  final bool loading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading) const CircularProgressIndicator(),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null)
              TextButton(
                onPressed: onRetry,
                child: Text(AppLocalizations.of(context).commonRetry),
              ),
          ],
        ),
      ),
    ),
  );
}

final class _Banner extends StatelessWidget {
  const _Banner({required this.message, this.loading = false, this.onRetry});

  final String message;
  final bool loading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          if (loading)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: Text(AppLocalizations.of(context).commonRetry),
            ),
        ],
      ),
    ),
  );
}
