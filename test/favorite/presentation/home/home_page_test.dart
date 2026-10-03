import 'package:auto_route/auto_route.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/favorite/application/favorite_intentions.dart';
import 'package:doable/src/favorite/presentation/home/home_page.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/presentation/intention_summary_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'home_test_support.dart';

/// Страница Главной над управляемым чтением избранного.
///
/// Маршрутизатор теста знает только Главную и два маршрута назначения:
/// страницы намерения и каталога намерений заменены пустыми, поэтому
/// проверяется сам переход и его аргументы.
void main() {
  group('полученный список', () {
    testWidgets('называется избранными намерениями и идёт в порядке снимка', (
      tester,
    ) async {
      final h = await _pumpHome(tester);
      h.repository.completeRead(
        0,
        items: [
          homeTestRow(3, 'Плавать'),
          homeTestRow(1, 'Читать'),
          homeTestRow(2, 'Гулять'),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.text('Избранные намерения'), findsOneWidget);
      final rows = tester
          .widgetList<IntentionSummaryView>(find.byType(IntentionSummaryView))
          .map((row) => row.title);
      expect(rows, ['Плавать', 'Читать', 'Гулять']);
      expect(
        tester.getTopLeft(find.text('Плавать')).dy,
        lessThan(tester.getTopLeft(find.text('Читать')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Читать')).dy,
        lessThan(tester.getTopLeft(find.text('Гулять')).dy),
      );
    });

    testWidgets('строка показывает название, готовность и число активных '
        'связей без звезды, тегов, описания и архивного состояния', (
      tester,
    ) async {
      final h = await _pumpHome(tester);
      h.repository.completeRead(
        0,
        items: [
          homeTestRow(
            1,
            'Быть Здоровым',
            readiness: IntentionReadiness.ready,
            activeRelationCount: 3,
          ),
          homeTestRow(2, 'Гулять'),
        ],
      );
      await tester.pumpAndSettle();

      final first = find.byKey(ValueKey(homeTestIntentionId(1)));
      Finder inFirst(Finder finder) =>
          find.descendant(of: first, matching: finder);
      expect(inFirst(find.text('Быть Здоровым')), findsOneWidget);
      expect(inFirst(find.text('Готово к действию')), findsOneWidget);
      expect(inFirst(find.text('Активных связей: 3')), findsOneWidget);
      final second = find.byKey(ValueKey(homeTestIntentionId(2)));
      expect(
        find.descendant(
          of: second,
          matching: find.text('Не готово к действию'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: second, matching: find.text('Активных связей: 0')),
        findsOneWidget,
      );

      final view = tester.widget<IntentionSummaryView>(
        inFirst(find.byType(IntentionSummaryView)),
      );
      expect(view.confirmedFavoriteMark, isNull);
      expect(view.confirmedTags, isNull);
      expect(view.showArchiveState, isFalse);
      expect(view.traits, ['Готово к действию']);
      expect(find.byIcon(Icons.star), findsNothing);
      expect(find.text('Активно'), findsNothing);
      expect(find.text('Есть описание'), findsNothing);
      expect(find.text('Нет описания'), findsNothing);
    });

    testWidgets('не предлагает снятие отметки', (tester) async {
      final h = await _pumpHome(tester);
      h.repository.completeRead(
        0,
        items: [homeTestRow(1, 'Читать'), homeTestRow(2, 'Гулять')],
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.star), findsNothing);
      expect(find.byType(IconButton), findsNothing);
      expect(find.byType(Dismissible), findsNothing);
    });

    testWidgets('одноимённые намерения остаются отдельными строками, а '
        'нажатие открывает страницу именно этого намерения', (tester) async {
      final h = await _pumpHome(tester);
      h.repository.completeRead(
        0,
        items: [homeTestRow(1, 'Гулять'), homeTestRow(2, 'Гулять')],
      );
      await tester.pumpAndSettle();

      expect(find.text('Гулять'), findsNWidgets(2));
      await tester.tap(find.byKey(ValueKey(homeTestIntentionId(2))));
      await tester.pumpAndSettle();

      expect(h.router.current.name, IntentionDetailsRoute.name);
      expect(
        h.router.current.argsAs<IntentionDetailsRouteArgs>().intentionId,
        homeTestIntentionId(2),
      );
    });

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
      expect(h.repository.readCount, 1);
    });
  });

  group('загрузка и пустые состояния', () {
    testWidgets('загрузка не выглядит пустой Главной или отказом', (
      tester,
    ) async {
      await _pumpHome(tester);

      expect(find.text('Загружаем избранные намерения…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.textContaining('пока нет'), findsNothing);
      expect(find.text('Избранные намерения'), findsNothing);
      expect(find.text('Повторить'), findsNothing);
      expect(find.text('Открыть граф намерений'), findsNothing);
    });

    testWidgets('без избранных намерений объясняет, что намерение отмечается '
        'на его странице', (tester) async {
      final h = await _pumpHome(tester);
      h.repository.completeRead(0);
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Избранных намерений пока нет. Чтобы добавить намерение сюда, '
          'отметьте его избранным на его странице.',
        ),
        findsOneWidget,
      );
      expect(find.text('Открыть граф намерений'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Повторить'), findsNothing);
    });

    testWidgets('со всеми избранными в архиве не утверждает, что избранных '
        'намерений нет', (tester) async {
      final h = await _pumpHome(tester);
      h.repository.completeRead(0, archivedCount: 2);
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Все избранные намерения в архиве. Намерение, восстановленное из '
          'архива, вернётся сюда на своё место.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('пока нет'), findsNothing);
      expect(find.text('Открыть граф намерений'), findsOneWidget);
    });

    for (final archivedCount in [0, 1]) {
      testWidgets('пустое состояние с числом архивированных избранных '
          '$archivedCount ведёт к каталогу намерений', (tester) async {
        final h = await _pumpHome(tester);
        h.repository.completeRead(0, archivedCount: archivedCount);
        await tester.pumpAndSettle();

        await tester.tap(find.text('Открыть граф намерений'));
        await tester.pumpAndSettle();

        expect(h.router.current.name, IntentionCatalogRoute.name);
      });
    }
  });

  group('отказ первоначального получения', () {
    testWidgets('недоступность показывает повтор, а успешный повтор — '
        'актуальный список без прежнего сообщения', (tester) async {
      final h = await _pumpHome(tester);
      h.repository.failRead(0, const FavoriteIntentionsUnavailableFailure());
      await tester.pumpAndSettle();

      const message =
          'Не удалось загрузить избранные намерения. Повторите попытку.';
      expect(find.text(message), findsOneWidget);
      expect(find.textContaining('пока нет'), findsNothing);
      expect(find.text('Открыть граф намерений'), findsNothing);

      await tester.tap(find.text('Повторить'));
      await tester.pump();
      expect(find.text('Загружаем избранные намерения…'), findsOneWidget);
      expect(h.repository.readCount, 2);

      h.repository.completeRead(1, items: [homeTestRow(1, 'Читать')]);
      await tester.pumpAndSettle();
      expect(find.text('Читать'), findsOneWidget);
      expect(find.text(message), findsNothing);
      expect(find.text('Повторить'), findsNothing);
    });

    for (final (failure, message) in [
      (
        const FavoriteIntentionsCorruptionFailure(),
        'Сохранённые данные избранных намерений повреждены и не могут быть '
            'показаны.',
      ),
      (
        const FavoriteIntentionsUnexpectedFailure(),
        'Не удалось загрузить избранные намерения из-за непредвиденной ошибки.',
      ),
    ]) {
      testWidgets('${failure.category.name} — отдельный неповторяемый '
          'результат без обычного повтора', (tester) async {
        final h = await _pumpHome(tester);
        h.repository.failRead(0, failure);
        await tester.pumpAndSettle();

        expect(find.text(message), findsOneWidget);
        expect(find.text('Повторить'), findsNothing);
        expect(find.byType(FilledButton), findsNothing);
        expect(find.textContaining('пока нет'), findsNothing);
        expect(find.text('Открыть граф намерений'), findsNothing);
        expect(h.repository.readCount, 1);
      });
    }
  });

  group('отказ обновления', () {
    testWidgets('недоступность оставляет прежний список с пометкой и '
        'повтором, а успешное получение убирает пометку', (tester) async {
      final h = await _pumpLoadedHome(tester);
      await _confirmMark(tester, h, revision: 2);
      h.repository.failRead(1, const FavoriteIntentionsUnavailableFailure());
      await tester.pumpAndSettle();

      const mark =
          'Список избранных намерений не обновлён: не удалось получить '
          'изменения.';
      expect(find.text(mark), findsOneWidget);
      expect(find.text('Читать'), findsOneWidget);
      expect(find.text('Гулять'), findsOneWidget);

      await tester.tap(find.text('Повторить'));
      await tester.pump();
      expect(find.text('Читать'), findsOneWidget);
      h.repository.completeRead(
        2,
        items: [
          homeTestRow(1, 'Читать'),
          homeTestRow(2, 'Гулять'),
          homeTestRow(3, 'Плавать'),
        ],
        revision: 2,
      );
      await tester.pumpAndSettle();

      expect(find.text(mark), findsNothing);
      expect(find.text('Повторить'), findsNothing);
      expect(find.text('Плавать'), findsOneWidget);
    });

    for (final (failure, mark) in [
      (
        const FavoriteIntentionsCorruptionFailure(),
        'Список избранных намерений не обновлён: сохранённые данные '
            'повреждены.',
      ),
      (
        const FavoriteIntentionsUnexpectedFailure(),
        'Список избранных намерений не обновлён из-за непредвиденной ошибки.',
      ),
    ]) {
      testWidgets('${failure.category.name} оставляет прежний список с '
          'пометкой без повтора', (tester) async {
        final h = await _pumpLoadedHome(tester);
        await _confirmMark(tester, h, revision: 2);
        h.repository.failRead(1, failure);
        await tester.pumpAndSettle();

        expect(find.text(mark), findsOneWidget);
        expect(find.text('Повторить'), findsNothing);
        expect(find.text('Читать'), findsOneWidget);
        expect(find.text('Гулять'), findsOneWidget);
      });
    }

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

    testWidgets('английский интерфейс показывает английские строки списка', (
      tester,
    ) async {
      final h = await _pumpHome(tester, locale: 'en');
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('Home')),
        findsOneWidget,
      );
      expect(find.text('Loading favorite intentions…'), findsOneWidget);

      h.repository.completeRead(
        0,
        items: [homeTestRow(1, 'Читать', activeRelationCount: 2)],
      );
      await tester.pumpAndSettle();
      expect(find.text('Favorite intentions'), findsOneWidget);
      expect(find.text('Читать'), findsOneWidget);
      expect(find.text('Not ready for action'), findsOneWidget);
      expect(find.text('Active relations: 2'), findsOneWidget);

      await _confirmMark(tester, h, revision: 2);
      h.repository.failRead(1, const FavoriteIntentionsUnavailableFailure());
      await tester.pumpAndSettle();
      expect(
        find.text(
          'The favorite intention list isn’t up to date: changes couldn’t be '
          'loaded.',
        ),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsOneWidget);
    });

    for (final (archivedCount, message) in [
      (
        0,
        'There are no favorite intentions yet. To add an intention here, '
            'mark it as a favorite on its page.',
      ),
      (
        1,
        'All favorite intentions are archived. An intention restored from '
            'the archive returns here to its place.',
      ),
    ]) {
      testWidgets('английское пустое состояние с числом архивированных '
          'избранных $archivedCount', (tester) async {
        final h = await _pumpHome(tester, locale: 'en');
        h.repository.completeRead(0, archivedCount: archivedCount);
        await tester.pumpAndSettle();

        expect(find.text(message), findsOneWidget);
        expect(find.text('Open intention graph'), findsOneWidget);
      });
    }

    for (final (failure, message, mark) in [
      (
        const FavoriteIntentionsUnavailableFailure(),
        'Favorite intentions couldn’t be loaded. Try again.',
        'The favorite intention list isn’t up to date: changes couldn’t be '
            'loaded.',
      ),
      (
        const FavoriteIntentionsCorruptionFailure(),
        'Stored favorite intention data is damaged and can’t be shown.',
        'The favorite intention list isn’t up to date: stored data is '
            'damaged.',
      ),
      (
        const FavoriteIntentionsUnexpectedFailure(),
        'Favorite intentions couldn’t be loaded because of an unexpected '
            'error.',
        'The favorite intention list isn’t up to date because of an '
            'unexpected error.',
      ),
    ]) {
      testWidgets('английские сообщения отказа ${failure.category.name}', (
        tester,
      ) async {
        final initial = await _pumpHome(tester, locale: 'en');
        initial.repository.failRead(0, failure);
        await tester.pumpAndSettle();
        expect(find.text(message), findsOneWidget);

        final loaded = await _pumpLoadedHome(tester, locale: 'en');
        await _confirmMark(tester, loaded, revision: 2);
        loaded.repository.failRead(1, failure);
        await tester.pumpAndSettle();
        expect(find.text(mark), findsOneWidget);
      });
    }
  });

  group('живая область', () {
    testWidgets('объявляет загрузку', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpHome(tester);

      _expectLiveRegion(tester, 'Загружаем избранные намерения…');
      semantics.dispose();
    });

    for (final (archivedCount, text) in [
      (0, 'Избранных намерений пока нет'),
      (1, 'Все избранные намерения в архиве'),
    ]) {
      testWidgets('объявляет пустое состояние с числом архивированных '
          'избранных $archivedCount', (tester) async {
        final semantics = tester.ensureSemantics();
        final h = await _pumpHome(tester);
        h.repository.completeRead(0, archivedCount: archivedCount);
        await tester.pumpAndSettle();

        _expectLiveRegion(tester, text);
        semantics.dispose();
      });
    }

    for (final (failure, text) in <(FavoriteIntentionsReadFailure, String)>[
      (
        const FavoriteIntentionsUnavailableFailure(),
        'Не удалось загрузить избранные намерения. Повторите попытку.',
      ),
      (const FavoriteIntentionsCorruptionFailure(), 'повреждены'),
      (const FavoriteIntentionsUnexpectedFailure(), 'непредвиденной ошибки'),
    ]) {
      testWidgets('объявляет отказ получения ${failure.category.name}', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        final h = await _pumpHome(tester);
        h.repository.failRead(0, failure);
        await tester.pumpAndSettle();

        _expectLiveRegion(tester, text);
        semantics.dispose();
      });
    }

    testWidgets('объявляет пометку «не обновлён»', (tester) async {
      final semantics = tester.ensureSemantics();
      final h = await _pumpLoadedHome(tester);
      await _confirmMark(tester, h, revision: 2);
      h.repository.failRead(1, const FavoriteIntentionsUnavailableFailure());
      await tester.pumpAndSettle();

      _expectLiveRegion(tester, 'Список избранных намерений не обновлён');
      semantics.dispose();
    });

    testWidgets('строка сообщает экранному диктору название, готовность и '
        'число активных связей одним узлом', (tester) async {
      final semantics = tester.ensureSemantics();
      final h = await _pumpHome(tester);
      h.repository.completeRead(
        0,
        items: [
          homeTestRow(
            1,
            'Читать',
            readiness: IntentionReadiness.ready,
            activeRelationCount: 3,
          ),
        ],
      );
      await tester.pumpAndSettle();

      final node = tester.getSemantics(
        find.descendant(
          of: find.byKey(ValueKey(homeTestIntentionId(1))),
          matching: find.byType(IntentionSummaryView),
        ),
      );
      expect(node.label, contains('Читать'));
      expect(node.label, contains('Готово к действию'));
      expect(node.label, contains('Активных связей: 3'));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      semantics.dispose();
    });
  });

  testWidgets('при увеличенном тексте объяснение пустого состояния и переход '
      'к графу намерений остаются доступными', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final h = await _pumpHome(tester, textScale: 2.5);
    h.repository.completeRead(0);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('пока нет'), findsOneWidget);
    await tester.ensureVisible(find.text('Открыть граф намерений'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Открыть граф намерений'));
    await tester.pumpAndSettle();

    expect(h.router.current.name, IntentionCatalogRoute.name);
    expect(tester.takeException(), isNull);
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

Future<HomeHarnessWithRouter> _pumpHome(
  WidgetTester tester, {
  String locale = 'ru',
  double textScale = 1,
}) async {
  final harness = HomeHarness();
  addTearDown(harness.dispose);
  final router = _TestRouter();
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      // Новый ключ заменяет приложение предыдущего вызова целиком.
      key: UniqueKey(),
      container: harness.container,
      child: MaterialApp.router(
        routerConfig: router.config(),
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pump();
  expect(find.byType(HomePage), findsOneWidget);
  return (repository: harness.repository, harness: harness, router: router);
}

/// Главная со списком «Читать», «Гулять» на ревизии 1.
Future<HomeHarnessWithRouter> _pumpLoadedHome(
  WidgetTester tester, {
  String locale = 'ru',
}) async {
  final h = await _pumpHome(tester, locale: locale);
  h.repository.completeRead(
    0,
    items: [homeTestRow(1, 'Читать'), homeTestRow(2, 'Гулять')],
  );
  await tester.pumpAndSettle();
  return h;
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

/// Проверяет, что текст [text] объявляется живой областью.
void _expectLiveRegion(WidgetTester tester, String text) {
  final node = tester.getSemantics(
    find
        .ancestor(
          of: find.textContaining(text),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && (widget.properties.liveRegion ?? false),
          ),
        )
        .first,
  );
  expect(node.flagsCollection.isLiveRegion, isTrue);
  expect(node.label, contains(text));
}
