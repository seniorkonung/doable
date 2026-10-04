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

/// Подтверждённое изменение, пакет которого приходит во время перестановки:
/// [order] — полный порядок границы после него, [changed] — снимок Главной с
/// ним до записи, [moved] — с ним и записью.
typedef _ConcurrentChange = ({
  String name,
  Future<void> Function(HomeHarness h, int revision) confirm,
  FavoriteOrder order,
  List<FavoriteIntentionRow> changed,
  List<FavoriteIntentionRow> moved,
  int archivedCount,
});

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

    test('отказ чтения после записи оставляет список неактуальным, не '
        'изображает запись откатившейся и запрещает перестановку', () async {
      final h = await loadedHome();
      h.model.move(d, AfterFavoritePlacement(a));
      h.repository.completeMove(0, revision: 2);
      await pumpEventQueue();

      h.repository.failRead(1, const FavoriteIntentionsUnavailableFailure());
      await pumpEventQueue();

      // Подтверждённый снимок остаётся прежним, а записанное положение
      // по-прежнему ждёт снимка и не выдаётся за него.
      final awaiting = list(h).reorder as HomeReorderAwaitingSnapshot;
      expect((awaiting.revision as HomeTestRevision).number, 2);
      expect(confirmedIds(h), [a, b, c, d]);
      expect(displayedIds(h), [a, d, b, c]);
      expect(revisionOf(list(h)), 1);
      final stale = list(h).freshness as HomeFreshnessStale;
      expect(stale.canRetry, isTrue);
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

      expect(list(h).reorder, isA<HomeReorderIdle>());
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
    // Записанное положение не изображается откатившимся и не становится
    // подтверждённым снимком.
    expect(list(h).reorder, isA<HomeReorderAwaitingSnapshot>());
    expect(confirmedIds(h), [a, b, c, d]);
    expect(displayedIds(h), [a, d, b, c]);
    expect(list(h).acceptsReorder, isFalse);
    expect(h.repository.moves, hasLength(1));

    // Явный повтор при недоступности получает подтверждающий снимок.
    unawaited(h.model.retry());
    h.repository.completeRead(
      9,
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
    expect(list(h).freshness, isA<HomeFreshnessCurrent>());
    expect(list(h).acceptsReorder, isTrue);
    expect(h.repository.readCount, 10);
  });

  group('подтверждённые изменения во время перестановки', () {
    // Полный порядок границы: А, Б, архивированное Д, В, Г; Главная
    // показывает А, Б, В и Г на ревизии 1. Перемещение Г сразу после А даёт
    // полный порядок А, Г, Б, Д, В.
    final e = homeTestIntentionId(5);
    final x = homeTestIntentionId(9);
    const defaultTitles = {1: 'А', 2: 'Б', 3: 'В', 4: 'Г', 5: 'Д', 6: 'Е'};

    List<FavoriteIntentionRow> rows(
      List<int> numbers, {
      Map<int, String> titles = const {},
      Map<int, int> counts = const {},
    }) => [
      for (final number in numbers)
        homeTestRow(
          number,
          titles[number] ?? defaultTitles[number]!,
          activeRelationCount: counts[number] ?? 0,
        ),
    ];

    /// Видимое содержимое строк: идентичность, название и число связей.
    List<(IntentionId, String, int)> described(
      List<FavoriteIntentionRow> items,
    ) => [
      for (final row in items) (row.id, row.title, row.activeRelationCount),
    ];

    Future<HomeHarness> loadedWithArchived() async {
      final h = HomeHarness();
      addTearDown(h.dispose);
      h.repository.favoriteOrder = homeTestOrder(
        [1, 2, 5, 3, 4],
        archived: {5},
      );
      h.repository.completeRead(0, items: rows([1, 2, 3, 4]), archivedCount: 1);
      await pumpEventQueue();
      expect(list(h).acceptsReorder, isTrue);
      return h;
    }

    /// Перестановка завершена цельным снимком [settled] ревизии [revision]:
    /// ни изменение, ни запись не потеряны, а перемещение не повторялось.
    void expectSettled(
      HomeHarness h,
      List<FavoriteIntentionRow> settled, {
      required int revision,
      required int reads,
    }) {
      expect(list(h).reorder, isA<HomeReorderIdle>());
      expect(described(list(h).items), described(settled));
      expect(described(list(h).displayedItems), described(settled));
      expect(revisionOf(list(h)), revision);
      expect(list(h).freshness, isA<HomeFreshnessCurrent>());
      expect(list(h).acceptsReorder, isTrue);
      expect(h.repository.readCount, reads);
      expect(h.repository.moves, hasLength(1));
    }

    final changes = <_ConcurrentChange>[
      (
        name: 'отметка нового избранного намерения',
        confirm: (h, revision) => h.confirm(
          MarkIntentionFavorite(homeTestIntentionId(6)),
          revision: revision,
          before: homeTestSummary(
            6,
            'Е',
            favoriteMark: FavoriteMark.notFavorite,
          ),
          after: homeTestSummary(6, 'Е'),
        ),
        order: homeTestOrder([1, 2, 5, 3, 4, 6], archived: {5}),
        changed: rows([1, 2, 3, 4, 6]),
        moved: rows([1, 4, 2, 3, 6]),
        archivedCount: 1,
      ),
      (
        name: 'полное создание сразу избранного намерения',
        confirm: (h, revision) => h.create(
          homeTestSummary(6, 'Е', tags: [homeTestTag(1, 'Дом')]),
          revision: revision,
        ),
        order: homeTestOrder([1, 2, 5, 3, 4, 6], archived: {5}),
        changed: rows([1, 2, 3, 4, 6]),
        moved: rows([1, 4, 2, 3, 6]),
        archivedCount: 1,
      ),
      (
        name: 'снятие отметки',
        confirm: (h, revision) => h.confirm(
          UnmarkIntentionFavorite(b),
          revision: revision,
          before: homeTestSummary(2, 'Б'),
          after: homeTestSummary(
            2,
            'Б',
            favoriteMark: FavoriteMark.notFavorite,
          ),
        ),
        order: homeTestOrder([1, 5, 3, 4], archived: {5}),
        changed: rows([1, 3, 4]),
        moved: rows([1, 4, 3]),
        archivedCount: 1,
      ),
      (
        name: 'архивирование',
        confirm: (h, revision) => h.confirm(
          ArchiveIntention(b),
          revision: revision,
          before: homeTestSummary(2, 'Б'),
          after: homeTestSummary(
            2,
            'Б',
            archiveState: IntentionArchiveState.archived,
          ),
        ),
        order: homeTestOrder([1, 2, 5, 3, 4], archived: {2, 5}),
        changed: rows([1, 3, 4]),
        moved: rows([1, 4, 3]),
        archivedCount: 2,
      ),
      (
        name: 'восстановление из архива',
        confirm: (h, revision) => h.confirm(
          RestoreIntention(e),
          revision: revision,
          before: homeTestSummary(
            5,
            'Д',
            archiveState: IntentionArchiveState.archived,
          ),
          after: homeTestSummary(5, 'Д'),
        ),
        order: homeTestOrder([1, 2, 5, 3, 4]),
        changed: rows([1, 2, 5, 3, 4]),
        moved: rows([1, 4, 2, 5, 3]),
        archivedCount: 0,
      ),
      (
        name: 'физическое удаление',
        confirm: (h, revision) => h.confirm(
          DeleteIntention(b),
          revision: revision,
          before: homeTestSummary(2, 'Б'),
          after: null,
        ),
        order: homeTestOrder([1, 5, 3, 4], archived: {5}),
        changed: rows([1, 3, 4]),
        moved: rows([1, 4, 3]),
        archivedCount: 1,
      ),
      (
        name: 'переименование',
        confirm: (h, revision) => h.confirm(
          UpdateIntention(id: b, title: 'Бэ', description: null),
          revision: revision,
          before: homeTestSummary(2, 'Б'),
          after: homeTestSummary(2, 'Бэ'),
        ),
        order: homeTestOrder([1, 2, 5, 3, 4], archived: {5}),
        changed: rows([1, 2, 3, 4], titles: {2: 'Бэ'}),
        moved: rows([1, 4, 2, 3], titles: {2: 'Бэ'}),
        archivedCount: 1,
      ),
      (
        name: 'изменение счётчиков связей',
        // Пакет чужой операции: каталожная мутация неизбранного намерения и
        // новые счётчики связей показанного Б.
        confirm: (h, revision) => h.confirm(
          UpdateIntention(id: x, title: 'Игрек', description: null),
          revision: revision,
          before: homeTestSummary(
            9,
            'Икс',
            favoriteMark: FavoriteMark.notFavorite,
          ),
          after: homeTestSummary(
            9,
            'Игрек',
            favoriteMark: FavoriteMark.notFavorite,
          ),
          activeRelationCounts: {2: 3},
        ),
        order: homeTestOrder([1, 2, 5, 3, 4], archived: {5}),
        changed: rows([1, 2, 3, 4], counts: {2: 3}),
        moved: rows([1, 4, 2, 3], counts: {2: 3}),
        archivedCount: 1,
      ),
    ];

    for (final change in changes) {
      group(change.name, () {
        test('во время записи: снимок до её завершения публикуется с '
            'запрошенным положением, а подтверждённая запись — следующим '
            'снимком', () async {
          final h = await loadedWithArchived();
          // Изменение принято до перестановки, а его пакет приходит во
          // время записи.
          unawaited(change.confirm(h, 2));
          h.model.move(d, AfterFavoritePlacement(a));
          await pumpEventQueue();
          expect(list(h).reorder, isA<HomeReorderSaving>());
          expect(list(h).freshness, isA<HomeFreshnessRefreshing>());
          expect(h.repository.readCount, 2);

          h.repository.completeRead(
            1,
            items: change.changed,
            archivedCount: change.archivedCount,
            revision: 2,
          );
          await pumpEventQueue();

          expect(list(h).reorder, isA<HomeReorderSaving>());
          expect(described(list(h).items), described(change.changed));
          expect(described(list(h).displayedItems), described(change.moved));
          expect(revisionOf(list(h)), 2);
          expect(list(h).freshness, isA<HomeFreshnessCurrent>());
          expect(list(h).acceptsReorder, isFalse);
          expect(h.repository.readCount, 2);

          h.repository.favoriteOrder = change.order;
          h.repository.completeMove(0, revision: 3);
          await pumpEventQueue();

          expect(list(h).reorder, isA<HomeReorderAwaitingSnapshot>());
          expect(described(list(h).items), described(change.changed));
          expect(described(list(h).displayedItems), described(change.moved));
          expect(h.repository.readCount, 3);

          h.repository.completeRead(
            2,
            items: change.moved,
            archivedCount: change.archivedCount,
            revision: 3,
          );
          await pumpEventQueue();

          expectSettled(h, change.moved, revision: 3, reads: 3);
        });

        test('во время записи: снимок, полученный после подтверждения '
            'записи, но старше неё, не возвращает прежний порядок', () async {
          final h = await loadedWithArchived();
          unawaited(change.confirm(h, 2));
          h.model.move(d, AfterFavoritePlacement(a));
          await pumpEventQueue();
          h.repository.favoriteOrder = change.order;
          h.repository.completeMove(0, revision: 3);
          await pumpEventQueue();

          // Пакет записи пришёл во время чтения: параллельного чтения нет.
          expect(h.repository.readCount, 2);
          expect(list(h).reorder, isA<HomeReorderAwaitingSnapshot>());
          expect(displayedIds(h), [a, d, b, c]);

          h.repository.completeRead(
            1,
            items: change.changed,
            archivedCount: change.archivedCount,
            revision: 2,
          );
          await pumpEventQueue();

          expect(list(h).reorder, isA<HomeReorderAwaitingSnapshot>());
          expect(described(list(h).items), described(rows([1, 2, 3, 4])));
          expect(revisionOf(list(h)), 1);
          expect(displayedIds(h), [a, d, b, c]);
          expect(list(h).freshness, isA<HomeFreshnessRefreshing>());
          expect(h.repository.readCount, 3);

          h.repository.completeRead(
            2,
            items: change.moved,
            archivedCount: change.archivedCount,
            revision: 3,
          );
          await pumpEventQueue();

          expectSettled(h, change.moved, revision: 3, reads: 3);
        });

        test('во время перечитывания после записи: снимок записи без '
            'изменения не публикуется, и изменение не теряется', () async {
          final h = await loadedWithArchived();
          h.model.move(d, AfterFavoritePlacement(a));
          h.repository.completeMove(0, revision: 2);
          await pumpEventQueue();
          expect(h.repository.readCount, 2);

          await change.confirm(h, 3);

          expect(h.repository.readCount, 2);
          expect(list(h).reorder, isA<HomeReorderAwaitingSnapshot>());
          expect(displayedIds(h), [a, d, b, c]);

          h.repository.completeRead(
            1,
            items: rows([1, 4, 2, 3]),
            archivedCount: 1,
            revision: 2,
          );
          await pumpEventQueue();

          expect(list(h).reorder, isA<HomeReorderAwaitingSnapshot>());
          expect(revisionOf(list(h)), 1);
          expect(displayedIds(h), [a, d, b, c]);
          expect(list(h).freshness, isA<HomeFreshnessRefreshing>());
          expect(h.repository.readCount, 3);

          h.repository.completeRead(
            2,
            items: change.moved,
            archivedCount: change.archivedCount,
            revision: 3,
          );
          await pumpEventQueue();

          expectSettled(h, change.moved, revision: 3, reads: 3);
        });
      });
    }

    test('архивирование опоры во время записи показывает намерение после '
        'ближайшего оставшегося в списке предшественника', () async {
      final h = await loadedWithArchived();
      unawaited(
        h.confirm(
          ArchiveIntention(a),
          revision: 2,
          before: homeTestSummary(1, 'А'),
          after: homeTestSummary(
            1,
            'А',
            archiveState: IntentionArchiveState.archived,
          ),
        ),
      );
      h.model.move(d, AfterFavoritePlacement(a));
      await pumpEventQueue();
      h.repository.completeRead(
        1,
        items: rows([2, 3, 4]),
        archivedCount: 2,
        revision: 2,
      );
      await pumpEventQueue();

      // Опора скрыта, а перед ней в запрошенном положении никого нет: Г
      // показан первым, как и окажется после записи.
      expect(list(h).reorder, isA<HomeReorderSaving>());
      expect(confirmedIds(h), [b, c, d]);
      expect(displayedIds(h), [d, b, c]);

      h.repository.favoriteOrder = homeTestOrder(
        [1, 2, 5, 3, 4],
        archived: {1, 5},
      );
      h.repository.completeMove(0, revision: 3);
      await pumpEventQueue();

      // Архивирование опоры перестановку не отклоняет: граница ставит Г
      // сразу после скрытого А.
      expect(h.repository.favoriteOrder.intentionIds, [a, d, b, e, c]);
      expect(list(h).reorder, isA<HomeReorderAwaitingSnapshot>());
      expect(displayedIds(h), [d, b, c]);

      h.repository.completeRead(
        2,
        items: rows([4, 2, 3]),
        archivedCount: 2,
        revision: 3,
      );
      await pumpEventQueue();

      expectSettled(h, rows([4, 2, 3]), revision: 3, reads: 3);
    });

    test('при скрытой архивированием опоре запрошенное положение следует за '
        'ближайшим показанным предшественником', () async {
      final h = await loadedWithArchived();
      // Г перемещается сразу после Б, перед которым стоит А.
      unawaited(
        h.confirm(
          ArchiveIntention(b),
          revision: 2,
          before: homeTestSummary(2, 'Б'),
          after: homeTestSummary(
            2,
            'Б',
            archiveState: IntentionArchiveState.archived,
          ),
        ),
      );
      h.model.move(d, AfterFavoritePlacement(b));
      expect(displayedIds(h), [a, b, d, c]);
      await pumpEventQueue();
      h.repository.completeRead(
        1,
        items: rows([1, 3, 4]),
        archivedCount: 2,
        revision: 2,
      );
      await pumpEventQueue();

      expect(list(h).reorder, isA<HomeReorderSaving>());
      expect(displayedIds(h), [a, d, c]);
    });

    test('запоздалый отказ записи не заменяет снимок, опубликованный во '
        'время неё', () async {
      final h = await loadedWithArchived();
      final renamed = rows([1, 2, 3, 4], titles: {2: 'Бэ'});
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
      h.repository.completeRead(
        1,
        items: renamed,
        archivedCount: 1,
        revision: 2,
      );
      await pumpEventQueue();

      h.repository.failMove(0, const FavoriteOrderUnavailableFailure());
      await pumpEventQueue();

      // Последний подтверждённый порядок — снимок ревизии 2, а не прежний
      // показанный до записи.
      expectSettled(h, renamed, revision: 2, reads: 2);
    });

    test('отказ операции намерения во время перечитывания не меняет '
        'ожидание снимка записи', () async {
      final h = await loadedWithArchived();
      h.model.move(d, AfterFavoritePlacement(a));
      h.repository.completeMove(0, revision: 2);
      await pumpEventQueue();

      await h.reject(UpdateIntention(id: b, title: 'Бэ', description: null));

      expect(list(h).reorder, isA<HomeReorderAwaitingSnapshot>());
      expect(displayedIds(h), [a, d, b, c]);
      expect(list(h).freshness, isA<HomeFreshnessRefreshing>());
      expect(h.repository.readCount, 2);

      h.repository.completeRead(
        1,
        items: rows([1, 4, 2, 3]),
        archivedCount: 1,
        revision: 2,
      );
      await pumpEventQueue();

      expectSettled(h, rows([1, 4, 2, 3]), revision: 2, reads: 2);
    });

    test('конфликт после удаления опоры во время записи обновляет список '
        'тем же чтением без повторной отправки перемещения', () async {
      final h = await loadedWithArchived();
      unawaited(
        h.confirm(
          DeleteIntention(a),
          revision: 2,
          before: homeTestSummary(1, 'А'),
          after: null,
        ),
      );
      h.model.move(d, AfterFavoritePlacement(a));
      await pumpEventQueue();
      // Удаление опоры исполнено раньше записи.
      h.repository.favoriteOrder = homeTestOrder([2, 5, 3, 4], archived: {5});
      h.repository.completeMove(0, revision: 2);
      await pumpEventQueue();

      // Конфликт запрашивает актуальный снимок, а чтение уже выполняется:
      // параллельного чтения нет.
      expect(list(h).reorder, isA<HomeReorderIdle>());
      expect(displayedIds(h), [a, b, c, d]);
      expect(list(h).freshness, isA<HomeFreshnessRefreshing>());
      expect(list(h).acceptsReorder, isFalse);
      expect(h.repository.readCount, 2);

      h.repository.completeRead(
        1,
        items: rows([2, 3, 4]),
        archivedCount: 1,
        revision: 2,
      );
      await pumpEventQueue();

      expectSettled(h, rows([2, 3, 4]), revision: 2, reads: 2);
    });

    group('отказ обновления после записи без повтора', () {
      const failures = <(String, FavoriteIntentionsReadFailure)>[
        ('повреждение', FavoriteIntentionsCorruptionFailure()),
        ('неизвестный отказ', FavoriteIntentionsUnexpectedFailure()),
      ];
      for (final (name, failure) in failures) {
        test('$name сохраняет записанное положение до следующего пакета '
            'любого вида', () async {
          final h = await loadedWithArchived();
          h.model.move(d, AfterFavoritePlacement(a));
          h.repository.completeMove(0, revision: 2);
          await pumpEventQueue();
          h.repository.failRead(1, failure);
          await pumpEventQueue();

          expect(list(h).reorder, isA<HomeReorderAwaitingSnapshot>());
          expect(confirmedIds(h), [a, b, c, d]);
          expect(displayedIds(h), [a, d, b, c]);
          final stale = list(h).freshness as HomeFreshnessStale;
          expect(stale.failure, failure);
          expect(stale.canRetry, isFalse);
          expect(list(h).acceptsReorder, isFalse);

          // Явный повтор при таком отказе чтения не запускает.
          await h.model.retry();
          expect(h.repository.readCount, 2);

          // Пакет, не затрагивающий избранное, повторяет обновление.
          await h.confirm(
            UpdateIntention(id: x, title: 'Игрек', description: null),
            revision: 3,
            before: homeTestSummary(
              9,
              'Икс',
              favoriteMark: FavoriteMark.notFavorite,
            ),
            after: homeTestSummary(
              9,
              'Игрек',
              favoriteMark: FavoriteMark.notFavorite,
            ),
          );
          expect(list(h).freshness, isA<HomeFreshnessRefreshing>());
          expect(list(h).reorder, isA<HomeReorderAwaitingSnapshot>());
          expect(h.repository.readCount, 3);

          h.repository.completeRead(
            2,
            items: rows([1, 4, 2, 3]),
            archivedCount: 1,
            revision: 3,
          );
          await pumpEventQueue();

          expectSettled(h, rows([1, 4, 2, 3]), revision: 3, reads: 3);
        });
      }
    });
  });

  group('подтверждённая перестановка для объявления экранному диктору', () {
    final rowsAdbc = [
      homeTestRow(1, 'А'),
      homeTestRow(4, 'Г'),
      homeTestRow(2, 'Б'),
      homeTestRow(3, 'В'),
    ];

    /// Подтверждение несёт перемещённое намерение с его местом в
    /// подтвердившем снимке, начиная с единицы, и числом строк снимка.
    void expectConfirmed(
      HomeConfirmedMove? confirmed, {
      required IntentionId intentionId,
      required String title,
      required int position,
      required int count,
    }) {
      expect(confirmed, isNotNull);
      expect(confirmed!.row.id, intentionId);
      expect(confirmed.row.title, title);
      expect(confirmed.position, position);
      expect(confirmed.count, count);
    }

    test('появляется только вместе с цельным снимком, подтвердившим запись, '
        'и несёт место перемещённого намерения в нём', () async {
      final h = await loadedHome();
      expect(list(h).confirmedMove, isNull);

      h.model.move(d, AfterFavoritePlacement(a));
      expect(list(h).reorder, isA<HomeReorderSaving>());
      expect(list(h).confirmedMove, isNull);

      h.repository.completeMove(0, revision: 2);
      await pumpEventQueue();
      expect(list(h).reorder, isA<HomeReorderAwaitingSnapshot>());
      expect(list(h).confirmedMove, isNull);

      // Снимок старше записи её не подтверждает.
      h.repository.completeRead(1, items: rowsAbcd);
      await pumpEventQueue();
      expect(list(h).confirmedMove, isNull);

      h.repository.completeRead(2, items: rowsAdbc, revision: 2);
      await pumpEventQueue();

      expect(list(h).reorder, isA<HomeReorderIdle>());
      expectConfirmed(
        list(h).confirmedMove,
        intentionId: d,
        title: 'Г',
        position: 2,
        count: 4,
      );
    });

    test('снимок, уже несущий запись к её завершению, подтверждает её с '
        'актуальными данными строк', () async {
      final h = await loadedHome();
      unawaited(
        h.confirm(
          UpdateIntention(id: d, title: 'Гэ', description: null),
          revision: 2,
          before: homeTestSummary(4, 'Г'),
          after: homeTestSummary(4, 'Гэ'),
        ),
      );
      h.model.move(d, AfterFavoritePlacement(a));
      await pumpEventQueue();
      h.repository.completeRead(
        1,
        items: [
          homeTestRow(1, 'А'),
          homeTestRow(4, 'Гэ'),
          homeTestRow(2, 'Б'),
          homeTestRow(3, 'В'),
        ],
        revision: 3,
      );
      await pumpEventQueue();
      expect(list(h).reorder, isA<HomeReorderSaving>());
      expect(list(h).confirmedMove, isNull);

      h.repository.completeMove(0, revision: 3);
      await pumpEventQueue();

      expect(list(h).reorder, isA<HomeReorderIdle>());
      expectConfirmed(
        list(h).confirmedMove,
        intentionId: d,
        title: 'Гэ',
        position: 2,
        count: 4,
      );
    });

    test('остаётся с подтвердившим снимком при смене актуальности и не '
        'переходит в следующий снимок', () async {
      final h = await loadedHome();
      h.model.move(d, AfterFavoritePlacement(a));
      h.repository.completeMove(0, revision: 2);
      await pumpEventQueue();
      h.repository.completeRead(1, items: rowsAdbc, revision: 2);
      await pumpEventQueue();
      final confirmed = list(h).confirmedMove;
      expect(confirmed, isNotNull);

      // Отметка Д требует обновления: показан тот же снимок.
      await h.confirm(
        MarkIntentionFavorite(homeTestIntentionId(5)),
        revision: 3,
        before: homeTestSummary(5, 'Д', favoriteMark: FavoriteMark.notFavorite),
        after: homeTestSummary(5, 'Д'),
      );
      expect(list(h).freshness, isA<HomeFreshnessRefreshing>());
      expect(identical(list(h).confirmedMove, confirmed), isTrue);

      h.repository.completeRead(
        2,
        items: [...rowsAdbc, homeTestRow(5, 'Д')],
        revision: 3,
      );
      await pumpEventQueue();

      expect(list(h).items, hasLength(5));
      expect(list(h).confirmedMove, isNull);
    });

    test(
      'снимок без перемещённого намерения не подтверждает его место',
      () async {
        final h = await loadedHome();
        h.model.move(d, AfterFavoritePlacement(a));
        h.repository.completeMove(0, revision: 2);
        await pumpEventQueue();
        // Г архивировано после записи, до подтверждающего снимка.
        await h.confirm(
          ArchiveIntention(d),
          revision: 3,
          before: homeTestSummary(4, 'Г'),
          after: homeTestSummary(
            4,
            'Г',
            archiveState: IntentionArchiveState.archived,
          ),
        );

        h.repository.completeRead(
          1,
          items: [
            homeTestRow(1, 'А'),
            homeTestRow(2, 'Б'),
            homeTestRow(3, 'В'),
          ],
          archivedCount: 1,
          revision: 3,
        );
        await pumpEventQueue();

        expect(list(h).reorder, isA<HomeReorderIdle>());
        expect(confirmedIds(h), [a, b, c]);
        expect(list(h).confirmedMove, isNull);
      },
    );

    for (final (name, complete) in <(String, void Function(HomeHarness h))>[
      (
        'успех без изменения',
        (h) {
          h.repository.favoriteOrder = homeTestOrder([1, 4, 2, 3]);
          h.repository.completeMove(0, revision: 1);
        },
      ),
      (
        'отказ записи',
        (h) =>
            h.repository.failMove(0, const FavoriteOrderUnavailableFailure()),
      ),
      (
        'конфликт актуального состояния',
        (h) {
          h.repository.favoriteOrder = homeTestOrder([2, 3, 4]);
          h.repository.completeMove(0, revision: 1);
        },
      ),
    ]) {
      test('$name не подтверждает новое место', () async {
        final h = await loadedHome();
        h.model.move(d, AfterFavoritePlacement(a));

        complete(h);
        await pumpEventQueue();
        if (h.repository.readCount > 1) {
          h.repository.completeRead(
            1,
            items: [
              homeTestRow(2, 'Б'),
              homeTestRow(3, 'В'),
              homeTestRow(4, 'Г'),
            ],
            revision: 2,
          );
          await pumpEventQueue();
        }

        expect(list(h).reorder, isA<HomeReorderIdle>());
        expect(list(h).confirmedMove, isNull);
      });
    }
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
