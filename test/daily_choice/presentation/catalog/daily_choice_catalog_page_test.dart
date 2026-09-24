import 'dart:async';

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

void main() {
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
    expect(find.byKey(const ValueKey('daily-choice-row-1')), findsOneWidget);
  });
}

Future<AppRouter> _open(
  WidgetTester tester,
  _Repository repository, {
  Locale locale = const Locale('ru'),
  Size size = const Size(1200, 2400),
}) async {
  final router = AppRouter();
  addTearDown(router.dispose);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
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
  unawaited(router.push(const DailyChoiceCatalogRoute()));
  await tester.pump();
  return router;
}

final class _Repository implements PersonalGraphRepository {
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
