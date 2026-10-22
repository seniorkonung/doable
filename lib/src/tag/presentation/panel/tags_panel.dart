import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/button.dart';
import '../../../design_system/components/empty_state.dart';
import '../../../design_system/components/list_state.dart';
import '../../../design_system/components/notice.dart';
import '../../../design_system/components/search_field.dart';
import '../../../design_system/components/sheet.dart';
import '../../../design_system/components/tag_create_row.dart';
import '../../../design_system/components/tag_row.dart';
import '../../../design_system/doable_metrics.dart';
import '../../../graph/application/graph_command_coordinator.dart';
import '../catalog/tag_catalog_filter.dart';
import '../catalog/tag_catalog_search_controller.dart';
import '../editor/tag_editor_state.dart';
import '../editor/tag_sheet.dart';
import '../tag_color_presentation.dart';
import 'tags_panel_context.dart';
import 'tags_panel_state.dart';
import 'tags_panel_view_model.dart';

/// Показывает панель тегов над страницей или листом инициатора.
///
/// Нажатия применяются сразу, поэтому «Готово», свайп вниз, касание
/// затемнения и «назад» только закрывают панель. Каждый вызов — новое
/// открытие с пустым поиском. Отказы операций панели общая поверхность
/// показывает поверх неё, над «Готово».
Future<void> showTagsPanel(
  BuildContext context,
  TagsPanelContext panelContext,
) {
  // Открытие создаётся один раз: маршрут может перестраивать содержимое.
  final opening = TagsPanelOpening(panelContext);
  return showDoableExpandableSheet<void>(
    context: context,
    hostsMessages: true,
    builder: (_, sheet) => _TagsPanel(sheet, opening),
  );
}

final class _TagsPanel extends ConsumerStatefulWidget {
  const _TagsPanel(this.sheet, this.opening);

  final ExpandableSheetCapability sheet;
  final TagsPanelOpening opening;

  @override
  ConsumerState<_TagsPanel> createState() => _TagsPanelState();
}

final class _TagsPanelState extends ConsumerState<_TagsPanel> {
  final _searchController = TagCatalogSearchController();

  /// Один ключ на открытие: повторный лист создания не обходит ещё
  /// выполняющееся создание этой панели.
  final _creationKey = TagCreationFormKey();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Лист «Новый тег» поверх панели; принятое в нём создание продолжает
  /// модель панели, поэтому возвращаемое листом значение не нужно.
  void _openCreation(
    String name,
    TagsPanelLoaded catalog,
    TagsPanelViewModel model,
  ) => showTagSheet(
    context,
    TagEditorCreating(
      _creationKey,
      initialName: name,
      existingNames: [for (final row in catalog.rows) row.tag.name],
      onCreationAccepted: model.acceptCreation,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final provider = tagsPanelViewModelProvider(widget.opening);
    final state = ref.watch(provider);
    final model = ref.read(provider.notifier);
    ref.listen(provider, (previous, next) {
      // Ввод в поле всегда даёт новый поиск, поэтому начальный после другого
      // означает сброс моделью после подтверждённого создания.
      if (identical(next.search, TagsPanelSearch.initial) &&
          !identical(previous?.search, next.search)) {
        _searchController.clear();
      }
    });
    final (title, text) = switch (widget.opening.context) {
      TagsPanelAssignmentContext() => (
        l10n.tagsPanelTitle,
        l10n.tagsPanelAssignmentHint,
      ),
    };

    // Маршрут извещает о любом своём закрытии сразу, а содержимое
    // освобождается только после закрывающей анимации.
    return PopScope<void>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) widget.opening.close();
      },
      child: Sheet.expandable(
        widget.sheet,
        title: title,
        text: text,
        expandLabel: l10n.tagsPanelExpand,
        collapseLabel: l10n.tagsPanelCollapse,
        pinned: SearchField(
          controller: _searchController,
          placeholder: l10n.tagsPanelSearchPlaceholder,
          label: l10n.tagsPanelSearchLabel,
          clearLabel: l10n.tagsPanelClearSearch,
          onChanged: model.search,
          error: state.search.inputIsInvalid
              ? l10n.tagsPanelInvalidSearch
              : null,
        ),
        body: switch (state.catalog) {
          TagsPanelLoading() => _StatusBody(
            ListState.loading(text: l10n.tagsPanelLoading),
          ),
          TagsPanelLoadFailure(:final failure, :final canRetry) => _StatusBody(
            ListState.error(
              message: _loadFailureMessage(l10n, failure),
              retry: canRetry
                  ? (label: l10n.commonRetry, onPressed: model.retryLoad)
                  : null,
            ),
          ),
          TagsPanelIntentionMissing() => _StatusBody(
            ListState.error(message: l10n.tagsPanelIntentionMissing),
          ),
          final TagsPanelLoaded loaded => _LoadedCatalog(
            catalog: loaded,
            filter: state.search.filter,
            model: model,
            onCreate: (name) => _openCreation(name, loaded, model),
          ),
        },
        footer: Button.primary(
          label: l10n.tagsPanelDone,
          onPressed: () => Navigator.pop(context),
        ),
      ),
    );
  }
}

