import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/routing/app_router.gr.dart';
import '../../../intention/domain/intention_id.dart';
import '../../application/daily_choice_catalog.dart';
import '../../domain/calendar_date.dart';
import '../path/choice_path_page.dart';
import 'daily_choice_calendar.dart';
import 'daily_choice_calendar_viewport.dart';
import 'daily_choice_catalog_state.dart';
import 'daily_choice_catalog_view_model.dart';
import 'daily_choice_local_date_provider.dart';
import 'daily_choice_local_day_observer.dart';

/// Высота кнопки создания дневного выбора вместе с отступами над нижним краем.
const _createActionExtent = 56 + 2 * kFloatingActionButtonMargin;

@RoutePage()
final class DailyChoiceCatalogPage extends ConsumerStatefulWidget {
  const DailyChoiceCatalogPage({super.key});

  @override
  ConsumerState<DailyChoiceCatalogPage> createState() =>
      _DailyChoiceCatalogPageState();
}

final class _DailyChoiceCatalogPageState
    extends ConsumerState<DailyChoiceCatalogPage> {
  /// Просматриваемый период календаря.
  ///
  /// Выбранной датой владеет модель, а просмотром — страница: он один раз
  /// начинается с недели выбранной даты. Выбор дня переносит в этот день дату
  /// просмотра, сохраняя представление; ответы хранилища и ошибки просмотр не
  /// меняют.
  late DailyChoiceCalendarViewport _viewport;

  /// Текущий местный день, отмеченный в календаре.
  ///
  /// Страница перечитывает его при создании, возвращении приложения в
  /// активное состояние и наступлении следующей местной даты. Новый день
  /// только перестраивает календарь: выбранная дата, просмотр, фильтры и
  /// выдача остаются прежними.
  late final DailyChoiceLocalDayObserver _localDay;

  @override
  void initState() {
    super.initState();
    _viewport = DailyChoiceCalendarViewport(
      focusedDate: ref.read(dailyChoiceCatalogViewModelProvider).selection.date,
      mode: DailyChoiceCalendarMode.week,
    );
    _localDay = DailyChoiceLocalDayObserver(
      readLocalDay: ref.read(dailyChoiceLocalDateSourceProvider),
      onTodayChanged: () => setState(() {}),
    );
  }

  @override
  void dispose() {
    _localDay.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(dailyChoiceCatalogViewModelProvider);
    final model = ref.read(dailyChoiceCatalogViewModelProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.appDestinationDailyChoices)),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('daily-choice-create-from-action'),
        onPressed: () => unawaited(_chooseAction()),
        icon: const Icon(Icons.add),
        label: Text(l10n.dailyChoiceCreateFromAction),
      ),
      // Календарь, фильтры, количество, полосы обновления и выдача
      // прокручиваются вместе: прокрученная до конца выдача получает всю
      // высоту тела страницы, а место под кнопкой создания остаётся последним
      // элементом. Календарь стоит вне ветвления по состоянию выдачи и
      // доступен при загрузке, пустоте и любом отказе.
      body: SafeArea(
        child: CustomScrollView(
          // Как прокрутки других корневых страниц, общая прокрутка хранит
          // смещение в хранилище страниц маршрута под постоянным ключом.
          // Страницы календаря хранятся в его собственном хранилище и эту
          // запись не заменяют.
          key: const PageStorageKey<String>('daily-choice-catalog'),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: DailyChoiceCalendar(
                  selectedDate: state.selection.date,
                  viewport: _viewport,
                  today: _localDay.today,
                  onDateSelected: (date) => _selectDate(model, date),
                  onViewportChanged: (viewport) =>
                      setState(() => _viewport = viewport),
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
                    SizedBox(
                      key: const ValueKey('daily-choice-completion-filter'),
                      width: 240,
                      child: DropdownButtonFormField<bool?>(
                        key: ValueKey(state.selection.isCompleted),
                        initialValue: state.selection.isCompleted,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: l10n.dailyChoiceCatalogCompletionFilter,
                        ),
                        items: [
                          DropdownMenuItem<bool?>(
                            value: null,
                            child: Text(l10n.dailyChoiceCatalogAllStates),
                          ),
                          DropdownMenuItem<bool?>(
                            value: false,
                            child: Text(l10n.dailyChoiceCatalogIncomplete),
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
    );
  }

  Future<void> _chooseAction() async {
    final actionId = await context.router.push<IntentionId>(
      const DailyChoiceActionPickerRoute(),
    );
    if (!mounted || actionId == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ChoicePathPage.fromAction(actionIntentionId: actionId),
      ),
    );
  }

  /// Нажатый день становится и датой просмотра в прежнем представлении, и
  /// выбранной датой модели — синхронно, до следующего кадра. Повторный выбор
  /// того же дня только возвращает к нему просмотр.
  void _selectDate(DailyChoiceCatalogViewModel model, CalendarDate date) {
    setState(() => _viewport = _viewport.withFocusedDate(date));
    model.selectDate(date);
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
        SliverPadding(
          // Место под кнопку создания дневного выбора: прокрученные до конца
          // последняя строка и продолжение выдачи стоят над ней.
          padding: const EdgeInsets.only(bottom: _createActionExtent),
          sliver: SliverList.builder(
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
              void open() => context.router.push(
                DailyChoiceDetailsRoute(choiceId: item.id),
              );
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
    DailyChoiceCatalogValidationFailure() => l10n.dailyChoiceCatalogInvalid,
    DailyChoiceCatalogUnexpectedFailure() => l10n.dailyChoiceCatalogUnexpected,
  };
}

/// Состояние без строк выдачи занимает остаток высоты под фильтрами и стоит
/// над местом под кнопкой создания дневного выбора.
final class _SliverStatus extends StatelessWidget {
  const _SliverStatus(this.status);

  final _Status status;

  @override
  Widget build(BuildContext context) => SliverFillRemaining(
    hasScrollBody: false,
    child: Padding(
      padding: const EdgeInsets.only(bottom: _createActionExtent),
      child: status,
    ),
  );
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
