import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/routing/app_router.gr.dart';
import '../../../design_system/components/confirm_dialog.dart';
import '../../../design_system/components/list_state.dart';
import '../../../design_system/components/notice.dart';
import '../../../design_system/components/path_builder.dart';
import '../../../design_system/components/step_option.dart';
import '../../../design_system/components/tabs.dart';
import '../../../design_system/components/top_bar.dart';
import '../../../design_system/doable_metrics.dart';
import '../../../design_system/doable_priority.dart';
import '../../../intention/domain/intention_id.dart';
import '../../../long_term_relation/domain/long_term_relation.dart';
import '../../../graph/presentation/operation_failure_presentation.dart';
import '../../../long_term_relation/presentation/details/relation_details_sheet.dart';
import '../../application/path_candidates.dart';
import '../../domain/action_path.dart';
import '../../domain/action_priority.dart';
import '../action_command_failure_message.dart';
import '../panel/action_field_labels.dart';
import '../path_start/path_start_picker_page.dart';
import 'path_state.dart';
import 'path_view_model.dart';

/// Экран пути — страница-задача без панели навигации (ADR-0059).
///
/// Путь на экране меняется только здесь: смена корня в поиске начала пути и
/// сокращение нажатием на промежуточное намерение граф не меняют.
/// «Сохранить» возвращает путь вызывающему, а уход без сохранения — `null`.
/// Изменённый путь закрывается только после ответа «Отменить».
///
/// Путь существующего действия «Сохранить» заменяет сама и закрывает экран
/// только после подтверждённой замены; отказ остаётся на экране. Пока замена
/// выполняется, путь на экране не меняется, а уход закрывает экран без
/// вопроса и без результата (ADR-0059).
@RoutePage()
final class PathPage extends ConsumerStatefulWidget {
  const PathPage({
    required this.purpose,
    required this.actionTitle,
    required this.actionPriority,
    super.key,
  });

  /// Откуда открыт экран: лист нового действия или панель действия.
  final PathPurpose purpose;

  /// Название действия, как оно стоит в листе или на панели.
  final String actionTitle;
  final ActionPriority actionPriority;

  @override
  ConsumerState<PathPage> createState() => _PathPageState();
}

final class _PathPageState extends ConsumerState<PathPage> {
  final _sessionKey = PathSessionKey();

  PathViewModelProvider get _provider =>
      pathViewModelProvider(_sessionKey, widget.purpose);

