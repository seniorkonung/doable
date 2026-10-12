import 'dart:ui' show Tristate;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_local_date_provider.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/statistics/application/statistics_period.dart';
import 'package:doable/src/statistics/application/statistics_read_contract.dart';
import 'package:doable/src/statistics/presentation/home_statistics_period_selector.dart';
import 'package:doable/src/statistics/presentation/home_statistics_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'стрелки переходят через границу года, вкладки сохраняют периоды',
    (tester) async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      harness.model.selectPeriod(StatisticsMonth(2026, 12));
      await harness.pump(tester);

      await tester.tap(find.byTooltip('Следующий месяц'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          harness.texts(tester).statisticsMonthPeriod(DateTime.utc(2027, 1)),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Год'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Предыдущий год'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          harness.texts(tester).statisticsYearPeriod(DateTime.utc(2025)),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Месяц'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          harness.texts(tester).statisticsMonthPeriod(DateTime.utc(2027, 1)),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Предыдущий месяц'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          harness.texts(tester).statisticsMonthPeriod(DateTime.utc(2026, 12)),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Год'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          harness.texts(tester).statisticsYearPeriod(DateTime.utc(2025)),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('просмотр года не выбирает месяц, выбор сохраняет раскрытие', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    final texts = harness.texts(tester);
    final october = texts.statisticsMonthPeriod(DateTime.utc(2026, 10));
    final march = texts.statisticsMonthPeriod(DateTime.utc(2025, 3));
    final reads = harness.reader.queries.length;

    await tester.tap(find.byTooltip(texts.statisticsExpandPeriodSelector));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(texts.statisticsPreviousYear));
    await tester.pumpAndSettle();
    expect(find.text(october), findsOneWidget);
    expect(
      find.text(texts.statisticsYearPeriod(DateTime.utc(2025))),
      findsOneWidget,
    );
    expect(harness.reader.queries, hasLength(reads));

    await tester.tap(
      find.text(texts.statisticsMonthName(DateTime.utc(2025, 3))),
    );
    await tester.pumpAndSettle();
    expect(find.text(march), findsOneWidget);
    expect(
      find.byTooltip(texts.statisticsCollapsePeriodSelector),
      findsOneWidget,
    );
    expect(
      find.text(texts.statisticsMonthName(DateTime.utc(2025, 12))),
      findsOneWidget,
    );
    expect(harness.reader.queries.last.period, StatisticsMonth(2025, 3));
    expect(find.text(texts.statisticsCurrentPeriod), findsNothing);

    await tester.tap(find.byTooltip(texts.statisticsCollapsePeriodSelector));
    await tester.pumpAndSettle();
    expect(
      find.text(texts.statisticsMonthName(DateTime.utc(2025, 12))),
      findsNothing,
    );
    expect(find.text(march), findsOneWidget);
  });

  testWidgets(
    'просмотр соседних годов не выбирает год, выбор остаётся раскрытым',
    (tester) async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      await harness.pump(tester);
      final texts = harness.texts(tester);
      await tester.tap(find.text(texts.statisticsYearTab));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(texts.statisticsExpandPeriodSelector));
      await tester.pumpAndSettle();
      final reads = harness.reader.queries.length;
      await tester.tap(find.byTooltip(texts.statisticsPreviousYear).last);
      await tester.pumpAndSettle();
      expect(harness.reader.queries, hasLength(reads));
      expect(
        find.text(texts.statisticsYearPeriod(DateTime.utc(2020))),
        findsOneWidget,
      );

      await tester.tap(
        find.text(texts.statisticsYearPeriod(DateTime.utc(2024))),
      );
      await tester.pumpAndSettle();
      expect(harness.reader.queries.last.period, StatisticsYear(2024));
      expect(
        find.byTooltip(texts.statisticsCollapsePeriodSelector),
        findsOneWidget,
      );
      expect(
        find.text(texts.statisticsYearPeriod(DateTime.utc(2019))),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip(texts.statisticsCollapsePeriodSelector));
      await tester.pumpAndSettle();
      expect(
        find.text(texts.statisticsYearPeriod(DateTime.utc(2024))),
        findsOneWidget,
      );
    },
  );

  for (final boundary in [CalendarDate.earliest, CalendarDate.latest]) {
    testWidgets(
      'у границы ${boundary.year} недоступны выход за календарь и его просмотр',
      (tester) async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        harness.model.selectPeriod(
          StatisticsMonth(boundary.year, boundary.month),
        );
        await harness.pump(tester);
        final texts = harness.texts(tester);
        final first = boundary == CalendarDate.earliest;
        final monthCommand = first
            ? texts.statisticsPreviousMonth
            : texts.statisticsNextMonth;
        final yearCommand = first
            ? texts.statisticsPreviousYear
            : texts.statisticsNextYear;
        expect(
          _named(tester, monthCommand).single.flagsCollection.isEnabled,
          Tristate.isFalse,
        );
        await tester.tap(find.byTooltip(texts.statisticsExpandPeriodSelector));
        await tester.pumpAndSettle();
        expect(
          _named(tester, yearCommand).single.flagsCollection.isEnabled,
          Tristate.isFalse,
        );
        await tester.tap(
          find.text(
            texts.statisticsMonthName(
              DateTime.utc(boundary.year, first ? 2 : 11),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          _named(tester, monthCommand).single.flagsCollection.isEnabled,
          Tristate.isTrue,
        );

        harness.model.selectPeriod(StatisticsYear(boundary.year));
        await tester.pumpAndSettle();
        expect(_named(tester, yearCommand), hasLength(2));
        expect(
          _named(
            tester,
            yearCommand,
          ).every((node) => node.flagsCollection.isEnabled == Tristate.isFalse),
          isTrue,
        );
        final neighbor = boundary.year + (first ? 1 : -1);
        await tester.tap(
          find.text(texts.statisticsYearPeriod(DateTime.utc(neighbor))),
        );
        await tester.pumpAndSettle();
        expect(harness.reader.queries.last.period, StatisticsYear(neighbor));
        expect(
          _named(
            tester,
            yearCommand,
          ).every((node) => node.flagsCollection.isEnabled == Tristate.isTrue),
          isTrue,
        );
      },
    );
  }

  testWidgets(
    'клавиатура переключает вкладку, период, раскрытие и выбор; семантика сообщает состояния',
    (tester) async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      await harness.pump(tester);
      final texts = harness.texts(tester);
      expect(
        _named(
          tester,
          texts.statisticsMonthTab,
        ).single.flagsCollection.isSelected,
        Tristate.isTrue,
      );
      expect(
        _named(tester, texts.statisticsMonthTab).single.role,
        SemanticsRole.tab,
      );
      expect(
        _named(
          tester,
          texts.statisticsYearTab,
        ).single.flagsCollection.isSelected,
        Tristate.isFalse,
      );
      expect(
        _named(
          tester,
          texts.statisticsExpandPeriodSelector,
        ).single.flagsCollection.isExpanded,
        Tristate.isFalse,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        _named(
          tester,
          texts.statisticsYearTab,
        ).single.flagsCollection.isSelected,
        Tristate.isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(harness.reader.queries.last.period, StatisticsYear(2025));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(
        _named(
          tester,
          texts.statisticsCollapsePeriodSelector,
        ).single.flagsCollection.isExpanded,
        Tristate.isTrue,
      );
      final current =
          '${texts.statisticsYearPeriod(DateTime.utc(2026))}\n${texts.statisticsCurrentPeriod}';
      expect(
        _named(tester, current).single.flagsCollection.isSelected,
        Tristate.isFalse,
      );
      final chosen = _named(
        tester,
        texts.statisticsYearPeriod(DateTime.utc(2025)),
      ).where((node) => node.flagsCollection.isInMutuallyExclusiveGroup);
      expect(chosen.single.flagsCollection.isSelected, Tristate.isTrue);

      // Следующий период, просмотр назад, просмотр вперёд, первый год сетки.
      for (var step = 0; step < 4; ++step) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(harness.reader.queries.last.period, StatisticsYear(2020));
      expect(
        find.byTooltip(texts.statisticsCollapsePeriodSelector),
        findsOneWidget,
      );
    },
  );

  for (final locale in [const Locale('ru'), const Locale('en')]) {
    testWidgets(
      'названия и команды читаемы при тройном тексте на ${locale.languageCode}, смена локали сохраняет выбор',
      (tester) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final harness = _Harness();
        addTearDown(harness.dispose);
        await harness.pump(tester, locale: locale, textScale: 3);
        var texts = harness.texts(tester);
        await tester.tap(find.byTooltip(texts.statisticsExpandPeriodSelector));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final september = find.text(
          texts.statisticsMonthName(DateTime.utc(2026, 9)),
        );
        await tester.ensureVisible(september);
        await tester.tap(september);
        await tester.pumpAndSettle();
        expect(harness.reader.queries.last.period, StatisticsMonth(2026, 9));
        await tester.ensureVisible(
          find.byTooltip(texts.statisticsCollapsePeriodSelector),
        );
        expect(
          find
              .text(texts.statisticsMonthPeriod(DateTime.utc(2026, 9)))
              .hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);

        final other = locale.languageCode == 'ru'
            ? const Locale('en')
            : const Locale('ru');
        final reads = harness.reader.queries.length;
        await harness.pump(tester, locale: other, textScale: 3);
        texts = harness.texts(tester);
        expect(
          find.text(texts.statisticsMonthPeriod(DateTime.utc(2026, 9))),
          findsOneWidget,
        );
        expect(
          find.byTooltip(texts.statisticsCollapsePeriodSelector),
          findsOneWidget,
        );
        expect(harness.reader.queries, hasLength(reads));
        final label =
            '${texts.statisticsMonthPeriod(DateTime.utc(2026, 10))}\n${texts.statisticsCurrentPeriod}';
        await tester.ensureVisible(
          find.text(texts.statisticsMonthName(DateTime.utc(2026, 10))),
        );
        await tester.pumpAndSettle();
        expect(
          _named(tester, label).single.flagsCollection.isSelected,
          Tristate.isFalse,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Iterable<SemanticsData> _named(WidgetTester tester, String label) => tester
    .semantics
    .simulatedAccessibilityTraversal()
    .map((node) => node.getSemanticsData())
    .where((node) => node.label == label || node.tooltip == label);

final class _Harness {
  _Harness() {
    container = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(reader),
        dailyChoiceLocalDateSourceProvider.overrideWithValue(
          () => DailyChoiceLocalDay(
            date: CalendarDate.fromParts(2026, 10, 12),
            untilNextDate: const Duration(hours: 12),
          ),
        ),
      ],
    );
    subscription = container.listen(homeStatisticsViewModelProvider, (_, _) {});
    model = container.read(homeStatisticsViewModelProvider.notifier);
    model.setVisible(true);
  }

  final reader = _Reader();
  late final ProviderContainer container;
  late final ProviderSubscription subscription;
  late final HomeStatisticsViewModel model;

  Future<void> pump(
    WidgetTester tester, {
    Locale locale = const Locale('ru'),
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Consumer(
                  builder: (context, ref, _) => HomeStatisticsPeriodSelector(
                    selection: ref
                        .watch(homeStatisticsViewModelProvider)
                        .selection,
                    onTabSelected: model.selectTab,
                    onPeriodSelected: model.selectPeriod,
                    onPreviousPeriod: model.selectPreviousPeriod,
                    onNextPeriod: model.selectNextPeriod,
                    onExpandedChanged: model.setPeriodSelectorExpanded,
                    onBrowsePreviousYear: model.browsePreviousYear,
                    onBrowseNextYear: model.browseNextYear,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  AppLocalizations texts(WidgetTester tester) => AppLocalizations.of(
    tester.element(find.byType(HomeStatisticsPeriodSelector)),
  );

  void dispose() {
    subscription.close();
    container.dispose();
  }
}

final class _Reader implements PersonalGraphRepository {
  final queries = <StatisticsQuery>[];

  @override
  Future<StatisticsPageResult> getStatisticsPage(StatisticsQuery query) async {
    queries.add(query);
    return const StatisticsPageError(StatisticsReadUnavailableFailure());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'В этой проверке используется только чтение статистики.',
  );
}
