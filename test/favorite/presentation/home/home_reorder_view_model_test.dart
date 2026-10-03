import 'dart:async';

import 'package:doable/src/favorite/application/favorite_intentions.dart';
import 'package:doable/src/favorite/application/favorite_order_command.dart';
import 'package:doable/src/favorite/domain/favorite_order.dart';
import 'package:doable/src/favorite/presentation/home/home_state.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:flutter_test/flutter_test.dart';

import 'home_test_support.dart';

/// Перестановка на Главной: запрошенное положение, ожидание сохранения и
/// завершение по результату координатора.
///
/// Намерения 1 «А», 2 «Б», 3 «В» и 4 «Г» избранные в этом порядке и показаны
/// списком на ревизии 1; тестовая граница хранит тот же полный порядок.
void main() {
  final a = homeTestIntentionId(1);
  final b = homeTestIntentionId(2);
  final c = homeTestIntentionId(3);
  final d = homeTestIntentionId(4);

  final rowsAbcd = [
    homeTestRow(1, 'А'),
    homeTestRow(2, 'Б'),
    homeTestRow(3, 'В'),
    homeTestRow(4, 'Г'),
  ];

  /// Главная со списком А, Б, В, Г на ревизии 1 после первоначального чтения.
  Future<HomeHarness> loadedHome() async {
    final h = HomeHarness();
    addTearDown(h.dispose);
    h.repository.favoriteOrder = homeTestOrder([1, 2, 3, 4]);
    h.repository.completeRead(0, items: rowsAbcd);
    await pumpEventQueue();
    expect((h.state as HomeList).acceptsReorder, isTrue);
    return h;
  }

  HomeList list(HomeHarness h) => h.state as HomeList;

  List<IntentionId> confirmedIds(HomeHarness h) => [
    for (final row in list(h).items) row.id,
  ];

  List<IntentionId> displayedIds(HomeHarness h) => [
    for (final row in list(h).displayedItems) row.id,
  ];

  int revisionOf(HomeLoaded loaded) =>
      (loaded.revision as HomeTestRevision).number;

  group('запрос перестановки', () {
    test('перемещение по текущему списку передаётся координатору, а список '
        'показывает запрошенное положение с ожиданием сохранения', () async {
      final h = await loadedHome();

      h.model.move(d, AfterFavoritePlacement(a));

      final command = h.repository.moves.single.command;
      expect(command.intentionId, d);
      expect((command.placement as AfterFavoritePlacement).anchorId, a);
      expect(h.coordinator.isFavoriteOrderRunning, isTrue);
      final saving = list(h).reorder as HomeReorderSaving;
      expect(saving.intentionId, d);
      expect((saving.placement as AfterFavoritePlacement).anchorId, a);
      // Подтверждённый снимок отделён от запрошенного положения.
      expect(confirmedIds(h), [a, b, c, d]);
      expect(displayedIds(h), [a, d, b, c]);
      expect(list(h).acceptsReorder, isFalse);
      expect(list(h).freshness, isA<HomeFreshnessCurrent>());
      expect(revisionOf(list(h)), 1);
      expect(h.repository.readCount, 1);
    });

    test('перемещение на первое место показывает намерение первым', () async {
      final h = await loadedHome();

      h.model.move(c, const FirstFavoritePlacement());

      expect(
        h.repository.moves.single.command.placement,
        isA<FirstFavoritePlacement>(),
      );
      expect(list(h).reorder, isA<HomeReorderSaving>());
      expect(confirmedIds(h), [a, b, c, d]);
      expect(displayedIds(h), [c, a, b, d]);
    });

    test('вторая перестановка во время выполняющейся не принимается и не '
        'отправляется', () async {
      final h = await loadedHome();
      h.model.move(d, AfterFavoritePlacement(a));

      h.model.move(b, const FirstFavoritePlacement());
      h.model.move(c, AfterFavoritePlacement(d));
      await pumpEventQueue();

      expect(h.repository.moves, hasLength(1));
      expect(displayedIds(h), [a, d, b, c]);
    });

    test(
      'перемещение без изменения положения в списке команду не отправляет',
      () async {
        final h = await loadedHome();

        h.model.move(b, AfterFavoritePlacement(a));
        h.model.move(a, const FirstFavoritePlacement());
        await pumpEventQueue();

        expect(h.repository.moves, isEmpty);
        expect(h.coordinator.isFavoriteOrderRunning, isFalse);
        expect(list(h).reorder, isA<HomeReorderIdle>());
        expect(list(h).acceptsReorder, isTrue);
        expect(displayedIds(h), [a, b, c, d]);
      },
    );

    test('опора на само перемещаемое намерение или на намерение вне списка '
        'команду не отправляет', () async {
      final h = await loadedHome();
      final notShown = homeTestIntentionId(9);

      h.model.move(c, AfterFavoritePlacement(c));
      h.model.move(notShown, AfterFavoritePlacement(a));
      h.model.move(a, AfterFavoritePlacement(notShown));
      await pumpEventQueue();

      expect(h.repository.moves, isEmpty);
      expect(list(h).reorder, isA<HomeReorderIdle>());
      expect(displayedIds(h), [a, b, c, d]);
    });

    group(
      'без текущего подтверждённого списка перестановка не принимается',
      () {
        test('во время загрузки', () async {
          final h = HomeHarness();
          addTearDown(h.dispose);

          h.model.move(b, const FirstFavoritePlacement());
          await pumpEventQueue();

          expect(h.state, isA<HomeLoading>());
          expect(h.repository.moves, isEmpty);
        });

        test('при пустой Главной', () async {
          final h = HomeHarness();
          addTearDown(h.dispose);
          h.repository.completeRead(0, archivedCount: 2);
          await pumpEventQueue();

          h.model.move(b, AfterFavoritePlacement(a));
          await pumpEventQueue();

          expect(h.state, isA<HomeEmpty>());
          expect(h.repository.moves, isEmpty);
        });

        test('при отказе получения', () async {
          final h = HomeHarness();
          addTearDown(h.dispose);
          h.repository.failRead(
            0,
            const FavoriteIntentionsUnavailableFailure(),
          );
          await pumpEventQueue();

          h.model.move(b, const FirstFavoritePlacement());
          await pumpEventQueue();

          expect(h.state, isA<HomeUnavailable>());
          expect(h.repository.moves, isEmpty);
        });

        test('во время обновления списка', () async {
          final h = await loadedHome();
          await h.confirm(
            UpdateIntention(id: b, title: 'Бэ', description: null),
            revision: 2,
            before: homeTestSummary(2, 'Б'),
            after: homeTestSummary(2, 'Бэ'),
          );
          expect(list(h).freshness, isA<HomeFreshnessRefreshing>());
          expect(list(h).acceptsReorder, isFalse);

          h.model.move(d, AfterFavoritePlacement(a));
          await pumpEventQueue();

          expect(h.repository.moves, isEmpty);
          expect(list(h).reorder, isA<HomeReorderIdle>());
        });

        test('при неактуальном списке', () async {
          final h = await loadedHome();
          await h.confirm(
            UpdateIntention(id: b, title: 'Бэ', description: null),
            revision: 2,
            before: homeTestSummary(2, 'Б'),
            after: homeTestSummary(2, 'Бэ'),
          );
          h.repository.failRead(
            1,
            const FavoriteIntentionsUnavailableFailure(),
          );
          await pumpEventQueue();
          expect(list(h).freshness, isA<HomeFreshnessStale>());
          expect(list(h).acceptsReorder, isFalse);

          h.model.move(d, AfterFavoritePlacement(a));
          await pumpEventQueue();

          expect(h.repository.moves, isEmpty);
          expect(displayedIds(h), [a, b, c, d]);
        });
      },
    );
  });

  group('успешная запись', () {
    test(
      'применяется только цельным снимком не старше ревизии завершения',
      () async {
        final h = await loadedHome();
        h.model.move(d, AfterFavoritePlacement(a));

        h.repository.completeMove(0, revision: 2);
        await pumpEventQueue();

        // Граница вычислила новый полный порядок функцией правила.
        expect(h.repository.favoriteOrder.intentionIds, [a, d, b, c]);
        expect(h.coordinator.isFavoriteOrderRunning, isFalse);
        final awaiting = list(h).reorder as HomeReorderAwaitingSnapshot;
        expect((awaiting.revision as HomeTestRevision).number, 2);
        expect(confirmedIds(h), [a, b, c, d]);
        expect(displayedIds(h), [a, d, b, c]);
        expect(list(h).acceptsReorder, isFalse);
        // Пакет изменения порядка перечитывает полный снимок.
        expect(h.repository.readCount, 2);

        // Снимок старше ревизии завершения не публикуется.
        h.repository.completeRead(1, items: rowsAbcd);
        await pumpEventQueue();
        expect(list(h).reorder, isA<HomeReorderAwaitingSnapshot>());
        expect(confirmedIds(h), [a, b, c, d]);
        expect(displayedIds(h), [a, d, b, c]);
        expect(h.repository.readCount, 3);

        h.repository.completeRead(
          2,
          items: [
            homeTestRow(1, 'А'),
            homeTestRow(4, 'Г'),
            homeTestRow(2, 'Б'),
            homeTestRow(3, 'В'),
          ],
          revision: 2,
        );
        await pumpEventQueue();

        expect(list(h).reorder, isA<HomeReorderIdle>());
        expect(confirmedIds(h), [a, d, b, c]);
        expect(displayedIds(h), [a, d, b, c]);
        expect(revisionOf(list(h)), 2);
        expect(list(h).freshness, isA<HomeFreshnessCurrent>());
        expect(list(h).acceptsReorder, isTrue);
        expect(h.repository.readCount, 3);
        expect(h.repository.moves, hasLength(1));
      },
    );

    test('освобождённый ключ до цельного снимка не разрешает команду по '
        'прежнему порядку', () async {
      final h = await loadedHome();
      h.model.move(d, AfterFavoritePlacement(a));
      h.repository.completeMove(0, revision: 2);
      await pumpEventQueue();
      expect(h.coordinator.isFavoriteOrderRunning, isFalse);

      h.model.move(c, const FirstFavoritePlacement());
      h.model.move(b, AfterFavoritePlacement(c));
      await pumpEventQueue();

      expect(h.repository.moves, hasLength(1));
      expect(list(h).reorder, isA<HomeReorderAwaitingSnapshot>());
      expect(displayedIds(h), [a, d, b, c]);
    });

    test(
      'снимок, уже несущий подтверждённую запись, завершает перестановку без '
      'нового чтения',
      () async {
        final h = await loadedHome();
        // Переименование принято до перестановки, а его пакет приходит во
        // время записи: чтение, которое он вызывает, исполняется после неё.
        unawaited(
          h.confirm(
            UpdateIntention(id: b, title: 'Бэ', description: null),
            revision: 2,
            before: homeTestSummary(2, 'Б'),
            after: homeTestSummary(2, 'Бэ'),
          ),
        );
        h.model.move(d, AfterFavoritePlacement(a));
        await pumpEventQueue();
        expect(h.repository.readCount, 2);
        h.repository.completeRead(
          1,
          items: [
            homeTestRow(1, 'А'),
            homeTestRow(4, 'Г'),
            homeTestRow(2, 'Бэ'),
            homeTestRow(3, 'В'),
          ],
          revision: 3,
        );
        await pumpEventQueue();
        expect(list(h).reorder, isA<HomeReorderSaving>());

        h.repository.completeMove(0, revision: 3);
        await pumpEventQueue();

        expect(list(h).reorder, isA<HomeReorderIdle>());
        expect(confirmedIds(h), [a, d, b, c]);
        expect(list(h).items[2].title, 'Бэ');
        expect(revisionOf(list(h)), 3);
        expect(list(h).freshness, isA<HomeFreshnessCurrent>());
        expect(list(h).acceptsReorder, isTrue);
        expect(h.repository.readCount, 2);
      },
    );

    test('успех без изменения завершает ожидание без нового чтения', () async {
      final h = await loadedHome();
      // Граница уже хранит порядок, в котором Г стоит сразу после А.
      h.repository.favoriteOrder = homeTestOrder([1, 4, 2, 3]);
      h.model.move(d, AfterFavoritePlacement(a));

      h.repository.completeMove(0, revision: 1);
      await pumpEventQueue();

      expect(h.repository.favoriteOrder.intentionIds, [a, d, b, c]);
      expect(list(h).reorder, isA<HomeReorderIdle>());
      expect(displayedIds(h), [a, b, c, d]);
      expect(list(h).freshness, isA<HomeFreshnessCurrent>());
      expect(list(h).acceptsReorder, isTrue);
      expect(h.repository.readCount, 1);
      expect(h.coordinator.isFavoriteOrderRunning, isFalse);
    });

    test('отказ чтения после записи сохраняет последний подтверждённый список '
        'неактуальным и запрещает перестановку', () async {
      final h = await loadedHome();
      h.model.move(d, AfterFavoritePlacement(a));
      h.repository.completeMove(0, revision: 2);
      await pumpEventQueue();

      h.repository.failRead(1, const FavoriteIntentionsUnavailableFailure());
      await pumpEventQueue();

      expect(list(h).reorder, isA<HomeReorderIdle>());
      expect(confirmedIds(h), [a, b, c, d]);
      expect(displayedIds(h), [a, b, c, d]);
      expect(revisionOf(list(h)), 1);
      expect(list(h).freshness, isA<HomeFreshnessStale>());
      expect(list(h).acceptsReorder, isFalse);
      h.model.move(c, const FirstFavoritePlacement());
      await pumpEventQueue();
      expect(h.repository.moves, hasLength(1));

      // Повтор при недоступности возвращает актуальный список и перестановку.
      unawaited(h.model.retry());
      h.repository.completeRead(
        2,
        items: [
          homeTestRow(1, 'А'),
          homeTestRow(4, 'Г'),
          homeTestRow(2, 'Б'),
          homeTestRow(3, 'В'),
        ],
        revision: 2,
      );
      await pumpEventQueue();

      expect(confirmedIds(h), [a, d, b, c]);
      expect(list(h).freshness, isA<HomeFreshnessCurrent>());
      expect(list(h).acceptsReorder, isTrue);
    });

    test(
      'перестановка, принятая не этой Главной, тоже перечитывает снимок',
      () async {
        final h = await loadedHome();

        final accepted = h.coordinator.acceptFavoriteOrderMove(
          MoveFavoriteIntention(
            intentionId: c,
            placement: const FirstFavoritePlacement(),
          ),
        ) as FavoriteOrderCommandAccepted;
        h.repository.completeMove(0, revision: 2);
        await accepted.future;
        await pumpEventQueue();

        expect(list(h).reorder, isA<HomeReorderIdle>());
        expect(list(h).freshness, isA<HomeFreshnessRefreshing>());
        expect(h.repository.readCount, 2);

        h.repository.completeRead(
          1,
          items: [
            homeTestRow(3, 'В'),
            homeTestRow(1, 'А'),
            homeTestRow(2, 'Б'),
            homeTestRow(4, 'Г'),
          ],
          revision: 2,
        );
        await pumpEventQueue();

        expect(confirmedIds(h), [c, a, b, d]);
        expect(list(h).acceptsReorder, isTrue);
      },
    );
  });

  group('отказ записи возвращает последний подтверждённый порядок', () {
    /// Отказ остаётся общей поверхности: Главная его не присваивает, и
    /// регистрация оболочки получает именно его.
    Future<void> expectSharedFailure(HomeHarness h, Matcher failure) async {
      final registration = h.coordinator.registerAppPresentation();
      addTearDown(registration.release);
      final claim = await registration.nextClaim();
      final completion = claim!.completion as FavoriteOrderFailedCompletion;
      expect(completion.failure, failure);
    }

    Future<HomeHarness> failedMove(void Function(HomeHarness h) fail) async {
      final h = await loadedHome();
      h.model.move(d, AfterFavoritePlacement(a));
      fail(h);
      await pumpEventQueue();
      return h;
    }

    void expectConfirmedOrder(HomeHarness h) {
      expect(list(h).reorder, isA<HomeReorderIdle>());
      expect(confirmedIds(h), [a, b, c, d]);
      expect(displayedIds(h), [a, b, c, d]);
      expect(revisionOf(list(h)), 1);
      expect(list(h).freshness, isA<HomeFreshnessCurrent>());
      expect(list(h).acceptsReorder, isTrue);
      expect(h.repository.readCount, 1);
      // Команда не повторяется автоматически.
      expect(h.repository.moves, hasLength(1));
      expect(h.coordinator.isFavoriteOrderRunning, isFalse);
    }

    test('при недоступности', () async {
      final h = await failedMove(
        (h) =>
            h.repository.failMove(0, const FavoriteOrderUnavailableFailure()),
      );

      expectConfirmedOrder(h);
      expect(h.repository.favoriteOrder.intentionIds, [a, b, c, d]);
      await expectSharedFailure(h, isA<FavoriteOrderUnavailableFailure>());
    });

    test('при повреждении', () async {
      final h = await failedMove(
        (h) => h.repository.failMove(0, const FavoriteOrderCorruptionFailure()),
      );

      expectConfirmedOrder(h);
      await expectSharedFailure(h, isA<FavoriteOrderCorruptionFailure>());
    });

    test('при неизвестном отказе', () async {
      final h = await failedMove(
        (h) => h.repository.failMove(0, const FavoriteOrderUnexpectedFailure()),
      );

      expectConfirmedOrder(h);
      await expectSharedFailure(h, isA<FavoriteOrderUnexpectedFailure>());
    });

    test('при исключении границы', () async {
      final h = await failedMove(
        (h) => h.repository.throwFromMove(
          0,
          StateError('UPDATE favorite_intentions SET position = ?'),
        ),
      );

      expectConfirmedOrder(h);
      await expectSharedFailure(h, isA<FavoriteOrderUnexpectedFailure>());
    });

    test('при ошибке ввода', () async {
      final h = await failedMove(
        (h) => h.repository.failMove(0, const FavoriteOrderInputFailure()),
      );

      expectConfirmedOrder(h);
      await expectSharedFailure(h, isA<FavoriteOrderInputFailure>());
    });
  });

  test('конфликт актуального состояния запрашивает актуальный снимок без '
      'повторной отправки перемещения', () async {
    final h = await loadedHome();
    // Отметка Б к моменту записи снята: опора перестала быть избранной.
    h.repository.favoriteOrder = homeTestOrder([1, 3, 4]);
    h.model.move(a, AfterFavoritePlacement(b));

    h.repository.completeMove(0, revision: 1);
    await pumpEventQueue();

    expect(h.repository.favoriteOrder.intentionIds, [a, c, d]);
    expect(list(h).reorder, isA<HomeReorderIdle>());
    expect(confirmedIds(h), [a, b, c, d]);
    expect(displayedIds(h), [a, b, c, d]);
    expect(list(h).freshness, isA<HomeFreshnessRefreshing>());
    expect(list(h).acceptsReorder, isFalse);
    expect(h.repository.readCount, 2);

    h.repository.completeRead(
      1,
      items: [homeTestRow(1, 'А'), homeTestRow(3, 'В'), homeTestRow(4, 'Г')],
      revision: 2,
    );
    await pumpEventQueue();

    expect(confirmedIds(h), [a, c, d]);
    expect(list(h).freshness, isA<HomeFreshnessCurrent>());
    expect(list(h).acceptsReorder, isTrue);
    expect(h.repository.moves, hasLength(1));
  });

  test('конфликт из-за снятой до записи отметки опоры приводит к актуальному '
      'списку без повторной отправки', () async {
    final h = await loadedHome();
    // Снятие отметки Б принято до перестановки и исполняется раньше неё.
    h.repository.favoriteOrder = homeTestOrder([1, 3, 4]);
    unawaited(
      h.confirm(
        UnmarkIntentionFavorite(b),
        revision: 2,
        before: homeTestSummary(2, 'Б'),
        after: homeTestSummary(2, 'Б', favoriteMark: FavoriteMark.notFavorite),
      ),
    );
    h.model.move(a, AfterFavoritePlacement(b));
    expect(list(h).reorder, isA<HomeReorderSaving>());
    await pumpEventQueue();
    expect(list(h).freshness, isA<HomeFreshnessRefreshing>());
    expect(h.repository.readCount, 2);

    h.repository.completeMove(0, revision: 2);
    await pumpEventQueue();

    expect(list(h).reorder, isA<HomeReorderIdle>());
    expect(displayedIds(h), [a, b, c, d]);
    expect(list(h).freshness, isA<HomeFreshnessRefreshing>());
    expect(list(h).acceptsReorder, isFalse);

    // Ответ старше снятия отметки барьер ревизии не публикует, и чтение
    // повторяется.
    h.repository.completeRead(1, items: rowsAbcd);
    await pumpEventQueue();
    expect(confirmedIds(h), [a, b, c, d]);
    expect(h.repository.readCount, 3);
    h.repository.completeRead(
      2,
      items: [homeTestRow(1, 'А'), homeTestRow(3, 'В'), homeTestRow(4, 'Г')],
      revision: 2,
    );
    await pumpEventQueue();

    expect(confirmedIds(h), [a, c, d]);
    expect(list(h).freshness, isA<HomeFreshnessCurrent>());
    expect(list(h).acceptsReorder, isTrue);
    expect(h.repository.moves, hasLength(1));
  });

  test('архивированные избранные границы сохраняют места, а Главная показывает '
      'подтверждённый снимок', () async {
    final h = HomeHarness();
    addTearDown(h.dispose);
    // Полный порядок: А, архивированное Б, В, архивированное Г, Д.
    h.repository.favoriteOrder = homeTestOrder(
      [1, 2, 3, 4, 5],
      archived: {2, 4},
    );
    h.repository.completeRead(
      0,
      items: [homeTestRow(1, 'А'), homeTestRow(3, 'В'), homeTestRow(5, 'Д')],
      archivedCount: 2,
    );
    await pumpEventQueue();
    final e = homeTestIntentionId(5);

    h.model.move(e, AfterFavoritePlacement(a));
    expect(displayedIds(h), [a, e, c]);
    h.repository.completeMove(0, revision: 2);
    await pumpEventQueue();

    expect(h.repository.favoriteOrder.intentionIds, [a, e, b, c, d]);
    h.repository.completeRead(
      1,
      items: [homeTestRow(1, 'А'), homeTestRow(5, 'Д'), homeTestRow(3, 'В')],
      archivedCount: 2,
      revision: 2,
    );
    await pumpEventQueue();

    expect(list(h).reorder, isA<HomeReorderIdle>());
    expect(confirmedIds(h), [a, e, c]);
  });

  test('ожидание снимка после записи ограничено: без подтверждающего снимка '
      'список становится неактуальным', () async {
    // Снимок другой эпохи не подтверждает запись и не публикуется, а
    // повторные чтения ограничены.
    final h = await loadedHome();
    h.model.move(d, AfterFavoritePlacement(a));
    h.repository.completeMove(0, revision: 2);
    await pumpEventQueue();

    for (var read = 1; read < 9; read++) {
      if (read >= h.repository.readCount) break;
      h.repository.reads[read].complete(
        FavoriteIntentionsSuccess(
          FavoriteIntentionsSnapshot(
            items: rowsAbcd,
            archivedCount: 0,
            revision: const HomeTestRevision(5, 1),
          ),
        ),
      );
      await pumpEventQueue();
    }

    expect(h.repository.readCount, 9);
    expect(list(h).freshness, isA<HomeFreshnessStale>());
    expect(list(h).reorder, isA<HomeReorderIdle>());
    expect(confirmedIds(h), [a, b, c, d]);
    expect(list(h).acceptsReorder, isFalse);
    expect(h.repository.moves, hasLength(1));
  });

  test('запрошенное положение одноимённых намерений определяется '
      'идентификатором', () {
    final shown = HomeList(
      items: [homeTestRow(1, 'Гулять'), homeTestRow(2, 'Гулять')],
      revision: const HomeTestRevision(1),
      reorder: HomeReorderSaving(
        intentionId: homeTestIntentionId(2),
        placement: const FirstFavoritePlacement(),
      ),
    );

    expect(shown.displayedItems.map((row) => row.id), [
      homeTestIntentionId(2),
      homeTestIntentionId(1),
    ]);
    expect(shown.items.map((row) => row.id), [
      homeTestIntentionId(1),
      homeTestIntentionId(2),
    ]);
    expect(shown.acceptsReorder, isFalse);
    expect(
      HomeList(
        items: shown.items,
        revision: const HomeTestRevision(1),
      ).acceptsReorder,
      isTrue,
    );
  });
}
