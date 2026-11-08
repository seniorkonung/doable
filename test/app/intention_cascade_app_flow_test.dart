import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/action/application/action_day.dart';
import 'package:doable/src/action/presentation/path/path_page.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/design_system/components/archived_fold.dart';
import 'package:doable/src/design_system/components/catalog_header.dart';
import 'package:doable/src/design_system/components/page_head.dart';
import 'package:doable/src/design_system/components/relation_row.dart';
import 'package:doable/src/design_system/components/segmented_control.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/components/sheet.dart';
import 'package:doable/src/intention/application/intention_catalog.dart'
    show IntentionKindFilter;
import 'package:doable/src/intention/application/intention_holding.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_row.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/details/intention_options.dart';
import 'package:doable/src/intention/presentation/picker/intention_picker_row.dart';
import 'package:doable/src/long_term_relation/application/intention_relation_group.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/action_day_controls.dart';
import '../support/action_panel_controls.dart';
import '../support/action_panel_edit_controls.dart';
import '../support/action_seed.dart';
import '../support/app_root_pages.dart';
import '../support/controlled_local_date.dart';
import '../support/graph_seed.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/in_memory_quick_creation_mode_store.dart';
import '../support/intention_catalog_controls.dart';
import '../support/intention_options.dart';
import '../support/local_database_harness.dart';
import '../support/path_screen_controls.dart';

const _healthy = 'Быть здоровым';
const _walk = 'Много ходить';
const _shoes = 'Хорошая обувь';
const _sleep = 'Высыпаться';
const _hike = 'Сходить в поход';
const _warmUp = 'Разминка';
const _stretch = 'Растяжка';

final _today = CalendarDate.fromParts(2026, 10, 8);
final _l10n = lookupAppLocalizations(const Locale('ru'));

