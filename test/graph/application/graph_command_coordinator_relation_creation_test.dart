import 'dart:async';

import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
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

void main() {
  group('GraphCommandCoordinator — создание долговременной связи', () {
    test(
      'ключ формы блокирует повтор, не мешая независимому намерению',
      () async {
        final repository = _ControlledPersonalGraphRepository();
        final coordinator = _coordinator(repository);
        final formKey = LongTermRelationCreationFormKey();

        final accepted = coordinator.acceptRelationCreation(
          formKey,
          _createRelation(),
        );
        final repeated = coordinator.acceptRelationCreation(
          formKey,
          _createRelation(),
        );
        final independent = coordinator.acceptCreation(
          IntentionCreationFormKey(),
          const CreateIntention(title: 'Намерение', description: null),
        );

        expect(accepted, isA<LongTermRelationCommandAccepted>());
        expect(repeated, isA<LongTermRelationCommandAlreadyRunning>());
        expect(independent, isA<IntentionCommandAccepted>());
        expect(repository.commands, [
          isA<CreateLongTermRelation>(),
          isA<CreateIntention>(),
        ]);

        repository.complete(
          0,
          const GraphCommandFailed<
            LongTermRelationCommandSuccess,
            LongTermRelationCommandFailure
          >(LongTermRelationUnavailableFailure()),
        );
        repository.complete(
          1,
          const ResultFailure<ConfirmedGraphResult<IntentionCommandSuccess>>(
            IntentionUnavailableFailure(),
          ),
        );
        await (accepted as LongTermRelationCommandAccepted).future;
        await (independent as IntentionCommandAccepted).future;
        await coordinator.shutdown();
      },
    );

    test('публикует намерения и связи одним упорядоченным каналом', () async {
      final repository = _ControlledPersonalGraphRepository();
      final coordinator = _coordinator(repository);
      final completions = <GraphCommandCompletion>[];
      final subscription = coordinator.completions.listen(completions.add);

      final intention = coordinator.acceptCreation(
        IntentionCreationFormKey(),
        const CreateIntention(title: 'Намерение', description: null),
      ) as IntentionCommandAccepted;
      final relation = coordinator.acceptRelationCreation(
        LongTermRelationCreationFormKey(),
        _createRelation(),
      ) as LongTermRelationCommandAccepted;

      repository.complete(
        1,
        const GraphCommandFailed<
          LongTermRelationCommandSuccess,
          LongTermRelationCommandFailure
        >(LongTermRelationUnavailableFailure()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(completions, isEmpty);

      repository.complete(
        0,
        const ResultFailure<ConfirmedGraphResult<IntentionCommandSuccess>>(
          IntentionUnavailableFailure(),
        ),
      );
      final intentionCompletion = await intention.future;
      final relationCompletion = await relation.future;

      expect(completions, [
        same(intentionCompletion),
        same(relationCompletion),
      ]);
      expect(relationCompletion.kind, LongTermRelationCommandKind.create);

      await subscription.cancel();
      await coordinator.shutdown();
    });

    test('завершает принятую команду после ухода формы без повтора', () async {
      final repository = _ControlledPersonalGraphRepository();
      final coordinator = _coordinator(repository);
      final formKey = LongTermRelationCreationFormKey();

      final accepted = coordinator.acceptRelationCreation(
        formKey,
        _createRelation(),
      ) as LongTermRelationCommandAccepted;
      expect(coordinator.isKeyRunning(formKey), isTrue);

      repository.complete(
        0,
        const GraphCommandFailed<
          LongTermRelationCommandSuccess,
          LongTermRelationCommandFailure
        >(LongTermRelationUnavailableFailure()),
      );
      final completion = await accepted.future;

      expect(
        completion.result,
        isA<
          GraphResultFailure<
            LongTermRelationCommandSuccess,
            LongTermRelationCommandFailure
          >
        >(),
      );
      expect(repository.commands, hasLength(1));
      expect(coordinator.isKeyRunning(formKey), isFalse);
      await coordinator.shutdown();
    });

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

    test('shutdown ждёт создание связи и запрещает новую работу', () async {
      final repository = _ControlledPersonalGraphRepository();
      final coordinator = _coordinator(repository);
      final accepted = coordinator.acceptRelationCreation(
        LongTermRelationCreationFormKey(),
        _createRelation(),
      ) as LongTermRelationCommandAccepted;

      final shutdown = coordinator.shutdown();
      var shutdownCompleted = false;
      unawaited(shutdown.then((_) => shutdownCompleted = true));

      expect(
        coordinator.acceptRelationCreation(
          LongTermRelationCreationFormKey(),
          _createRelation(),
        ),
        isA<GraphCommandCoordinatorDraining>(),
      );
      await Future<void>.delayed(Duration.zero);
      expect(shutdownCompleted, isFalse);

      repository.complete(
        0,
        const GraphCommandFailed<
          LongTermRelationCommandSuccess,
          LongTermRelationCommandFailure
        >(LongTermRelationUnavailableFailure()),
      );
      await accepted.future;
      await shutdown;
      expect(shutdownCompleted, isTrue);
    });
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
    implements PersonalGraphRepository {
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

  void complete(int index, Object result) => _results[index].complete(result);

  @override
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  ) => throw UnsupportedError('Каталог не используется в этих тестах.');

  @override
  Future<Result<GraphSnapshot<RelationCounts>>> getRelationCounts(
    IntentionId intentionId,
  ) => throw UnsupportedError('Сводка не используется в этих тестах.');

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
