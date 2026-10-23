import 'dart:async';

import 'package:doable/src/daily_choice/application/daily_choice_day_statuses.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_local_date_provider.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/statistics/application/contribution_counts.dart';
import 'package:doable/src/statistics/application/intention_statistics_breakdown.dart';
import 'package:doable/src/statistics/application/intention_statistics_calendar.dart';
import 'package:doable/src/statistics/application/intention_statistics_read_contract.dart';
import 'package:doable/src/statistics/application/intention_statistics_target.dart';
import 'package:doable/src/statistics/application/statistics_period.dart';
import 'package:doable/src/statistics/application/statistics_read_contract.dart';
import 'package:doable/src/statistics/presentation/intention_statistics_state.dart';
import 'package:doable/src/statistics/presentation/intention_statistics_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';

import '../../support/tag_positions.dart';

final statisticsToday = CalendarDate.fromParts(2026, 10, 12);

final class IntentionStatisticsHarness {
  IntentionStatisticsHarness() {
    container = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(reader),
        dailyChoiceLocalDateSourceProvider.overrideWithValue(
          () => DailyChoiceLocalDay(
            date: statisticsToday,
            untilNextDate: const Duration(hours: 12),
          ),
        ),
      ],
    );
  }

  final reader = IntentionStatisticsReader();
  late final ProviderContainer container;

  IntentionStatisticsTestPage open({
    IntentionStatisticsTarget? target,
    bool visible = true,
  }) {
    final page = IntentionStatisticsTestPage(container, target);
    if (visible) page.model.setVisible(true);
    return page;
  }

  var _tag = Tag(
    id: (TagId.decode(
      '00000000-0000-4000-8000-000000000001',
    ) as TagIdDecodingSuccess).id,
    name: TagName.fromInput('Тег'),
    color: null,
    position: tagPositionAt(1000),
  );

  Future<void> change(int revision, {int epoch = 0}) async {
    final next = Tag(
      id: _tag.id,
      name: TagName.fromInput('Тег $epoch $revision'),
      color: _tag.color,
      position: _tag.position,
    );
    final stamp = StatisticsTestRevision(revision, epoch);
    reader.commandResult = TagCommandSucceeded(
      ConfirmedGraphResult(
        revision: stamp,
        value: next.name == _tag.name
            ? TagUnchanged(TagUnchangedChange(revision: stamp, tag: _tag))
            : TagUpdated(
                TagUpdatedChange(revision: stamp, before: _tag, after: next),
              ),
      ),
    );
    final accepted =
        container
                .read(graphCommandCoordinatorProvider.notifier)
                .acceptTagUpdate(
                  UpdateTag(tagId: _tag.id, name: next.name, color: _tag.color),
                )
            as TagCommandAccepted;
    await accepted.future;
    _tag = next;
    await pumpEventQueue();
  }

  void dispose() => container.dispose();
}

final class IntentionStatisticsTestPage {
  IntentionStatisticsTestPage(
    this.container,
    IntentionStatisticsTarget? target,
  ) {
    provider = intentionStatisticsViewModelProvider(
      statisticsId(1),
      Object(),
      target: target,
    );
    subscription = container.listen(provider, (_, _) {});
    model = container.read(provider.notifier);
  }

  final ProviderContainer container;
  late final IntentionStatisticsViewModelProvider provider;
  late final ProviderSubscription<IntentionStatisticsState> subscription;
  late final IntentionStatisticsViewModel model;
  IntentionStatisticsState get state => container.read(provider);
  IntentionStatisticsLoaded get loaded =>
      state.read as IntentionStatisticsLoaded;
  void close() => subscription.close();
}

final class IntentionStatisticsReader implements PersonalGraphRepository {
  final queries = <IntentionStatisticsQuery>[];
  final responses = <Completer<IntentionStatisticsSectionResult>>[];
  final continuations = <PendingStatisticsBreakdown<Object?>>[];
  late TagCommandResult commandResult;