void main() {
  testWidgets('Открытый каталог согласуется с ушедшими каскадом намерениями', (
    tester,
  ) async {
    await _launch(tester, _seedHealthyGraph);
    await openIntentionGraph(tester, waitFor: _pumpUntilFound);
    await selectIntentionCatalogKind(
      tester,
      IntentionKindFilter.mainAndSupporting,
    );
    await _pumpUntilFound(tester, intentionCatalogRow(_walk));
    expect(intentionCatalogTotal(5), findsOneWidget);

    await _openFromCatalog(tester, _healthy);
    await _chooseOption(tester, IntentionOption.archive);
    await _tapWhenFound(tester, find.text(_l10n.detailsCascadeWithSupporting));
    await _pumpUntilFound(
      tester,
      find.textContaining(_l10n.cascadeArchiveIntentionSupporting(1)),
    );
    await _back(tester);

    await _pumpUntilAbsent(tester, intentionCatalogRow(_healthy));
    expect(intentionCatalogRow(_walk), findsNothing);
    expect(intentionCatalogTotal(3), findsOneWidget);
    await _pumpUntilHolding(tester, _shoes, IntentionHolding.held);
  });

  testWidgets('каскад восстановления возвращает намерения в открытый каталог, '
      'меняет метки удержания и согласует открытые страницы', (tester) async {
    await _launch(tester, _seedRestorableGraph);
    await openIntentionGraph(tester, waitFor: _pumpUntilFound);
    await selectIntentionCatalogKind(
      tester,
      IntentionKindFilter.mainAndSupporting,
    );
    await _pumpUntilHolding(tester, _warmUp, IntentionHolding.notHeld);
    await _pumpUntilHolding(tester, _stretch, IntentionHolding.notHeld);
    expect(intentionCatalogTotal(2), findsOneWidget);

    await _openFromCatalog(tester, _warmUp);
    expect(_relationCounts(active: 2, archived: 1), findsOneWidget);
    await _walkToIncomingArchived(tester, _walk);
    await _walkToIncomingArchived(tester, _healthy);
    await _tapWhenFound(tester, intentionHeadRestore);
    await _tapWhenFound(tester, find.text(_l10n.detailsCascadeWithSupporting));
    await _pumpUntilFound(
      tester,
      find.textContaining(_l10n.cascadeRestoreIntentionSupporting(1)),
    );
    await _pumpUntilHeadMuted(tester, muted: false);

    await _back(tester);
    await _pumpUntilDetailsTitle(tester, _walk);
    await _pumpUntilHeadMuted(tester, muted: false);
    await _pumpUntilFound(tester, _relationCounts(active: 2, archived: 0));
    await _pumpUntilKind(tester, IntentionKind.supporting);

    await _back(tester);
    await _pumpUntilDetailsTitle(tester, _warmUp);
    await _pumpUntilFound(tester, _relationCounts(active: 3, archived: 0));

    await _back(tester);
    await _pumpUntilFound(tester, intentionCatalogRow(_healthy));
    expect(intentionCatalogRow(_walk), findsOneWidget);
    expect(intentionCatalogTotal(4), findsOneWidget);
    await _pumpUntilHolding(tester, _warmUp, IntentionHolding.held);
    await _pumpUntilHolding(tester, _stretch, IntentionHolding.held);
  });

  testWidgets('каскад восстановления возвращает намерения в открытый поиск '
      'для выбора связи и меняет метки удержания', (tester) async {
    await _launch(tester, (db) {
      _seedRestorableGraph(db);
      _intention(db, 4, _sleep);
    });
    await openIntentionGraph(tester, waitFor: _pumpUntilFound);
    await _openFromCatalog(tester, _sleep);
    await _chooseDetailsTab(tester);
    await _tapWhenFound(
      tester,
      _onTopPage(find.byKey(const ValueKey('intention-relations-add'))),
    );
    await _pumpUntilFound(tester, _pickerRow(_warmUp));
    await _pumpUntilPickerHolding(tester, _warmUp, IntentionHolding.notHeld);
    await _pumpUntilPickerHolding(tester, _stretch, IntentionHolding.notHeld);
    expect(_pickerCount(tester), 2);

    await tester.pumpAndSettle(const Duration(milliseconds: 1));
    await tester.tap(
      find.descendant(
        of: _pickerRow(_warmUp),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is DoableIcon &&
              widget.icon == DoableIconData.arrowUpRight,
        ),
      ),
    );
    await _pumpUntilDetailsTitle(tester, _warmUp);
    await _walkToIncomingArchived(tester, _walk);
    await _walkToIncomingArchived(tester, _healthy);
    await _tapWhenFound(tester, intentionHeadRestore);
    await _tapWhenFound(tester, find.text(_l10n.detailsCascadeWithSupporting));
    await _pumpUntilFound(
      tester,
      find.textContaining(_l10n.cascadeRestoreIntentionSupporting(1)),
    );
    await _back(tester);
    await _back(tester);
    await _back(tester);

    await _pumpUntilFound(tester, _pickerRow(_healthy));
    expect(_pickerRow(_walk), findsOneWidget);
    expect(_pickerCount(tester), 4);
    await _pumpUntilPickerHolding(tester, _warmUp, IntentionHolding.held);
    await _pumpUntilPickerHolding(tester, _stretch, IntentionHolding.held);
  });

  testWidgets('архивирование со вспомогательными показывает новое состояние и '
      'счётчики на открытых страницах затронутых намерений', (tester) async {
    await _launch(tester, _seedHealthyGraph);
    await openIntentionGraph(tester, waitFor: _pumpUntilFound);
    await _openFromCatalog(tester, _sleep);
    expect(_relationCounts(active: 1, archived: 0), findsOneWidget);
    await _walkToIncoming(tester, _walk);
    expect(_relationCounts(active: 3, archived: 0), findsOneWidget);
    await _walkToIncoming(tester, _healthy);

    await _chooseOption(tester, IntentionOption.archive);
    await _tapWhenFound(tester, find.text(_l10n.detailsCascadeWithSupporting));
    await _pumpUntilFound(
      tester,
      find.textContaining(_l10n.cascadeArchiveIntentionSupporting(1)),
    );
    await _pumpUntilHeadMuted(tester, muted: true);

    await _back(tester);
    await _pumpUntilDetailsTitle(tester, _walk);
    await _pumpUntilHeadMuted(tester, muted: true);
    await _pumpUntilFound(tester, _relationCounts(active: 0, archived: 3));

    await _back(tester);
    await _pumpUntilDetailsTitle(tester, _sleep);
    await _pumpUntilHeadMuted(tester, muted: false);
    await _pumpUntilFound(tester, _relationCounts(active: 0, archived: 1));
  });

  testWidgets('удаление со вспомогательными сообщает об отсутствии намерения '
      'на его открытой странице и связи в её открытой панели', (tester) async {
    await _launch(tester, _seedHealthyGraph);
    await openIntentionGraph(tester, waitFor: _pumpUntilFound);
    await _openFromCatalog(tester, _sleep);
    await _chooseDetailsTab(tester);
    await _selectGroup(tester, IntentionRelationGroup.neededFor);
    final phrase = _l10n.relationNeighborhoodNeedPhrase(_walk, _sleep);
    await _tapWhenFound(tester, _relationRow(phrase));
    await _pumpUntilFound(tester, find.bySemanticsLabel(phrase));
    await tester.pumpAndSettle(const Duration(milliseconds: 1));
    await _tapWhenFound(
      tester,
      find.descendant(
        of: _relationSheet,
        matching: find.bySemanticsLabel(
          _l10n.relationSheetOpenParticipant(_walk),
        ),
      ),
    );
    await _pumpUntilDetailsTitle(tester, _walk);
    await _walkToIncoming(tester, _healthy);

    await _chooseOption(tester, IntentionOption.delete);
    await _tapWhenFound(tester, find.text(_l10n.detailsDeleteCount(2)));
    await _pumpUntilFound(
      tester,
      find.textContaining(_l10n.cascadeDeleteIntentionSupporting(1)),
    );
    await _pumpUntilFound(tester, find.text(_l10n.detailsNotFound));
    expect(find.byType(PageHead), findsNothing);

    await _back(tester);
    await _pumpUntilFound(
      tester,
      find.descendant(
        of: _relationSheet,
        matching: find.text(_l10n.relationDetailsNotFound),
      ),
    );

    await _back(tester);
    await _pumpUntilAbsent(tester, _relationSheet);
    await _pumpUntilDetailsTitle(tester, _sleep);
    await _pumpUntilFound(tester, _relationCounts(active: 0, archived: 0));
  });

  testWidgets('удаление «только это» показывает ставшее главным намерение на '
      'его открытой странице', (tester) async {
    await _launch(tester, _seedHealthyGraph);
    await openIntentionGraph(tester, waitFor: _pumpUntilFound);
    await selectIntentionCatalogKind(
      tester,
      IntentionKindFilter.mainAndSupporting,
    );
    await _pumpUntilFound(tester, intentionCatalogRow(_walk));
    await _openFromCatalog(tester, _walk);
    await _pumpUntilKind(tester, IntentionKind.supporting);
    await _walkToIncoming(tester, _healthy);

    await _chooseOption(tester, IntentionOption.delete);
    await _tapWhenFound(tester, find.text(_l10n.detailsCascadeOnlyThis));
    await _pumpUntilFound(
      tester,
      find.textContaining(_l10n.cascadeDeleteIntentionPromoted(1)),
    );

    await _pumpUntilDetailsTitle(tester, _walk);
    await _pumpUntilFound(tester, _relationCounts(active: 2, archived: 0));
    await _pumpUntilKind(tester, IntentionKind.main);
  });

  testWidgets('каскад, который уносит начало пути, сокращает путь на открытом '
      'экране пути до пустого', (tester) async {
    await _launch(tester, (db) {
      _seedHealthyGraph(db);
      seedAction(
        db,
        id: seedUuid(201),
        path: [seedUuid(2), seedUuid(3)],
        date: _today.toCanonicalString(),
      );
    });
    await openActions(tester, tap: _tapWhenFound);
    await showActionDaySection(tester, ActionDaySection.incomplete);
    await _tapWhenFound(tester, find.byKey(const ValueKey('action-day-row-1')));
    await _pumpUntilFound(tester, actionPanelReady);
    await tester.pumpAndSettle(const Duration(milliseconds: 1));
    await openActionPanelPathEdit(tester, tap: _tapWhenFound);
    await _pumpUntilFound(
      tester,
      find.descendant(of: pathScreen, matching: find.text(_shoes)),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 1));

    await tester.tap(
      find.descendant(
        of: pathScreen,
        matching: find.byTooltip(_l10n.intentionPickerOpenIntentionPage(_walk)),
      ),
    );
    await _pumpUntilDetailsTitle(tester, _walk);
    await _walkToIncoming(tester, _healthy);
    await _chooseOption(tester, IntentionOption.archive);
    await _tapWhenFound(tester, find.text(_l10n.detailsCascadeWithSupporting));
    await _pumpUntilFound(
      tester,
      find.textContaining(_l10n.cascadeArchiveIntentionSupporting(1)),
    );

    await _back(tester);
    await _back(tester);
    await _pumpUntilFound(
      tester,
      find.descendant(
        of: pathScreen,
        matching: find.text(_l10n.pathChooseReason),
      ),
    );
    expect(
      find.descendant(of: pathScreen, matching: find.text(_walk)),
      findsNothing,
    );
    expect(
      find.descendant(of: pathScreen, matching: find.text(_shoes)),
      findsNothing,
    );
    expect(find.byType(PathPage), findsOneWidget);
  });
}

