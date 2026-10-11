import 'package:doable/src/favorite/application/favorite_intentions.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/domain/intention_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('строка отклоняет недопустимое название и отрицательное число', () {
    expect(
      () => FavoriteIntentionRow(
        id: _id(1),
        title: '',
        readiness: IntentionReadiness.notReady,
        activeRelationCount: 0,
      ),
      throwsA(isA<IntentionTextValidationException>()),
    );
    expect(
      () => FavoriteIntentionRow(
        id: _id(1),
        title: 'Гулять',
        readiness: IntentionReadiness.notReady,
        activeRelationCount: -1,
      ),
      throwsArgumentError,
    );
  });

  test('снимок не допускает повтора намерения', () {
    expect(
      () => FavoriteIntentionsSnapshot(
        items: [_row(1, 'Гулять'), _row(2, 'Читать'), _row(1, 'Гулять')],
        archivedCount: 0,
        revision: const _Revision(),
      ),
      throwsA(
        isA<FavoriteIntentionsSnapshotValidationException>().having(
          (error) => error.failure,
          'причина',
          FavoriteIntentionsSnapshotValidationFailure.duplicateIntention,
        ),
      ),
    );
  });

  test('снимок не допускает отрицательного числа архивированных', () {
    expect(
      () => FavoriteIntentionsSnapshot(
        items: const [],
        archivedCount: -1,
        revision: const _Revision(),
      ),
      throwsA(
        isA<FavoriteIntentionsSnapshotValidationException>().having(
          (error) => error.failure,
          'причина',
          FavoriteIntentionsSnapshotValidationFailure.negativeArchivedCount,
        ),
      ),
    );
  });
}

IntentionId _id(int number) => (IntentionId.decode(
  '018f0000-0000-7000-8000-${number.toRadixString(16).padLeft(12, '0')}',
) as IntentionIdDecodingSuccess).id;

FavoriteIntentionRow _row(int number, String title) => FavoriteIntentionRow(
  id: _id(number),
  title: title,
  readiness: number.isEven
      ? IntentionReadiness.ready
      : IntentionReadiness.notReady,
  activeRelationCount: number % 4,
);

final class _Revision implements GraphRevision {
  const _Revision();

  @override
  GraphRevisionOrder compareTo(GraphRevision other) => GraphRevisionOrder.same;
}
