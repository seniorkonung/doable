import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent, ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/action_row.dart';
import '../../../design_system/components/day_heading.dart';
import '../../../design_system/components/empty_state.dart';
import '../../../design_system/components/list_state.dart';
import '../../../design_system/components/notice.dart';
import '../../../design_system/components/scroll_top_button.dart';
import '../../../design_system/components/section_header.dart';
import '../../../design_system/doable_colors.dart';
import '../../../design_system/doable_icon.dart';
import '../../../design_system/doable_metrics.dart';
import '../../../design_system/doable_priority.dart';
import '../../../design_system/doable_type.dart';
import '../../../graph/presentation/operation_failure_presentation.dart';
import '../../../shared/domain/calendar_date.dart';
import '../../../shared/presentation/local_day/local_date_provider.dart';
import '../../../shared/presentation/local_day/local_day_observer.dart';
import '../../application/daily_choice_catalog.dart';
import '../../domain/daily_choice_id.dart';
import '../../domain/daily_choice_priority.dart';
import '../../domain/daily_choice_schedule.dart';
import '../daily_choice_command_failure_message.dart';
import '../details/daily_choice_field_labels.dart';
import '../details/daily_choice_sheet.dart';
import 'daily_choice_calendar.dart';
import 'daily_choice_calendar_day_marks_view_model.dart';
import 'daily_choice_calendar_viewport.dart';
import 'daily_choice_catalog_instance.dart';
import 'daily_choice_catalog_state.dart';
import 'daily_choice_catalog_view_model.dart';

/// Строит каркас страницы вокруг [body] и кнопки возврата к началу.
///
/// [scrollTopButton] равна `null`, пока кнопка не нужна. Она стоит в слоте
/// плавающей кнопки `Scaffold` страницы: тогда сообщение встаёт над ней, а
/// вложенный `Scaffold` показал бы сообщение второй раз.
typedef DailyChoiceCatalogScaffoldBuilder = Widget Function(
  Widget body,
  Widget? scrollTopButton,
);

/// Содержимое каталога; каркас страницы строит [scaffoldBuilder].
///
/// Страница создаёт и удерживает [instance], передавая его также в [ObjectKey].
/// Тело владеет просмотром календаря, наблюдателем местного дня и хранилищем
/// прокрутки; модели выбранного дня, выдачи и отметок живут с этим экземпляром.
final class DailyChoiceCatalogBody extends ConsumerStatefulWidget {
  const DailyChoiceCatalogBody({
    required this.instance,
    required this.scaffoldBuilder,
    super.key,
  });

  final DailyChoiceCatalogInstance instance;
  final DailyChoiceCatalogScaffoldBuilder scaffoldBuilder;

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

  _CalendarTransitionScrollSnapshot? _scrollSnapshot;

  /// Выдача прокручена дальше высоты своей видимой области.
  var _isPastViewport = false;

  /// Плавный возврат к началу выдачи.
  static const _returnToStartDuration = Duration(milliseconds: 300);

  /// Свободное место под последней строкой выдачи.
  static const double _listEndSpace = 72;

  /// Запас построения строк за краем выдачи: подвал секции строится и
  /// запрашивает порцию, когда конец её загруженной части подошёл на это
  /// расстояние.
  static const double _pageRequestDistance = 160;

  /// Текущий местный день, отмеченный в календаре и заголовке дня.
  ///
  /// Тело перечитывает его при создании, возвращении приложения в
  /// активное состояние и наступлении следующей местной даты. Новый день
  /// только перестраивает календарь и заголовок: выбранная дата, просмотр,
  /// секции и выдача остаются прежними.
  late final LocalDayObserver _localDay;

