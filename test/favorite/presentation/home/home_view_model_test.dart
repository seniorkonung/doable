import 'package:doable/src/favorite/application/favorite_intentions.dart';
import 'package:doable/src/favorite/presentation/home/home_state.dart';
import 'package:doable/src/favorite/presentation/home/home_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'home_test_support.dart';

void main() {
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
    });
  });

  group('повтор', () {
    test('повторный отказ снова показывает недоступность', () async {
      final h = HomeHarness();
      addTearDown(h.dispose);
      h.repository.failRead(0, const FavoriteIntentionsUnavailableFailure());
      await pumpEventQueue();

      h.model.retry();
      h.repository.failRead(1, const FavoriteIntentionsUnavailableFailure());
      await pumpEventQueue();

      expect(h.state, isA<HomeUnavailable>());
    });
  });

  test(
    'ответ прежнего чтения, пришедший после нового, не публикуется',
    () async {
      final h = HomeHarness();
      addTearDown(h.dispose);

      // Пересборка провайдера начинает новое чтение, пока прежнее не завершено.
      h.container.invalidate(homeViewModelProvider);
      expect(h.state, isA<HomeLoading>());

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
