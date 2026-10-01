import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../tag/application/tag_catalog.dart';
import '../../../tag/domain/tag.dart';
import '../../../tag/domain/tag_id.dart';
import '../../../tag/presentation/catalog/tag_catalog_filter.dart';
import '../../../tag/presentation/catalog/tag_catalog_search_controller.dart';
import '../../../tag/presentation/catalog/tag_catalog_state.dart';
import '../../../tag/presentation/catalog/tag_catalog_view_model.dart';
import 'intention_tag_conditions_view_model.dart';

/// Выбор тега для условия поиска намерений.
///
/// Экран показывает полный снимок каталога тегов в порядке создания и сужает
/// его по названию. Выбор возвращает типизированный результат с тегом,
/// надобностью и ревизией снимка; закрытие без выбора не возвращает ничего.
/// Состояние принадлежит одному открытию и не разделяется с каталогом тегов.
/// Экран только читает теги: он не создаёт, не назначает и не снимает их.
@RoutePage()
final class TagConditionPickerPage extends ConsumerStatefulWidget {
  const TagConditionPickerPage({required this.conditions, super.key});

  /// Условия вызвавшего поиска на момент открытия: их теги отмечаются
  /// текущей надобностью.
  final List<IntentionTagCondition> conditions;

  @override
  ConsumerState<TagConditionPickerPage> createState() =>
      _TagConditionPickerPageState();
}

final class _TagConditionPickerPageState
    extends ConsumerState<TagConditionPickerPage> {
  final _opening = TagCatalogOpening();
  final _scrollController = ScrollController();
  final _searchController = TagCatalogSearchController();
  TagCatalogFilter _filter = TagCatalogFilter.empty;
  bool _searchIsInvalid = false;

  TagCatalogViewModelProvider get _provider =>
      tagCatalogViewModelProvider(opening: _opening);

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _updateSearch(String input) {
    final result = TagCatalogFilter.fromInput(input);
    setState(() {
      switch (result) {
        case TagCatalogFilter():
          _filter = result;
          _searchIsInvalid = false;
        case TagCatalogFilterInvalidUnicode():
          _searchIsInvalid = true;
      }
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  void _clearSearch() {
    _searchController.clear();
    _updateSearch('');
  }

  void _select(
    TagCatalogLoaded loaded,
    Tag tag,
    IntentionTagRequirement requirement,
  ) => unawaited(
    context.router.maybePop<IntentionTagConditionSelection>(
      IntentionTagConditionSelection(
        tag: tag,
        requirement: requirement,
        snapshotRevision: loaded.revision,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final state = ref.watch(_provider);
    final model = ref.read(_provider.notifier);
    return Scaffold(
      appBar: AppBar(title: Text(localizations.tagConditionPickerTitle)),
      body: CustomScrollView(
        key: const ValueKey('tag-condition-picker-list'),
        controller: _scrollController,
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                key: const ValueKey('tag-condition-picker-search'),
                controller: _searchController,
                onChanged: _updateSearch,
                decoration: InputDecoration(
                  labelText: localizations.tagCatalogSearch,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: localizations.tagCatalogClearSearch,
                          onPressed: _clearSearch,
                          icon: const Icon(Icons.clear),
                        ),
                  error: _searchIsInvalid
                      ? Semantics(
                          liveRegion: true,
                          child: Text(localizations.tagCatalogInvalidSearch),
                        )
                      : null,
                ),
              ),
            ),
          ),
          ...switch (state) {
            TagCatalogInitialLoading() => [
              _FillStatus(
                message: localizations.tagCatalogLoading,
                loading: true,
              ),
            ],
            TagCatalogInitialFailure(:final failure, :final canRetry) => [
              _FillStatus(
                message: _readFailure(localizations, failure),
                onRetry: canRetry ? model.retryInitialLoad : null,
              ),
            ],
            // Режим просмотра не читает намерение и этого состояния не даёт.
            TagCatalogIntentionMissing() => [
              _FillStatus(message: localizations.tagCatalogUnexpected),
            ],
            TagCatalogLoaded loaded => _loaded(localizations, loaded, model),
          },
        ],
      ),
    );
  }

  List<Widget> _loaded(
    AppLocalizations localizations,
    TagCatalogLoaded loaded,
    TagCatalogViewModel model,
  ) {
    if (loaded.isEmpty && loaded.canUseCurrentItems) {
      return [_FillStatus(message: localizations.tagCatalogEmpty)];
    }
    final tags = [
      for (final tag in loaded.items)
        if (_filter.matches(tag.name)) tag,
    ];
    final requirements = <TagId, IntentionTagRequirement>{
      for (final condition in widget.conditions)
        condition.tagId: condition.requirement,
    };
    return [
      SliverToBoxAdapter(
        child: switch (loaded.freshness) {
          TagCatalogFreshness.current => const SizedBox.shrink(),
          TagCatalogFreshness.refreshing => _InlineStatus(
            message: localizations.tagCatalogRefreshing,
            loading: true,
          ),
          TagCatalogFreshness.stale => _InlineStatus(
            message: _readFailure(localizations, loaded.refreshFailure!),
            onRetry: loaded.refreshFailure is TagCatalogUnavailableFailure
                ? model.retryRefresh
                : null,
          ),
        },
      ),
      if (tags.isEmpty && loaded.canUseCurrentItems)
        _FillStatus(message: localizations.tagCatalogNoMatches)
      else
        SliverList.builder(
          itemCount: tags.length,
          itemBuilder: (context, index) {
            final tag = tags[index];
            return _TagRow(
              tag: tag,
              selectedRequirement: requirements[tag.id],
              onSelect: (requirement) => _select(loaded, tag, requirement),
            );
          },
        ),
    ];
  }
}

