import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/home/home_page.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/app/settings/settings_page.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar_viewport.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_page.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/data_transfer/application/graph_replacement.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph_format/graph_format_records.dart';
import 'package:doable/src/graph_snapshots/graph_snapshot_store.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart';
import 'package:doable/src/intention/presentation/catalog/tag_condition_picker_page.dart';
import 'package:doable/src/statistics/application/statistics_period.dart';
import 'package:doable/src/statistics/application/statistics_read_contract.dart';
import 'package:doable/src/statistics/presentation/home_statistics_state.dart';
import 'package:doable/src/statistics/presentation/home_statistics_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/app_root_pages.dart';
import '../../support/daily_choice_catalog_controls.dart';
import '../../support/daily_choice_local_date.dart';
import '../../support/graph_seed.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/in_memory_quick_creation_mode_store.dart';
import '../../support/inline_text.dart';
import '../../support/tag_storage_fixture.dart';
import '../../support/temporary_graph_files.dart';

/// Намерений в графе до замены и после неё: выдача каталога длиннее экрана.
const _intentionCount = 40;

/// Тег «Здоровье» прежнего графа; его получает каждое намерение.
const _previousTag = 601;

/// Первое намерение прежнего графа.
const _firstPrevious = 1;

/// Тег «Здоровье» нового графа и его первое намерение.
const _replacedTag = 602;
const _firstReplaced = 101;

/// Местное сегодня до замены графа.
final _today = CalendarDate.fromParts(2026, 10, 19);

/// Прошлый день, который выбран в каталоге дневных выборов до замены.
final _pastDay = CalendarDate.fromParts(2026, 10, 14);

/// Местное сегодня к замене графа: корневые страницы открываются на нём, а
/// каталог дневных выборов — не на дне своего первого открытия.
final _replacementDay = CalendarDate.fromParts(2026, 10, 20);

final _l10n = lookupAppLocalizations(const Locale('ru'));

void main() {
  testWidgets('замена графа со страницы «Настройки» оставляет её открытой с '
      'выбранным пунктом «Главная», а корневые страницы после неё открываются '
      'как при новом запуске', (tester) async {
    final app = await _start(tester);
    await _prepareIntentionCatalog(tester);
    await _prepareDailyChoiceCatalog(tester);
    await _prepareHome(tester, app);
    await _open(tester, find.byTooltip(_l10n.settingsTitle), SettingsPage);
    app.localDate.today = _replacementDay;

    await _replaceGraph(tester, app);

    expect(find.byType(SettingsPage), findsOneWidget);
    expect(app.router.stack.map((page) => page.name), [
      AppShellRoute.name,
      SettingsRoute.name,
    ]);
    expect(_selected(tester), AppDestination.home);

    await _closeTop(tester, SettingsPage);
    expect(_selected(tester), AppDestination.home);
    final home = app.container.read(homeStatisticsViewModelProvider).selection;
    expect(
      (
        today: home.localDate,
        tab: home.tab,
        period: home.period,
        view: home.view,
        expanded: home.isPeriodSelectorExpanded,
      ),
      (
        today: _replacementDay,
        tab: HomeStatisticsTab.month,
        period: StatisticsMonth(2026, 10),
        view: StatisticsView.sourceIntentions,
        expanded: false,
      ),
    );

    await _select(tester, AppDestination.intentionGraph);
    await _until(tester, find.text(_l10n.catalogTotalCount(_intentionCount)));
    await _settle(tester);
    expect(_intentionCatalogParameters(tester), {
      'охват': [_l10n.catalogScopeActive, _l10n.catalogScopeLabel],
      'фильтр названия': '',
      'условия по тегам': isEmpty,
      'порядок': [_l10n.catalogOrderCreatedNewest, _l10n.catalogOrderLabel],
      'позиция прокрутки': 0,
      'позиция прокрутки страницы': 0,
    });
    // Выдача нового графа начинается с первой строки начального порядка.
    expect(
      find.descendant(
        of: find.byType(IntentionCatalogPage),
        matching: find.text(_replacedTitle(_intentionCount)),
      ),
      findsOneWidget,
    );

    await _select(tester, AppDestination.dailyChoices);
    expect(shownDailyChoiceCatalogDate(tester), _replacementDay);
    expect(
      shownDailyChoiceCatalogViewport(tester),
      DailyChoiceCalendarViewport(
        focusedDate: _replacementDay,
        mode: DailyChoiceCalendarMode.week,
      ),
    );
    expect(tester.takeException(), isNull);
  });
}

