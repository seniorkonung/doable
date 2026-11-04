import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart' hide Badge, TextField;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/routing/app_router.gr.dart';
import '../../../design_system/components/badge.dart';
import '../../../design_system/components/choice_head.dart';
import '../../../design_system/components/choice_path.dart';
import '../../../design_system/components/confirm_dialog.dart';
import '../../../design_system/components/half_pinned_sliver.dart';
import '../../../design_system/components/list_state.dart';
import '../../../design_system/components/notice.dart';
import '../../../design_system/components/option_row.dart';
import '../../../design_system/components/options_menu.dart';
import '../../../design_system/components/reason_chain.dart';
import '../../../design_system/components/sheet.dart';
import '../../../design_system/components/tabs.dart';
import '../../../design_system/components/text_field.dart';
import '../../../design_system/components/top_bar.dart';
import '../../../design_system/doable_colors.dart';
import '../../../design_system/doable_icon.dart';
import '../../../design_system/doable_metrics.dart';
import '../../../design_system/doable_priority.dart';
import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/personal_graph_repository_provider.dart';
import '../../../graph/presentation/operation_failure_presentation.dart';
import '../../../intention/domain/intention.dart';
import '../../../long_term_relation/domain/long_term_relation.dart';
import '../../../long_term_relation/presentation/details/relation_details_sheet.dart';
import '../../application/daily_choice_command.dart';
import '../../application/daily_choice_details.dart';
import '../../domain/daily_choice_description.dart';
import '../../domain/daily_choice_id.dart';
import '../daily_choice_command_failure_message.dart';
import 'daily_choice_delete_confirmation.dart';
import 'daily_choice_detail_fields.dart';
import 'daily_choice_details_state.dart';
import 'daily_choice_details_view_model.dart';
import 'daily_choice_field_labels.dart';

/// Показывает дневной выбор раскрываемой панелью над текущей страницей.
///
/// Панель владеет моделью выбора, поэтому её закрытие снимает подписку. Шапка
/// с вкладками — первый срез тела: она закреплена, пока занимает не больше
/// половины высоты тела, а выше прокручивается вместе с ним.
///
/// Без загруженного выбора вместо шапки и вкладок стоит одно состояние.
/// Параметров в нём нет, а закрывает лист пользователь, в том числе когда
/// выбора больше нет.
///
/// Флажок шапки и поля «Обзора» выключены на время записи, а новое значение
/// приходит из подписки. Дата, время и приоритет меняются сразу и по одному
/// полю за запись. Отказ стоит над содержимым обеих вкладок и остаётся за
/// панелью, пока она открыта, даже перекрытая страницей.
///
/// Описание меняется под полосой: вместо вкладок над полем стоит шапка выбора
/// без параметров, а сохранение — отдельная запись одного описания. Уход с
/// несохранёнными правками, в том числе закрытие панели, спрашивает
/// подтверждение.
///
/// Подтверждённое удаление из меню закрывает панель, и до конца закрытия она
/// показывает прежнее содержимое с выключенными флажком и параметрами. Панель,
/// перекрытая в этот момент, остаётся открытой и показывает, что выбора нет.
Future<void> showDailyChoiceSheet(
  BuildContext context,
  DailyChoiceId choiceId,
) => showDoableSheet<void>(
  context: context,
  hostsMessages: true,
  builder: (_, sheet) => DailyChoiceSheet(sheet, choiceId: choiceId),
);

enum _ChoiceTab { overview, path }

enum _ChoiceOption { description, delete }

/// Открытое изменение описания: текст при открытии и отказ проверки введённого
/// текста, который живёт до следующего ввода.
typedef _DescriptionEdit = ({
  String opened,
  DailyChoiceDescriptionValidationReason? invalid,
});

/// Содержимое панели выбора; показывает его [showDailyChoiceSheet].
final class DailyChoiceSheet extends ConsumerStatefulWidget {
  const DailyChoiceSheet(this.sheet, {required this.choiceId, super.key});

  final SheetPresentation sheet;
  final DailyChoiceId choiceId;

  @override
  ConsumerState<DailyChoiceSheet> createState() => _DailyChoiceSheetState();
}

final class _DailyChoiceSheetState extends ConsumerState<DailyChoiceSheet> {
  late final DailyChoiceDetailsViewModel _model;
  final _descriptionController = TextEditingController();
  final _descriptionFocus = FocusNode();