  @override
  void initState() {
    super.initState();
    _viewport = DailyChoiceCalendarViewport(
      focusedDate: widget.instance.initialDate,
      mode: DailyChoiceCalendarMode.week,
    );
    _localDay = LocalDayObserver(
      readLocalDay: ref.read(localDateSourceProvider),
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
    ref.listen(provider, (previous, next) {
      if (_scrollSnapshot != null && !_hasSameScrollContent(previous, next)) {
        _scrollSnapshot = null;
      }
      if (previous?.selection.date != next.selection.date &&
          _scrollController.hasClients) {
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
    final body = PageStorage(
      bucket: _pageStorage,
      child: SafeArea(
        // Календарь определяет свою высоту; выдаче остаётся остальное место:
        // https://api.flutter.dev/flutter/widgets/Column-class.html
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: DoableMetrics.space4),
              child: DailyChoiceCalendar(
                selectedDate: state.selection.date,
                viewport: _viewport,
                today: _localDay.today,
                dayStatusForDate: (date) =>
                    dayMarks.dayStatuses?.statuses[date],
                hasDayMarksReadFailure: dayMarks.hasReadFailure,
                onDateSelected: (date) => _selectDate(model, date),
                onViewportChanged: _setViewport,
                onExpansionTransitionStarted: _rememberScrollPosition,
                onExpansionTransitionEnded: _restoreScrollPosition,
                onMonthSelectionCompleted: (viewport) => _setViewport(
                  viewport,
                  reason: DailyChoiceCalendarViewportUpdateReason
                      .monthSelectionCompleted,
                ),
              ),
            ),
            Expanded(
              // Календарь и новая выдача двигают границу и без прокрутки:
              // https://api.flutter.dev/flutter/widgets/ScrollMetricsNotification-class.html
              child: NotificationListener<ScrollMetricsNotification>(
                onNotification: _onScrollMetricsNotification,
                child: NotificationListener<ScrollNotification>(
                  onNotification: _onScrollNotification,
                  child: CustomScrollView(
                    controller: _scrollController,
                    physics: const _CalendarResizeScrollPhysics(),
                    // https://api.flutter.dev/flutter/widgets/ScrollView/scrollCacheExtent.html
                    scrollCacheExtent: const ScrollCacheExtent.pixels(
                      _pageRequestDistance,
                    ),
                    key: const PageStorageKey<String>('daily-choice-catalog'),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            DoableMetrics.space5,
                            DoableMetrics.space4,
                            DoableMetrics.space5,
                            0,
                          ),
                          child: DayHeading(
                            weekday:
                                weekday[0].toUpperCase() + weekday.substring(1),
                            // Явный формат сохраняет порядок и не добавляет
                            // «г.»:
                            // https://pub.dev/documentation/intl/latest/intl/DateFormat-class.html
                            date: DateFormat('d MMMM y', locale).format(date),
                            todayLabel: selectedDate == _localDay.today
                                ? l10n.dailyChoiceCalendarToday
                                : null,
                            trailing: _refreshLine(state, l10n),
                          ),
                        ),
                      ),
                      ..._content(state, model, l10n),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return widget.scaffoldBuilder(
      body,
      _isPastViewport
          ? ScrollTopButton(
              label: l10n.dailyChoiceCatalogScrollToTop,
              onPressed: _returnToStart,
            )
          : null,
    );
  }

  /// Строка обновления занимает место всегда, поэтому её появление не меняет
  /// заголовок дня и не двигает выдачу.
  ///
  /// Сохранение размера требует сохранить анимацию, поэтому вне обновления
  /// кольцо останавливает отдельный [TickerMode]: иначе скрытая строка
  /// запрашивала бы кадры постоянно.
  /// https://api.flutter.dev/flutter/widgets/Visibility/maintainSize.html
  Widget _refreshLine(DailyChoiceCatalogState state, AppLocalizations l10n) {
    final isRefreshing =
        state is DailyChoiceCatalogLoaded &&
        state.freshness == DailyChoiceCatalogFreshness.refreshing;
    return Visibility(
      visible: isRefreshing,
      maintainState: true,
      maintainAnimation: true,
      maintainSize: true,
      child: TickerMode(
        enabled: isRefreshing,
        child: ListState.refreshing(text: l10n.dailyChoiceCatalogRefreshing),
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
    _scrollSnapshot = null;
    setState(() => _viewport = viewport);
    ref
        .read(
          dailyChoiceCalendarDayMarksViewModelProvider(widget.instance)
              .notifier,
        )
        .setViewport(viewport, reason: reason);
  }

  void _rememberScrollPosition() {
    _scrollSnapshot = _scrollController.hasClients
        ? _CalendarTransitionScrollSnapshot(
            mode: _viewport.mode,
            offset: _scrollController.offset,
          )
        : null;
  }

  /// Новая цель, как и прокрутка пользователя, отменяет отложенное
  /// восстановление позиции после перехода календаря.
  void _returnToStart() {
    _scrollSnapshot = null;
    if (MediaQuery.disableAnimationsOf(context)) {
      _scrollController.jumpTo(0);
    } else {
      unawaited(
        _scrollController.animateTo(
          0,
          duration: _returnToStartDuration,
          curve: Curves.easeOut,
        ),
      );
    }
  }

  void _updatePastViewport(ScrollMetrics metrics) {
    final isPastViewport = metrics.pixels > metrics.viewportDimension;
    if (isPastViewport != _isPastViewport) {
      setState(() => _isPastViewport = isPastViewport);
    }
  }

  bool _onScrollMetricsNotification(ScrollMetricsNotification notification) {
    if (notification.depth == 0) _updatePastViewport(notification.metrics);
    return false;
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollUpdateNotification) {
      _updatePastViewport(notification.metrics);
    }
    final snapshot = _scrollSnapshot;
    if (snapshot == null) return false;
    // Коррекция геометрии не является пользовательской прокруткой:
    // https://api.flutter.dev/flutter/widgets/UserScrollNotification-class.html
    final isUserScroll = switch (notification) {
      ScrollStartNotification(:final dragDetails) => dragDetails != null,
      UserScrollNotification(:final direction) =>
        direction != ScrollDirection.idle,
      // Инерция продолжает пользовательскую прокрутку без dragDetails.
      // Изменение высоты согласует _CalendarResizeScrollPhysics, поэтому
      // геометрический возврат не создаёт здесь обновлений со старым направлением.
      // https://api.flutter.dev/flutter/widgets/ScrollEndNotification/dragDetails.html
      ScrollUpdateNotification(:final dragDetails) =>
        dragDetails != null ||
            _scrollController.position.userScrollDirection !=
                ScrollDirection.idle,
      _ => false,
    };
    if (isUserScroll) {
      // Новая цель отменяет отложенное восстановление старой, но сохраняет
      // исходное представление до итога удерживаемого перехода календаря.
      _scrollSnapshot = _CalendarTransitionScrollSnapshot(
        mode: snapshot.mode,
        offset: notification.metrics.pixels,
      );
    }
    return false;
  }

  void _restoreScrollPosition(DailyChoiceCalendarMode mode) {
    final snapshot = _scrollSnapshot;
    if (snapshot == null) return;
    if (snapshot.mode != mode) {
      _scrollSnapshot = null;
      return;
    }
    // Окончательные границы известны после раскладки с исходной высотой:
    // https://api.flutter.dev/flutter/scheduler/SchedulerBinding/addPostFrameCallback.html
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_scrollSnapshot, snapshot)) return;
      _scrollSnapshot = null;
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      final offset = snapshot.offset.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (position.pixels != offset) _scrollController.jumpTo(offset);
    });
  }

  /// Слайверы согласованной пары под заголовком дня.
  ///
  /// Заголовки секций стоят только над подтверждёнными данными: пока их нет
  /// или день пуст, под заголовком дня стоит одно состояние.
  List<Widget> _content(
    DailyChoiceCatalogState state,
    DailyChoiceCatalogViewModel model,
    AppLocalizations l10n,
  ) => switch (state) {
    DailyChoiceCatalogInitialLoad() => [
      _status(ListState.loading(text: l10n.dailyChoiceCatalogLoading)),
    ],
    DailyChoiceCatalogInitialFailure(:final failure, :final canRetry) => [
      _status(
        ListState.error(
          message: _failureMessage(failure, l10n),
          retry: canRetry
              ? (label: l10n.commonRetry, onPressed: model.retryFirstPage)
              : null,
        ),
      ),
    ],
    final DailyChoiceCatalogLoaded loaded => _loadedContent(
      loaded,
      model,
      l10n,
    ),
  };

  SliverPadding _status(Widget status) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(
      DoableMetrics.space5,
      DoableMetrics.space4,
      DoableMetrics.space5,
      0,
    ),
    sliver: SliverToBoxAdapter(child: status),
  );

  List<Widget> _loadedContent(
    DailyChoiceCatalogLoaded state,
    DailyChoiceCatalogViewModel model,
    AppLocalizations l10n,
  ) => [
    if (state.refreshFailure case final failure?)
      _status(
        Notice.content(
          message: Semantics(
            container: true,
            liveRegion: true,
            child: Text(_failureMessage(failure, l10n)),
          ),
          action: state.canRetryRefresh
              ? (label: l10n.commonRetry, onPressed: model.retryRefresh)
              : null,
        ),
      ),
    if (state.totalCount == 0)
      SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyState(
          icon: DoableIconData.calendar,
          title: l10n.dailyChoiceCatalogEmptyTitle,
          text: l10n.dailyChoiceCatalogEmptyText,
        ),
      )
    else ...[
      for (final isCompleted in [false, true]) ...[
        SliverToBoxAdapter(
          child: Padding(
            // Второй заголовок стоит на 2 ниже строк первой секции.
            padding: EdgeInsets.fromLTRB(
              DoableMetrics.space5,
              isCompleted ? 2 : 0,
              DoableMetrics.space5,
              0,
            ),
            child: SectionHeader(
              key: ValueKey('daily-choice-section-$isCompleted'),
              title: isCompleted
                  ? l10n.dailyChoiceCatalogCompleted
                  : l10n.dailyChoiceCatalogIncomplete,
              count: state.section(isCompleted).totalCount,
              open: state.selection.isExpanded(isCompleted),
              onToggle: () => model.toggleSection(isCompleted),
            ),
          ),
        ),
        if (state.selection.isExpanded(isCompleted))
          ..._section(state, isCompleted, model, l10n),
      ],
      const SliverToBoxAdapter(child: SizedBox(height: _listEndSpace)),
    ],
  ];

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
        itemCount: section.items.length + (section.nextCursor == null ? 0 : 1),
        // При смене порядка Flutter находит карточку по идентификатору:
        // https://api.flutter.dev/flutter/widgets/SliverChildBuilderDelegate/findChildIndexCallback.html
        findChildIndexCallback: (key) => indices[key],
        itemBuilder: (context, index) {
          if (index == section.items.length) {
            _requestPage(model, isCompleted);
            return _pageFooter(state, isCompleted, model, l10n);
          }
          final item = section.items[index];
          final number =
              index + 1 + (isCompleted ? state.incomplete.items.length : 0);
          final action = item.selected.title;
          final completion = item.isCompleted
              ? l10n.dailyChoiceDetailsCompleted
              : l10n.dailyChoiceDetailsNotCompleted;
          void open() => unawaited(showDailyChoiceSheet(context, item.id));
          final schedule = dailyChoiceTimeValue(context, item.schedule);
          final priority = l10n.dailyChoicePriorityOption(
            item.priority.name.toUpperCase(),
          );
          final steps = item.pathIntentionCount - 1;
          final startsGroup =
              index == 0 || section.items[index - 1].schedule != item.schedule;
          final showGroup =
              startsGroup &&
              (item.schedule is DailyChoiceTime || state.hasTimedChoices);
          final gap = index == 0
              ? 0.0
              : startsGroup
              ? DoableMetrics.space4
              : DoableMetrics.space2;
          return _CompletionSurface(
            key: ValueKey(item.id),
            id: item.id,
            model: model,
            builder: (changeCompletion) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    DoableMetrics.space5,
                    gap,
                    DoableMetrics.space5,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 6,
                    children: [
                      if (showGroup)
                        Semantics(
                          container: true,
                          header: true,
                          child: Text(
                            schedule,
                            style: DoableType.label.copyWith(
                              color: Theme.of(context)
                                  .extension<DoableColors>()!
                                  .muted,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ActionRow(
                        openKey: ValueKey('daily-choice-row-$number'),
                        checkKey: ValueKey(
                          'daily-choice-completion-${item.id.toCanonicalString()}',
                        ),
                        goal: item.source.title,
                        action: action,
                        description: item.description?.value,
                        priority: switch (item.priority) {
                          DailyChoicePriority.p1 => DoablePriority.p1,
                          DailyChoicePriority.p2 => DoablePriority.p2,
                          DailyChoicePriority.p3 => DoablePriority.p3,
                          DailyChoicePriority.p4 => DoablePriority.p4,
                        },
                        reasons: steps,
                        done: item.isCompleted,
                        checkLabel: l10n.dailyChoiceCatalogCompletionLabel(
                          number,
                          action,
                          priority,
                        ),
                        label: [
                          l10n.dailyChoiceCatalogRowLabel(number, action),
                          if (item.description case final description?)
                            description.value,
                          l10n.dailyChoiceCatalogRowSource(item.source.title),
                          l10n.dailyChoiceCatalogPathStepCount(steps),
                          if (item.schedule is DailyChoiceTime)
                            l10n.dailyChoiceCatalogRowTime(schedule)
                          else
                            schedule,
                          completion,
                        ].join('\n'),
                        onToggle: state.canChangeCompletion(item.id)
                            ? () => changeCompletion(!item.isCompleted)
                            : null,
                        onOpen: open,
                      ),
                    ],
                  ),
                ),
                if (_completionNotice(
                      item,
                      state.completionOperations[item.id],
                      model,
                      l10n,
                      changeCompletion,
                    )
                    case final notice?)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      DoableMetrics.space5,
                      DoableMetrics.space2,
                      DoableMetrics.space5,
                      0,
                    ),
                    child: notice,
                  ),
              ],
            ),
          );
        },
      ),
    ];
  }

  /// Уведомление у карточки при отказе записи выполнения.
  ///
  /// Пока запись и согласование идут, под карточкой ничего нет: флажок
  /// недоступен, а строки не сдвигаются. Уведомление несёт одно действие:
  /// повтор при доказанно временном отказе, иначе актуализацию. Сообщение и
  /// повтор принадлежат только сессии, получившей отказ; вернувшейся карточке
  /// остаётся действие, без которого флажок недоступен.
  Widget? _completionNotice(
    DailyChoiceCatalogItem item,
    DailyChoiceCompletionOperation? operation,
    DailyChoiceCatalogViewModel model,
    AppLocalizations l10n,
    ValueChanged<bool> changeCompletion,
  ) {
    final refresh = (
      label: l10n.dailyChoiceCompletionRefresh,
      onPressed: () => model.refreshCompletion(item.id),
    );
    return switch (operation) {
      null ||
      DailyChoiceCompletionSubmitting() ||
      DailyChoiceCompletionAwaitingSnapshot() => null,
      DailyChoiceCompletionFailed(
        :final failure,
        :final inline,
        :final canRetry,
      )
          when inline != null && inline.session.isOpen =>
        Notice.content(
          message: OperationFailurePresentation(
            claim: inline.claim,
            message: dailyChoiceCommandFailureMessage(l10n, failure),
            inheritsColor: true,
          ),
          action: canRetry
              ? (
                  label: l10n.commonRetry,
                  onPressed: () => changeCompletion(!item.isCompleted),
                )
              : refresh,
        ),
      DailyChoiceCompletionFailed(requiresRefresh: true) => Notice.content(
        message: const SizedBox.shrink(),
        action: refresh,
      ),
      DailyChoiceCompletionFailed() => null,
    };
  }

  /// Подвал — последний элемент ленивого списка, поэтому его построение
  /// означает, что конец загруженной части подошёл к видимой области. Модель
  /// сама пропускает запрос при неактуальной выдаче или занятой порции, а
  /// каждая новая выдача заново строит подвал на виду.
  void _requestPage(DailyChoiceCatalogViewModel model, bool isCompleted) {
    // https://api.flutter.dev/flutter/scheduler/SchedulerBinding/addPostFrameCallback.html
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(model.loadMore(isCompleted: isCompleted));
    });
  }

  /// Устаревшая выдача не запрашивает порцию и не обновляется сама, поэтому
  /// кольцо в её подвале вращалось бы вечно: пока есть отказ обновления,
  /// подвал показывает его, а повтор несёт только доказанно временный.
  Widget _pageFooter(
    DailyChoiceCatalogLoaded state,
    bool isCompleted,
    DailyChoiceCatalogViewModel model,
    AppLocalizations l10n,
  ) => Padding(
    key: ValueKey('daily-choice-page-footer-$isCompleted'),
    padding: const EdgeInsets.fromLTRB(
      DoableMetrics.space5,
      DoableMetrics.space4,
      DoableMetrics.space5,
      0,
    ),
    child: switch ((
      state.refreshFailure,
      state.section(isCompleted).pageStatus,
    )) {
      (final failure?, _) => ListState.error(
        message: _failureMessage(failure, l10n),
        retry: state.canRetryRefresh
            ? (label: l10n.commonRetry, onPressed: model.retryRefresh)
            : null,
      ),
      (null, DailyChoiceCatalogPageFailure(:final failure, :final canRetry)) =>
        ListState.error(
          message: _failureMessage(failure, l10n),
          retry: canRetry
              ? (
                  label: l10n.commonRetry,
                  onPressed: () =>
                      unawaited(model.retryLoadMore(isCompleted: isCompleted)),
                )
              : null,
        ),
      (null, DailyChoiceCatalogPageIdle() || DailyChoiceCatalogPageLoading()) =>
        ListState.more(text: l10n.dailyChoiceCatalogLoadingMore),
    },
  );

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

