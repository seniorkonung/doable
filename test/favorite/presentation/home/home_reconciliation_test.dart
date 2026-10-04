import 'package:doable/src/favorite/application/favorite_intentions.dart';
import 'package:doable/src/favorite/application/favorite_order_command.dart';
import 'package:doable/src/favorite/domain/favorite_order.dart';
import 'package:doable/src/favorite/presentation/home/home_state.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:flutter_test/flutter_test.dart';

import 'home_test_support.dart';

/// Согласование Главной с подтверждёнными пакетами канала завершений.
///
/// Намерения 1 «А» и 2 «Б» избранные и показаны списком на ревизии 1;
/// намерение 3 «В» избранным становится в отдельных случаях, намерение 9
/// «Икс» не избранное.
void main() {
  final a = homeTestIntentionId(1);
  final b = homeTestIntentionId(2);
  final c = homeTestIntentionId(3);
  final x = homeTestIntentionId(9);

  final notFavoriteX = homeTestSummary(
    9,
    'Икс',
    favoriteMark: FavoriteMark.notFavorite,
  );

  /// Главная со списком А, Б на ревизии 1 после первоначального чтения.
  Future<HomeHarness> loadedHome() async {
    final h = HomeHarness();
    addTearDown(h.dispose);
    h.repository.completeRead(
      0,
      items: [homeTestRow(1, 'А'), homeTestRow(2, 'Б')],
    );
    await pumpEventQueue();
    expect(h.state, isA<HomeList>());
    return h;
  }

  /// Подтверждённая отметка намерения 3 «В» на ревизии [revision].
  Future<void> confirmMarkC(HomeHarness h, {required int revision}) =>
      h.confirm(
        MarkIntentionFavorite(c),
        revision: revision,
        before: homeTestSummary(3, 'В', favoriteMark: FavoriteMark.notFavorite),
        after: homeTestSummary(3, 'В'),
      );

  /// Подтверждённое переименование неизбранного намерения 9 на ревизии
  /// [revision]: пакет, не затрагивающий избранное.
  Future<void> confirmRenameX(
    HomeHarness h, {
    required int revision,
    Map<int, int> activeRelationCounts = const {},
  }) => h.confirm(
    UpdateIntention(id: x, title: 'Игрек', description: null),
    revision: revision,
    before: notFavoriteX,
    after: homeTestSummary(9, 'Игрек', favoriteMark: FavoriteMark.notFavorite),
    activeRelationCounts: activeRelationCounts,
  );

  List<IntentionId> ids(HomeHarness h) => [
    for (final row in (h.state as HomeList).items) row.id,
  ];

  void expectRefreshingAB(HomeHarness h) {
    final list = h.state as HomeList;
    expect(list.items.map((row) => row.id), [a, b]);
    expect(list.freshness, isA<HomeFreshnessRefreshing>());
  }

  group('подтверждённое изменение избранного перечитывает полный снимок', () {
    test('отметка добавляет намерение последним', () async {
      final h = await loadedHome();

      await confirmMarkC(h, revision: 2);

      expectRefreshingAB(h);
      expect(h.repository.readCount, 2);

      h.repository.completeRead(
        1,
        items: [homeTestRow(1, 'А'), homeTestRow(2, 'Б'), homeTestRow(3, 'В')],
        revision: 2,
      );
      await pumpEventQueue();

      expect(ids(h), [a, b, c]);
      final list = h.state as HomeList;
      expect(list.freshness, isA<HomeFreshnessCurrent>());
      expect((list.revision as HomeTestRevision).number, 2);
      expect(h.repository.readCount, 2);
    });

    test('снятие отметки убирает намерение', () async {
      final h = await loadedHome();

      await h.confirm(
        UnmarkIntentionFavorite(b),
        revision: 2,
        before: homeTestSummary(2, 'Б'),
        after: homeTestSummary(2, 'Б', favoriteMark: FavoriteMark.notFavorite),
      );
      expect(h.repository.readCount, 2);
      h.repository.completeRead(1, items: [homeTestRow(1, 'А')], revision: 2);
      await pumpEventQueue();

      expect(ids(h), [a]);
    });

    test('переименование обновляет строку без изменения порядка', () async {
      final h = await loadedHome();

      await h.confirm(
        UpdateIntention(id: a, title: 'Альфа', description: null),
        revision: 2,
        before: homeTestSummary(1, 'А'),
        after: homeTestSummary(1, 'Альфа'),
      );
      expect(h.repository.readCount, 2);
      h.repository.completeRead(
        1,
        items: [homeTestRow(1, 'Альфа'), homeTestRow(2, 'Б')],
        revision: 2,
      );
      await pumpEventQueue();

      expect(ids(h), [a, b]);
      expect((h.state as HomeList).items.first.title, 'Альфа');
    });

    test('изменение готовности обновляет строку', () async {
      final h = await loadedHome();

      await h.confirm(
        EnableIntentionReadiness(b),
        revision: 2,
        before: homeTestSummary(2, 'Б'),
        after: homeTestSummary(2, 'Б', readiness: IntentionReadiness.ready),
      );
      expect(h.repository.readCount, 2);
      h.repository.completeRead(
        1,
        items: [
          homeTestRow(1, 'А'),
          homeTestRow(2, 'Б', readiness: IntentionReadiness.ready),
        ],
        revision: 2,
      );
      await pumpEventQueue();

      expect(ids(h), [a, b]);
      expect(
        (h.state as HomeList).items.last.readiness,
        IntentionReadiness.ready,
      );
    });

    test('архивирование скрывает намерение, восстановление возвращает его на '
        'место', () async {
      final h = await loadedHome();

      await h.confirm(
        ArchiveIntention(a),
        revision: 2,
        before: homeTestSummary(1, 'А'),
        after: homeTestSummary(
          1,
          'А',
          archiveState: IntentionArchiveState.archived,
        ),
      );
      expect(h.repository.readCount, 2);
      h.repository.completeRead(
        1,
        items: [homeTestRow(2, 'Б')],
        archivedCount: 1,
        revision: 2,
      );
      await pumpEventQueue();
      expect(ids(h), [b]);

      await h.confirm(
        RestoreIntention(a),
        revision: 3,
        before: homeTestSummary(
          1,
          'А',
          archiveState: IntentionArchiveState.archived,
        ),
        after: homeTestSummary(1, 'А'),
      );
      expect(h.repository.readCount, 3);
      h.repository.completeRead(
        2,
        items: [homeTestRow(1, 'А'), homeTestRow(2, 'Б')],
        revision: 3,
      );
      await pumpEventQueue();

      expect(ids(h), [a, b]);
    });

    test('архивирование последнего показанного намерения меняет причину '
        'пустого состояния, а его удаление — возвращает прежнюю', () async {
      final h = HomeHarness();
      addTearDown(h.dispose);
      h.repository.completeRead(0, items: [homeTestRow(1, 'А')]);
      await pumpEventQueue();

      await h.confirm(
        ArchiveIntention(a),
        revision: 2,
        before: homeTestSummary(1, 'А'),
        after: homeTestSummary(
          1,
          'А',
          archiveState: IntentionArchiveState.archived,
        ),
      );
      h.repository.completeRead(1, archivedCount: 1, revision: 2);
      await pumpEventQueue();

      final archived = h.state as HomeEmpty;
      expect(archived.reason, HomeEmptyReason.allArchived);
      expect(archived.freshness, isA<HomeFreshnessCurrent>());

      // Пустое состояние тоже согласуется: избранное намерение в нём не
      // показано, но каталожная мутация несёт его отметку.
      await h.confirm(
        DeleteIntention(a),
        revision: 3,
        before: homeTestSummary(
          1,
          'А',
          archiveState: IntentionArchiveState.archived,
        ),
        after: null,
      );
      expect((h.state as HomeEmpty).reason, HomeEmptyReason.allArchived);
      expect((h.state as HomeEmpty).freshness, isA<HomeFreshnessRefreshing>());
      expect(h.repository.readCount, 3);
      h.repository.completeRead(2, revision: 3);
      await pumpEventQueue();

      final none = h.state as HomeEmpty;
      expect(none.reason, HomeEmptyReason.noFavorites);
      expect(none.freshness, isA<HomeFreshnessCurrent>());
    });

    test('физическое удаление убирает строку с сохранением порядка '
        'остальных', () async {
      final h = HomeHarness();
      addTearDown(h.dispose);
      h.repository.completeRead(
        0,
        items: [homeTestRow(1, 'А'), homeTestRow(2, 'Б'), homeTestRow(3, 'В')],
      );
      await pumpEventQueue();

      await h.confirm(
        DeleteIntention(b),
        revision: 2,
        before: homeTestSummary(2, 'Б'),
        after: null,
      );
      expect(h.repository.readCount, 2);
      h.repository.completeRead(
        1,
        items: [homeTestRow(1, 'А'), homeTestRow(3, 'В')],
        revision: 2,
      );
      await pumpEventQueue();

      expect(ids(h), [a, c]);
    });

    test('изменение числа активных связей намерения из списка обновляет '
        'строку', () async {
      final h = await loadedHome();

      // Пакет чужой операции: каталожная мутация неизбранного намерения и
      // новые счётчики связей избранного А.
      await confirmRenameX(h, revision: 2, activeRelationCounts: {1: 3});

      expectRefreshingAB(h);
      expect(h.repository.readCount, 2);
      h.repository.completeRead(
        1,
        items: [
          homeTestRow(1, 'А', activeRelationCount: 3),
          homeTestRow(2, 'Б'),
        ],
        revision: 2,
      );
      await pumpEventQueue();

      expect((h.state as HomeList).items.first.activeRelationCount, 3);
    });
  });

  group('пакет, не затрагивающий избранное, чтения не вызывает', () {
    test('каталожная мутация неизбранного намерения', () async {
      final h = await loadedHome();
      final before = h.state;

      await confirmRenameX(h, revision: 2);

      expect(h.state, same(before));
      expect(h.repository.readCount, 1);
    });

    test('счётчики связей намерения не из показанного списка', () async {
      final h = await loadedHome();
      final before = h.state;

      await confirmRenameX(h, revision: 2, activeRelationCounts: {9: 4, 3: 1});

      expect(h.state, same(before));
      expect(h.repository.readCount, 1);
    });

    test('завершение без подтверждённого пакета', () async {
      final h = await loadedHome();
      final before = h.state;

      await h.reject(UnmarkIntentionFavorite(a));

      expect(h.state, same(before));
      expect(h.repository.readCount, 1);
    });

    test('пакет ревизии, уже отражённой показанным снимком', () async {
      final h = await loadedHome();
      final before = h.state;

      // Повторная отметка ревизию не продвигает: снимок ревизии 1 её
      // уже содержит.
      await h.confirm(
        MarkIntentionFavorite(a),
        revision: 1,
        before: homeTestSummary(1, 'А'),
        after: homeTestSummary(1, 'А'),
      );

      expect(h.state, same(before));
      expect(h.repository.readCount, 1);
    });

    test('при отказе первоначального получения', () async {
      final h = HomeHarness();
      addTearDown(h.dispose);
      h.repository.failRead(0, const FavoriteIntentionsCorruptionFailure());
      await pumpEventQueue();

      await confirmRenameX(h, revision: 2, activeRelationCounts: {1: 3});

      expect(h.state, isA<HomeCorruption>());
      expect(h.repository.readCount, 1);
    });
  });

  group('изменение избранного согласуется при отказе получения', () {
    const failures = <(String, FavoriteIntentionsReadFailure)>[
      ('недоступности', FavoriteIntentionsUnavailableFailure()),
      ('повреждении', FavoriteIntentionsCorruptionFailure()),
      ('неизвестном отказе', FavoriteIntentionsUnexpectedFailure()),
    ];
    for (final (name, failure) in failures) {
      test('при $name пакет запускает новое получение', () async {
        final h = HomeHarness();
        addTearDown(h.dispose);
        h.repository.failRead(0, failure);
        await pumpEventQueue();

        await confirmMarkC(h, revision: 2);

        expect(h.state, isA<HomeLoading>());
        expect(h.repository.readCount, 2);

        h.repository.completeRead(1, items: [homeTestRow(3, 'В')], revision: 2);
        await pumpEventQueue();

        expect(ids(h), [c]);
        expect((h.state as HomeList).freshness, isA<HomeFreshnessCurrent>());
      });
    }

    test('повторный отказ получения остаётся отказом, а не пустым '
        'состоянием', () async {
      final h = HomeHarness();
      addTearDown(h.dispose);
      h.repository.failRead(0, const FavoriteIntentionsUnavailableFailure());
      await pumpEventQueue();

      await confirmMarkC(h, revision: 2);
      h.repository.failRead(1, const FavoriteIntentionsCorruptionFailure());
      await pumpEventQueue();

      expect(h.state, isA<HomeCorruption>());
      expect(h.repository.readCount, 2);
    });
  });

  group('запоздалое чтение не возвращает прежний список', () {
    test(
      'снимок старше ревизии пакета не публикуется и перечитывается',
      () async {
        final h = await loadedHome();

        await confirmMarkC(h, revision: 2);
        // Чтение обогнало подтверждение записи и вернуло прежний состав.
        h.repository.completeRead(
          1,
          items: [homeTestRow(2, 'Б'), homeTestRow(1, 'А')],
          revision: 1,
        );
        await pumpEventQueue();

        expectRefreshingAB(h);
        expect(h.repository.readCount, 3);

        h.repository.completeRead(
          2,
          items: [
            homeTestRow(1, 'А'),
            homeTestRow(2, 'Б'),
            homeTestRow(3, 'В'),
          ],
          revision: 2,
        );
        await pumpEventQueue();

        expect(ids(h), [a, b, c]);
        expect((h.state as HomeList).freshness, isA<HomeFreshnessCurrent>());
        expect(h.repository.readCount, 3);
      },
    );

    test('чтение, начатое до подтверждённой перестановки, не возвращает '
        'прежний порядок', () async {
      final h = await loadedHome();
      h.repository.favoriteOrder = homeTestOrder([1, 2, 3]);

      await confirmMarkC(h, revision: 2);
      expect(h.repository.readCount, 2);
      // Перестановку принял не экран Главной; её пакет приходит во время
      // чтения, начатого отметкой.
      final accepted = h.coordinator.acceptFavoriteOrderMove(
        MoveFavoriteIntention(
          intentionId: c,
          placement: const FirstFavoritePlacement(),
        ),
      ) as FavoriteOrderCommandAccepted;
      h.repository.completeMove(0, revision: 3);
      await accepted.future;
      await pumpEventQueue();
      expect(h.repository.readCount, 2);

      h.repository.completeRead(
        1,
        items: [homeTestRow(1, 'А'), homeTestRow(2, 'Б'), homeTestRow(3, 'В')],
        revision: 2,
      );
      await pumpEventQueue();

      expectRefreshingAB(h);
      expect(h.repository.readCount, 3);

      h.repository.completeRead(
        2,
        items: [homeTestRow(3, 'В'), homeTestRow(1, 'А'), homeTestRow(2, 'Б')],
        revision: 3,
      );
      await pumpEventQueue();

      expect(ids(h), [c, a, b]);
      expect((h.state as HomeList).freshness, isA<HomeFreshnessCurrent>());
      expect(h.repository.readCount, 3);
    });

    test('первоначальное чтение, начатое до подтверждённого изменения, не '
        'публикует прежний состав', () async {
      final h = HomeHarness();
      addTearDown(h.dispose);

      await confirmMarkC(h, revision: 5);
      expect(h.repository.readCount, 1);

      h.repository.completeRead(
        0,
        items: [homeTestRow(1, 'А'), homeTestRow(2, 'Б')],
        revision: 4,
      );
      await pumpEventQueue();

      expect(h.state, isA<HomeLoading>());
      expect(h.repository.readCount, 2);

      h.repository.completeRead(
        1,
        items: [homeTestRow(1, 'А'), homeTestRow(2, 'Б'), homeTestRow(3, 'В')],
        revision: 5,
      );
      await pumpEventQueue();

      expect(ids(h), [a, b, c]);
    });

    test('снимок другой эпохи ревизий не публикуется', () async {
      final h = await loadedHome();

      await confirmMarkC(h, revision: 2);
      h.repository.reads[1].complete(
        FavoriteIntentionsSuccess(
          FavoriteIntentionsSnapshot(
            items: [homeTestRow(1, 'А')],
            archivedCount: 0,
            revision: const HomeTestRevision(7, 1),
          ),
        ),
      );
      await pumpEventQueue();

      expectRefreshingAB(h);
      expect(h.repository.readCount, 3);
    });

    test('исчерпание повторов даёт устранимую недоступность без публикации '
        'устаревшего снимка', () async {
      final h = await loadedHome();

      await confirmMarkC(h, revision: 2);
      var read = 1;
      while ((h.state as HomeList).freshness is HomeFreshnessRefreshing) {
        expect(read, lessThan(50), reason: 'число повторов ограничено');
        expect(h.repository.readCount, read + 1);
        h.repository.completeRead(read, items: [homeTestRow(3, 'В')]);
        await pumpEventQueue();
        read++;
      }

      final list = h.state as HomeList;
      expect(list.items.map((row) => row.id), [a, b]);
      final stale = list.freshness as HomeFreshnessStale;
      expect(stale.failure, isA<FavoriteIntentionsUnavailableFailure>());
      expect(stale.canRetry, isTrue);
      expect(read - 1, greaterThan(1), reason: 'чтение повторялось');
      expect(h.repository.readCount, read);
    });

    test('исчерпание повторов первоначального получения даёт недоступность с '
        'повтором', () async {
      final h = HomeHarness();
      addTearDown(h.dispose);

      await confirmMarkC(h, revision: 2);
      var read = 0;
      while (h.state is HomeLoading) {
        expect(read, lessThan(50), reason: 'число повторов ограничено');
        expect(h.repository.readCount, read + 1);
        h.repository.completeRead(read, items: [homeTestRow(1, 'А')]);
        await pumpEventQueue();
        read++;
      }

      expect(h.state, isA<HomeUnavailable>());
      expect(h.repository.readCount, read);

      h.model.retry();
      h.repository.completeRead(
        read,
        items: [homeTestRow(3, 'В')],
        revision: 2,
      );
      await pumpEventQueue();

      expect(ids(h), [c]);
    });
  });

  group('пакеты, пришедшие во время чтения', () {
    test('не запускают параллельных чтений и не теряются', () async {
      final h = await loadedHome();

      await confirmMarkC(h, revision: 2);
      expect(h.repository.readCount, 2);

      await h.confirm(
        UnmarkIntentionFavorite(a),
        revision: 3,
        before: homeTestSummary(1, 'А'),
        after: homeTestSummary(1, 'А', favoriteMark: FavoriteMark.notFavorite),
      );
      await h.confirm(
        UpdateIntention(id: b, title: 'Бета', description: null),
        revision: 4,
        before: homeTestSummary(2, 'Б'),
        after: homeTestSummary(2, 'Бета'),
      );
      expectRefreshingAB(h);
      expect(h.repository.readCount, 2);

      // Снимок отражает только первый пакет.
      h.repository.completeRead(
        1,
        items: [homeTestRow(1, 'А'), homeTestRow(2, 'Б'), homeTestRow(3, 'В')],
        revision: 2,
      );
      await pumpEventQueue();

      expectRefreshingAB(h);
      expect(h.repository.readCount, 3);

      h.repository.completeRead(
        2,
        items: [homeTestRow(2, 'Бета'), homeTestRow(3, 'В')],
        revision: 4,
      );
      await pumpEventQueue();

      expect(ids(h), [b, c]);
      expect((h.state as HomeList).items.first.title, 'Бета');
      expect((h.state as HomeList).freshness, isA<HomeFreshnessCurrent>());
      expect(h.repository.readCount, 3);
    });

    test('снимок, уже отражающий пришедшие пакеты, публикуется без лишнего '
        'чтения', () async {
      final h = await loadedHome();

      await confirmMarkC(h, revision: 2);
      await h.confirm(
        UnmarkIntentionFavorite(a),
        revision: 3,
        before: homeTestSummary(1, 'А'),
        after: homeTestSummary(1, 'А', favoriteMark: FavoriteMark.notFavorite),
      );
      h.repository.completeRead(
        1,
        items: [homeTestRow(2, 'Б'), homeTestRow(3, 'В')],
        revision: 3,
      );
      await pumpEventQueue();

      expect(ids(h), [b, c]);
      expect((h.state as HomeList).freshness, isA<HomeFreshnessCurrent>());
      expect(h.repository.readCount, 2);
    });

    test('после отказа чтения, начатого до пакета, обновление '
        'повторяется', () async {
      final h = await loadedHome();

      await confirmMarkC(h, revision: 2);
      await h.confirm(
        UnmarkIntentionFavorite(a),
        revision: 3,
        before: homeTestSummary(1, 'А'),
        after: homeTestSummary(1, 'А', favoriteMark: FavoriteMark.notFavorite),
      );
      h.repository.failRead(1, const FavoriteIntentionsUnavailableFailure());
      await pumpEventQueue();

      // Отказ чтения, начатого до пакета ревизии 3, не публикуется: пакет
      // даёт ещё одно чтение.
      expectRefreshingAB(h);
      expect(h.repository.readCount, 3);

      h.repository.failRead(2, const FavoriteIntentionsUnavailableFailure());
      await pumpEventQueue();

      expect((h.state as HomeList).freshness, isA<HomeFreshnessStale>());
      expect(h.repository.readCount, 3);
    });

    test('счётчики связей намерения, появившегося только в новом снимке, не '
        'остаются прежними', () async {
      final h = await loadedHome();

      await confirmMarkC(h, revision: 2);
      // В ещё не показано, но его счётчики изменились во время чтения.
      await confirmRenameX(h, revision: 3, activeRelationCounts: {3: 2});
      h.repository.completeRead(
        1,
        items: [homeTestRow(1, 'А'), homeTestRow(2, 'Б'), homeTestRow(3, 'В')],
        revision: 2,
      );
      await pumpEventQueue();

      expectRefreshingAB(h);
      expect(h.repository.readCount, 3);

      h.repository.completeRead(
        2,
        items: [
          homeTestRow(1, 'А'),
          homeTestRow(2, 'Б'),
          homeTestRow(3, 'В', activeRelationCount: 2),
        ],
        revision: 3,
      );
      await pumpEventQueue();

      expect(ids(h), [a, b, c]);
      expect((h.state as HomeList).items.last.activeRelationCount, 2);
      expect(h.repository.readCount, 3);
    });

    test('пакет без избранного во время чтения лишнего чтения не '
        'вызывает', () async {
      final h = await loadedHome();

      await confirmMarkC(h, revision: 2);
      await confirmRenameX(h, revision: 3, activeRelationCounts: {9: 2});
      h.repository.completeRead(
        1,
        items: [homeTestRow(1, 'А'), homeTestRow(2, 'Б'), homeTestRow(3, 'В')],
        revision: 2,
      );
      await pumpEventQueue();

      expect(ids(h), [a, b, c]);
      expect((h.state as HomeList).freshness, isA<HomeFreshnessCurrent>());
      expect(h.repository.readCount, 2);
    });
  });

  group('отказ обновления сохраняет прежнее состояние неактуальным', () {
    const failures = <(String, FavoriteIntentionsReadFailure, bool)>[
      ('недоступность', FavoriteIntentionsUnavailableFailure(), true),
      ('повреждение', FavoriteIntentionsCorruptionFailure(), false),
      ('неизвестный отказ', FavoriteIntentionsUnexpectedFailure(), false),
    ];
    for (final (name, failure, canRetry) in failures) {
      test('$name оставляет прежний список с причиной', () async {
        final h = await loadedHome();

        await confirmMarkC(h, revision: 2);
        h.repository.failRead(1, failure);
        await pumpEventQueue();

        final list = h.state as HomeList;
        expect(list.items.map((row) => row.id), [a, b]);
        expect((list.revision as HomeTestRevision).number, 1);
        final stale = list.freshness as HomeFreshnessStale;
        expect(stale.failure.runtimeType, failure.runtimeType);
        expect(stale.canRetry, canRetry);
        expect(h.repository.readCount, 2);
      });
    }

    test('исключение границы оставляет прежний список с неизвестным '
        'отказом', () async {
      final h = await loadedHome();

      await confirmMarkC(h, revision: 2);
      h.repository.throwFromRead(1, StateError('сбой'));
      await pumpEventQueue();

      final stale = (h.state as HomeList).freshness as HomeFreshnessStale;
      expect(stale.failure, isA<FavoriteIntentionsUnexpectedFailure>());
      expect(ids(h), [a, b]);
    });

    test('пустое состояние остаётся с прежней причиной и пометкой', () async {
      final h = HomeHarness();
      addTearDown(h.dispose);
      h.repository.completeRead(0, archivedCount: 2);
      await pumpEventQueue();

      await confirmMarkC(h, revision: 2);
      h.repository.failRead(1, const FavoriteIntentionsUnavailableFailure());
      await pumpEventQueue();

      final empty = h.state as HomeEmpty;
      expect(empty.reason, HomeEmptyReason.allArchived);
      expect(empty.freshness, isA<HomeFreshnessStale>());
    });

    test('явный повтор при недоступности возвращает текущую актуальность и '
        'убирает причину', () async {
      final h = await loadedHome();
      await confirmMarkC(h, revision: 2);
      h.repository.failRead(1, const FavoriteIntentionsUnavailableFailure());
      await pumpEventQueue();

      h.model.retry();

      expectRefreshingAB(h);
      expect(h.repository.readCount, 3);

      h.repository.completeRead(
        2,
        items: [homeTestRow(1, 'А'), homeTestRow(2, 'Б'), homeTestRow(3, 'В')],
        revision: 2,
      );
      await pumpEventQueue();

      expect(ids(h), [a, b, c]);
      expect((h.state as HomeList).freshness, isA<HomeFreshnessCurrent>());
    });

    test('повтор не публикует снимок старше ревизии отказавшего '
        'обновления', () async {
      final h = await loadedHome();
      await confirmMarkC(h, revision: 2);
      h.repository.failRead(1, const FavoriteIntentionsUnavailableFailure());
      await pumpEventQueue();

      h.model.retry();
      h.repository.completeRead(2, items: [homeTestRow(1, 'А')], revision: 1);
      await pumpEventQueue();

      expectRefreshingAB(h);
      expect(h.repository.readCount, 4);
    });

    test('повторный отказ явного повтора сохраняет пометку', () async {
      final h = await loadedHome();
      await confirmMarkC(h, revision: 2);
      h.repository.failRead(1, const FavoriteIntentionsUnavailableFailure());
      await pumpEventQueue();

      h.model.retry();
      h.repository.failRead(2, const FavoriteIntentionsCorruptionFailure());
      await pumpEventQueue();

      final stale = (h.state as HomeList).freshness as HomeFreshnessStale;
      expect(stale.failure, isA<FavoriteIntentionsCorruptionFailure>());
      expect(ids(h), [a, b]);
    });

    test('при повреждении и неизвестном отказе явный повтор чтения не '
        'запускает', () async {
      for (final failure in <FavoriteIntentionsReadFailure>[
        const FavoriteIntentionsCorruptionFailure(),
        const FavoriteIntentionsUnexpectedFailure(),
      ]) {
        final h = await loadedHome();
        await confirmMarkC(h, revision: 2);
        h.repository.failRead(1, failure);
        await pumpEventQueue();
        final before = h.state;

        h.model.retry();
        await pumpEventQueue();

        expect(h.state, same(before));
        expect(h.repository.readCount, 2);
      }
    });

    test('следующий пакет с изменением избранного повторяет обновление и '
        'восстанавливает актуальность', () async {
      final h = await loadedHome();
      await confirmMarkC(h, revision: 2);
      h.repository.failRead(1, const FavoriteIntentionsCorruptionFailure());
      await pumpEventQueue();

      await h.confirm(
        UpdateIntention(id: a, title: 'Альфа', description: null),
        revision: 3,
        before: homeTestSummary(1, 'А'),
        after: homeTestSummary(1, 'Альфа'),
      );

      expectRefreshingAB(h);
      expect(h.repository.readCount, 3);

      h.repository.completeRead(
        2,
        items: [
          homeTestRow(1, 'Альфа'),
          homeTestRow(2, 'Б'),
          homeTestRow(3, 'В'),
        ],
        revision: 3,
      );
      await pumpEventQueue();

      expect(ids(h), [a, b, c]);
      expect((h.state as HomeList).freshness, isA<HomeFreshnessCurrent>());
    });
  });

  group('неактуальное состояние восстанавливается любым следующим пакетом', () {
    const failures = <(String, FavoriteIntentionsReadFailure)>[
      ('недоступности', FavoriteIntentionsUnavailableFailure()),
      ('повреждения', FavoriteIntentionsCorruptionFailure()),
      ('неизвестного отказа', FavoriteIntentionsUnexpectedFailure()),
    ];

    /// Список А, Б ревизии 1, обновление которого после отметки В на ревизии
    /// 2 завершилось отказом [failure].
    Future<HomeHarness> staleHome(FavoriteIntentionsReadFailure failure) async {
      final h = await loadedHome();
      await confirmMarkC(h, revision: 2);
      h.repository.failRead(1, failure);
      await pumpEventQueue();
      expect((h.state as HomeList).freshness, isA<HomeFreshnessStale>());
      expect(h.repository.readCount, 2);
      return h;
    }

    final abc = [homeTestRow(1, 'А'), homeTestRow(2, 'Б'), homeTestRow(3, 'В')];

    for (final (name, failure) in failures) {
      test('пакет, не затрагивающий избранное, после $name вызывает чтение и '
          'возвращает текущую актуальность', () async {
        final h = await staleHome(failure);

        await confirmRenameX(h, revision: 3);

        expectRefreshingAB(h);
        expect(h.repository.readCount, 3);

        h.repository.completeRead(2, items: abc, revision: 3);
        await pumpEventQueue();

        expect(ids(h), [a, b, c]);
        final list = h.state as HomeList;
        expect(list.freshness, isA<HomeFreshnessCurrent>());
        expect((list.revision as HomeTestRevision).number, 3);
        expect(h.repository.readCount, 3);
      });
    }

    test('пакет, не затрагивающий избранное, при неактуальном пустом '
        'состоянии вызывает чтение', () async {
      final h = HomeHarness();
      addTearDown(h.dispose);
      h.repository.completeRead(0, archivedCount: 2);
      await pumpEventQueue();
      await confirmMarkC(h, revision: 2);
      h.repository.failRead(1, const FavoriteIntentionsCorruptionFailure());
      await pumpEventQueue();
      expect((h.state as HomeEmpty).freshness, isA<HomeFreshnessStale>());

      await confirmRenameX(h, revision: 3);

      final refreshing = h.state as HomeEmpty;
      expect(refreshing.reason, HomeEmptyReason.allArchived);
      expect(refreshing.freshness, isA<HomeFreshnessRefreshing>());
      expect(h.repository.readCount, 3);

      h.repository.completeRead(
        2,
        items: [homeTestRow(3, 'В')],
        archivedCount: 2,
        revision: 3,
      );
      await pumpEventQueue();

      expect(ids(h), [c]);
      expect((h.state as HomeList).freshness, isA<HomeFreshnessCurrent>());
    });

    test('снимок старше ревизии вызвавшего чтение пакета не '
        'публикуется', () async {
      final h = await staleHome(const FavoriteIntentionsCorruptionFailure());

      await confirmRenameX(h, revision: 3);
      h.repository.completeRead(2, items: abc, revision: 2);
      await pumpEventQueue();

      expectRefreshingAB(h);
      expect(h.repository.readCount, 4);

      h.repository.completeRead(3, items: abc, revision: 3);
      await pumpEventQueue();

      expect(ids(h), [a, b, c]);
      expect((h.state as HomeList).freshness, isA<HomeFreshnessCurrent>());
      expect(h.repository.readCount, 4);
    });

    test('повторный отказ сохраняет прежний список с причиной последнего '
        'отказа, а следующий пакет снова повторяет обновление', () async {
      final h = await staleHome(const FavoriteIntentionsUnavailableFailure());

      await confirmRenameX(h, revision: 3);
      h.repository.failRead(2, const FavoriteIntentionsCorruptionFailure());
      await pumpEventQueue();

      final list = h.state as HomeList;
      expect(list.items.map((row) => row.id), [a, b]);
      expect((list.revision as HomeTestRevision).number, 1);
      final stale = list.freshness as HomeFreshnessStale;
      expect(stale.failure, isA<FavoriteIntentionsCorruptionFailure>());
      expect(stale.canRetry, isFalse);
      // Без нового пакета и явного повтора чтение не повторяется.
      expect(h.repository.readCount, 3);

      await confirmRenameX(h, revision: 4);

      expectRefreshingAB(h);
      expect(h.repository.readCount, 4);

      h.repository.completeRead(3, items: abc, revision: 4);
      await pumpEventQueue();

      expect(ids(h), [a, b, c]);
      expect((h.state as HomeList).freshness, isA<HomeFreshnessCurrent>());
    });

    test('пакет во время повторного чтения не запускает параллельного и '
        'после его неуспеха даёт ещё одно', () async {
      final h = await staleHome(const FavoriteIntentionsUnexpectedFailure());

      await confirmRenameX(h, revision: 3);
      expect(h.repository.readCount, 3);
      await confirmRenameX(h, revision: 4);

      expectRefreshingAB(h);
      expect(h.repository.readCount, 3);

      h.repository.failRead(2, const FavoriteIntentionsUnavailableFailure());
      await pumpEventQueue();

      // Отказ чтения, начатого до пакета ревизии 4, не публикуется.
      expectRefreshingAB(h);
      expect(h.repository.readCount, 4);

      h.repository.completeRead(3, items: abc, revision: 4);
      await pumpEventQueue();

      expect(ids(h), [a, b, c]);
      expect((h.state as HomeList).freshness, isA<HomeFreshnessCurrent>());
      expect(h.repository.readCount, 4);
    });

    test('пакет во время явного повтора неактуального списка после его '
        'неуспеха даёт ещё одно чтение', () async {
      final h = await staleHome(const FavoriteIntentionsUnavailableFailure());

      h.model.retry();
      expect(h.repository.readCount, 3);
      await confirmRenameX(h, revision: 3);
      expect(h.repository.readCount, 3);

      h.repository.failRead(2, const FavoriteIntentionsUnavailableFailure());
      await pumpEventQueue();

      expectRefreshingAB(h);
      expect(h.repository.readCount, 4);
    });

    test('после восстановления актуальности пакет, не затрагивающий '
        'избранное, чтения не вызывает', () async {
      final h = await staleHome(const FavoriteIntentionsCorruptionFailure());
      await confirmRenameX(h, revision: 3);
      h.repository.completeRead(2, items: abc, revision: 3);
      await pumpEventQueue();
      final restored = h.state;
      expect((restored as HomeList).freshness, isA<HomeFreshnessCurrent>());

      await confirmRenameX(h, revision: 4);

      expect(h.state, same(restored));
      expect(h.repository.readCount, 3);
    });

    test('после восстановления явным повтором пакет, не затрагивающий '
        'избранное, чтения не вызывает', () async {
      final h = await staleHome(const FavoriteIntentionsUnavailableFailure());
      h.model.retry();
      h.repository.completeRead(2, items: abc, revision: 2);
      await pumpEventQueue();
      final restored = h.state;
      expect((restored as HomeList).freshness, isA<HomeFreshnessCurrent>());

      await confirmRenameX(h, revision: 3);

      expect(h.state, same(restored));
      expect(h.repository.readCount, 3);
    });
  });

  group('полное создание намерения согласуется по отметке окончательного '
      'снимка', () {
    /// Окончательный снимок намерения 3 «В», созданного готовым к действию,
    /// с двумя тегами и отметкой [favoriteMark].
    IntentionSummary createdC({
      FavoriteMark favoriteMark = FavoriteMark.favorite,
    }) => homeTestSummary(
      3,
      'В',
      favoriteMark: favoriteMark,
      readiness: IntentionReadiness.ready,
      tags: [homeTestTag(1, 'Дом'), homeTestTag(2, 'Выходные')],
    );

    final rowA = homeTestRow(1, 'А');
    final rowB = homeTestRow(2, 'Б');
    final rowC = homeTestRow(3, 'В', readiness: IntentionReadiness.ready);

    /// Главная со списком А, Б на ревизии 1: единый порядок А, архивированное
    /// Д, Б, и архивированное место Главная не показывает.
    Future<HomeHarness> loadedWithArchived() async {
      final h = HomeHarness();
      addTearDown(h.dispose);
      h.repository.completeRead(0, items: [rowA, rowB], archivedCount: 1);
      await pumpEventQueue();
      expect(ids(h), [a, b]);
      return h;
    }

    void expectCurrentABC(HomeHarness h, {required int revision}) {
      final list = h.state as HomeList;
      expect(list.items, [rowA, rowB, rowC]);
      expect(list.freshness, isA<HomeFreshnessCurrent>());
      expect((list.revision as HomeTestRevision).number, revision);
      expect(list.reorder, isA<HomeReorderIdle>());
    }

    test('созданное избранным намерение встаёт последним, а прежние '
        'сохраняют взаимный порядок', () async {
      final h = await loadedWithArchived();

      await h.create(createdC(), revision: 2);

      // Главная согласуется самим пакетом создания: без отдельной команды
      // отметки и без поверхности сообщений, которой в контейнере нет.
      expect(h.repository.commands, [isA<CreateIntention>()]);
      expectRefreshingAB(h);
      expect(h.repository.readCount, 2);

      h.repository.completeRead(
        1,
        items: [rowA, rowB, rowC],
        archivedCount: 1,
        revision: 2,
      );
      await pumpEventQueue();

      expectCurrentABC(h, revision: 2);
      expect(
        (h.state as HomeList).items.last.readiness,
        IntentionReadiness.ready,
      );
      expect(h.repository.readCount, 2);
      expect(h.repository.commands, hasLength(1));
    });

    test('созданное без отметки намерение Главную не меняет и чтения не '
        'вызывает', () async {
      final h = await loadedWithArchived();
      final before = h.state;

      await h.create(
        createdC(favoriteMark: FavoriteMark.notFavorite),
        revision: 2,
      );

      expect(h.state, same(before));
      expect(h.repository.readCount, 1);
      expect(h.repository.commands, [isA<CreateIntention>()]);
    });

    for (final (reason, archivedCount) in const [
      (HomeEmptyReason.noFavorites, 0),
      (HomeEmptyReason.allArchived, 1),
    ]) {
      test('пустая Главная (${reason.name}) показывает созданное избранным '
          'намерение', () async {
        final h = HomeHarness();
        addTearDown(h.dispose);
        h.repository.completeRead(0, archivedCount: archivedCount);
        await pumpEventQueue();
        expect((h.state as HomeEmpty).reason, reason);

        await h.create(createdC(), revision: 2);

        final refreshing = h.state as HomeEmpty;
        expect(refreshing.reason, reason);
        expect(refreshing.freshness, isA<HomeFreshnessRefreshing>());
        expect(h.repository.readCount, 2);

        h.repository.completeRead(
          1,
          items: [rowC],
          archivedCount: archivedCount,
          revision: 2,
        );
        await pumpEventQueue();

        expect((h.state as HomeList).items, [rowC]);
        expect((h.state as HomeList).freshness, isA<HomeFreshnessCurrent>());
      });
    }

    test('снимок старше ревизии создания не публикуется и '
        'перечитывается', () async {
      final h = await loadedWithArchived();

      await h.create(createdC(), revision: 2);
      // Чтение обогнало подтверждение создания и вернуло прежний состав.
      h.repository.completeRead(
        1,
        items: [rowA, rowB],
        archivedCount: 1,
        revision: 1,
      );
      await pumpEventQueue();

      expectRefreshingAB(h);
      expect(h.repository.readCount, 3);

      h.repository.completeRead(
        2,
        items: [rowA, rowB, rowC],
        archivedCount: 1,
        revision: 2,
      );
      await pumpEventQueue();

      expectCurrentABC(h, revision: 2);
      expect(h.repository.readCount, 3);
    });

    test('чтение, начатое до создания и завершённое после него, не '
        'публикует прежний состав', () async {
      final h = await loadedWithArchived();

      // Чтение вызвано переименованием А, а пакет создания приходит, пока
      // оно выполняется.
      await h.confirm(
        UpdateIntention(id: a, title: 'Альфа', description: null),
        revision: 2,
        before: homeTestSummary(1, 'А'),
        after: homeTestSummary(1, 'Альфа'),
      );
      await h.create(createdC(), revision: 3);
      expect(h.repository.readCount, 2);

      h.repository.completeRead(
        1,
        items: [homeTestRow(1, 'Альфа'), rowB],
        archivedCount: 1,
        revision: 2,
      );
      await pumpEventQueue();

      expectRefreshingAB(h);
      expect(h.repository.readCount, 3);

      h.repository.completeRead(
        2,
        items: [homeTestRow(1, 'Альфа'), rowB, rowC],
        archivedCount: 1,
        revision: 3,
      );
      await pumpEventQueue();

      expect(ids(h), [a, b, c]);
      expect((h.state as HomeList).items.first.title, 'Альфа');
      expect((h.state as HomeList).freshness, isA<HomeFreshnessCurrent>());
      expect(h.repository.readCount, 3);
    });

    test('первоначальное чтение, начатое до создания, не публикует прежний '
        'состав', () async {
      final h = HomeHarness();
      addTearDown(h.dispose);

      await h.create(createdC(), revision: 5);
      expect(h.repository.readCount, 1);

      h.repository.completeRead(
        0,
        items: [rowA, rowB],
        archivedCount: 1,
        revision: 4,
      );
      await pumpEventQueue();

      expect(h.state, isA<HomeLoading>());
      expect(h.repository.readCount, 2);

      h.repository.completeRead(
        1,
        items: [rowA, rowB, rowC],
        archivedCount: 1,
        revision: 5,
      );
      await pumpEventQueue();

      expectCurrentABC(h, revision: 5);
    });

    test('повторная доставка уже отражённого пакета создания чтения не '
        'вызывает и состав не меняет', () async {
      final h = await loadedWithArchived();
      await h.create(createdC(), revision: 2);
      h.repository.completeRead(
        1,
        items: [rowA, rowB, rowC],
        archivedCount: 1,
        revision: 2,
      );
      await pumpEventQueue();
      final reconciled = h.state;

      await h.create(createdC(), revision: 2);

      expect(h.state, same(reconciled));
      expect(h.repository.readCount, 2);
    });

    test('повторная доставка пакета создания во время чтения не запускает '
        'параллельного и лишнего чтения', () async {
      final h = await loadedWithArchived();

      await h.create(createdC(), revision: 2);
      await h.create(createdC(), revision: 2);
      expectRefreshingAB(h);
      expect(h.repository.readCount, 2);

      h.repository.completeRead(
        1,
        items: [rowA, rowB, rowC],
        archivedCount: 1,
        revision: 2,
      );
      await pumpEventQueue();

      expectCurrentABC(h, revision: 2);
      expect(h.repository.readCount, 2);
    });
  });

  test('после закрытия Главной пакет чтения не запускает', () async {
    final h = HomeHarness();
    h.repository.completeRead(0, items: [homeTestRow(1, 'А')]);
    await pumpEventQueue();
    final repository = h.repository;
    h.subscription.close();
    await pumpEventQueue();

    await confirmMarkC(h, revision: 2);

    expect(repository.readCount, 1);
    h.dispose();
  });
}
