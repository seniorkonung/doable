import 'dart:async';

import 'package:doable/src/daily_choice/application/choice_path_continuations.dart';
import 'package:doable/src/favorite/application/favorite_order_command.dart';
import 'package:doable/src/favorite/domain/favorite_order.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/catalog_reconciliation_test_fallback.dart';
import '../../support/favorite_read_contract_test_fallback.dart';
import '../../support/tag_read_contract_test_fallback.dart';

void main() {
  test('перестановка занимает единственный ключ порядка и не ставит повтор в очередь', () async {
    final repository = _ControlledRepository();
    final coordinator = _coordinator(repository);

    final first = coordinator.acceptFavoriteOrderMove(
      _moveAfter(_c, _a),
    ) as FavoriteOrderCommandAccepted;
    final repeated = coordinator.acceptFavoriteOrderMove(_moveAfter(_c, _a));
    final other = coordinator.acceptFavoriteOrderMove(_moveFirst(_b));

    expect(repeated, isA<FavoriteOrderCommandAlreadyRunning>());
    expect(other, isA<FavoriteOrderCommandAlreadyRunning>());
    expect(repository.commands, hasLength(1));
    expect(coordinator.isFavoriteOrderRunning, isTrue);
    expect(coordinator.isKeyRunning(FavoriteOrderKey.instance), isTrue);

    repository.complete(0, _moved(const _Revision(2)));
    await first.future;

    expect(coordinator.isFavoriteOrderRunning, isFalse);
    // Отклонённые перестановки не запускаются после освобождения ключа.
    await Future<void>.delayed(Duration.zero);
    expect(repository.commands, hasLength(1));

    final next = coordinator.acceptFavoriteOrderMove(_moveFirst(_b));
    expect(next, isA<FavoriteOrderCommandAccepted>());
    expect(repository.commands, hasLength(2));
    repository.complete(1, _unchanged(const _Revision(2)));
    await (next as FavoriteOrderCommandAccepted).future;
    await coordinator.shutdown();
  });

  test(
    'перестановка и операции её участников не блокируют приём друг друга',
    () async {
      final repository = _ControlledRepository();
      final coordinator = _coordinator(repository);

      final archive = coordinator.acceptExisting(
        ArchiveIntention(_a),
        presentationTitle: 'А',
      ) as IntentionCommandAccepted;
      final move = coordinator.acceptFavoriteOrderMove(
        _moveAfter(_c, _a),
      ) as FavoriteOrderCommandAccepted;
      final mark = coordinator.acceptExisting(
        MarkIntentionFavorite(_c),
        presentationTitle: 'В',
      ) as IntentionCommandAccepted;
      final assign = coordinator.acceptTagAssign(
        AssignTag(tagId: _tag, intentionId: _b),
      ) as TagCommandAccepted;

      expect(repository.commands, hasLength(4));
      expect(coordinator.isRunning(_a), isTrue);
      expect(coordinator.isRunning(_c), isTrue);
      expect(coordinator.isRunning(_b), isTrue);
      expect(coordinator.isFavoriteOrderRunning, isTrue);
      expect(
        coordinator.acceptExisting(
          ArchiveIntention(_a),
          presentationTitle: 'А',
        ),
        isA<IntentionCommandAlreadyRunning>(),
      );
      expect(
        coordinator.acceptFavoriteOrderMove(_moveFirst(_a)),
        isA<FavoriteOrderCommandAlreadyRunning>(),
      );

      repository
        ..complete(0, _intentionFailure)
        ..complete(1, _moved(const _Revision(2)))
        ..complete(2, _intentionFailure)
        ..complete(3, const TagCommandFailed(TagUnavailableFailure()));
      await Future.wait([
        archive.future,
        move.future,
        mark.future,
        assign.future,
      ]);

      expect(coordinator.isRunning(_a), isFalse);
      expect(coordinator.isRunning(_b), isFalse);
      expect(coordinator.isRunning(_c), isFalse);
      expect(coordinator.isFavoriteOrderRunning, isFalse);
      await coordinator.shutdown();
    },
  );

  for (final scenario in [
    (name: 'изменение порядка', result: _moved(const _Revision(5))),
    (name: 'отсутствие изменения', result: _unchanged(const _Revision(4))),
  ]) {
    test(
      'успех (${scenario.name}) публикуется для согласования без права предъявления',
      () async {
        final repository = _ControlledRepository();
        final coordinator = _coordinator(repository);
        final completions = <GraphCommandCompletion>[];
        final subscription = coordinator.completions.listen(completions.add);
        final registration = coordinator.registerAppPresentation();
        GraphAppPresentationClaim? issued;
        unawaited(registration.nextClaim().then((claim) => issued = claim));

        final move = coordinator.acceptFavoriteOrderMove(
          _moveAfter(_c, _a),
        ) as FavoriteOrderCommandAccepted;
        repository.complete(0, scenario.result);
        final completion = await move.future;
        await Future<void>.delayed(Duration.zero);

        expect(completion, isA<FavoriteOrderConfirmedCompletion>());
        expect(completion.token, same(move.token));
        expect(completion.isFailure, isFalse);
        final confirmed = completion as FavoriteOrderConfirmedCompletion;
        expect(
          completion.confirmedChange,
          same((scenario.result as FavoriteOrderCommandSucceeded).value),
        );
        expect(confirmed.success.change.revision, same(completion.revision));
        expect(completions, [same(completion)]);
        expect(issued, isNull);

        // Следующая операция с правом оболочки не ждёт успеха перестановки.
        final archive = coordinator.acceptExisting(
          ArchiveIntention(_a),
          presentationTitle: 'А',
        ) as IntentionCommandAccepted;
        coordinator.releaseInitiatorPresentation(archive.token);
        repository.complete(1, _intentionFailure);
        final archiveCompletion = await archive.future;
        await Future<void>.delayed(Duration.zero);

        expect(issued?.completion, same(archiveCompletion));
        coordinator.confirmPresentation(issued!);
        GraphAppPresentationClaim? afterArchive;
        unawaited(
          registration.nextClaim().then((claim) => afterArchive = claim),
        );
        await Future<void>.delayed(Duration.zero);
        expect(afterArchive, isNull);

        registration.release();
        await subscription.cancel();
        await coordinator.shutdown();
      },
    );
  }

  test(
    'отказ сразу принадлежит общей поверхности, а не странице инициатора',
    () async {
      final repository = _ControlledRepository();
      final coordinator = _coordinator(repository);
      final completions = <GraphCommandCompletion>[];
      final subscription = coordinator.completions.listen(completions.add);

      final move = coordinator.acceptFavoriteOrderMove(
        _moveAfter(_c, _b),
      ) as FavoriteOrderCommandAccepted;
      // Токен перестановки не адресует право инициатора.
      expect(move.token, isNot(isA<GraphInitiatorOperationToken>()));
      repository.complete(
        0,
        const FavoriteOrderCommandFailed(FavoriteOrderConflictFailure()),
      );
      final completion = await move.future;

      expect(completion, isA<FavoriteOrderFailedCompletion>());
      expect(completion.isFailure, isTrue);
      expect(completion.confirmedChange, isNull);
      expect(
        (completion as FavoriteOrderFailedCompletion).failure,
        isA<FavoriteOrderConflictFailure>(),
      );
      expect(completions, [same(completion)]);
      expect(coordinator.isFavoriteOrderRunning, isFalse);

      // Поверхность регистрируется после завершения: отказ её дожидается.
      final registration = coordinator.registerAppPresentation();
      final claim = await registration.nextClaim();
      expect(claim?.token, same(move.token));
      expect(claim?.completion, same(completion));

      coordinator.confirmPresentation(claim!);
      GraphAppPresentationClaim? repeated;
      unawaited(registration.nextClaim().then((next) => repeated = next));
      await Future<void>.delayed(Duration.zero);
      expect(repeated, isNull);

      registration.release();
      await subscription.cancel();
      await coordinator.shutdown();
    },
  );

  test(
    'отказ намерения при открытой странице остаётся у инициатора по ADR-0012',
    () async {
      final repository = _ControlledRepository();
      final coordinator = _coordinator(repository);
      final registration = coordinator.registerAppPresentation();
      final claims = <GraphAppPresentationClaim?>[];
      unawaited(registration.nextClaim().then(claims.add));

      final archive = coordinator.acceptExisting(
        ArchiveIntention(_a),
        presentationTitle: 'А',
      ) as IntentionCommandAccepted;
      final move = coordinator.acceptFavoriteOrderMove(
        _moveFirst(_c),
      ) as FavoriteOrderCommandAccepted;
      repository
        ..complete(0, _intentionFailure)
        ..complete(
          1,
          const FavoriteOrderCommandFailed(FavoriteOrderUnavailableFailure()),
        );
      final archiveCompletion = await archive.future;
      final moveCompletion = await move.future;
      await Future<void>.delayed(Duration.zero);

      expect(claims.single?.completion, same(moveCompletion));
      final initiatorClaim = coordinator.claimInitiatorFailure(archive.token);
      expect(initiatorClaim?.completion, same(archiveCompletion));

      coordinator.confirmPresentation(claims.single!);
      coordinator.confirmPresentation(initiatorClaim!);
      GraphAppPresentationClaim? next;
      unawaited(registration.nextClaim().then((claim) => next = claim));
      await Future<void>.delayed(Duration.zero);
      expect(next, isNull);

      registration.release();
      await coordinator.shutdown();
    },
  );

  test(
    'публикация перестановки сохраняет порядок принятия и держит ключ до неё',
    () async {
      final repository = _ControlledRepository();
      final coordinator = _coordinator(repository);
      final completions = <GraphCommandCompletion>[];
      final subscription = coordinator.completions.listen(completions.add);

      final archive = coordinator.acceptExisting(
        ArchiveIntention(_a),
        presentationTitle: 'А',
      ) as IntentionCommandAccepted;
      final move = coordinator.acceptFavoriteOrderMove(
        _moveAfter(_c, _a),
      ) as FavoriteOrderCommandAccepted;
      repository.complete(1, _moved(const _Revision(2)));
      await Future<void>.delayed(Duration.zero);

      expect(completions, isEmpty);
      expect(coordinator.isFavoriteOrderRunning, isTrue);
      expect(
        coordinator.acceptFavoriteOrderMove(_moveFirst(_b)),
        isA<FavoriteOrderCommandAlreadyRunning>(),
      );

      repository.complete(0, _intentionFailure);
      final archiveCompletion = await archive.future;
      final moveCompletion = await move.future;

      expect(completions, [same(archiveCompletion), same(moveCompletion)]);
      expect(coordinator.isFavoriteOrderRunning, isFalse);
      await subscription.cancel();
      await coordinator.shutdown();
    },
  );

  test(
    'исключение хранилища становится неизвестным отказом и освобождает ключ',
    () async {
      final repository = _ControlledRepository();
      final coordinator = _coordinator(repository);
      final registration = coordinator.registerAppPresentation();
      final claimFuture = registration.nextClaim();

      final move = coordinator.acceptFavoriteOrderMove(
        _moveAfter(_c, _a),
      ) as FavoriteOrderCommandAccepted;
      repository.fail(
        0,
        StateError('SELECT position FROM favorite_intentions'),
      );
      final completion = await move.future;
      final claim = await claimFuture;

      expect(
        completion,
        isA<FavoriteOrderFailedCompletion>().having(
          (failed) => failed.failure,
          'отказ',
          isA<FavoriteOrderUnexpectedFailure>(),
        ),
      );
      expect(claim?.completion, same(completion));
      expect(coordinator.isFavoriteOrderRunning, isFalse);
      expect(
        coordinator.acceptFavoriteOrderMove(_moveFirst(_c)),
        isA<FavoriteOrderCommandAccepted>(),
      );

      coordinator.confirmPresentation(claim!);
      repository.complete(1, _unchanged(const _Revision(1)));
      registration.release();
      await coordinator.shutdown();
    },
  );

  test('завершение работы ждёт перестановку и не принимает новую', () async {
    final repository = _ControlledRepository();
    final coordinator = _coordinator(repository);
    final move = coordinator.acceptFavoriteOrderMove(
      _moveAfter(_c, _a),
    ) as FavoriteOrderCommandAccepted;

    final shutdown = coordinator.shutdown();
    var finished = false;
    unawaited(shutdown.then((_) => finished = true));

    expect(
      coordinator.acceptFavoriteOrderMove(_moveFirst(_b)),
      isA<GraphCommandCoordinatorDraining>(),
    );
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    expect(coordinator.isFavoriteOrderRunning, isTrue);

    repository.complete(0, _moved(const _Revision(2)));
    await move.future;
    await shutdown;
    expect(finished, isTrue);
    expect(repository.commands, hasLength(1));
  });
}

