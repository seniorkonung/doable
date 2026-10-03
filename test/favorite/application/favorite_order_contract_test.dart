import 'package:doable/src/favorite/application/favorite_order_command.dart';
import 'package:doable/src/favorite/domain/favorite_order.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('команда адресует перемещаемое намерение и опору идентификаторами', () {
    // Оба намерения называются «Гулять»: команда различает их только по id.
    final firstWalk = _id(1);
    final secondWalk = _id(2);

    const first = FirstFavoritePlacement();
    final afterFirstWalk = AfterFavoritePlacement(firstWalk);
    final moveFirst = MoveFavoriteIntention(
      intentionId: secondWalk,
      placement: first,
    );
    final moveAfter = MoveFavoriteIntention(
      intentionId: secondWalk,
      placement: afterFirstWalk,
    );

    expect(moveFirst.intentionId, secondWalk);
    expect(moveFirst.placement, same(first));
    expect(moveAfter.intentionId, secondWalk);
    expect(moveAfter.intentionId, isNot(firstWalk));
    expect(switch (moveAfter.placement) {
      FirstFavoritePlacement() => null,
      AfterFavoritePlacement(:final anchorId) => anchorId,
    }, firstWalk);
  });

  test('исполнение возвращает типизированный результат перестановки', () async {
    const revision = _Revision(3);
    final change = FavoriteOrderChangedChange(revision: revision);
    final GraphCommandRepository repository = _Repository(
      GraphCommandSucceeded<
        FavoriteOrderCommandSuccess,
        FavoriteOrderCommandFailure
      >(
        ConfirmedGraphResult(
          revision: revision,
          value: FavoriteOrderMoved(change),
        ),
      ),
    );

    final FavoriteOrderCommandResult result = await repository.execute(
      MoveFavoriteIntention(
        intentionId: _id(1),
        placement: const FirstFavoritePlacement(),
      ),
    );

    expect(
      result,
      isA<FavoriteOrderCommandSucceeded>().having(
        (success) => success.value.value,
        'исход',
        isA<FavoriteOrderMoved>(),
      ),
    );
  });

  test('изменение порядка — отдельный факт графа новой ревизии без '
      'мутаций намерений', () {
    const revision = _Revision(8);
    final change = FavoriteOrderChangedChange(revision: revision);
    final outcome = FavoriteOrderMoved(change);

    final confirmed = ConfirmedGraphResult<FavoriteOrderCommandSuccess>(
      revision: revision,
      value: outcome,
    );

    expect(outcome.change, same(change));
    expect(confirmed.revision, same(revision));
    expect(confirmed.changes, [same(change)]);
    expect(confirmed.changes.whereType<IntentionCatalogMutation>(), isEmpty);
    expect(() => confirmed.changes.clear(), throwsUnsupportedError);
  });

  test('успех без изменения подтверждается на текущей ревизии без '
      'фиктивной мутации намерения', () {
    const current = _Revision(5);
    final change = FavoriteOrderUnchangedChange(revision: current);
    final outcome = FavoriteOrderUnchanged(change);

    final confirmed = ConfirmedGraphResult<FavoriteOrderCommandSuccess>(
      revision: current,
      value: outcome,
    );

    expect(outcome.change, same(change));
    expect(confirmed.revision, same(current));
    expect(confirmed.changes, [same(change)]);
    expect(confirmed.changes.whereType<IntentionCatalogMutation>(), isEmpty);
  });

  test('подтверждённый результат требует ревизии изменения порядка', () {
    expect(
      () => ConfirmedGraphResult<FavoriteOrderCommandSuccess>(
        revision: const _Revision(9),
        value: FavoriteOrderMoved(
          FavoriteOrderChangedChange(revision: const _Revision(8)),
        ),
      ),
      throwsA(
        isA<ConfirmedGraphResultValidationException>().having(
          (error) => error.failure,
          'причина',
          ConfirmedGraphResultValidationFailure.revisionMismatch,
        ),
      ),
    );
  });

  test('исходы различают изменение и успех без изменения', () {
    const revision = _Revision(1);
    final outcomes = <FavoriteOrderCommandSuccess>[
      FavoriteOrderMoved(FavoriteOrderChangedChange(revision: revision)),
      FavoriteOrderUnchanged(FavoriteOrderUnchangedChange(revision: revision)),
    ];

    expect(
      outcomes.map(
        (outcome) => switch (outcome) {
          FavoriteOrderMoved() => 'изменение',
          FavoriteOrderUnchanged() => 'без изменения',
        },
      ),
      ['изменение', 'без изменения'],
    );
    expect(
      outcomes.map(
        (outcome) => switch (outcome.change) {
          FavoriteOrderChangedChange() => 'изменение',
          FavoriteOrderUnchangedChange() => 'без изменения',
        },
      ),
      ['изменение', 'без изменения'],
    );
  });

  test('отказы различают ошибку ввода, конфликт, недоступность, повреждение '
      'и неизвестный отказ', () {
    const failures = <FavoriteOrderCommandFailure>[
      FavoriteOrderInputFailure(),
      FavoriteOrderConflictFailure(),
      FavoriteOrderUnavailableFailure(),
      FavoriteOrderCorruptionFailure(),
      FavoriteOrderUnexpectedFailure(),
    ];

    expect(failures.map((failure) => failure.category), [
      GraphFailureCategory.validation,
      GraphFailureCategory.conflict,
      GraphFailureCategory.unavailable,
      GraphFailureCategory.corruption,
      GraphFailureCategory.unexpected,
    ]);
    expect(
      failures.map(
        (failure) => switch (failure) {
          FavoriteOrderInputFailure() => 'ввод',
          FavoriteOrderConflictFailure() => 'конфликт',
          FavoriteOrderUnavailableFailure() => 'недоступность',
          FavoriteOrderCorruptionFailure() => 'повреждение',
          FavoriteOrderUnexpectedFailure() => 'неизвестный отказ',
        },
      ),
      ['ввод', 'конфликт', 'недоступность', 'повреждение', 'неизвестный отказ'],
    );
    for (final failure in failures) {
      final FavoriteOrderCommandResult result = FavoriteOrderCommandFailed(
        failure,
      );
      expect(switch (result) {
        FavoriteOrderCommandSucceeded() => null,
        FavoriteOrderCommandFailed(:final failure) => failure,
      }, same(failure));
    }
  });

  test('опора, совпадающая с перемещаемым намерением, — ошибка ввода, '
      'а утраченный участник — конфликт', () {
    final order = FavoriteOrder([
      FavoriteOrderEntry(
        intentionId: _id(1),
        archiveState: IntentionArchiveState.active,
      ),
      FavoriteOrderEntry(
        intentionId: _id(2),
        archiveState: IntentionArchiveState.archived,
      ),
    ]);

    final selfAnchored = moveInFavoriteOrder(
      order,
      intentionId: _id(2),
      placement: AfterFavoritePlacement(_id(2)),
    );
    final missingAnchor = moveInFavoriteOrder(
      order,
      intentionId: _id(2),
      placement: AfterFavoritePlacement(_id(3)),
    );

    expect(_failureOf(selfAnchored), isA<FavoriteOrderInputFailure>());
    expect(_failureOf(missingAnchor), isA<FavoriteOrderConflictFailure>());
  });
}

FavoriteOrderCommandFailure _failureOf(FavoriteOrderMoveResult result) =>
    switch (result) {
      final FavoriteOrderMoveRejected rejection =>
        FavoriteOrderCommandFailure.rejected(rejection),
      _ => fail('Ожидалось отклонение, получено ${result.runtimeType}.'),
    };

IntentionId _id(int number) => (IntentionId.decode(
  '018f0000-0000-7000-8000-${number.toRadixString(16).padLeft(12, '0')}',
) as IntentionIdDecodingSuccess).id;

final class _Revision implements GraphRevision {
  const _Revision(this.value);

  final int value;

  @override
  GraphRevisionOrder compareTo(GraphRevision other) {
    if (other is! _Revision) {
      return GraphRevisionOrder.differentEpoch;
    }
    if (value == other.value) {
      return GraphRevisionOrder.same;
    }
    return value < other.value
        ? GraphRevisionOrder.older
        : GraphRevisionOrder.newer;
  }
}

final class _Repository implements GraphCommandRepository {
  const _Repository(this._result);

  final FavoriteOrderCommandResult _result;

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async =>
      _result as GraphCommandResult<TSuccess, TFailure>;
}