  /// Поле описания вместе с отказом проверки под ним.
  final _descriptionKey = GlobalKey();

  var _tab = _ChoiceTab.overview;
  _DescriptionEdit? _edit;

  /// Собственное удаление подтвердилось, когда панель была перекрыта, и она
  /// осталась открытой без выбора.
  var _deletedWhileCovered = false;

  @override
  void initState() {
    super.initState();
    _model = DailyChoiceDetailsViewModel(
      ref.read(personalGraphRepositoryProvider),
      ref.read(graphCommandCoordinatorProvider.notifier),
      widget.choiceId,
    );
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _descriptionFocus.dispose();
    _model.dispose();
    super.dispose();
  }

  void _openDescription(String text) {
    _descriptionController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    setState(() => _edit = (opened: text, invalid: null));
  }

  /// Возвращает «Обзор», с какой бы вкладки ни началось изменение.
  void _closeDescription() => setState(() {
    _edit = null;
    _tab = _ChoiceTab.overview;
  });

  void _changeDescription(_DescriptionEdit edit) =>
      setState(() => _edit = (opened: edit.opened, invalid: null));

  bool _isChanged(_DescriptionEdit edit) =>
      _descriptionController.text != edit.opened;

  /// Неверный ввод и отказ записи оставляют текст в поле: первый показан у
  /// поля, второй — отказом панели.
  Future<void> _saveDescription(_DescriptionEdit edit) async {
    final DailyChoiceDescriptionPatch description;
    try {
      description = DailyChoiceDescriptionPatch.fromInput(
        _descriptionController.text,
      );
    } on DailyChoiceDescriptionValidationException catch (exception) {
      setState(
        () => _edit = (opened: edit.opened, invalid: exception.failure.reason),
      );
      _revealInvalid();
      return;
    }
    final saved = await _model.change(
      DailyChoiceFieldsPatch(description: description),
    );
    if (saved && mounted) _closeDescription();
  }