  PathStartFlow get _flow => switch (widget.purpose) {
    NewActionPathPurpose() => PathStartFlow.newAction,
    ExistingActionPathPurpose() => PathStartFlow.editPath,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final path = ref.watch(_provider);
    final model = ref.read(_provider.notifier);
    return PopScope<ActionPath>(
      canPop: path.closeDecision == PathCloseDecision.close,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_askDiscard());
      },
      child: Scaffold(
        appBar: TopBar.withButton(
          context,
          title: switch (_flow) {
            PathStartFlow.newAction => l10n.pathTitle,
            PathStartFlow.editPath => l10n.pathEditTitle,
          },
          backLabel: MaterialLocalizations.of(context).backButtonTooltip,
          onBack: () => unawaited(context.router.maybePop()),
          buttonLabel: l10n.pathSave,
          onButtonPressed: path.canSave ? () => unawaited(_save()) : null,
        ),
        body: SafeArea(
          top: false,
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification.metrics.axis == Axis.vertical &&
                  notification.metrics.extentAfter < 200) {
                unawaited(model.loadMore());
              }
              return false;
            },
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                DoableMetrics.space5,
                DoableMetrics.space2,
                DoableMetrics.space5,
                DoableMetrics.space5,
              ),
              // Пока замена выполняется, путь на экране не меняется и поверх
              // экрана ничего не открывается: успех закрывает именно его.
              child: IgnorePointer(
                ignoring: path.saving is PathSavingRunning,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (path.saving case final PathSavingFailed failed) ...[
                      Notice.content(
                        message: OperationFailurePresentation(
                          claim: failed.presentation,
                          message: actionCommandFailureMessage(
                            l10n,
                            failed.failure,
                          ),
                          inheritsColor: true,
                        ),
                      ),
                      const SizedBox(height: DoableMetrics.space3),
                    ],
                    _draft(l10n, model, path),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _draft(AppLocalizations l10n, PathViewModel model, PathState path) =>
      switch (path.draft) {
        LoadingPathDraft() => ListState.loading(text: l10n.pathLoading),
        final FailedPathDraft failed => ListState.error(
          message: _failureMessage(l10n, failed.failure),
          retry: failed.canRetry
              ? (
                  label: l10n.commonRetry,
                  onPressed: () => unawaited(model.retry()),
                )
              : null,
        ),
        EmptyPathDraft() => _builder(l10n, model, const [], null, null),
        final LoadedPathDraft loaded => _builder(
          l10n,
          model,
          loaded.intentions,
          loaded.segment,
          path.candidates,
          appended: loaded.appended,
        ),
      };

  Widget _builder(
    AppLocalizations l10n,
    PathViewModel model,
    List<IntentionId> ids,
    PathSegment? segment,
    CandidateState? candidates, {
    PathCandidate? appended,
  }) {
    final steps = segment == null
        ? const <PathBuilderStep>[]
        : _steps(l10n, segment, appended);
    return PathBuilder(
      steps: steps,
      priority: actionDesignPriority(widget.actionPriority),
      actionName: widget.actionTitle,
      actionLabel: widget.actionTitle.isEmpty
          ? l10n.pathNewActionLabel
          : l10n.pathActionLabel(widget.actionTitle),
      emptyActionText: l10n.pathNewAction,
      slotText: l10n.pathChooseReason,
      slotLabel: l10n.pathChooseReasonLabel,
      onChooseRoot: () => unawaited(_chooseRoot(ids.firstOrNull)),
      onStep: (key) =>
          model.endAt(ids.firstWhere((id) => id.toCanonicalString() == key)),
      hint: switch (steps.length) {
        0 => l10n.pathEmptyHint,
        1 => '',
        _ => l10n.pathShortenHint,
      },
      switcher: candidates != null && candidates.counts != null
          ? Tabs<LongTermRelationType>.toggle(
              items: [
                TabItem(
                  id: LongTermRelationType.need,
                  label: l10n.relationNeighborhoodTypeNeed,
                  semanticLabel:
                      '${l10n.relationNeighborhoodTypeNeed}: ${candidates.counts!.need}',
                  count: candidates.counts!.need,
                ),
                TabItem(
                  id: LongTermRelationType.can,
                  label: l10n.relationNeighborhoodTypeCan,
                  semanticLabel:
                      '${l10n.relationNeighborhoodTypeCan}: ${candidates.counts!.can}',
                  count: candidates.counts!.can,
                ),
              ],
              value: candidates.half,
              onChange: model.selectHalf,
              label: l10n.pathNextIntention,
              minWidth: 0,
            )
          : const SizedBox.shrink(),
      emptyHalf:
          candidates != null &&
              candidates.counts != null &&
              candidates.items.isEmpty &&
              !candidates.loading &&
              candidates.failure == null
          ? candidates.half == LongTermRelationType.need
                ? (title: l10n.pathNeedEmptyTitle, text: l10n.pathNeedEmptyText)
                : (title: l10n.pathCanEmptyTitle, text: l10n.pathCanEmptyText)
          : null,
      addText: l10n.pathAdd,
      addLabel: l10n.pathAdd,
      onAdd: () {},
      children: [
        if (candidates != null) ...[
          for (final candidate in candidates.items)
            StepOption(
              name: candidate.title,
              priority: _designPriority(candidate.relation.priority),
              label: l10n.pathCandidateLabel(
                candidate.title,
                l10n.actionPriorityOption(
                  actionPriorityName(
                    _designPriority(candidate.relation.priority),
                  ),
                ),
              ),
              openLabel: l10n.intentionPickerOpenIntentionPage(candidate.title),
              onPick: () => model.selectCandidate(candidate),
              onOpen: () => unawaited(
                context.router.push(
                  IntentionDetailsRoute(
                    intentionId: candidate.relation.relatedIntentionId,
                  ),
                ),
              ),
            ),
          if (candidates.loading)
            ListState.loading(text: l10n.pathCandidatesLoading),
          if (candidates.failure case final failure?)
            ListState.error(
              message: failure is PathCandidatesUnavailableFailure
                  ? l10n.pathCandidatesUnavailable
                  : _failureMessage(l10n, failure),
              retry: failure is PathCandidatesUnavailableFailure
                  ? (
                      label: l10n.commonRetry,
                      onPressed: () => unawaited(model.retry()),
                    )
                  : null,
            ),
        ],
      ],
    );
  }

  List<PathBuilderStep> _steps(
    AppLocalizations l10n,
    PathSegment segment,
    PathCandidate? appended,
  ) {
    final last = segment.steps.length + (appended == null ? 0 : 1);
    PathBuilderStep step(
      IntentionId id,
      String title,
      int index, [
      PathBuilderRelation? relation,
    ]) {
      return PathBuilderStep(
        id: id.toCanonicalString(),
        name: title,
        label: switch (index) {
          0 => l10n.pathRootLabel(title),
          _ when index == last => l10n.pathFinalLabel(title),
          _ => l10n.pathEndAtLabel(title),
        },
        openLabel: l10n.intentionPickerOpenIntentionPage(title),
        onOpen: () => unawaited(
          context.router.push(IntentionDetailsRoute(intentionId: id)),
        ),
        relation: relation,
      );
    }

    return [
      step(segment.root.id, segment.root.title, 0),
      for (final (index, item) in segment.steps.indexed)
        step(
          item.intention.id,
          item.intention.title,
          index + 1,
          _relation(
            l10n,
            item.relation,
            source: index == 0
                ? segment.root.title
                : segment.steps[index - 1].intention.title,
            related: item.intention.title,
          ),
        ),
      if (appended != null)
        step(
          appended.relation.relatedIntentionId,
          appended.title,
          last,
          _relation(
            l10n,
            appended.relation,
            source: segment.last.title,
            related: appended.title,
          ),
        ),
    ];
  }

  PathBuilderRelation _relation(
    AppLocalizations l10n,
    LongTermRelation relation, {
    required String source,
    required String related,
  }) {
    final (kind, word) = switch (relation.type) {
      LongTermRelationType.need => (
        PathBuilderRelationKind.need,
        l10n.relationNeighborhoodTypeNeed,
      ),
      LongTermRelationType.can => (
        PathBuilderRelationKind.can,
        l10n.relationNeighborhoodTypeCan,
      ),
    };
    final priority = switch (relation.priority) {
      RelationPriority.p1 => DoablePriority.p1,
      RelationPriority.p2 => DoablePriority.p2,
      RelationPriority.p3 => DoablePriority.p3,
      RelationPriority.p4 => DoablePriority.p4,
    };
    return PathBuilderRelation(
      kind: kind,
      priority: priority,
      word: word,
      label: l10n.actionPathRelationLabel(
        word,
        source,
        related,
        l10n.actionPriorityOption(actionPriorityName(priority)),
      ),
      onOpen: () => unawaited(showRelationDetailsSheet(context, relation.id)),
    );
  }

  /// Выбор в поиске начала пути заменяет весь путь одним корнем, а закрытие
  /// без выбора путь не меняет.
  Future<void> _chooseRoot(IntentionId? currentRoot) async {
    final root = await context.router.push<IntentionId>(
      PathStartPickerRoute(flow: _flow, currentRoot: currentRoot),
    );
    if (mounted && root != null) {
      ref.read(_provider.notifier).selectRoot(root);
    }
  }

  /// Экран, с которого ушли до исхода замены, ничего не закрывает.
  Future<void> _save() async {
    final saved = await ref.read(_provider.notifier).save();
    if (saved != null && mounted) context.router.pop(saved);
  }

  Future<void> _askDiscard() async {
    if (ref.read(_provider.notifier).requestClose() ==
        PathCloseDecision.close) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final discarded = await showDiscardDialog(
      context: context,
      title: l10n.pathDiscardTitle,
      text: l10n.pathDiscardMessage,
      discardLabel: l10n.pathDiscardAction,
      keepLabel: l10n.pathContinueAction,
    );
    if (discarded && mounted) context.router.pop();
  }
}

String _failureMessage(
  AppLocalizations l10n,
  PathCandidatesReadFailure failure,
) => switch (failure) {
  PathCandidatesUnavailableFailure() => l10n.pathReadUnavailable,
  PathCandidatesCorruptionFailure() => l10n.pathReadCorruption,
  // Первое чтение не привязано к ревизии и устареть не может.
  PathCandidatesSnapshotExpired() ||
  PathCandidatesUnexpectedFailure() => l10n.pathReadUnexpected,
};

DoablePriority _designPriority(RelationPriority priority) => switch (priority) {
  RelationPriority.p1 => DoablePriority.p1,
  RelationPriority.p2 => DoablePriority.p2,
  RelationPriority.p3 => DoablePriority.p3,
  RelationPriority.p4 => DoablePriority.p4,
};
