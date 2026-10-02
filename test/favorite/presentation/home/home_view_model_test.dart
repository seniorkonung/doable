import 'package:doable/src/favorite/application/favorite_intentions.dart';
import 'package:doable/src/favorite/presentation/home/home_state.dart';
import 'package:doable/src/favorite/presentation/home/home_view_model.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:flutter_test/flutter_test.dart';

import 'home_test_support.dart';

void main() {
  test('пока список получается, состояние — загрузка, а не пустая Главная', () {
    final h = HomeHarness();
    addTearDown(h.dispose);

    expect(h.state, isA<HomeLoading>());
    expect(h.repository.readCount, 1);
  });

  test('успешный снимок публикуется списком с данными каждой строки', () async {
    final h = HomeHarness();
    addTearDown(h.dispose);

    h.repository.completeRead(
      0,
      items: [
        homeTestRow(
          1,
          'Гулять',
          readiness: IntentionReadiness.ready,
          activeRelationCount: 3,
        ),
        homeTestRow(2, 'Гулять'),
      ],
      archivedCount: 4,
      revision: 7,
    );
    await pumpEventQueue();

    final list = h.state as HomeList;
    expect(list.items.map((row) => row.id), [
      homeTestIntentionId(1),
      homeTestIntentionId(2),
    ]);
    expect(list.items.map((row) => row.title), ['Гулять', 'Гулять']);
    expect(list.items.first.readiness, IntentionReadiness.ready);
    expect(list.items.first.activeRelationCount, 3);
    expect(list.items.last.readiness, IntentionReadiness.notReady);
    expect(list.items.last.activeRelationCount, 0);
    expect(list.revision, isA<HomeTestRevision>());
    expect((list.revision as HomeTestRevision).number, 7);
    expect(list.freshness, isA<HomeFreshnessCurrent>());
    expect(h.repository.readCount, 1);
  });

  test(
    'список из 150 намерений публикуется целиком в порядке снимка',
    () async {
      final h = HomeHarness();
      addTearDown(h.dispose);
      // Порядок мест не совпадает с порядком идентификаторов и названий.
      final numbers = [for (var number = 150; number >= 1; number--) number];

      h.repository.completeRead(
        0,
        items: [for (final number in numbers) homeTestRow(number, 'Н $number')],
      );
      await pumpEventQueue();

      final list = h.state as HomeList;
      expect(list.items, hasLength(150));
      expect(list.items.map((row) => row.id), numbers.map(homeTestIntentionId));
      expect(() => list.items.clear(), throwsUnsupportedError);
      expect(h.repository.readCount, 1);
    },
  );

  test(
    'пустой снимок без архивированных избранных — «избранных нет»',
    () async {
      final h = HomeHarness();
      addTearDown(h.dispose);

      h.repository.completeRead(0, revision: 2);
      await pumpEventQueue();

      final empty = h.state as HomeEmpty;
      expect(empty.reason, HomeEmptyReason.noFavorites);
      expect(empty.freshness, isA<HomeFreshnessCurrent>());
      expect((empty.revision as HomeTestRevision).number, 2);
    },
  );

  test(
    'пустой снимок с архивированными избранными — «все архивированы»',
    () async {
      final h = HomeHarness();
      addTearDown(h.dispose);

      h.repository.completeRead(0, archivedCount: 1);
      await pumpEventQueue();

      final empty = h.state as HomeEmpty;
      expect(empty.reason, HomeEmptyReason.allArchived);
      expect(empty.freshness, isA<HomeFreshnessCurrent>());
    },
  );

  test('архивированные избранные не делают непустой список пустым', () async {
    final h = HomeHarness();
    addTearDown(h.dispose);

    h.repository.completeRead(
      0,
      items: [homeTestRow(1, 'Гулять')],
      archivedCount: 5,
    );
    await pumpEventQueue();

    expect(h.state, isA<HomeList>());
  });

  group('отказ первоначального получения не становится пустым состоянием', () {
    test('недоступность', () async {
      final h = HomeHarness();
      addTearDown(h.dispose);

      h.repository.failRead(0, const FavoriteIntentionsUnavailableFailure());
      await pumpEventQueue();

      expect(h.state, isA<HomeUnavailable>());
    });

    test('повреждение', () async {
      final h = HomeHarness();
      addTearDown(h.dispose);

      h.repository.failRead(0, const FavoriteIntentionsCorruptionFailure());
      await pumpEventQueue();

      expect(h.state, isA<HomeCorruption>());
    });

    test('неизвестный отказ', () async {
      final h = HomeHarness();
      addTearDown(h.dispose);

      h.repository.failRead(0, const FavoriteIntentionsUnexpectedFailure());
      await pumpEventQueue();

      expect(h.state, isA<HomeUnexpected>());
    });
  });

  group('исключение границы становится неизвестным отказом', () {
    test('в ответе чтения', () async {
      final h = HomeHarness();
      addTearDown(h.dispose);

      h.repository.throwFromRead(0, StateError('SELECT * FROM favorite'));
      await pumpEventQueue();

      expect(h.state, isA<HomeUnexpected>());
    });

    test('при запуске чтения', () async {
      final h = HomeHarness(firstReadError: StateError('database is closed'));
      addTearDown(h.dispose);

      expect(h.state, isA<HomeLoading>());
      await pumpEventQueue();

      expect(h.state, isA<HomeUnexpected>());
      expect(h.repository.readCount, 1);
    });
  });

  group('повтор', () {
    test(
      'при недоступности возвращает загрузку и выполняет новое чтение',
      () async {
        final h = HomeHarness();
        addTearDown(h.dispose);
        h.repository.failRead(0, const FavoriteIntentionsUnavailableFailure());
        await pumpEventQueue();

        h.model.retry();

        expect(h.state, isA<HomeLoading>());
        expect(h.repository.readCount, 2);

        h.repository.completeRead(1, items: [homeTestRow(1, 'Гулять')]);
        await pumpEventQueue();

        final list = h.state as HomeList;
        expect(list.items.single.id, homeTestIntentionId(1));
        expect(list.freshness, isA<HomeFreshnessCurrent>());
      },
    );

    test('повторный отказ снова показывает недоступность', () async {
      final h = HomeHarness();
      addTearDown(h.dispose);
      h.repository.failRead(0, const FavoriteIntentionsUnavailableFailure());
      await pumpEventQueue();

      h.model.retry();
      h.repository.failRead(1, const FavoriteIntentionsUnavailableFailure());
      await pumpEventQueue();

      expect(h.state, isA<HomeUnavailable>());
      expect(h.repository.readCount, 2);
    });

    test('при повреждении недоступен и чтение не запускает', () async {
      final h = HomeHarness();
      addTearDown(h.dispose);
      h.repository.failRead(0, const FavoriteIntentionsCorruptionFailure());
      await pumpEventQueue();

      h.model.retry();
      await pumpEventQueue();

      expect(h.state, isA<HomeCorruption>());
      expect(h.repository.readCount, 1);
    });

    test('при неизвестном отказе недоступен и чтение не запускает', () async {
      final h = HomeHarness();
      addTearDown(h.dispose);
      h.repository.failRead(0, const FavoriteIntentionsUnexpectedFailure());
      await pumpEventQueue();

      h.model.retry();
      await pumpEventQueue();

      expect(h.state, isA<HomeUnexpected>());
      expect(h.repository.readCount, 1);
    });

    test('во время загрузки не запускает параллельное чтение', () async {
      final h = HomeHarness();
      addTearDown(h.dispose);

      h.model.retry();
      expect(h.repository.readCount, 1);

      h.repository.failRead(0, const FavoriteIntentionsUnavailableFailure());
      await pumpEventQueue();
      h.model.retry();
      h.model.retry();

      expect(h.state, isA<HomeLoading>());
      expect(h.repository.readCount, 2);
    });

    test(
      'при показанном списке и пустом состоянии чтение не запускает',
      () async {
        final h = HomeHarness();
        addTearDown(h.dispose);
        h.repository.completeRead(0, items: [homeTestRow(1, 'Гулять')]);
        await pumpEventQueue();

        h.model.retry();
        await pumpEventQueue();

        expect(h.state, isA<HomeList>());
        expect(h.repository.readCount, 1);
      },
    );
  });

  test(
    'ответ прежнего чтения, пришедший после нового, не публикуется',
    () async {
      final h = HomeHarness();
      addTearDown(h.dispose);
      expect(h.repository.readCount, 1);

      // Пересборка провайдера начинает новое чтение, пока прежнее не завершено.
      h.container.invalidate(homeViewModelProvider);
      expect(h.state, isA<HomeLoading>());
      expect(h.repository.readCount, 2);

      h.repository.completeRead(
        1,
        items: [homeTestRow(2, 'Новое')],
        revision: 2,
      );
      await pumpEventQueue();
      h.repository.completeRead(0, items: [homeTestRow(1, 'Прежнее')]);
      await pumpEventQueue();

      final list = h.state as HomeList;
      expect(list.items.single.id, homeTestIntentionId(2));
    },
  );

  test('ответ чтения после закрытия Главной не публикуется', () async {
    final h = HomeHarness();
    h.dispose();

    h.repository.completeRead(0, items: [homeTestRow(1, 'Гулять')]);
    await pumpEventQueue();

    expect(h.repository.readCount, 1);
  });
}