/// Запущенное приложение на реальном хранилище с файлами графа.
final class _App {
  _App(this.container, this.files, this.localDate);

  final ProviderContainer container;
  final TemporaryGraphFiles files;
  final ControlledDailyChoiceLocalDate localDate;

  AppRouter get router => container.read(appRouterProvider);
}

/// Запускает приложение на засеянном хранилище и ждёт Главную.
Future<_App> _start(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  tester.binding.platformDispatcher.localesTestValue = const [Locale('ru')];
  addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
  tester.view.physicalSize = const Size(1200, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  late sqlite.Database raw;
  final files = TemporaryGraphFiles();
  final localDate = ControlledDailyChoiceLocalDate(_today);
  final runtime = AppRuntime(
    connectionFactory: () =>
        openInMemoryLocalDatabase(setup: (database) => raw = database),
    diagnosticsSink: InMemoryDiagnosticsSink(),
    quickCreationModeStore: InMemoryQuickCreationModeStore(),
    graphFilesFactory: files.create,
    dailyChoiceLocalDateSource: localDate.read,
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(runtime.shutdown);
  });
  final ready = (await tester.runAsync(runtime.bootstrap)) as AppRuntimeReady;
  _seed(raw);
  await tester.pumpWidget(MainApp(runtime: runtime));
  await _until(tester, find.byType(HomePage));
  await _waitFor(
    tester,
    () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
  );
  await tester.pumpAndSettle();
  return _App(ready.container, files, localDate);
}

/// Прежний граф: тег «Здоровье» и намерения «Намерение 01» … «Намерение 40»
/// с этим тегом.
void _seed(sqlite.Database database) {
  database.execute('BEGIN');
  seedRawGraph(database, () {
    database.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
      tagFixtureId(_previousTag),
      'Здоровье',
    ]);
    for (var number = 1; number <= _intentionCount; number++) {
      final id = tagFixtureId(_firstPrevious + number - 1);
      database
        ..execute(
          'INSERT INTO intentions (id, title, is_action_ready, is_archived, '
          'created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
          [id, _previousTitle(number), 1, 0, number, number],
        )
        ..execute(
          'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
          [tagFixtureId(_previousTag), id],
        );
    }
  });
  database.execute('COMMIT');
}

String _previousTitle(int number) =>
    'Намерение ${number.toString().padLeft(2, '0')}';

String _replacedTitle(int number) =>
    'Новое ${number.toString().padLeft(2, '0')}';

/// Каталог намерений: все намерения, фильтр названия, условие по тегу,
/// порядок от старых к новым и прокрученные выдача и страница.
Future<void> _prepareIntentionCatalog(WidgetTester tester) async {
  await _select(tester, AppDestination.intentionGraph);
  await _tap(tester, find.byKey(const ValueKey('catalog-scope-control')));
  await tester.tap(find.text(_l10n.catalogScopeAll).last);
  await _settle(tester);
  await tester.enterText(
    find.byKey(const ValueKey('catalog-filter-field')),
    'Намерение',
  );
  await _until(tester, find.text(_l10n.catalogTotalCount(_intentionCount)));
  await _tap(
    tester,
    find.byKey(const ValueKey('intention-tag-conditions-add')),
  );
  await _tap(
    tester,
    find.byKey(
      ValueKey(
        'tag-condition-picker-mustBePresent-${tagFixtureId(_previousTag)}',
      ),
    ),
  );
  await _waitFor(
    tester,
    () => find.byType(TagConditionPickerPage).evaluate().isEmpty,
  );
  await _settle(tester);
  await _tap(tester, find.byKey(const ValueKey('catalog-order-control')));
  await tester.tap(find.text(_l10n.catalogOrderCreatedOldest).last);
  await _settle(tester);
  final list = _catalogPosition(tester);
  list.jumpTo(list.maxScrollExtent / 2);
  final page = _catalogPagePosition(tester);
  page.jumpTo(page.maxScrollExtent / 2);
  await _settle(tester);

  expect(_intentionCatalogParameters(tester), {
    'охват': [_l10n.catalogScopeAll, _l10n.catalogScopeLabel],
    'фильтр названия': 'Намерение',
    'условия по тегам': ['Здоровье'],
    'порядок': [_l10n.catalogOrderCreatedOldest, _l10n.catalogOrderLabel],
    'позиция прокрутки': greaterThan(0),
    'позиция прокрутки страницы': greaterThan(0),
  });
}

