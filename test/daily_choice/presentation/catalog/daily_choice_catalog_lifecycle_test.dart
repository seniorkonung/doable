import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/daily_choice/application/daily_choice_catalog.dart'
    hide DailyChoiceCatalogPage;
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_page.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_state.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_view_model.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_local_date_provider.dart';
import 'package:doable/src/favorite/presentation/home/home_page.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/app_root_pages.dart';
import '../../../support/catalog_reconciliation_test_fallback.dart';
import '../../../support/favorite_read_contract_test_fallback.dart';
import '../../../support/tag_read_contract_test_fallback.dart';
import 'daily_choice_calendar_test_support.dart';

// Обозначение сегодняшнего дня в каталоге следует за местными часами, которые
// идут вместе с поддельным временем теста: полночь, сутки перевода часов и дни
// в фоне проверяются без настоящего ожидания.
void main() {
  setUp(() {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  testWidgets('в местную полночь отмечает новый сегодняшний день, не меняя '
      'выбор, просмотр, выдачу и прокрутку', (tester) async {
    final clock = _LocalClock(tester, start: _local(2026, 10, 6, 23, 30));
    final repository = _Repository();
    await _openCatalog(tester, repository, clock);
    expect(repository.queries.single.date, date(2026, 10, 6));
    repository.completeFirst(_items(date(2026, 10, 6)), total: 40);
    await tester.pump();

    // Пользователь смотрит невыполненные выборы дня, раскрывает месяц и
    // прокручивает выдачу.
    await tester.tap(
      find.byKey(const ValueKey('daily-choice-completion-filter')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(_l10n.dailyChoiceCatalogIncomplete).last);
    await tester.pump();
    expect(repository.queries, hasLength(2));
    repository.completeFirst(_items(date(2026, 10, 6)), index: 1, total: 40);
    await tester.pump();
    await tester.tap(find.byTooltip(_l10n.dailyChoiceCalendarExpand));
    await _settle(tester);
    _catalogScroll(tester).jumpTo(300);
    await tester.pump();

    final catalog = _catalogState(tester);
    expect(catalog, isA<DailyChoiceCatalogLoaded>());
    expect(catalog.selection.isCompleted, false);
    final viewport = month(date(2026, 10, 6));
    expect(_calendar(tester).viewport, viewport);
    expect(_calendar(tester).today, date(2026, 10, 6));
    expect(dayCell(tester, date(2026, 10, 6)).isToday, isTrue);
    final reads = clock.readCount;

    // Подготовка заняла часть оставшегося до полуночи поддельного времени.
    await tester.pump(clock.untilNextDate - const Duration(seconds: 1));
    expect(_calendar(tester).today, date(2026, 10, 6));
    expect(clock.readCount, reads);

    await tester.pump(const Duration(seconds: 1));
    expect(clock.readCount, reads + 1);
    expect(_calendar(tester).today, date(2026, 10, 7));
    expect(dayCell(tester, date(2026, 10, 7)).isToday, isTrue);
    expect(dayCell(tester, date(2026, 10, 6)).isToday, isFalse);
    // Новый сегодняшний день не выбирается сам: выбор, охват, просмотр,
    // загруженная выдача и прокрутка остаются прежними, чтений нет.
    expect(_calendar(tester).selectedDate, date(2026, 10, 6));
    expect(dayCell(tester, date(2026, 10, 6)).isSelected, isTrue);
    expect(_calendar(tester).viewport, viewport);
    expect(_catalogState(tester), same(catalog));
    expect(repository.queries, hasLength(2));
    expect(_catalogScroll(tester).pixels, 300);
  });

  for (final (name, start, transitionDay, transitionLength) in [
    (
      'на летнее время сутки длятся 23 часа',
      _local(2026, 3, 7, 23),
      date(2026, 3, 8),
      const Duration(hours: 23),
    ),
    (
      'на зимнее время сутки длятся 25 часов',
      _local(2026, 10, 31, 23),
      date(2026, 11, 1),
      const Duration(hours: 25),
    ),
  ]) {
    testWidgets('при переводе часов $name, и сегодняшний день сменяется в их '
        'местную полночь', (tester) async {
      final clock = _LocalClock(tester, start: start);
      final repository = _Repository();
      await _openCatalog(tester, repository, clock);
      repository.completeFirst([], total: 0);
      await tester.pump();
      final selected = _calendar(tester).selectedDate;
      final reads = clock.readCount;

      await tester.pump(const Duration(hours: 1));
      expect(_calendar(tester).today, transitionDay);
      expect(clock.readCount, reads + 1);

      // Следующая дата начинается не через фиксированные 24 часа, а в
      // действительную местную полночь.
      await tester.pump(transitionLength - const Duration(seconds: 1));
      expect(_calendar(tester).today, transitionDay);
      expect(clock.readCount, reads + 1);

      await tester.pump(const Duration(seconds: 1));
      expect(_calendar(tester).today, _nextDay(transitionDay));
      expect(clock.readCount, reads + 2);
      expect(_calendar(tester).selectedDate, selected);
      expect(repository.queries, hasLength(1));
    });
  }

  testWidgets('каждое возвращение в приложение перечитывает часы, а до '
      'полуночи остаётся один таймер', (tester) async {
    final clock = _LocalClock(tester, start: _local(2026, 10, 6, 21));
    final repository = _Repository();
    await _openCatalog(tester, repository, clock);
    repository.completeFirst(_items(date(2026, 10, 6)), total: 40);
    await tester.pump();
    final catalog = _catalogState(tester);
    final reads = clock.readCount;

    for (var resume = 1; resume <= 3; resume++) {
      await tester.pump(const Duration(minutes: 10));
      _sendToBackground(tester);
      await tester.pump(const Duration(minutes: 10));
      _returnToForeground(tester);
      await tester.pump();
      expect(clock.readCount, reads + resume);
      expect(_calendar(tester).today, date(2026, 10, 6));
    }
    expect(_catalogState(tester), same(catalog));
    expect(repository.queries, hasLength(1));

    // С 22:00 до полуночи: прежние таймеры заменены, срабатывает только один.
    await tester.pump(const Duration(hours: 1, minutes: 59, seconds: 59));
    expect(clock.readCount, reads + 3);
    await tester.pump(const Duration(seconds: 1));
    expect(clock.readCount, reads + 4);
    expect(_calendar(tester).today, date(2026, 10, 7));

    await tester.pump(const Duration(hours: 23, minutes: 59, seconds: 59));
    expect(clock.readCount, reads + 4);
    await tester.pump(const Duration(seconds: 1));
    expect(clock.readCount, reads + 5);
    expect(_calendar(tester).today, date(2026, 10, 8));
    expect(_calendar(tester).selectedDate, date(2026, 10, 6));
    expect(_catalogState(tester), same(catalog));
    expect(repository.queries, hasLength(1));
  });

  testWidgets('после нескольких дней приостановки в фоне возвращение '
      'отмечает день возвращения и переносит таймер', (tester) async {
    final clock = _LocalClock(tester, start: _local(2026, 10, 6, 22));
    final repository = _Repository();
    await _openCatalog(tester, repository, clock);
    repository.completeFirst(_items(date(2026, 10, 6)), total: 40);
    await tester.pump();
    final catalog = _catalogState(tester);
    final viewport = _calendar(tester).viewport;
    final reads = clock.readCount;

    // Приостановленный процесс не выполняет таймеры, а часы устройства идут:
    // процесс возвращается 9 октября в 11:00.
    _sendToBackground(tester);
    clock.suspend(const Duration(days: 2, hours: 13));
    _returnToForeground(tester);
    await tester.pump();
    expect(clock.readCount, reads + 1);
    expect(_calendar(tester).today, date(2026, 10, 9));
    expect(_calendar(tester).selectedDate, date(2026, 10, 6));
    expect(_calendar(tester).viewport, viewport);
    expect(_catalogState(tester), same(catalog));
    expect(repository.queries, hasLength(1));

    // Таймер до прежней полуночи заменён таймером до полуночи 10 октября.
    await tester.pump(const Duration(hours: 12, minutes: 59, seconds: 59));
    expect(clock.readCount, reads + 1);
    await tester.pump(const Duration(seconds: 1));
    expect(clock.readCount, reads + 2);
    expect(_calendar(tester).today, date(2026, 10, 10));
  });

  testWidgets('дни, прошедшие в фоне с работающими таймерами, отмечаются при '
      'возвращении', (tester) async {
    final clock = _LocalClock(tester, start: _local(2026, 10, 6, 22));
    final repository = _Repository();
    await _openCatalog(tester, repository, clock);
    repository.completeFirst([], total: 0);
    await tester.pump();
    final reads = clock.readCount;

    _sendToBackground(tester);
    await tester.pump(const Duration(days: 3));
    // Три местные полуночи прошли в фоне.
    expect(clock.readCount, reads + 3);
    _returnToForeground(tester);
    await tester.pump();

    expect(clock.readCount, reads + 4);
    expect(_calendar(tester).today, date(2026, 10, 9));
    expect(_calendar(tester).selectedDate, date(2026, 10, 6));
    expect(repository.queries, hasLength(1));
  });

  testWidgets('после закрытия каталога часы не читаются, а таймер и '
      'возвращение в приложение ничего не вызывают', (tester) async {
    final clock = _LocalClock(tester, start: _local(2026, 10, 6, 23, 30));
    final repository = _Repository();
    await _openCatalog(tester, repository, clock);
    repository.completeFirst([], total: 0);
    await tester.pump();
    final reads = clock.readCount;

    await tester.pumpWidget(const SizedBox.shrink());
    expect(find.byType(DailyChoiceCatalogPage), findsNothing);
    _sendToBackground(tester);
    _returnToForeground(tester);
    await tester.pump(const Duration(days: 2));

    expect(clock.readCount, reads);
    expect(tester.takeException(), isNull);
  });

  testWidgets('если приложение оставалось на Главной до следующего дня, первое '
      'открытие каталога выбирает день открытия', (tester) async {
    final clock = _LocalClock(tester, start: _local(2026, 10, 6, 22));
    final repository = _Repository();
    final router = await _pumpApp(tester, repository, clock);
    expect(find.byType(HomePage), findsOneWidget);

    await tester.pump(const Duration(hours: 3));
    expect(clock.readCount, 0);
    openDailyChoicesOn(router);
    await tester.pump();
    await tester.pump();

    expect(repository.queries.single.date, date(2026, 10, 7));
    expect(repository.queries.single.isCompleted, isNull);
    expect(_calendar(tester).selectedDate, date(2026, 10, 7));
    expect(_calendar(tester).today, date(2026, 10, 7));
    expect(_calendar(tester).viewport, week(date(2026, 10, 7)));
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

  /// Число чтений часов каталогом.
  int get readCount => _readCount;

  /// Override источника местного сегодня каталога этими часами.
  Override get override =>
      dailyChoiceLocalDateSourceProvider.overrideWithValue(_read);

  /// Продвигает часы устройства на [duration], пока процесс приостановлен и
  /// его таймеры не выполняются.
  void suspend(Duration duration) => _suspended += duration;

  DateTime get _now => _start
      .add(_tester.binding.clock.now().difference(_testStart))
      .add(_suspended);

  /// Время до местной полуночи следующей даты; часы при этом не читаются
  /// каталогом.
  Duration get untilNextDate => _reading().untilNextDate;

  DailyChoiceLocalDay _read() {
    _readCount += 1;
    return _reading();
  }

  DailyChoiceLocalDay _reading() {
    final now = _now;
    final local = now.add(_offsetAt(now));
    final nextDateStart = _instantOf(
      DateTime.utc(local.year, local.month, local.day + 1),
    );
    return DailyChoiceLocalDay(
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

DailyChoiceCalendar _calendar(WidgetTester tester) =>
    tester.widget<DailyChoiceCalendar>(find.byType(DailyChoiceCalendar));

DailyChoiceCatalogState _catalogState(WidgetTester tester) =>
    ProviderScope.containerOf(
      tester.element(find.byType(DailyChoiceCatalogPage)),
    ).read(dailyChoiceCatalogViewModelProvider);

/// Общая вертикальная прокрутка каталога.
ScrollPosition _catalogScroll(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byType(DailyChoiceCatalogPage),
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
        personalGraphRepositoryProvider.overrideWithValue(repository),
        clock.override,
      ],
      retry: (count, error) => null,
      child: MaterialApp.router(
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

/// Открывает каталог дневных выборов в приложении с часами [clock].
Future<void> _openCatalog(
  WidgetTester tester,
  _Repository repository,
  _LocalClock clock,
) async {
  final router = await _pumpApp(tester, repository, clock);
  openDailyChoicesOn(router);
  await tester.pump();
  await tester.pump();
  expect(find.byType(DailyChoiceCatalogPage), findsOneWidget);
}

final class _Repository
    with
        TagReadContractTestFallback,
        FavoriteReadContractTestFallback,
        CatalogReconciliationTestFallback
    implements PersonalGraphRepository {
  final queries = <DailyChoiceCatalogQuery>[];
  final _requests = <Completer<DailyChoiceCatalogPageResult>>[];

  @override
  Future<DailyChoiceCatalogPageResult> getDailyChoiceCatalogPage(
    DailyChoiceCatalogQuery query,
  ) {
    queries.add(query);
    final request = Completer<DailyChoiceCatalogPageResult>();
    _requests.add(request);
    return request.future;
  }

  void completeFirst(
    List<DailyChoiceCatalogItem> items, {
    int index = 0,
    required int total,
  }) {
    _requests[index].complete(
      DailyChoiceCatalogPageSuccess(
        DailyChoiceCatalogFirstPage(
          items: items,
          totalCount: total,
          nextCursor: items.length < total ? const _Cursor() : null,
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

final class _Cursor implements DailyChoiceCatalogCursor {
  const _Cursor();
}

/// Первая порция из 20 невыполненных дневных выборов дня [day].
List<DailyChoiceCatalogItem> _items(CalendarDate day) => [
  for (var number = 1; number <= 20; number++)
    DailyChoiceCatalogItem(
      id: _id(number),
      source: DailyChoiceCatalogParticipant(
        id: _intentionId(1),
        title: 'Основание',
        archiveState: IntentionArchiveState.active,
        readiness: IntentionReadiness.ready,
      ),
      selected: DailyChoiceCatalogParticipant(
        id: _intentionId(2),
        title: 'Действие',
        archiveState: IntentionArchiveState.active,
        readiness: IntentionReadiness.ready,
      ),
      date: day,
      isCompleted: false,
    ),
];

DailyChoiceId _id(int number) => (DailyChoiceId.decode(
  '00000000-0000-4000-8000-${number.toString().padLeft(12, '0')}',
) as DailyChoiceIdDecodingSuccess).id;

IntentionId _intentionId(int number) => (IntentionId.decode(
  '00000000-0000-4000-8000-${number.toString().padLeft(12, '0')}',
) as IntentionIdDecodingSuccess).id;
