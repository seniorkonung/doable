import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/routing/app_router.gr.dart';
import '../../../design_system/components/confirm_dialog.dart';
import '../../../design_system/components/list_state.dart';
import '../../../design_system/components/path_builder.dart';
import '../../../design_system/components/top_bar.dart';
import '../../../design_system/doable_metrics.dart';
import '../../../design_system/doable_priority.dart';
import '../../../intention/domain/intention_id.dart';
import '../../../long_term_relation/domain/long_term_relation.dart';
import '../../../long_term_relation/presentation/details/relation_details_sheet.dart';
import '../../application/path_candidates.dart';
import '../../domain/action_path.dart';
import '../../domain/action_priority.dart';
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
@RoutePage()
final class PathPage extends ConsumerStatefulWidget {
  const PathPage({
    required this.flow,
    required this.originalPath,
    required this.actionTitle,
    required this.actionPriority,
    super.key,
  });

  /// Откуда открыт экран: лист нового действия или панель действия.
  final PathStartFlow flow;

  /// Исходный путь; `null`, пока путь нового действия не выбран.
  final ActionPath? originalPath;

  /// Название действия, как оно стоит в листе или на панели.
  final String actionTitle;
  final ActionPriority actionPriority;

  @override
  ConsumerState<PathPage> createState() => _PathPageState();
}

final class _PathPageState extends ConsumerState<PathPage> {
  final _sessionKey = PathSessionKey();

  PathViewModelProvider get _provider =>
      pathViewModelProvider(_sessionKey, widget.originalPath);

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
          title: switch (widget.flow) {
            PathStartFlow.newAction => l10n.pathTitle,
            PathStartFlow.editPath => l10n.pathEditTitle,
          },
          backLabel: MaterialLocalizations.of(context).backButtonTooltip,
          onBack: () => unawaited(context.router.maybePop()),
          buttonLabel: l10n.pathSave,
          onButtonPressed: path.canSave ? _save : null,
        ),
        body: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              DoableMetrics.space5,
              DoableMetrics.space2,
              DoableMetrics.space5,
              DoableMetrics.space5,
            ),
            child: switch (path.draft) {
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
              EmptyPathDraft() => _builder(l10n, model, const [], null),
              final LoadedPathDraft loaded => _builder(
                l10n,
                model,
                loaded.intentions,
                loaded.segment,
              ),
            },
          ),
        ),
      ),
    );
  }

  Widget _builder(
    AppLocalizations l10n,
    PathViewModel model,
    List<IntentionId> ids,
    PathSegment? segment,
  ) {
    final steps = segment == null
        ? const <PathBuilderStep>[]
        : _steps(l10n, segment);
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
      // Переключатель половин и «Добавить» подключают кандидаты следующего
      // намерения и добавление связей экрана.
      switcher: const SizedBox.shrink(),
      addText: l10n.pathAdd,
      addLabel: l10n.pathAdd,
      onAdd: () {},
    );
  }

  List<PathBuilderStep> _steps(AppLocalizations l10n, PathSegment segment) {
    final last = segment.steps.length;
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
      PathStartPickerRoute(flow: widget.flow, currentRoot: currentRoot),
    );
    if (mounted && root != null) {
      ref.read(_provider.notifier).selectRoot(root);
    }
  }

  void _save() {
    final saved = ref.read(_provider.notifier).save();
    if (saved != null) context.router.pop(saved);
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
