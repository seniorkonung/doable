import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/action_row.dart';
import '../../../design_system/components/add_row.dart';
import '../../../design_system/components/count_tiles.dart';
import '../../../design_system/components/empty_state.dart';
import '../../../design_system/components/list_state.dart';
import '../../../design_system/components/notice.dart';
import '../../../design_system/doable_colors.dart';
import '../../../design_system/doable_metrics.dart';
import '../../../design_system/doable_type.dart';
import '../../../intention/domain/intention_id.dart';
import '../../../intention/presentation/details/intention_page_target.dart';
import '../../../shared/domain/calendar_date.dart';
import '../../application/action_list_item.dart';
import '../../application/intention_actions.dart';
import '../../domain/action_schedule.dart';
import '../panel/action_field_labels.dart';
import '../panel/action_panel.dart';
import 'intention_actions_state.dart';
import 'intention_actions_view_model.dart';

/// Вкладка «Действия» страницы намерения: три плитки ролей намерения в путях
/// действий и порционный список действий выбранной роли по группам дат.
///
/// Единственный sliver сохраняет ленивое построение строк внутри общего
/// scrollable страницы, а подгрузка следует за построенным подвалом списка.
/// Флажок строки только показывает выполнение: действие выполняют на экране
/// дня и в панели.
final class IntentionActionsSliver extends ConsumerStatefulWidget {
  const IntentionActionsSliver({
    required this.intentionId,
    required this.pageInstance,
    required this.today,
    this.onAdd,
    super.key,
  });

  final IntentionId intentionId;
  final IntentionPageInstance pageInstance;

  /// Местный день, от которого считаются группы и слова «Сегодня» и «Завтра».
  final CalendarDate today;
  final VoidCallback? onAdd;

  @override
  ConsumerState<IntentionActionsSliver> createState() =>
      _IntentionActionsSliverState();
}

