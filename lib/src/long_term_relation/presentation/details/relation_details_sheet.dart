import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart' hide TextField;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/routing/app_router.gr.dart';
import '../../../daily_choice/presentation/catalog/daily_choice_local_date_provider.dart';
import '../../../design_system/components/confirm_dialog.dart';
import '../../../design_system/components/list_state.dart';
import '../../../design_system/components/notice.dart';
import '../../../design_system/components/priority_picker.dart';
import '../../../design_system/components/relation_head.dart';
import '../../../design_system/components/sheet.dart';
import '../../../design_system/components/text_field.dart';
import '../../../design_system/components/top_bar.dart';
import '../../../design_system/doable_colors.dart';
import '../../../design_system/doable_metrics.dart';
import '../../../design_system/doable_type.dart';
import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/presentation/operation_failure_presentation.dart';
import '../../../intention/domain/intention.dart';
import '../../../shared/presentation/timestamp_dates_line.dart';
import '../../application/long_term_relation_projection.dart';
import '../../domain/long_term_relation.dart';
import '../../domain/long_term_relation_description.dart';
import '../../domain/long_term_relation_id.dart';
import '../relation_command_failure_message.dart';
import 'relation_details_options.dart';
import 'relation_details_state.dart';
import 'relation_details_view_model.dart';

/// Показывает подробный просмотр связи панелью над текущей страницей.
///
/// Шапка всегда сохраняет исходное направление связи, поэтому вход из входящей
/// группы её не переворачивает. Название участника открывает его страницу
/// поверх панели, а панель остаётся ниже в истории.
///
/// Описание меняется в полном размере панели, а изменённый текст уходит только
/// после ответа на вопрос: панель не закрывается сама, пока он не сохраняется.
/// Архивирование, восстановление и удаление связи выбираются в её параметрах.
Future<void> showRelationDetailsSheet(
  BuildContext context,
  LongTermRelationId relationId,
) => showDoableSheet<void>(
  context: context,
  hostsMessages: true,
  builder: (_, presentation) =>
      _RelationDetailsSheet(presentation, relationId: relationId),
);

final class _RelationDetailsSheet extends ConsumerStatefulWidget {
  const _RelationDetailsSheet(this.presentation, {required this.relationId});

  final SheetPresentation presentation;
  final LongTermRelationId relationId;

  @override
  ConsumerState<_RelationDetailsSheet> createState() =>
      _RelationDetailsSheetState();
}

/// Открытое изменение описания: текст при открытии и отказ проверки введённого
/// текста, который живёт до следующего ввода.
typedef _DescriptionEdit = ({
  String opened,
  LongTermRelationTextValidationReason? invalid,
});