  /// Прокручивает к отказу проверки после его кадра: под длинным текстом или
  /// над клавиатурой он оказался бы вне видимой части.
  ///
  /// Фокус снимается, иначе вернувшаяся клавиатура прокрутит обратно к каретке.
  void _revealInvalid() {
    _descriptionFocus.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final field = _descriptionKey.currentContext;
      if (!mounted || field == null) return;
      unawaited(
        Scrollable.ensureVisible(
          field,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        ),
      );
    });
  }

  Future<bool> _confirmDiscard() {
    final localizations = AppLocalizations.of(context);
    return showDiscardDialog(
      context: context,
      title: localizations.dailyChoiceSheetDescriptionDiscardTitle,
      text: localizations.dailyChoiceSheetDescriptionDiscardMessage,
      discardLabel: localizations.dailyChoiceSheetDescriptionDiscardAction,
      keepLabel: localizations.dailyChoiceSheetDescriptionContinueAction,
    );
  }

  /// Стрелка возвращает «Обзор», а изменённый текст уходит только после ответа.
  Future<void> _leaveDescription(_DescriptionEdit edit) async {
    if (_isChanged(edit) && !await _confirmDiscard()) return;
    if (mounted) _closeDescription();
  }

  Future<void> _closeSheetAfterDiscard() async {
    if (await _confirmDiscard() && mounted) {
      Navigator.of(context).pop();
    }
  }

  /// Пункт описания открывает то же изменение, что и нажатие на описание в
  /// «Обзоре», с какой бы вкладки ни открыто меню.
  Future<void> _showOptions(DailyChoiceDetails details) async {
    final l10n = AppLocalizations.of(context);
    final description = details.choice.description?.value;
    final option = await showDoableSheet<_ChoiceOption>(
      context: context,
      builder: (_, sheet) => OptionsMenu<_ChoiceOption>(
        sheet,
        title: l10n.dailyChoiceDetailsTitle,
        items: [
          OptionsMenuItem(
            value: _ChoiceOption.description,
            icon: DoableIconData.edit,
            name: description == null
                ? l10n.detailsAddDescription
                : l10n.dailyChoiceSheetOptionEditDescription,
          ),
          OptionsMenuItem(
            value: _ChoiceOption.delete,
            icon: DoableIconData.delete,
            name: l10n.dailyChoiceSheetOptionDelete,
            tone: OptionRowTone.danger,
          ),
        ],
      ),
    );
    if (!mounted || !(ModalRoute.isCurrentOf(context) ?? false)) return;
    final state = _model.state;
    if (state is! DailyChoiceDetailsLoaded || state.details.path.isEmpty) {
      return;
    }
    switch (option) {
      case _ChoiceOption.description:
        _openDescription(state.details.choice.description?.value ?? '');
      case _ChoiceOption.delete:
        final confirmed = await confirmDailyChoiceDeletion(
          context,
          state.details,
        );
        if (!confirmed ||
            !mounted ||
            !(ModalRoute.isCurrentOf(context) ?? false)) {
          return;
        }
        final deleted = await _model.delete();
        if (!deleted || !mounted) return;
        if (ModalRoute.isCurrentOf(context) ?? false) {
          Navigator.of(context).pop();
        } else {
          setState(() => _deletedWhileCovered = true);
        }
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: _model,
      builder: (context, _) => _buildSheet(localizations),
    );
  }

  Widget _buildSheet(AppLocalizations localizations) {
    final state = _model.state;
    // Выбор, которого больше нет или который не прочитан, изменять нечего.
    final edit =
        state is DailyChoiceDetailsLoaded && state.details.path.isNotEmpty
        ? _edit
        : null;
    final isRunning = _model.operation is DailyChoiceDetailsOperationWriting;
    final isChanged = edit != null && _isChanged(edit);
    return PopScope<void>(
      // Во время сохранения запись продолжится и без панели, а её отказ
      // предъявит общая поверхность.
      canPop: !isChanged || isRunning,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_closeSheetAfterDiscard());
      },
      child: Sheet.expandableUntitled(
        widget.sheet,
        label: localizations.dailyChoiceDetailsTitle,
        expandLabel: localizations.dailyChoiceSheetExpand,
        collapseLabel: localizations.dailyChoiceSheetCollapse,
        bar: edit == null
            ? null
            : TopBar.withButton(
                context,
                title: localizations.dailyChoiceSheetDescriptionTitle,
                backLabel: localizations.dailyChoiceSheetDescriptionBack,
                onBack: isRunning
                    ? null
                    : () => unawaited(_leaveDescription(edit)),
                buttonLabel: localizations.dailyChoiceSheetDescriptionSave,
                onButtonPressed: isChanged && !isRunning
                    ? () => unawaited(_saveDescription(edit))
                    : null,
              ),
        slivers: switch (state) {
          DailyChoiceDetailsLoading() => [
            _StateSliver(
              ListState.loading(text: localizations.dailyChoiceDetailsLoading),
            ),
          ],
          DailyChoiceDetailsNotFound() => [_notFound(localizations)],
          DailyChoiceDetailsDeleted() when _deletedWhileCovered => [
            _notFound(localizations),
          ],
          DailyChoiceDetailsDeleted(:final details) => _choice(
            localizations,
            details,
            writable: false,
          ),
          DailyChoiceDetailsUnavailable() => [
            _StateSliver(
              ListState.error(
                message: localizations.dailyChoiceDetailsUnavailable,
                retry: (
                  label: localizations.commonRetry,
                  onPressed: _model.retry,
                ),
              ),
            ),
          ],
          DailyChoiceDetailsUnexpected() => [
            _StateSliver(
              ListState.error(
                message: localizations.dailyChoiceDetailsUnexpected,
              ),
            ),
          ],
          DailyChoiceDetailsCorruption() => [_corruption(localizations)],
          DailyChoiceDetailsLoaded(:final details) when edit != null =>
            _description(localizations, details, edit, isRunning: isRunning),
          DailyChoiceDetailsLoaded(:final details) => _choice(
            localizations,
            details,
            writable: !isRunning,
          ),
        },
      ),
    );
  }

  /// Шапка, вкладки и текущая вкладка; без [writable] флажок и параметры
  /// выключены.
  List<Widget> _choice(
    AppLocalizations localizations,
    DailyChoiceDetails details, {
    required bool writable,
  }) {
    if (details.path.isEmpty) return [_corruption(localizations)];
    return [
      HalfPinnedSliver(
        child: _ChoiceHeader(
          details: details,
          browsing: (
            tab: _tab,
            onTabChange: (tab) => setState(() => _tab = tab),
            onOptions: writable ? () => unawaited(_showOptions(details)) : null,
          ),
          onToggle: writable
              ? () => _model.change(
                  DailyChoiceFieldsPatch(
                    isCompleted: DailyChoiceFieldSet(
                      !details.choice.isCompleted,
                    ),
                  ),
                )
              : null,
        ),
      ),
      if (_model.operation
          case final DailyChoiceDetailsOperationFailed operation)
        _OperationFailureNotice(operation),
      ...switch (_tab) {
        _ChoiceTab.overview => [
          _Overview(
            details: details,
            enabled: writable,
            onChange: _model.change,
            onOpenDescription: _openDescription,
          ),
        ],
        _ChoiceTab.path => [_Path(details: details)],
      },
    ];
  }

  /// Шапка без вкладок и параметров над полем описания; флажок выключен, пока
  /// изменение занимает панель.
  List<Widget> _description(
    AppLocalizations localizations,
    DailyChoiceDetails details,
    _DescriptionEdit edit, {
    required bool isRunning,
  }) => [
    HalfPinnedSliver(
      child: _ChoiceHeader(details: details, browsing: null, onToggle: null),
    ),
    if (_model.operation case final DailyChoiceDetailsOperationFailed operation)
      _OperationFailureNotice(operation),
    SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        DoableMetrics.space5,
        DoableMetrics.space3,
        DoableMetrics.space5,
        0,
      ),
      sliver: SliverToBoxAdapter(
        child: KeyedSubtree(
          key: _descriptionKey,
          child: TextField.multiline(
            controller: _descriptionController,
            focusNode: _descriptionFocus,
            placeholder: localizations.detailsAddDescription,
            label: localizations.dailyChoiceSheetDescriptionTitle,
            minLines: _descriptionMinLines,
            maxLines: _descriptionMaxLines,
            autofocus: true,
            readOnly: isRunning,
            onChanged: (_) => _changeDescription(edit),
            error: switch (edit.invalid) {
              DailyChoiceDescriptionValidationReason.tooLong => Text(
                localizations.editorDescriptionTooLong,
              ),
              DailyChoiceDescriptionValidationReason.invalidUnicodeRepertoire =>
                Text(localizations.editorDescriptionInvalidUnicode),
              DailyChoiceDescriptionValidationReason.absent => Text(
                localizations.dailyChoiceDescriptionInvalid,
              ),
              null => null,
            },
          ),
        ),
      ),
    ),
  ];

  static const _descriptionMinLines = 5;
  static const _descriptionMaxLines = 13;

  Widget _notFound(AppLocalizations localizations) => _StateSliver(
    ListState.error(message: localizations.dailyChoiceDetailsNotFound),
  );

  Widget _corruption(AppLocalizations localizations) => _StateSliver(
    ListState.error(message: localizations.dailyChoiceDetailsCorruption),
  );
}

