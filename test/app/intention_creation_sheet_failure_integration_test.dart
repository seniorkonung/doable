import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_page.dart';
import 'package:doable/src/shared/diagnostics/developer_diagnostics_sink.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/app_root_pages.dart';
import '../support/graph_seed.dart';
import '../support/local_database_harness.dart';
import '../support/intention_creation_storage_observer.dart';
import '../support/intention_creation_origin.dart';
import '../support/tag_storage_fixture.dart';
import '../support/in_memory_quick_creation_mode_store.dart';

const _rawTitle = '  Рисовать акварель  ';
const _title = 'Рисовать акварель';
const _description = ' Пейзаж у реки\nс берега ';
const _sport = 'Спорт';
final _home = _tagId(301);
final _seededIntention =
    (IntentionId.decode(tagFixtureId(1)) as IntentionIdDecodingSuccess).id;

Finder _key(String key) => find.byKey(ValueKey(key));
final _sheet = _key('intention-creation-sheet');
final _submit = _key('intention-editor-submit');
final _message = _key('graph-operation-message');
final _failure = _key('intention-editor-failure');

void main() {
  testWidgets('отказ файлового хранилища после записи части назначений тегов '
      'откатывает граф и FTS; компактная панель '
      'предъявляет один отказ и явный повтор сохраняет одно намерение '
      'на экране 568×320 с открытой клавиатурой '
      'даже при отказе диагностики', (tester) async {
    final app = await _launch(tester);
    final sport = await _prepare(tester, app);
    tester.view.physicalSize = const Size(568, 320);
    tester.view.padding = const FakeViewPadding(top: 24, right: 48);
    tester.view.viewPadding = const FakeViewPadding(top: 24, right: 48);
    tester.view.viewInsets = const FakeViewPadding(bottom: 160);

    await tester.pumpAndSettle();
    final before = _storedGraph(app.raw);
    _expectTightKeyboard(tester);
    app.storage.observeCreation(fail: true);
    app.diagnostics.throwOnIntentionCommand = true;
    await _tap(tester, _submit);
    final failed = await _creation(tester, app);
    await tester.pumpAndSettle();

    expect(
      failed.result,
      isA<ResultFailure>().having(
        (result) => result.failure,
        'причина',
        isA<IntentionUnavailableFailure>(),
      ),
    );
    expect(failed.confirmedChange, isNull);
    _expectFaultPoint(app, [_home, sport]);
    expect(_storedGraph(app.raw), before);
    _expectDraft(tester, [_home, sport]);
    _expectTightKeyboard(tester);
    // Отказ читается от начала до конца прокруткой при той же клавиатуре.
    final status = _key('intention-creation-sheet-status');
    for (final alignment in [0.0, 1.0]) {
      await Scrollable.ensureVisible(
        tester.element(_failure),
        alignment: alignment,
      );
      await tester.pumpAndSettle();
      final viewport = tester.getRect(status);
      final message = tester.getRect(_failure);
      final edge = alignment == 0 ? message.top : message.bottom - 0.1;
      expect(viewport.height, greaterThan(0));
      expect(edge, greaterThanOrEqualTo(viewport.top));
      expect(edge, lessThan(viewport.bottom));
      _expectTightKeyboard(tester);
    }
    await Scrollable.ensureVisible(tester.element(_failure), alignment: 0.5);
    await tester.pumpAndSettle();
    _expectInlineFailure(app.l10n.editorCreateUnavailable);
    expect(
      tester.getSemantics(_failure),
      isSemantics(label: app.l10n.editorCreateUnavailable),
    );
    expect(_submit.hitTestable(), findsOneWidget);
    expect(tester.widget<FilledButton>(_submit).onPressed, isNotNull);
    expect(app.diagnostics.thrown, 1);

    // Одноразовый hook уже снял отказ: повтор выполняется только кнопкой
    // панели.
    expect(app.creations, hasLength(1));
    _expectTightKeyboard(tester);
    await _tap(tester, _submit);
    final saved = await _creation(tester, app, count: 2);
    await _wait(tester, () => _sheet.evaluate().isEmpty);
    _expectSaved(app, saved, [_home, sport]);
    expect(app.diagnostics.thrown, 2);
    await returnToIntentionGraphAfterCreation(
      tester,
      app.container.read(appRouterProvider),
      waitFor: (tester, finder) =>
          _wait(tester, () => finder.evaluate().isNotEmpty),
    );
    await _acceptMessage(tester, _successMessage(app));
    app.diagnostics.expectPrivateDataHidden(app.raw);
    expect(tester.takeException(), isNull);
  });
}

