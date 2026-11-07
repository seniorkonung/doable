import 'dart:async';

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
import 'package:doable/src/long_term_relation/application/intention_relation_group.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/tag_read_contract_test_fallback.dart';
import '../../support/action_read_contract_test_fallback.dart';
import '../../support/statistics_read_contract_test_fallback.dart';

void main() {
  group('GraphCommandCoordinator — создание долговременной связи', () {
    test('добавление блокирует только тот поиск, который его принял', () async {
      final repository = _ControlledPersonalGraphRepository();
      final coordinator = _coordinator(repository);
      final key = RelationsAdditionSearchKey();
      final first = coordinator.acceptRelationsAddition(
        key,
        _addition(),
      ) as LongTermRelationCommandAccepted;
      expect(
        coordinator.acceptRelationsAddition(key, _addition()),
        isA<LongTermRelationCommandAlreadyRunning>(),
      );
      final second = coordinator.acceptRelationsAddition(
        RelationsAdditionSearchKey(),
        _addition(),
      ) as LongTermRelationCommandAccepted;
      expect(repository.commands, hasLength(2));
      coordinator.releaseInitiatorPresentation(first.token);
      repository.completeFailure(0);
      repository.completeFailure(1);
      await first.future;
      await second.future;
      expect(coordinator.isKeyRunning(key), isFalse);
      await coordinator.shutdown();
    });

    test(
      'отказ добавления после ухода поиска предъявляется оболочке один раз',
      () async {
        final repository = _ControlledPersonalGraphRepository();
        final coordinator = _coordinator(repository);
        final registration = coordinator.registerAppPresentation();
        final accepted = coordinator.acceptRelationsAddition(
          RelationsAdditionSearchKey(),
          _addition(),
        ) as LongTermRelationCommandAccepted;
        coordinator.releaseInitiatorPresentation(accepted.token);
        repository.completeFailure(0);
        await accepted.future;
        final claim = await registration.nextClaim();
        expect(claim, isNotNull);
        expect(
          claim!.completions.single,
          isA<LongTermRelationPresentableCompletion>(),
        );
        expect(coordinator.claimInitiatorFailure(accepted.token), isNull);
        coordinator.confirmAppPresentation(claim, [accepted.token]);
        expect(coordinator.claimInitiatorFailure(accepted.token), isNull);
        await coordinator.shutdown();
      },
    );

    test('отказ добавления принадлежит открытому поиску', () async {
      final repository = _ControlledPersonalGraphRepository();
      final coordinator = _coordinator(repository);
      final accepted = coordinator.acceptRelationsAddition(
        RelationsAdditionSearchKey(),
        _addition(),
      ) as LongTermRelationCommandAccepted;
      repository.completeFailure(0);
      await accepted.future;
      final claim = coordinator.claimInitiatorFailure(accepted.token);
      expect(claim, isNotNull);
      coordinator.confirmPresentation(claim!);
      expect(coordinator.claimInitiatorFailure(accepted.token), isNull);
      await coordinator.shutdown();
    });
    test(
      'преобразует неожиданную ошибку repository в terminal outcome',
      () async {
        final repository = _ControlledPersonalGraphRepository()
          ..nextError = StateError('внутренняя ошибка');
        final coordinator = _coordinator(repository);

        final accepted = coordinator.acceptRelationsAddition(
          RelationsAdditionSearchKey(),
          _addition(),
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

AddLongTermRelations _addition() => AddLongTermRelations(
  pageIntentionId: _id(_sourceUuid),
  group: IntentionRelationGroup.needs,
  candidateIds: [_id(_relatedUuid)],
);

final class _ControlledPersonalGraphRepository
    with
        ActionReadContractTestFallback,
        StatisticsReadContractTestFallback,
        TagReadContractTestFallback
    implements PersonalGraphRepository {
  final commands = <Object>[];
  final _results = <Completer<Object>>[];
  Object? nextError;

  void completeFailure(int index) => _results[index].complete(
    const GraphResultFailure<
      LongTermRelationCommandSuccess,
      LongTermRelationCommandFailure
    >(LongTermRelationUnavailableFailure()),
  );

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
  Future<RelationGroupPageResult> getRelationGroupPage(
    RelationGroupQuery query,
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
