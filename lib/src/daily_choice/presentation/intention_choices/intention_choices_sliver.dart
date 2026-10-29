import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/add_row.dart';
import '../../../design_system/doable_metrics.dart';
import '../../../intention/domain/intention_id.dart';
import '../../../intention/presentation/details/intention_page_target.dart';
import '../../../long_term_relation/application/relation_counts.dart';
import '../../../long_term_relation/application/relation_group_page.dart';
import '../../../long_term_relation/presentation/relation_list_reconciliation.dart';
import '../../../long_term_relation/presentation/relation_list_status.dart';
import '../../application/daily_choice_catalog.dart';
import '../../domain/daily_choice_id.dart';
import 'intention_choices_state.dart';
import 'intention_choices_view_model.dart';

/// Прямые дневные выборы намерения в роли, выбранной на странице.
///
/// Единственный sliver сохраняет ленивое построение строк внутри общего
/// scrollable страницы, а подгрузка следует за построенными строками.
final class IntentionChoicesSliver extends ConsumerStatefulWidget {
  const IntentionChoicesSliver({
    required this.intentionId,
    required this.pageInstance,
    required this.onOpenDailyChoice,
    required this.onAddAsSource,
    required this.onAddAsSelected,
    super.key,
  });

  final IntentionId intentionId;
  final IntentionPageInstance pageInstance;

  /// Открывает сохранённый путь дневного выбора по его идентификатору.
  final ValueChanged<DailyChoiceId> onOpenDailyChoice;

  /// Начинает дневной выбор от этого намерения; без обработчика у роли
  /// «исходное» нет «Добавить».
  final VoidCallback? onAddAsSource;

  /// Начинает дневной выбор, который заканчивается этим намерением; без
  /// обработчика у роли «выбранное» нет «Добавить».
  final VoidCallback? onAddAsSelected;

  @override
  ConsumerState<IntentionChoicesSliver> createState() =>
      _IntentionChoicesSliverState();
}