final class _App {
  _App(
    this.raw,
    this.container,
    this.diagnostics,
    this.completions,
    this.storage,
    this.history,
  );

  final sqlite.Database raw;
  final ProviderContainer container;
  final _Diagnostics diagnostics;
  final List<GraphCommandCompletion> completions;
  final IntentionCreationStorageObserver storage;
  final IntentionCreationHistory history;
  GraphCommandCoordinator get coordinator =>
      container.read(graphCommandCoordinatorProvider.notifier);
  List<IntentionCommandCompletion> get creations =>
      completions.whereType<IntentionCommandCompletion>().toList();
  AppLocalizations get l10n => lookupAppLocalizations(const Locale('ru'));
}

Future<_App> _launch(
  WidgetTester tester, {
  IntentionCreationOrigin origin = IntentionCreationOrigin.graph,
}) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  tester.binding.platformDispatcher.localesTestValue = [const Locale('ru')];
  addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final harness = (await tester.runAsync(LocalDatabaseHarness.fileBacked))!;
  addTearDown(harness.dispose);
  late sqlite.Database raw;
  final diagnostics = _Diagnostics();
  diagnostics.privateValues.addAll([
    harness.databaseFile.path,
    harness.temporaryDirectory.path,
  ]);
  final storage = IntentionCreationStorageObserver(snapshotGraph: _storedGraph);
  final runtime = AppRuntime(
    quickCreationModeStore: InMemoryQuickCreationModeStore(),
    connectionFactory: () => observeConfiguredLocalDatabaseConnection(
      openFileBackedLocalDatabase(
        harness.databaseFile,
        setup: (database) => raw = database,
      ),
      storage,
    ),
    diagnosticsSink: diagnostics,
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await runtime.shutdown();
  });
  final ready = (await tester.runAsync(runtime.bootstrap)) as AppRuntimeReady;
  storage.connection = raw;
  seedRawGraph(raw, () {
    for (final (id, title, archived) in [(1, 'Гулять', 0), (2, 'Читать', 1)]) {
      raw.execute(
        'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, 0, ?, 1, 1)',
        [tagFixtureId(id), title, archived],
      );
    }
    raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
      tagFixtureId(301),
      'Дом',
    ]);
    raw.execute(
      'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
      [tagFixtureId(301), tagFixtureId(1)],
    );
  });
  final completions = <GraphCommandCompletion>[];
  final subscription = ready.container
      .read(graphCommandCoordinatorProvider.notifier)
      .completions
      .listen(completions.add);
  addTearDown(subscription.cancel);
  await tester.pumpWidget(MainApp(runtime: runtime));
  await openIntentionGraph(tester, waitFor: _until);
  await _wait(tester, () => find.text('Гулять').evaluate().isNotEmpty);
  await tester.pumpAndSettle();
  final history = await origin.open(
    tester,
    ready.container.read(appRouterProvider),
    participantId: _seededIntention,
    waitFor: _until,
  );
  return _App(raw, ready.container, diagnostics, completions, storage, history);
}

Future<void> _open(WidgetTester tester, _App app) async {
  unawaited(
    app.container
        .read(appRouterProvider)
        .push<void>(const IntentionEditorRoute()),
  );
  await _until(tester, _sheet);
  await tester.pumpAndSettle();
  expect(_sheet, findsOneWidget);
  expect(find.byType(IntentionEditorPage), findsOneWidget);
}

/// Название, описание, готовность и теги команды подготавливаются
/// реальными панелью, общим выбором и редактором тега.
Future<TagId> _prepare(WidgetTester tester, _App app) async {
  await _open(tester, app);
  await tester.enterText(_key('intention-editor-title'), _rawTitle);
  await tester.enterText(_key('intention-editor-description'), _description);
  await _tap(tester, _key('intention-editor-readiness'));
  await _tap(tester, _key('intention-editor-readiness-confirm'));
  await _tap(tester, _key('intention-editor-choose-tags'));
  await _add(tester, _home);
  // Локальные правки не маскируются событиями постоянных команд.
  expect(app.completions, isEmpty);
  final sport = await _newTag(tester, app);
  await _add(tester, sport);
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
  _expectDraft(tester, [_home, sport]);
  expect(app.completions.single, isA<TagCommandCompletion>());
  return sport;
}