/// Одно состояние на месте шапки, вкладок и содержимого.
final class _StateSliver extends StatelessWidget {
  const _StateSliver(this.state);

  final ListState state;

  @override
  Widget build(BuildContext context) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(
      DoableMetrics.space5,
      DoableMetrics.space2,
      DoableMetrics.space5,
      0,
    ),
    sliver: SliverToBoxAdapter(child: state),
  );
}

/// Отказ операции под вкладками. Новый отказ панель показывает сама: тело могло
/// уйти дальше него, а высокая шапка могла вытеснить его вниз. Видимый отказ
/// остаётся на месте.
final class _OperationFailureNotice extends StatefulWidget {
  const _OperationFailureNotice(this.operation);

  final DailyChoiceDetailsOperationFailed operation;

  @override
  State<_OperationFailureNotice> createState() =>
      _OperationFailureNoticeState();
}

final class _OperationFailureNoticeState
    extends State<_OperationFailureNotice> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final policy in const [
        ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      ]) {
        unawaited(Scrollable.ensureVisible(context, alignmentPolicy: policy));
      }
    });
  }

  @override
  Widget build(BuildContext context) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(
      DoableMetrics.space5,
      2,
      DoableMetrics.space5,
      DoableMetrics.space1,
    ),
    sliver: SliverToBoxAdapter(
      child: Notice.content(
        message: OperationFailurePresentation(
          claim: widget.operation.failurePresentation,
          message: dailyChoiceCommandFailureMessage(
            AppLocalizations.of(context),
            widget.operation.failure,
          ),
          inheritsColor: true,
        ),
      ),
    ),
  );
}

