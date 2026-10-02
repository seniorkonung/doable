import 'package:doable/src/favorite/application/favorite_intentions.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/domain/intention_text.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/favorite_read_contract_test_fallback.dart';

void main() {
  test('строка хранит идентификатор, название, готовность и число связей', () {
    final row = FavoriteIntentionRow(
      id: _id(1),
      title: 'Гулять  по  утрам',
      readiness: IntentionReadiness.ready,
      activeRelationCount: 3,
    );

    expect(row.id, _id(1));
    expect(row.title, 'Гулять  по  утрам');
    expect(row.readiness, IntentionReadiness.ready);
    expect(row.activeRelationCount, 3);
  });

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

  test('полный снимок хранит все 150 строк в переданном порядке и защищён', () {
    // Порядок мест не совпадает с порядком идентификаторов и названий.
    final numbers = [for (var number = 150; number >= 1; number--) number];
    final rows = [
      for (final number in numbers) _row(number, 'Намерение $number'),
    ];
    const revision = _Revision();

    final snapshot = FavoriteIntentionsSnapshot(
      items: rows,
      archivedCount: 7,
      revision: revision,
    );
    rows.clear();

    expect(snapshot.items.map((row) => row.id), numbers.map(_id));
    expect(snapshot.archivedCount, 7);
    expect(snapshot.revision, same(revision));
    expect(() => snapshot.items.clear(), throwsUnsupportedError);
    expect(
      () => snapshot.items.add(_row(151, 'Лишнее')),
      throwsUnsupportedError,
    );
  });

  test('одноимённые намерения остаются отдельными строками снимка', () {
    final snapshot = FavoriteIntentionsSnapshot(
      items: [_row(1, 'Гулять'), _row(2, 'Гулять')],
      archivedCount: 0,
      revision: const _Revision(),
    );

    expect(snapshot.items.map((row) => row.id), [_id(1), _id(2)]);
    expect(snapshot.items.map((row) => row.title), ['Гулять', 'Гулять']);
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

  test(
    'пустой снимок с нулём архивированных является успехом, а не отказом',
    () async {
      final FavoriteReadContract source = _FavoriteSource(
        FavoriteIntentionsSuccess(
          FavoriteIntentionsSnapshot(
            items: const [],
            archivedCount: 0,
            revision: const _Revision(),
          ),
        ),
      );

      final result = await source.getFavoriteIntentions();

      expect(result, isA<FavoriteIntentionsSuccess>());
      final snapshot = (result as FavoriteIntentionsSuccess).value;
      expect(snapshot.items, isEmpty);
      expect(snapshot.archivedCount, 0);
    },
  );

  test(
    'пустой список со всеми архивированными отличается числом архивированных',
    () {
      final snapshot = FavoriteIntentionsSnapshot(
        items: const [],
        archivedCount: 2,
        revision: const _Revision(),
      );

      expect(snapshot.items, isEmpty);
      expect(snapshot.archivedCount, 2);
    },
  );

  test('отказы различают недоступность, повреждение и неизвестный отказ', () {
    const failures = <FavoriteIntentionsReadFailure>[
      FavoriteIntentionsUnavailableFailure(),
      FavoriteIntentionsCorruptionFailure(),
      FavoriteIntentionsUnexpectedFailure(),
    ];

    expect(failures.map((failure) => failure.category), [
      GraphFailureCategory.unavailable,
      GraphFailureCategory.corruption,
      GraphFailureCategory.unexpected,
    ]);
    for (final failure in failures) {
      final FavoriteIntentionsResult outcome = FavoriteIntentionsError(failure);
      expect(switch (outcome) {
        FavoriteIntentionsSuccess() => null,
        FavoriteIntentionsError(:final failure) => failure,
      }, same(failure));
    }
  });

  test('граница личного графа включает контракт чтения избранного', () {
    expect(_isFavoriteReadContract<PersonalGraphRepository>(), isTrue);
  });

  test('запасной вариант тестовых реализаций возвращает типизированный отказ, '
      'а не пустой снимок', () async {
    final FavoriteReadContract source = _FallbackFavoriteSource();

    final result = await source.getFavoriteIntentions();

    expect(
      result,
      isA<FavoriteIntentionsError>().having(
        (error) => error.failure,
        'причина',
        isA<FavoriteIntentionsUnexpectedFailure>(),
      ),
    );
  });
}

bool _isFavoriteReadContract<T>() => <T>[] is List<FavoriteReadContract>;

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

final class _FavoriteSource implements FavoriteReadContract {
  const _FavoriteSource(this._result);

  final FavoriteIntentionsResult _result;

  @override
  Future<FavoriteIntentionsResult> getFavoriteIntentions() async => _result;
}

final class _FallbackFavoriteSource with FavoriteReadContractTestFallback {}