final class _IntentionActionsSliverState
    extends ConsumerState<IntentionActionsSliver> {
  static const double _listEndSpace = 24;

  IntentionActionsViewModelProvider get _provider =>
      intentionActionsViewModelProvider(
        widget.intentionId,
        widget.pageInstance,
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(_provider);
    final model = ref.read(_provider.notifier);
    final counts = state.counts;
    final role = switch (state) {
      IntentionActionsLoaded(:final role) => role,
      IntentionActionsInitialLoad(:final role) ||
      IntentionActionsInitialFailure(:final role) => role,
      IntentionActionsHidden() => null,
    };
    return SliverMainAxisGroup(
      slivers: [
        if (widget.onAdd case final onAdd?)
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: DoableMetrics.space5,
            ),
            sliver: SliverToBoxAdapter(
              child: AddRow.addOnly(
                addText: l10n.detailsActionsAdd,
                addLabel: l10n.detailsActionsAddLabel,
                onAdd: onAdd,
              ),
            ),
          ),
        if (counts != null)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              DoableMetrics.space5,
              DoableMetrics.space2,
              DoableMetrics.space5,
              DoableMetrics.space1,
            ),
            sliver: SliverToBoxAdapter(
              child: _RoleTiles(
                counts: counts,
                selected: role ?? counts.busiestRole,
                onSelect: model.selectRole,
              ),
            ),
          ),
        ...switch (state) {
          IntentionActionsHidden() || IntentionActionsInitialLoad() => [
            _status(ListState.loading(text: l10n.detailsActionsLoading)),
          ],
          final IntentionActionsInitialFailure failure => [
            _status(
              ListState.error(
                message: _failureMessage(failure.failure, l10n),
                retry: failure.canRetry
                    ? (
                        label: l10n.commonRetry,
                        onPressed: () => unawaited(model.retryFirstPage()),
                      )
                    : null,
              ),
            ),
          ],
          final IntentionActionsLoaded loaded => _loaded(loaded, model, l10n),
        },
      ],
    );
  }

  SliverPadding _status(Widget status) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(
      DoableMetrics.space5,
      DoableMetrics.space4,
      DoableMetrics.space5,
      0,
    ),
    sliver: SliverToBoxAdapter(child: status),
  );

  List<Widget> _loaded(
    IntentionActionsLoaded state,
    IntentionActionsViewModel model,
    AppLocalizations l10n,
  ) => [
    switch (state.freshness) {
      IntentionActionsCurrent() => const SliverToBoxAdapter(),
      IntentionActionsRefreshing() => _status(
        ListState.refreshing(text: l10n.detailsActionsRefreshing),
      ),
      IntentionActionsStale(:final failure) => _status(
        Notice.content(
          message: Semantics(
            container: true,
            liveRegion: true,
            child: Text(_failureMessage(failure, l10n)),
          ),
          action: state.canRetryRefresh
              ? (
                  label: l10n.commonRetry,
                  onPressed: () => unawaited(model.retryRefresh()),
                )
              : null,
        ),
      ),
    },
    if (state.items.isEmpty)
      SliverFillRemaining(
        hasScrollBody: false,
        child: _EmptyRole(role: state.role),
      )
    else ...[
      SliverList.builder(
        itemCount: state.items.length + (state.nextCursor == null ? 0 : 1),
        // При смене состава Flutter находит строку по идентификатору:
        // https://api.flutter.dev/flutter/widgets/SliverChildBuilderDelegate/findChildIndexCallback.html
        findChildIndexCallback: (key) {
          if (key is! ValueKey<String>) return null;
          final index = state.items.indexWhere(
            (item) =>
                'intention-actions-item-${item.id.toCanonicalString()}' ==
                key.value,
          );
          return index < 0 ? null : index;
        },
        itemBuilder: (context, index) {
          if (index == state.items.length) {
            _requestPage(model);
            return _pageFooter(state, model, l10n);
          }
          return _buildRow(context, state, index, l10n);
        },
      ),
      const SliverToBoxAdapter(child: SizedBox(height: _listEndSpace)),
    ],
  ];

  Widget _buildRow(
    BuildContext context,
    IntentionActionsLoaded state,
    int index,
    AppLocalizations l10n,
  ) {
    final item = state.items[index];
    final today = widget.today;
    final group = _GroupKey.of(item.date, today);
    final startsGroup =
        index == 0 || _GroupKey.of(state.items[index - 1].date, today) != group;
    final when = _whenLine(context, item, today, group);
    final number = index + 1;
    final action = item.title.value;
    final priority = l10n.actionPriorityOption(
      actionPriorityName(actionDesignPriority(item.priority)),
    );
    // Под ролью «Корневое» корень пути — сама страница.
    final root = state.role == IntentionActionRole.root ? null : item.rootTitle;
    return Padding(
      key: ValueKey('intention-actions-item-${item.id.toCanonicalString()}'),
      padding: EdgeInsets.fromLTRB(
        DoableMetrics.space5,
        index == 0
            ? DoableMetrics.space2
            : startsGroup
            ? DoableMetrics.space4
            : DoableMetrics.space2,
        DoableMetrics.space5,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 6,
        children: [
          if (startsGroup) _GroupHeading(group: group, today: today),
          ActionRow(
            openKey: ValueKey(
              'intention-actions-row-${item.id.toCanonicalString()}',
            ),
            checkKey: ValueKey(
              'intention-actions-check-${item.id.toCanonicalString()}',
            ),
            goal: root,
            when: when,
            action: action,
            description: item.description?.value,
            priority: actionDesignPriority(item.priority),
            reasons: item.pathIntentionCount,
            done: item.isCompleted,
            checkLabel: l10n.actionDayCompletionLabel(number, action, priority),
            label: [
              l10n.actionDayRowLabel(number, action),
              if (item.description case final description?) description.value,
              ?(root == null ? null : l10n.actionDayRowRoot(root)),
              l10n.actionDayPathIntentionCount(item.pathIntentionCount),
              when,
              item.isCompleted ? l10n.actionCompleted : l10n.actionNotCompleted,
            ].join('\n'),
            onOpen: () => unawaited(showActionPanel(context, item.id)),
          ),
        ],
      ),
    );
  }

  /// Первая линия строки: дата, а у действия на час — ещё и время.
  /// Слова «Сегодня», «Завтра» и «Вчера» стоят вместо даты; остальные даты
  /// называют день недели и число, а в первой группе — ещё месяц и чужой год.
  String _whenLine(
    BuildContext context,
    ActionListItem item,
    CalendarDate today,
    _GroupKey group,
  ) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final date = _utc(item.date);
    final day = switch (date.difference(_utc(today)).inDays) {
      0 => l10n.actionDateToday,
      1 => l10n.actionDateTomorrow,
      -1 => l10n.actionDateYesterday,
      // https://pub.dev/documentation/intl/latest/intl/DateFormat-class.html
      _ => DateFormat(switch (group) {
        _TodayAndLater() when item.date.year == today.year => 'EEE d MMM',
        _TodayAndLater() => 'EEE d MMM y',
        _EarlierMonth() => 'EEE d',
      }, locale).format(date),
    };
    return switch (item.schedule) {
      ActionAllDay() => day,
      ActionAtHour() => '$day · ${actionTimeValue(context, item.schedule)}',
    };
  }

  /// Подвал — последний элемент ленивого списка, поэтому его построение
  /// означает, что конец загруженной части подошёл к видимой области. Модель
  /// сама пропускает запрос при устаревшей или занятой части.
  void _requestPage(IntentionActionsViewModel model) {
    // https://api.flutter.dev/flutter/scheduler/SchedulerBinding/addPostFrameCallback.html
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(model.loadMore());
    });
  }

  /// Устаревшая часть не запрашивает порцию и не обновляется сама, поэтому
  /// кольцо в её подвале вращалось бы вечно: отказ обновления стоит выше.
  Widget _pageFooter(
    IntentionActionsLoaded state,
    IntentionActionsViewModel model,
    AppLocalizations l10n,
  ) => Padding(
    key: const ValueKey('intention-actions-page-footer'),
    padding: const EdgeInsets.fromLTRB(
      DoableMetrics.space5,
      DoableMetrics.space4,
      DoableMetrics.space5,
      0,
    ),
    child: switch (state.page) {
      IntentionActionsPageFailure(:final failure, :final canRetry) =>
        ListState.error(
          message: _failureMessage(failure, l10n),
          retry: canRetry
              ? (
                  label: l10n.commonRetry,
                  onPressed: () => unawaited(model.retryLoadMore()),
                )
              : null,
        ),
      IntentionActionsPageIdle() || IntentionActionsPageLoading()
          when state.freshness is IntentionActionsCurrent =>
        ListState.more(text: l10n.detailsActionsLoadingMore),
      IntentionActionsPageIdle() ||
      IntentionActionsPageLoading() => const SizedBox.shrink(),
    },
  );
}

