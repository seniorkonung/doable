import 'package:doable/src/favorite/application/favorite_order_command.dart';
import 'package:doable/src/favorite/domain/favorite_order.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