final class _IntentionChoicesSliverState
    extends ConsumerState<IntentionChoicesSliver> {
  int? _scheduledLoadMoreIndex;

  @override
  Widget build(BuildContext context) {
    final provider = intentionChoicesViewModelProvider(
      widget.intentionId,
      widget.pageInstance,
    );
    final state = ref.watch(provider);
    final viewModel = ref.read(provider.notifier);
    final addRow = _addRow(AppLocalizations.of(context), state);
    final headerCount = addRow == null ? 1 : 2;
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        if (index == 0) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              24,
              16,
              addRow == null ? 16 : DoableMetrics.space1,
            ),
            child: _RoleSummary(
              counts: switch (state) {
                IntentionChoicesConfirmed(:final counts) => counts,
                IntentionChoicesInitialLoad() ||
                IntentionChoicesInitialFailure() ||
                IntentionChoicesIntentionNotFound() => null,
              },
              selectedRole: state.role,
              onSelectRole: viewModel.selectRole,
            ),
          );
        }
        if (addRow != null && index == 1) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, DoableMetrics.space1),
            child: addRow,
          );
        }
        return _buildBodyChild(context, state, index - headerCount, viewModel);
      }, childCount: _bodyChildCount(state) + headerCount),
    );
  }

  /// Подсказка называет роль, только когда её подтверждённый список не пуст;
  /// без «Добавить» и без подсказки строки нет.
  AddRow? _addRow(AppLocalizations l10n, IntentionChoicesState state) {
    final (hint, addLabel, onAdd) = switch (state.role) {
      DailyChoiceRelationRole.source => (
        l10n.detailsChoicesSourceHint,
        l10n.detailsChoicesAddSourceLabel,
        widget.onAddAsSource,
      ),
      DailyChoiceRelationRole.selected => (
        l10n.detailsChoicesSelectedHint,
        l10n.detailsChoicesAddSelectedLabel,
        widget.onAddAsSelected,
      ),
    };
    const addKey = ValueKey('intention-choices-add');
    final hasItems = switch (state) {
      IntentionChoicesLoaded() => true,
      IntentionChoicesInitialLoad() ||
      IntentionChoicesInitialFailure() ||
      IntentionChoicesIntentionNotFound() ||
      IntentionChoicesEmpty() => false,
    };
    return switch ((hasItems, onAdd)) {
      (true, final onAdd?) => AddRow.hint(
        hint: hint,
        addText: l10n.detailsChoicesAdd,
        addLabel: addLabel,
        onAdd: onAdd,
        addKey: addKey,
      ),
      (true, null) => AddRow.hintOnly(hint: hint),
      (false, final onAdd?) => AddRow.addOnly(
        addText: l10n.detailsChoicesAdd,
        addLabel: addLabel,
        onAdd: onAdd,
        addKey: addKey,
      ),
      (false, null) => null,
    };
  }

  int _bodyChildCount(IntentionChoicesState state) => switch (state) {
    IntentionChoicesLoaded(:final items) => items.length + 1,
    IntentionChoicesInitialLoad() ||
    IntentionChoicesInitialFailure() ||
    IntentionChoicesIntentionNotFound() ||
    IntentionChoicesEmpty() => 1,
  };

  Widget _buildBodyChild(
    BuildContext context,
    IntentionChoicesState state,
    int index,
    IntentionChoicesViewModel viewModel,
  ) {
    final localizations = AppLocalizations.of(context);
    return switch (state) {
      IntentionChoicesInitialLoad() => RelationListStatus.initialLoad(
        localizations,
      ),
      final IntentionChoicesInitialFailure failure =>
        RelationListStatus.initialFailure(
          localizations,
          failure: failure.failure,
          onRetry: viewModel.retryFirstPage,
        ),
      IntentionChoicesIntentionNotFound() =>
        RelationListStatus.intentionNotFound(localizations),
      final IntentionChoicesEmpty empty => _EmptyRole(
        summaryStatus: empty.summaryStatus,
        onRetryRefresh: viewModel.retryRefresh,
      ),
      final IntentionChoicesLoaded loaded when index < loaded.items.length =>
        _buildRow(loaded, index, viewModel),
      final IntentionChoicesLoaded loaded => _LoadedRoleFooter(
        state: loaded,
        onRetryLoadMore: loaded.summaryStatus is RelationListSummaryCurrent
            ? viewModel.retryLoadMore
            : null,
        onRetryRefresh: viewModel.retryRefresh,
      ),
    };
  }

  Widget _buildRow(
    IntentionChoicesLoaded state,
    int index,
    IntentionChoicesViewModel viewModel,
  ) {
    _scheduleLoadMore(index, viewModel);
    final item = state.items[index];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: _DailyChoiceRow(
        key: ValueKey('intention-choices-row-${item.id.toCanonicalString()}'),
        item: item,
        role: state.role,
        onOpen: widget.onOpenDailyChoice,
      ),
    );
  }

  void _scheduleLoadMore(
    int visibleIndex,
    IntentionChoicesViewModel viewModel,
  ) {
    if (_scheduledLoadMoreIndex == visibleIndex) {
      return;
    }
    _scheduledLoadMoreIndex = visibleIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _scheduledLoadMoreIndex = null;
      unawaited(viewModel.loadMoreIfNeeded(visibleIndex: visibleIndex));
    });
  }
}

final class _RoleSummary extends StatelessWidget {
  const _RoleSummary({
    required this.counts,
    required this.selectedRole,
    required this.onSelectRole,
  });

