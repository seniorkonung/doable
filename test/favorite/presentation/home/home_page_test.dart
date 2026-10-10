import 'package:auto_route/auto_route.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/favorite/application/favorite_intentions.dart';
import 'package:doable/src/favorite/presentation/home/home_page.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'home_test_support.dart';

/// Страница Главной над управляемым чтением избранного.
///
/// Маршрутизатор теста знает только Главную и два маршрута назначения:
/// страницы намерения и каталога намерений заменены пустыми.
void main() {
  group('полученный список', () {
    testWidgets('из 150 строк доступен целиком без получения продолжения', (
      tester,
    ) async {
      final h = await _pumpHome(tester);
      h.repository.completeRead(
        0,
        items: [for (var i = 1; i <= 150; i++) homeTestRow(i, 'Намерение $i')],
      );
      await tester.pumpAndSettle();

      expect(find.text('Намерение 1'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Намерение 150'),
        600,
        scrollable: _listScrollable,
        maxScrolls: 400,
      );
      await tester.pumpAndSettle();

      expect(find.text('Намерение 150'), findsOneWidget);
    });
  });

  group('отказ обновления', () {
    testWidgets('прежнее пустое состояние остаётся с пометкой, что оно не '
        'обновлено', (tester) async {
      final h = await _pumpHome(tester);
      h.repository.completeRead(0);
      await tester.pumpAndSettle();
      await _confirmMark(tester, h, revision: 2);
      h.repository.failRead(1, const FavoriteIntentionsUnavailableFailure());
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Список избранных намерений не обновлён: не удалось получить '
          'изменения.',
        ),
        findsOneWidget,
      );
      expect(find.text('Повторить'), findsOneWidget);
      expect(find.textContaining('пока нет'), findsOneWidget);
      expect(find.text('Открыть граф намерений'), findsOneWidget);
    });
  });

  group('обновление списка', () {
    Future<HomeHarnessWithRouter> pumpScrolledHome(WidgetTester tester) async {
      final h = await _pumpHome(tester);
      h.repository.completeRead(0, items: _manyRows());
      await tester.pumpAndSettle();
      await tester.drag(_listScrollable, const Offset(0, -1500));
      await tester.pumpAndSettle();
      expect(_scrollOffset(tester), greaterThan(0));
      return h;
    }

    testWidgets('не сбрасывает позицию прокрутки', (tester) async {
      final h = await pumpScrolledHome(tester);
      final offset = _scrollOffset(tester);

      await _confirmMark(tester, h, revision: 2, number: 99);
      await tester.pump();
      expect(_scrollOffset(tester), offset);
      h.repository.completeRead(
        1,
        items: [..._manyRows(), homeTestRow(99, 'Новое')],
        revision: 2,
      );
      await tester.pumpAndSettle();

      expect(_scrollOffset(tester), offset);
    });

    testWidgets('при отказе и после успешного повтора не сбрасывает позицию '
        'прокрутки', (tester) async {
      final h = await pumpScrolledHome(tester);
      final offset = _scrollOffset(tester);

      await _confirmMark(tester, h, revision: 2, number: 99);
      h.repository.failRead(1, const FavoriteIntentionsUnavailableFailure());
      await tester.pumpAndSettle();
      expect(_scrollOffset(tester), offset);

      await tester.tap(find.text('Повторить'));
      h.repository.completeRead(2, items: _manyRows(), revision: 2);
      await tester.pumpAndSettle();
      expect(_scrollOffset(tester), offset);
    });
  });

  group('заголовок и локализация', () {
    testWidgets('заголовок страницы — название пункта «Главная»', (
      tester,
    ) async {
      await _pumpHome(tester);

      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Главная'),
        ),
        findsOneWidget,
      );
    });
  });
}

typedef HomeHarnessWithRouter = ({
  HomeTestRepository repository,
  HomeHarness harness,
  _TestRouter router,
});

/// Маршрутизатор с Главной и пустыми страницами назначения её переходов.
final class _TestRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: HomeRoute.page, initial: true),
    AutoRoute(
      page: PageInfo(
        IntentionDetailsRoute.name,
        builder: (_) => const SizedBox.shrink(),
      ),
    ),
    AutoRoute(
      page: PageInfo(
        IntentionCatalogRoute.name,
        builder: (_) => const SizedBox.shrink(),
      ),
    ),
  ];
}

Future<HomeHarnessWithRouter> _pumpHome(WidgetTester tester) async {
  final harness = HomeHarness();
  addTearDown(harness.dispose);
  final router = _TestRouter();
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: harness.container,
      child: MaterialApp.router(
        routerConfig: router.config(),
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pump();
  expect(find.byType(HomePage), findsOneWidget);
  return (repository: harness.repository, harness: harness, router: router);
}

/// Подтверждённая отметка намерения [number] на ревизии [revision]: пакет
/// требует обновления списка.
///
/// Координатор завершает команду в настоящем цикле событий, поэтому она
/// проводится вне поддельного времени теста.
Future<void> _confirmMark(
  WidgetTester tester,
  HomeHarnessWithRouter h, {
  required int revision,
  int number = 3,
}) => tester.runAsync(
  () => h.harness.confirm(
    MarkIntentionFavorite(homeTestIntentionId(number)),
    revision: revision,
    before: homeTestSummary(
      number,
      'Плавать',
      favoriteMark: FavoriteMark.notFavorite,
    ),
    after: homeTestSummary(number, 'Плавать'),
  ),
);

List<FavoriteIntentionRow> _manyRows() => [
  for (var i = 1; i <= 40; i++) homeTestRow(i, 'Намерение $i'),
];

/// Прокрутка списка избранных намерений, а не места пометки над ним.
final _listScrollable = find.descendant(
  of: find.byType(CustomScrollView),
  matching: find.byType(Scrollable),
);

double _scrollOffset(WidgetTester tester) =>
    tester.state<ScrollableState>(_listScrollable).position.pixels;
