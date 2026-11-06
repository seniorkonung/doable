import 'dart:async';

import 'package:flutter/material.dart' hide Action, TextField;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/action_head.dart';
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
import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/personal_graph_repository_provider.dart';
import '../../../graph/presentation/operation_failure_presentation.dart';
import '../../../shared/domain/calendar_date.dart';
import '../../../shared/presentation/local_day/local_date_provider.dart';
import '../../../shared/presentation/local_day/local_day_observer.dart';
import '../../../shared/presentation/timestamp_dates_line.dart';
import '../../application/action_command.dart';
import '../../application/action_details.dart';
import '../../application/action_result.dart';
import '../../domain/action.dart';
import '../../domain/action_id.dart';
import '../action_command_failure_message.dart';
import 'action_delete_confirmation.dart';
import 'action_field_labels.dart';
import 'action_panel_fields.dart';
import 'action_panel_state.dart';
import 'action_panel_view_model.dart';
import 'action_path_tab.dart';
import 'action_text_editor.dart';

/// Показывает действие раскрываемой панелью над текущей страницей.
///
/// Панель владеет моделью действия, поэтому её закрытие снимает подписку. Шапка
/// с вкладками — первый срез тела: она закреплена, пока занимает не больше
/// половины высоты тела, а выше прокручивается вместе с ним. Панель открывается
/// на «Обзоре»; корень с цепочкой в шапке открывает «Путь», где сохранённый
/// путь показан только для чтения. Страница намерения и просмотр связи из пути
/// ложатся поверх панели, а возврат оставляет её на прежней вкладке.
///
/// Без загруженного действия вместо шапки стоит одно состояние. Закрывает лист
/// пользователь, в том числе когда действия больше нет.
///
/// Флажок шапки и поля «Обзора» выключены на время записи, а новое значение
/// приходит из подписки. Дата, время, приоритет и выполнение меняются сразу и
/// по одному полю за запись. Отказ стоит над содержимым и остаётся за панелью,
/// пока она открыта, даже перекрытая страницей. После отказа без явного
/// повтора флажок выключен, пока панель не перечитает действие.
///
/// Название и описание меняются вместе в изменении под полосой: его открывают
/// название в шапке, описание в «Обзоре» и пункт меню параметров. Сохранение —
/// одна запись обоих полей, а панель закрывает изменение, только когда
/// подписка показала записанные значения. Закрытое изменение возвращает
/// вкладку, с которой оно начато. Уход с правками спрашивает подтверждение.
///
/// Удаление спрашивает подтверждение. Подтверждённое закрывает панель с
/// прежним содержимым, а отказ остаётся в открытой панели.
Future<void> showActionPanel(BuildContext context, ActionId actionId) =>
    showDoableSheet<void>(
      context: context,
      hostsMessages: true,
      builder: (_, sheet) => ActionPanel(sheet, actionId: actionId),
    );

enum _ActionOption { editText, delete }

/// Содержимое панели действия; показывает его [showActionPanel].
final class ActionPanel extends ConsumerStatefulWidget {
  const ActionPanel(this.sheet, {required this.actionId, super.key});

  final SheetPresentation sheet;
  final ActionId actionId;

  @override
  ConsumerState<ActionPanel> createState() => _ActionPanelState();
}

final class _ActionPanelState extends ConsumerState<ActionPanel> {
  late final ActionPanelViewModel _model;

  /// Панель может остаться на экране после местной полуночи, и тогда
  /// «Сегодня» в поле даты и текущий год в строке дат стали бы неверными.
  late final LocalDayObserver _localDay;

  /// Открытое изменение названия и описания.
  ActionTextEdit? _edit;

  /// Выбранная вкладка не меняется изменением текста: оно её только скрывает.
  var _tab = ActionPanelTab.overview;

  @override
  void initState() {
    super.initState();
    _model = ActionPanelViewModel(
      ref.read(personalGraphRepositoryProvider),
      ref.read(graphCommandCoordinatorProvider.notifier),
      widget.actionId,
    );
    _localDay = LocalDayObserver(
      readLocalDay: ref.read(localDateSourceProvider),
      onTodayChanged: () => setState(() {}),
    );
  }

  @override
  void dispose() {
    _localDay.dispose();
    _model.dispose();
    super.dispose();
  }

  void _openEdit(Action action, ActionTextField focus) =>
      setState(() => _edit = ActionTextEdit.open(action, focus));

  void _closeEdit() => setState(() => _edit = null);

  void _changeEdit(ActionTextEdit edit, ActionTextDraft draft) {
    if (draft != edit.current) setState(() => _edit = edit.withDraft(draft));
  }

