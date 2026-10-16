import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/routing/app_router.gr.dart';
import '../../../design_system/components/day_heading.dart';
import '../../../graph/presentation/operation_failure_presentation.dart';
import '../../application/daily_choice_catalog.dart';
import '../../domain/calendar_date.dart';
import '../../domain/daily_choice_id.dart';
import '../../domain/daily_choice_schedule.dart';
import '../daily_choice_command_failure_message.dart';
import 'daily_choice_calendar.dart';
import 'daily_choice_calendar_day_marks_view_model.dart';
import 'daily_choice_calendar_viewport.dart';
import 'daily_choice_catalog_instance.dart';
import 'daily_choice_catalog_state.dart';
import 'daily_choice_catalog_view_model.dart';
import 'daily_choice_local_date_provider.dart';
import 'daily_choice_local_day_observer.dart';

/// Содержимое каталога без каркаса страницы.
///
/// Страница создаёт и удерживает [instance], передавая его также в [ObjectKey].
/// Тело владеет просмотром календаря, наблюдателем местного дня и хранилищем
/// прокрутки; модели выбранного дня, выдачи и отметок живут с этим экземпляром.
final class DailyChoiceCatalogBody extends ConsumerStatefulWidget {
  const DailyChoiceCatalogBody({required this.instance, super.key});

  final DailyChoiceCatalogInstance instance;

  @override
  ConsumerState<DailyChoiceCatalogBody> createState() =>
      _DailyChoiceCatalogBodyState();
}

