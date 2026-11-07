import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/design_system/components/option_row.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:doable/src/shared/presentation/local_day/local_date_provider.dart';
import 'package:doable/src/statistics/application/contribution_counts.dart';
import 'package:doable/src/statistics/application/statistics_read_contract.dart';
import 'package:doable/src/statistics/presentation/home_statistics_content.dart';
import 'package:doable/src/statistics/presentation/home_statistics_state.dart';
import 'package:doable/src/statistics/presentation/home_statistics_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'строка открывает намерение клавиатурой и доступна диктору на RU/EN',
    (tester) async {
      final semantics = tester.ensureSemantics();
      for (final locale in ['ru', 'en']) {
        final item = _item(1, 'Высыпаться', 3, 7, archived: true);
        final harness = _Harness(_data([item], summary: _summary(4, 8)));
        await harness.pump(tester, locale: Locale(locale));
        final texts = harness.texts(tester);
        final row = find.bySemanticsLabel(RegExp('^Высыпаться'));
        await tester.scrollUntilVisible(find.text('Высыпаться'), 400);
        await tester.pumpAndSettle();
        final data = tester.getSemantics(row).getSemanticsData();
        expect(data.flagsCollection.isButton, isTrue);
        expect(data.hasAction(SemanticsAction.tap), isTrue);
        expect(data.label, contains(texts.detailsArchived));
        expect(
          data.label,
          contains(texts.statisticsContributionCountsSemantics(3, 7)),
        );
        expect(data.label, contains(texts.statisticsPeriodActionsShare(7 / 8)));
        final button = find.widgetWithText(TextButton, 'Высыпаться');
        Focus.of(tester.element(find.text('Высыпаться'))).requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(harness.openedIntentions, [item.id]);
        await tester.tap(button);
        expect(harness.openedIntentions, hasLength(2));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
      semantics.dispose();
    },
  );

  testWidgets(
    'каталог сохраняет порядок, точное число и доли действий периода',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final harness = _Harness(
        _data([
          _item(1, 'Высыпаться', 3, 8),
          _item(2, 'Быть в форме', 1, 5),
          _item(3, 'Учить испанский', 0, 5),
          _item(4, 'Читать книги', 0, 2),
        ], summary: _summary(4, 20)),
      );
      await harness.pump(tester);
      final texts = harness.texts(tester);

      expect(find.text(texts.statisticsPeriodSummary), findsOneWidget);
      expect(find.text(texts.statisticsPeriodActions(20)), findsOneWidget);
      expect(find.text(texts.statisticsPeriodCompleted(4, 20)), findsOneWidget);
      // Невыполненное не делится на пропущенное и предстоящее.
      expect(find.textContaining(RegExp('Пропущено|Предстоит')), findsNothing);
      expect(find.text(texts.statisticsTotalItems(4)), findsOneWidget);
      expect(
        find.text(texts.statisticsContributionCounts(3, 8)),
        findsOneWidget,
      );
      expect(find.text(texts.statisticsPeriodActionsShare(.4)), findsOneWidget);
      expect(
        find.text(texts.statisticsPeriodActionsShare(.25)),
        findsNWidgets(2),
      );
      expect(find.text(texts.statisticsPeriodActionsShare(.1)), findsOneWidget);
      final titles = [
        'Высыпаться',
        'Быть в форме',
        'Учить испанский',
        'Читать книги',
      ];
      for (var i = 1; i < titles.length; ++i) {
        expect(
          tester.getTopLeft(find.text(titles[i])).dy,
          greaterThan(tester.getTopLeft(find.text(titles[i - 1])).dy),
        );
      }
    },
  );

  testWidgets(
    'выбор вида показывает название и точное число элементов и открывает лист с четырьмя видами и пояснениями',
    (tester) async {
      final harness = _Harness(
        _data([_item(1, 'Высыпаться', 3, 8)], summary: _summary(3, 20)),
      );
      await harness.pump(tester);
      final texts = harness.texts(tester);
      expect(find.text(texts.statisticsRootIntentions), findsOneWidget);
      expect(find.text(texts.statisticsTotalItems(1)), findsOneWidget);

      await tester.tap(find.text(texts.statisticsRootIntentions));
      await tester.pumpAndSettle();

      expect(find.text('Считать действия по'), findsOneWidget);
      final rows = find.byType(OptionRow);
      expect(rows, findsNWidgets(4));
      final names = [
        for (final row in tester.widgetList<OptionRow>(rows)) row.name,
      ];
      expect(names, [
        'Корневые намерения',
        'Промежуточные намерения',
        'Конечные намерения',
        'Через связи',
      ]);
      final hints = [
        for (final row in tester.widgetList<OptionRow>(rows)) row.hint,
      ];
      expect(hints, [
        'С чего начинается каждый путь',
        'Звенья между корневым и конечным',
        'Последняя причина прямо над действием',
        'Все намерения, которым служит действие',
      ]);
      expect(
        tester
            .widgetList<OptionRow>(rows)
            .where((row) => row.trailing == OptionRowTrailing.selected)
            .map((row) => row.name),
        ['Корневые намерения'],
      );
    },
  );

  testWidgets('вид выбирается в листе, применяется сразу и закрывает лист', (
    tester,
  ) async {
    final harness = _Harness(_data([_item(1, 'Высыпаться', 3, 8)]));
    await harness.pump(tester);
    final texts = harness.texts(tester);

    await tester.tap(find.text(texts.statisticsRootIntentions));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(OptionRow, texts.statisticsTerminalIntentions),
    );
    await tester.pumpAndSettle();

    expect(harness.selectedViews, [StatisticsView.terminalIntentions]);
    expect(find.byType(OptionRow), findsNothing);
    expect(find.text(texts.statisticsViewSheetTitle), findsNothing);
    expect(find.text(texts.statisticsTerminalIntentions), findsOneWidget);
  });

  testWidgets(
    'пояснение о связях на сейчас стоит только над видом «Через связи»',
    (tester) async {
      final harness = _Harness(_data([_item(1, 'Высыпаться', 3, 8)]));
      await harness.pump(tester);
      final texts = harness.texts(tester);
      expect(find.text(texts.statisticsThroughRelationsNote), findsNothing);

      harness.state.value = HomeStatisticsState(
        selection: harness.state.value.selection.copyWith(
          view: StatisticsView.throughRelations,
        ),
        read: _data([_item(1, 'Высыпаться', 3, 8)]),
      );
      await tester.pump();

      expect(
        find.text('Вид считает по связям на сейчас и меняется вместе с ними.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'загрузка, пустой период, пустой вид и обновление различаются без ложных нулей',
    (tester) async {
      final harness = _Harness(
        const HomeStatisticsInitialLoad(),
        view: StatisticsView.intermediateIntentions,
      );
      await harness.pump(tester);
      final texts = harness.texts(tester);
      expect(find.text(texts.statisticsLoading), findsOneWidget);
      expect(find.text(texts.statisticsPeriodActions(0)), findsNothing);
      expect(find.text(texts.statisticsTotalItems(0)), findsNothing);

      harness.show(
        HomeStatisticsViewEmpty(summary: _summary(4, 21), revision: _revision),
      );
      await tester.pump();
      expect(
        find.text(
          'В виде «Промежуточные намерения» в этом периоде элементов нет.',
        ),
        findsOneWidget,
      );
      expect(find.text(texts.statisticsTotalItems(0)), findsOneWidget);
      expect(find.text(texts.statisticsPeriodActions(21)), findsOneWidget);
      expect(find.text(texts.statisticsPeriodCompleted(4, 21)), findsOneWidget);

      harness.show(HomeStatisticsPeriodEmpty(revision: _revision));
      await tester.pump();
      expect(
        find.text(
          'В этом периоде действий нет. Действия, датированные им, будут посчитаны здесь.',
        ),
        findsOneWidget,
      );
      expect(find.text(texts.statisticsPeriodSummary), findsNothing);
      expect(find.text(texts.statisticsViewLabel), findsNothing);
      expect(find.text(texts.statisticsIntermediateIntentions), findsNothing);
      expect(find.text(texts.statisticsTotalItems(0)), findsNothing);

      harness.show(
        _data([
          _item(1, 'Высыпаться', 3, 7),
        ], refreshStatus: const HomeStatisticsRefreshing()),
      );
      await tester.pump();
      expect(find.text(texts.statisticsRefreshing), findsOneWidget);
      expect(find.text(texts.statisticsPeriodCompleted(3, 7)), findsOneWidget);
      expect(find.text('Высыпаться'), findsOneWidget);
      expect(find.text(texts.statisticsLoading), findsNothing);
    },
  );

  for (final scenario in [
    (
      failure: const StatisticsReadUnavailableFailure(),
      initial: 'Не удалось загрузить статистику. Повторите попытку.',
      refresh: 'Статистика не обновлена: не удалось получить изменения. Повторите попытку.',
      more: 'Не удалось загрузить следующие элементы. Повторите попытку.',
      canRetry: true,
      name: 'недоступность',
    ),
    (
      failure: const StatisticsReadCorruptionFailure(),
      initial: 'Сохранённые данные повреждены. Статистика недоступна.',
      refresh: 'Статистика не обновлена: сохранённые данные повреждены.',
      more: 'Следующие элементы недоступны: сохранённые данные повреждены.',
      canRetry: false,
      name: 'повреждение',
    ),
    (
      failure: const StatisticsReadUnexpectedFailure(),
      initial: 'Не удалось загрузить статистику из-за непредвиденной ошибки.',
      refresh: 'Статистика не обновлена из-за непредвиденной ошибки.',
      more: 'Не удалось загрузить следующие элементы из-за непредвиденной ошибки.',
      canRetry: false,
      name: 'неизвестный отказ',
    ),
  ]) {
    testWidgets('${scenario.name}: сообщения и повтор для трёх этапов чтения', (
      tester,
    ) async {
      final harness = _Harness(HomeStatisticsInitialFailure(scenario.failure));
      await harness.pump(tester);
      final texts = harness.texts(tester);
      expect(find.text(scenario.initial), findsOneWidget);
      expect(find.text(texts.statisticsPeriodSummary), findsNothing);
      expect(
        find.text(texts.commonRetry),
        scenario.canRetry ? findsOneWidget : findsNothing,
      );
      if (scenario.canRetry) {
        await tester.tap(find.text(texts.commonRetry));
        await tester.pump();
        expect(harness.retries, ['initial']);
        expect(find.text(texts.statisticsLoading), findsOneWidget);
      }

      final items = [_item(1, 'Высыпаться', 3, 7)];
      harness.show(
        _data(
          items,
          refreshStatus: HomeStatisticsRefreshFailure(scenario.failure),
        ),
      );
      await tester.pump();
      expect(find.text(scenario.refresh), findsOneWidget);
      expect(find.text(texts.statisticsPeriodCompleted(3, 7)), findsOneWidget);
      expect(find.text('Высыпаться'), findsOneWidget);
      expect(
        find.text(texts.commonRetry),
        scenario.canRetry ? findsOneWidget : findsNothing,
      );
      if (scenario.canRetry) {
        await tester.tap(find.text(texts.commonRetry));
        await tester.pump();
        expect(harness.retries.last, 'refresh');
        expect(find.text(texts.statisticsRefreshing), findsOneWidget);
      }

      harness.show(
        _data(
          items,
          totalItems: 2,
          summary: _summary(4, 8),
          cursor: const _Cursor(),
          pageStatus: HomeStatisticsPageFailure(scenario.failure),
        ),
      );
      await tester.pump();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.text(scenario.more).hitTestable(), findsOneWidget);
      expect(find.text('Высыпаться'), findsOneWidget);
      expect(
        find.text(texts.commonRetry),
        scenario.canRetry ? findsOneWidget : findsNothing,
      );
      if (scenario.canRetry) {
        await tester.tap(find.text(texts.commonRetry));
        await tester.pump();
        expect(harness.retries.last, 'more');
        expect(find.text(texts.statisticsLoadingMore), findsOneWidget);
      }
      expect(find.byType(SnackBar), findsNothing);
    });
  }

  testWidgets(
    'каталог строится лениво и прокрутка подгружает следующую порцию',
    (tester) async {
      final first = List.generate(
        100,
        (i) => _item(i + 1, 'Намерение ${i + 1}', 1, 1),
      );
      final reader = _Reader();
      final container = ProviderContainer(
        overrides: [
          personalGraphRepositoryProvider.overrideWithValue(reader),
          localDateSourceProvider.overrideWithValue(
            () => LocalDay(
              date: CalendarDate.fromParts(2026, 10, 12),
              untilNextDate: const Duration(hours: 12),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        homeStatisticsViewModelProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      final model = container.read(homeStatisticsViewModelProvider.notifier);
      model.selectView(StatisticsView.throughRelations);
      model.setVisible(true);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('ru'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => HomeStatisticsContent(
                  state: ref.watch(homeStatisticsViewModelProvider),
                  periodSelector: const SizedBox.shrink(),
                  onViewSelected: model.selectView,
                  onOpenIntention: (_) {},
                  onLoadMoreIfNeeded: model.loadMoreIfNeeded,
                  onRetryFirstPage: model.retryFirstPage,
                  onRetryRefresh: model.retryRefresh,
                  onRetryLoadMore: model.retryLoadMore,
                ),
              ),
            ),
          ),
        ),
      );
      reader.responses.single.complete(
        StatisticsPageSuccess(
          StatisticsFirstPage(
            summary: _summary(150, 150),
            totalItems: 150,
            items: first,
            revision: _revision,
            nextCursor: const _Cursor(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final texts = AppLocalizations.of(
        tester.element(find.byType(HomeStatisticsContent)),
      );
      expect(find.text(texts.statisticsTotalItems(150)), findsOneWidget);
      expect(find.text('Намерение 100'), findsNothing);
      expect(reader.responses, hasLength(1));

      await tester.scrollUntilVisible(
        find.text('Намерение 75'),
        500,
        maxScrolls: 25,
      );
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text(texts.statisticsLoadingMore),
        500,
        maxScrolls: 15,
      );
      expect(find.text(texts.statisticsLoadingMore), findsOneWidget);
      expect(reader.responses, hasLength(2));
      reader.responses.last.complete(
        StatisticsPageSuccess(
          StatisticsContinuationPage(
            items: [
              for (var i = 101; i <= 150; ++i) _item(i, 'Намерение $i', 1, 1),
            ],
            revision: _revision,
            nextCursor: null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Намерение 150'),
        500,
        maxScrolls: 20,
      );
      expect(find.text('Намерение 150').hitTestable(), findsOneWidget);
      expect(reader.responses, hasLength(2));
    },
  );

  for (final locale in [const Locale('ru'), const Locale('en')]) {
    testWidgets(
      '${locale.languageCode}: статус и повтор видны при глубокой прокрутке',
      (tester) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final semantics = tester.ensureSemantics();
        final items = List.generate(
          100,
          (i) => _item(i + 1, 'Намерение ${i + 1}', 1, 1),
        );
        final harness = _Harness(_data(items));
        await harness.pump(tester, locale: locale);
        final texts = harness.texts(tester);
        final row = find.text('Намерение 60');
        await tester.scrollUntilVisible(row, 500, maxScrolls: 100);
        await tester.pumpAndSettle();
        final position = tester
            .state<ScrollableState>(find.byType(Scrollable))
            .position;
        final offset = position.pixels;
        expect(row.hitTestable(), findsOneWidget);

        harness.show(
          _data(items, refreshStatus: const HomeStatisticsRefreshing()),
        );
        await tester.pump();
        final refreshing = find.text(texts.statisticsRefreshing);
        expect(refreshing.hitTestable(at: Alignment.topCenter), findsOneWidget);
        expect(
          tester.getSemantics(refreshing).flagsCollection.isLiveRegion,
          isTrue,
        );
        expect(row.hitTestable(), findsOneWidget);
        expect(position.pixels, offset);

        void failRefresh() => harness.show(
          _data(
            items,
            refreshStatus: const HomeStatisticsRefreshFailure(
              StatisticsReadUnavailableFailure(),
            ),
          ),
        );
        failRefresh();
        await tester.pump();
        final failure = find.text(texts.statisticsRefreshUnavailable);
        final retry = find.text(texts.commonRetry);
        expect(failure.hitTestable(at: Alignment.topCenter), findsOneWidget);
        expect(retry.hitTestable(), findsOneWidget);
        expect(row.hitTestable(), findsOneWidget);
        expect(position.pixels, offset);
        expect(
          tester.getBottomRight(retry).dy,
          lessThanOrEqualTo(
            tester.getTopLeft(find.byType(CustomScrollView)).dy,
          ),
        );
        expect(
          tester.getSemantics(failure).flagsCollection.isLiveRegion,
          isTrue,
        );
        expect(tester.getSemantics(retry).flagsCollection.isButton, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(harness.retries, ['refresh']);
        expect(refreshing.hitTestable(at: Alignment.topCenter), findsOneWidget);
        expect(position.pixels, offset);

        failRefresh();
        await tester.pump();
        await tester.tap(retry);
        await tester.pump();
        expect(harness.retries, ['refresh', 'refresh']);
        expect(refreshing.hitTestable(at: Alignment.topCenter), findsOneWidget);
        harness.show(_data(items.reversed.toList()));
        await tester.pumpAndSettle();
        expect(refreshing, findsNothing);
        expect(failure, findsNothing);
        expect(retry, findsNothing);
        expect(position.pixels, offset);
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );
  }

  testWidgets('замена сохраняет прокрутку и ограничивает её новым содержимым', (
    tester,
  ) async {
    final items = List.generate(
      100,
      (i) => _item(i + 1, 'Намерение ${i + 1}', 1, 1),
    );
    final harness = _Harness(_data(items));
    await harness.pump(tester);
    await tester.scrollUntilVisible(
      find.text('Намерение 60'),
      500,
      maxScrolls: 25,
    );
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    final offset = position.pixels;
    harness.show(_data(items, refreshStatus: const HomeStatisticsRefreshing()));
    await tester.pump();
    harness.show(_data(items.reversed.toList()));
    await tester.pumpAndSettle();
    expect(position.pixels, closeTo(offset, 1));

    harness.show(_data(items.take(20).toList()));
    await tester.pumpAndSettle();
    expect(position.pixels, inInclusiveRange(0, position.maxScrollExtent));
    expect(find.text('Намерение 20').hitTestable(), findsOneWidget);

    harness.state.value = HomeStatisticsState(
      selection: harness.state.value.selection.copyWith(
        view: StatisticsView.terminalIntentions,
      ),
      read: const HomeStatisticsInitialLoad(),
    );
    await tester.pumpAndSettle();
    expect(position.pixels, 0);
    expect(
      find.text(harness.texts(tester).statisticsLoading).hitTestable(),
      findsOneWidget,
    );
  });

  for (final locale in [const Locale('ru'), const Locale('en')]) {
    testWidgets(
      '${locale.languageCode}: архив и числа доступны диктору, смена локали сохраняет выбор',
      (tester) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final harness = _Harness(
          _data([
            _item(
              1,
              'Высыпаться и соблюдать вечерний ритуал',
              3,
              7,
              archived: true,
            ),
            _item(2, 'Другое намерение', 1, 14),
          ], summary: _summary(4, 21)),
        );
        await harness.pump(tester, locale: locale);
        var texts = harness.texts(tester);
        await tester.scrollUntilVisible(
          find.text(texts.statisticsContributionCounts(3, 7)),
          300,
          maxScrolls: 30,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final rowLabel =
            'Высыпаться и соблюдать вечерний ритуал\n${texts.detailsArchived}\n${texts.statisticsContributionCountsSemantics(3, 7)}\n${texts.statisticsPeriodActionsShare(7 / 21)}';
        expect(find.bySemanticsLabel(rowLabel), findsOneWidget);
        expect(find.text(texts.detailsArchived), findsOneWidget);
        expect(
          find.text(texts.statisticsContributionCounts(3, 7)).hitTestable(),
          findsOneWidget,
        );
        await tester.scrollUntilVisible(
          find.text(texts.statisticsPeriodActionsShare(7 / 21)),
          200,
          maxScrolls: 10,
        );
        expect(
          find.text(texts.statisticsPeriodActionsShare(7 / 21)).hitTestable(),
          findsOneWidget,
        );

        await tester.drag(
          find.byType(CustomScrollView),
          const Offset(0, 10000),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text(texts.statisticsRootIntentions),
          250,
          maxScrolls: 20,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(texts.statisticsRootIntentions));
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(OptionRow, texts.statisticsThroughRelations),
        );
        await tester.pumpAndSettle();
        expect(harness.selectedViews.last, StatisticsView.throughRelations);
        expect(find.byType(OptionRow), findsNothing);
        expect(find.text(texts.statisticsThroughRelations), findsOneWidget);

        final selection = harness.state.value.selection;
        await harness.pump(
          tester,
          locale: locale.languageCode == 'ru'
              ? const Locale('en')
              : const Locale('ru'),
        );
        texts = harness.texts(tester);
        expect(harness.state.value.selection.period, selection.period);
        expect(harness.state.value.selection.view, selection.view);
        expect(find.text(texts.statisticsThroughRelations), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

final class _Cursor implements StatisticsCursor {
  const _Cursor();
}

final _revision = _Revision();

final class _Revision implements GraphRevision {
  @override
  GraphRevisionOrder compareTo(GraphRevision other) => identical(this, other)
      ? GraphRevisionOrder.same
      : GraphRevisionOrder.differentEpoch;
}

ContributionCounts _summary(int contribution, int planned) =>
    ContributionCounts(planned: planned, contribution: contribution);

StatisticsItem _item(
  int id,
  String title,
  int contribution,
  int planned, {
  bool archived = false,
}) => StatisticsItem(
  id: switch (IntentionId.decode(
    '00000000-0000-4000-8000-${id.toString().padLeft(12, '0')}',
  )) {
    IntentionIdDecodingSuccess(:final id) => id,
    InvalidIntentionIdDecoding() => throw StateError(
      'Некорректный идентификатор фикстуры',
    ),
  },
  title: title,
  archiveState: archived
      ? IntentionArchiveState.archived
      : IntentionArchiveState.active,
  counts: ContributionCounts(planned: planned, contribution: contribution),
);

HomeStatisticsData _data(
  List<StatisticsItem> items, {
  ContributionCounts? summary,
  int? totalItems,
  StatisticsCursor? cursor,
  HomeStatisticsPageStatus pageStatus = const HomeStatisticsPageIdle(),
  HomeStatisticsRefreshStatus refreshStatus = const HomeStatisticsRefreshIdle(),
}) {
  final planned = items.fold(0, (sum, item) => sum + item.counts.planned);
  final contribution = items.fold(
    0,
    (sum, item) => sum + item.counts.contribution,
  );
  return HomeStatisticsData(
    summary: summary ?? _summary(contribution, planned),
    totalItems: totalItems ?? items.length,
    items: items,
    revision: _revision,
    nextCursor: cursor,
    pageStatus: pageStatus,
    refreshStatus: refreshStatus,
  );
}

final class _Harness {
  _Harness(
    HomeStatisticsReadState read, {
    StatisticsView view = StatisticsView.rootIntentions,
  }) : state = ValueNotifier(
         HomeStatisticsState(
           selection: HomeStatisticsSelection.initial(
             CalendarDate.fromParts(2026, 10, 12),
           ).copyWith(view: view),
           read: read,
         ),
       ) {
    addTearDown(state.dispose);
  }

  final ValueNotifier<HomeStatisticsState> state;
  final selectedViews = <StatisticsView>[];
  final openedIntentions = <IntentionId>[];
  final retries = <String>[];

  void show(HomeStatisticsReadState read) =>
      state.value = state.value.copyWith(read: read);

  AppLocalizations texts(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(HomeStatisticsContent)));

  Future<void> pump(
    WidgetTester tester, {
    Locale locale = const Locale('ru'),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          appBar: AppBar(title: const Text('Главная')),
          body: ValueListenableBuilder(
            valueListenable: state,
            builder: (context, value, _) => HomeStatisticsContent(
              state: value,
              periodSelector: const SizedBox.shrink(),
              onOpenIntention: openedIntentions.add,
              onViewSelected: (view) {
                selectedViews.add(view);
                if (view == value.selection.view) return;
                state.value = HomeStatisticsState(
                  selection: value.selection.copyWith(view: view),
                  read: const HomeStatisticsInitialLoad(),
                );
              },
              onLoadMoreIfNeeded: (_) {},
              onRetryFirstPage: () {
                retries.add('initial');
                show(const HomeStatisticsInitialLoad());
              },
              onRetryRefresh: () {
                retries.add('refresh');
                show(
                  (state.value.read as HomeStatisticsLoaded).withRefreshStatus(
                    const HomeStatisticsRefreshing(),
                  ),
                );
              },
              onRetryLoadMore: () {
                retries.add('more');
                show(
                  (state.value.read as HomeStatisticsData).withPageStatus(
                    const HomeStatisticsPageLoading(),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }
}

final class _Reader implements PersonalGraphRepository {
  final responses = <Completer<StatisticsPageResult>>[];

  @override
  Future<StatisticsPageResult> getStatisticsPage(StatisticsQuery query) {
    final response = Completer<StatisticsPageResult>();
    responses.add(response);
    return response.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'В этой проверке используется только чтение статистики.',
  );
}