/// Создаёт самостоятельный тег редактором над текущим общим выбором.
Future<TagId> _newTag(WidgetTester tester, _App app) async {
  await _tap(tester, _key('tag-catalog-create'));
  await _until(tester, _key('tag-editor-name'));
  await tester.pumpAndSettle();
  await tester.enterText(_key('tag-editor-name'), _sport);
  await _tap(tester, _key('tag-editor-submit'));
  await _wait(tester, () => _key('tag-editor-name').evaluate().isEmpty);
  await _acceptMessage(
    tester,
    app.l10n.graphOperationMessage(
      app.l10n.graphOperationCreate,
      app.l10n.graphOperationTag,
      app.l10n.tagCreated,
    ),
  );
  final sport = _tagIdFrom(
    app.raw.select('SELECT id FROM tags WHERE name = ?', [_sport]).single['id']
        as String,
  );
  app.diagnostics.privateValues.add(sport.toCanonicalString());
  return sport;
}

Future<void> _add(WidgetTester tester, TagId id) async {
  await _tap(tester, _key('tag-catalog-row-${id.toCanonicalString()}'));
  final add = _key('tag-catalog-add-to-draft');
  await _wait(tester, () => tester.widget<FilledButton>(add).onPressed != null);
  await _tap(tester, add);
}

void _expectDraft(WidgetTester tester, List<TagId> tags) {
  expect(_text(tester, 'intention-editor-title'), _rawTitle);
  expect(_text(tester, 'intention-editor-description'), _description);
  for (final id in tags) {
    expect(_chip(id), findsOneWidget);
  }
  expect(_icon(tester, 'intention-editor-readiness'), Icons.check_circle);
}

IconData? _icon(WidgetTester tester, String key) => tester
    .widget<Icon>(find.descendant(of: _key(key), matching: find.byType(Icon)))
    .icon;

String _text(WidgetTester tester, String key) =>
    tester.widget<TextField>(_key(key)).controller!.text;
Finder _chip(TagId id) =>
    _key('intention-editor-tag-${id.toCanonicalString()}');
TagId _tagId(int number) => _tagIdFrom(tagFixtureId(number));
TagId _tagIdFrom(String value) =>
    (TagId.decode(value) as TagIdDecodingSuccess).id;

/// Полные строки предметного графа и FTS: не только число намерений.
Map<String, List<List<Object?>>> _storedGraph(sqlite.Database raw) => {
  for (final table in [
    'intentions',
    'intention_titles_fts',
    'tags',
    'tag_assignments',
    'long_term_relations',
    'daily_choices',
    'daily_choice_path_steps',
  ])
    table: [
      for (final row in raw.select('SELECT * FROM $table ORDER BY rowid'))
        row.values.toList(),
    ],
  // MATCH читает сам поисковый индекс: external-content FTS при SELECT *
  // мог бы скрыть оставшиеся после отката строки индекса.
  'ftsCreatedMatches': [
    for (final row in raw.select(
      'SELECT rowid FROM intention_titles_fts WHERE intention_titles_fts MATCH ?',
      ['"Рисовать акварель"'],
    ))
      row.values.toList(),
  ],
};

final class _Diagnostics implements DiagnosticsSink {
  final events = <DiagnosticsEvent>[];
  final lines = <String>[];
  final privateValues = <String>[];
  var throwOnIntentionCommand = false;
  var thrown = 0;

  @override
  void record(DiagnosticsEvent event) {
    events.add(event);
    DeveloperDiagnosticsSink(lines.add).record(event);
    if (throwOnIntentionCommand && event is IntentionCommandDiagnosticsEvent) {
      thrown++;
      throw StateError('Управляемый отказ получателя диагностики');
    }
  }

  void expectPrivateDataHidden(sqlite.Database raw) {
    final recorded = [
      ...events.map((event) => event.toString()),
      ...lines,
    ].join('\n');
    expect(lines, isNotEmpty);
    for (final value in [
      _rawTitle,
      _title,
      _description,
      _sport,
      'Дом',
      'Быт',
      'Другое намерение',
      'Другой черновик',
      'INSERT ',
      'SELECT ',
      'UPDATE ',
      'tag_assignments',
      ...privateValues,
      for (final table in ['tags', 'intentions'])
        for (final row in raw.select('SELECT id FROM $table'))
          row['id'] as String,
    ]) {
      expect(recorded, isNot(contains(value)), reason: value);
    }
  }
}

