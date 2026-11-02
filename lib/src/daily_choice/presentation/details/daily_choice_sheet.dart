import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart' hide Badge, TextField;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/routing/app_router.gr.dart';
import '../../../design_system/components/badge.dart';
import '../../../design_system/components/choice_head.dart';
import '../../../design_system/components/choice_path.dart';
import '../../../design_system/components/detail_row.dart';
import '../../../design_system/components/half_pinned_sliver.dart';
import '../../../design_system/components/list_state.dart';
import '../../../design_system/components/notice.dart';
import '../../../design_system/components/option_row.dart';
import '../../../design_system/components/options_menu.dart';
import '../../../design_system/components/priority_picker.dart';
import '../../../design_system/components/reason_chain.dart';
import '../../../design_system/components/sheet.dart';
import '../../../design_system/components/tabs.dart';
import '../../../design_system/components/text_field.dart';
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
import '../../domain/calendar_date.dart';
import '../../domain/daily_choice_id.dart';
import '../catalog/daily_choice_local_date_provider.dart';
import '../catalog/daily_choice_local_day_observer.dart';
import '../daily_choice_command_failure_message.dart';
import 'daily_choice_delete_confirmation.dart';
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
/// Флажок шапки выключен на время записи, а новое значение приходит из
/// подписки. Отказ стоит над содержимым обеих вкладок и остаётся за панелью,
/// пока она открыта, даже перекрытая страницей.
Future<void> showDailyChoiceSheet(
  BuildContext context,
  DailyChoiceId choiceId,
) => showDoableSheet<void>(
  context: context,
  hostsMessages: true,
  builder: (_, sheet) => _DailyChoiceSheet(sheet, choiceId: choiceId),
);

enum _ChoiceTab { overview, path }

enum _ChoiceOption { edit, delete }

final class _DailyChoiceSheet extends ConsumerStatefulWidget {
  const _DailyChoiceSheet(this.sheet, {required this.choiceId});

  final SheetPresentation sheet;
  final DailyChoiceId choiceId;

  @override
  ConsumerState<_DailyChoiceSheet> createState() => _DailyChoiceSheetState();
}

final class _DailyChoiceSheetState extends ConsumerState<_DailyChoiceSheet> {
  late final DailyChoiceDetailsViewModel _model;

  /// Сегодняшний день для подписи даты: панель может оставаться открытой
  /// после местной полуночи, и тогда «Сегодня» стало бы неверным.
  late final DailyChoiceLocalDayObserver _localDay;

  var _tab = _ChoiceTab.overview;

  @override
  void initState() {
    super.initState();
    _model = DailyChoiceDetailsViewModel(
      ref.read(personalGraphRepositoryProvider),
      ref.read(graphCommandCoordinatorProvider.notifier),
      widget.choiceId,
    );
    _localDay = DailyChoiceLocalDayObserver(
      readLocalDay: ref.read(dailyChoiceLocalDateSourceProvider),
      onTodayChanged: () => setState(() {}),
    );
  }