final class _RelationDetailsSheetState
    extends ConsumerState<_RelationDetailsSheet> {
  final _descriptionController = TextEditingController();
  final _descriptionFocus = FocusNode();

  /// Конец содержимого изменения: под полем и его отказами.
  final _editEndKey = GlobalKey();

  _DescriptionEdit? _edit;

  RelationDetailsViewModelProvider get _provider =>
      relationDetailsViewModelProvider(widget.relationId);

  @override
  void dispose() {
    _descriptionController.dispose();
    _descriptionFocus.dispose();
    super.dispose();
  }

  void _openDescription(String text) {
    _descriptionController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    setState(() => _edit = (opened: text, invalid: null));
  }

  void _closeDescription() => setState(() => _edit = null);

  void _changeDescription(_DescriptionEdit edit) =>
      setState(() => _edit = (opened: edit.opened, invalid: null));

  Future<void> _saveDescription(_DescriptionEdit edit) async {
    final outcome = await ref
        .read(_provider.notifier)
        .saveDescription(_descriptionController.text);
    if (!mounted) return;
    switch (outcome) {
      case RelationDescriptionSaved() || RelationDescriptionUnchanged():
        _closeDescription();
      case RelationDescriptionInvalid(:final reason):
        setState(() => _edit = (opened: edit.opened, invalid: reason));
        _revealFailure();
      case RelationDescriptionSaveFailed():
        _revealFailure();
    }
  }

  /// Прокручивает к отказу под полем после его кадра: над клавиатурой он
  /// оказался бы вне видимой части, и кадр не подтвердил бы его предъявление.
  ///
  /// Фокус снимается, иначе вернувшаяся клавиатура прокрутит обратно к каретке.
  void _revealFailure() {
    _descriptionFocus.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final end = _editEndKey.currentContext;
      if (!mounted || end == null) return;
      unawaited(
        Scrollable.ensureVisible(
          end,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        ),
      );
    });
  }

  Future<bool> _confirmDiscard() {
    final localizations = AppLocalizations.of(context);
    return showDiscardDialog(
      context: context,
      title: localizations.relationSheetDescriptionDiscardTitle,
      text: localizations.relationSheetDescriptionDiscardMessage,
      discardLabel: localizations.relationSheetDescriptionDiscardAction,
      keepLabel: localizations.relationSheetDescriptionContinueAction,
    );
  }

  bool _isChanged(_DescriptionEdit edit) =>
      _descriptionController.text != edit.opened;

  /// Стрелка возвращает панель, а изменённый текст уходит только после ответа.
  Future<void> _leaveDescription(_DescriptionEdit edit) async {
    if (_isChanged(edit) && !await _confirmDiscard()) return;
    if (mounted) _closeDescription();
  }

  Future<void> _closeSheetAfterDiscard() async {
    if (await _confirmDiscard() && mounted) {
      Navigator.of(context).pop();
    }
  }

  /// Лист параметров закрывается до начала действия, поэтому оно начинается уже
  /// на панели (ADR-0042). Выбор приходит после анимации закрытия, когда панель
  /// уже принимает нажатия, поэтому поздний выбор отбрасывается, если над
  /// панелью уже что-то открыто или она уходит.
  Future<void> _openOptions() async {
    final provider = _provider;
    final option = await showDoableSheet<RelationOption>(
      context: context,
      builder: (_, sheet) =>
          RelationOptionsSheet(sheet: sheet, provider: provider),
    );
    if (option == null ||
        !mounted ||
        !(ModalRoute.isCurrentOf(context) ?? false)) {
      return;
    }
    final viewModel = ref.read(provider.notifier);
    switch (option) {
      case RelationOption.archive:
        viewModel.archive();
      case RelationOption.restore:
        viewModel.restore();
      case RelationOption.delete:
        await _confirmDeletion();
    }
  }

  Future<void> _confirmDeletion() async {
    final loaded = ref.read(_provider);
    if (loaded is! RelationDetailsLoaded) return;
    final localizations = AppLocalizations.of(context);
    final confirmed = await showConfirmDialog(
      context: context,
      title: localizations.relationSheetDeleteDialogTitle,
      text: ConfirmDialogText(
        before: localizations.relationSheetDeleteDialogTextBefore,
        name: _relationPhrase(localizations, loaded.details),
        after: localizations.relationSheetDeleteDialogTextAfter,
      ),
      cancelLabel: localizations.relationSheetDeleteDialogCancel,
      actionLabel: localizations.relationSheetDeleteDialogConfirm,
    );
    if (confirmed && mounted) await _delete();
  }

  Future<void> _delete() async {
    final deleted = await ref.read(_provider.notifier).delete();
    // Закрытие принадлежит принявшей команду панели, а не общему Deleted. После
    // ожидания сброшенный или перекрытый маршрут теряет это право.
    // https://api.flutter.dev/flutter/widgets/Route/isCurrent.html
    // pop синхронен: после проверки нет новой асинхронной границы.
    // https://api.flutter.dev/flutter/widgets/NavigatorState/pop.html
    if (deleted && mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
      Navigator.of(context).pop();
    }
  }

  /// Повтор удаления закрывает панель так же, как первое удаление.
  void _retryLifecycleChange() {
    final current = ref.read(_provider);
    if (current case RelationDetailsLoaded(
      lifecycleChange: RelationDetailsLifecycleFailed(
        kind: RelationDetailsLifecycleKind.delete,
        canRetry: true,
      ),
    )) {
      unawaited(_delete());
    } else {
      ref.read(_provider.notifier).retryLifecycleChange();
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final state = ref.watch(_provider);
    final viewModel = ref.read(_provider.notifier);
    final retry = (
      label: localizations.commonRetry,
      onPressed: viewModel.retry,
    );
    // Связь, которой больше нет, изменять нечего, и панель закрывается сразу.
    final edit = state is RelationDetailsLoaded ? _edit : null;
    final isRunning = state.isOperationRunning;
    final isChanged = edit != null && _isChanged(edit);
    return PopScope<void>(
      // Во время сохранения команда продолжится и без панели, а её отказ
      // предъявит оболочка.
      canPop: !isChanged || isRunning,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_closeSheetAfterDiscard());
      },
      child: Sheet.untitled(
        widget.presentation,
        label: switch (state) {
          RelationDetailsLoaded() when edit != null =>
            localizations.relationSheetDescriptionLabel,
          RelationDetailsLoaded(:final details) => _sheetLabel(
            localizations,
            details,
          ),
          _ => localizations.relationDetailsTitle,
        },
        expandLabel: localizations.relationSheetExpand,
        collapseLabel: localizations.relationSheetCollapse,
        bar: edit == null
            ? null
            : TopBar.withButton(
                context,
                title: localizations.relationSheetDescriptionTitle,
                backLabel: localizations.relationSheetDescriptionBack,
                onBack: isRunning
                    ? null
                    : () => unawaited(_leaveDescription(edit)),
                buttonLabel: localizations.relationSheetDescriptionSave,
                onButtonPressed: isChanged && !isRunning
                    ? () => unawaited(_saveDescription(edit))
                    : null,
              ),
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
              description: switch (edit) {
                final edit? => _DescriptionEditing(
                  controller: _descriptionController,
                  focusNode: _descriptionFocus,
                  invalid: edit.invalid,
                  endKey: _editEndKey,
                  onChanged: (_) => _changeDescription(edit),
                ),
                null => _DescriptionSaved(onOpen: _openDescription),
              },
              onRetry: viewModel.retry,
              onChangeType: viewModel.changeType,
              onChangePriority: viewModel.changePriority,
              onOpenOptions: () => unawaited(_openOptions()),
              onRetryLifecycleChange: _retryLifecycleChange,
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
      ),
    );
  }
}