/// Согласует рост области выдачи с её позицией до перезапуска инерции.
final class _CalendarResizeScrollPhysics extends ScrollPhysics {
  const _CalendarResizeScrollPhysics({super.parent});

  @override
  _CalendarResizeScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _CalendarResizeScrollPhysics(parent: buildParent(ancestor));

  @override
  double adjustPositionForNewDimensions({
    required ScrollMetrics oldPosition,
    required ScrollMetrics newPosition,
    required bool isScrolling,
    required double velocity,
  }) {
    final adjusted = super.adjustPositionForNewDimensions(
      oldPosition: oldPosition,
      newPosition: newPosition,
      isScrolling: isScrolling,
      velocity: velocity,
    );
    // RangeMaintainingScrollPhysics пропускает ограничение при инерции.
    // При сворачивании календаря применяем его через correctPixels в раскладке,
    // без ScrollUpdateNotification и пружинного возврата со старым направлением.
    // Движение внутри диапазона остаётся у штатной физики Flutter.
    // https://api.flutter.dev/flutter/widgets/ScrollPhysics/adjustPositionForNewDimensions.html
    if (newPosition.viewportDimension > oldPosition.viewportDimension &&
        newPosition.maxScrollExtent < oldPosition.maxScrollExtent) {
      return adjusted.clamp(
        newPosition.minScrollExtent,
        newPosition.maxScrollExtent,
      );
    }
    return adjusted;
  }
}

