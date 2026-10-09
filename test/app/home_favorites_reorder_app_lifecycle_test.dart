import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/favorite/presentation/home/home_page.dart';
import 'package:doable/src/favorite/presentation/home/home_state.dart';
import 'package:doable/src/favorite/presentation/home/home_view_model.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/intention_summary_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/app_root_pages.dart';
import '../support/favorite_storage_fixture.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/local_database_harness.dart';
import '../support/tag_storage_fixture.dart';
import '../support/in_memory_quick_creation_mode_store.dart';

// Названия намерений — данные человека: они одинаковы в обеих локалях.

/// «Гулять», готово к действию, без связей — А.
const _walk = 1;

/// «Читать», готово к действию, одна активная связь — Б.
const _read = 2;

/// «Плавать», не готово к действию, без связей — В: архивируется, пока
/// избранное, и остаётся скрытым участником перестановки.
const _swim = 3;

/// «Бегать», готово к действию, одна активная связь — Г.
const _run = 4;

/// «Спать», готово к действию, без связей — Д: остаётся архивированным
/// избранным намерением на время перезапуска.
const _sleep = 5;

/// «Петь», готово к действию, — неизбранный участник обеих связей.
const _sing = 6;

/// Намерение так, как его показывает строка Главной.
typedef _Intention = ({String title, bool isReady, int relations});

const _intentions = <int, _Intention>{
  _walk: (title: 'Гулять', isReady: true, relations: 0),
  _read: (title: 'Читать', isReady: true, relations: 1),
  _swim: (title: 'Плавать', isReady: false, relations: 0),
  _run: (title: 'Бегать', isReady: true, relations: 1),
  _sleep: (title: 'Спать', isReady: true, relations: 0),
  _sing: (title: 'Петь', isReady: true, relations: 2),
};

const _favoriteControl = ValueKey('intention-details-favorite-mark');
const _message = ValueKey('graph-operation-message');

