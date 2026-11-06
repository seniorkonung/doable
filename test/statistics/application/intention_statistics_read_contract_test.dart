import 'package:doable/src/action/application/action_day_statuses.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:doable/src/statistics/application/contribution_counts.dart';
import 'package:doable/src/statistics/application/intention_statistics_breakdown.dart';
import 'package:doable/src/statistics/application/intention_statistics_calendar.dart';
import 'package:doable/src/statistics/application/intention_statistics_read_contract.dart';
import 'package:doable/src/statistics/application/intention_statistics_target.dart';
import 'package:doable/src/statistics/application/statistics_period.dart';
import 'package:doable/src/statistics/application/statistics_read_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('каждый вид предоставляет только свои разбивки в порядке показа', () {
    expect(StatisticsView.rootIntentions.breakdowns, [
      StatisticsBreakdown.terminalIntentions,
    ]);
    expect(StatisticsView.intermediateIntentions.breakdowns, [
      StatisticsBreakdown.rootIntentions,
      StatisticsBreakdown.terminalIntentions,
    ]);
    expect(StatisticsView.terminalIntentions.breakdowns, [
      StatisticsBreakdown.rootIntentions,
    ]);
    expect(StatisticsView.throughRelations.breakdowns, [
      StatisticsBreakdown.relations,
      StatisticsBreakdown.terminalIntentions,
    ]);
  });

  test('цель разбивки сохраняет период и открывает соответствующий вид', () {
    final period = StatisticsYear(2025);
    for (final (breakdown, view) in [
      (StatisticsBreakdown.rootIntentions, StatisticsView.rootIntentions),
      (
        StatisticsBreakdown.terminalIntentions,
        StatisticsView.terminalIntentions,
      ),
      (StatisticsBreakdown.relations, StatisticsView.throughRelations),
    ]) {
      final target = IntentionStatisticsTarget.forBreakdown(
        breakdown: breakdown,
        period: period,
      );
      expect(target.view, view);
      expect(target.period, period);
    }
  });

  test('месяц сохраняет свои отметки независимо от исходной карты', () {
    final completed = CalendarDate.fromParts(2026, 10, 5);
    final incomplete = CalendarDate.fromParts(2026, 10, 7);
    final empty = CalendarDate.fromParts(2026, 10, 9);
    final statuses = {
      completed: ActionDayStatus.allCompleted,
      incomplete: ActionDayStatus.hasIncomplete,
    };
    final calendar = IntentionStatisticsMonthCalendar(
      period: StatisticsMonth(2026, 10),
      statuses: statuses,
    );
    statuses.clear();

    expect(calendar.statuses[completed], ActionDayStatus.allCompleted);
    expect(calendar.statuses[incomplete], ActionDayStatus.hasIncomplete);
    expect(calendar.statuses[empty], isNull);
    expect(() => calendar.statuses.clear(), throwsUnsupportedError);
    expect(
      () => IntentionStatisticsMonthCalendar(
        period: StatisticsMonth(2026, 11),
        statuses: calendar.statuses,
      ),
      throwsA(isA<StatisticsDataValidationException>()),
    );
  });

  test('год сохраняет ровно 12 месяцев, включая месяцы без выборов', () {
    final months = List.generate(
      12,
      (index) => ContributionCounts(planned: index, contribution: 0),
    );
    final calendar = IntentionStatisticsYearCalendar(
      period: StatisticsYear(2026),
      months: months,
    );
    months.clear();

    expect(
      calendar.months.map((month) => month.planned),
      List.generate(12, (index) => index),
    );
    expect(() => calendar.months.clear(), throwsUnsupportedError);
    for (final length in [11, 13]) {
      expect(
        () => IntentionStatisticsYearCalendar(
          period: StatisticsYear(2026),
          months: List.filled(
            length,
            ContributionCounts(planned: 0, contribution: 0),
          ),
        ),
        throwsA(isA<StatisticsDataValidationException>()),
      );
    }
  });

  test('порция разбивки сохраняет строки и ограничивает их количество', () {
    final item = StatisticsItem(
      id: _id,
      title: 'Высыпаться',
      archiveState: IntentionArchiveState.archived,
      counts: ContributionCounts(planned: 7, contribution: 3),
    );
    final items = [item];
    final page = StatisticsBreakdownFirstPage<StatisticsItem>(
      items: items,
      totalItems: 1,
      nextCursor: null,
    );
    items.clear();
    expect(page.items, [item]);
    expect(() => page.items.clear(), throwsUnsupportedError);
    expect(
      () => StatisticsBreakdownFirstPage<StatisticsItem>(
        items: const [],
        totalItems: -1,
        nextCursor: null,
      ),
      throwsA(isA<StatisticsDataValidationException>()),
    );
    expect(
      () => StatisticsBreakdownFirstPage<StatisticsItem>(
        items: List.filled(101, item),
        totalItems: 101,
        nextCursor: null,
      ),
      throwsA(isA<StatisticsDataValidationException>()),
    );
  });

  test(
    'раздел не принимает календарь другого периода или разбивки другого вида',
    () {
      final query = _query(StatisticsMonth(2026, 10));
      expect(
        () => _section(
          query: query,
          calendar: IntentionStatisticsYearCalendar(
            period: StatisticsYear(2026),
            months: List.filled(12, _zero),
          ),
        ),
        throwsA(isA<StatisticsDataValidationException>()),
      );
      expect(
        () => _section(
          query: query,
          details: IntentionStatisticsRootDetails(
            terminalIntentions: _emptyIntentions(),
          ),
        ),
        throwsA(isA<StatisticsDataValidationException>()),
      );
    },
  );

  test(
    'сводка выбранного вида согласована с карточкой и явными основаниями',
    () {
      final counts = ContributionCounts(planned: 8, contribution: 3);
      final cards = IntentionStatisticsCards(
        rootIntentions: ContributionCounts(planned: 7, contribution: 3),
        intermediateIntentions: _zero,
        terminalIntentions: _zero,
        throughRelations: counts,
      );
      for (final explicitPathActions in [9, -1]) {
        expect(
          () => _section(
            cards: cards,
            details: IntentionStatisticsThroughRelationsDetails(
              explicitPathActions: explicitPathActions,
              relations: StatisticsBreakdownFirstPage<StatisticsRelationItem>(
                items: const [],
                totalItems: 0,
                nextCursor: null,
              ),
              terminalIntentions: _emptyIntentions(),
            ),
          ),
          throwsA(isA<StatisticsDataValidationException>()),
        );
      }
      final section = _section(
        cards: cards,
        details: IntentionStatisticsThroughRelationsDetails(
          explicitPathActions: 7,
          relations: StatisticsBreakdownFirstPage<StatisticsRelationItem>(
            items: const [],
            totalItems: 0,
            nextCursor: null,
          ),
          terminalIntentions: _emptyIntentions(),
        ),
      );
      expect(section.selectedCounts.planned, 8);
      expect(section.selectedCounts.contribution, 3);
      expect(section.periodCounts.contribution, 4);
    },
  );

  test('раздел принимает пустой вид запроса с любым видом разбивок', () {
    final query = IntentionStatisticsQuery(
      intentionId: _id,
      period: StatisticsMonth(2026, 10),
      view: null,
      pageSize: 100,
    );

    final section = _section(
      query: query,
      details: IntentionStatisticsRootDetails(
        terminalIntentions: _emptyIntentions(),
      ),
    );

    expect(section.view, StatisticsView.rootIntentions);
  });

  test(
    'раздел отклоняет вид разбивок, не совпадающий с заданным видом запроса',
    () {
      expect(
        () => _section(
          details: IntentionStatisticsTerminalDetails(
            rootIntentions: _emptyIntentions(),
          ),
        ),
        throwsA(isA<StatisticsDataValidationException>()),
      );
    },
  );

  test('раздел отклоняет вид, где действий больше, чем в периоде', () {
    expect(
      () => _section(
        cards: IntentionStatisticsCards(
          rootIntentions: _zero,
          intermediateIntentions: _zero,
          terminalIntentions: _zero,
          throughRelations: ContributionCounts(planned: 22, contribution: 0),
        ),
      ),
      throwsA(isA<StatisticsDataValidationException>()),
    );
  });

  test('размер порции ограничивает каждую из двух разбивок раздела', () {
    StatisticsItem item(String id, int planned) => StatisticsItem(
      id: switch (IntentionId.decode(id)) {
        IntentionIdDecodingSuccess(:final id) => id,
        InvalidIntentionIdDecoding() => throw StateError(
          'Некорректная фикстура.',
        ),
      },
      title: 'Намерение',
      archiveState: IntentionArchiveState.active,
      counts: ContributionCounts(planned: planned, contribution: 0),
    );
    final one = StatisticsBreakdownFirstPage<StatisticsItem>(
      items: [item('018f0b5d-6b2e-7c80-8000-000000000002', 2)],
      totalItems: 1,
      nextCursor: null,
    );
    final two = StatisticsBreakdownFirstPage<StatisticsItem>(
      items: [
        item('018f0b5d-6b2e-7c80-8000-000000000003', 1),
        item('018f0b5d-6b2e-7c80-8000-000000000002', 1),
      ],
      totalItems: 2,
      nextCursor: null,
    );
    for (final (sources, actions) in [(one, two), (two, one)]) {
      expect(
        () => _section(
          query: IntentionStatisticsQuery(
            intentionId: _id,
            period: StatisticsMonth(2026, 10),
            view: StatisticsView.intermediateIntentions,
            pageSize: 1,
          ),
          cards: IntentionStatisticsCards(
            rootIntentions: _zero,
            intermediateIntentions: ContributionCounts(
              planned: 2,
              contribution: 0,
            ),
            terminalIntentions: _zero,
            throughRelations: ContributionCounts(planned: 2, contribution: 0),
          ),
          details: IntentionStatisticsIntermediateDetails(
            rootIntentions: sources,
            terminalIntentions: actions,
          ),
          calendar: IntentionStatisticsMonthCalendar(
            period: StatisticsMonth(2026, 10),
            statuses: {
              CalendarDate.fromParts(2026, 10, 5):
                  ActionDayStatus.hasIncomplete,
            },
          ),
        ),
        throwsA(isA<StatisticsDataValidationException>()),
      );
    }
  });
}

