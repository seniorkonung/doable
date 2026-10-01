import 'dart:async';

import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/delete_blocking_relations.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/tag_read_contract_test_fallback.dart';
import '../../support/catalog_reconciliation_test_fallback.dart';
import '../../support/tag_assignment_changed.dart';

void main() {
  test(
    'ключ формы отклоняет повтор без очереди, другие формы независимы',
    () async {
      final repository = _ControlledRepository();
      final coordinator = _coordinator(repository);
      final form = TagCreationFormKey();
      final first = coordinator.acceptTagCreation(
        form,
        CreateTag(_name),
      ) as TagCommandAccepted;
      expect(
        coordinator.acceptTagCreation(form, CreateTag(_name)),
        isA<TagCommandAlreadyRunning>(),
      );
      final second = coordinator.acceptTagCreation(
        TagCreationFormKey(),
        CreateTag(_name),
      ) as TagCommandAccepted;
      expect(repository.commands, hasLength(2));
      expect(coordinator.isKeyRunning(form), isTrue);

      final completions = <GraphCommandCompletion>[];
      final subscription = coordinator.completions.listen(completions.add);
      repository.complete(1, const TagCommandFailed(TagUnavailableFailure()));
      await Future<void>.delayed(Duration.zero);
      expect(completions, isEmpty);
      expect(coordinator.isKeyRunning(form), isTrue);
      repository.complete(0, _created());
      final firstCompletion = await first.future;
      final secondCompletion = await second.future;
      expect(firstCompletion.kind, TagCommandKind.create);
      expect(firstCompletion.confirmedChange?.revision, same(_revision));
      expect(firstCompletion.isFailure, isFalse);
      expect(completions, [same(firstCompletion), same(secondCompletion)]);
      expect(coordinator.isKeyRunning(form), isFalse);
      await subscription.cancel();
      await coordinator.shutdown();
    },
  );

  test(
    'переименование и удаление одного тега разделяют ключ после ухода',
    () async {
      final repository = _ControlledRepository();
      final coordinator = _coordinator(repository);
      final accepted = coordinator.acceptTagRename(
        RenameTag(tagId: _tagId, name: _name),
      ) as TagCommandAccepted;
      coordinator.releaseInitiatorPresentation(accepted.token);
      final registration = coordinator.registerAppPresentation();
      final claimFuture = registration.nextClaim();

      expect(coordinator.isTagRunning(_tagId), isTrue);
      expect(
        coordinator.acceptTagDelete(DeleteTag(_tagId)),
        isA<TagCommandAlreadyRunning>(),
      );
      expect(
        coordinator.acceptTagRename(RenameTag(tagId: _tagId, name: _name)),
        isA<TagCommandAlreadyRunning>(),
      );
      expect(repository.commands, hasLength(1));
      repository.complete(0, const TagCommandFailed(TagUnavailableFailure()));
      final completion = await accepted.future;
      final claim = await claimFuture;
      expect(claim?.completion, same(completion));
      expect(completion.isFailure, isTrue);
      expect(coordinator.claimInitiatorFailure(accepted.token), isNull);
      expect(coordinator.isTagRunning(_tagId), isFalse);
      coordinator.confirmPresentation(claim!);
      registration.release();
      await coordinator.shutdown();
    },
  );

  test(
    'исключение становится типизированным отказом и освобождает ключ',
    () async {
      final repository = _ControlledRepository();
      final coordinator = _coordinator(repository);
      final accepted = coordinator.acceptTagAssign(
        AssignTag(tagId: _tagId, intentionId: _intentionId),
      ) as TagCommandAccepted;
      repository.fail(0);
      final completion = await accepted.future;
      expect(completion.result, isA<GraphResultFailure>());
      expect(
        (completion.result as GraphResultFailure).failure,
        isA<TagUnexpectedFailure>(),
      );
      expect(coordinator.isTagRunning(_tagId), isFalse);
      expect(coordinator.isRunning(_intentionId), isFalse);
      await coordinator.shutdown();
    },
  );

  test('завершение работы ждёт назначение и отклоняет новые команды', () async {
    final repository = _ControlledRepository();
    final coordinator = _coordinator(repository);
    final accepted = coordinator.acceptTagAssign(
      AssignTag(tagId: _tagId, intentionId: _intentionId),
    ) as TagCommandAccepted;
    final shutdown = coordinator.shutdown();
    var finished = false;
    unawaited(shutdown.then((_) => finished = true));
    expect(
      coordinator.acceptTagDelete(DeleteTag(_tagId)),
      isA<GraphCommandCoordinatorDraining>(),
    );
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    expect(coordinator.isTagRunning(_tagId), isTrue);
    expect(coordinator.isRunning(_intentionId), isTrue);
    repository.complete(0, const TagCommandFailed(TagUnavailableFailure()));
    await accepted.future;
    await shutdown;
    expect(finished, isTrue);
    expect(coordinator.isTagRunning(_tagId), isFalse);
    expect(coordinator.isRunning(_intentionId), isFalse);
  });

  test('назначение намерению атомарно резервирует тег и намерение', () async {
    final repository = _ControlledRepository();
    final coordinator = _coordinator(repository);
    final command = AssignTag(tagId: _tagId, intentionId: _intentionId);
    final accepted = coordinator.acceptTagAssign(command) as TagCommandAccepted;

    expect(coordinator.isTagRunning(_tagId), isTrue);
    expect(coordinator.isRunning(_intentionId), isTrue);
    expect(
      coordinator.acceptTagAssign(command),
      isA<TagCommandAlreadyRunning>(),
    );
    expect(
      coordinator.acceptTagAssign(
        AssignTag(tagId: _otherTagId, intentionId: _intentionId),
      ),
      isA<TagCommandAlreadyRunning>(),
    );
    expect(coordinator.isTagRunning(_otherTagId), isFalse);
    expect(
      coordinator.acceptTagAssign(
        AssignTag(tagId: _tagId, intentionId: _otherIntentionId),
      ),
      isA<TagCommandAlreadyRunning>(),
    );
    expect(coordinator.isRunning(_otherIntentionId), isFalse);
    expect(
      coordinator.acceptExisting(
        DeleteIntention(_intentionId),
        presentationTitle: 'Намерение',
      ),
      isA<IntentionCommandAlreadyRunning>(),
    );
    expect(
      coordinator.acceptTagRename(RenameTag(tagId: _tagId, name: _name)),
      isA<TagCommandAlreadyRunning>(),
    );
    expect(repository.commands, [same(command)]);

    repository.complete(0, const TagCommandFailed(TagUnavailableFailure()));
    final completion = await accepted.future;
    expect(completion.kind, TagCommandKind.assign);
    expect(coordinator.isTagRunning(_tagId), isFalse);
    expect(coordinator.isRunning(_intentionId), isFalse);
    await coordinator.shutdown();
  });

  test('занятое намерение не оставляет резервирования тега', () async {
    final repository = _ControlledRepository();
    final coordinator = _coordinator(repository);
    final accepted = coordinator.acceptExisting(
      DeleteIntention(_intentionId),
      presentationTitle: 'Намерение',
    ) as IntentionCommandAccepted;
    final command = RemoveTagAssignment(
      tagId: _tagId,
      intentionId: _intentionId,
    );

    expect(
      coordinator.acceptTagRemoveAssignment(command),
      isA<TagCommandAlreadyRunning>(),
    );
    expect(coordinator.isTagRunning(_tagId), isFalse);
    expect(repository.commands, hasLength(1));
    final independent =
        coordinator.acceptTagDelete(DeleteTag(_tagId)) as TagCommandAccepted;
    repository.complete(
      0,
      const GraphCommandFailed(IntentionUnavailableFailure()),
    );
    repository.complete(1, const TagCommandFailed(TagUnavailableFailure()));
    await accepted.future;
    await independent.future;
    await coordinator.shutdown();
  });

  test('занятый тег не оставляет резервирования намерения', () async {
    final repository = _ControlledRepository();
    final coordinator = _coordinator(repository);
    final accepted =
        coordinator.acceptTagDelete(DeleteTag(_tagId)) as TagCommandAccepted;
    final command = AssignTag(tagId: _tagId, intentionId: _intentionId);

    expect(
      coordinator.acceptTagAssign(command),
      isA<TagCommandAlreadyRunning>(),
    );
    expect(coordinator.isRunning(_intentionId), isFalse);
    final independent = coordinator.acceptExisting(
      DeleteIntention(_intentionId),
      presentationTitle: 'Намерение',
    ) as IntentionCommandAccepted;
    expect(repository.commands, hasLength(2));

    repository.complete(0, const TagCommandFailed(TagUnavailableFailure()));
    repository.complete(
      1,
      const GraphCommandFailed(IntentionUnavailableFailure()),
    );
    await accepted.future;
    await independent.future;
    await coordinator.shutdown();
  });

  test('снятие назначения намерению конфликтует с массовым удалением в обоих порядках', () async {
    final repository = _ControlledRepository();
    final coordinator = _coordinator(repository);
    final command = RemoveTagAssignment(
      tagId: _tagId,
      intentionId: _intentionId,
    );
    final massDelete = DeleteBlockingRelations.longTerm(
      intentionId: _intentionId,
      relationIds: {_relationId},
    );
    final assignment =
        coordinator.acceptTagRemoveAssignment(command) as TagCommandAccepted;
    expect(coordinator.isTagRunning(_tagId), isTrue);
    expect(coordinator.isRunning(_intentionId), isTrue);
    expect(
      coordinator.acceptBlockingRelationsDelete(
        massDelete,
        presentationTitle: 'Намерение',
      ),
      isA<BlockingRelationsDeleteAlreadyRunning>(),
    );
    expect(coordinator.isRelationRunning(_relationId), isFalse);
    repository.complete(0, const TagCommandFailed(TagUnavailableFailure()));
    await assignment.future;

    final deletion = coordinator.acceptBlockingRelationsDelete(
      massDelete,
      presentationTitle: 'Намерение',
    ) as BlockingRelationsDeleteAccepted;
    expect(
      coordinator.acceptTagRemoveAssignment(command),
      isA<TagCommandAlreadyRunning>(),
    );
    expect(coordinator.isTagRunning(_tagId), isFalse);
    expect(repository.commands, [same(command), same(massDelete)]);
    repository.complete(
      1,
      const GraphCommandFailed(DeleteBlockingRelationsUnavailableFailure()),
    );
    await deletion.future;
    await coordinator.shutdown();
  });

  test(
    'успешное назначение публикует одно завершение и одно право оболочки',
    () async {
      final repository = _ControlledRepository();
      final coordinator = _coordinator(repository);
      final completions = <GraphCommandCompletion>[];
      final subscription = coordinator.completions.listen(completions.add);
      final registration = coordinator.registerAppPresentation();
      final command = AssignTag(tagId: _tagId, intentionId: _intentionId);
      final accepted =
          coordinator.acceptTagAssign(command) as TagCommandAccepted;
      coordinator.releaseInitiatorPresentation(accepted.token);
      final claimFuture = registration.nextClaim();

      repository.complete(
        0,
        TagCommandSucceeded(
          ConfirmedGraphResult(
            revision: _revision,
            value: testTagAssignmentChanged(
              TagAssignmentChangedChange(
                revision: _revision,
                assignment: command.assignment,
                state: TagAssignmentState.assigned,
              ),
            ),
          ),
        ),
      );
      final completion = await accepted.future;
      final claim = await claimFuture;
      expect(completion.token, same(accepted.token));
      expect(completion.confirmedChange?.revision, same(_revision));
      expect(completions, [same(completion)]);
      expect(claim?.completion, same(completion));
      expect(coordinator.claimInitiatorFailure(accepted.token), isNull);
      expect(coordinator.isTagRunning(_tagId), isFalse);
      expect(coordinator.isRunning(_intentionId), isFalse);
      coordinator.confirmPresentation(claim!);
      registration.release();
      await subscription.cancel();
      await coordinator.shutdown();
    },
  );

  test(
    'оба ключа заняты до публикации отказа после более ранней команды',
    () async {
      final repository = _ControlledRepository();
      final coordinator = _coordinator(repository);
      final earlier = coordinator.acceptTagCreation(
        TagCreationFormKey(),
        CreateTag(_name),
      ) as TagCommandAccepted;
      final command = RemoveTagAssignment(
        tagId: _tagId,
        intentionId: _intentionId,
      );
      final accepted =
          coordinator.acceptTagRemoveAssignment(command) as TagCommandAccepted;
      coordinator.releaseInitiatorPresentation(accepted.token);
      final registration = coordinator.registerAppPresentation();
      final claimFuture = registration.nextClaim();

      repository.complete(1, const TagCommandFailed(TagUnavailableFailure()));
      await Future<void>.delayed(Duration.zero);
      expect(coordinator.isTagRunning(_tagId), isTrue);
      expect(coordinator.isRunning(_intentionId), isTrue);
      expect(
        coordinator.acceptTagRemoveAssignment(command),
        isA<TagCommandAlreadyRunning>(),
      );
      expect(repository.commands, hasLength(2));

      repository.complete(0, const TagCommandFailed(TagUnavailableFailure()));
      await earlier.future;
      final completion = await accepted.future;
      final claim = await claimFuture;
      expect(claim?.completion, same(completion));
      expect(coordinator.claimInitiatorFailure(accepted.token), isNull);
      expect(coordinator.isTagRunning(_tagId), isFalse);
      expect(coordinator.isRunning(_intentionId), isFalse);
      coordinator.confirmPresentation(claim!);
      registration.release();
      await coordinator.shutdown();
    },
  );
}

