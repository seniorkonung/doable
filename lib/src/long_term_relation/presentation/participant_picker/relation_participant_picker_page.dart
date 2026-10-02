import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/routing/app_router.gr.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../intention/application/intention_catalog.dart';
import '../../../intention/domain/intention_id.dart';
import '../../../intention/presentation/catalog/intention_catalog_purpose.dart';
import '../../../intention/presentation/catalog/intention_catalog_state.dart';
import '../../../intention/presentation/catalog/intention_catalog_view_model.dart';
import '../../../intention/presentation/catalog/intention_search_layout.dart';
import '../../../intention/presentation/catalog/intention_search_results.dart';
import '../../../intention/presentation/catalog/intention_tag_conditions_section.dart';
import '../../../intention/presentation/intention_summary_view.dart';
import '../../application/long_term_relation_projection.dart';

/// Выбор существующего намерения участником долговременной связи.
///
/// Страница не заводит собственного источника списка: она читает тот же
/// каталог намерений ограниченными порциями с буквальным фильтром названия
/// и условиями по тегам. Строки показывают собственные теги намерений.
/// Второе намерение пары исключается по идентификатору, а одноимённые
/// намерения остаются отдельными строками с доступом к подробным данным.
/// Выбор возвращает типизированную ссылку с идентификатором и снимком
/// уже загруженной строки. Отмена не возвращает ничего и не создаёт намерений.
@RoutePage()
final class RelationParticipantPickerPage extends ConsumerStatefulWidget {
  const RelationParticipantPickerPage({
    required this.excludedIntentionId,
    required this.selectionContext,
    super.key,
  });

  /// Намерение, уже занятое вторым участником пары.
  final IntentionId excludedIntentionId;

  /// Архивное состояние редактируемой связи, выраженное допустимым охватом.
  final RelationParticipantSelectionContext selectionContext;

  @override
  ConsumerState<RelationParticipantPickerPage> createState() =>
      _RelationParticipantPickerPageState();
}

final class _RelationParticipantPickerPageState
    extends ConsumerState<RelationParticipantPickerPage> {
  final _filterController = TextEditingController();

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final purpose = SelectRelationParticipant(
      excludedIntentionId: widget.excludedIntentionId,
      selectionContext: widget.selectionContext,
    );
    final catalog = ref.watch(intentionCatalogViewModelProvider(purpose));
    final notifier = ref.read(
      intentionCatalogViewModelProvider(purpose).notifier,
    );
    final selection = catalog.value?.selection ?? notifier.selection;
    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.participantPickerTitle),
        leading: IconButton(
          key: const ValueKey('participant-picker-cancel'),
          icon: const Icon(Icons.close),
          tooltip: localizations.participantPickerCancel,
          onPressed: _cancel,
        ),
      ),
      body: SafeArea(
        child: IntentionSearchLayout(
          controls: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  key: const ValueKey('participant-picker-filter-field'),
                  controller: _filterController,
                  decoration: InputDecoration(
                    labelText: localizations.catalogFilterLabel,
                    errorText: _filterError(localizations, selection),
                  ),
                  onChanged: notifier.changeTitleFilter,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: IntentionTagConditionsSection(purpose: purpose),
                ),
              ),
            ],
          ),
          results: IntentionSearchResults(
            purpose: purpose,
            catalog: _withoutOccupiedResults(catalog),
            listKey: const PageStorageKey<String>('participant-picker-list'),
            messages: IntentionSearchResultsMessages(
              loading: localizations.catalogLoading,
              unavailable: localizations.catalogUnavailable,
              corruption: localizations.catalogCorruption,
              unexpected: localizations.catalogUnexpectedFailure,
            ),
            // Условия по тегам сужают охват: пустая выдача при них не
            // означает, что других намерений для выбора нет.
            emptyMessage: (empty) =>
                empty.query.tagFilter != IntentionTagFilter.empty
                ? localizations.catalogTagConditionsEmpty
                : localizations.participantPickerEmpty,
            // Второй участник пары остаётся строкой каталога без высоты:
            // позиции остальных строк в загруженной части не смещаются, и
            // продолжение каталога запрашивается по ним же.
            itemBuilder: (context, results, summary) =>
                summary.id == widget.excludedIntentionId
                ? const SizedBox.shrink()
                : _ParticipantOptionTile(
                    summary: summary,
                    revision: results.revision,
                    onSelected: _select,
                  ),
          ),
        ),
      ),
    );
  }

  /// Выдача, целиком занятая вторым участником пары, для выбора пуста.
  ///
  /// Пока у каталога есть продолжение, выдача остаётся загруженной: оно
  /// остаётся единственным источником следующих доступных строк.
  AsyncValue<IntentionCatalogState> _withoutOccupiedResults(
    AsyncValue<IntentionCatalogState> catalog,
  ) {
    final state = catalog.value;
    if (catalog is! AsyncData<IntentionCatalogState> ||
        catalog.isLoading ||
        state is! IntentionCatalogLoaded ||
        state.nextCursor != null ||
        state.continuation is! IntentionCatalogContinuationIdle ||
        state.items.any((item) => item.id != widget.excludedIntentionId)) {
      return catalog;
    }
    return AsyncData(
      IntentionCatalogEmpty(
        selection: state.selection,
        query: state.query,
        revision: state.revision,
        refresh: state.refresh,
      ),
    );
  }

  void _cancel() {
    unawaited(context.router.maybePop());
  }

  void _select(GraphSnapshot<RelationParticipantSummary> participant) {
    unawaited(context.router.maybePop(participant));
  }

  String? _filterError(
    AppLocalizations localizations,
    IntentionCatalogSelection selection,
  ) => switch (selection.filterValidationFailure) {
    IntentionCatalogFilterValidationFailure.invalidUnicodeRepertoire =>
      localizations.catalogFilterInvalidUnicode,
    IntentionCatalogFilterValidationFailure.tooLong =>
      localizations.catalogFilterTooLong,
    null => null,
  };
}

/// Одна доступная для выбора строка.
///
/// Выбор и переход к подробным данным остаются отдельными действиями с
/// собственной семантикой: подробные данные различают одноимённые намерения,
/// а участником становится только явно выбранное.
final class _ParticipantOptionTile extends StatelessWidget {
  const _ParticipantOptionTile({
    required this.summary,
    required this.revision,
    required this.onSelected,
  });

  final IntentionSummary summary;
  final GraphRevision revision;
  final ValueChanged<GraphSnapshot<RelationParticipantSummary>> onSelected;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: IntentionSummaryView(
            title: summary.title,
            archiveState: summary.archiveState,
            showArchiveState: true,
            confirmedTags: summary.tags,
            confirmedFavoriteMark: summary.favoriteMark,
            activeRelationCount: ConfirmedActiveRelationCount(
              summary.activeRelationCount,
            ),
            onTap: () => onSelected(
              GraphSnapshot(
                revision: revision,
                value: RelationParticipantSummary(
                  id: summary.id,
                  title: summary.title,
                  archiveState: summary.archiveState,
                  activeRelationCount: summary.activeRelationCount,
                ),
              ),
            ),
            tapHint: localizations.participantPickerSelectHint,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.info_outline),
          tooltip: localizations.participantPickerOpenDetails,
          onPressed: () {
            unawaited(
              context.router.push(
                IntentionDetailsRoute(intentionId: summary.id),
              ),
            );
          },
        ),
      ],
    );
  }
}