final _zero = ContributionCounts(planned: 0, contribution: 0);

StatisticsBreakdownFirstPage<StatisticsItem> _emptyIntentions() =>
    StatisticsBreakdownFirstPage(
      items: const [],
      totalItems: 0,
      nextCursor: null,
    );

IntentionStatisticsQuery _query(StatisticsPeriod period) =>
    IntentionStatisticsQuery(
      intentionId: _id,
      period: period,
      view: StatisticsView.throughRelations,
      pageSize: 100,
    );

IntentionStatisticsSection _section({
  IntentionStatisticsQuery? query,
  IntentionStatisticsCards? cards,
  IntentionStatisticsViewDetails? details,
  IntentionStatisticsCalendar? calendar,
}) => IntentionStatisticsSection(
  query: query ?? _query(StatisticsMonth(2026, 10)),
  revision: const _TestRevision(),
  cards:
      cards ??
      IntentionStatisticsCards(
        rootIntentions: _zero,
        intermediateIntentions: _zero,
        terminalIntentions: _zero,
        throughRelations: _zero,
      ),
  periodCounts: ContributionCounts(planned: 21, contribution: 4),
  details:
      details ??
      IntentionStatisticsThroughRelationsDetails(
        explicitPathActions: 0,
        relations: StatisticsBreakdownFirstPage<StatisticsRelationItem>(
          items: const [],
          totalItems: 0,
          nextCursor: null,
        ),
        terminalIntentions: _emptyIntentions(),
      ),
  calendar:
      calendar ??
      IntentionStatisticsMonthCalendar(
        period: StatisticsMonth(2026, 10),
        statuses: const {},
      ),
);

final class _TestRevision implements GraphRevision {
  const _TestRevision();

  @override
  GraphRevisionOrder compareTo(GraphRevision other) => identical(this, other)
      ? GraphRevisionOrder.same
      : GraphRevisionOrder.differentEpoch;
}

final _id = switch (IntentionId.decode(
  '018f0b5d-6b2e-7c80-8000-000000000001',
)) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw StateError('Некорректная фикстура.'),
};