/// Отказ прерывает открытую транзакцию после записи намерения
/// и одного из выбранных назначений тегов.
void _expectFaultPoint(_App app, List<TagId> tags) {
  final point = app.storage.faultPoint!;
  expect(point.inTransaction, isTrue);
  final row = point.graph['intentions']!.last;
  // Порядок столбцов соответствует схемам intentions и tag_assignments.
  // Проверяются также сохраняемые поисковый ключ и порядок тегов.
  expect(row, [
    isA<String>(),
    _title,
    'рисовать акварель',
    _description,
    1,
    0,
    isA<int>(),
    isA<int>(),
  ]);
  expect(row[6], row[7]);
  final assignments = point.graph['tag_assignments']!
      .where((assignment) => assignment[3] == row.first)
      .toList();
  expect(assignments, hasLength(1));
  expect(assignments.length, lessThan(tags.length));
  final assignment = assignments.single;
  expect(assignment, [
    isA<int>(),
    isIn(tags.map((tag) => tag.toCanonicalString())),
    point.graph['tags']!.singleWhere((stored) => stored[1] == assignment[1])[0],
    row.first,
  ]);
  expect(point.graph['intention_titles_fts']!.last, ['рисовать акварель']);
  expect(point.graph['ftsCreatedMatches'], hasLength(1));
}

Future<IntentionCommandCompletion> _creation(
  WidgetTester tester,
  _App app, {
  int count = 1,
}) async {
  await _wait(tester, () => app.creations.length >= count);
  expect(app.creations, hasLength(count));
  return app.creations.last;
}

void _expectSaved(
  _App app,
  IntentionCommandCompletion completion,
  List<TagId> tags,
) {
  final saved = switch (completion.result) {
    ResultSuccess(value: final IntentionSaved saved) => saved,
    final result => fail('Создание не подтверждено: $result'),
  };
  final intention = saved.intention;
  app.diagnostics.privateValues.add(intention.id.toCanonicalString());
  expect(intention.title, _title);
  expect(intention.description, _description);
  expect(intention.readiness, IntentionReadiness.ready);
  expect(intention.archiveState, IntentionArchiveState.active);
  expect(intention.createdAt, intention.updatedAt);
  final stored = app.raw
      .select(
        'SELECT title, description, is_action_ready, is_archived, created_at, updated_at FROM intentions WHERE id = ?',
        [intention.id.toCanonicalString()],
      )
      .single
      .values
      .toList();
  expect(stored, [_title, _description, 1, 0, isA<int>(), isA<int>()]);
  expect(stored[4], stored[5]);
  expect(_storedGraph(app.raw)['ftsCreatedMatches'], hasLength(1));
  expect(
    saved.additionalChanges.whereType<TagAssignmentChangedChange>().map(
      (change) => change.assignment.tagId,
    ),
    unorderedEquals(tags),
  );
  expect(
    app.raw.select('SELECT id FROM intentions WHERE title = ?', [_title]),
    hasLength(1),
  );
  expect(
    app.raw
        .select('SELECT tag_id FROM tag_assignments WHERE intention_id = ?', [
          intention.id.toCanonicalString(),
        ])
        .map((row) => row['tag_id']),
    unorderedEquals(tags.map((id) => id.toCanonicalString())),
  );
}

void _expectInlineFailure(String text) {
  expect(_failure.hitTestable(), findsOneWidget);
  expect(find.text(text).hitTestable(), findsOneWidget);
  expect(_message, findsNothing);
  expect(find.byType(SnackBar), findsNothing);
}

String _successMessage(_App app) => app.l10n.graphOperationMessage(
  app.l10n.graphOperationCreate,
  _title,
  app.l10n.editorCreated,
);
Future<void> _acceptMessage(WidgetTester tester, String text) async {
  await _until(tester, _message.hitTestable());
  await tester.pumpAndSettle();
  expect(find.byType(SnackBar).hitTestable(), findsOneWidget);
  expect(find.text(text).hitTestable(), findsOneWidget);
  ScaffoldMessenger.of(tester.element(_message.hitTestable()))
      .hideCurrentSnackBar();
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
  expect(_message, findsNothing);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _until(tester, finder);
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

/// Исходная тесная геометрия сохраняет поля и действия над клавиатурой.
void _expectTightKeyboard(WidgetTester tester) {
  expect(tester.view.physicalSize, const Size(568, 320));
  expect(tester.view.viewInsets.bottom, 160);
  expect(tester.view.padding.top, 24);
  expect(tester.view.padding.right, 48);

  expect(tester.getRect(_sheet).top, greaterThanOrEqualTo(48));
  expect(tester.getRect(_sheet).bottom, 160);
  expect(
    tester.getSize(_key('intention-creation-sheet-fields')).height,
    greaterThan(0),
  );
  expect(_key('intention-editor-close').hitTestable(), findsOneWidget);
}

Future<void> _until(WidgetTester tester, Finder finder) =>
    _wait(tester, () => finder.evaluate().isNotEmpty);

Future<void> _wait(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 100 && !done(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue);
}