/// Идентичность снимка не даёт отложенному возврату отменить новый переход,
/// прокрутку пользователя или изменение выдачи.
final class _CalendarTransitionScrollSnapshot {
  _CalendarTransitionScrollSnapshot({required this.mode, required this.offset});

  final DailyChoiceCalendarMode mode;
  final double offset;
}

/// Посторонняя ревизия меняет needsRebase, сохраняя строки и их раскладку.
/// Отменять восстановление должны только изменения содержимого прокрутки.
bool _hasSameScrollContent(
  DailyChoiceCatalogState? previous,
  DailyChoiceCatalogState next,
) {
  if (previous?.selection.date != next.selection.date ||
      previous?.selection.incompleteExpanded !=
          next.selection.incompleteExpanded ||
      previous?.selection.completedExpanded !=
          next.selection.completedExpanded) {
    return false;
  }
  return switch ((previous, next)) {
    (DailyChoiceCatalogLoaded before, DailyChoiceCatalogLoaded after) =>
      _hasSameSectionContent(before.incomplete, after.incomplete) &&
          _hasSameSectionContent(before.completed, after.completed) &&
          // Место строки обновления занято всегда, а отказ добавляет карточку.
          before.refreshFailure == after.refreshFailure &&
          // Отказ изменения выполнения выводится внутри карточки.
          mapEquals(before.completionOperations, after.completionOperations),
    _ => identical(previous, next),
  };
}

bool _hasSameSectionContent(
  DailyChoiceCatalogSectionState before,
  DailyChoiceCatalogSectionState after,
) =>
    listEquals(before.items, after.items) &&
    before.totalCount == after.totalCount &&
    (before.nextCursor != null) == (after.nextCursor != null) &&
    before.pageStatus == after.pageStatus;

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
