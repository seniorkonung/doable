import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/presentation/action_picker/daily_choice_action_picker_page.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_page.dart';
import 'package:doable/src/daily_choice/presentation/source_picker/daily_choice_source_picker_page.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/favorite/presentation/home/home_page.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/intention_summary_view.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/long_term_relation/presentation/participant_picker/relation_participant_picker_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/favorite_storage_fixture.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/local_database_harness.dart';
import '../support/tag_storage_fixture.dart';
import '../support/in_memory_quick_creation_mode_store.dart';

// Названия намерений — данные человека: они одинаковы в обеих локалях.

/// «Гулять», готово к действию.
const _walk = 1;

/// «Читать», готово к действию.
const _read = 2;

/// «Плавать», не готово к действию.
const _swim = 3;

/// «Бегать», готово к действию: источник обеих связей и невыполненного
/// дневного выбора.
const _run = 4;

/// «Спать», готово к действию: выбранное действие дневного выбора.
const _sleep = 5;

/// «Петь», готово к действию: связанный участник связи вне дневных путей.
const _sing = 6;

const _titles = {
  _walk: 'Гулять',
  _read: 'Читать',
  _swim: 'Плавать',
  _run: 'Бегать',
  _sleep: 'Спать',
  _sing: 'Петь',
};

/// Связь «Бегать» → «Спать» — путь невыполненного дневного выбора.
const _pathRelation = 101;

/// Связь «Бегать» → «Петь» вне дневных путей: её связанного участника можно
/// заменить.
const _freeRelation = 102;

/// Невыполненный дневной выбор, из замены пути которого открываются поиски
/// действия и исходного намерения.
const _openChoice = 201;

/// Идентификатор, которому не соответствует ни одно намерение.
const _missing = 99;

const _favoriteControl = ValueKey('intention-details-favorite-mark');
const _message = ValueKey('graph-operation-message');

