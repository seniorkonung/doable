import 'package:doable/src/favorite/domain/favorite_order.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('изменение порядка', () {
    test('перемещение Д после А при скрытых архивированных Б и Г даёт '
        'А, Д, Б, В, Г', () {
      final order = _order(['А', 'Б*', 'В', 'Г*', 'Д']);

      final result = moveInFavoriteOrder(
        order,
        intentionId: _id('Д'),
        placement: AfterFavoritePlacement(_id('А')),
      );

      expect(_namesOf(result), ['А', 'Д', 'Б', 'В', 'Г']);
    });

    test('перемещение на первое место ставит намерение перед скрытыми '
        'архивированными', () {
      final order = _order(['Б*', 'А', 'В']);

      final result = moveInFavoriteOrder(
        order,
        intentionId: _id('В'),
        placement: const FirstFavoritePlacement(),
      );

      expect(_namesOf(result), ['В', 'Б', 'А']);
    });

    test('перемещение к началу ставит намерение сразу после опоры', () {
      final order = _order(['А', 'Б', 'В', 'Г']);

      final result = moveInFavoriteOrder(
        order,
        intentionId: _id('Г'),
        placement: AfterFavoritePlacement(_id('А')),
      );

      expect(_namesOf(result), ['А', 'Г', 'Б', 'В']);
    });

    test('перемещение к концу ставит намерение сразу после опоры', () {
      final order = _order(['А', 'Б', 'В', 'Г']);

      final result = moveInFavoriteOrder(
        order,
        intentionId: _id('А'),
        placement: AfterFavoritePlacement(_id('В')),
      );

      expect(_namesOf(result), ['Б', 'В', 'А', 'Г']);
    });

    test('перемещение в конец списка оставляет скрытые архивированные '
        'после последнего активного на прежних местах', () {
      final order = _order(['А', 'Б', 'В*']);

      final result = moveInFavoriteOrder(
        order,
        intentionId: _id('А'),
        placement: AfterFavoritePlacement(_id('Б')),
      );

      expect(_namesOf(result), ['Б', 'А', 'В']);
    });

    test('перемещение первого активного за последним сохраняет скрытые '
        'архивированные до и между активными', () {
      final order = _order(['Б*', 'А', 'Г*', 'В', 'Д*']);

      final result = moveInFavoriteOrder(
        order,
        intentionId: _id('А'),
        placement: AfterFavoritePlacement(_id('В')),
      );

      expect(_namesOf(result), ['Б', 'Г', 'В', 'А', 'Д']);
    });

    test('новый порядок сохраняет архивное состояние каждого намерения', () {
      final order = _order(['А', 'Б*', 'В', 'Г*', 'Д']);

      final result = moveInFavoriteOrder(
        order,
        intentionId: _id('Д'),
        placement: AfterFavoritePlacement(_id('А')),
      );

      expect(_reordered(result).entries, [
        _entry('А'),
        _entry('Д'),
        _entry('Б*'),
        _entry('В'),
        _entry('Г*'),
      ]);
    });

    test('архивирование перемещаемого намерения не отклоняет перемещение', () {
      final order = _order(['А', 'Б', 'В*']);

      final result = moveInFavoriteOrder(
        order,
        intentionId: _id('В'),
        placement: const FirstFavoritePlacement(),
      );

      expect(_namesOf(result), ['В', 'А', 'Б']);
    });

    test('архивирование опорного намерения не отклоняет перемещение', () {
      final order = _order(['А', 'Б*', 'В', 'Г']);

      final result = moveInFavoriteOrder(
        order,
        intentionId: _id('Г'),
        placement: AfterFavoritePlacement(_id('Б')),
      );

      expect(_namesOf(result), ['А', 'Б', 'Г', 'В']);
    });

    test('одноимённые намерения различаются только идентификатором', () {
      final first = _intentionId(1);
      final second = _intentionId(2);
      final reading = _intentionId(3);
      final order = FavoriteOrder([
        _activeEntry(first),
        _activeEntry(second),
        _activeEntry(reading),
      ]);

      final result = moveInFavoriteOrder(
        order,
        intentionId: second,
        placement: AfterFavoritePlacement(reading),
      );

      expect(_reordered(result).intentionIds, [first, reading, second]);
    });

    test('каждое перемещение меняет место только перемещаемого намерения', () {
      const names = ['А', 'Б*', 'В', 'Г*', 'Д', 'Е'];
      final order = _order(names);
      final placements = <FavoritePlacement>[
        const FirstFavoritePlacement(),
        for (final name in names) AfterFavoritePlacement(_id(name)),
      ];

      for (final moved in names) {
        final movedId = _id(moved);
        for (final placement in placements) {
          if (placement case AfterFavoritePlacement(:final anchorId)
              when anchorId == movedId) {
            continue;
          }

          final result = moveInFavoriteOrder(
            order,
            intentionId: movedId,
            placement: placement,
          );

          final resulting = switch (result) {
            FavoriteOrderMoveApplied(order: final reordered) =>
              reordered.intentionIds,
            FavoriteOrderMoveWithoutChange() => order.intentionIds,
            FavoriteOrderMoveSelfAnchored() ||
            FavoriteOrderMoveMissingParticipant() => fail(
              'Допустимое перемещение отклонено.',
            ),
          };
          final others = order.intentionIds.where((id) => id != movedId);
          expect(
            resulting.where((id) => id != movedId),
            orderedEquals(others),
            reason: 'Взаимный порядок остальных сохраняется.',
          );
          expect(resulting, unorderedEquals(order.intentionIds));
          if (result is FavoriteOrderMoveApplied) {
            final movedIndex = resulting.indexOf(movedId);
            switch (placement) {
              case FirstFavoritePlacement():
                expect(movedIndex, 0);
              case AfterFavoritePlacement(:final anchorId):
                expect(resulting[movedIndex - 1], anchorId);
            }
          }
        }
      }
    });
  });

  group('отсутствие видимого изменения', () {
    test('опора, совпадающая с ближайшим предшествующим активным, '
        'не переставляет скрытые архивированные', () {
      final order = _order(['А', 'Б*', 'В']);

      final result = moveInFavoriteOrder(
        order,
        intentionId: _id('В'),
        placement: AfterFavoritePlacement(_id('А')),
      );

      expect(result, isA<FavoriteOrderMoveWithoutChange>());
    });

    test('опора, непосредственно предшествующая перемещаемому, не меняет '
        'порядок', () {
      final order = _order(['А', 'Б', 'В']);

      final result = moveInFavoriteOrder(
        order,
        intentionId: _id('В'),
        placement: AfterFavoritePlacement(_id('Б')),
      );

      expect(result, isA<FavoriteOrderMoveWithoutChange>());
    });

    test('размещение первым без активного предшественника не ставит '
        'намерение перед скрытыми архивированными', () {
      final order = _order(['Б*', 'Г*', 'А', 'В']);

      final result = moveInFavoriteOrder(
        order,
        intentionId: _id('А'),
        placement: const FirstFavoritePlacement(),
      );

      expect(result, isA<FavoriteOrderMoveWithoutChange>());
    });

    test('размещение первым уже первого намерения не меняет порядок', () {
      final order = _order(['А', 'Б']);

      final result = moveInFavoriteOrder(
        order,
        intentionId: _id('А'),
        placement: const FirstFavoritePlacement(),
      );

      expect(result, isA<FavoriteOrderMoveWithoutChange>());
    });

    test('архивированная опора непосредственно перед перемещаемым не '
        'меняет полный порядок', () {
      final order = _order(['А', 'Б*', 'В']);

      final result = moveInFavoriteOrder(
        order,
        intentionId: _id('В'),
        placement: AfterFavoritePlacement(_id('Б')),
      );

      expect(result, isA<FavoriteOrderMoveWithoutChange>());
    });

    test('единственное избранное намерение остаётся на месте', () {
      final order = _order(['А']);

      final result = moveInFavoriteOrder(
        order,
        intentionId: _id('А'),
        placement: const FirstFavoritePlacement(),
      );

      expect(result, isA<FavoriteOrderMoveWithoutChange>());
    });
  });

  group('недопустимые участники', () {
    test('перемещаемое намерение, совпадающее с опорой, — ошибка ввода', () {
      final order = _order(['А', 'Б']);

      final result = moveInFavoriteOrder(
        order,
        intentionId: _id('Б'),
        placement: AfterFavoritePlacement(_id('Б')),
      );

      expect(result, isA<FavoriteOrderMoveSelfAnchored>());
    });

    test('совпадение с опорой остаётся ошибкой ввода и для намерения '
        'вне избранного', () {
      final order = _order(['А']);

      final result = moveInFavoriteOrder(
        order,
        intentionId: _id('Б'),
        placement: AfterFavoritePlacement(_id('Б')),
      );

      expect(result, isA<FavoriteOrderMoveSelfAnchored>());
    });

    test('перемещаемое намерение вне избранного — конфликт', () {
      final order = _order(['А', 'Б']);

      final result = moveInFavoriteOrder(
        order,
        intentionId: _id('В'),
        placement: AfterFavoritePlacement(_id('А')),
      );

      expect(result, isA<FavoriteOrderMoveMissingParticipant>());
    });

    test('перемещаемое намерение вне избранного при размещении первым — '
        'конфликт', () {
      final order = _order(['А', 'Б']);

      final result = moveInFavoriteOrder(
        order,
        intentionId: _id('В'),
        placement: const FirstFavoritePlacement(),
      );

      expect(result, isA<FavoriteOrderMoveMissingParticipant>());
    });

    test('опорное намерение вне избранного — конфликт', () {
      final order = _order(['А', 'В']);

      final result = moveInFavoriteOrder(
        order,
        intentionId: _id('В'),
        placement: AfterFavoritePlacement(_id('Б')),
      );

      expect(result, isA<FavoriteOrderMoveMissingParticipant>());
    });

    test('в пустом порядке любое перемещение — конфликт', () {
      final order = FavoriteOrder(const []);

      final result = moveInFavoriteOrder(
        order,
        intentionId: _id('А'),
        placement: const FirstFavoritePlacement(),
      );

      expect(result, isA<FavoriteOrderMoveMissingParticipant>());
    });
  });

  group('полный порядок', () {
    test('хранит переданные места и защищён от изменения', () {
      final entries = [_entry('А'), _entry('Б*')];

      final order = FavoriteOrder(entries);
      entries.clear();

      expect(order.entries, [_entry('А'), _entry('Б*')]);
      expect(order.intentionIds, [_id('А'), _id('Б')]);
      expect(() => order.entries.clear(), throwsUnsupportedError);
      expect(() => order.intentionIds.clear(), throwsUnsupportedError);
    });

    test('не допускает повтора намерения', () {
      expect(
        () => FavoriteOrder([_entry('А'), _entry('Б'), _entry('А*')]),
        throwsA(
          isA<FavoriteOrderValidationException>().having(
            (error) => error.failure,
            'причина',
            FavoriteOrderValidationFailure.duplicateIntention,
          ),
        ),
      );
    });

    test('места равны при совпадении намерения и архивного состояния', () {
      expect(_entry('А'), _entry('А'));
      expect(_entry('А').hashCode, _entry('А').hashCode);
      expect(_entry('А'), isNot(_entry('А*')));
      expect(_entry('А'), isNot(_entry('Б')));
    });
  });
}

