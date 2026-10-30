import 'package:doable/src/daily_choice/application/daily_choice_day_statuses.dart';
import 'package:doable/src/daily_choice/application/daily_choice_catalog.dart';

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
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/long_term_relation/presentation/participant_picker/relation_participant_choice.dart';

import '../../../support/tag_read_contract_test_fallback.dart';
import '../../../support/statistics_read_contract_test_fallback.dart';
import '../../../support/intention_type_counts.dart';

/// Поток создания без формы: экран поиска здесь проверяется отдельно от неё.
const testRelationCreationFlow = RelationCreationChoiceFlow(
  restore: _NoRelationRestore(),
  priority: null,
  description: '',
);

/// Дескриптор восстановления, продолжение потока которого задаёт тест.
final class ControlledRelationRestore implements RelationCreationRestore {
  @override
  bool canContinue = true;

  @override
  void accept(LongTermRelationId relationId) => throw UnsupportedError(
    'Восстановление не выполняется в тесте выбора участника.',
  );
}

final class _NoRelationRestore implements RelationCreationRestore {
  const _NoRelationRestore();

  @override
  bool get canContinue => true;

  @override
  void accept(LongTermRelationId relationId) => throw UnsupportedError(
    'Восстановление не выполняется в тесте выбора участника.',
  );
}

/// Репозиторий графа, управляемый тестом выбора участника.
///
/// Каталожные порции остаются единственным источником списка намерений.
/// Подробные чтения намерения, его соседства и связи только открываются и не
/// завершаются: переход к подробным данным проверяется отдельно от выбора.
final class ControlledParticipantPickerRepository
    with StatisticsReadContractTestFallback, TagReadContractTestFallback
    implements PersonalGraphRepository {
  @override
  Future<DailyChoiceDayStatusesReadResult> getDailyChoiceDayStatuses(
    DailyChoiceDayStatusQuery query,
  ) => throw UnsupportedError(
    'Чтение состояний дней не используется в этом тесте.',
  );

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

  final queries = <IntentionCatalogQuery>[];
  final _requests = <Completer<Result<IntentionCatalogPage>>>[];
  final _intentionStreams =
      <StreamController<Result<GraphSnapshot<IntentionDetails?>>>>[];
  final _relationStreams = <StreamController<LongTermRelationReadResult>>[];

  /// Связи, подробный просмотр которых открывали, в порядке открытия.
  final watchedRelations = <LongTermRelationId>[];

  IntentionCatalogQuery queryAt(int index) => queries[index];

  void complete(int index, Result<IntentionCatalogPage> result) {
    _requests[index].complete(answerCatalogQuery(queries[index], result));
  }

  void dispose() {
    for (final controller in _intentionStreams) {
      unawaited(controller.close());
    }
    for (final controller in _relationStreams) {
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
  Future<DailyChoiceCatalogPageResult> getDailyChoiceCatalogPage(
    DailyChoiceCatalogQuery query,
  ) => throw UnsupportedError(
    'Каталог дневных выборов не используется в этом тесте.',
  );

  @override
  Future<RelationGroupPageResult> getRelationGroupPage(
    RelationGroupPageQuery query,
  ) => Completer<RelationGroupPageResult>().future;

  @override
  Stream<LongTermRelationReadResult> watchRelation(LongTermRelationId id) {
    watchedRelations.add(id);
    final controller = StreamController<LongTermRelationReadResult>.broadcast();
    _relationStreams.add(controller);
    return controller.stream;
  }

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