  /// Неверный ввод остаётся у поля, а отказ записи — отказом панели; в обоих
  /// случаях текст остаётся в полях.
  Future<void> _saveEdit(ActionTextEdit edit) async {
    switch (edit.parse()) {
      case ActionTextRejected rejected:
        setState(() => _edit = edit.withRejected(rejected));
      case ActionTextAccepted(:final patch):
        final saved = await _model.change(patch);
        if (saved && mounted) _closeEdit();
    }
  }

  Future<bool> _confirmDiscard() {
    final localizations = AppLocalizations.of(context);
    return showDiscardDialog(
      context: context,
      title: localizations.actionTextEditDiscardTitle,
      text: localizations.actionTextEditDiscardMessage,
      discardLabel: localizations.actionTextEditDiscardAction,
      keepLabel: localizations.actionTextEditContinueAction,
    );
  }

  /// Стрелка возвращает вкладку, с которой начата правка, а изменённый текст
  /// уходит только после ответа.
  Future<void> _leaveEdit(ActionTextEdit edit) async {
    if (edit.isChanged && !await _confirmDiscard()) return;
    if (mounted) _closeEdit();
  }

  Future<void> _closePanelAfterDiscard() async {
    if (await _confirmDiscard() && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _showOptions() async {
    final localizations = AppLocalizations.of(context);
    final option = await showDoableSheet<_ActionOption>(
      context: context,
      builder: (_, sheet) => OptionsMenu<_ActionOption>(
        sheet,
        title: localizations.actionPanelTitle,
        items: [
          OptionsMenuItem(
            value: _ActionOption.editText,
            icon: DoableIconData.edit,
            name: localizations.actionOptionEditText,
          ),
          OptionsMenuItem(
            value: _ActionOption.delete,
            icon: DoableIconData.delete,
            name: localizations.actionOptionDelete,
            hint: localizations.actionOptionDeleteHint,
            tone: OptionRowTone.danger,
          ),
        ],
      ),
    );
    if (!mounted || !(ModalRoute.isCurrentOf(context) ?? false)) return;
    final state = _model.state;
    if (state is! ActionPanelLoaded) return;
    switch (option) {
      case _ActionOption.editText:
        _openEdit(state.details.action, ActionTextField.title);
      case _ActionOption.delete:
        final confirmed = await confirmActionDeletion(
          context,
          state.details.action,
          today: _localDay.today,
        );
        if (!confirmed ||
            !mounted ||
            !(ModalRoute.isCurrentOf(context) ?? false)) {
          return;
        }
        if (await _model.delete() && mounted) Navigator.of(context).pop();
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: _model,
      builder: (context, _) {
        // Действия, которого больше нет или которое не прочитано, изменять
        // нечего.
        final edit = _model.state is ActionPanelLoaded ? _edit : null;
        // До снимка с записанным значением панель недоступна, как во время
        // записи.
        final isWriting = switch (_model.operation) {
          ActionPanelOperationWriting() ||
          ActionPanelOperationAwaitingSnapshot() => true,
          ActionPanelOperationIdle() || ActionPanelOperationFailed() => false,
        };
        return PopScope<void>(
          // Во время сохранения запись продолжится и без панели, а её отказ
          // предъявит общая поверхность.
          canPop: edit == null || !edit.isChanged || isWriting,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) unawaited(_closePanelAfterDiscard());
          },
          child: Sheet.expandableUntitled(
            widget.sheet,
            label: localizations.actionPanelTitle,
            expandLabel: localizations.actionPanelExpand,
            collapseLabel: localizations.actionPanelCollapse,
            bar: edit == null
                ? null
                : TopBar.withButton(
                    context,
                    title: localizations.actionTextEditTitle,
                    backLabel: localizations.actionTextEditBack,
                    onBack: isWriting
                        ? null
                        : () => unawaited(_leaveEdit(edit)),
                    buttonLabel: localizations.actionTextEditSave,
                    onButtonPressed: edit.canSave && !isWriting
                        ? () => unawaited(_saveEdit(edit))
                        : null,
                  ),
            slivers: switch (_model.state) {
              ActionPanelLoading() => [
                _StateSliver(
                  ListState.loading(text: localizations.actionPanelLoading),
                ),
              ],
              ActionPanelNotFound() => [
                _StateSliver(
                  ListState.error(
                    message: localizations.actionOperationNotFound,
                  ),
                ),
              ],
              ActionPanelUnavailable() => [
                _StateSliver(
                  ListState.error(
                    message: localizations.actionPanelUnavailable,
                    retry: (
                      label: localizations.commonRetry,
                      onPressed: _model.retry,
                    ),
                  ),
                ),
              ],
              ActionPanelCorruption() => [
                _StateSliver(
                  ListState.error(message: localizations.actionPanelCorruption),
                ),
              ],
              ActionPanelUnexpected() => [
                _StateSliver(
                  ListState.error(message: localizations.actionPanelUnexpected),
                ),
              ],
              ActionPanelDeleted(:final details) => _action(
                details,
                isWriting: true,
              ),
              ActionPanelLoaded() when edit != null => _textEdit(
                edit,
                isWriting: isWriting,
              ),
              ActionPanelLoaded(:final details) => _action(
                details,
                isWriting: isWriting,
              ),
            },
          ),
        );
      },
    );
  }