const _letters = ['А', 'Б', 'В', 'Г', 'Д', 'Е'];

/// Имя со звёздочкой обозначает архивированное избранное намерение.
FavoriteOrder _order(List<String> names) =>
    FavoriteOrder([for (final name in names) _entry(name)]);

FavoriteOrderEntry _entry(String name) => FavoriteOrderEntry(
  intentionId: _id(name),
  archiveState: name.endsWith('*')
      ? IntentionArchiveState.archived
      : IntentionArchiveState.active,
);

FavoriteOrderEntry _activeEntry(IntentionId id) => FavoriteOrderEntry(
  intentionId: id,
  archiveState: IntentionArchiveState.active,
);

IntentionId _id(String name) {
  final index = _letters.indexOf(name.replaceAll('*', ''));
  if (index < 0) {
    throw ArgumentError.value(name, 'name');
  }
  return _intentionId(index + 10);
}

IntentionId _intentionId(int number) => (IntentionId.decode(
  '018f0000-0000-7000-8000-${number.toRadixString(16).padLeft(12, '0')}',
) as IntentionIdDecodingSuccess).id;

FavoriteOrder _reordered(FavoriteOrderMoveResult result) => switch (result) {
  FavoriteOrderMoveApplied(:final order) => order,
  _ => fail('Ожидался новый порядок, получено ${result.runtimeType}.'),
};

List<String> _namesOf(FavoriteOrderMoveResult result) => [
  for (final id in _reordered(result).intentionIds)
    _letters[_letters.indexWhere((name) => _id(name) == id)],
];