/// Граф требований каскада: главному «Быть здоровым» нужно вспомогательное
/// «Много ходить», которому нужны вспомогательная «Хорошая обувь» и главное
/// «Высыпаться»; «Хорошую обувь» удерживает и главное «Сходить в поход».
void _seedHealthyGraph(sqlite.Database db) {
  _intention(db, 1, _healthy);
  _intention(db, 2, _walk, supporting: true);
  _intention(db, 3, _shoes, supporting: true);
  _intention(db, 4, _sleep);
  _intention(db, 5, _hike);
  _relation(db, 101, 1, 2);
  _relation(db, 102, 2, 3);
  _relation(db, 103, 2, 4);
  _relation(db, 104, 5, 3);
}

/// Архивные главное «Быть здоровым» и вспомогательное «Много ходить», которому
/// архивной связью нужна «Разминка»; активные вспомогательные «Разминка» и
/// «Растяжка» нужны только друг другу, и их ничто не удерживает.
void _seedRestorableGraph(sqlite.Database db) {
  _intention(db, 1, _healthy, archived: true);
  _intention(db, 2, _walk, supporting: true, archived: true);
  _intention(db, 6, _warmUp, supporting: true);
  _intention(db, 7, _stretch, supporting: true);
  _relation(db, 101, 1, 2, archived: true);
  _relation(db, 105, 6, 7);
  _relation(db, 106, 7, 6);
  _relation(db, 107, 2, 6, archived: true);
}