/// Каталог дневных выборов: выбран прошлый день, а календарь раскрыт.
Future<void> _prepareDailyChoiceCatalog(WidgetTester tester) async {
  await _select(tester, AppDestination.dailyChoices);
  await selectDailyChoiceCatalogDate(tester, _pastDay, tap: _tap);
  await _settle(tester);
  await expandDailyChoiceCatalogCalendar(tester, tap: _tap);
  await _settle(tester);

  expect(shownDailyChoiceCatalogDate(tester), _pastDay);
  expect(
    shownDailyChoiceCatalogViewport(tester).mode,
    DailyChoiceCalendarMode.month,
  );
}

/// Главная: вкладка «Год», прошлый год и вид «Выбранные действия».
Future<void> _prepareHome(WidgetTester tester, _App app) async {
  await _select(tester, AppDestination.home);
  await _tap(tester, find.text(_l10n.statisticsYearTab));
  await _tap(tester, find.byTooltip(_l10n.statisticsPreviousYear));
  await _tap(tester, find.text(_l10n.statisticsSelectedActions));
  await _settle(tester);

  final home = app.container.read(homeStatisticsViewModelProvider).selection;
  expect(
    (tab: home.tab, period: home.period, view: home.view),
    (
      tab: HomeStatisticsTab.year,
      period: StatisticsYear(2025),
      view: StatisticsView.selectedActions,
    ),
  );
}

/// Заменяет граф операцией координатора: восстановление копии в монопольном
/// режиме завершается изменением «граф заменён». Новый граф — тег «Здоровье»
/// и намерения «Новое 01» … «Новое 40» с этим тегом.
Future<void> _replaceGraph(WidgetTester tester, _App app) async {
  final replacement =
      app.container.read(personalGraphRepositoryProvider) as GraphReplacement;
  final coordinator = app.container.read(
    graphCommandCoordinatorProvider.notifier,
  );
  final snapshot = (await tester.runAsync(
    () => _writeReplacementSnapshot(app.files.snapshots),
  ))!;
  final start = coordinator.acceptBackupRestore(
    (exclusive) => exclusive.replace(
      () => replacement.replaceGraph(
        snapshot,
        onProgress: (_) {},
        cancellation: GraphReplacementCancellation(),
      ),
    ),
  ) as GraphBackupRestoreAccepted;
  GraphBackupRestoreOutcome? outcome;
  unawaited(start.future.then((value) => outcome = value));
  await _waitFor(tester, () => outcome != null);
  expect(outcome, isA<GraphBackupRestored>());
  await _settle(tester);
}

/// Записывает в каталог снимков [directory] снимок замены нового графа, как
/// его записало бы хранилище снимков.
Future<UnregisteredGraphSnapshot> _writeReplacementSnapshot(
  Directory directory,
) async {
  final tagId = tagFixtureId(_replacedTag);
  String intentionId(int number) => tagFixtureId(_firstReplaced + number - 1);
  String moment(int number) =>
      '2026-10-01T06:${number.toString().padLeft(2, '0')}:00.000000Z';
  final counts = GraphRecordCounts(
    tags: 1,
    intentions: _intentionCount,
    tagAssignments: _intentionCount,
    longTermRelations: 0,
    dailyChoices: 0,
  );
  final records = [
    {
      'format': 'doable-graph',
      'version': 1,
      'writtenAt': '2026-10-19T09:00:00.000000Z',
      'counts': {
        'tags': counts.tags,
        'intentions': counts.intentions,
        'tagAssignments': counts.tagAssignments,
        'longTermRelations': counts.longTermRelations,
        'dailyChoices': counts.dailyChoices,
      },
    },
    {'kind': 'tag', 'id': tagId, 'name': 'Здоровье', 'color': null},
    for (var number = 1; number <= _intentionCount; number++)
      {
        'kind': 'intention',
        'id': intentionId(number),
        'title': _replacedTitle(number),
        'description': null,
        'actionReady': true,
        'archived': false,
        'createdAt': moment(number),
        'updatedAt': moment(number),
      },
    for (var number = 1; number <= _intentionCount; number++)
      {
        'kind': 'tagAssignment',
        'tagId': tagId,
        'intentionId': intentionId(number),
      },
  ];
  final bytes = gzip.encode(
    utf8.encode(
      [for (final record in records) '${jsonEncode(record)}\n'].join(),
    ),
  );
  const fileName = 'замена.jsonl.gz';
  await directory.create(recursive: true);
  await File.fromUri(directory.uri.resolve(fileName))
      .writeAsBytes(bytes, flush: true);
  return UnregisteredGraphSnapshot(
    directory: directory,
    fileName: fileName,
    byteSize: bytes.length,
    checksum: Uint8List.fromList(sha256.convert(bytes).bytes),
    counts: counts,
  );
}

