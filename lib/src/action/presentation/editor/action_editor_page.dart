import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart' hide Badge, TextField;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/routing/app_router.gr.dart';
import '../../../design_system/components/action_path.dart'
    show ActionPathRelationKind;
import '../../../design_system/components/badge.dart';
import '../../../design_system/components/button.dart';
import '../../../design_system/components/confirm_dialog.dart';
import '../../../design_system/components/notice.dart';
import '../../../design_system/components/path_brief.dart';
import '../../../design_system/components/sheet.dart';
import '../../../design_system/components/text_field.dart';
import '../../../design_system/components/value_chip.dart';
import '../../../design_system/doable_metrics.dart';
import '../../../graph/presentation/operation_failure_presentation.dart';
import '../../../intention/domain/intention.dart';
import '../../../intention/domain/intention_text.dart';
import '../../../long_term_relation/domain/long_term_relation.dart';
import '../../../shared/presentation/local_day/local_date_provider.dart';
import '../../../shared/presentation/local_day/local_day_observer.dart';
import '../../application/action_details.dart';
import '../../domain/action_priority.dart';
import '../../domain/action_path.dart';
import '../action_command_failure_message.dart';
import '../panel/action_date_sheet.dart';
import '../panel/action_field_labels.dart';
import '../panel/action_time_sheet.dart';
import '../path/path_segment.dart';
import '../path/path_state.dart';
import '../path_start/path_start_picker_page.dart';
import 'action_editor_state.dart';
import 'action_editor_view_model.dart';
import 'action_priority_sheet.dart';

/// Маршрут листа нового действия: лист над корневым навигатором, который стек
/// маршрутизатора видит своей страницей. Сообщения общей поверхности, в том
/// числе «Действие создано», появляются над листом.
Route<T> actionEditorRoute<T>(
  BuildContext context,
  Widget child,
  AutoRoutePage<T> page,
) => doableSheetPageRoute<T>(
  context: context,
  page: page,
  child: child,
  hostsMessages: true,
);

/// Лист нового действия: название, описание, свёрнутый путь, дата, время и
/// приоритет одной сессии черновика.
///
/// Создание не закрывает лист: подтверждённое действие очищает название и
/// описание, а остальное остаётся для следующего. Пока команда выполняется,
/// черновик не меняется, а отказ остаётся в листе со всеми полями.
///
/// Смахивание, затемнение и «назад» при введённом тексте спрашивают
/// «Отменить новое действие?», без текста и во время создания закрывают лист
/// сразу, не отменяя команду.
@RoutePage()
final class ActionEditorPage extends ConsumerStatefulWidget {
  const ActionEditorPage({required this.launch, super.key});

  final ActionEditorLaunch launch;

  @override
  ConsumerState<ActionEditorPage> createState() => _ActionEditorPageState();
}

final class _ActionEditorPageState extends ConsumerState<ActionEditorPage> {
  static const _descriptionMinLines = 2;
  static const _descriptionMaxLines = 9;

  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  /// Лист может остаться открытым после местной полуночи, и тогда «Сегодня»
  /// в значении даты стало бы неверным.
  late final LocalDayObserver _localDay;

  /// Вопрос о закрытии уже задан; второй не открывается.
  var _isAskingToClose = false;

  ActionEditorViewModelProvider get _provider =>
      actionEditorViewModelProvider(widget.launch);

  @override
  void initState() {
    super.initState();
    _localDay = LocalDayObserver(
      readLocalDay: ref.read(localDateSourceProvider),
      onTodayChanged: () => setState(() {}),
    );
  }

