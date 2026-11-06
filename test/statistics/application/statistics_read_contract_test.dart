import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/statistics/application/contribution_counts.dart';
import 'package:doable/src/statistics/application/statistics_period.dart';
import 'package:doable/src/statistics/application/statistics_read_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('запрос допускает порции от 1 до 100 и отклоняет выход за границы', () {
    StatisticsQuery query(int pageSize) => StatisticsQuery(
      period: StatisticsMonth(2026, 10),
      view: StatisticsView.rootIntentions,
      pageSize: pageSize,
    );

    for (final size in [1, 100]) {
      expect(query(size).pageSize, size);
    }
    for (final size in [0, 101]) {
      expect(
        () => query(size),
        throwsA(isA<StatisticsQueryValidationException>()),
      );
    }
  });

  test(
    'прочитанные меры не допускают отрицательных или избыточных вкладов',
    () {
      for (final (planned, contribution) in [(-1, 0), (0, -1), (1, 2)]) {
        expect(
          () =>
              ContributionCounts(planned: planned, contribution: contribution),
          throwsA(isA<StatisticsDataValidationException>()),
        );
      }
    },
  );

  test('элемент отклоняет отсутствие запланированного вклада', () {
    expect(
      () => StatisticsItem(
        id: _id,
        title: 'Высыпаться',
        archiveState: IntentionArchiveState.active,
        counts: ContributionCounts(planned: 0, contribution: 0),
      ),
      throwsA(isA<StatisticsDataValidationException>()),
    );
  });

  test('первая порция отклоняет отрицательное число элементов', () {
    expect(
      () => StatisticsFirstPage(
        items: const [],
        summary: ContributionCounts(planned: 0, contribution: 0),
        totalItems: -1,
        revision: const _TestRevision(),
        nextCursor: null,
      ),
      throwsA(isA<StatisticsDataValidationException>()),
    );
  });

  test(
    'порция копирует элементы и запрещает изменение опубликованного списка',
    () {
      final item = StatisticsItem(
        id: _id,
        title: 'Высыпаться',
        archiveState: IntentionArchiveState.archived,
        counts: ContributionCounts(planned: 7, contribution: 3),
      );
      final source = [item];
      final StatisticsPage page = StatisticsFirstPage(
        items: source,
        summary: ContributionCounts(planned: 21, contribution: 4),
        totalItems: 1,
        revision: const _TestRevision(),
        nextCursor: null,
      );

      source.clear();

      expect(page.items, [item]);
      expect(() => page.items.clear(), throwsUnsupportedError);
    },
  );
}

final _id = switch (IntentionId.decode(
  '018f0b5d-6b2e-7c80-8000-000000000001',
)) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw StateError('Некорректная фикстура.'),
};

final class _TestRevision implements GraphRevision {
  const _TestRevision();

  @override
  GraphRevisionOrder compareTo(GraphRevision other) => identical(this, other)
      ? GraphRevisionOrder.same
      : GraphRevisionOrder.differentEpoch;
}
