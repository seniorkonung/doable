import 'dart:async';

import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/tag_read_contract_test_fallback.dart';

void main() {
  test('редактирование и удаление одного тега разделяют ключ', () async {
    final repository = _ControlledRepository();
    final coordinator = _coordinator(repository);
    final accepted = coordinator.acceptTagUpdate(
      UpdateTag(tagId: _tagId, name: _name, color: null),
    ) as TagCommandAccepted;
    final registration = coordinator.registerAppPresentation();
    final claimFuture = registration.nextClaim();

    expect(coordinator.isTagRunning(_tagId), isTrue);
    expect(
      coordinator.acceptTagDelete(DeleteTag(_tagId)),
      isA<TagCommandAlreadyRunning>(),
    );
    expect(
      coordinator.acceptTagUpdate(
        UpdateTag(tagId: _tagId, name: _name, color: null),
      ),
      isA<TagCommandAlreadyRunning>(),
    );
    expect(repository.commands, hasLength(1));
    repository.complete(0, const TagCommandFailed(TagUnavailableFailure()));
    final completion = await accepted.future;
    final claim = await claimFuture;
    expect(claim?.completions, [same(completion)]);
    expect(completion.isFailure, isTrue);
    expect(coordinator.claimInitiatorFailure(accepted.token), isNull);
    expect(coordinator.isTagRunning(_tagId), isFalse);
    coordinator.confirmAppPresentation(
      claim!,
      claim.completions.map((completion) => completion.token),
    );
    registration.release();
    await coordinator.shutdown();
  });

  test(
    'перестановка тега разделяет ключ с его изменением и удалением',
    () async {
      final repository = _ControlledRepository();
      final coordinator = _coordinator(repository);
      final move = MoveTag(tagId: _tagId, placement: TagPlacement.first);
      final accepted = coordinator.acceptTagMove(move) as TagCommandAccepted;

      expect(coordinator.isTagRunning(_tagId), isTrue);
      expect(coordinator.acceptTagMove(move), isA<TagCommandAlreadyRunning>());
      expect(
        coordinator.acceptTagUpdate(
          UpdateTag(tagId: _tagId, name: _name, color: null),
        ),
        isA<TagCommandAlreadyRunning>(),
      );
      expect(
        coordinator.acceptTagDelete(DeleteTag(_tagId)),
        isA<TagCommandAlreadyRunning>(),
      );
      expect(repository.commands, [same(move)]);

      repository.complete(0, const TagCommandFailed(TagUnavailableFailure()));
      final completion = await accepted.future;
      expect(completion.kind, TagCommandKind.move);
      expect(coordinator.isTagRunning(_tagId), isFalse);

      final update = coordinator.acceptTagUpdate(
        UpdateTag(tagId: _tagId, name: _name, color: null),
      ) as TagCommandAccepted;
      expect(coordinator.acceptTagMove(move), isA<TagCommandAlreadyRunning>());
      repository.complete(1, const TagCommandFailed(TagUnavailableFailure()));
      await update.future;
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
      coordinator.acceptTagUpdate(
        UpdateTag(tagId: _tagId, name: _name, color: null),
      ),
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

  test(
    'снятие назначения намерению конфликтует с его удалением в обоих порядках',
    () async {
      final repository = _ControlledRepository();
      final coordinator = _coordinator(repository);
      final command = RemoveTagAssignment(
        tagId: _tagId,
        intentionId: _intentionId,
      );
      final delete = DeleteIntention(_intentionId);
      final assignment =
          coordinator.acceptTagRemoveAssignment(command) as TagCommandAccepted;
      expect(coordinator.isTagRunning(_tagId), isTrue);
      expect(coordinator.isRunning(_intentionId), isTrue);
      expect(
        coordinator.acceptExisting(delete, presentationTitle: 'Намерение'),
        isA<IntentionCommandAlreadyRunning>(),
      );
      repository.complete(0, const TagCommandFailed(TagUnavailableFailure()));
      await assignment.future;

      final deletion = coordinator.acceptExisting(
        delete,
        presentationTitle: 'Намерение',
      ) as IntentionCommandAccepted;
      expect(
        coordinator.acceptTagRemoveAssignment(command),
        isA<TagCommandAlreadyRunning>(),
      );
      expect(coordinator.isTagRunning(_tagId), isFalse);
      expect(repository.commands, [same(command), same(delete)]);
      repository.complete(
        1,
        const ResultFailure<ConfirmedGraphResult<IntentionCommandSuccess>>(
          IntentionUnavailableFailure(),
        ),
      );
      await deletion.future;
      await coordinator.shutdown();
    },
  );

  for (final kind in TagCommandKind.values) {
    test('успех операции «${kind.name}» публикуется для согласования без права '
        'предъявления и не задерживает следующий отказ', () async {
      final repository = _ControlledRepository();
      final coordinator = _coordinator(repository);
      final completions = <GraphCommandCompletion>[];
      final subscription = coordinator.completions.listen(completions.add);
      final registration = coordinator.registerAppPresentation();
      final claims = <GraphAppPresentationClaim?>[];
      unawaited(registration.nextClaim().then(claims.add));

      final accepted = _startTag(coordinator, kind);
      repository.complete(0, _deletedSuccess);
      final completion = await accepted.future;
      await pumpEventQueue();

      expect(completion.isFailure, isFalse);
      expect(completion.confirmedChange?.revision, same(_revision));
      expect(completions, [same(completion)]);
      expect(claims, isEmpty);
      expect(coordinator.claimInitiatorFailure(accepted.token), isNull);

      final failed = coordinator.acceptTagDelete(
        DeleteTag(_otherTagId),
      ) as TagCommandAccepted;
      repository.complete(1, const TagCommandFailed(TagUnavailableFailure()));
      final failure = await failed.future;
      await pumpEventQueue();

      expect(claims.single?.completions, [same(failure)]);
      coordinator.confirmAppPresentation(claims.single!, [failure.token]);
      registration.release();
      await subscription.cancel();
      await coordinator.shutdown();
    });

    test(
      'отказ операции «${kind.name}» сразу принадлежит общей поверхности без '
      'права инициатора',
      () async {
        final repository = _ControlledRepository();
        final coordinator = _coordinator(repository);
        final registration = coordinator.registerAppPresentation();
        final claimFuture = registration.nextClaim();

        final accepted = _startTag(coordinator, kind);
        repository.complete(0, const TagCommandFailed(TagUnavailableFailure()));
        final completion = await accepted.future;

        expect(coordinator.claimInitiatorFailure(accepted.token), isNull);
        final claim = await claimFuture;
        expect(claim?.completions, [same(completion)]);
        coordinator.confirmAppPresentation(claim!, [completion.token]);
        registration.release();
        await coordinator.shutdown();
      },
    );
  }
}

TagCommandAccepted _startTag(
  GraphCommandCoordinator coordinator,
  TagCommandKind kind,
) => switch (kind) {
  TagCommandKind.create => coordinator.acceptTagCreation(
    TagCreationFormKey(),
    CreateTag(name: _name, color: null, placement: TagPlacement.first),
  ),
  TagCommandKind.update => coordinator.acceptTagUpdate(
    UpdateTag(tagId: _tagId, name: _name, color: null),
  ),
  TagCommandKind.delete => coordinator.acceptTagDelete(DeleteTag(_tagId)),
  TagCommandKind.move => coordinator.acceptTagMove(
    MoveTag(tagId: _tagId, placement: TagPlacement.first),
  ),
  TagCommandKind.assign => coordinator.acceptTagAssign(
    AssignTag(tagId: _tagId, intentionId: _intentionId),
  ),
  TagCommandKind.removeAssignment => coordinator.acceptTagRemoveAssignment(
    RemoveTagAssignment(tagId: _tagId, intentionId: _intentionId),
  ),
} as TagCommandAccepted;

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
const _revision = _Revision();
final _deletedSuccess = TagCommandSucceeded(
  ConfirmedGraphResult(
    revision: _revision,
    value: TagDeleted(TagDeletedChange(revision: _revision, tagId: _tagId)),
  ),
);

final class _ControlledRepository
    with TagReadContractTestFallback
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
