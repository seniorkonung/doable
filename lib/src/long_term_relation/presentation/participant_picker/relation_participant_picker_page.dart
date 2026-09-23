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
import '../../../intention/presentation/catalog/intention_catalog_status_views.dart';
import '../../../intention/presentation/catalog/intention_catalog_view_model.dart';
import '../../../intention/presentation/intention_summary_view.dart';
import '../../application/long_term_relation_projection.dart';

/// Выбор существующего намерения участником долговременной связи.
///
/// Страница не заводит собственного источника списка: она читает тот же
/// каталог намерений ограниченными порциями с буквальным фильтром названия.
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
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _filterController.dispose();
    _scrollController.dispose();
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
        child: Column(
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
                onChanged: (value) {
                  _scrollToTop();
                  notifier.changeTitleFilter(value);
                },
              ),
            ),
            Expanded(
              child: catalog.when(
                skipLoadingOnReload: false,
                skipLoadingOnRefresh: false,
                data: (state) => _PickerContent(
                  purpose: purpose,
                  state: state,
                  scrollController: _scrollController,
                  onSelected: _select,
                ),
                error: (_, _) => IntentionCatalogStatusView(
                  message: localizations.catalogUnexpectedFailure,
                ),
                loading: () => IntentionCatalogStatusView(
                  message: localizations.catalogLoading,
                  progressIndicator: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
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

final class _PickerContent extends ConsumerWidget {
  const _PickerContent({
    required this.purpose,
    required this.state,
    required this.scrollController,
    required this.onSelected,
  });

  final SelectRelationParticipant purpose;
  final IntentionCatalogState state;
  final ScrollController scrollController;
  final ValueChanged<GraphSnapshot<RelationParticipantSummary>> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    return switch (state) {
      IntentionCatalogDebouncing() => IntentionCatalogStatusView(
        message: localizations.catalogLoading,
        progressIndicator: true,
      ),
      IntentionCatalogInvalidFilter() => const SizedBox.shrink(),
      final IntentionCatalogLoaded loaded => _PickerOptions(
        purpose: purpose,
        state: loaded,
        scrollController: scrollController,
        onSelected: onSelected,
      ),
      IntentionCatalogEmpty() => IntentionCatalogStatusView(
        message: localizations.participantPickerEmpty,
      ),
      IntentionCatalogUnavailable() => IntentionCatalogStatusView(
        message: localizations.catalogUnavailable,
        retryLabel: localizations.commonRetry,
        onRetry: () {
          unawaited(
            ref
                .read(intentionCatalogViewModelProvider(purpose).notifier)
                .retry(),
          );
        },
      ),
      IntentionCatalogCorruption() => IntentionCatalogStatusView(
        message: localizations.catalogCorruption,
      ),
      IntentionCatalogUnexpected() => IntentionCatalogStatusView(
        message: localizations.catalogUnexpectedFailure,
      ),
    };
  }
}

/// Доступные для выбора строки уже загруженной части каталога.
///
/// Исключение второго участника не меняет ни запрос, ни порядок порций:
/// подгрузка продолжает тот же каталог по его собственным позициям.
final class _PickerOptions extends ConsumerWidget {
  const _PickerOptions({
    required this.purpose,
    required this.state,
    required this.scrollController,
    required this.onSelected,
  });

  final SelectRelationParticipant purpose;
  final IntentionCatalogLoaded state;
  final ScrollController scrollController;
  final ValueChanged<GraphSnapshot<RelationParticipantSummary>> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final options = <_ParticipantOption>[];
    for (var index = 0; index < state.items.length; index++) {
      final summary = state.items[index];
      if (summary.id == purpose.excludedIntentionId) {
        continue;
      }
      options.add(_ParticipantOption(catalogIndex: index, summary: summary));
    }

    final hasContinuationStatus =
        state.continuation is! IntentionCatalogContinuationIdle;
    if (options.isEmpty && !hasContinuationStatus) {
      if (state.nextCursor == null) {
        return IntentionCatalogStatusView(
          message: localizations.participantPickerEmpty,
        );
      }
      // Вся загруженная часть занята вторым участником: продолжение каталога
      // остаётся единственным источником следующих доступных строк.
      _requestNextPage(context, ref, state.items.length - 1);
      return IntentionCatalogStatusView(
        message: localizations.catalogLoadingMore,
        progressIndicator: true,
      );
    }

    return ListView.builder(
      key: const PageStorageKey<String>('participant-picker-list'),
      controller: scrollController,
      itemCount: options.length + (hasContinuationStatus ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == options.length) {
          return IntentionCatalogContinuationStatusView(
            purpose: purpose,
            continuation: state.continuation,
          );
        }
        final option = options[index];
        _requestNextPage(context, ref, option.catalogIndex);
        return _ParticipantOptionTile(
          summary: option.summary,
          revision: state.revision,
          onSelected: onSelected,
        );
      },
    );
  }

  void _requestNextPage(BuildContext context, WidgetRef ref, int visibleIndex) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) {
        return;
      }
      unawaited(
        ref
            .read(intentionCatalogViewModelProvider(purpose).notifier)
            .loadNextPageIfNeeded(visibleIndex: visibleIndex),
      );
    });
  }
}

final class _ParticipantOption {
  const _ParticipantOption({required this.catalogIndex, required this.summary});

  /// Позиция строки в загруженной части каталога, а не в списке выбора.
  final int catalogIndex;
  final IntentionSummary summary;
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