/// Вкладки под шапкой и параметры в ней; без [onOptions] параметры выключены.
typedef _Browsing = ({
  _ChoiceTab tab,
  ValueChanged<_ChoiceTab> onTabChange,
  VoidCallback? onOptions,
});

/// Шапка выбора и вкладки. Тело проходит под закреплённым срезом, поэтому фон
/// непрозрачный.
final class _ChoiceHeader extends StatelessWidget {
  const _ChoiceHeader({
    required this.details,
    required this.browsing,
    required this.onToggle,
  });

  final DailyChoiceDetails details;

  /// Без него шапка стоит над полем описания: без вкладок и параметров.
  final _Browsing? browsing;

  /// Переключает выполнение; без него флажок выключен.
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<DoableColors>()!;
    final choice = details.choice;
    final priority = dailyChoiceDesignPriority(choice.priority);
    final steps = details.path.length;
    final hasArchive = _hasArchive(details);
    final browsing = this.browsing;
    return ColoredBox(
      color: colors.raised,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DoableMetrics.space5,
            ),
            child: ChoiceHead(
              goal: details.source.title,
              action: details.selected.title,
              priority: priority,
              done: choice.isCompleted,
              chain: ReasonChain(
                reasons: steps,
                priority: priority,
                off: choice.isCompleted,
              ),
              checkLabel: localizations.dailyChoiceSheetCompletionLabel(
                details.selected.title,
                localizations.dailyChoicePriorityOption(
                  dailyChoicePriorityName(priority),
                ),
              ),
              onToggle: onToggle,
              goalBadge: _isArchived(details.source)
                  ? Badge.archivedInline(
                      word: localizations.detailsArchivedBadge,
                    )
                  : null,
              actionBadge: _archiveBadge(localizations, details.selected),
              options: browsing == null
                  ? const ChoiceHeadOptions.none()
                  : switch (browsing.onOptions) {
                      final onOpen? => ChoiceHeadOptions.available(
                        label: localizations.dailyChoiceSheetOptionsLabel,
                        onOpen: onOpen,
                      ),
                      null => ChoiceHeadOptions.unavailable(
                        label: localizations.dailyChoiceSheetOptionsLabel,
                      ),
                    },
            ),
          ),
          if (browsing != null)
            Tabs(
              plane: TabsPlane.sheet,
              label: localizations.dailyChoiceSheetTabsLabel,
              value: browsing.tab,
              onChange: browsing.onTabChange,
              items: [
                TabItem(
                  id: _ChoiceTab.overview,
                  label: localizations.detailsOverviewTab,
                  semanticLabel: localizations.detailsOverviewTab,
                ),
                TabItem(
                  id: _ChoiceTab.path,
                  label: localizations.dailyChoiceSheetPathTab,
                  semanticLabel: hasArchive
                      ? localizations.dailyChoiceSheetPathTabArchivedLabel(
                          steps,
                        )
                      : localizations.dailyChoiceSheetPathTabLabel(steps),
                  count: steps,
                  icon: hasArchive ? DoableIconData.archive : null,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget? _archiveBadge(AppLocalizations localizations, Intention intention) =>
      _isArchived(intention)
      ? Badge.archived(word: localizations.detailsArchivedBadge)
      : null;
}

bool _isArchived(Intention intention) =>
    intention.archiveState == IntentionArchiveState.archived;

bool _hasArchive(DailyChoiceDetails details) =>
    _isArchived(details.source) ||
    details.path.any(
      (step) =>
          _isArchived(step.related) ||
          step.relation.scope == RelationScope.archived,
    );

/// Сохранённые ссылки показывают текущие данные намерений и связей.
final class _Path extends StatelessWidget {
  const _Path({required this.details});

  final DailyChoiceDetails details;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    ChoicePathStep intention(Intention value, String role, int position) {
      final archived = _isArchived(value);
      final state = archived
          ? l10n.dailyChoiceDetailsArchived
          : l10n.dailyChoiceDetailsActive;
      return ChoicePathStep(
        name: value.title,
        semanticLabel: '$role, ${value.title}, $state',
        archived: archived,
        buttonKey: ValueKey('daily-choice-intention-$position'),
        onOpen: () => unawaited(
          context.router.push(IntentionDetailsRoute(intentionId: value.id)),
        ),
      );
    }

    ChoicePathLink link(DailyChoicePathStepDetails step, int index) {
      final relation = step.relation;
      final archived = relation.scope == RelationScope.archived;
      final kind = switch (relation.type) {
        LongTermRelationType.need => ChoicePathRelationKind.need,
        LongTermRelationType.can => ChoicePathRelationKind.can,
      };
      final word = switch (kind) {
        ChoicePathRelationKind.need => l10n.relationNeighborhoodTypeNeed,
        ChoicePathRelationKind.can => l10n.relationNeighborhoodTypeCan,
      };
      final state = archived
          ? l10n.dailyChoiceDetailsArchived
          : l10n.dailyChoiceDetailsActive;
      final priority = switch (relation.priority) {
        RelationPriority.p1 => DoablePriority.p1,
        RelationPriority.p2 => DoablePriority.p2,
        RelationPriority.p3 => DoablePriority.p3,
        RelationPriority.p4 => DoablePriority.p4,
      };
      final role = index == details.path.length - 1
          ? l10n.dailyChoiceDetailsSelectedAction
          : l10n.dailyChoiceDetailsIntermediate;
      return ChoicePathLink(
        relation: ChoicePathRelation(
          kind: kind,
          priority: priority,
          semanticLabel:
              '${l10n.dailyChoiceDetailsStep(index + 1)}, $word, '
              '${step.source.title}, ${step.related.title}, '
              '${dailyChoicePriorityName(priority)}, $state',
          archived: archived,
          buttonKey: ValueKey('daily-choice-relation-${index + 1}'),
          onOpen: () =>
              unawaited(showRelationDetailsSheet(context, relation.id)),
        ),
        step: intention(step.related, role, index + 2),
      );
    }

    final links = [
      for (final (index, step) in details.path.indexed) link(step, index),
    ];
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        DoableMetrics.space5,
        2,
        DoableMetrics.space5,
        0,
      ),
      sliver: SliverToBoxAdapter(
        child: ChoicePath(
          source: intention(details.source, l10n.dailyChoiceDetailsSource, 1),
          intermediate: links.sublist(0, links.length - 1),
          action: links.last,
          priority: dailyChoiceDesignPriority(details.choice.priority),
          done: details.choice.isCompleted,
          kindWord: (kind) => switch (kind) {
            ChoicePathRelationKind.need => l10n.relationNeighborhoodTypeNeed,
            ChoicePathRelationKind.can => l10n.relationNeighborhoodTypeCan,
          },
          archivedBadge: Badge.archived(word: l10n.detailsArchivedBadge),
          archivedNote: l10n.dailyChoiceSheetPathArchivedNote,
        ),
      ),
    );
  }
}