final class _DailyChoiceCatalogBodyState
    extends ConsumerState<DailyChoiceCatalogBody> {
  /// Просматриваемый период календаря.
  ///
  /// Выбранной датой владеет модель, а просмотром — тело каталога: он один раз
  /// начинается с недели выбранной даты. Выбор дня переносит в этот день дату
  /// просмотра, сохраняя представление; ответы хранилища и ошибки просмотр не
  /// меняют.
  late DailyChoiceCalendarViewport _viewport;

  /// Изолирует смещение прокрутки от других экземпляров каталога.
  final _pageStorage = PageStorageBucket();

  /// Единственная прокрутка выдачи; календарь стоит над ней.
  /// Контроллер живёт с телом:
  /// https://api.flutter.dev/flutter/widgets/ScrollController-class.html
  final _scrollController = ScrollController();

  /// Текущий местный день, отмеченный в календаре и заголовке дня.
  ///
  /// Тело перечитывает его при создании, возвращении приложения в
  /// активное состояние и наступлении следующей местной даты. Новый день
  /// только перестраивает календарь и заголовок: выбранная дата, просмотр,
  /// секции и выдача остаются прежними.
  late final DailyChoiceLocalDayObserver _localDay;

  @override
  void initState() {
    super.initState();
    _viewport = DailyChoiceCalendarViewport(
      focusedDate: widget.instance.initialDate,
      mode: DailyChoiceCalendarMode.week,
    );
    _localDay = DailyChoiceLocalDayObserver(
      readLocalDay: ref.read(dailyChoiceLocalDateSourceProvider),
      onTodayChanged: () => setState(() {}),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _localDay.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final provider = dailyChoiceCatalogViewModelProvider(widget.instance);
    // Только новый выбранный день возвращает выдачу к началу:
    // https://riverpod.dev/docs/concepts2/refs#reflisten
    ref.listen(provider.select((state) => state.selection.date), (
      previous,
      next,
    ) {
      if (previous != next && _scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
    final state = ref.watch(provider);
    final model = ref.read(provider.notifier);
    final selectedDate = state.selection.date;
    final date = DateTime.utc(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
    );
    final locale = Localizations.localeOf(context).toLanguageTag();
    final weekday = DateFormat.EEEE(locale).format(date);
    final dayMarks = ref.watch(
      dailyChoiceCalendarDayMarksViewModelProvider(widget.instance),
    );
    return PageStorage(
      bucket: _pageStorage,
      child: SafeArea(
        // Календарь определяет свою высоту; выдаче остаётся остальное место:
        // https://api.flutter.dev/flutter/widgets/Column-class.html
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: DailyChoiceCalendar(
                selectedDate: state.selection.date,
                viewport: _viewport,
                today: _localDay.today,
                dayStatusForDate: (date) =>
                    dayMarks.dayStatuses?.statuses[date],
                hasDayMarksReadFailure: dayMarks.hasReadFailure,
                onDateSelected: (date) => _selectDate(model, date),
                onViewportChanged: _setViewport,
                onMonthSelectionCompleted: (viewport) => _setViewport(
                  viewport,
                  reason: DailyChoiceCalendarViewportUpdateReason
                      .monthSelectionCompleted,
                ),
              ),
            ),
            Expanded(
              child: CustomScrollView(
                controller: _scrollController,
                key: const PageStorageKey<String>('daily-choice-catalog'),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: DayHeading(
                        weekday:
                            weekday[0].toUpperCase() + weekday.substring(1),
                        // Явный формат сохраняет порядок и не добавляет «г.»:
                        // https://pub.dev/documentation/intl/latest/intl/DateFormat-class.html
                        date: DateFormat('d MMMM y', locale).format(date),
                        todayLabel: selectedDate == _localDay.today
                            ? l10n.dailyChoiceCalendarToday
                            : null,
                      ),
                    ),
                  ),
                  ..._content(state, model, l10n),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Нажатый день становится и датой просмотра в прежнем представлении, и
  /// выбранной датой модели — синхронно, до следующего кадра. Повторный выбор
  /// того же дня только возвращает к нему просмотр.
  void _selectDate(DailyChoiceCatalogViewModel model, CalendarDate date) {
    _setViewport(_viewport.withFocusedDate(date));
    model.selectDate(date);
  }

  void _setViewport(
    DailyChoiceCalendarViewport viewport, {
    DailyChoiceCalendarViewportUpdateReason reason =
        DailyChoiceCalendarViewportUpdateReason.ordinary,
  }) {
    setState(() => _viewport = viewport);
    ref
        .read(
          dailyChoiceCalendarDayMarksViewModelProvider(widget.instance)
              .notifier,
        )
        .setViewport(viewport, reason: reason);
  }

  /// Слайверы согласованной пары под заголовком дня.
  List<Widget> _content(
    DailyChoiceCatalogState state,
    DailyChoiceCatalogViewModel model,
    AppLocalizations l10n,
  ) {
    final loaded = state is DailyChoiceCatalogLoaded ? state : null;
    return [
      if (loaded != null)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Semantics(
              liveRegion: true,
              child: Text(l10n.dailyChoiceCatalogTotalCount(loaded.totalCount)),
            ),
          ),
        ),
      if (loaded?.freshness == DailyChoiceCatalogFreshness.refreshing)
        SliverToBoxAdapter(
          child: _Banner(
            message: l10n.dailyChoiceCatalogRefreshing,
            loading: true,
          ),
        ),
      if (loaded?.freshness == DailyChoiceCatalogFreshness.stale)
        SliverToBoxAdapter(
          child: _Banner(
            message: _failureMessage(loaded!.refreshFailure!, l10n),
            onRetry:
                loaded.refreshFailure is DailyChoiceCatalogUnavailableFailure
                ? model.retryRefresh
                : null,
          ),
        ),
      for (final isCompleted in [false, true]) ...[
        SliverToBoxAdapter(
          child: Semantics(
            header: true,
            expanded: state.selection.isExpanded(isCompleted),
            child: ListTile(
              key: ValueKey('daily-choice-section-$isCompleted'),
              title: Text(
                isCompleted
                    ? l10n.dailyChoiceCatalogCompleted
                    : l10n.dailyChoiceCatalogIncomplete,
              ),
              trailing: Icon(
                state.selection.isExpanded(isCompleted)
                    ? Icons.expand_less
                    : Icons.expand_more,
              ),
              onTap: () => model.toggleSection(isCompleted),
            ),
          ),
        ),
        if (loaded != null && state.selection.isExpanded(isCompleted))
          ..._section(loaded, isCompleted, model, l10n),
      ],
      if (state is DailyChoiceCatalogInitialLoad)
        _SliverStatus(
          _Status(message: l10n.dailyChoiceCatalogLoading, loading: true),
        ),
      if (state case DailyChoiceCatalogInitialFailure(
        :final failure,
        :final canRetry,
      ))
        _SliverStatus(
          _Status(
            message: _failureMessage(failure, l10n),
            onRetry: canRetry ? model.retryFirstPage : null,
          ),
        ),
      if (loaded?.totalCount == 0)
        _SliverStatus(_Status(message: l10n.dailyChoiceCatalogEmpty)),
    ];
  }

  List<Widget> _section(
    DailyChoiceCatalogLoaded state,
    bool isCompleted,
    DailyChoiceCatalogViewModel model,
    AppLocalizations l10n,
  ) {
    final section = state.section(isCompleted);
    final indices = {
      for (var index = 0; index < section.items.length; index++)
        ValueKey(section.items[index].id): index,
    };
    return [
      SliverList.builder(
        itemCount: section.items.length,
        // При смене порядка Flutter находит карточку по идентификатору:
        // https://api.flutter.dev/flutter/widgets/SliverChildBuilderDelegate/findChildIndexCallback.html
        findChildIndexCallback: (key) => indices[key],
        itemBuilder: (context, index) {
          final item = section.items[index];
          final number =
              index + 1 + (isCompleted ? state.incomplete.items.length : 0);
          final phrase = l10n.dailyChoiceDetailsPhrase(
            item.source.title,
            item.selected.title,
          );
          final date = item.date.toCanonicalString();
          final completion = item.isCompleted
              ? l10n.dailyChoiceDetailsCompleted
              : l10n.dailyChoiceDetailsNotCompleted;
          void open() =>
              context.router.push(DailyChoiceDetailsRoute(choiceId: item.id));
          final schedule = switch (item.schedule) {
            DailyChoiceAllDay() => l10n.dailyChoiceAllDay,
            DailyChoiceTime(:final hour, :final minute) => TimeOfDay(
              hour: hour,
              minute: minute,
            ).format(context),
          };
          final priority = l10n.dailyChoicePriorityOption(
            item.priority.name.toUpperCase(),
          );
          final pathCount = l10n.dailyChoiceCatalogPathIntentionCount(
            item.pathIntentionCount,
          );
          final startsGroup =
              index == 0 || section.items[index - 1].schedule != item.schedule;
          final showGroup =
              startsGroup &&
              (item.schedule is DailyChoiceTime || section.hasTimedChoices);
          return _CompletionSurface(
            key: ValueKey(item.id),
            id: item.id,
            model: model,
            builder: (changeCompletion) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showGroup)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Semantics(
                      container: true,
                      header: true,
                      child: Text(
                        schedule,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  ),
                // Сначала читаются данные карточки, затем отдельный флажок:
                // https://api.flutter.dev/flutter/semantics/SemanticsProperties/sortKey.html
                Semantics(
                  container: true,
                  explicitChildNodes: true,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Semantics(
                          key: ValueKey('daily-choice-row-$number'),
                          sortKey: const OrdinalSortKey(0),
                          container: true,
                          button: true,
                          label: [
                            l10n.dailyChoiceCatalogRowLabel(
                              number,
                              phrase,
                              date,
                              completion,
                            ),
                            schedule,
                            priority,
                            pathCount,
                            if (item.description case final description?)
                              description.value,
                          ].join('\n'),
                          onTap: open,
                          child: ExcludeSemantics(
                            child: ListTile(
                              title: Text(phrase),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    '${l10n.dailyChoiceDetailsDate(date)} · $completion',
                                  ),
                                  Text(schedule),
                                  Text(priority),
                                  Text(pathCount),
                                  if (item.description case final description?)
                                    // Ограничение относится только к карточке:
                                    // https://api.flutter.dev/flutter/widgets/Text/maxLines.html
                                    Text(
                                      description.value,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                              onTap: open,
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 8, right: 8),
                        // Флажок остаётся вне исключённого содержимого открытия:
                        // https://api.flutter.dev/flutter/material/Checkbox-class.html
                        child: Semantics(
                          sortKey: const OrdinalSortKey(1),
                          child: Checkbox(
                            key: ValueKey(
                              'daily-choice-completion-${item.id.toCanonicalString()}',
                            ),
                            semanticLabel: l10n
                                .dailyChoiceCatalogCompletionLabel(
                                  number,
                                  phrase,
                                  date,
                                ),
                            value: item.isCompleted,
                            onChanged: state.canChangeCompletion(item.id)
                                ? (_) => changeCompletion(!item.isCompleted)
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (state.completionOperations[item.id] case final operation?)
                  _completionFeedback(
                    item.id,
                    item.isCompleted,
                    operation,
                    model,
                    l10n,
                    changeCompletion,
                  ),
              ],
            ),
          );
        },
      ),
      if (section.nextCursor != null)
        SliverToBoxAdapter(child: _pageFooter(state, isCompleted, model, l10n)),
    ];
  }

  Widget _completionFeedback(
    DailyChoiceId id,
    bool isCompleted,
    DailyChoiceCompletionOperation operation,
    DailyChoiceCatalogViewModel model,
    AppLocalizations l10n,
    ValueChanged<bool> changeCompletion,
  ) => switch (operation) {
    DailyChoiceCompletionSubmitting() => _Banner(
      message: l10n.dailyChoiceCompletionSaving,
      loading: true,
    ),
    DailyChoiceCompletionAwaitingSnapshot() => _Banner(
      message: l10n.dailyChoiceCompletionSynchronizing,
      loading: true,
    ),
    // Сообщение и его повтор принадлежат только сессии, получившей отказ;
    // вернувшейся карточке остаётся действие, без которого флажок недоступен.
    DailyChoiceCompletionFailed(
      :final failure,
      :final inline,
      :final canRetry,
      :final requiresRefresh,
    )
        when (inline?.session.isOpen ?? false) || requiresRefresh =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (inline != null && inline.session.isOpen) ...[
              OperationFailurePresentation(
                claim: inline.claim,
                message: dailyChoiceCommandFailureMessage(l10n, failure),
              ),
              if (canRetry)
                TextButton(
                  onPressed: () => changeCompletion(!isCompleted),
                  child: Text(l10n.commonRetry),
                ),
            ],
            if (requiresRefresh)
              TextButton(
                onPressed: () => model.refreshCompletion(id),
                child: Text(l10n.dailyChoiceCompletionRefresh),
              ),
          ],
        ),
      ),
    DailyChoiceCompletionFailed() => const SizedBox.shrink(),
  };

  Widget _pageFooter(
    DailyChoiceCatalogLoaded state,
    bool isCompleted,
    DailyChoiceCatalogViewModel model,
    AppLocalizations l10n,
  ) => switch (state.section(isCompleted).pageStatus) {
    DailyChoiceCatalogPageLoading() => _Status(
      message: l10n.dailyChoiceCatalogLoadingMore,
      loading: true,
    ),
    DailyChoiceCatalogPageFailure(:final failure, :final canRetry) => _Status(
      message: _failureMessage(failure, l10n),
      onRetry: canRetry
          ? () => model.retryLoadMore(isCompleted: isCompleted)
          : null,
    ),
    DailyChoiceCatalogPageIdle() => Center(
      child: TextButton(
        key: ValueKey('daily-choice-load-more-$isCompleted'),
        onPressed: state.freshness == DailyChoiceCatalogFreshness.current
            ? () => model.loadMore(isCompleted: isCompleted)
            : null,
        child: Text(l10n.dailyChoiceCatalogLoadMore),
      ),
    ),
  };

  String _failureMessage(
    DailyChoiceCatalogReadFailure failure,
    AppLocalizations l10n,
  ) => switch (failure) {
    DailyChoiceCatalogUnavailableFailure() =>
      l10n.dailyChoiceCatalogUnavailable,
    DailyChoiceCatalogCorruptionFailure() => l10n.dailyChoiceCatalogCorruption,
    DailyChoiceCatalogSnapshotExpired() => l10n.dailyChoiceCatalogExpired,
    DailyChoiceCatalogUnexpectedFailure() => l10n.dailyChoiceCatalogUnexpected,
  };
}

/// Состояние без строк выдачи занимает остаток высоты под секциями.
final class _SliverStatus extends StatelessWidget {
  const _SliverStatus(this.status);

  final _Status status;

  @override
  Widget build(BuildContext context) =>
      SliverFillRemaining(hasScrollBody: false, child: status);
}

final class _Status extends StatelessWidget {
  const _Status({required this.message, this.loading = false, this.onRetry});

  final String message;
  final bool loading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading) const CircularProgressIndicator(),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null)
              TextButton(
                onPressed: onRetry,
                child: Text(AppLocalizations.of(context).commonRetry),
              ),
          ],
        ),
      ),
    ),
  );
}