void main() {
  for (final locale in const [Locale('ru'), Locale('en')]) {
    final code = locale.languageCode;

    testWidgets('человек отмечает намерения на их страницах, переставляет их '
        'на Главной жестом и действием экранного диктора, в том числе мимо '
        'скрытого архивированного, снимает и возвращает отметку, а после '
        'полного перезапуска Главная открывается с тем же полным порядком и '
        'отметками без изменения времени намерений на $code', (tester) async {
      final semantics = tester.ensureSemantics();
      final install = await _install(tester, locale);
      final l10n = install.l10n;
      final first = await _launch(tester, install, seed: _seedGraph);
      _expectHomeRoot(tester, first);
      expect(_homeText(l10n.homeEmptyNoFavorites), findsOneWidget);

      // Порядок отметок не совпадает с порядком каталога.
      await openIntentionGraph(
        tester,
        waitFor: _until,
        content: _catalogRow(_walk),
      );
      for (final intention in [_walk, _read, _swim, _run, _sleep]) {
        await _openFromCatalog(tester, intention);
        await _toggleMark(tester);
        await _closeDetails(tester);
      }
      await openHome(tester, waitFor: _until);
      await _expectConfirmedHome(tester, first, const [
        _walk,
        _read,
        _swim,
        _run,
        _sleep,
      ]);
      expect(
        storedFavoriteMarks(first.raw),
        _places(const [_walk, _read, _swim, _run, _sleep]),
      );

      // Жест: «Спать» перетаскивается ручкой сразу после «Гулять».
      var times = _intentionTimes(first.raw);
      await _dragHandle(tester, _sleep, -3);
      await _expectConfirmedHome(tester, first, const [
        _walk,
        _sleep,
        _read,
        _swim,
        _run,
      ]);
      expect(
        storedFavoriteMarks(first.raw),
        _places(const [_walk, _sleep, _read, _swim, _run]),
      );
      expect(_intentionTimes(first.raw), times);

      // Действие экранного диктора: «Читать» — на одно место ниже. Новое
      // место объявляется после подтверждения записи.
      _moveBySemantics(
        tester,
        l10n,
        _read,
        (actions) => actions.reorderItemDown,
      );
      await _expectConfirmedHome(tester, first, const [
        _walk,
        _sleep,
        _swim,
        _read,
        _run,
      ]);
      expect(
        find.semantics.byLabel(l10n.homeReorderMoved('Читать', 4, 5)),
        findsOne,
      );
      expect(
        storedFavoriteMarks(first.raw),
        _places(const [_walk, _sleep, _swim, _read, _run]),
      );
      expect(_intentionTimes(first.raw), times);

      // Архивированное «Плавать» скрыто на Главной и сохраняет место.
      await _openFromHome(tester, _swim);
      await _archive(tester);
      await _closeDetails(tester);
      await _expectConfirmedHome(tester, first, const [
        _walk,
        _sleep,
        _read,
        _run,
      ]);

      // «Бегать» ставится сразу после «Спать» и встаёт перед скрытым
      // «Плавать»: остальные сохраняют взаимный порядок.
      times = _intentionTimes(first.raw);
      await _dragHandle(tester, _run, -1);
      await _expectConfirmedHome(tester, first, const [
        _walk,
        _sleep,
        _run,
        _read,
      ]);
      expect(
        storedFavoriteMarks(first.raw),
        _places(const [_walk, _sleep, _run, _swim, _read]),
      );
      expect(_intentionTimes(first.raw), times);

      // Восстановленное «Плавать» возвращается на своё место.
      await openIntentionGraph(tester, waitFor: _until);
      await _selectScope(tester, l10n.catalogScopeArchived);
      await _openFromCatalog(tester, _swim);
      await _restore(tester);
      await _closeDetails(tester);
      await openHome(tester, waitFor: _until);
      await _expectConfirmedHome(tester, first, const [
        _walk,
        _sleep,
        _run,
        _swim,
        _read,
      ]);

      // Снятая и поставленная заново отметка ставит «Гулять» в конец.
      await _openFromHome(tester, _walk);
      await _toggleMark(tester);
      expect(_controlTooltip(tester), l10n.detailsMarkFavoriteAction);
      await _toggleMark(tester);
      await _closeDetails(tester);
      await _expectConfirmedHome(tester, first, const [
        _sleep,
        _run,
        _swim,
        _read,
        _walk,
      ]);

      // «Спать» остаётся архивированным избранным намерением на время
      // перезапуска.
      await _openFromHome(tester, _sleep);
      await _archive(tester);
      await _closeDetails(tester);
      await _expectConfirmedHome(tester, first, const [
        _run,
        _swim,
        _read,
        _walk,
      ]);
      final marks = [
        (tagFixtureId(_sleep), 2),
        (tagFixtureId(_run), 3),
        (tagFixtureId(_swim), 4),
        (tagFixtureId(_read), 5),
        (tagFixtureId(_walk), 6),
      ];
      expect(storedFavoriteMarks(first.raw), marks);

      // Перед завершением выбран граф намерений и поверх открыта страница
      // намерения: новый запуск их не восстанавливает.
      await openIntentionGraph(tester, waitFor: _until);
      await _openFromCatalog(tester, _sleep);
      times = _intentionTimes(first.raw);
      expect(_builtMessages, findsNothing);

      await first.shutdown(tester);
      final second = await _launch(tester, install);
      _expectHomeRoot(tester, second);
      await _expectConfirmedHome(tester, second, const [
        _run,
        _swim,
        _read,
        _walk,
      ]);
      expect(storedFavoriteMarks(second.raw), marks);
      expect(_intentionTimes(second.raw), times);

      // Отметки сохранились у активных и архивированного намерений.
      await openIntentionGraph(
        tester,
        waitFor: _until,
        content: _catalogRow(_walk),
      );
      await _expectStars(
        tester,
        l10n,
        shown: const [_walk, _read, _swim, _run, _sing],
        favorites: const {_walk, _read, _swim, _run},
      );
      await _selectScope(tester, l10n.catalogScopeArchived);
      await _expectStars(
        tester,
        l10n,
        shown: const [_sleep],
        favorites: const {_sleep},
      );

      // Восстановленное после перезапуска «Спать» встаёт на своё первое
      // место.
      await _openFromCatalog(tester, _sleep);
      await _restore(tester);
      await _closeDetails(tester);
      await openHome(tester, waitFor: _until);
      await _expectConfirmedHome(tester, second, const [
        _sleep,
        _run,
        _swim,
        _read,
        _walk,
      ]);
      expect(storedFavoriteMarks(second.raw), marks);
      expect(_builtMessages, findsNothing);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }
}

/// Установка приложения: постоянное хранилище, переживающее перезапуски.
final class _Install {
  _Install(this.harness, this.l10n);

  final LocalDatabaseHarness harness;
  final AppLocalizations l10n;
}

Future<_Install> _install(WidgetTester tester, Locale locale) async {
  // Общая поверхность показывает сообщения только работающему приложению.
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  tester.binding.platformDispatcher.localesTestValue = [locale];
  addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final harness = (await tester.runAsync(LocalDatabaseHarness.fileBacked))!;
  addTearDown(harness.dispose);
  return _Install(harness, lookupAppLocalizations(locale));
}

/// Один запуск приложения на хранилище установки.
final class _Launch {
  _Launch(this.runtime, this.raw, this.container);

  final AppRuntime runtime;
  final sqlite.Database raw;
  final ProviderContainer container;

  AppRouter get router => container.read(appRouterProvider);

  HomeState get home => container.read(homeViewModelProvider);

  /// Полное завершение: дерево приложения снято, хранилище закрыто.
  Future<void> shutdown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(runtime.shutdown);
  }
}

/// Запускает приложение на хранилище [install], засевает его [seed] и ждёт,
/// пока Главная закончит первоначальное получение.
Future<_Launch> _launch(
  WidgetTester tester,
  _Install install, {
  void Function(sqlite.Database database)? seed,
}) async {
  late sqlite.Database raw;
  final runtime = AppRuntime(
    quickCreationModeStore: InMemoryQuickCreationModeStore(),
    connectionFactory: () => openFileBackedLocalDatabase(
      install.harness.databaseFile,
      setup: (database) => raw = database,
    ),
    diagnosticsSink: InMemoryDiagnosticsSink(),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await runtime.shutdown();
  });
  final ready = (await tester.runAsync(runtime.bootstrap)) as AppRuntimeReady;
  seed?.call(raw);
  await tester.pumpWidget(MainApp(runtime: runtime));
  await _until(tester, find.byType(HomePage));
  await _waitFor(
    tester,
    () => find.text(install.l10n.homeLoading).evaluate().isEmpty,
  );
  await tester.pumpAndSettle();
  return _Launch(runtime, raw, ready.container);
}