/// Состояние всего каталога на месте его строк.
final class _StatusBody extends StatelessWidget {
  const _StatusBody(this.state);

  final ListState state;

  @override
  Widget build(BuildContext context) =>
      ListView(padding: _bodyPadding, children: [state]);
}

final class _LoadedCatalog extends StatelessWidget {
  const _LoadedCatalog({
    required this.catalog,
    required this.filter,
    required this.model,
    required this.onCreate,
  });

  final TagsPanelLoaded catalog;
  final TagCatalogFilter filter;
  final TagsPanelViewModel model;

  /// Открывает создание тега с предложенным названием.
  final ValueChanged<String> onCreate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rows = catalog.rowsMatching(filter);
    final proposedName = catalog.proposedTagName(filter);
    final refreshFailure = catalog.refreshFailure;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Сообщение стоит вне прокрутки: оно видно при любом положении
        // списка и не сдвигает прокрутку показанных строк.
        if (refreshFailure != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              DoableMetrics.space2,
              0,
              DoableMetrics.space2,
              DoableMetrics.space2,
            ),
            child: Notice.content(
              message: Semantics(
                container: true,
                liveRegion: true,
                child: Text(_refreshFailureMessage(l10n, refreshFailure)),
              ),
              action: catalog.canRetryRefresh
                  ? (label: l10n.commonRetry, onPressed: model.retryRefresh)
                  : null,
            ),
          ),
        Expanded(
          child: CustomScrollView(
            slivers: [
              if (catalog.isEmpty && filter.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    title: l10n.tagsPanelEmptyTitle,
                    text: l10n.tagsPanelEmptyText,
                  ),
                )
              else
                SliverPadding(
                  padding: _bodyPadding,
                  sliver: SliverMainAxisGroup(
                    slivers: [
                      if (proposedName != null)
                        SliverToBoxAdapter(
                          child: TagCreateRow(
                            text: l10n.tagsPanelCreateTag(proposedName),
                            label: l10n.tagsPanelCreateTag(proposedName),
                            onPressed: () => onCreate(proposedName),
                          ),
                        ),
                      SliverList.builder(
                        itemCount: rows.length,
                        itemBuilder: (context, index) => _row(
                          rows[index],
                          isCurrent: catalog.rowsAreCurrent,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(TagsPanelRow row, {required bool isCurrent}) {
    final tag = row.tag;
    final name = tag.name.value;
    return TagRow(
      key: ValueKey('tags-panel-row-${tag.id.toCanonicalString()}'),
      name: name,
      color: tagColorPresentation(tag.color),
      mark: row.isMarked ? TagRowMark.checked : TagRowMark.none,
      label: name,
      handle: const TagRowHiddenHandle(),
      // Отказ принадлежит общей поверхности, а нажатие во время изменения
      // назначений намерения координатор отклоняет без сообщения.
      onPressed: isCurrent ? () => model.toggle(tag.id) : null,
    );
  }
}

const _bodyPadding = EdgeInsets.symmetric(horizontal: DoableMetrics.space2);

String _loadFailureMessage(
  AppLocalizations l10n,
  TagsPanelReadFailure failure,
) => switch (failure) {
  TagsPanelReadFailure.unavailable => l10n.tagsPanelLoadUnavailable,
  TagsPanelReadFailure.corruption => l10n.tagsPanelLoadCorruption,
  TagsPanelReadFailure.unexpected => l10n.tagsPanelLoadUnexpected,
};

String _refreshFailureMessage(
  AppLocalizations l10n,
  TagsPanelReadFailure failure,
) => switch (failure) {
  TagsPanelReadFailure.unavailable => l10n.tagsPanelRefreshUnavailable,
  TagsPanelReadFailure.corruption => l10n.tagsPanelRefreshCorruption,
  TagsPanelReadFailure.unexpected => l10n.tagsPanelRefreshUnexpected,
};