  /// Изменение названия и описания под полосой; шапки и «Обзора» нет, а отказ
  /// записи стоит над полями.
  List<Widget> _textEdit(ActionTextEdit edit, {required bool isWriting}) => [
    ..._notice(),
    ActionTextEditor(
      edit: edit,
      readOnly: isWriting,
      onChanged: (draft) => _changeEdit(edit, draft),
    ),
  ];

  /// Отказ операции над содержимым, если он есть.
  List<Widget> _notice() {
    final completionLock = _model.completionLock;
    final failed = switch (_model.operation) {
      final ActionPanelOperationFailed operation => operation,
      _ => null,
    };
    return [
      if (failed != null || completionLock != null)
        _OperationNotice(
          failed: failed,
          lockFailure: completionLock,
          onRefresh: completionLock == null ? null : _model.refresh,
        ),
    ];
  }

  /// Шапка с вкладками и выбранная вкладка. Пока идёт запись, флажок, название,
  /// описание, параметры и поля недоступны; вкладки переключаются всегда.
  List<Widget> _action(ActionDetails details, {required bool isWriting}) {
    final completionLock = _model.completionLock;
    return [
      HalfPinnedSliver(
        child: _ActionHeader(
          details: details,
          tab: _tab,
          onTabChange: (tab) => setState(() => _tab = tab),
          onToggle: isWriting || completionLock != null
              ? null
              : () => unawaited(
                  _model.change(
                    ActionFieldsPatch(
                      isCompleted: ActionFieldSet(!details.action.isCompleted),
                    ),
                  ),
                ),
          onEditName: isWriting
              ? null
              : () => _openEdit(details.action, ActionTextField.title),
          onOpenOptions: isWriting ? null : () => unawaited(_showOptions()),
        ),
      ),
      ..._notice(),
      switch (_tab) {
        ActionPanelTab.overview => _Overview(
          details: details,
          today: _localDay.today,
          enabled: !isWriting,
          onChange: (patch) => unawaited(_model.change(patch)),
          onOpenDescription: isWriting
              ? null
              : () => _openEdit(details.action, ActionTextField.description),
        ),
        ActionPanelTab.path => ActionPathTab(details: details),
      },
    ];
  }
}

/// Одно состояние на месте шапки и содержимого.
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
///
/// Отказ изменения выполнения без явного повтора остаётся рядом с действием
/// [onRefresh], пока флажок выключен, даже когда следующая операция сняла
/// отказ [failed].
final class _OperationNotice extends StatefulWidget {
  const _OperationNotice({
    required this.failed,
    required this.lockFailure,
    required this.onRefresh,
  });

  final ActionPanelOperationFailed? failed;
  final ActionCommandFailure? lockFailure;
  final VoidCallback? onRefresh;

  @override
  State<_OperationNotice> createState() => _OperationNoticeState();
}

final class _OperationNoticeState extends State<_OperationNotice> {
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
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final failed = widget.failed;
    final failure = failed?.failure ?? widget.lockFailure!;
    final onRefresh = widget.onRefresh;
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        DoableMetrics.space5,
        2,
        DoableMetrics.space5,
        DoableMetrics.space1,
      ),
      sliver: SliverToBoxAdapter(
        child: Notice.content(
          message: OperationFailurePresentation(
            claim: failed?.failurePresentation,
            message: actionCommandFailureMessage(localizations, failure),
            inheritsColor: true,
          ),
          action: onRefresh == null
              ? null
              : (label: localizations.actionRefresh, onPressed: onRefresh),
        ),
      ),
    );
  }
}

/// Шапка действия и вкладки. Тело проходит под закреплённым срезом, поэтому
/// фон непрозрачный.
final class _ActionHeader extends StatelessWidget {
  const _ActionHeader({
    required this.details,
    required this.tab,
    required this.onTabChange,
    required this.onToggle,
    required this.onEditName,
    required this.onOpenOptions,
  });

  final ActionDetails details;
  final ActionPanelTab tab;
  final ValueChanged<ActionPanelTab> onTabChange;

  /// Переключает выполнение; без него флажок выключен.
  final VoidCallback? onToggle;

  /// Открывает изменение по названию; без него название не нажимается.
  final VoidCallback? onEditName;