String _failureMessage(
  IntentionActionsReadFailure failure,
  AppLocalizations l10n,
) => switch (failure) {
  IntentionActionsUnavailableFailure() => l10n.detailsActionsUnavailable,
  IntentionActionsCorruptionFailure() => l10n.detailsActionsCorruption,
  IntentionActionsSnapshotExpired() => l10n.detailsActionsExpired,
  IntentionActionsUnexpectedFailure() => l10n.detailsActionsUnexpected,
};

DateTime _utc(CalendarDate date) =>
    DateTime.utc(date.year, date.month, date.day);

/// Группа списка: сегодняшний и более поздние дни вместе, затем месяцы
/// более ранних дат.
sealed class _GroupKey {
  const _GroupKey();

  factory _GroupKey.of(CalendarDate date, CalendarDate today) =>
      !_utc(date).isBefore(_utc(today))
      ? const _TodayAndLater()
      : _EarlierMonth(year: date.year, month: date.month);

  @override
  bool operator ==(Object other) => switch ((this, other)) {
    (_TodayAndLater(), _TodayAndLater()) => true,
    (_EarlierMonth a, _EarlierMonth b) =>
      a.year == b.year && a.month == b.month,
    _ => false,
  };

  @override
  int get hashCode => switch (this) {
    _TodayAndLater() => 0,
    _EarlierMonth(:final year, :final month) => Object.hash(year, month),
  };
}

final class _TodayAndLater extends _GroupKey {
  const _TodayAndLater();
}

final class _EarlierMonth extends _GroupKey {
  const _EarlierMonth({required this.year, required this.month});

  final int year;
  final int month;
}

final class _GroupHeading extends StatelessWidget {
  const _GroupHeading({required this.group, required this.today});

  final _GroupKey group;
  final CalendarDate today;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final title = switch (group) {
      _TodayAndLater() => AppLocalizations.of(
        context,
      ).detailsActionsTodayAndLater,
      _EarlierMonth(:final year, :final month) => _capitalized(
        // https://pub.dev/documentation/intl/latest/intl/DateFormat-class.html
        DateFormat(
          year == today.year ? 'LLLL' : 'LLLL y',
          locale,
        ).format(DateTime.utc(year, month)),
      ),
    };
    return Semantics(
      container: true,
      header: true,
      child: Text(
        title,
        style: DoableType.label.copyWith(
          color: Theme.of(context).extension<DoableColors>()!.muted,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

String _capitalized(String text) =>
    text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

/// Три плитки ролей намерения в путях действий.
final class _RoleTiles extends StatelessWidget {
  const _RoleTiles({
    required this.counts,
    required this.selected,
    required this.onSelect,
  });

  final IntentionActionCounts counts;
  final IntentionActionRole selected;
  final ValueChanged<IntentionActionRole> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return CountTiles<IntentionActionRole>(
      columns: CountTileColumns.three,
      value: selected,
      onPick: onSelect,
      label: l10n.detailsActionsRolesLabel,
      tiles: [
        for (final role in IntentionActionRole.values)
          CountTile(
            key: ValueKey('intention-actions-role-${role.name}'),
            id: role,
            count: counts.countOf(role),
            name: _roleName(l10n, role),
            semanticLabel: l10n.detailsActionsRoleTileSemantic(
              _roleName(l10n, role),
              counts.countOf(role),
            ),
          ),
      ],
    );
  }
}

String _roleName(AppLocalizations l10n, IntentionActionRole role) =>
    switch (role) {
      IntentionActionRole.root => l10n.detailsActionsRoleRoot,
      IntentionActionRole.intermediate => l10n.detailsActionsRoleIntermediate,
      IntentionActionRole.terminal => l10n.detailsActionsRoleFinal,
    };

/// Объяснение пустой плитки: какое действие здесь появится.
final class _EmptyRole extends StatelessWidget {
  const _EmptyRole({required this.role});

  final IntentionActionRole role;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return EmptyState(
      title: l10n.detailsActionsEmptyTitle,
      text: switch (role) {
        IntentionActionRole.root => l10n.detailsActionsEmptyRoot,
        IntentionActionRole.intermediate =>
          l10n.detailsActionsEmptyIntermediate,
        IntentionActionRole.terminal => l10n.detailsActionsEmptyFinal,
      },
      textMaxWidth: 270,
      spaceAbove: DoableMetrics.space6,
      spaceBelow: DoableMetrics.space6,
      pretty: true,
    );
  }
}