/// Тег с действиями «Есть» и «Нет»; нажатие на саму строку ничего не выбирает.
final class _TagRow extends StatelessWidget {
  const _TagRow({
    required this.tag,
    required this.selectedRequirement,
    required this.onSelect,
  });

  final Tag tag;
  final IntentionTagRequirement? selectedRequirement;
  final ValueChanged<IntentionTagRequirement> onSelect;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final id = tag.id.toCanonicalString();
    final name = tag.name.value;
    return Semantics(
      key: ValueKey('tag-condition-picker-row-$id'),
      container: true,
      selected: selectedRequirement != null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              name,
              key: const ValueKey('tag-condition-picker-name'),
              style: theme.textTheme.titleMedium,
            ),
            if (selectedRequirement case final requirement?)
              Text(switch (requirement) {
                IntentionTagRequirement.mustBePresent =>
                  localizations.tagConditionPickerSelectedPresent,
                IntentionTagRequirement.mustBeAbsent =>
                  localizations.tagConditionPickerSelectedAbsent,
              }, style: theme.textTheme.bodyMedium),
            // Действия переносятся под название при нехватке ширины.
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  key: ValueKey('tag-condition-picker-mustBePresent-$id'),
                  onPressed: () =>
                      onSelect(IntentionTagRequirement.mustBePresent),
                  icon: const Icon(Icons.check),
                  label: Text(
                    localizations.tagConditionPickerPresent,
                    semanticsLabel: localizations
                        .tagConditionPickerPresentNamed(name),
                  ),
                ),
                OutlinedButton.icon(
                  key: ValueKey('tag-condition-picker-mustBeAbsent-$id'),
                  onPressed: () =>
                      onSelect(IntentionTagRequirement.mustBeAbsent),
                  icon: const Icon(Icons.block),
                  label: Text(
                    localizations.tagConditionPickerAbsent,
                    semanticsLabel: localizations.tagConditionPickerAbsentNamed(
                      name,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

final class _FillStatus extends StatelessWidget {
  const _FillStatus({
    required this.message,
    this.loading = false,
    this.onRetry,
  });

  final String message;
  final bool loading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => SliverFillRemaining(
    hasScrollBody: false,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: _StatusContent(
          message: message,
          loading: loading,
          onRetry: onRetry,
        ),
      ),
    ),
  );
}

final class _InlineStatus extends StatelessWidget {
  const _InlineStatus({
    required this.message,
    this.loading = false,
    this.onRetry,
  });

  final String message;
  final bool loading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: _StatusContent(message: message, loading: loading, onRetry: onRetry),
  );
}

final class _StatusContent extends StatelessWidget {
  const _StatusContent({
    required this.message,
    required this.loading,
    this.onRetry,
  });

  final String message;
  final bool loading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: true,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (loading) ...[
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
        ],
        Text(message, textAlign: TextAlign.center),
        if (onRetry case final retry?) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: retry,
            child: Text(AppLocalizations.of(context).commonRetry),
          ),
        ],
      ],
    ),
  );
}

String _readFailure(
  AppLocalizations localizations,
  TagCatalogReadFailure failure,
) => switch (failure) {
  TagCatalogUnavailableFailure() => localizations.tagCatalogUnavailable,
  TagCatalogCorruptionFailure() => localizations.tagCatalogCorruption,
  TagCatalogIntentionNotFound() ||
  TagCatalogUnexpectedFailure() => localizations.tagCatalogUnexpected,
};
