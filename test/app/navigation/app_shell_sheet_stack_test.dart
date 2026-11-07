import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/home/home_page.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/action/presentation/day/action_day_root_page.dart';
import 'package:doable/src/data/local/app_database.dart'
    show openInMemoryLocalDatabase;
import 'package:doable/src/design_system/components/empty_state.dart';
import 'package:doable/src/design_system/components/page_head.dart';
import 'package:doable/src/design_system/components/relation_head.dart';
import 'package:doable/src/design_system/components/relation_row.dart';
import 'package:doable/src/design_system/components/sheet.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/app_root_pages.dart';
import '../../support/graph_seed.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/in_memory_quick_creation_mode_store.dart';
import '../../support/quick_creation.dart';
import '../../support/tag_storage_fixture.dart';

/// Намерение страницы, над которой открыта панель связи, и страницы, которую
/// открывает лист над корневым экраном дня.
const _origin = 1;

/// Намерение страницы, которую панель открывает поверх себя.
const _other = 2;

/// Связь «чтобы другое, нужно исходное», которую открывает панель на странице
/// исходного намерения: главное намерение открывается на группе
/// «Нужно для».
const _relation = 10;

const _originTitle = 'Исходное';
const _otherTitle = 'Другое';
const _createdTitle = 'Созданное';

const _catalogSheetTitle = 'Лист над каталогом';
const _openPageLabel = 'Открыть страницу';
const _countLabel = 'Счёт';

final _l10n = lookupAppLocalizations(const Locale('en'));