  @override
  Future<IntentionStatisticsSectionResult> getIntentionStatisticsSection(
    IntentionStatisticsQuery query,
  ) {
    queries.add(query);
    final response = Completer<IntentionStatisticsSectionResult>();
    responses.add(response);
    return response.future;
  }

  @override
  Future<IntentionStatisticsBreakdownResult<T>>
  getIntentionStatisticsBreakdown<T>(StatisticsBreakdownCursor<T> cursor) {
    final pending = PendingStatisticsBreakdown<T>();
    continuations.add(pending);
    return pending.response.future;
  }

  void section(
    int index, {
    int marker = 1,
    int revision = 0,
    int epoch = 0,
    UncompletedSplit? split,
    int count = 1,
    int? total,
    int? relationsTotal,
    bool empty = false,
    StatisticsBreakdownCursor<StatisticsItem>? sourcesCursor,
    StatisticsBreakdownCursor<StatisticsItem>? actionsCursor,
    StatisticsBreakdownCursor<StatisticsRelationItem>? relationsCursor,
  }) {
    final query = queries[index];
    final counts = ContributionCounts(
      planned: empty ? 0 : total ?? count,
      contribution: empty
          ? 0
          : (total ?? count) - (split?.missed ?? 0) - (split?.upcoming ?? 0),
    );
    final items = empty
        ? <StatisticsItem>[]
        : List.generate(count, (i) => statisticsItem(marker + count - 1 - i));
    StatisticsBreakdownFirstPage<StatisticsItem> intentions([
      StatisticsBreakdownCursor<StatisticsItem>? cursor,
    ]) => StatisticsBreakdownFirstPage(
      items: items,
      totalItems: empty ? 0 : total ?? count,
      nextCursor: cursor,
    );
    final uncompleted = split ?? UncompletedSplit(missed: 0, upcoming: 0);
    final details = switch (query.view) {
      StatisticsView.sourceIntentions => IntentionStatisticsSourceDetails(
        uncompleted: uncompleted,
        selectedActions: intentions(actionsCursor),
      ),
      StatisticsView.intermediateIntentions =>
        IntentionStatisticsIntermediateDetails(
          uncompleted: uncompleted,
          sourceIntentions: intentions(sourcesCursor),
          selectedActions: intentions(actionsCursor),
        ),
      StatisticsView.selectedActions => IntentionStatisticsSelectedDetails(
        uncompleted: uncompleted,
        sourceIntentions: intentions(sourcesCursor),
      ),
      StatisticsView.throughRelations =>
        IntentionStatisticsThroughRelationsDetails(
          uncompleted: uncompleted,
          explicitPathChoices: 0,
          relations: StatisticsBreakdownFirstPage(
            items: empty
                ? <StatisticsRelationItem>[]
                : List.generate(
                    count,
                    (i) => statisticsRelation(
                      marker + count - 1 - i,
                      planned: relationsTotal == null ? 1 : 3,
                    ),
                  ),
            totalItems: empty ? 0 : relationsTotal ?? total ?? count,
            nextCursor: relationsCursor,
          ),
          selectedActions: intentions(actionsCursor),
        ),
    };
    responses[index].complete(
      IntentionStatisticsSectionSuccess(
        IntentionStatisticsSection(
          query: query,
          revision: StatisticsTestRevision(revision, epoch),
          cards: IntentionStatisticsCards(
            sourceIntentions:
                empty && query.view != StatisticsView.sourceIntentions
                ? ContributionCounts(planned: 1, contribution: 1)
                : query.view == StatisticsView.sourceIntentions
                ? counts
                : ContributionCounts(planned: 0, contribution: 0),
            intermediateIntentions:
                query.view == StatisticsView.intermediateIntentions
                ? counts
                : ContributionCounts(planned: 0, contribution: 0),
            selectedActions: query.view == StatisticsView.selectedActions
                ? counts
                : ContributionCounts(planned: 0, contribution: 0),
            throughRelations:
                empty && query.view != StatisticsView.throughRelations
                ? ContributionCounts(planned: 1, contribution: 1)
                : counts,
          ),
          periodCounts: ContributionCounts(
            planned: empty ? 20 : (total ?? count) + 20,
            contribution: empty ? 20 : (total ?? count) + 20,
          ),
          details: details,
          calendar: switch (query.period) {
            final StatisticsMonth period => IntentionStatisticsMonthCalendar(
              period: period,
              statuses: empty
                  ? {}
                  : {period.firstDate: DailyChoiceDayStatus.allCompleted},
            ),
            final StatisticsYear period => IntentionStatisticsYearCalendar(
              period: period,
              months: List.generate(
                12,
                (i) => i == 0
                    ? counts
                    : ContributionCounts(planned: 0, contribution: 0),
              ),
            ),
          },
        ),
      ),
    );
  }