/// Шесть активных намерений без отметок и две связи с «Петь».
void _seedGraph(sqlite.Database database) {
  for (final MapEntry(key: number, value: intention) in _intentions.entries) {
    database.execute(
      'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
      [
        tagFixtureId(number),
        intention.title,
        intention.isReady ? 1 : 0,
        0,
        number,
        number,
      ],
    );
  }
  for (final (number, source) in [(101, _read), (102, _run)]) {
    database.execute(
      'INSERT INTO long_term_relations (id, source_intention_id, related_intention_id, type, priority, is_archived) VALUES (?, ?, ?, ?, ?, ?)',
      [
        tagFixtureId(number),
        tagFixtureId(source),
        tagFixtureId(_sing),
        'need',
        2,
        0,
      ],
    );
  }
}

/// Сохранённые места намерений [order] после перезаписи порядка: 1, 2, …
List<(String, int)> _places(List<int> order) => [
  for (final (index, intention) in order.indexed)
    (tagFixtureId(intention), index + 1),
];

/// Сохранённые показания времени создания и изменения всех намерений.
List<List<Object?>> _intentionTimes(sqlite.Database database) => [
  for (final row in database.select(
    'SELECT id, created_at, updated_at FROM intentions ORDER BY rowid',
  ))
    row.values.toList(),
];

IntentionId _intentionId(int number) =>
    (IntentionId.decode(tagFixtureId(number)) as IntentionIdDecodingSuccess).id;

/// Элементы Главной, в том числе пока она закрыта другим пунктом или
/// страницей поверх оболочки.
Finder _onHome(Finder matching) => find.descendant(
  of: find.byType(HomePage, skipOffstage: false),
  matching: matching,
  skipOffstage: false,
);

Finder _homeText(String text) => _onHome(find.text(text, skipOffstage: false));

/// Сообщения общей поверхности в дереве, включая невыбранные вкладки.
final _builtMessages = find.byKey(_message, skipOffstage: false);

/// Строка Главной намерения [number].
Finder _homeRow(int number) => find.descendant(
  of: find.byType(HomePage),
  matching: find.byKey(ValueKey(_intentionId(number))),
);

/// Ручка строки Главной намерения [number].
Finder _handle(int number) => find.descendant(
  of: _homeRow(number),
  matching: find.byIcon(Icons.drag_handle),
);

