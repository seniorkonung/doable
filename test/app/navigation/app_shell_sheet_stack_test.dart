import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/home/home_page.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/data/local/app_database.dart'
    show openInMemoryLocalDatabase;
import 'package:doable/src/design_system/components/page_head.dart';
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

/// Намерение страницы, над которой открыт лист.
const _origin = 1;

/// Намерение страницы, которую лист открывает поверх себя.
const _other = 2;

const _originTitle = 'Исходное';
const _otherTitle = 'Другое';
const _createdTitle = 'Созданное';

void main() {
  for (final (name, back) in [
    ('кнопка «Назад»', _tapBackButton),
    ('системное «назад»', _systemBack),
  ]) {
    testWidgets('$name со страницы над листом возвращает тот же лист с его '
        'состоянием, а следующее «назад» показывает исходную страницу', (
      tester,
    ) async {
      await _openPageAboveSheet(tester, await _start(tester));

      await back(tester);

      expect(find.text('Нажатий: 1').hitTestable(), findsOneWidget);
      expect(_shownIntention(tester), _originTitle);

      await _systemBack(tester);

      expect(_allSheets, findsNothing);
      expect(_allIntentionPages, findsOneWidget);
      expect(_shownIntention(tester), _originTitle);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('выбор пункта панели на странице над листом убирает страницы и '
      'лист из истории', (tester) async {
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

  testWidgets('быстрое создание на странице над листом запускается, а возврат '
      'с созданного намерения ведёт на неё и затем на лист', (tester) async {
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

    expect(find.text('Нажатий: 1').hitTestable(), findsOneWidget);
    expect(_shownIntention(tester), _originTitle);
    expect(tester.takeException(), isNull);
  });
}

/// Лист вместе с закрытым страницей над ним.
final _allSheets = find.byType(Sheet, skipOffstage: false);

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

/// Открывает над страницей [_origin] лист, меняет его состояние и переходит
/// из листа на страницу [_other], которая встаёт над листом.
Future<void> _openPageAboveSheet(WidgetTester tester, AppRouter router) async {
  unawaited(
    router.push(IntentionDetailsRoute(intentionId: _intentionId(_origin))),
  );
  await _until(tester, find.byType(IntentionDetailsPage));
  await _until(tester, _intentionTitle);
  await tester.pumpAndSettle();

  unawaited(
    showDoableSheet<void>(
      context: tester.element(find.byType(IntentionDetailsPage)),
      builder: (_, sheet) =>
          Sheet(sheet, title: 'Лист', child: const _SheetBody()),
    ),
  );
  await _tap(tester, find.text('Нажатий: 0'));
  await tester.pumpAndSettle();
  await _tap(tester, find.text('Открыть другое намерение'));
  await _waitFor(tester, () => _allIntentionPages.evaluate().length == 2);
  await _until(tester, _intentionTitle);
  await tester.pumpAndSettle();

  expect(_shownIntention(tester), _otherTitle);
  expect(find.byType(Sheet), findsNothing);
  expect(_allSheets, findsOneWidget);
  expect(appNavigationDestinations().hitTestable(), findsExactly(3));
}

/// Тело листа с собственным состоянием: счётчик отличает тот же лист от
/// построенного заново.
final class _SheetBody extends StatefulWidget {
  const _SheetBody();

  @override
  State<_SheetBody> createState() => _SheetBodyState();
}

final class _SheetBodyState extends State<_SheetBody> {
  var _presses = 0;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      TextButton(
        onPressed: () => setState(() => _presses += 1),
        child: Text('Нажатий: $_presses'),
      ),
      TextButton(
        onPressed: () => unawaited(
          context.router.push(
            IntentionDetailsRoute(intentionId: _intentionId(_other)),
          ),
        ),
        child: const Text('Открыть другое намерение'),
      ),
    ],
  );
}

/// Запускает приложение на засеянном хранилище и ждёт Главную.
Future<AppRouter> _start(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  tester.binding.platformDispatcher.localesTestValue = const [Locale('en')];
  addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
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
        'INSERT INTO intentions (id, title, is_action_ready, is_archived, '
        'created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
        [tagFixtureId(number), title, 1, 0, number, number],
      );
    }
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