void _intention(
  sqlite.Database db,
  int number,
  String title, {
  bool supporting = false,
  bool archived = false,
}) => db.execute(
  'INSERT INTO intentions (id, title, kind, is_archived, created_at, '
  'updated_at) VALUES (?, ?, ?, ?, 1, 1)',
  [seedUuid(number), title, supporting ? 'supporting' : 'main', archived],
);

/// Связь «нужно» с приоритетом P1.
void _relation(
  sqlite.Database db,
  int number,
  int source,
  int related, {
  bool archived = false,
}) => db.execute(
  '''INSERT INTO long_term_relations
     (id, source_intention_id, related_intention_id, type, priority,
      is_archived, created_at, updated_at)
     VALUES (?, ?, ?, 'need', 1, ?, 1, 1)''',
  [seedUuid(number), seedUuid(source), seedUuid(related), archived],
);

/// Заполняет файловый граф [seed] и запускает приложение над ним.
Future<void> _launch(
  WidgetTester tester,
  void Function(sqlite.Database db) seed,
) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  tester.binding.platformDispatcher.localesTestValue = const [Locale('ru')];
  addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final storage = (await tester.runAsync(LocalDatabaseHarness.fileBacked))!;
  late sqlite.Database raw;
  await storage.openReadyDatabase(setup: (database) => raw = database);
  seedRawGraph(raw, () => seed(raw));
  await storage.closePersistenceObjectGraph();
  final runtime = AppRuntime(
    quickCreationModeStore: InMemoryQuickCreationModeStore(),
    connectionFactory: () => openFileBackedLocalDatabase(storage.databaseFile),
    diagnosticsSink: InMemoryDiagnosticsSink(),
    localDateSource: ControlledLocalDate(_today).read,
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await runtime.shutdown();
    await storage.dispose();
  });
  await tester.pumpWidget(MainApp(runtime: runtime));
}