/// Вкладка «Обзор»: описание целиком и поля, которые меняются сразу.
final class _Overview extends StatelessWidget {
  const _Overview({
    required this.details,
    required this.enabled,
    required this.onChange,
    required this.onOpenDescription,
  });

  final DailyChoiceDetails details;

  /// Без него поля не меняются: идёт запись или панель закрывается.
  final bool enabled;

  /// Каждый выбор значения — отдельная запись одного поля.
  final ValueChanged<DailyChoiceFieldsPatch> onChange;

  /// Открывает изменение описания с сохранённым текстом.
  final ValueChanged<String> onOpenDescription;

  /// Вместе с нижним полем полосы вкладок даёт 6 под областью их нажатия.
  static const double _top = 2;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final choice = details.choice;
    final description = choice.description?.value;
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        DoableMetrics.space5,
        _top,
        DoableMetrics.space5,
        0,
      ),
      sliver: SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField.saved(
              value: description ?? '',
              placeholder: localizations.detailsAddDescription,
              label: switch (description) {
                final description? => localizations.detailsEditDescriptionLabel(
                  description,
                ),
                null => localizations.detailsAddDescription,
              },
              onOpen: enabled
                  ? () => onOpenDescription(description ?? '')
                  : null,
            ),
            const SizedBox(height: DoableMetrics.space2),
            DailyChoiceDetailFields(
              date: choice.date,
              schedule: choice.schedule,
              priority: choice.priority,
              enabled: enabled,
              onDateChanged: (date) => onChange(
                DailyChoiceFieldsPatch(date: DailyChoiceFieldSet(date)),
              ),
              onScheduleChanged: (schedule) => onChange(
                DailyChoiceFieldsPatch(schedule: DailyChoiceFieldSet(schedule)),
              ),
              onPriorityChanged: (priority) => onChange(
                DailyChoiceFieldsPatch(priority: DailyChoiceFieldSet(priority)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