  final RelationCounts? counts;
  final DailyChoiceRelationRole selectedRole;
  final ValueChanged<DailyChoiceRelationRole> onSelectRole;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              counts == null
                  ? l10n.dailyChoiceCatalogTitle
                  : l10n.relationNeighborhoodDailyTotal(counts!.dailyTotal),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final role in DailyChoiceRelationRole.values)
                  ChoiceChip(
                    key: ValueKey('intention-choices-role-${role.name}'),
                    label: Text(
                      counts == null
                          ? _roleLabel(l10n, role)
                          : '${_roleLabel(l10n, role)}: '
                                '${counts!.forSelection(DailyChoiceRelationGroup(role: role))}',
                    ),
                    selected: selectedRole == role,
                    onSelected: (_) => onSelectRole(role),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _roleLabel(AppLocalizations l10n, DailyChoiceRelationRole role) =>
    switch (role) {
      DailyChoiceRelationRole.source =>
        l10n.relationNeighborhoodDailySourceRole,
      DailyChoiceRelationRole.selected =>
        l10n.relationNeighborhoodDailySelectedRole,
    };

final class _DailyChoiceRow extends StatelessWidget {
  const _DailyChoiceRow({
    required this.item,
    required this.role,
    required this.onOpen,
    super.key,
  });

  final DailyChoiceCatalogItem item;
  final DailyChoiceRelationRole role;
  final ValueChanged<DailyChoiceId> onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final roleLabel = _roleLabel(l10n, role);
    final phrase = l10n.dailyChoiceDetailsPhrase(
      item.source.title,
      item.selected.title,
    );
    final date = l10n.dailyChoiceDetailsDate(item.date.toCanonicalString());
    final completion = item.isCompleted
        ? l10n.dailyChoiceDetailsCompleted
        : l10n.dailyChoiceDetailsNotCompleted;
    void open() => onOpen(item.id);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        button: true,
        label: [
          l10n.dailyChoiceDetailsTitle,
          roleLabel,
          phrase,
          date,
          completion,
        ].join('. '),
        hint: l10n.relationNeighborhoodOpenDailyChoice,
        onTap: open,
        child: ExcludeSemantics(
          child: InkWell(
            onTap: open,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    roleLabel,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(phrase, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(date),
                  Text(completion),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _EmptyRole extends StatelessWidget {
  const _EmptyRole({required this.summaryStatus, required this.onRetryRefresh});

  final RelationListSummaryStatus summaryStatus;
  final Future<void> Function() onRetryRefresh;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Column(
      children: [
        RelationListStatus(message: localizations.relationNeighborhoodEmpty),
        if (summaryStatus is RelationListSummaryRefreshing)
          RelationListStatus.refreshing(localizations),
        if (summaryStatus case final RelationListSummaryRefreshFailure refresh)
          RelationListStatus.refreshFailure(
            localizations,
            failure: refresh.failure,
            onRetry: onRetryRefresh,
          ),
      ],
    );
  }
}

final class _LoadedRoleFooter extends StatelessWidget {
  const _LoadedRoleFooter({
    required this.state,
    required this.onRetryLoadMore,
    required this.onRetryRefresh,
  });

  final IntentionChoicesLoaded state;
  final Future<void> Function()? onRetryLoadMore;
  final Future<void> Function() onRetryRefresh;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return switch ((state.progress, state.summaryStatus)) {
      (RelationListLoadingMore(), _) => RelationListStatus.loadingMore(
        localizations,
      ),
      (final RelationListLoadMoreFailure failure, _) =>
        RelationListStatus.loadMoreFailure(
          localizations,
          failure: failure.failure,
          onRetry: onRetryLoadMore,
        ),
      (RelationListIdle(), RelationListSummaryRefreshing()) =>
        RelationListStatus.refreshing(localizations),
      (RelationListIdle(), final RelationListSummaryRefreshFailure refresh) =>
        RelationListStatus.refreshFailure(
          localizations,
          failure: refresh.failure,
          onRetry: onRetryRefresh,
        ),
      (RelationListIdle(), RelationListSummaryCurrent()) =>
        state.hasConfirmedEnd
            ? RelationListStatus.confirmedEnd(localizations)
            : const SizedBox(height: 16),
    };
  }
}
