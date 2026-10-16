import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/routing/app_router.gr.dart';
import '../../../design_system/components/day_heading.dart';
import '../../../design_system/doable_metrics.dart';
import '../../application/daily_choice_catalog.dart';
import '../../domain/calendar_date.dart';
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
  /// фильтры и выдача остаются прежними.
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
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _CompletionFilter(
                            label: l10n.dailyChoiceCatalogCompletionFilter,
                            field: DropdownButtonFormField<bool?>(
                              key: ValueKey(state.selection.isCompleted),
                              initialValue: state.selection.isCompleted,
                              isExpanded: true,
                              // Выбранное состояние переносится и растягивает поле
                              // по высоте вместо обрезки по одной строке.
                              isDense: false,
                              items: [
                                DropdownMenuItem<bool?>(
                                  value: null,
                                  child: Text(l10n.dailyChoiceCatalogAllStates),
                                ),
                                DropdownMenuItem<bool?>(
                                  value: false,
                                  child: Text(
                                    l10n.dailyChoiceCatalogIncomplete,
                                  ),
                                ),
                                DropdownMenuItem<bool?>(
                                  value: true,
                                  child: Text(l10n.dailyChoiceCatalogCompleted),
                                ),
                              ],
                              onChanged: model.selectCompletion,
                            ),
                          ),
                          TextButton(
                            key: const ValueKey('daily-choice-clear-filters'),
                            onPressed: model.clearFilters,
                            child: Text(l10n.dailyChoiceCatalogClearFilters),
                          ),
                        ],
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

  /// Слайверы выдачи под фильтрами.
  List<Widget> _content(
    DailyChoiceCatalogState state,
    DailyChoiceCatalogViewModel model,
    AppLocalizations l10n,
  ) => switch (state) {
    DailyChoiceCatalogInitialLoad() => [
      _SliverStatus(
        _Status(message: l10n.dailyChoiceCatalogLoading, loading: true),
      ),
    ],
    DailyChoiceCatalogInitialFailure(:final failure, :final canRetry) => [
      _SliverStatus(
        _Status(
          message: _failureMessage(failure, l10n),
          onRetry: canRetry ? model.retryFirstPage : null,
        ),
      ),
    ],
    DailyChoiceCatalogEmpty() => _loaded(state, model, l10n),
    DailyChoiceCatalogLoaded() => _loaded(state, model, l10n),
  };

  List<Widget> _loaded(
    DailyChoiceCatalogLoaded state,
    DailyChoiceCatalogViewModel model,
    AppLocalizations l10n,
  ) {
    final isRefreshing =
        state.freshness == DailyChoiceCatalogFreshness.refreshing;
    final isStale = state.freshness == DailyChoiceCatalogFreshness.stale;
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Semantics(
            liveRegion: true,
            child: Text(l10n.dailyChoiceCatalogTotalCount(state.totalCount)),
          ),
        ),
      ),
      if (isRefreshing)
        SliverToBoxAdapter(
          child: _Banner(
            message: l10n.dailyChoiceCatalogRefreshing,
            loading: true,
          ),
        ),
      if (isStale)
        SliverToBoxAdapter(
          child: _Banner(
            message: _failureMessage(state.refreshFailure!, l10n),
            onRetry:
                state.refreshFailure is DailyChoiceCatalogUnavailableFailure
                ? model.retryRefresh
                : null,
          ),
        ),
      if (state.items.isEmpty)
        _SliverStatus(_Status(message: l10n.dailyChoiceCatalogEmpty))
      else
        SliverList.builder(
          itemCount: state.items.length + (state.nextCursor == null ? 0 : 1),
          itemBuilder: (context, index) {
            if (index == state.items.length) {
              return _pageFooter(state, model, l10n);
            }
            final item = state.items[index];
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
            return Semantics(
              key: ValueKey('daily-choice-row-${index + 1}'),
              button: true,
              label: l10n.dailyChoiceCatalogRowLabel(
                index + 1,
                phrase,
                date,
                completion,
              ),
              onTap: open,
              child: ExcludeSemantics(
                child: ListTile(
                  title: Text(phrase),
                  subtitle: Text(
                    '${l10n.dailyChoiceDetailsDate(date)} · $completion',
                  ),
                  onTap: open,
                ),
              ),
            );
          },
        ),
    ];
  }

  Widget _pageFooter(
    DailyChoiceCatalogLoaded state,
    DailyChoiceCatalogViewModel model,
    AppLocalizations l10n,
  ) => switch (state.pageStatus) {
    DailyChoiceCatalogPageLoading() => _Status(
      message: l10n.dailyChoiceCatalogLoadingMore,
      loading: true,
    ),
    DailyChoiceCatalogPageFailure(:final failure, :final canRetry) => _Status(
      message: _failureMessage(failure, l10n),
      onRetry: canRetry ? model.retryLoadMore : null,
    ),
    DailyChoiceCatalogPageIdle() => Center(
      child: TextButton(
        key: const ValueKey('daily-choice-load-more'),
        onPressed: state.freshness == DailyChoiceCatalogFreshness.current
            ? model.loadMore
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

/// Фильтр выполнения: название фильтра над полем выбора состояния.
///
/// Плавающая подпись поля ввода рассчитана на одну строку и при крупном
/// тексте обрезается, поэтому название стоит отдельной переносимой строкой.
/// Для вспомогательных технологий название и выбранное состояние — одна
/// кнопка выбора. Ширина при обычном тексте вмещает самое длинное состояние
/// в одну строку и растёт вместе с системным размером текста до ширины
/// страницы; дальше название и состояние переносятся.
final class _CompletionFilter extends StatelessWidget {
  const _CompletionFilter({required this.label, required this.field});

  final String label;
  final Widget field;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: SizedBox(
        // Ширина больше доступной ограничивается шириной ряда фильтров.
        width: MediaQuery.textScalerOf(context).scale(280),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            KeyedSubtree(
              key: const ValueKey('daily-choice-completion-filter'),
              child: field,
            ),
          ],
        ),
      ),
    );
  }
}

/// Состояние без строк выдачи занимает остаток высоты под фильтрами.
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
