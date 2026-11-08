import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/home/home_page.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/action/application/action_day.dart';
import 'package:doable/src/action/application/action_day_statuses.dart';
import 'package:doable/src/action/application/action_list_item.dart';
import 'package:doable/src/action/presentation/day/action_day_calendar.dart';
import 'package:doable/src/action/presentation/day/action_day_root_page.dart';
import 'package:doable/src/action/presentation/day/action_day_state.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:doable/src/shared/presentation/local_day/local_date_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import '../../../support/app_root_pages.dart';
import '../../../support/action_day_provider.dart';
import '../../../support/tag_read_contract_test_fallback.dart';
import '../../../support/in_memory_quick_creation_mode_store.dart';
import 'action_day_calendar_test_support.dart';
import 'action_day_page_test_support.dart';
import '../../../support/intention_holding_read_contract_test_fallback.dart';

// Обозначение сегодняшнего дня на экране дня следует за местными часами, которые
// идут вместе с поддельным временем теста: полночь, сутки перевода часов и дни
// в фоне проверяются без настоящего ожидания.
void main() {
  setUp(() {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  for (final fromMonths in [false, true]) {
    final level = fromMonths ? 'месяцев' : 'лет';
    testWidgets('местная полночь обновляет текущий период, сохраняя открытую '
        'страницу $level, выбранный день и выдачу', (tester) async {
      final selected = fromMonths ? date(2026, 9, 30) : date(2026, 12, 31);
      final clock = _LocalClock(
        tester,
        start: _local(selected.year, selected.month, selected.day, 23, 30),
      );
      final repository = _Repository();
      await _openActionDay(tester, repository, clock);
      repository.completeFirst(_items(selected), total: 40);
      await tester.pump();
      await tester.tap(find.bySemanticsLabel(_l10n.actionCalendarExpand));
      await _settle(tester);
      await tester.tap(
        find.bySemanticsLabel(_l10n.actionCalendarChooseYearAndMonth),
      );
      await tester.pumpAndSettle();
      if (fromMonths) {
        await tester.tap(find.text('2026'));
        await tester.pumpAndSettle();
      }
      final previous = fromMonths ? 'Сентябрь 2026' : '2026';
      final current = fromMonths ? 'Октябрь 2026' : '2027';
      expect(
        find.bySemanticsLabel('$previous, ${_l10n.statisticsCurrentPeriod}'),
        findsOneWidget,
      );
      _dayScroll(tester).jumpTo(200);
      await tester.pump();
      final loaded = _dayState(tester);

      await tester.pump(clock.untilNextDate);

      expect(find.text(fromMonths ? '2026' : '2020–2031'), findsOneWidget);
      expect(visibleWeeks(tester), isEmpty);
      expect(find.bySemanticsLabel(previous), findsOneWidget);
      expect(
        find.bySemanticsLabel('$current, ${_l10n.statisticsCurrentPeriod}'),
        findsOneWidget,
      );
      _expectDayUnchanged(tester, loaded);
      expect(_dayScroll(tester).pixels, 200);
      expect(repository.queries, hasLength(1));

      await tester.tap(
        find.bySemanticsLabel(_l10n.actionCalendarBackToMonthDays),
      );
      await tester.pumpAndSettle();
      expect(
        visibleWeeks(tester),
        weeksFrom(fromMonths ? date(2026, 8, 31) : date(2026, 11, 30), 6),
      );
      expect(dayCell(tester, selected).isSelected, isTrue);
      expect(repository.queries, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('в местную полночь отмечает новый сегодняшний день, не меняя '
      'выбор, просмотр, выдачу и прокрутку', (tester) async {
    final semantics = tester.ensureSemantics();
    final clock = _LocalClock(tester, start: _local(2026, 10, 6, 23, 30));
    final repository = _Repository();
    await _openActionDay(tester, repository, clock);
    expect(repository.queries.single.date, date(2026, 10, 6));
    repository.completeFirst(_items(date(2026, 10, 6)), total: 40);
    await tester.pump();

    // Пользователь смотрит невыполненные действия дня, раскрывает месяц и
    // прокручивает выдачу.
    await tester.tap(find.bySemanticsLabel(_l10n.actionCalendarExpand));
    await _settle(tester);
    expect(find.text(_l10n.actionDateToday), findsOneWidget);
    _dayScroll(tester).jumpTo(300);
    await tester.pump();

    final loaded = _dayState(tester);
    expect(loaded, isA<ActionDayLoaded>());
    expect(loaded.selection.completedExpanded, true);
    final shownWeeks = visibleWeeks(tester);
    expect(shownWeeks, weeksFrom(date(2026, 9, 28), 6));
    expect(_todayMarker(tester, date(2026, 10, 6)), findsOneWidget);

    // Подготовка заняла часть оставшегося до полуночи поддельного времени.
    await tester.pump(clock.untilNextDate - const Duration(seconds: 1));
    expect(_todayMarker(tester, date(2026, 10, 6)), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(_todayMarker(tester, date(2026, 10, 7)), findsOneWidget);
    expect(_todayMarker(tester, date(2026, 10, 6)), findsNothing);
    // Новый сегодняшний день не выбирается сам: выбор, охват, просмотр,
    // загруженная выдача и прокрутка остаются прежними, чтений нет.
    expect(visibleWeeks(tester), shownWeeks);
    _expectDayUnchanged(tester, loaded);
    expect(repository.queries, hasLength(1));
    expect(_dayScroll(tester).pixels, 300);
    // Заголовок дня строится лениво и возвращается вместе с началом выдачи.
    _dayScroll(tester).jumpTo(0);
    await tester.pump();
    expect(find.text(_l10n.actionDateToday), findsNothing);
    _expectSelected(tester, date(2026, 10, 6));
    semantics.dispose();
  });

  // Расчёт промежутка до местной полуночи на обоих переходах проверяет
  // `untilLocalDateStart` в local_date_provider_test.dart; здесь
  // проверено, что страница ждёт именно этот промежуток, а не 24 часа.
  testWidgets('при переводе часов на летнее время сутки длятся 23 часа, и '
      'сегодняшний день сменяется в их местную полночь', (tester) async {
    final semantics = tester.ensureSemantics();
    final transitionDay = date(2026, 3, 8);
    const transitionLength = Duration(hours: 23);
    final clock = _LocalClock(tester, start: _local(2026, 3, 7, 23));
    final repository = _Repository();
    await _openActionDay(tester, repository, clock);
    repository.completeFirst([], total: 0);
    await tester.pump();
    // Месяц показывает и сутки перехода, и следующую за ними дату.
    await tester.tap(find.bySemanticsLabel(_l10n.actionCalendarExpand));
    await _settle(tester);
    _expectSelected(tester, date(2026, 3, 7));

    await tester.pump(clock.untilNextDate);
    expect(_todayMarker(tester, transitionDay), findsOneWidget);

    // Следующая дата начинается не через фиксированные 24 часа, а в
    // действительную местную полночь.
    await tester.pump(transitionLength - const Duration(seconds: 1));
    expect(_todayMarker(tester, transitionDay), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(_todayMarker(tester, _nextDay(transitionDay)), findsOneWidget);
    _expectSelected(tester, date(2026, 3, 7));
    expect(repository.queries, hasLength(1));
    semantics.dispose();
  });

  testWidgets('возвращения в приложение не сдвигают местную полночь, в которую '
      'сегодняшний день сменяется', (tester) async {
    final semantics = tester.ensureSemantics();
    final clock = _LocalClock(tester, start: _local(2026, 10, 6, 21));
    final repository = _Repository();
    await _openActionDay(tester, repository, clock);
    repository.completeFirst(_items(date(2026, 10, 6)), total: 40);
    await tester.pump();
    final loaded = _dayState(tester);

    for (var resume = 1; resume <= 3; resume++) {
      await tester.pump(const Duration(minutes: 10));
      _sendToBackground(tester);
      await tester.pump(const Duration(minutes: 10));
      _returnToForeground(tester);
      await tester.pump();
      expect(_todayMarker(tester, date(2026, 10, 6)), findsOneWidget);
    }
    _expectDayUnchanged(tester, loaded);
    expect(repository.queries, hasLength(1));

    // С 22:00 до полуночи: день сменяется ровно в полночь, а не раньше.
    await tester.pump(const Duration(hours: 1, minutes: 59, seconds: 59));
    expect(_todayMarker(tester, date(2026, 10, 6)), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(_todayMarker(tester, date(2026, 10, 7)), findsOneWidget);

    await tester.pump(const Duration(hours: 23, minutes: 59, seconds: 59));
    expect(_todayMarker(tester, date(2026, 10, 7)), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(_todayMarker(tester, date(2026, 10, 8)), findsOneWidget);
    _expectSelected(tester, date(2026, 10, 6));
    _expectDayUnchanged(tester, loaded);
    expect(repository.queries, hasLength(1));
    semantics.dispose();
  });

  testWidgets('после нескольких дней приостановки в фоне возвращение '
      'отмечает день возвращения и переносит таймер', (tester) async {
    final semantics = tester.ensureSemantics();
    final clock = _LocalClock(tester, start: _local(2026, 10, 6, 22));
    final repository = _Repository();
    await _openActionDay(tester, repository, clock);
    repository.completeFirst(_items(date(2026, 10, 6)), total: 40);
    await tester.pump();
    final loaded = _dayState(tester);
    final weeks = visibleWeeks(tester);

    expect(find.text(_l10n.actionDateToday), findsOneWidget);

    // Приостановленный процесс не выполняет таймеры, а часы устройства идут:
    // процесс возвращается 9 октября в 11:00.
    _sendToBackground(tester);
    clock.suspend(const Duration(days: 2, hours: 13));
    _returnToForeground(tester);
    await tester.pump();
    expect(_todayMarker(tester, date(2026, 10, 9)), findsOneWidget);
    expect(find.text(_l10n.actionDateToday), findsNothing);
    _expectSelected(tester, date(2026, 10, 6));
    expect(visibleWeeks(tester), weeks);
    _expectDayUnchanged(tester, loaded);
    expect(repository.queries, hasLength(1));

    // Следующая смена дня — в полночь 10 октября, а не по прежнему таймеру.
    await tester.pump(const Duration(hours: 12, minutes: 59, seconds: 59));
    expect(_todayMarker(tester, date(2026, 10, 9)), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(_todayMarker(tester, date(2026, 10, 10)), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('дни, прошедшие в фоне с работающими таймерами, отмечаются при '
      'возвращении', (tester) async {
    final semantics = tester.ensureSemantics();
    final clock = _LocalClock(tester, start: _local(2026, 10, 6, 22));
    final repository = _Repository();
    await _openActionDay(tester, repository, clock);
    repository.completeFirst([], total: 0);
    await tester.pump();

    _sendToBackground(tester);
    // Три местные полуночи прошли в фоне.
    await tester.pump(const Duration(days: 3));
    _returnToForeground(tester);
    await tester.pump();

    expect(_todayMarker(tester, date(2026, 10, 9)), findsOneWidget);
    _expectSelected(tester, date(2026, 10, 6));
    expect(repository.queries, hasLength(1));
    semantics.dispose();
  });

  testWidgets('после закрытия экрана дня часы не читаются, а таймер и '
      'возвращение в приложение ничего не вызывают', (tester) async {
    final clock = _LocalClock(tester, start: _local(2026, 10, 6, 23, 30));
    final repository = _Repository();
    await _openActionDay(tester, repository, clock);
    repository.completeFirst([], total: 0);
    await tester.pump();
    final reads = clock.readCount;

    await tester.pumpWidget(const SizedBox.shrink());
    expect(find.byType(ActionDayRootPage), findsNothing);
    _sendToBackground(tester);
    _returnToForeground(tester);
    await tester.pump(const Duration(days: 2));

    expect(clock.readCount, reads);
    expect(tester.takeException(), isNull);
  });

  testWidgets('если приложение оставалось на Главной до следующего дня, первое '
      'открытие экрана дня выбирает день открытия', (tester) async {
    final semantics = tester.ensureSemantics();
    final clock = _LocalClock(tester, start: _local(2026, 10, 6, 22));
    final repository = _Repository();
    final router = await _pumpApp(tester, repository, clock);
    expect(find.byType(HomePage), findsOneWidget);

    await tester.pump(const Duration(hours: 3));
    openActionsOn(router);
    await tester.pump();
    await tester.pump();

    expect(repository.queries.single.date, date(2026, 10, 7));
    expect(repository.queries.single.section, ActionDaySection.incomplete);
    _expectSelected(tester, date(2026, 10, 7));
    expect(_todayMarker(tester, date(2026, 10, 7)), findsOneWidget);
    expect(visibleWeeks(tester), weeksFrom(date(2026, 10, 5), 1));
    semantics.dispose();
  });
}

final _l10n = lookupAppLocalizations(const Locale('ru'));

/// Местное время Нью-Йорка в виде UTC-значения с теми же полями.
DateTime _local(int year, int month, int day, [int hour = 0, int minute = 0]) =>
    DateTime.utc(year, month, day, hour, minute);

CalendarDate _nextDay(CalendarDate value) {
  final next = DateTime.utc(value.year, value.month, value.day + 1);
  return date(next.year, next.month, next.day);
}

/// Местные часы Нью-Йорка 2026 года, которые идут вместе с поддельным временем
/// теста.
///
/// Момент показания — начальный момент плюс поддельное время, прошедшее после
/// создания часов, и время приостановки процесса [suspend]. Летнее время
/// действует с 8 марта 2:00 до 1 ноября 2:00 местного времени, поэтому эти
/// сутки длятся 23 и 25 часов.
final class _LocalClock {
  _LocalClock(this._tester, {required DateTime start})
    : _start = _instantOf(start),
      _testStart = _tester.binding.clock.now();

  static const _standardOffset = Duration(hours: -5);
  static const _summerOffset = Duration(hours: -4);
  static final _summerStart = DateTime.utc(2026, 3, 8, 7);
  static final _summerEnd = DateTime.utc(2026, 11, 1, 6);

  final WidgetTester _tester;
  final DateTime _start;
  final DateTime _testStart;
  var _suspended = Duration.zero;
  var _readCount = 0;

  /// Число чтений часов экраном дня.
  int get readCount => _readCount;

  /// Override источника местного сегодня экрана дня этими часами.
  Override get override => localDateSourceProvider.overrideWithValue(_read);

  /// Продвигает часы устройства на [duration], пока процесс приостановлен и
  /// его таймеры не выполняются.
  void suspend(Duration duration) => _suspended += duration;

  DateTime get _now => _start
      .add(_tester.binding.clock.now().difference(_testStart))
      .add(_suspended);

  /// Время до местной полуночи следующей даты; часы при этом не читаются
  /// экраном дня.
  Duration get untilNextDate => _reading().untilNextDate;

  LocalDay _read() {
    _readCount += 1;
    return _reading();
  }

  LocalDay _reading() {
    final now = _now;
    final local = now.add(_offsetAt(now));
    final nextDateStart = _instantOf(
      DateTime.utc(local.year, local.month, local.day + 1),
    );
    return LocalDay(
      date: date(local.year, local.month, local.day),
      untilNextDate: nextDateStart.difference(now),
    );
  }

  static Duration _offsetAt(DateTime instant) =>
      !instant.isBefore(_summerStart) && instant.isBefore(_summerEnd)
      ? _summerOffset
      : _standardOffset;

  /// Момент, в который часы показывают местное время [local].
  static DateTime _instantOf(DateTime local) {
    for (final offset in const [_summerOffset, _standardOffset]) {
      final instant = local.subtract(offset);
      if (_offsetAt(instant) == offset) return instant;
    }
    throw ArgumentError.value(local, 'local', 'Пропущено переводом часов.');
  }
}

/// Уводит приложение в фон так, как об этом сообщает платформа.
void _sendToBackground(WidgetTester tester) {
  for (final state in const [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

/// Возвращает приложение из фона в активное состояние.
void _returnToForeground(WidgetTester tester) {
  for (final state in const [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

/// Полная дата с днём недели в том виде, в каком её называет календарь.
String _fullDate(WidgetTester tester, CalendarDate value) {
  final context = tester.element(find.byType(ActionDayCalendar));
  return MaterialLocalizations.of(context)
      .formatFullDate(DateTime.utc(value.year, value.month, value.day));
}

/// День [value] назван сегодняшним: так его читает экранный диктор.
Finder _todayMarker(WidgetTester tester, CalendarDate value) => find
    .bySemanticsLabel('${_fullDate(tester, value)}, ${_l10n.actionDateToday}');

/// Заголовок дня называет выбранную дату [value].
void _expectSelected(WidgetTester tester, CalendarDate value) => expect(
  find.text(
    DateFormat(
      'd MMMM y',
      'ru',
    ).format(DateTime.utc(value.year, value.month, value.day)),
  ),
  findsOneWidget,
);

/// Выдача экрана дня осталась такой же, как была: те же строки, количество,
/// день и охват.
void _expectDayUnchanged(WidgetTester tester, ActionDayState before) {
  final now = _dayState(tester) as ActionDayLoaded;
  final was = before as ActionDayLoaded;
  expect(now.items.map((item) => item.id), was.items.map((item) => item.id));
  expect(now.totalCount, was.totalCount);
  expect(now.selection.date, was.selection.date);
  expect(now.selection.incompleteExpanded, was.selection.incompleteExpanded);
  expect(now.selection.completedExpanded, was.selection.completedExpanded);
}

ActionDayState _dayState(WidgetTester tester) {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(ActionDayRootPage)),
  );
  return container.read(openedActionDayProvider(container));
}

/// Вертикальная прокрутка выдачи под закреплённым календарём.
ScrollPosition _dayScroll(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const PageStorageKey<String>('action-day')),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

/// Доводит до конца анимацию календаря, не дожидаясь покоя индикаторов.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

/// Показывает приложение на Главной с часами [clock] на экране телефона.
Future<AppRouter> _pumpApp(
  WidgetTester tester,
  _Repository repository,
  _LocalClock clock,
) async {
  final router = AppRouter();
  addTearDown(router.dispose);
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        inMemoryQuickCreationModeOverride,
        personalGraphRepositoryProvider.overrideWithValue(repository),
        clock.override,
      ],
      retry: (count, error) => null,
      child: MaterialApp.router(
        theme: doableTheme(Brightness.light),
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router.config(),
      ),
    ),
  );
  await tester.pump();
  return router;
}

/// Открывает экран дня в приложении с часами [clock].
Future<void> _openActionDay(
  WidgetTester tester,
  _Repository repository,
  _LocalClock clock,
) async {
  final router = await _pumpApp(tester, repository, clock);
  openActionsOn(router);
  await tester.pump();
  await tester.pump();
  expect(find.byType(ActionDayRootPage), findsOneWidget);
}

final class _Repository
    with IntentionHoldingReadContractTestFallback, TagReadContractTestFallback
    implements PersonalGraphRepository {
  @override
  Future<ActionDayStatusesReadResult> getActionDayStatuses(
    ActionDayStatusQuery query,
  ) => Completer<ActionDayStatusesReadResult>().future;

  // Управляемые чтения невыполненных; выполненная секция дня пуста.
  final queries = <ActionDayQuery>[];
  final _requests = <Completer<ActionDayPageResult>>[];

  @override
  Future<ActionDayPageResult> getActionDayPage(ActionDayQuery query) {
    if (query.section == ActionDaySection.completed) {
      return Future.value(
        ActionDayPageSuccess(
          ActionDayFirstPage(
            items: const [],
            incompleteCount: 0,
            completedCount: 0,
            hasTimedActions: false,
            nextCursor: null,
            revision: const _Revision(),
          ),
        ),
      );
    }
    queries.add(query);
    final request = Completer<ActionDayPageResult>();
    _requests.add(request);
    return request.future;
  }

  void completeFirst(
    List<ActionListItem> items, {
    int index = 0,
    required int total,
  }) {
    _requests[index].complete(
      ActionDayPageSuccess(
        ActionDayFirstPage(
          items: items,
          incompleteCount: total,
          completedCount: 0,
          hasTimedActions: false,
          nextCursor: items.length < total ? const ActionDayTestCursor() : null,
          revision: const _Revision(),
        ),
      ),
    );
  }

  @override
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  ) async => ResultSuccess(
    IntentionCatalogFirstPage(
      items: const [],
      totalCount: 0,
      nextCursor: null,
      revision: const _Revision(),
    ),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Revision implements GraphRevision {
  const _Revision();

  @override
  GraphRevisionOrder compareTo(GraphRevision other) => GraphRevisionOrder.same;
}

/// Первая порция из 20 невыполненных действий дня [day].
List<ActionListItem> _items(CalendarDate day) => [
  for (var number = 1; number <= 20; number++) actionDayItem(number, date: day),
];
