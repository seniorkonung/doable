import 'package:doable/src/daily_choice/application/daily_choice_catalog.dart';
import 'package:doable/src/graph/application/selected_relations.dart';

import 'dart:async';

import 'package:doable/src/daily_choice/application/choice_path_continuations.dart';
import 'package:doable/src/daily_choice/application/choice_path_suggestions.dart';

import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/favorite_read_contract_test_fallback.dart';
import '../../support/tag_read_contract_test_fallback.dart';
import '../../support/catalog_reconciliation_test_fallback.dart';

void main() {
  group('GraphCommandCoordinator — создание долговременной связи', () {
    test(
      'преобразует неожиданную ошибку repository в terminal outcome',
      () async {
        final repository = _ControlledPersonalGraphRepository()
          ..nextError = StateError('внутренняя ошибка');
        final coordinator = _coordinator(repository);

        final accepted = coordinator.acceptRelationCreation(
          LongTermRelationCreationFormKey(),
          _createRelation(),
        ) as LongTermRelationCommandAccepted;
        final completion = await accepted.future;

        expect(
          completion.result,
          isA<
                GraphResultFailure<
                  LongTermRelationCommandSuccess,
                  LongTermRelationCommandFailure
                >
              >()
              .having(
                (result) => result.failure,
                'отказ',
                isA<LongTermRelationUnexpectedFailure>(),
              ),
        );
        await coordinator.shutdown();
      },
    );
  });
}

GraphCommandCoordinator _coordinator(PersonalGraphRepository repository) {
  final container = ProviderContainer.test(
    overrides: [personalGraphRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);
  return container.read(graphCommandCoordinatorProvider.notifier);
}

CreateLongTermRelation _createRelation() => CreateLongTermRelation(
  sourceIntentionId: _id(_sourceUuid),
  relatedIntentionId: _id(_relatedUuid),
  type: LongTermRelationType.need,
  priority: RelationPriority.p2,
  description: null,
);

final class _ControlledPersonalGraphRepository
    with
        TagReadContractTestFallback,
        FavoriteReadContractTestFallback,
        CatalogReconciliationTestFallback
    implements PersonalGraphRepository {
  @override
  Future<ChoicePathSuggestionsResult> getChoicePathSuggestions(
    ChoicePathSuggestionsQuery query,
  ) => throw UnimplementedError();

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

  final commands = <Object>[];
  final _results = <Completer<Object>>[];
  Object? nextError;

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    commands.add(command);
    final error = nextError;
    if (error != null) {
      nextError = null;
      throw error;
    }
    final result = Completer<Object>();
    _results.add(result);
    return await result.future as GraphCommandResult<TSuccess, TFailure>;
  }

  @override
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  ) => throw UnsupportedError('Каталог не используется в этих тестах.');

  @override
  Future<Result<GraphSnapshot<RelationCounts>>> getRelationCounts(
    IntentionId intentionId,
  ) => throw UnsupportedError('Сводка не используется в этих тестах.');

  @override
  Future<DailyChoiceCatalogPageResult> getDailyChoiceCatalogPage(
    DailyChoiceCatalogQuery query,
  ) => throw UnsupportedError(
    'Каталог дневных выборов не используется в этом тесте.',
  );

  @override
  Future<RelationGroupPageResult> getRelationGroupPage(
    RelationGroupPageQuery query,
  ) => throw UnsupportedError('Группы связей не используются в этих тестах.');

  @override
  Stream<LongTermRelationReadResult> watchRelation(LongTermRelationId id) =>
      throw UnsupportedError('Связи не наблюдаются в этих тестах.');

  @override
  Stream<Result<GraphSnapshot<IntentionDetails?>>> watchIntention(
    IntentionId id,
  ) => throw UnsupportedError('Намерения не наблюдаются в этих тестах.');
}

IntentionId _id(String value) => switch (IntentionId.decode(value)) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw StateError(
    'Некорректный UUID fixture.',
  ),
};

const _sourceUuid = '018f47c2-6b7d-7abc-8def-0123456789ab';
const _relatedUuid = '018f47c2-6b7d-7abc-8def-0123456789ac';