final class _Banner extends StatelessWidget {
  const _Banner({required this.message, this.loading = false, this.onRetry});

  final String message;
  final bool loading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          if (loading)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: Text(AppLocalizations.of(context).commonRetry),
            ),
        ],
      ),
    ),
  );
}

/// Карточка удерживает только право будущей ошибки в своей экранной сессии;
/// команда живёт в координаторе.
final class _CompletionSurface extends StatefulWidget {
  const _CompletionSurface({
    required this.id,
    required this.model,
    required this.builder,
    super.key,
  });

  final DailyChoiceId id;
  final DailyChoiceCatalogViewModel model;
  final Widget Function(ValueChanged<bool> changeCompletion) builder;

  @override
  State<_CompletionSurface> createState() => _CompletionSurfaceState();
}

final class _CompletionSurfaceState extends State<_CompletionSurface> {
  DailyChoiceCompletionSession? _session;
  VoidCallback? _releasePresentation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Скрытая вкладка и маршрут под непрозрачным отключают тикеры, оставляя
    // карточку в дереве; уход с экрана завершает её сессию:
    // https://api.flutter.dev/flutter/widgets/TickerMode/valuesOf.html
    if (!TickerMode.valuesOf(context).enabled) _closeSession();
  }

  @override
  void dispose() {
    // Освобождаем право даже до построения первого сообщения ошибки:
    // https://api.flutter.dev/flutter/widgets/State/dispose.html
    _closeSession();
    super.dispose();
  }

  void _closeSession() {
    _session?.close();
    _session = null;
    _releasePresentation?.call();
    _releasePresentation = null;
  }

  @override
  Widget build(BuildContext context) {
    // Маршрут может перестать быть верхним раньше, чем отключатся тикеры:
    // https://api.flutter.dev/flutter/widgets/Route/isCurrent.html
    final route = ModalRoute.of(context);
    return widget.builder((isCompleted) {
      _releasePresentation?.call();
      _releasePresentation = widget.model.changeCompletion(
        widget.id,
        isCompleted,
        session: _session ??= DailyChoiceCompletionSession(
          isCurrent: () => route?.isCurrent ?? true,
        ),
      );
    });
  }
}