GraphCommandCoordinator _coordinator(PersonalGraphRepository repository) {
  final container = ProviderContainer.test(
    overrides: [personalGraphRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);
  return container.read(graphCommandCoordinatorProvider.notifier);
}

final _tagId = (TagId.decode(
  '018f47c2-6b7d-7abc-8def-0123456789ab',
) as TagIdDecodingSuccess).id;
final _otherTagId = (TagId.decode(
  '018f47c2-6b7d-7abc-8def-0123456789ac',
) as TagIdDecodingSuccess).id;
final _name = TagName.fromInput('Важное');
final _intentionId = (IntentionId.decode(
  '018f47c2-6b7d-7abc-8def-0123456789a1',
) as IntentionIdDecodingSuccess).id;
final _otherIntentionId = (IntentionId.decode(
  '018f47c2-6b7d-7abc-8def-0123456789a2',
) as IntentionIdDecodingSuccess).id;
final _relationId = (LongTermRelationId.decode(
  '018f47c2-6b7d-7abc-8def-0123456789b1',
) as LongTermRelationIdDecodingSuccess).id;
const _revision = _Revision();

TagCommandSucceeded _created() => TagCommandSucceeded(
  ConfirmedGraphResult(
    revision: _revision,
    value: TagCreated(
      TagCreatedChange(
        revision: _revision,
        after: Tag(id: _tagId, name: _name),
      ),
    ),
  ),
);

final class _ControlledRepository
    with TagReadContractTestFallback, CatalogReconciliationTestFallback
    implements PersonalGraphRepository {
  final commands = <Object>[];
  final _results = <Completer<Object>>[];

  @override
  Future<GraphCommandResult<T, F>> execute<
    T extends GraphCommandOutcome,
    F extends GraphCommandFailure
  >(GraphCommand<T, F> command) async {
    commands.add(command);
    final result = Completer<Object>();
    _results.add(result);
    return await result.future as GraphCommandResult<T, F>;
  }

  void complete(int index, Object result) => _results[index].complete(result);
  void fail(int index) =>
      _results[index].completeError(StateError('Отказ записи'));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Revision implements GraphRevision {
  const _Revision();

  @override
  GraphRevisionOrder compareTo(GraphRevision other) => other is _Revision
      ? GraphRevisionOrder.same
      : GraphRevisionOrder.differentEpoch;
}