  void fail(int index, StatisticsReadFailure failure) =>
      responses[index].complete(IntentionStatisticsSectionError(failure));
  void more<T>(
    int index,
    List<T> items, {
    StatisticsBreakdownCursor<T>? cursor,
    int revision = 0,
    int epoch = 0,
  }) =>
      (continuations[index] as PendingStatisticsBreakdown<T>).response.complete(
        IntentionStatisticsBreakdownSuccess(
          StatisticsBreakdownContinuationPage(
            items: items,
            revision: StatisticsTestRevision(revision, epoch),
            nextCursor: cursor,
          ),
        ),
      );
  void failMore<T>(int index, StatisticsReadFailure failure) =>
      (continuations[index] as PendingStatisticsBreakdown<T>).response.complete(
        IntentionStatisticsBreakdownError(failure),
      );

  @override
  Future<GraphCommandResult<T, F>>
  execute<T extends GraphCommandOutcome, F extends GraphCommandFailure>(
    GraphCommand<T, F> command,
  ) async => commandResult as GraphCommandResult<T, F>;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'В этой проверке используется только статистика намерения.',
  );
}

final class PendingStatisticsBreakdown<T> {
  final response = Completer<IntentionStatisticsBreakdownResult<T>>();
}

StatisticsItem statisticsItem(int id) => StatisticsItem(
  id: statisticsId(id),
  title: 'Намерение $id',
  archiveState: IntentionArchiveState.active,
  counts: ContributionCounts(planned: 1, contribution: 1),
);
StatisticsRelationItem statisticsRelation(int id, {int planned = 1}) =>
    StatisticsRelationItem(
      id: switch (LongTermRelationId.decode(
        statisticsId(id).toCanonicalString(),
      )) {
        LongTermRelationIdDecodingSuccess(:final id) => id,
        InvalidLongTermRelationIdDecoding() => throw StateError(
          'Некорректный UUID связи.',
        ),
      },
      scope: RelationScope.active,
      relatedIntention: StatisticsItem(
        id: statisticsId(id),
        title: 'Намерение $id',
        archiveState: IntentionArchiveState.active,
        counts: ContributionCounts(planned: planned, contribution: planned),
      ),
    );
IntentionId statisticsId(int value) => switch (IntentionId.decode(
  '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}',
)) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw StateError(
    'Некорректный UUID фикстуры.',
  ),
};

final class StatisticsTestRevision implements GraphRevision {
  const StatisticsTestRevision(this.value, [this.epoch = 0]);
  final int value;
  final int epoch;
  @override
  GraphRevisionOrder compareTo(GraphRevision other) =>
      other is! StatisticsTestRevision || other.epoch != epoch
      ? GraphRevisionOrder.differentEpoch
      : value < other.value
      ? GraphRevisionOrder.older
      : value > other.value
      ? GraphRevisionOrder.newer
      : GraphRevisionOrder.same;
}

final class StatisticsTestCursor<T> implements StatisticsBreakdownCursor<T> {}