GraphCommandCoordinator _coordinator(PersonalGraphRepository repository) {
  final container = ProviderContainer.test(
    overrides: [personalGraphRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);
  return container.read(graphCommandCoordinatorProvider.notifier);
}

MoveFavoriteIntention _moveAfter(IntentionId moved, IntentionId anchor) =>
    MoveFavoriteIntention(
      intentionId: moved,
      placement: AfterFavoritePlacement(anchor),
    );

MoveFavoriteIntention _moveFirst(IntentionId moved) => MoveFavoriteIntention(
  intentionId: moved,
  placement: const FirstFavoritePlacement(),
);

FavoriteOrderCommandResult _moved(GraphRevision revision) =>
    FavoriteOrderCommandSucceeded(
      ConfirmedGraphResult(
        revision: revision,
        value: FavoriteOrderMoved(
          FavoriteOrderChangedChange(revision: revision),
        ),
      ),
    );

FavoriteOrderCommandResult _unchanged(GraphRevision revision) =>
    FavoriteOrderCommandSucceeded(
      ConfirmedGraphResult(
        revision: revision,
        value: FavoriteOrderUnchanged(
          FavoriteOrderUnchangedChange(revision: revision),
        ),
      ),
    );

const _intentionFailure =
    ResultFailure<ConfirmedGraphResult<IntentionCommandSuccess>>(
      IntentionUnavailableFailure(),
    );

String _uuid(int number) =>
    '018f47c2-6b7d-7abc-8def-${number.toRadixString(16).padLeft(12, '0')}';
IntentionId _intention(int number) =>
    (IntentionId.decode(_uuid(number)) as IntentionIdDecodingSuccess).id;
final _a = _intention(1);
final _b = _intention(2);
final _c = _intention(3);
final _tag = (TagId.decode(_uuid(4)) as TagIdDecodingSuccess).id;

final class _ControlledRepository
    with
        TagReadContractTestFallback,
        FavoriteReadContractTestFallback,
        CatalogReconciliationTestFallback
    implements PersonalGraphRepository {
  @override
  Future<ChoicePathContinuationResult> getChoicePathContinuations(
    ChoicePathContinuationQuery query,
  ) => throw UnimplementedError();

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

  void fail(int index, Object error) => _results[index].completeError(error);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Revision implements GraphRevision {
  const _Revision(this.value);

  final int value;

  @override
  GraphRevisionOrder compareTo(GraphRevision other) => switch (other) {
    _Revision(:final value) when value < this.value => GraphRevisionOrder.newer,
    _Revision(:final value) when value == this.value => GraphRevisionOrder.same,
    _Revision() => GraphRevisionOrder.older,
    _ => GraphRevisionOrder.differentEpoch,
  };
}
