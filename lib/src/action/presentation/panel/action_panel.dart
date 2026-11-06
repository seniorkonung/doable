import 'dart:async';

import 'package:flutter/material.dart' hide TextField;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/action_head.dart';
import '../../../design_system/components/half_pinned_sliver.dart';
import '../../../design_system/components/list_state.dart';
import '../../../design_system/components/notice.dart';
import '../../../design_system/components/reason_chain.dart';
import '../../../design_system/components/sheet.dart';
import '../../../design_system/components/text_field.dart';
import '../../../design_system/doable_colors.dart';
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
import '../../domain/action_id.dart';
import '../action_command_failure_message.dart';
import 'action_field_labels.dart';
import 'action_panel_fields.dart';
import 'action_panel_state.dart';
import 'action_panel_view_model.dart';

/// Показывает действие раскрываемой панелью над текущей страницей.
///
/// Панель владеет моделью действия, поэтому её закрытие снимает подписку. Шапка
/// — первый срез тела: она закреплена, пока занимает не больше половины высоты
/// тела, а выше прокручивается вместе с ним.
///
/// Без загруженного действия вместо шапки стоит одно состояние. Закрывает лист
/// пользователь, в том числе когда действия больше нет.
///
/// Флажок шапки и поля «Обзора» выключены на время записи, а новое значение
/// приходит из подписки. Дата, время, приоритет и выполнение меняются сразу и
/// по одному полю за запись. Отказ стоит над содержимым и остаётся за панелью,
/// пока она открыта, даже перекрытая страницей. После отказа без явного
/// повтора флажок выключен, пока панель не перечитает действие.
Future<void> showActionPanel(BuildContext context, ActionId actionId) =>
    showDoableSheet<void>(
      context: context,
      hostsMessages: true,
      builder: (_, sheet) => ActionPanel(sheet, actionId: actionId),
    );

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

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: _model,
      builder: (context, _) => Sheet.expandableUntitled(
        widget.sheet,
        label: localizations.actionPanelTitle,
        expandLabel: localizations.actionPanelExpand,
        collapseLabel: localizations.actionPanelCollapse,
        slivers: switch (_model.state) {
          ActionPanelLoading() => [
            _StateSliver(
              ListState.loading(text: localizations.actionPanelLoading),
            ),
          ],
          ActionPanelNotFound() => [
            _StateSliver(
              ListState.error(message: localizations.actionOperationNotFound),
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
          ActionPanelLoaded(:final details) => _action(details),
        },
      ),
    );
  }

  /// Шапка и «Обзор». До снимка с записанным значением панель недоступна, как
  /// во время записи.
  List<Widget> _action(ActionDetails details) {
    final isWriting = switch (_model.operation) {
      ActionPanelOperationWriting() ||
      ActionPanelOperationAwaitingSnapshot() => true,
      ActionPanelOperationIdle() || ActionPanelOperationFailed() => false,
    };
    final completionLock = _model.completionLock;
    final failed = switch (_model.operation) {
      final ActionPanelOperationFailed operation => operation,
      _ => null,
    };
    return [
      HalfPinnedSliver(
        child: _ActionHeader(
          details: details,
          onToggle: isWriting || completionLock != null
              ? null
              : () => unawaited(
                  _model.change(
                    ActionFieldsPatch(
                      isCompleted: ActionFieldSet(!details.action.isCompleted),
                    ),
                  ),
                ),
        ),
      ),
      if (failed != null || completionLock != null)
        _OperationNotice(
          failed: failed,
          lockFailure: completionLock,
          onRefresh: completionLock == null ? null : _model.refresh,
        ),
      _Overview(
        details: details,
        today: _localDay.today,
        enabled: !isWriting,
        onChange: (patch) => unawaited(_model.change(patch)),
      ),
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

/// Отказ операции под шапкой. Новый отказ панель показывает сама: тело могло
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

/// Шапка действия. Тело проходит под закреплённым срезом, поэтому фон
/// непрозрачный.
final class _ActionHeader extends StatelessWidget {
  const _ActionHeader({required this.details, required this.onToggle});

  final ActionDetails details;

  /// Переключает выполнение; без него флажок выключен.
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<DoableColors>()!;
    final action = details.action;
    final priority = actionDesignPriority(action.priority);
    return ColoredBox(
      color: colors.raised,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: DoableMetrics.space5),
        child: ActionHead(
          goal: details.path.root.title,
          action: action.title.value,
          priority: priority,
          done: action.isCompleted,
          chain: ReasonChain(
            reasons: details.path.intentionCount,
            priority: priority,
            off: action.isCompleted,
          ),
          checkLabel: localizations.actionPanelCompletionLabel(
            action.title.value,
            localizations.actionPriorityOption(actionPriorityName(priority)),
          ),
          onToggle: onToggle,
        ),
      ),
    );
  }
}

/// «Обзор»: описание целиком, поля, которые меняются сразу, и строка дат.
final class _Overview extends StatelessWidget {
  const _Overview({
    required this.details,
    required this.today,
    required this.enabled,
    required this.onChange,
  });

  final ActionDetails details;
  final CalendarDate today;

  /// Без него поля не меняются: идёт запись.
  final bool enabled;

  /// Каждый выбор значения — отдельная запись одного поля.
  final ValueChanged<ActionFieldsPatch> onChange;

  /// Под шапкой без вкладок содержимое начинается так же, как под полосой
  /// вкладок.
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
              onOpen: null,
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
