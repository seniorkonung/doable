import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/button.dart';
import '../../../design_system/components/confirm_dialog.dart';
import '../../../design_system/components/empty_state.dart';
import '../../../design_system/components/list_state.dart';
import '../../../design_system/components/notice.dart';
import '../../../design_system/components/popup_menu.dart';
import '../../../design_system/components/search_field.dart';
import '../../../design_system/components/sheet.dart';
import '../../../design_system/components/tag_create_row.dart';
import '../../../design_system/components/tag_row.dart';
import '../../../design_system/doable_icon.dart';
import '../../../design_system/doable_metrics.dart';
import '../../../graph/application/graph_command_coordinator.dart';
import '../../application/tag_command.dart';
import '../../domain/tag.dart';
import '../../domain/tag_id.dart';
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

  /// Тег, меню которого открыто: его строка показана удерживаемой.
  TagId? _heldTagId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Лист «Новый тег» поверх панели; принятое в нём создание продолжает
  /// модель панели, поэтому возвращаемое листом значение не нужно.
  void _openCreation(
    TagCreationProposal proposal,
    TagsPanelLoaded catalog,
    TagsPanelViewModel model,
  ) => showTagSheet(
    context,
    TagEditorCreating(
      _creationKey,
      initialName: proposal.name,
      initialColor: proposal.color,
      placement: proposal.placement,
      existingNames: [for (final row in catalog.rows) row.tag.name],
      onCreationAccepted: model.acceptCreation,
    ),
  );

  /// Меню тега у строки [row]. Пока оно открыто, строка удерживаемая.
  Future<void> _openMenu(BuildContext row, Tag tag) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _heldTagId = tag.id);
    final action = await showPopupMenu<_TagAction>(
      row: row,
      contentInset: TagRow.contentInset,
      label: l10n.tagsPanelTagMenu(tag.name.value),
      actions: [
        PopupMenuAction(
          value: _TagAction.edit,
          icon: DoableIconData.edit,
          name: l10n.tagsPanelEditTag,
        ),
        PopupMenuAction(
          value: _TagAction.duplicate,
          icon: DoableIconData.copy,
          name: l10n.tagsPanelDuplicateTag,
        ),
      ],
      destructive: PopupMenuAction(
        value: _TagAction.delete,
        icon: DoableIconData.delete,
        name: l10n.tagsPanelDeleteTag,
      ),
    );
    if (!mounted) return;
    setState(() => _heldTagId = null);
    if (action != null) _runAction(action, tag.id);
  }

  /// Действие над тегом [tagId] из меню или у экранного диктора. Каталог мог
  /// измениться, пока меню было открыто, поэтому действие берёт актуальный
  /// тег и недоступно, если строки неактуальны или тега больше нет.
  void _runAction(_TagAction action, TagId tagId) {
    final provider = tagsPanelViewModelProvider(widget.opening);
    final catalog = ref.read(provider).catalog;
    if (catalog is! TagsPanelLoaded || !catalog.rowsAreCurrent) return;
    final tag = catalog.rows
        .where((row) => row.tag.id == tagId)
        .firstOrNull
        ?.tag;
    if (tag == null) return;
    final model = ref.read(provider.notifier);
    switch (action) {
      case _TagAction.edit:
        unawaited(
          showTagSheet(
            context,
            TagEditorRenaming(
              tag,
              existingNames: [for (final row in catalog.rows) row.tag.name],
            ),
          ),
        );
      case _TagAction.duplicate:
        _openCreation(catalog.duplicationOf(tagId)!, catalog, model);
      case _TagAction.delete:
        unawaited(_confirmDeletion(tag, model));
    }
  }

  Future<void> _confirmDeletion(Tag tag, TagsPanelViewModel model) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showConfirmDialog(
      context: context,
      title: l10n.tagsPanelDeleteTitle,
      text: ConfirmDialogText(
        before: l10n.tagsPanelDeleteTextBefore,
        name: tag.name.value,
        after: l10n.tagsPanelDeleteTextAfter,
      ),
      cancelLabel: l10n.tagsPanelDeleteCancel,
      actionLabel: l10n.tagsPanelDeleteConfirm,
    );
    if (confirmed && mounted) model.delete(tag.id);
  }

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
      TagsPanelAssignmentContext() || TagsPanelDraftContext() => (
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
            canReorder: state.canReorder,
            model: model,
            heldTagId: _heldTagId,
            onCreate: (proposal) => _openCreation(proposal, loaded, model),
            menuOf: (row, tag) => TagRowMenu(
              holdHint: l10n.tagsPanelTagHoldHint,
              onOpen: () => unawaited(_openMenu(row, tag)),
              actions: [
                for (final (action, label) in [
                  (_TagAction.edit, l10n.tagsPanelEditTag),
                  (_TagAction.duplicate, l10n.tagsPanelDuplicateTag),
                  (_TagAction.delete, l10n.tagsPanelDeleteTag),
                ])
                  (label: label, onInvoke: () => _runAction(action, tag.id)),
              ],
            ),
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
    required this.canReorder,
    required this.model,
    required this.heldTagId,
    required this.onCreate,
    required this.menuOf,
  });

  final TagsPanelLoaded catalog;
  final TagCatalogFilter filter;

  /// Новая перестановка доступна: строки актуальны, и предыдущая не
  /// выполняется.
  final bool canReorder;

  final TagsPanelViewModel model;

  /// Тег, меню которого открыто.
  final TagId? heldTagId;

  /// Открывает создание тега с предложенными значениями.
  final ValueChanged<TagCreationProposal> onCreate;

  /// Меню тега [tag], открываемое у строки [row].
  final TagRowMenu Function(BuildContext row, Tag tag) menuOf;

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
                            onPressed: () => onCreate(
                              TagCreationProposal(
                                name: proposedName,
                                color: null,
                                placement: TagPlacement.first,
                              ),
                            ),
                          ),
                        ),
                      // Переставляется только полный список на актуальных
                      // строках; список сам предлагает экранному диктору
                      // команды перемещения каждой строки.
                      if (filter.isEmpty && catalog.rowsAreCurrent)
                        SliverReorderableList(
                          itemCount: rows.length,
                          onReorderItem: (from, to) =>
                              model.move(rows[from].tag.id, to),
                          proxyDecorator: (_, index, _) => _row(
                            rows[index],
                            handle: TagRowDragHandle(
                              index: index,
                              enabled: false,
                            ),
                            ground: TagRowGround.lifted,
                            isCurrent: false,
                          ),
                          itemBuilder: (context, index) => _row(
                            rows[index],
                            handle: TagRowDragHandle(
                              index: index,
                              enabled: canReorder,
                            ),
                            isCurrent: true,
                          ),
                        )
                      else
                        SliverList.builder(
                          itemCount: rows.length,
                          itemBuilder: (context, index) => _row(
                            rows[index],
                            // Поиск скрывает ручки, а неактуальные строки
                            // показывают их недоступными.
                            handle: filter.isEmpty
                                ? TagRowDragHandle(index: index, enabled: false)
                                : const TagRowHiddenHandle(),
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

  Widget _row(
    TagsPanelRow row, {
    required TagRowHandle handle,
    required bool isCurrent,
    TagRowGround? ground,
  }) {
    final tag = row.tag;
    final name = tag.name.value;
    // Меню стоит у строки, поэтому ему нужен её собственный контекст.
    return Builder(
      key: ValueKey('tags-panel-row-${tag.id.toCanonicalString()}'),
      builder: (context) => TagRow(
        name: name,
        color: tagColorPresentation(tag.color),
        mark: row.isMarked
            ? TagRowSelectionMark.checked
            : TagRowSelectionMark.none,
        label: name,
        handle: handle,
        ground:
            ground ??
            (tag.id == heldTagId ? TagRowGround.held : TagRowGround.none),
        // Отказ принадлежит общей поверхности, а нажатие во время изменения
        // назначений намерения координатор отклоняет без сообщения.
        onPressed: isCurrent ? () => model.toggle(tag.id) : null,
        menu: isCurrent ? menuOf(context, tag) : null,
      ),
    );
  }
}

enum _TagAction { edit, duplicate, delete }

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