void main() {
  for (final locale in const [Locale('ru'), Locale('en')]) {
    final code = locale.languageCode;

    testWidgets('место без существующего намерения даёт на Главной отдельное '
        'неповторяемое повреждение, а каталог намерений, поиски и страница '
        'намерения продолжают работать с целостными отметками на $code', (
      tester,
    ) async {
      final install = await _install(tester, locale);
      final l10n = install.l10n;
      final app = await _launch(
        tester,
        install,
        seed: (database) {
          _seedGraph(database, favorites: const [_walk, _read]);
          storeFavoritePlaceWithoutIntention(
            database,
            intentionId: tagFixtureId(_missing),
            position: 3,
          );
        },
      );
      _expectCorruption(tester, l10n);
      // Повреждение не исправляется: место без намерения остаётся.
      final marks = [
        (tagFixtureId(_walk), 1),
        (tagFixtureId(_read), 2),
        (tagFixtureId(_missing), 3),
      ];
      expect(storedFavoriteMarks(app.raw), marks);

      // Каталог намерений и три поиска показывают целостные отметки.
      await _select(tester, AppDestination.intentionGraph);
      await _expectSearches(tester, app, l10n);

      // Страница избранного намерения показывает его отметку, а отметка
      // другого намерения подтверждается и видна в каталоге.
      await _openFromCatalog(tester, _walk);
      expect(_controlTooltip(tester), l10n.detailsUnmarkFavoriteAction);
      await _closeDetails(tester);
      final reads = install.homeReads.reads;
      await _openFromCatalog(tester, _run);
      expect(_controlTooltip(tester), l10n.detailsMarkFavoriteAction);
      await _toggleMark(tester);
      expect(_controlTooltip(tester), l10n.detailsUnmarkFavoriteAction);
      await _closeDetails(tester);
      await _expectStars(
        tester,
        IntentionCatalogPage,
        l10n,
        shown: _titles.keys.toList(),
        favorites: const {_walk, _read, _run},
      );
      expect(storedFavoriteMarks(app.raw), [...marks, (tagFixtureId(_run), 4)]);

      // Подтверждённое изменение избранного перечитывает список, и
      // повреждение остаётся отдельным результатом, а не списком с
      // пропуском.
      await _waitFor(tester, () => install.homeReads.reads > reads);
      await _select(tester, AppDestination.home);
      _expectCorruption(tester, l10n);
      expect(find.byKey(_message), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}

/// Установка приложения: постоянное хранилище и наблюдение чтений списка
/// Главной.
final class _Install {
  _Install(this.harness, this.l10n);

  final LocalDatabaseHarness harness;
  final AppLocalizations l10n;
  final homeReads = _HomeReads();
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
  _Launch(this.raw, this.container);

  final sqlite.Database raw;
  final ProviderContainer container;

  AppRouter get router => container.read(appRouterProvider);
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
    connectionFactory: () => observeConfiguredLocalDatabaseConnection(
      openFileBackedLocalDatabase(
        install.harness.databaseFile,
        setup: (database) => raw = database,
      ),
      install.homeReads,
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
  return _Launch(raw, ready.container);
}

/// Шесть активных намерений, связи «Бегать» и его невыполненный дневной
/// выбор; [favorites] отмечены в этом порядке на местах 1, 2, …
void _seedGraph(sqlite.Database database, {List<int> favorites = const []}) {
  for (final MapEntry(key: number, value: title) in _titles.entries) {
    database.execute(
      'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
      [tagFixtureId(number), title, number == _swim ? 0 : 1, 0, number, number],
    );
  }
  for (final (number, related) in [
    (_pathRelation, _sleep),
    (_freeRelation, _sing),
  ]) {
    database.execute(
      'INSERT INTO long_term_relations (id, source_intention_id, related_intention_id, type, priority, is_archived) VALUES (?, ?, ?, ?, ?, ?)',
      [
        tagFixtureId(number),
        tagFixtureId(_run),
        tagFixtureId(related),
        'need',
        2,
        0,
      ],
    );
  }
  database.execute(
    'INSERT INTO daily_choices (id, source_intention_id, selected_intention_id, choice_date, is_completed) VALUES (?, ?, ?, ?, ?)',
    [
      tagFixtureId(_openChoice),
      tagFixtureId(_run),
      tagFixtureId(_sleep),
      '2026-09-25',
      0,
    ],
  );
  database.execute(
    'INSERT INTO daily_choice_path_steps (id, daily_choice_id, long_term_relation_id) VALUES (?, ?, ?)',
    [
      tagFixtureId(_openChoice + 10),
      tagFixtureId(_openChoice),
      tagFixtureId(_pathRelation),
    ],
  );
  for (final (index, intention) in favorites.indexed) {
    storeFavoriteMark(
      database,
      intentionId: tagFixtureId(intention),
      position: index + 1,
    );
  }
}

/// Элементы Главной, в том числе пока она закрыта другим пунктом или
/// страницей поверх оболочки.
Finder _onHome(Finder matching) => find.descendant(
  of: find.byType(HomePage, skipOffstage: false),
  matching: matching,
  skipOffstage: false,
);

/// Текст [text] на Главной.
Finder _homeText(String text) => _onHome(find.text(text, skipOffstage: false));

final _homeRows = _onHome(find.byType(HomeIntentionRow, skipOffstage: false));

/// Повтор получения на Главной.
Finder _retry(AppLocalizations l10n) => _onHome(
  find.widgetWithText(FilledButton, l10n.commonRetry, skipOffstage: false),
);

/// Главная показывает отдельный неповторяемый результат повреждения: не
/// пустое состояние, не список с пропуском и не обычный повтор.
void _expectCorruption(WidgetTester tester, AppLocalizations l10n) {
  expect(_homeText(l10n.homeCorruption), findsOneWidget);
  expect(_homeRows, findsNothing);
  expect(_retry(l10n), findsNothing);
  for (final text in [
    l10n.homeEmptyNoFavorites,
    l10n.homeEmptyAllArchived,
    l10n.homeOpenIntentionGraph,
    l10n.homeUnavailable,
    l10n.homeLoading,
  ]) {
    expect(_homeText(text), findsNothing, reason: text);
  }
}

AppDestination _selected(WidgetTester tester) => tester
    .widget<AppNavigationBar>(
      find.byType(AppNavigationBar, skipOffstage: false),
    )
    .selected;

/// Выбирает пункт панели и ждёт его корневую страницу.
Future<void> _select(WidgetTester tester, AppDestination destination) async {
  await _tap(
    tester,
    find.descendant(
      of: find.byType(AppNavigationBar),
      matching: find.byIcon(
        _selected(tester) == destination
            ? destination.selectedIcon
            : destination.icon,
      ),
    ),
  );
  await _until(tester, find.byType(_rootPages[destination]!));
  await tester.pumpAndSettle();
  expect(_selected(tester), destination);
}

const _rootPages = {
  AppDestination.home: HomePage,
  AppDestination.dailyChoices: DailyChoiceCatalogPage,
  AppDestination.intentionGraph: IntentionCatalogPage,
};

Finder _catalogRow(int intention) => find.descendant(
  of: find.byType(IntentionCatalogPage),
  matching: find.widgetWithText(IntentionSummaryView, _titles[intention]!),
);

Future<void> _openFromCatalog(WidgetTester tester, int intention) async {
  await _tap(tester, _catalogRow(intention));
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
Future<void> _closeDetails(WidgetTester tester) =>
    _closeTop(tester, IntentionDetailsPage);

Future<void> _closeTop(WidgetTester tester, Type page) async {
  await tester.binding.handlePopRoute();
  await _gone(tester, page);
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
  expect(find.byKey(_message), findsNothing);
}

/// Проверяет звёзды целостных отметок в каталоге намерений и в поисках
/// действия, исходного намерения и участника связи.
Future<void> _expectSearches(
  WidgetTester tester,
  _Launch app,
  AppLocalizations l10n,
) async {
  const favorites = {_walk, _read};
  await _expectStars(
    tester,
    IntentionCatalogPage,
    l10n,
    shown: _titles.keys.toList(),
    favorites: favorites,
  );

  // Поиск действия: только активные готовые намерения.
  unawaited(
    app.router.push(
      DailyChoiceDetailsRoute(
        choiceId: (DailyChoiceId.decode(
          tagFixtureId(_openChoice),
        ) as DailyChoiceIdDecodingSuccess).id,
      ),
    ),
  );
  await _tap(tester, find.byKey(const ValueKey('daily-choice-replace-open')));
  await _tap(
    tester,
    find.byKey(const ValueKey('daily-choice-replace-bottom-up')),
  );
  await _until(tester, find.byType(DailyChoiceActionPickerPage));
  await _expectStars(
    tester,
    DailyChoiceActionPickerPage,
    l10n,
    shown: const [_walk, _read, _run, _sleep, _sing],
    favorites: favorites,
  );
  await _tap(tester, find.byKey(const ValueKey('daily-choice-action-cancel')));
  await _gone(tester, DailyChoiceActionPickerPage);

  // Поиск исходного намерения: активные независимо от готовности.
  await _tap(
    tester,
    find.byKey(const ValueKey('daily-choice-replace-top-down')),
  );
  await _until(tester, find.byType(DailyChoiceSourcePickerPage));
  await _expectStars(
    tester,
    DailyChoiceSourcePickerPage,
    l10n,
    shown: _titles.keys.toList(),
    favorites: favorites,
  );
  await _tap(tester, find.byKey(const ValueKey('daily-choice-source-cancel')));
  await _gone(tester, DailyChoiceSourcePickerPage);
  await _popToRoot(tester, app);

  // Поиск участника связи: второй участник «Бегать» исключён.
  unawaited(
    app.router.push(
      RelationDetailsRoute(
        relationId: (LongTermRelationId.decode(
          tagFixtureId(_freeRelation),
        ) as LongTermRelationIdDecodingSuccess).id,
      ),
    ),
  );
  await _tap(
    tester,
    find.byKey(const ValueKey('relation-details-edit-relation')),
  );
  await _tap(
    tester,
    find.byKey(const ValueKey('relation-editor-change-related')),
  );
  await _until(tester, find.byType(RelationParticipantPickerPage));
  await _expectStars(
    tester,
    RelationParticipantPickerPage,
    l10n,
    shown: const [_walk, _read, _swim, _sleep, _sing],
    favorites: favorites,
  );
  await _tap(tester, find.byKey(const ValueKey('participant-picker-cancel')));
  await _gone(tester, RelationParticipantPickerPage);
  await _popToRoot(tester, app);
  expect(find.byType(IntentionCatalogPage), findsOneWidget);
}

/// Дожидается, пока выдача страницы [page] покажет ровно намерения [shown], и
/// проверяет звезду каждого: она есть только у [favorites] и несёт
/// локализованное название отметки.
Future<void> _expectStars(
  WidgetTester tester,
  Type page,
  AppLocalizations l10n, {
  required List<int> shown,
  required Set<int> favorites,
}) async {
  final expected = {
    for (final number in shown) _titles[number]!: favorites.contains(number),
  };
  await _pumpUntil(
    tester,
    () => mapEquals(_shownStars(tester, page, l10n), expected),
  );
  await tester.pumpAndSettle();
  expect(_shownStars(tester, page, l10n), expected);
}

/// Видимые результаты поиска страницы: название и наличие звезды так, как
/// они показаны.
Map<String, bool> _shownStars(
  WidgetTester tester,
  Type page,
  AppLocalizations l10n,
) {
  final rows = find.descendant(
    of: find.byType(page),
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

Future<void> _popToRoot(WidgetTester tester, _Launch app) async {
  while (app.router.canPop()) {
    unawaited(app.router.maybePop());
    await tester.pumpAndSettle();
  }
}

Future<void> _gone(WidgetTester tester, Type page) async {
  await _waitFor(tester, () => find.byType(page).evaluate().isEmpty);
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

/// Наблюдает чтения списка Главной; остальные чтения и записи не
/// затрагиваются.
final class _HomeReads extends LocalDatabaseConnectionObserver {
  /// Число чтений списка Главной, дошедших до хранилища.
  var reads = 0;

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (statement.operation != LocalDatabaseSqlOperation.select ||
        !statement.statements.any(
          (sql) => sql.contains('FROM favorite_intentions f'),
        )) {
      return;
    }
    reads++;
  }
}
