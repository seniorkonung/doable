import 'package:doable/src/daily_choice/application/daily_choice_catalog.dart';
import 'package:doable/src/graph/application/selected_relations.dart';

import 'dart:async';

import 'package:doable/src/daily_choice/application/choice_path_continuations.dart';

import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';

/// Репозиторий графа, управляемый тестом выбора участника.
///
/// Каталожные порции остаются единственным источником списка намерений.
/// Подробные чтения намерения и его соседства только открываются и не
/// завершаются: переход к подробным данным проверяется отдельно от выбора.
final class ControlledParticipantPickerRepository
    implements PersonalGraphRepository {
  @override
  Future<ChoicePathContinuationResult> getChoicePathContinuations(
    ChoicePathContinuationQuery query,
  ) => throw UnimplementedError();

  @override
  Future<DailyChoiceReadResult> getDailyChoice(DailyChoiceId id) =>
      throw UnsupportedError(
        'Чтение дневного выбора не используется этим тестом.',
      );

  @override
  Stream<DailyChoiceReadResult> watchDailyChoice(DailyChoiceId id) =>
      throw UnsupportedError(
        'Наблюдение дневного выбора не используется этим тестом.',
      );

  @override
  Future<SelectedRelationsReadResult> getSelectedRelations(
    SelectedRelationsQuery query,
  ) => throw UnsupportedError(
    'Чтение выбранных связей не используется в этом тесте.',
  );

  @override
  Stream<SelectedRelationsReadResult> watchSelectedRelations(
    SelectedRelationsQuery query,
  ) => throw UnsupportedError(
    'Наблюдение выбранных связей не используется в этом тесте.',
  );

  final queries = <IntentionCatalogQuery>[];
  final _requests = <Completer<Result<IntentionCatalogPage>>>[];
  final _intentionStreams =
      <StreamController<Result<GraphSnapshot<IntentionDetails?>>>>[];

  IntentionCatalogQuery queryAt(int index) => queries[index];

  void complete(int index, Result<IntentionCatalogPage> result) {
    _requests[index].complete(result);
  }

  void dispose() {
    for (final controller in _intentionStreams) {
      unawaited(controller.close());
    }
  }

  @override
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  ) {
    queries.add(query);
    final request = Completer<Result<IntentionCatalogPage>>();
    _requests.add(request);
    return request.future;
  }

  @override
  Stream<Result<GraphSnapshot<IntentionDetails?>>> watchIntention(
    IntentionId id,
  ) {
    final controller =
        StreamController<Result<GraphSnapshot<IntentionDetails?>>>.broadcast();
    _intentionStreams.add(controller);
    return controller.stream;
  }

  @override
  Future<Result<GraphSnapshot<RelationCounts>>> getRelationCounts(
    IntentionId intentionId,
  ) => Completer<Result<GraphSnapshot<RelationCounts>>>().future;

  @override
  Future<DailyChoiceCatalogPageResult> getDailyChoiceCatalogPage(
    DailyChoiceCatalogQuery query,
  ) => throw UnsupportedError(
    'Каталог дневных выборов не используется в этом тесте.',
  );

  @override
  Future<RelationGroupPageResult> getRelationGroupPage(
    RelationGroupQuery query,
  ) => Completer<RelationGroupPageResult>().future;

  @override
  Stream<LongTermRelationReadResult> watchRelation(LongTermRelationId id) =>
      throw UnsupportedError('Связи не наблюдаются в тесте выбора участника.');

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) => throw UnsupportedError(
    'Команды не выполняются в тесте выбора участника.',
  );
}

final class TestPickerCursor implements IntentionCatalogCursor {
  const TestPickerCursor();
}

final class TestPickerRevision implements GraphRevision {
  const TestPickerRevision(this.sequence);

  final int sequence;

  @override
  GraphRevisionOrder compareTo(GraphRevision other) {
    if (other is! TestPickerRevision) {
      return GraphRevisionOrder.differentEpoch;
    }
    final comparison = sequence.compareTo(other.sequence);
    if (comparison < 0) return GraphRevisionOrder.older;
    if (comparison > 0) return GraphRevisionOrder.newer;
    return GraphRevisionOrder.same;
  }
}