/// Намерения строк Главной в порядке, в котором их видит человек.
List<String> _shownHome(WidgetTester tester) {
  final rows = [
    for (final element in find.byType(HomeIntentionRow).evaluate())
      (
        top: (element.renderObject! as RenderBox).localToGlobal(Offset.zero).dy,
        id: (element.widget as HomeIntentionRow).row.id.toCanonicalString(),
      ),
  ]..sort((a, b) => a.top.compareTo(b.top));
  return [for (final row in rows) row.id];
}

/// Дожидается, пока Главная покажет подтверждённый цельным снимком список
/// [expected] без принятой перестановки, и проверяет показанные строки:
/// порядок, отсутствие признака сохранения и доступные ручки.
Future<void> _expectConfirmedHome(
  WidgetTester tester,
  _Launch app,
  List<int> expected,
) async {
  final ids = [for (final number in expected) tagFixtureId(number)];
  await _waitFor(
    tester,
    () => switch (app.home) {
      HomeList(
        reorder: HomeReorderIdle(),
        freshness: HomeFreshnessCurrent(),
        :final items,
      ) =>
        listEquals([for (final row in items) row.id.toCanonicalString()], ids),
      _ => false,
    },
  );
  await tester.pumpAndSettle();
  expect(_shownHome(tester), ids);
  final l10n = AppLocalizations.of(tester.element(find.byType(HomePage)));
  expect(_homeText(l10n.homeReorderSaving), findsNothing);
  expect(find.byType(ReorderableDragStartListener), findsNWidgets(ids.length));
  // Успех перестановки предъявляется новым порядком, без сообщения.
  expect(_builtMessages, findsNothing);
}

/// Открыта Главная: страниц поверх нет, панель видна, выбран пункт
/// «Главная».
void _expectHomeRoot(WidgetTester tester, _Launch app) {
  expectHomeRootPage(app.router);
  expect(find.byType(HomePage), findsOneWidget);
  expect(find.byType(AppNavigationBar), findsOneWidget);
  expect(
    tester.widget<AppNavigationBar>(find.byType(AppNavigationBar)).selected,
    AppDestination.home,
  );
}

/// Перетаскивает строку Главной намерения [number] ручкой на [places] мест:
/// вниз при положительном числе, вверх — при отрицательном.
///
/// Перетаскиваемая строка занимает место соседней, когда её край заходит за
/// середину соседней строки, поэтому смещение на три четверти высоты строки
/// на каждое место однозначно задаёт новое место.
Future<void> _dragHandle(WidgetTester tester, int number, int places) async {
  final rowHeight = tester.getSize(_homeRow(number)).height;
  final distance = (places.abs() - 0.25) * rowHeight * places.sign;
  final gesture = await tester.startGesture(tester.getCenter(_handle(number)));
  const steps = 10;
  for (var step = 0; step < steps; step++) {
    await gesture.moveBy(Offset(0, distance / steps));
    await tester.pump();
  }
  await gesture.up();
  await tester.pump();
}

/// Выполняет у строки Главной намерения [number] системное действие
/// перемещения, которое экранный диктор предлагает на языке интерфейса.
void _moveBySemantics(
  WidgetTester tester,
  AppLocalizations l10n,
  int number,
  String Function(WidgetsLocalizations actions) action,
) {
  final intention = _intentions[number]!;
  final label = [
    intention.title,
    intention.isReady ? l10n.catalogReady : l10n.catalogNotReady,
    l10n.intentionActiveRelationCount(intention.relations),
  ].join('\n');
  tester.semantics.customAction(
    find.semantics.byLabel(label),
    CustomSemanticsAction(
      label: action(
        WidgetsLocalizations.of(tester.element(find.byType(HomePage))),
      ),
    ),
  );
}

Finder _catalogRow(int intention) => find.descendant(
  of: find.byType(IntentionCatalogPage),
  matching: find.widgetWithText(
    IntentionSummaryView,
    _intentions[intention]!.title,
  ),
);

Future<void> _openFromCatalog(WidgetTester tester, int intention) async {
  await _tap(tester, _catalogRow(intention));
  await _expectDetails(tester, intention);
}

Future<void> _openFromHome(WidgetTester tester, int intention) async {
  await _tap(tester, _homeRow(intention));
  await _expectDetails(tester, intention);
}

/// Открыта страница именно намерения [intention].
Future<void> _expectDetails(WidgetTester tester, int intention) async {
  await _until(tester, find.byKey(_favoriteControl));
  await tester.pumpAndSettle();
  expect(
    tester
        .widget<IntentionDetailsPage>(find.byType(IntentionDetailsPage))
        .intentionId
        .toCanonicalString(),
    tagFixtureId(intention),
  );
}