void main() {
  for (final (name, back) in [
    ('кнопка «Назад»', _tapBackButton),
    ('системное «назад»', _systemBack),
  ]) {
    testWidgets('$name со страницы над панелью связи возвращает ту же панель '
        'с её состоянием, а следующее «назад» показывает исходную страницу', (
      tester,
    ) async {
      await _openPageAboveSheet(tester, await _start(tester));

      await back(tester);

      expect(_descriptionSave.hitTestable(), findsOneWidget);
      expect(_shownIntention(tester), _originTitle);

      await _systemBack(tester);

      expect(_allSheets, findsNothing);
      expect(_allIntentionPages, findsOneWidget);
      expect(_shownIntention(tester), _originTitle);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('выбор пункта панели навигации на странице над панелью связи '
      'убирает страницы и панель из истории', (tester) async {
    final router = await _start(tester);
    await _openPageAboveSheet(tester, router);

    await tester.tap(appNavigationDestination(AppDestination.intentionGraph));
    await _until(tester, find.byType(IntentionCatalogPage));
    await tester.pumpAndSettle();

    expect(_allSheets, findsNothing);
    expect(_allIntentionPages, findsNothing);
    expect(
      tester.widget<AppNavigationBar>(find.byType(AppNavigationBar)).selected,
      AppDestination.intentionGraph,
    );

    await _systemBack(tester);

    expect(find.byType(HomePage), findsOneWidget);
    expect(router.canPop(), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('быстрое создание на странице над панелью связи запускается, а '
      'возврат с созданного намерения ведёт на неё и затем на панель', (
    tester,
  ) async {
    await _openPageAboveSheet(tester, await _start(tester));

    await openQuickCreation(
      tester,
      QuickCreationMode.intention,
      openedPage: find.byType(IntentionEditorPage),
      wait: _until,
    );
    await tester.enterText(
      find.byKey(const ValueKey('intention-editor-title')),
      _createdTitle,
    );
    await tester.tap(find.byKey(const ValueKey('intention-editor-submit')));
    await _waitFor(
      tester,
      () => find.byType(IntentionEditorPage).evaluate().isEmpty,
    );
    await tester.pumpAndSettle();
    expect(_shownIntention(tester), _createdTitle);

    await _systemBack(tester);

    expect(_shownIntention(tester), _otherTitle);

    await _systemBack(tester);

    expect(_descriptionSave.hitTestable(), findsOneWidget);
    expect(_shownIntention(tester), _originTitle);
    expect(tester.takeException(), isNull);
  });

  for (final (name, back) in [
    ('кнопка «Назад»', _tapBackButton),
    ('системное «назад»', _systemBack),
  ]) {
    testWidgets('$name со страницы над листом, открытым над корневым каталогом '
        'действий, возвращает тот же лист с его состоянием, а '
        'следующее «назад» показывает каталог', (tester) async {
      final router = await _start(tester);
      await _openPageAboveCatalogSheet(tester, router);

      await back(tester);

      expect(find.text('$_countLabel: 1').hitTestable(), findsOneWidget);
      expect(_allIntentionPages, findsNothing);

      await _systemBack(tester);

      expect(_allSheets, findsNothing);
      expect(_allIntentionPages, findsNothing);
      expectActionsRootPage(router);
      expect(find.byType(ActionDayRootPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('выбор пункта панели навигации на странице над листом, '
      'открытым над корневым экраном дня, убирает из истории '
      'и страницу, и лист', (tester) async {
    final router = await _start(tester);
    await _openPageAboveCatalogSheet(tester, router);

    await tester.tap(appNavigationDestination(AppDestination.intentionGraph));
    await _until(tester, find.byType(IntentionCatalogPage));
    await tester.pumpAndSettle();

    expect(_allSheets, findsNothing);
    expect(_allIntentionPages, findsNothing);
    expectIntentionGraphRootPage(router);

    await _systemBack(tester);

    expect(_allSheets, findsNothing);
    expect(_allIntentionPages, findsNothing);
    expect(router.canPop(), isFalse);
    expect(tester.takeException(), isNull);
  });
}

/// Панель вместе с закрытой страницей над ней.
final _allSheets = find.byType(Sheet, skipOffstage: false);

/// Кнопка сохранения описания: есть только у панели, открытой на изменении
/// описания.
final _descriptionSave = find.text(_l10n.relationSheetDescriptionSave);

/// Страницы намерений вместе с закрытыми страницей над ними.
final _allIntentionPages = find.byType(
  IntentionDetailsPage,
  skipOffstage: false,
);

/// Шапка верхней страницы намерения, которая появляется после загрузки.
final _intentionTitle = find.byKey(const ValueKey('intention-details-title'));

/// Название намерения на верхней странице.
String _shownIntention(WidgetTester tester) =>
    tester.widget<PageHead>(_intentionTitle).name;

IntentionId _intentionId(int number) =>
    (IntentionId.decode(tagFixtureId(number)) as IntentionIdDecodingSuccess).id;

/// Открывает над страницей [_origin] панель её связи, открывает в панели
/// изменение описания и переходит из панели на страницу [_other], которая
/// встаёт над панелью.
Future<void> _openPageAboveSheet(WidgetTester tester, AppRouter router) async {
  unawaited(
    router.push(IntentionDetailsRoute(intentionId: _intentionId(_origin))),
  );
  await _until(tester, find.byType(IntentionDetailsPage));
  await _until(tester, _intentionTitle);
  await tester.pumpAndSettle();

  await _tap(tester, find.text('Relations').first);
  await _tap(tester, _relationRow);
  await _until(tester, find.byType(RelationHead));
  await tester.pumpAndSettle();
  expect(_allSheets, findsOneWidget);

  // Изменение описания отличает ту же панель от построенной заново.
  await _tap(tester, find.text(_l10n.detailsAddDescription));
  await tester.pumpAndSettle();
  expect(_descriptionSave, findsOneWidget);
  await _tap(
    tester,
    find.descendant(
      of: find.byType(RelationHead),
      matching: find.text(_otherTitle),
    ),
  );
  await _waitFor(tester, () => _allIntentionPages.evaluate().length == 2);
  await _until(tester, _intentionTitle);
  await tester.pumpAndSettle();

  expect(_shownIntention(tester), _otherTitle);
  expect(find.byType(Sheet), findsNothing);
  expect(_allSheets, findsOneWidget);
  expect(appNavigationDestinations().hitTestable(), findsExactly(3));
}

/// Открывает экран дня корневой страницей, показывает над ним лист
/// с состоянием «Счёт: 1» и открывает из листа страницу намерения [_origin],
/// которая встаёт над листом.
Future<void> _openPageAboveCatalogSheet(
  WidgetTester tester,
  AppRouter router,
) async {
  await openActions(tester);
  // Пустой день показан, когда первая загрузка закончилась и ничто не движется.
  await _until(tester, find.byType(EmptyState));
  await tester.pumpAndSettle();
  expectActionsRootPage(router);

  unawaited(
    showDoableSheet<void>(
      context: tester.element(find.byType(ActionDayRootPage)),
      builder: (_, presentation) => Sheet(
        presentation,
        title: _catalogSheetTitle,
        child: _CountingSheetBody(intentionId: _intentionId(_origin)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(_allSheets, findsOneWidget);

  // Состояние отличает тот же лист от построенного заново.
  await _tap(tester, find.text('$_countLabel: 0'));
  await tester.pumpAndSettle();
  expect(find.text('$_countLabel: 1'), findsOneWidget);
  await _tap(tester, find.text(_openPageLabel));
  await _waitFor(tester, () => _allIntentionPages.evaluate().length == 1);
  await _until(tester, _intentionTitle);
  await tester.pumpAndSettle();

  expect(_shownIntention(tester), _originTitle);
  expect(find.byType(Sheet), findsNothing);
  expect(_allSheets, findsOneWidget);
  expect(appNavigationDestinations().hitTestable(), findsExactly(3));
}

/// Тело листа над каталогом: считает нажатия и открывает страницу намерения
/// через `context.router.push`, как шаг пути панели выбора.
final class _CountingSheetBody extends StatefulWidget {
  const _CountingSheetBody({required this.intentionId});

  final IntentionId intentionId;

  @override
  State<_CountingSheetBody> createState() => _CountingSheetBodyState();
}

final class _CountingSheetBodyState extends State<_CountingSheetBody> {
  var _count = 0;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      TextButton(
        onPressed: () => setState(() => _count++),
        child: Text('$_countLabel: $_count'),
      ),
      TextButton(
        onPressed: () => unawaited(
          context.router.push(
            IntentionDetailsRoute(intentionId: widget.intentionId),
          ),
        ),
        child: const Text(_openPageLabel),
      ),
    ],
  );
}

/// Строка связи на вкладке «Связи» страницы [_origin].
final _relationRow = find.byWidgetPredicate(
  (widget) => widget is RelationRow,
  description: 'строка связи',
);

/// Запускает приложение на засеянном хранилище и ждёт Главную.
Future<AppRouter> _start(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  tester.binding.platformDispatcher.localesTestValue = const [Locale('en')];
  addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
  // Высокий экран строит строку связи без прокрутки вкладки.
  tester.view.physicalSize = const Size(1200, 6000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  late sqlite.Database raw;
  final runtime = AppRuntime(
    quickCreationModeStore: InMemoryQuickCreationModeStore(),
    connectionFactory: () =>
        openInMemoryLocalDatabase(setup: (database) => raw = database),
    diagnosticsSink: InMemoryDiagnosticsSink(),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await runtime.shutdown();
  });
  final ready = (await tester.runAsync(runtime.bootstrap)) as AppRuntimeReady;
  seedRawGraph(raw, () {
    for (final (number, title) in [
      (_origin, _originTitle),
      (_other, _otherTitle),
    ]) {
      raw.execute(
        'INSERT INTO intentions (id, title, kind, is_archived, '
        'created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
        [tagFixtureId(number), title, 'main', 0, number, number],
      );
    }
    raw.execute(
      'INSERT INTO long_term_relations (id, source_intention_id, '
      'related_intention_id, type, priority, is_archived, created_at, '
      'updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [
        tagFixtureId(_relation),
        tagFixtureId(_other),
        tagFixtureId(_origin),
        'need',
        2,
        0,
        _relation,
        _relation,
      ],
    );
  });
  await tester.pumpWidget(MainApp(runtime: runtime));
  await _until(tester, find.byType(HomePage));
  await _waitFor(
    tester,
    () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
  );
  await tester.pumpAndSettle();
  return ready.container.read(appRouterProvider);
}

Future<void> _tapBackButton(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('Back'));
  await tester.pumpAndSettle();
}

Future<void> _systemBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

Future<void> _until(WidgetTester tester, Finder finder) =>
    _waitFor(tester, () => finder.evaluate().isNotEmpty);

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
  await tester.tap(finder);
  await tester.pump();
}