  @override
  void dispose() {
    _localDay.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  /// Поля показывают тексты черновика: создание очищает их в сессии.
  void _showDraftTexts(ActionEditorDraft draft) {
    if (_titleController.text != draft.title) {
      _titleController.text = draft.title;
    }
    if (_descriptionController.text != draft.description) {
      _descriptionController.text = draft.description;
    }
  }

  Future<void> _confirmClose() async {
    if (_isAskingToClose) return;
    final model = ref.read(_provider.notifier);
    if (model.requestClose() == ActionEditorCloseDecision.close) {
      _removeRoute();
      return;
    }
    _isAskingToClose = true;
    final localizations = AppLocalizations.of(context);
    final discarded = await showDiscardDialog(
      context: context,
      title: localizations.actionEditorDiscardTitle,
      text: localizations.actionEditorDiscardMessage,
      discardLabel: localizations.editorCloseDiscardAction,
      keepLabel: localizations.editorCloseContinueAction,
    );
    _isAskingToClose = false;
    if (!discarded || !mounted) return;
    model.close();
    _removeRoute();
  }

  void _removeRoute() {
    if (mounted) context.router.removeRoute(context.routeData);
  }

  Future<void> _pickDate(ActionEditorDraft draft) async {
    final picked = await showActionDateSheet(context, draft.date);
    if (picked != null && mounted) {
      ref.read(_provider.notifier).changeDate(picked);
    }
  }

  Future<void> _pickSchedule(ActionEditorDraft draft) async {
    final picked = await showActionTimeSheet(context, draft.schedule);
    if (picked != null && mounted) {
      ref.read(_provider.notifier).changeSchedule(picked);
    }
  }

  Future<void> _pickPriority(ActionEditorDraft draft) async {
    final picked = await showActionPrioritySheet(context, draft.priority);
    if (picked != null && mounted) {
      ref.read(_provider.notifier).changePriority(picked);
    }
  }

  Future<void> _pickPath(ActionEditorState state) async {
    final router = context.router;
    final draft = state.draft;
    final path = draft.path;
    PathStartChoice? choice;
    if (path == null) {
      choice = await router.push<PathStartChoice>(
        PathStartPickerRoute(flow: PathStartFlow.newAction),
      );
      if (!mounted || choice == null) return;
    }
    if (!mounted) return;
    void onSaved(LoadedPathDraft loaded) {
      if (!mounted) return;
      final segment = loaded.segment;
      final appended = loaded.appended;
      ref
          .read(_provider.notifier)
          .changePath(
            ActionDraftPath(
              root: ActionDraftIntention(
                id: segment.root.id,
                title: segment.root.title,
              ),
              steps: [
                for (final step in segment.steps)
                  ActionDraftPathStep(
                    relation: step.relation.type,
                    intention: ActionDraftIntention(
                      id: step.intention.id,
                      title: step.intention.title,
                    ),
                  ),
                if (appended != null)
                  ActionDraftPathStep(
                    relation: appended.relation.type,
                    intention: ActionDraftIntention(
                      id: appended.relation.relatedIntentionId,
                      title: appended.title,
                    ),
                  ),
              ],
            ),
          );
    }

    final pathState = state.pathState;
    await router.push<ActionPath>(
      PathRoute(
        purpose: path != null && pathState != null
            ? NewActionPathPurpose.segment(
                path.path,
                start: firstWholeSegment(pathState),
                onSaved: onSaved,
              )
            : NewActionPathPurpose(
                path?.path,
                start: choice == null ? null : ActionPath([choice.intention]),
                createdIntention: choice is PathStartCreated,
                onSaved: onSaved,
              ),
        actionTitle: draft.title,
        actionPriority: draft.priority,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final state = ref.watch(_provider);
    final model = ref.read(_provider.notifier);
    ref.listen(_provider, (_, next) => _showDraftTexts(next.draft));
    final draft = state.draft;
    final editable = state.isEditable;
    final rejected = switch (state.submission) {
      final ActionEditorInputRejected rejected => rejected,
      _ => null,
    };
    final failed = switch (state.submission) {
      final ActionEditorFailed failed => failed,
      _ => null,
    };
    final priority = actionDesignPriority(draft.priority);
    final time = actionTimeValue(context, draft.schedule);
    return PopScope<Object?>(
      canPop: !state.asksOnClose,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          model.close();
        } else {
          unawaited(_confirmClose());
        }
      },
      child: Sheet(
        SheetPresentation.of(context),
        title: localizations.actionEditorTitle,
        footer: Button.primary(
          label: localizations.actionEditorCreate,
          onPressed: state.canSubmit ? model.submit : null,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: DoableMetrics.space2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField.multiline(
                controller: _titleController,
                placeholder: localizations.actionTextEditNameLabel,
                label: localizations.actionTextEditNameLabel,
                kind: TextFieldKind.name,
                autofocus: true,
                readOnly: !editable,
                onChanged: model.changeTitle,
                error: switch (rejected?.title) {
                  IntentionTextValidationReason.empty => Text(
                    localizations.editorTitleEmpty,
                  ),
                  IntentionTextValidationReason.tooLong => Text(
                    localizations.editorTitleTooLong,
                  ),
                  IntentionTextValidationReason.invalidUnicodeRepertoire =>
                    Text(localizations.editorTitleInvalidUnicode),
                  null => null,
                },
              ),
              const SizedBox(height: DoableMetrics.space2),
              TextField.multiline(
                controller: _descriptionController,
                placeholder: localizations.detailsAddDescription,
                label: localizations.actionTextEditDescriptionLabel,
                minLines: _descriptionMinLines,
                maxLines: _descriptionMaxLines,
                readOnly: !editable,
                onChanged: model.changeDescription,
                error: switch (rejected?.description) {
                  IntentionTextValidationReason.tooLong => Text(
                    localizations.editorDescriptionTooLong,
                  ),
                  IntentionTextValidationReason.invalidUnicodeRepertoire =>
                    Text(localizations.editorDescriptionInvalidUnicode),
                  IntentionTextValidationReason.empty => Text(
                    localizations.actionDescriptionInvalid,
                  ),
                  null => null,
                },
              ),
              const SizedBox(height: DoableMetrics.space2),
              _PathBrief(
                path: draft.path,
                pathState: state.pathState,
                priority: draft.priority,
                onPressed: editable ? () => unawaited(_pickPath(state)) : null,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ValueChip.icon(
                    value: actionDateValue(
                      context,
                      draft.date,
                      today: _localDay.today,
                    ),
                    icon: ValueChipIcon.calendar,
                    label: localizations.actionFieldDateLabel(
                      actionFullDate(context, draft.date),
                    ),
                    onPressed: editable
                        ? () => unawaited(_pickDate(draft))
                        : null,
                  ),
                  ValueChip.icon(
                    value: time,
                    icon: ValueChipIcon.clock,
                    label: localizations.actionFieldTimeLabel(time),
                    onPressed: editable
                        ? () => unawaited(_pickSchedule(draft))
                        : null,
                  ),
                  ValueChip.priority(
                    value: actionPriorityName(priority),
                    priority: priority,
                    label: localizations.actionEditorPriorityLabel(
                      actionPriorityName(priority),
                    ),
                    onPressed: editable
                        ? () => unawaited(_pickPriority(draft))
                        : null,
                  ),
                ],
              ),
              if (failed != null) ...[
                const SizedBox(height: DoableMetrics.space2),
                Notice.content(
                  message: OperationFailurePresentation(
                    claim: failed.presentation,
                    message: actionCommandFailureMessage(
                      localizations,
                      failed.failure,
                    ),
                    inheritsColor: true,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Свёрнутый путь черновика и переход к его изменению.
///
/// Прочитанный путь показывает текущие названия и отметки разрывов: после
/// корневого и конечного намерений — их собственные, а разрывы промежуточных
/// намерений и связей — на самом пути.
final class _PathBrief extends StatelessWidget {
  const _PathBrief({
    required this.path,
    required this.pathState,
    required this.priority,
    required this.onPressed,
  });

  final ActionDraftPath? path;
  final ActionSavedPath? pathState;
  final ActionPriority priority;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final steps = _steps();
    final last = steps.length - 1;
    final between = [
      for (var index = 0; index < steps.length; index++) ...[
        if (index > 0) steps[index].link,
        if (index > 0 && index < last) steps[index].intention,
      ],
    ];
    final archivedBetween = between.contains(_PathMark.archived);
    final deletedBetween = between.contains(_PathMark.deleted);
    String named(_BriefStep step) =>
        [step.title, ..._words(localizations, step.intention)].join(', ');
    return PathBrief(
      steps: [
        for (final (index, step) in steps.indexed)
          PathBriefStep(
            name: step.title,
            relation: switch (step.relation) {
              LongTermRelationType.need => ActionPathRelationKind.need,
              LongTermRelationType.can => ActionPathRelationKind.can,
              null => null,
            },
            marks: index == 0 || index == last
                ? [
                    if (step.intention == _PathMark.archived)
                      Badge.archivedInline(word: localizations.detailsArchived),
                    if (step.intention == _PathMark.deleted)
                      Badge.deletedInline(
                        word: localizations.actionPathDeletedBadge,
                      ),
                  ]
                : const [],
          ),
      ],
      marks: [
        if (archivedBetween)
          Badge.archived(word: localizations.detailsArchived),
        if (deletedBetween)
          Badge.deleted(word: localizations.actionPathDeletedBadge),
      ],
      priority: actionDesignPriority(priority),
      emptyText: localizations.pathChooseReason,
      emptyHint: localizations.actionEditorPathEmptyHint,
      // Строку промежуточных намерений лист показывает только при них.
      betweenText: steps.length > 2
          ? localizations.actionEditorPathBetween(steps.length - 2)
          : '',
      label: steps.isEmpty
          ? localizations.pathChooseReasonLabel
          : localizations.actionEditorPathLabel(
              [
                steps
                    .map(named)
                    .reduce(
                      (previous, next) =>
                          localizations.actionEditorPathThen(previous, next),
                    ),
                if (steps
                    .skip(1)
                    .any((step) => step.link == _PathMark.archived))
                  localizations.actionEditorPathLinkArchived,
                if (steps.skip(1).any((step) => step.link == _PathMark.deleted))
                  localizations.actionEditorPathLinkDeleted,
              ].join('. '),
            ),
      onPressed: onPressed,
    );
  }

  /// Шаги пути: прочитанные, а до чтения — как их знает черновик.
  List<_BriefStep> _steps() {
    final state = pathState;
    if (state != null) {
      return [
        _BriefStep(
          title: state.root.title,
          intention: _intentionMark(state.root),
        ),
        for (final step in state.steps)
          _BriefStep(
            title: step.intention.title,
            intention: _intentionMark(step.intention),
            relation: step.link.type,
            link: _linkMark(step.link),
          ),
      ];
    }
    final path = this.path;
    if (path == null) return const [];
    return [
      _BriefStep(title: path.root.title),
      for (final step in path.steps)
        _BriefStep(title: step.intention.title, relation: step.relation),
    ];
  }

  static List<String> _words(AppLocalizations localizations, _PathMark? mark) =>
      switch (mark) {
        _PathMark.archived => [localizations.detailsArchived],
        _PathMark.deleted => [localizations.actionPathDeletedBadge],
        null => const [],
      };
}

/// Разрыв звена или намерения пути.
enum _PathMark { archived, deleted }

_PathMark? _intentionMark(ActionPathIntention intention) => switch (intention) {
  DeletedActionPathIntention() => _PathMark.deleted,
  ExistingActionPathIntention(:final intention) =>
    switch (intention.archiveState) {
      IntentionArchiveState.archived => _PathMark.archived,
      IntentionArchiveState.active => null,
    },
};

_PathMark? _linkMark(ActionPathLink link) => switch (link) {
  DeletedActionPathLink() => _PathMark.deleted,
  ExistingActionPathLink(:final relation) => switch (relation.scope) {
    RelationScope.archived => _PathMark.archived,
    RelationScope.active => null,
  },
};

/// Намерение свёрнутого пути, связь к нему от предыдущего и их разрывы.
final class _BriefStep {
  const _BriefStep({
    required this.title,
    this.intention,
    this.relation,
    this.link,
  });

  final String title;
  final _PathMark? intention;
  final LongTermRelationType? relation;
  final _PathMark? link;
}
