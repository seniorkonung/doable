import 'dart:async';
import 'dart:math' as math;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/daily_choice/application/daily_choice_catalog.dart';
import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/app_root_pages.dart';
import '../../../support/favorite_read_contract_test_fallback.dart';
import '../../../support/tag_read_contract_test_fallback.dart';
import '../../../support/catalog_reconciliation_test_fallback.dart';

void main() {
  for (final (locale, label) in [
    (const Locale('ru'), 'Создать выбор от действия'),
    (const Locale('en'), 'Create a choice from an action'),
  ]) {
    testWidgets(
      'вход в нижний выбор доступен на языке ${locale.languageCode}',
      (tester) async {
        final repository = _Repository();
        final router = await _open(tester, repository, locale: locale);
        await tester.pump(const Duration(milliseconds: 400));
        final entry = find.byKey(
          const ValueKey('daily-choice-create-from-action'),
        );
        expect(find.text(label), findsOneWidget);
        final semantics = tester.ensureSemantics();
        expect(find.bySemanticsLabel(label), findsOneWidget);
        await tester.tap(entry);
        await tester.pumpAndSettle();
        expect(router.current.name, DailyChoiceActionPickerRoute.name);
        await tester.tap(
          find.byKey(const ValueKey('daily-choice-action-cancel')),
        );
        await tester.pump(const Duration(milliseconds: 400));
        expectDailyChoicesRootPage(router);
        repository.completeFirst([], total: 0);
        await tester.pump();
        expect(entry, findsOneWidget);
        semantics.dispose();
      },
    );
  }

  testWidgets('показывает все записи, количество и открывает дубликат по id', (
    tester,
  ) async {
    final repository = _Repository();
    final router = await _open(tester, repository);
    expect(find.text('Загружаем дневные выборы…'), findsOneWidget);
    repository.completeFirst([_item(1), _item(2)], total: 2);
    await tester.pumpAndSettle();
    expect(find.text('Всего дневных выборов: 2'), findsOneWidget);
    expect(find.text('Чтобы Основание, я сегодня Действие'), findsNWidgets(2));
    final semantics = tester.ensureSemantics();
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('daily-choice-row-2')))
          .label,
      contains('№ 2'),
    );
    await tester.tap(find.byKey(const ValueKey('daily-choice-row-2')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(router.current.name, DailyChoiceDetailsRoute.name);
    expect(
      router.current.argsAs<DailyChoiceDetailsRouteArgs>().choiceId,
      _id(2),
    );
    semantics.dispose();
  });

  testWidgets('фильтры, подгрузка и сброс возвращают полный охват', (
    tester,
  ) async {
    final repository = _Repository();
    await _open(tester, repository);
    repository.completeFirst([_item(1)], total: 2, cursor: const _Cursor());
    await tester.pumpAndSettle();
    expect(find.text('Всего дневных выборов: 2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('daily-choice-load-more')));
    await tester.pump();
    expect(repository.queries[1].cursor, isA<_Cursor>());
    repository.completeMore(1, [_item(2)]);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('daily-choice-row-2')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('daily-choice-date-filter')),
      '2026-09-24',
    );
    await tester.tap(find.byKey(const ValueKey('daily-choice-apply-date')));
    await tester.pump();
    expect(repository.queries[2].date, CalendarDate.fromParts(2026, 9, 24));
    repository.completeFirst([_item(2)], index: 2, total: 1);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('daily-choice-completion-filter')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выполненные').last);
    await tester.pump();
    expect(repository.queries[3].isCompleted, true);
    repository.completeFirst([], index: 3, total: 0);
    await tester.pumpAndSettle();
    expect(find.text('Дневных выборов по фильтрам нет.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('daily-choice-clear-filters')));
    await tester.pump();
    expect(repository.queries[4].date, isNull);
    expect(repository.queries[4].isCompleted, isNull);
    repository.completeFirst([_item(1), _item(2)], index: 4, total: 2);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('daily-choice-row-1')), findsOneWidget);
    expect(find.text('Все состояния'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('daily-choice-date-filter')),
      '2026-02-30',
    );
    await tester.tap(find.byKey(const ValueKey('daily-choice-apply-date')));
    await tester.pump();
    expect(
      find.text('Введите корректную дату в формате ГГГГ-ММ-ДД.'),
      findsOneWidget,
    );
    expect(repository.queries, hasLength(5));
  });

  testWidgets('различает ошибку чтения и повторную попытку на английском', (
    tester,
  ) async {
    final repository = _Repository();
    await _open(tester, repository, locale: const Locale('en'));
    repository.failFirst();
    await tester.pumpAndSettle();
    expect(
      find.text('Could not load daily choices. Try again.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Try again'));
    await tester.pump();
    repository.completeFirst([_item(1)], index: 1, total: 1);
    await tester.pumpAndSettle();
    expect(find.text('To Основание, today I Действие'), findsOneWidget);
  });

  testWidgets('фильтры, количество и выдача прокручиваются вместе одним '
      'жестом по выдаче', (tester) async {
    final repository = _Repository();
    await _open(tester, repository, size: _phone);
    repository.completeFirst(
      [for (var number = 1; number <= 20; number++) _item(number)],
      total: 21,
      cursor: const _Cursor(),
    );
    await tester.pumpAndSettle();
    final dateFilter = find.byKey(const ValueKey('daily-choice-date-filter'));
    final count = find.text('Всего дневных выборов: 21');
    final row = find.byKey(const ValueKey('daily-choice-row-2'));
    final before = [
      for (final finder in [dateFilter, count, row]) tester.getRect(finder).top,
    ];

    await tester.drag(row, const Offset(0, -100));
    await tester.pumpAndSettle();

    final shifts = [
      for (final (index, finder) in [dateFilter, count, row].indexed)
        before[index] - tester.getRect(finder).top,
    ];
    expect(shifts.first, greaterThan(0));
    expect(shifts, everyElement(moreOrLessEquals(shifts.first)));
  });

  for (final (keyboard, variant) in [
    (0.0, 'без клавиатуры'),
    (300.0, 'при открытой клавиатуре'),
  ]) {
    testWidgets('начальные загрузка, отказ с повтором и пустая выдача стоят '
        'под фильтрами и доступны над созданием дневного выбора $variant', (
      tester,
    ) async {
      final repository = _Repository();
      await _open(tester, repository, size: _phone, keyboard: keyboard);
      final l10n = lookupAppLocalizations(const Locale('ru'));
      final create = find.byKey(
        const ValueKey('daily-choice-create-from-action'),
      );

      // Прокручивает страницу до конца жестом из-под шапки и проверяет, что
      // элемент стоит под фильтрами и целиком виден над созданием дневного
      // выбора, а значит, и над клавиатурой.
      Future<void> expectReachable(Finder finder) async {
        final appBar = tester.getRect(find.byType(AppBar));
        await tester.dragFrom(
          Offset(appBar.left + 24, appBar.bottom + 24),
          const Offset(0, -400),
        );
        // Индикатор загрузки не даёт кадрам успокоиться.
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(finder, findsOneWidget);
        final filtersBottom = [
          for (final key in _filterKeys)
            tester
                .getRect(find.byKey(ValueKey(key), skipOffstage: false))
                .bottom,
        ].reduce(math.max);
        final rect = tester.getRect(finder);
        expect(
          rect.top,
          greaterThanOrEqualTo(filtersBottom),
          reason: '$finder',
        );
        expect(
          rect.top,
          greaterThanOrEqualTo(appBar.bottom),
          reason: '$finder',
        );
        expect(
          rect.bottom,
          lessThanOrEqualTo(tester.getRect(create).top),
          reason: '$finder',
        );
      }

      await expectReachable(find.text(l10n.dailyChoiceCatalogLoading));

      repository.failFirst();
      await tester.pumpAndSettle();
      final retry = find.widgetWithText(TextButton, l10n.commonRetry);
      await expectReachable(find.text(l10n.dailyChoiceCatalogUnavailable));
      await expectReachable(retry);
      expect(retry.hitTestable(), findsOneWidget);

      await tester.tap(retry);
      await tester.pump();
      expect(repository.queries, hasLength(2));
      await expectReachable(find.text(l10n.dailyChoiceCatalogLoading));

      repository.completeFirst([], index: 1, total: 0);
      await tester.pumpAndSettle();
      await expectReachable(find.text(l10n.dailyChoiceCatalogTotalCount(0)));
      await expectReachable(find.text(l10n.dailyChoiceCatalogEmpty));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('фильтры и строки доступны при увеличенном тексте', (
    tester,
  ) async {
    tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
    );
    final repository = _Repository();
    await _open(tester, repository, size: const Size(360, 640));
    repository.completeFirst([_item(1)], total: 1);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('daily-choice-date-filter')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('daily-choice-completion-filter')),
      findsOneWidget,
    );
    // Строки идут за крупными фильтрами и становятся видимыми прокруткой
    // страницы.
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('daily-choice-row-1')),
      find.byType(CustomScrollView),
      const Offset(0, -100),
    );
    expect(find.byKey(const ValueKey('daily-choice-row-1')), findsOneWidget);
  });
}