/// Параметры и позиция каталога намерений, как их видит человек.
Map<String, Object?> _intentionCatalogParameters(WidgetTester tester) => {
  'охват': _texts(find.byKey(const ValueKey('catalog-scope-control'))),
  'фильтр названия': tester
      .widget<TextField>(find.byKey(const ValueKey('catalog-filter-field')))
      .controller!
      .text,
  'условия по тегам': [
    for (final label
        in find
            .descendant(
              of: find.byType(IntentionCatalogPage),
              matching: find.byKey(
                const ValueKey('intention-tag-condition-label'),
              ),
            )
            .evaluate())
      textIgnoringInlineWidgets(label.widget as Text),
  ],
  'порядок': _texts(find.byKey(const ValueKey('catalog-order-control'))),
  'позиция прокрутки': _catalogPosition(tester).pixels,
  'позиция прокрутки страницы': _catalogPagePosition(tester).pixels,
};

/// Видимые тексты элемента [finder] в порядке дерева.
List<String?> _texts(Finder finder) => [
  for (final element
      in find.descendant(of: finder, matching: find.byType(Text)).evaluate())
    (element.widget as Text).data,
];

ScrollPosition _positionOf(WidgetTester tester, Finder scrollView) => tester
    .state<ScrollableState>(
      find.descendant(of: scrollView, matching: find.byType(Scrollable)).first,
    )
    .position;

/// Позиция прокрутки выдачи каталога намерений.
ScrollPosition _catalogPosition(WidgetTester tester) => _positionOf(
  tester,
  find.byKey(const PageStorageKey<String>('intention-catalog-list')),
);

/// Позиция прокрутки страницы каталога намерений: параметры поиска и выдача
/// прокручиваются вместе.
ScrollPosition _catalogPagePosition(WidgetTester tester) => _positionOf(
  tester,
  find.descendant(
    of: find.byType(IntentionCatalogPage),
    matching: find.byType(CustomScrollView),
  ),
);

AppDestination _selected(WidgetTester tester) =>
    tester.widget<AppNavigationBar>(find.byType(AppNavigationBar)).selected;

/// Корневая страница каждого пункта.
const _rootPages = {
  AppDestination.home: HomePage,
  AppDestination.dailyChoices: DailyChoiceCatalogPage,
  AppDestination.intentionGraph: IntentionCatalogPage,
};

/// Выбирает пункт панели и ждёт его корневую страницу.
Future<void> _select(WidgetTester tester, AppDestination destination) async {
  await tester.tap(appNavigationDestination(destination));
  await _until(tester, find.byType(_rootPages[destination]!));
  await _settle(tester);
}

/// Нажимает [entry] и ждёт, пока страница [page] откроется целиком.
Future<void> _open(WidgetTester tester, Finder entry, Type page) async {
  await _tap(tester, entry);
  await _until(tester, find.byType(page));
  await tester.pumpAndSettle();
}

/// Закрывает верхнюю страницу системным действием «назад».
Future<void> _closeTop(WidgetTester tester, Type page) async {
  await tester.binding.handlePopRoute();
  await _waitFor(tester, () => find.byType(page).evaluate().isEmpty);
  await _settle(tester);
}

/// Даёт хранилищу завершить начатые обращения и дожидается покоя кадров.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pumpAndSettle();
}

Future<void> _until(WidgetTester tester, Finder finder) =>
    _waitFor(tester, () => finder.evaluate().isNotEmpty);

/// Чередует реальное ожидание хранилища с кадрами, пока не выполнится [done].
Future<void> _waitFor(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 100 && !done(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _until(tester, finder);
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}