  @override
  void dispose() {
    _localDay.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _showOptions() async {
    final l10n = AppLocalizations.of(context);
    final option = await showDoableSheet<_ChoiceOption>(
      context: context,
      builder: (_, sheet) => OptionsMenu<_ChoiceOption>(
        sheet,
        title: l10n.dailyChoiceDetailsTitle,
        items: [
          OptionsMenuItem(
            value: _ChoiceOption.edit,
            icon: DoableIconData.edit,
            name: l10n.dailyChoiceEditTitle,
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
    if (_model.operation is DailyChoiceDetailsOperationWriting) return;
    final state = _model.state;
    if (state is! DailyChoiceDetailsLoaded || state.details.path.isEmpty) {
      return;
    }
    switch (option) {
      case _ChoiceOption.edit:
        await context.router.push(DailyChoiceEditRoute(details: state.details));
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
        if (deleted && mounted && (ModalRoute.isCurrentOf(context) ?? false)) {
          Navigator.of(context).pop();
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
      builder: (context, _) => Sheet.expandableUntitled(
        widget.sheet,
        label: localizations.dailyChoiceDetailsTitle,
        expandLabel: localizations.dailyChoiceSheetExpand,
        collapseLabel: localizations.dailyChoiceSheetCollapse,
        slivers: switch (_model.state) {
          DailyChoiceDetailsLoading() => [
            _StateSliver(
              ListState.loading(text: localizations.dailyChoiceDetailsLoading),
            ),
          ],
          DailyChoiceDetailsNotFound() => [
            _StateSliver(
              ListState.error(
                message: localizations.dailyChoiceDetailsNotFound,
              ),
            ),
          ],
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
          DailyChoiceDetailsLoaded(:final details) when details.path.isEmpty =>
            [_corruption(localizations)],
          DailyChoiceDetailsLoaded(:final details) => [
            HalfPinnedSliver(
              child: _ChoiceHeader(
                details: details,
                tab: _tab,
                onTabChange: (tab) => setState(() => _tab = tab),
                onOptions:
                    _model.operation is DailyChoiceDetailsOperationWriting
                    ? null
                    : () => unawaited(_showOptions()),
                onToggle: _model.operation is DailyChoiceDetailsOperationWriting
                    ? null
                    : () => _model.change(
                        DailyChoiceFieldsPatch(
                          isCompleted: DailyChoiceFieldSet(
                            !details.choice.isCompleted,
                          ),
                        ),
                      ),
              ),
            ),
            if (_model.operation
                case final DailyChoiceDetailsOperationFailed operation)
              _OperationFailureNotice(operation),
            ...switch (_tab) {
              _ChoiceTab.overview => [
                _Overview(details: details, today: _localDay.today),
              ],
              _ChoiceTab.path => [_Path(details: details)],
            },
          ],
        },
      ),
    );
  }

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

/// Шапка выбора и вкладки. Тело проходит под закреплённым срезом, поэтому фон
/// непрозрачный.
final class _ChoiceHeader extends StatelessWidget {
  const _ChoiceHeader({
    required this.details,
    required this.tab,
    required this.onTabChange,
    required this.onToggle,
    required this.onOptions,
  });

  final DailyChoiceDetails details;
  final _ChoiceTab tab;
  final ValueChanged<_ChoiceTab> onTabChange;

  /// Переключает выполнение; без него флажок выключен.
  final VoidCallback? onToggle;
  final VoidCallback? onOptions;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<DoableColors>()!;
    final choice = details.choice;
    final priority = dailyChoiceDesignPriority(choice.priority);
    final steps = details.path.length;
    final hasArchive = _hasArchive(details);
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
              options: onOptions == null
                  ? ChoiceHeadOptions.unavailable(
                      label: localizations.dailyChoiceSheetOptionsLabel,
                    )
                  : ChoiceHeadOptions.available(
                      label: localizations.dailyChoiceSheetOptionsLabel,
                      onOpen: onOptions!,
                    ),
            ),
          ),
          Tabs(
            plane: TabsPlane.sheet,
            label: localizations.dailyChoiceSheetTabsLabel,
            value: tab,
            onChange: onTabChange,
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
                    ? localizations.dailyChoiceSheetPathTabArchivedLabel(steps)
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

/// Вкладка «Обзор»: описание целиком и поля, которые пока только показывают
/// значения.
final class _Overview extends StatelessWidget {
  const _Overview({required this.details, required this.today});

  final DailyChoiceDetails details;
  final CalendarDate today;

  /// Последняя пилюля приоритета выходит за край содержимого.
  static const double _pickerShift = 2;

  /// Вместе с нижним полем полосы вкладок даёт 6 под областью их нажатия.
  static const double _top = 2;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final choice = details.choice;
    final time = dailyChoiceTimeValue(context, choice.schedule);
    final priority = dailyChoiceDesignPriority(choice.priority);
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
            if (choice.description case final description?) ...[
              TextField.saved(
                value: description.value,
                placeholder: localizations.detailsAddDescription,
                label: description.value,
                onOpen: null,
              ),
              const SizedBox(height: DoableMetrics.space2),
            ],
            DetailRow(
              label: localizations.dailyChoiceFieldDate,
              icon: DoableIconData.calendar,
              value: dailyChoiceDateValue(context, choice.date, today: today),
              valueLabel: localizations.dailyChoiceFieldDateLabel(
                dailyChoiceFullDate(context, choice.date),
              ),
            ),
            DetailRow(
              label: localizations.dailyChoiceFieldTime,
              icon: DoableIconData.clock,
              value: time,
              valueLabel: localizations.dailyChoiceTimeLabel(time),
            ),
            DetailRow.slot(
              label: localizations.dailyChoicePriorityLabel,
              shift: _pickerShift,
              child: PriorityPicker(
                value: priority,
                onChange: null,
                label: localizations.dailyChoicePriorityLabel,
                name: dailyChoicePriorityName,
                itemLabel: (priority) =>
                    dailyChoicePriorityItemLabel(localizations, priority),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