Future<void> _openFromCatalog(WidgetTester tester, String title) async {
  final row = intentionCatalogRow(title);
  await _pumpUntilFound(tester, row);
  await tester.ensureVisible(row);
  await tester.pumpAndSettle(const Duration(milliseconds: 1));
  await tester.tap(row);
  await _pumpUntilDetailsTitle(tester, title);
}

/// Переходит со страницы на страницу соседа [title] по активной входящей
/// связи «нужно».
Future<void> _walkToIncoming(WidgetTester tester, String title) async {
  await _chooseDetailsTab(tester);
  await _selectGroup(tester, IntentionRelationGroup.neededFor);
  await _walkTo(tester, title);
}

/// Переходит на страницу соседа [title] по архивной входящей связи «нужно».
/// Архивы групп архивного намерения раскрыты сразу, у активного — по нажатию.
Future<void> _walkToIncomingArchived(WidgetTester tester, String title) async {
  await _chooseDetailsTab(tester);
  await _selectGroup(tester, IntentionRelationGroup.neededFor);
  final fold = _onTopPage(find.byType(ArchivedFold));
  await _pumpUntilFound(tester, fold);
  if (!tester.widget<ArchivedFold>(fold).open) {
    final toggle = find.descendant(of: fold, matching: find.byType(TextButton));
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle(const Duration(milliseconds: 1));
    await tester.tap(toggle);
    await tester.pump();
  }
  await _walkTo(tester, title);
}

Future<void> _walkTo(WidgetTester tester, String title) async {
  final walk = _onTopPage(
    find.bySemanticsLabel(_l10n.detailsRelationsWalkIntention(title)),
  );
  await _pumpUntilFound(tester, walk);
  await tester.ensureVisible(walk);
  await tester.pumpAndSettle(const Duration(milliseconds: 1));
  await tester.tap(walk);
  await _pumpUntilDetailsTitle(tester, title);
}

Future<void> _chooseDetailsTab(WidgetTester tester) async {
  final tab = _onTopPage(find.text(_l10n.detailsRelationsTab));
  await _pumpUntilFound(tester, tab);
  await tester.tap(tab.first);
  await tester.pump();
}

Future<void> _selectGroup(
  WidgetTester tester,
  IntentionRelationGroup group,
) async {
  final key = _onTopPage(
    find.byKey(ValueKey('intention-relations-group-${group.name}')),
  );
  await _pumpUntilFound(tester, key);
  await tester.ensureVisible(key);
  await tester.pumpAndSettle(const Duration(milliseconds: 1));
  await tester.tap(key);
  await tester.pumpAndSettle(const Duration(milliseconds: 1));
}

/// Выбирает пункт [option] в листе «Намерение» верхней страницы.
Future<void> _chooseOption(WidgetTester tester, IntentionOption option) async {
  await tester.pumpAndSettle(const Duration(milliseconds: 1));
  await _tapWhenFound(tester, _onTopPage(intentionOptionsButton));
  await _pumpUntilFound(tester, intentionOption(option));
  await tester.pumpAndSettle(const Duration(milliseconds: 1));
  await tester.tap(intentionOption(option));
  await tester.pump();
}

Future<void> _back(WidgetTester tester) async {
  await tester.pumpAndSettle(const Duration(milliseconds: 1));
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle(const Duration(milliseconds: 1));
}

final _relationSheet = find.byType(Sheet);

Finder _onTopPage(Finder matching) => find.descendant(
  of: find.byType(IntentionDetailsPage).last,
  matching: matching,
);

Finder _relationRow(String phrase) => find.byWidgetPredicate(
  (widget) =>
      widget is RelationRow && widget.semanticLabel.startsWith('$phrase. '),
);

/// Вкладка «Связи» верхней страницы с числами активных и архивных связей.
Finder _relationCounts({required int active, required int archived}) =>
    _onTopPage(
      find.bySemanticsLabel(
        _l10n.detailsRelationsTabSemantic(active, archived),
      ),
    );