/// Экран телефона, на котором фильтры и выдача делят высоту.
const _phone = Size(400, 800);

/// Фильтры каталога: поле даты, её применение, выполнение и сброс.
const _filterKeys = [
  'daily-choice-date-filter',
  'daily-choice-apply-date',
  'daily-choice-completion-filter',
  'daily-choice-clear-filters',
];

/// Открывает каталог дневных выборов; [keyboard] — высота открытой экранной
/// клавиатуры.
Future<AppRouter> _open(
  WidgetTester tester,
  _Repository repository, {
  Locale locale = const Locale('ru'),
  Size size = const Size(1200, 2400),
  double keyboard = 0,
}) async {
  final router = AppRouter();
  addTearDown(router.dispose);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
      retry: (count, error) => null,
      child: MaterialApp.router(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router.config(),
      ),
    ),
  );
  openDailyChoicesOn(router);
  await tester.pump();
  return router;
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
    DailyChoiceCatalogCursor? cursor,
  }) {
    _requests[index].complete(
      DailyChoiceCatalogPageSuccess(
        DailyChoiceCatalogFirstPage(
          items: items,
          totalCount: total,
          nextCursor: cursor,
          revision: const _Revision(),
        ),
      ),
    );
  }

  void completeMore(int index, List<DailyChoiceCatalogItem> items) {
    _requests[index].complete(
      DailyChoiceCatalogPageSuccess(
        DailyChoiceCatalogContinuationPage(
          items: items,
          nextCursor: null,
          revision: const _Revision(),
        ),
      ),
    );
  }

  void failFirst() => _requests[0].complete(
    const DailyChoiceCatalogPageError(DailyChoiceCatalogUnavailableFailure()),
  );

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
  Stream<DailyChoiceReadResult> watchDailyChoice(DailyChoiceId id) =>
      const Stream.empty();

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

DailyChoiceCatalogItem _item(int number) => DailyChoiceCatalogItem(
  id: _id(number),
  source: DailyChoiceCatalogParticipant(
    id: _intentionId(1),
    title: 'Основание',
    archiveState: IntentionArchiveState.archived,
    readiness: IntentionReadiness.notReady,
  ),
  selected: DailyChoiceCatalogParticipant(
    id: _intentionId(2),
    title: 'Действие',
    archiveState: IntentionArchiveState.active,
    readiness: IntentionReadiness.ready,
  ),
  date: CalendarDate.fromParts(2026, 9, 24),
  isCompleted: false,
);

DailyChoiceId _id(int number) => (DailyChoiceId.decode(
  '00000000-0000-4000-8000-${number.toString().padLeft(12, '0')}',
) as DailyChoiceIdDecodingSuccess).id;

IntentionId _intentionId(int number) => (IntentionId.decode(
  '00000000-0000-4000-8000-${number.toString().padLeft(12, '0')}',
) as IntentionIdDecodingSuccess).id;