/// Что панель показывает на месте описания.
sealed class _DescriptionMode {
  const _DescriptionMode();
}

/// Сохранённое описание, нажатие на которое открывает его изменение.
final class _DescriptionSaved extends _DescriptionMode {
  const _DescriptionSaved({required this.onOpen});

  final ValueChanged<String> onOpen;
}

/// Поле изменения описания в полном размере панели.
final class _DescriptionEditing extends _DescriptionMode {
  const _DescriptionEditing({
    required this.controller,
    required this.focusNode,
    required this.invalid,
    required this.endKey,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final LongTermRelationTextValidationReason? invalid;
  final Key endKey;
  final ValueChanged<String> onChanged;
}

/// Полная формулировка связи в исходном направлении.
String _relationPhrase(
  AppLocalizations localizations,
  LongTermRelationDetails details,
) => switch (details.relation.type) {
  LongTermRelationType.need => localizations.relationNeighborhoodNeedPhrase(
    details.source.title,
    details.related.title,
  ),
  LongTermRelationType.can => localizations.relationNeighborhoodCanPhrase(
    details.source.title,
    details.related.title,
  ),
};

/// Доступное название панели: формулировка, а у архивированной связи ещё и
/// пометка архива.
String _sheetLabel(
  AppLocalizations localizations,
  LongTermRelationDetails details,
) {
  final phrase = _relationPhrase(localizations, details);
  return switch (details.relation.scope) {
    RelationScope.active => phrase,
    RelationScope.archived => localizations.relationSheetArchivedLabel(phrase),
  };
}

final class _LoadedRelation extends ConsumerWidget {
  const _LoadedRelation({
    required this.state,
    required this.description,
    required this.onRetry,
    required this.onChangeType,
    required this.onChangePriority,
    required this.onOpenOptions,
    required this.onRetryLifecycleChange,
  });

  final RelationDetailsLoaded state;
  final _DescriptionMode description;
  final VoidCallback onRetry;
  final ValueChanged<LongTermRelationType> onChangeType;
  final ValueChanged<RelationPriority> onChangePriority;
  final VoidCallback onOpenOptions;
  final VoidCallback onRetryLifecycleChange;

  /// Последняя пилюля приоритета выходит за край содержимого.
  static const double _pickerShift = 2;
  static const _descriptionMinLines = 5;
  static const _descriptionMaxLines = 13;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<DoableColors>()!;
    final details = state.details;
    final relation = details.relation;
    final savedDescription = details.description?.value;
    final isOperationRunning = state.isOperationRunning;
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
    final description = this.description;
    final isEditing = description is _DescriptionEditing;
    final operationStatus = isOperationRunning
        ? Semantics(
            container: true,
            liveRegion: true,
            child: Text(
              localizations.detailsOperationRunning,
              style: DoableType.hint.copyWith(color: colors.muted),
            ),
          )
        : null;
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
            RelationScope.active when isEditing => const RelationHeadActive(),
            RelationScope.archived when isEditing =>
              const RelationHeadArchived(),
            RelationScope.active => RelationHeadActive(
              kindSwitch: RelationHeadKindSwitch(
                label: localizations.relationDetailsTypeLabel,
                onChange: isOperationRunning
                    ? null
                    : (kind) => onChangeType(_relationType(kind)),
              ),
            ),
            RelationScope.archived => RelationHeadArchived(
              note: localizations.relationSheetArchivedNote,
            ),
          },
          // Изменение описания занимает панель целиком, и параметры в это время
          // недоступны.
          menu: isEditing
              ? null
              : RelationHeadMenu(
                  label: localizations.relationSheetOptionsLabel,
                  onOpen: onOpenOptions,
                ),
          kindName: (kind) => switch (kind) {
            RelationHeadKind.need => localizations.relationNeighborhoodTypeNeed,
            RelationHeadKind.can => localizations.relationNeighborhoodTypeCan,
          },
          archivedWord: localizations.detailsArchivedBadge,
        ),
        const SizedBox(height: 10),
        ...switch (description) {
          _DescriptionSaved(:final onOpen) => [
            TextField.saved(
              value: savedDescription ?? '',
              placeholder: localizations.detailsAddDescription,
              label: switch (savedDescription) {
                final description? => localizations.detailsEditDescriptionLabel(
                  description,
                ),
                null => localizations.detailsAddDescription,
              },
              onOpen: isOperationRunning
                  ? null
                  : () => onOpen(savedDescription ?? ''),
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
                    onChange: isOperationRunning
                        ? null
                        : (priority) =>
                              onChangePriority(_relationPriority(priority)),
                    label: localizations.relationDetailsPriorityLabel,
                    name: _priorityName,
                    itemLabel: (priority, _) =>
                        _priorityItemLabel(localizations, priority),
                  ),
                ),
              ],
            ),
          ],
          final _DescriptionEditing editing => [
            TextField.multiline(
              controller: editing.controller,
              focusNode: editing.focusNode,
              placeholder: localizations.detailsAddDescription,
              label: localizations.relationSheetDescriptionTitle,
              minLines: _descriptionMinLines,
              maxLines: _descriptionMaxLines,
              autofocus: true,
              readOnly: isOperationRunning,
              onChanged: editing.onChanged,
              error: switch (editing.invalid) {
                LongTermRelationTextValidationReason.tooLong => Text(
                  localizations.relationEditorDescriptionTooLong,
                ),
                LongTermRelationTextValidationReason.invalidUnicodeRepertoire =>
                  Text(localizations.relationEditorDescriptionInvalidUnicode),
                null => null,
              },
            ),
          ],
        },
        if (state.editFailure case final editFailure?) ...[
          const SizedBox(height: DoableMetrics.space2),
          Notice.content(
            message: OperationFailurePresentation(
              claim: editFailure.failurePresentation,
              message: longTermRelationCommandFailureMessage(
                localizations,
                LongTermRelationCommandKind.update,
                editFailure.failure,
              ),
              inheritsColor: true,
            ),
          ),
        ],
        if (state.lifecycleChange case RelationDetailsLifecycleFailed(
          :final kind,
          :final failure,
          :final failurePresentation,
          :final canRetry,
        )) ...[
          const SizedBox(height: DoableMetrics.space2),
          Notice.content(
            message: OperationFailurePresentation(
              claim: failurePresentation,
              message: longTermRelationCommandFailureMessage(
                localizations,
                _commandKind(kind),
                failure,
              ),
              inheritsColor: true,
            ),
            action: canRetry && !isOperationRunning
                ? (
                    label: localizations.commonRetry,
                    onPressed: onRetryLifecycleChange,
                  )
                : null,
          ),
        ],
        const SizedBox(height: DoableMetrics.space2),
        switch (description) {
          // Правка длится мгновения: статус стоит рядом с датами, поэтому не
          // дёргает панель по высоте при каждом нажатии.
          _DescriptionSaved() => Wrap(
            spacing: DoableMetrics.space3,
            children: [
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
              ?operationStatus,
            ],
          ),
          _DescriptionEditing(:final endKey) => KeyedSubtree(
            key: endKey,
            child: operationStatus ?? const SizedBox.shrink(),
          ),
        },
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

LongTermRelationCommandKind _commandKind(
  RelationDetailsLifecycleKind kind,
) => switch (kind) {
  RelationDetailsLifecycleKind.archive => LongTermRelationCommandKind.archive,
  RelationDetailsLifecycleKind.restore => LongTermRelationCommandKind.restore,
  RelationDetailsLifecycleKind.delete => LongTermRelationCommandKind.delete,
};

LongTermRelationType _relationType(RelationHeadKind kind) => switch (kind) {
  RelationHeadKind.need => LongTermRelationType.need,
  RelationHeadKind.can => LongTermRelationType.can,
};

RelationPriority _relationPriority(DoablePriority priority) =>
    switch (priority) {
      DoablePriority.p1 => RelationPriority.p1,
      DoablePriority.p2 => RelationPriority.p2,
      DoablePriority.p3 => RelationPriority.p3,
      DoablePriority.p4 => RelationPriority.p4,
    };

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