/// Ждёт, пока вкладка «Обзор» верхней страницы покажет вид [kind].
Future<void> _pumpUntilKind(WidgetTester tester, IntentionKind kind) async {
  await _tapWhenFound(tester, _onTopPage(find.text(_l10n.detailsOverviewTab)));
  final control = _onTopPage(find.byType(SegmentedControl<IntentionKind>));
  await _pumpUntilFound(tester, control);
  await _pumpUntilTrue(
    tester,
    () => tester.widget<SegmentedControl<IntentionKind>>(control).value == kind,
    'Страница не показала вид $kind.',
  );
}

IntentionHolding? _catalogHolding(WidgetTester tester, String title) =>
    tester.widget<IntentionCatalogRow>(intentionCatalogRow(title)).holding;

Finder _pickerRow(String title) => find.byWidgetPredicate(
  (widget) => widget is IntentionPickerRow && widget.summary.title == title,
  description: 'строка поиска «$title»',
);

int? _pickerCount(WidgetTester tester) =>
    tester.widget<CatalogHeader>(find.byType(CatalogHeader)).count;

Future<void> _pumpUntilPickerHolding(
  WidgetTester tester,
  String title,
  IntentionHolding holding,
) => _pumpUntilTrue(
  tester,
  () => tester.widget<IntentionPickerRow>(_pickerRow(title)).holding == holding,
  'Строка поиска «$title» не показала удержание $holding.',
);

Future<void> _pumpUntilHolding(
  WidgetTester tester,
  String title,
  IntentionHolding holding,
) async {
  await _pumpUntilFound(tester, intentionCatalogRow(title));
  await _pumpUntilTrue(
    tester,
    () => _catalogHolding(tester, title) == holding,
    'Строка «$title» не показала удержание $holding.',
  );
}

/// Ждёт, пока шапка верхней страницы покажет архивное состояние [muted].
Future<void> _pumpUntilHeadMuted(WidgetTester tester, {required bool muted}) =>
    _pumpUntilTrue(
      tester,
      () =>
          tester.widget<PageHead>(_onTopPage(find.byType(PageHead))).muted ==
          muted,
      'Шапка страницы не показала ожидаемое архивное состояние.',
    );

/// Ждёт верхнюю страницу намерения [title] и показывает её шапку: прежний
/// переход по связи мог прокрутить страницу.
Future<void> _pumpUntilDetailsTitle(WidgetTester tester, String title) async {
  final head = _onTopPage(find.byType(PageHead));
  await _pumpUntilTrue(tester, () {
    if (head.evaluate().isEmpty) {
      tester
          .state<ScrollableState>(_onTopPage(find.byType(Scrollable)).first)
          .position
          .jumpTo(0);
      return false;
    }
    return tester.widget<PageHead>(head).name == title;
  }, 'Верхняя страница не показала намерение «$title».');
  await tester.pumpAndSettle(const Duration(milliseconds: 1));
}

Future<void> _pumpUntilTrue(
  WidgetTester tester,
  bool Function() condition,
  String failure,
) async {
  // Пока страница уходит или ещё не построена, её частей нет.
  bool met() {
    try {
      return condition();
    } on StateError {
      return false;
    }
  }

  for (var attempt = 0; attempt < 1000; attempt += 1) {
    if (met()) return;
    await _pumpPollStep(tester);
  }
  fail(failure);
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) =>
    _pumpUntilTrue(
      tester,
      () => finder.evaluate().isNotEmpty,
      'Поток не показал ожидаемый элемент: '
      '${finder.toString(describeSelf: true)}',
    );

Future<void> _pumpUntilAbsent(WidgetTester tester, Finder finder) =>
    _pumpUntilTrue(
      tester,
      () => finder.evaluate().isEmpty,
      'Поток не убрал ожидаемый элемент: '
      '${finder.toString(describeSelf: true)}',
    );

Future<void> _tapWhenFound(WidgetTester tester, Finder finder) async {
  await _pumpUntilFound(tester, finder);
  await tester.tap(finder.first);
  await tester.pump();
}

/// Шаг ожидания: хранилище и предпросмотр каскада отвечают только в
/// настоящем цикле событий.
Future<void> _pumpPollStep(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump(const Duration(milliseconds: 1));
}