/// Закрывает страницу намерения системным действием «назад».
Future<void> _closeDetails(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await _waitFor(
    tester,
    () => find.byType(IntentionDetailsPage).evaluate().isEmpty,
  );
  await tester.pumpAndSettle();
}

String? _controlTooltip(WidgetTester tester) =>
    tester.widget<IconButton>(find.byKey(_favoriteControl)).tooltip;

/// Нажимает управление отметкой и дожидается подтверждённого результата.
Future<void> _toggleMark(WidgetTester tester) async {
  final before = _controlTooltip(tester);
  await _tap(tester, find.byKey(_favoriteControl));
  await _waitFor(tester, () => _controlTooltip(tester) != before);
  await _acceptMessage(tester);
}

Future<void> _archive(WidgetTester tester) async {
  await _tap(tester, find.byKey(const ValueKey('intention-details-archive')));
  await _until(tester, find.byKey(const ValueKey('intention-details-restore')));
  await _acceptMessage(tester);
}

Future<void> _restore(WidgetTester tester) async {
  await _tap(tester, find.byKey(const ValueKey('intention-details-restore')));
  await _until(tester, find.byKey(const ValueKey('intention-details-archive')));
  await _acceptMessage(tester);
}

/// Дожидается ровно одного сообщения общей поверхности о подтверждённой
/// операции и закрывает его.
Future<void> _acceptMessage(WidgetTester tester) async {
  await _until(tester, find.byKey(_message));
  await tester.pumpAndSettle();
  expect(find.byKey(_message), findsOneWidget);
  ScaffoldMessenger.of(tester.element(find.byKey(_message)))
      .hideCurrentSnackBar();
  await tester.pumpAndSettle();
  // Предъявленный результат не показывается повторно.
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
  expect(_builtMessages, findsNothing);
}

/// Дожидается, пока выдача каталога намерений покажет ровно намерения
/// [shown], и проверяет звезду каждого: она есть только у [favorites] и несёт
/// локализованное название отметки.
Future<void> _expectStars(
  WidgetTester tester,
  AppLocalizations l10n, {
  required List<int> shown,
  required Set<int> favorites,
}) async {
  final expected = {
    for (final number in shown)
      _intentions[number]!.title: favorites.contains(number),
  };
  await _pumpUntil(
    tester,
    () => mapEquals(_shownStars(tester, l10n), expected),
  );
  await tester.pumpAndSettle();
  expect(_shownStars(tester, l10n), expected);
}

/// Видимые результаты каталога намерений: название и наличие звезды так, как
/// они показаны.
Map<String, bool> _shownStars(WidgetTester tester, AppLocalizations l10n) {
  final rows = find.descendant(
    of: find.byType(IntentionCatalogPage),
    matching: find.byType(IntentionSummaryView),
  );
  return {
    for (var index = 0; index < rows.evaluate().length; index++)
      tester.widget<IntentionSummaryView>(rows.at(index)).title: switch (tester
          .widgetList<Icon>(
            find.descendant(
              of: rows.at(index),
              matching: find.byIcon(Icons.star),
            ),
          )
          .toList()) {
        [] => false,
        [final star]
            when star.semanticLabel == l10n.intentionSummaryFavoriteMark =>
          true,
        final stars => fail('Недопустимая отметка строки: $stars'),
      },
  };
}

Future<void> _selectScope(WidgetTester tester, String label) async {
  await _tap(tester, find.byKey(const ValueKey('catalog-scope-control')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _until(WidgetTester tester, Finder finder) =>
    _waitFor(tester, () => finder.evaluate().isNotEmpty);

Future<void> _waitFor(WidgetTester tester, bool Function() done) async {
  await _pumpUntil(tester, done);
  expect(done(), isTrue);
}

/// Продвигает кадры и реальное время хранилища, пока не выполнится [done]
/// или не истечёт срок; результат проверяет вызывающий.
Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 100 && !done(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Нажимает элемент [finder], прокручивая к нему, только если он не
/// принимает нажатие: прокрутка к видимой строке выдачи увела бы параметры
/// поиска каталога намерений за верхний край страницы.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _until(tester, finder);
  await tester.pumpAndSettle();
  if (finder.hitTestable().evaluate().isEmpty) {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }
  await tester.tap(finder);
  await tester.pump();
}