  /// Открывает меню параметров; без него кнопка выключена.
  final VoidCallback? onOpenOptions;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<DoableColors>()!;
    final action = details.action;
    final priority = actionDesignPriority(action.priority);
    final intentionCount = details.path.intentionCount;
    final hasArchive = actionPathHasArchive(details.path);
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
            child: ActionHead(
              goal: details.path.root.title,
              action: action.title.value,
              priority: priority,
              done: action.isCompleted,
              chain: ReasonChain(
                reasons: intentionCount,
                priority: priority,
                off: action.isCompleted,
              ),
              checkLabel: localizations.actionPanelCompletionLabel(
                action.title.value,
                localizations.actionPriorityOption(
                  actionPriorityName(priority),
                ),
              ),
              onToggle: onToggle,
              goalBadge: actionPathRootBadge(localizations, details.path.root),
              // На самой вкладке путь уже виден, и корень с цепочкой не
              // действует.
              path: switch (tab) {
                ActionPanelTab.overview => ActionHeadButton.available(
                  label: localizations.actionPanelPathButtonLabel,
                  onOpen: () => onTabChange(ActionPanelTab.path),
                ),
                ActionPanelTab.path => ActionHeadButton.unavailable(
                  label: localizations.actionPanelPathButtonLabel,
                ),
              },
              nameEdit: _button(
                localizations.detailsEditTitleLabel(action.title.value),
                onEditName,
              ),
              options: _button(
                localizations.actionPanelOptionsLabel,
                onOpenOptions,
              ),
            ),
          ),
          Tabs(
            plane: TabsPlane.sheet,
            label: localizations.actionPanelTabsLabel,
            value: tab,
            onChange: onTabChange,
            items: [
              TabItem(
                id: ActionPanelTab.overview,
                label: localizations.detailsOverviewTab,
                semanticLabel: localizations.detailsOverviewTab,
              ),
              TabItem(
                id: ActionPanelTab.path,
                label: localizations.actionPanelPathTab,
                semanticLabel: hasArchive
                    ? localizations.actionPanelPathTabArchivedLabel(
                        intentionCount,
                      )
                    : localizations.actionPanelPathTabLabel(intentionCount),
                count: intentionCount,
                icon: hasArchive ? DoableIconData.archive : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Кнопка шапки остаётся на месте и без обработчика: недоступной.
  static ActionHeadButton _button(String label, VoidCallback? onOpen) =>
      switch (onOpen) {
        final onOpen? => ActionHeadButton.available(
          label: label,
          onOpen: onOpen,
        ),
        null => ActionHeadButton.unavailable(label: label),
      };
}

/// «Обзор»: описание целиком, поля, которые меняются сразу, и строка дат.
final class _Overview extends StatelessWidget {
  const _Overview({
    required this.details,
    required this.today,
    required this.enabled,
    required this.onChange,
    required this.onOpenDescription,
  });

  final ActionDetails details;
  final CalendarDate today;

  /// Без него поля не меняются: идёт запись.
  final bool enabled;

  /// Каждый выбор значения — отдельная запись одного поля.
  final ValueChanged<ActionFieldsPatch> onChange;

  /// Открывает изменение по описанию или подсказке; без него они не
  /// нажимаются.
  final VoidCallback? onOpenDescription;

  /// Вместе с нижним полем полосы вкладок даёт 6 под областью их нажатия.
  static const double _top = 2;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final action = details.action;
    final description = action.description?.value;
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        DoableMetrics.space5,
        _top,
        DoableMetrics.space5,
        DoableMetrics.space4,
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
              onOpen: onOpenDescription,
            ),
            const SizedBox(height: DoableMetrics.space2),
            ActionPanelFields(
              date: action.date,
              schedule: action.schedule,
              priority: action.priority,
              today: today,
              enabled: enabled,
              onDateChanged: (date) =>
                  onChange(ActionFieldsPatch(date: ActionFieldSet(date))),
              onScheduleChanged: (schedule) => onChange(
                ActionFieldsPatch(schedule: ActionFieldSet(schedule)),
              ),
              onPriorityChanged: (priority) => onChange(
                ActionFieldsPatch(priority: ActionFieldSet(priority)),
              ),
            ),
            const SizedBox(height: DoableMetrics.space4),
            Padding(
              // Строка начинается вровень с названиями полей.
              padding: const EdgeInsets.symmetric(
                horizontal: DoableMetrics.space1,
              ),
              child: timestampDatesLine(
                localizations: localizations,
                locale: Localizations.localeOf(context).toLanguageTag(),
                createdAt: action.createdAt.value,
                updatedAt: action.updatedAt.value,
                currentYear: today.year,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
