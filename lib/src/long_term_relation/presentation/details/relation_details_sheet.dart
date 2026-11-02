import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart' hide TextField;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/routing/app_router.gr.dart';
import '../../../daily_choice/presentation/catalog/daily_choice_local_date_provider.dart';
import '../../../design_system/components/list_state.dart';
import '../../../design_system/components/priority_picker.dart';
import '../../../design_system/components/relation_head.dart';
import '../../../design_system/components/sheet.dart';
import '../../../design_system/components/text_field.dart';
import '../../../design_system/doable_colors.dart';
import '../../../design_system/doable_metrics.dart';
import '../../../design_system/doable_type.dart';
import '../../../intention/domain/intention.dart';
import '../../../shared/presentation/timestamp_dates_line.dart';
import '../../application/long_term_relation_projection.dart';
import '../../domain/long_term_relation.dart';
import '../../domain/long_term_relation_id.dart';
import 'relation_details_state.dart';
import 'relation_details_view_model.dart';

/// Показывает подробный просмотр связи панелью над текущей страницей.
///
/// Шапка всегда сохраняет исходное направление связи, поэтому вход из входящей
/// группы её не переворачивает. Название участника открывает его страницу
/// поверх панели, а панель остаётся ниже в истории.
Future<void> showRelationDetailsSheet(
  BuildContext context,
  LongTermRelationId relationId,
) => showDoableSheet<void>(
  context: context,
  hostsMessages: true,
  builder: (_, presentation) =>
      _RelationDetailsSheet(presentation, relationId: relationId),
);

final class _RelationDetailsSheet extends ConsumerWidget {
  const _RelationDetailsSheet(this.presentation, {required this.relationId});

  final SheetPresentation presentation;
  final LongTermRelationId relationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final provider = relationDetailsViewModelProvider(relationId);
    final state = ref.watch(provider);
    final viewModel = ref.read(provider.notifier);
    final retry = (
      label: localizations.commonRetry,
      onPressed: viewModel.retry,
    );
    return Sheet.untitled(
      presentation,
      label: switch (state) {
        RelationDetailsLoaded(:final details) => _sheetLabel(
          localizations,
          details,
        ),
        _ => localizations.relationDetailsTitle,
      },
      // Шапка стоит глубже поля листа: область нажатия кнопки параметров
      // выходит за край содержимого.
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: DoableMetrics.space2),
        child: switch (state) {
          RelationDetailsLoading() => ListState.loading(
            text: localizations.relationDetailsLoading,
          ),
          final RelationDetailsLoaded loaded => _LoadedRelation(
            state: loaded,
            onRetry: viewModel.retry,
          ),
          RelationDetailsNotFound() || RelationDetailsDeleted() =>
            ListState.error(message: localizations.relationDetailsNotFound),
          RelationDetailsUnavailable() => ListState.error(
            message: localizations.relationDetailsUnavailable,
            retry: retry,
          ),
          RelationDetailsCorruption() => ListState.error(
            message: localizations.relationDetailsCorruption,
          ),
          RelationDetailsUnexpected() => ListState.error(
            message: localizations.relationDetailsUnexpected,
          ),
        },
      ),
    );
  }
}

/// Полная формулировка связи в исходном направлении.
String _sheetLabel(
  AppLocalizations localizations,
  LongTermRelationDetails details,
) {
  final phrase = switch (details.relation.type) {
    LongTermRelationType.need => localizations.relationNeighborhoodNeedPhrase(
      details.source.title,
      details.related.title,
    ),
    LongTermRelationType.can => localizations.relationNeighborhoodCanPhrase(
      details.source.title,
      details.related.title,
    ),
  };
  return switch (details.relation.scope) {
    RelationScope.active => phrase,
    RelationScope.archived => localizations.relationSheetArchivedLabel(phrase),
  };
}

final class _LoadedRelation extends ConsumerWidget {
  const _LoadedRelation({required this.state, required this.onRetry});

  final RelationDetailsLoaded state;
  final VoidCallback onRetry;

  /// Последняя пилюля приоритета выходит за край содержимого.
  static const double _pickerShift = 2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<DoableColors>()!;
    final details = state.details;
    final relation = details.relation;
    final description = details.description?.value;
    // Обычное обновление длится мгновения и не сдвигает панель строкой
    // статуса при каждой подтверждённой правке: виден только его отказ.
    final refreshFailure = switch (state.refreshStatus) {
      RelationDetailsFresh() || RelationDetailsRefreshing() => null,
      RelationDetailsRefreshUnavailable() =>
        localizations.relationDetailsRefreshUnavailable,
      RelationDetailsRefreshCorruption() =>
        localizations.relationDetailsRefreshCorruption,
      RelationDetailsRefreshUnexpected() =>
        localizations.relationDetailsRefreshUnexpected,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (refreshFailure != null) ...[
          ListState.error(
            message: refreshFailure,
            retry: state.canRetry
                ? (label: localizations.commonRetry, onPressed: onRetry)
                : null,
          ),
          const SizedBox(height: DoableMetrics.space3),
        ],
        RelationHead(
          kind: switch (relation.type) {
            LongTermRelationType.need => RelationHeadKind.need,
            LongTermRelationType.can => RelationHeadKind.can,
          },
          priority: _designPriority(relation.priority),
          source: _participant(context, details.source),
          target: _participant(context, details.related),
          status: switch (relation.scope) {
            RelationScope.active => const RelationHeadActive(),
            RelationScope.archived => RelationHeadArchived(
              note: localizations.relationSheetArchivedNote,
            ),
          },
          kindName: (kind) => switch (kind) {
            RelationHeadKind.need => localizations.relationNeighborhoodTypeNeed,
            RelationHeadKind.can => localizations.relationNeighborhoodTypeCan,
          },
          archivedWord: localizations.detailsArchivedBadge,
        ),
        const SizedBox(height: 10),
        TextField.saved(
          value: description ?? '',
          placeholder: localizations.detailsAddDescription,
          label: switch (description) {
            final description? => localizations.detailsEditDescriptionLabel(
              description,
            ),
            null => localizations.detailsAddDescription,
          },
          onOpen: null,
        ),
        const SizedBox(height: DoableMetrics.space2),
        // Без места на одной строке приоритет переносится целиком, а слово
        // не ломается.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: DoableMetrics.space3,
          children: [
            Text(
              localizations.relationDetailsPriorityLabel,
              style: DoableType.row.copyWith(color: colors.ink),
            ),
            Transform.translate(
              offset: const Offset(_pickerShift, 0),
              child: PriorityPicker(
                value: _designPriority(relation.priority),
                onChange: null,
                label: localizations.relationDetailsPriorityLabel,
                name: _priorityName,
                itemLabel: (priority, _) =>
                    _priorityItemLabel(localizations, priority),
              ),
            ),
          ],
        ),
        const SizedBox(height: DoableMetrics.space2),
        timestampDatesLine(
          localizations: localizations,
          locale: Localizations.localeOf(context).toLanguageTag(),
          createdAt: relation.createdAt.value,
          updatedAt: relation.updatedAt.value,
          // Строка называет год по дню показа панели.
          currentYear: ref
              .watch(dailyChoiceLocalDateSourceProvider)()
              .date
              .year,
        ),
      ],
    );
  }

  RelationHeadParticipant _participant(
    BuildContext context,
    RelationParticipantSummary participant,
  ) {
    final localizations = AppLocalizations.of(context);
    final archived = participant.archiveState == IntentionArchiveState.archived;
    return RelationHeadParticipant(
      name: participant.title,
      semanticLabel: archived
          ? localizations.relationSheetOpenArchivedParticipant(
              participant.title,
            )
          : localizations.relationSheetOpenParticipant(participant.title),
      archived: archived,
      onOpen: () => unawaited(
        context.router.push(IntentionDetailsRoute(intentionId: participant.id)),
      ),
    );
  }
}

DoablePriority _designPriority(RelationPriority priority) => switch (priority) {
  RelationPriority.p1 => DoablePriority.p1,
  RelationPriority.p2 => DoablePriority.p2,
  RelationPriority.p3 => DoablePriority.p3,
  RelationPriority.p4 => DoablePriority.p4,
};

String _priorityName(DoablePriority priority) => switch (priority) {
  DoablePriority.p1 => 'P1',
  DoablePriority.p2 => 'P2',
  DoablePriority.p3 => 'P3',
  DoablePriority.p4 => 'P4',
};

/// Диктор слышит порядок приоритетов: выбранную пилюлю объявляет её состояние.
String _priorityItemLabel(
  AppLocalizations localizations,
  DoablePriority priority,
) {
  final name = _priorityName(priority);
  return switch (priority) {
    DoablePriority.p1 => localizations.relationSheetPriorityHighest(name),
    DoablePriority.p2 ||
    DoablePriority.p3 => localizations.relationNeighborhoodPriority(name),
    DoablePriority.p4 => localizations.relationSheetPriorityLowest(name),
  };
}
