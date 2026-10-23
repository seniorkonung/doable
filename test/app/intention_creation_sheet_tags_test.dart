import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/design_system/components/sheet.dart';
import 'package:doable/src/design_system/components/tag_row.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/app_root_pages.dart';
import '../support/graph_seed.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/tag_storage_fixture.dart';
import '../support/in_memory_quick_creation_mode_store.dart';
import '../support/quick_creation.dart';
import '../support/tag_positions.dart';

const _homeTag = 301;
const _workTag = 302;
const _gardenTag = 303;

const _rawTitle = '  Купить семена ';

/// Описание, которое не помещается в компактную панель и прокручивается.
final _longDescription = [for (var line = 1; line <= 40; line++) 'Строка $line']
    .join('\n');

/// Таблицы, в которые пишет только создание намерения.
const _creationTables = [
  'intentions',
  'intention_titles_fts',
  'tag_assignments',
];

final _sheet = find.byKey(const ValueKey('intention-creation-sheet'));
final _chooseTags = find.byKey(const ValueKey('intention-editor-choose-tags'));
final _close = find.byKey(const ValueKey('intention-editor-close'));
final _submit = find.byKey(const ValueKey('intention-editor-submit'));
final _failure = find.byKey(const ValueKey('intention-editor-failure'));
final _message = find.byKey(const ValueKey('graph-operation-message'));

/// Теги панели создания и панель тегов над ней на настоящих маршрутах
/// приложения, настоящем листе тега и Drift-адаптере in-memory хранилища.
///
/// Набор черновика виден по элементам панели создания и отметкам панели
/// тегов, граф — по строкам хранилища. Панель создания открывается через
/// меню и общую кнопку, а панель тегов — её действием, сохраняя настоящую
/// сборку контекста.
void main() {
  testWidgets(
    'панель тегов над компактной панелью создаёт самостоятельный тег настоящим '
    'листом и отмечает его в черновике, закрытие возвращает ту же панель и её '
    'прокрутку, а сброс черновика сохраняет созданный тег',
    (tester) async {
      final app = await _App.start(tester);
      final l10n = app.l10n;
      final home = _tagId(_homeTag);

      await app.openPanel(tester);
      await tester.enterText(_field('intention-editor-title'), _rawTitle);
      await tester.enterText(
        _field('intention-editor-description'),
        _longDescription,
      );
      final graphBefore = app.storedGraph();

      // Завершаем ввод перед прокруткой: возврат фокуса к каретке не должен
      // подменять выбранную позицию. Выбор лежит в конце прокрученных полей.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(_chooseTags);
      await tester.pumpAndSettle();
      final fieldsOffset = _fieldsScroll(tester).pixels;
      expect(fieldsOffset, greaterThan(0));
      _expectCompactPanel(tester);
      final sheetRect = tester.getRect(_sheet);

      await app.openTagsPanel(tester);
      await _tap(tester, _row(home));
      await _waitForStorage(tester, () => _isMarked(tester, home));
      expect(app.storedGraph(), graphBefore);

      // Настоящий лист открывается над панелью тегов и сохраняет
      // самостоятельный тег, который сразу отмечается в черновике.
      await tester.enterText(_tagsPanelSearch(l10n), 'Сарай');
      await tester.pump();
      await _tap(tester, find.text(l10n.tagsPanelCreateTag('Сарай')));
      final createAction = find.widgetWithText(
        FilledButton,
        l10n.tagEditorCreateAction,
      );
      await _until(tester, createAction);
      await tester.pumpAndSettle();
      await _tap(tester, createAction);
      await _waitForStorage(tester, () => createAction.evaluate().isEmpty);
      final shed = app.storedTagId('Сарай');
      await _waitForStorage(
        tester,
        () => _row(shed).evaluate().isNotEmpty && _isMarked(tester, shed),
      );
      await tester.pumpAndSettle();
      expect(_isMarked(tester, home), isTrue);
      expect(app.storedGraph(), graphBefore);

      // Закрытие панели тегов показывает ту же компактную панель с прежней
      // прокруткой.
      await _tap(tester, find.text(l10n.tagsPanelDone));
      await tester.pumpAndSettle();
      expect(_sheet, findsOneWidget);
      expect(_tagsPanel(l10n), findsNothing);
      expect(app.router.current.name, IntentionEditorRoute.name);
      _expectCompactPanel(tester);
      expect(tester.getRect(_sheet), sheetRect);
      expect(_fieldsScroll(tester).pixels, fieldsOffset);
      expect(_text(tester, 'intention-editor-title'), _rawTitle);
      expect(_text(tester, 'intention-editor-description'), _longDescription);
      // Созданный тег встаёт первым в ручном порядке.
      expect(_chipNames(tester), ['Сарай', 'Дом']);
      // Созданный тег виден в панели тегов, поэтому успех не объявляется.
      expect(_message, findsNothing);

      // Сброс черновика не создаёт намерение и назначения, а созданный в
      // панели тегов тег остаётся самостоятельной меткой.
      await _tap(tester, _close);
      await tester.pumpAndSettle();
      await _tap(
        tester,
        find.byKey(const ValueKey('intention-editor-close-discard')),
      );
      await tester.pumpAndSettle();
      expectIntentionGraphRootPage(app.router);
      expect(app.storedGraph(), graphBefore);
      expect(app.storedTagNames(), ['Дом', 'Работа', 'Сад', 'Сарай']);

      // Новое открытие панели начинает пустой набор новой сессии.
      await app.openPanel(tester);
      expect(_chipNames(tester), isEmpty);
      _expectCompactPanel(tester);
      await app.openTagsPanel(tester);
      await _until(tester, _row(shed));
      expect(_isMarked(tester, shed), isFalse);
    },
  );

  testWidgets(
    'панель тегов, открытая одновременно с закрытием неизменённой панели '
    'создания, закрывается вместе с ней и не влияет на новое открытие',
    (tester) async {
      final app = await _App.start(tester);
      final l10n = app.l10n;
      final home = _tagId(_homeTag);

      await app.openPanel(tester);
      final close = tester.widget<IconButton>(_close).onPressed!;
      // Закрытие приходит обработчиком прежнего кадра: касания уже
      // перехватывает затемнение открывающейся панели тегов.
      await tester.tap(_chooseTags);
      close();
      await tester.pumpAndSettle();

      // Неизменённая панель создания закрылась сразу и унесла панель тегов,
      // открытую над ней.
      expect(_sheet, findsNothing);
      expect(_tagsPanel(l10n), findsNothing);
      expectIntentionGraphRootPage(app.router);

      // Новая панель создания получает собственный набор, на который
      // прежнее открытие не влияет.
      await app.openPanel(tester);
      expect(_chipNames(tester), isEmpty);
      await app.openTagsPanel(tester);
      expect(_isMarked(tester, home), isFalse);
      await _tap(tester, _row(home));
      await _waitForStorage(tester, () => _isMarked(tester, home));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_tagsPanel(l10n), findsNothing);
      expect(_chipNames(tester), ['Дом']);
      expect(app.storedTable('intentions'), isEmpty);
      expect(app.storedTable('tag_assignments'), isEmpty);
    },
  );

  testWidgets(
    'панель показывает переименование выбранного тега другим экраном, '
    'удаление в панели тегов убирает его из черновика без подмены одноимённым '
    'новым тегом, а сохранение создаёт намерение только с оставшимся тегом',
    (tester) async {
      final app = await _App.start(tester);
      final l10n = app.l10n;
      final home = _tagId(_homeTag);
      final work = _tagId(_workTag);

      await app.openPanel(tester);
      await tester.enterText(_field('intention-editor-title'), _rawTitle);
      await app.openTagsPanel(tester);
      await _tap(tester, _row(home));
      await _tap(tester, _row(work));
      await _waitForStorage(tester, () => _isMarked(tester, work));
      await _tap(tester, find.text(l10n.tagsPanelDone));
      await tester.pumpAndSettle();
      expect(_chipNames(tester), ['Дом', 'Работа']);

      // Подтверждённое переименование меняет только название выбранного
      // тега.
      await app.runTagCommand(
        tester,
        app.coordinator.acceptTagUpdate(
          UpdateTag(tagId: home, name: TagName.fromInput('Быт'), color: null),
        ),
      );
      await _waitForStorage(tester, () => _chipNames(tester).first == 'Быт');
      expect(_chipStatus(home), findsNothing);

      // Тег, удалённый в панели тегов, уходит из неё и из черновика, а
      // одноимённый новый тег его не заменяет.
      await app.openTagsPanel(tester);
      await tester.longPress(_row(home));
      await tester.pumpAndSettle();
      await _tap(tester, find.text(l10n.tagsPanelDeleteTag));
      await tester.pumpAndSettle();
      await _tap(tester, find.text(l10n.tagsPanelDeleteConfirm));
      await _waitForStorage(tester, () => _row(home).evaluate().isEmpty);
      await tester.pumpAndSettle();
      expect(_isMarked(tester, work), isTrue);
      expect(_message, findsNothing);
      await _tap(tester, find.text(l10n.tagsPanelDone));
      await tester.pumpAndSettle();
      expect(_chipNames(tester), ['Работа']);
      expect(_text(tester, 'intention-editor-title'), _rawTitle);
      await app.runTagCommand(
        tester,
        app.coordinator.acceptTagCreation(
          TagCreationFormKey(),
          CreateTag(
            name: TagName.fromInput('Быт'),
            color: null,
            placement: TagPlacement.first,
          ),
        ),
      );
      await _waitForStorage(tester, () => _chipNames(tester).length == 1);
      await _letStorageRun(tester);
      await tester.pumpAndSettle();
      expect(_chipNames(tester), ['Работа']);
      expect(_failure, findsNothing);
      expect(app.storedTable('intentions'), isEmpty);

      // Сохранение создаёт намерение только с оставшимся тегом.
      await _tap(tester, _submit);
      await _waitForStorage(tester, () => _sheet.evaluate().isEmpty);
      await returnToIntentionGraphAfterCreation(
        tester,
        app.router,
        waitFor: _until,
      );
      expect(app.storedTable('intentions'), hasLength(1));
      expect(
        [
          for (final row in app.raw.select(
            'SELECT tag_id FROM tag_assignments ORDER BY rowid',
          ))
            row['tag_id'],
        ],
        [work.toCanonicalString()],
      );
    },
  );
}

/// Приложение на Drift-адаптере in-memory хранилища с тегами «Дом»,
/// «Работа» и «Сад» и пустым каталогом намерений.
final class _App {
  _App(this.raw, this.router, this.coordinator, this.l10n);

  final sqlite.Database raw;
  final StackRouter router;
  final GraphCommandCoordinator coordinator;
  final AppLocalizations l10n;

  static Future<_App> start(WidgetTester tester) async {
    const locale = Locale('ru');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.platformDispatcher.localesTestValue = [locale];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    tester.view.physicalSize = const Size(400, 800);
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
      for (final (number, name) in [
        (_homeTag, 'Дом'),
        (_workTag, 'Работа'),
        (_gardenTag, 'Сад'),
      ]) {
        raw.execute('INSERT INTO tags (id, name, position) VALUES (?, ?, ?)', [
          tagFixtureId(number),
          name,
          tagPositionKey(number),
        ]);
      }
    });
    final l10n = lookupAppLocalizations(locale);
    await tester.pumpWidget(MainApp(runtime: runtime));
    await openIntentionGraph(tester, waitFor: _until);
    await _until(tester, find.text(l10n.catalogActiveEmpty));
    await tester.pumpAndSettle();
    return _App(
      raw,
      ready.container.read(appRouterProvider),
      ready.container.read(graphCommandCoordinatorProvider.notifier),
      l10n,
    );
  }

  /// Открывает панель создания через меню и кнопку общей панели.
  Future<void> openPanel(WidgetTester tester) async {
    await openQuickCreation(
      tester,
      QuickCreationMode.intention,
      openedPage: _sheet,
      wait: _until,
    );
    expect(router.current.name, IntentionEditorRoute.name);
  }

  /// Открывает панель тегов действием панели создания и ждёт её строки.
  /// Панель — не маршрут: над формой в стеке ничего не появляется.
  Future<void> openTagsPanel(WidgetTester tester) async {
    await _tap(tester, _chooseTags);
    await _until(tester, find.byType(TagRow));
    await tester.pumpAndSettle();
    expect(_tagsPanel(l10n), findsOneWidget);
    expect(router.current.name, IntentionEditorRoute.name);
  }

  /// Дожидается успеха команды тега другого экрана; успех виден в данных и
  /// не объявляется сообщением общей поверхности.
  Future<void> runTagCommand(WidgetTester tester, TagCommandStart start) async {
    final accepted = start as TagCommandAccepted;
    TagCommandCompletion? completion;
    unawaited(accepted.future.then((value) => completion = value));
    await _waitForStorage(tester, () => completion != null);
    expect(
      completion!.result,
      isA<GraphResultSuccess<TagCommandSuccess, TagCommandFailure>>(),
    );
    await tester.pumpAndSettle();
    expect(_message, findsNothing);
  }

  List<List<Object?>> storedTable(String table) => raw
      .select('SELECT * FROM $table ORDER BY rowid')
      .map((row) => row.values.toList())
      .toList();

  Map<String, List<List<Object?>>> storedGraph() => {
    for (final table in _creationTables) table: storedTable(table),
  };

  List<String> storedTagNames() => [
    for (final row in raw.select('SELECT name FROM tags ORDER BY rowid'))
      row['name'] as String,
  ];

  TagId storedTagId(String name) => switch (TagId.decode(
    raw.select('SELECT id FROM tags WHERE name = ?', [name]).single['id']
        as String,
  )) {
    TagIdDecodingSuccess(:final id) => id,
    InvalidTagIdDecoding() => throw StateError('Некорректный UUID тега.'),
  };
}

TagId _tagId(int number) => switch (TagId.decode(tagFixtureId(number))) {
  TagIdDecodingSuccess(:final id) => id,
  InvalidTagIdDecoding() => throw StateError('Некорректный UUID тега.'),
};

Size _screen(WidgetTester tester) =>
    tester.view.physicalSize / tester.view.devicePixelRatio;

/// Панель оставляет видимую часть каталога и прилегает к низу экрана.
void _expectCompactPanel(WidgetTester tester) {
  final rect = tester.getRect(_sheet);
  expect(rect.top, greaterThanOrEqualTo(72));
  expect(rect.bottom, _screen(tester).height);
}

Finder _field(String key) => find.byKey(ValueKey(key));

Finder _tagsPanel(AppLocalizations l10n) =>
    find.widgetWithText(Sheet, l10n.tagsPanelTitle);

Finder _tagsPanelSearch(AppLocalizations l10n) =>
    find.descendant(of: _tagsPanel(l10n), matching: find.byType(TextField));

Finder _row(TagId id) =>
    find.byKey(ValueKey('tags-panel-row-${id.toCanonicalString()}'));

/// Строка тега [id] в панели отмечена: тег входит в набор черновика.
bool _isMarked(WidgetTester tester, TagId id) =>
    tester
        .widget<TagRow>(
          find.descendant(of: _row(id), matching: find.byType(TagRow)),
        )
        .mark ==
    TagRowSelectionMark.checked;

Finder _chipStatus(TagId id) => find.byKey(
  ValueKey('intention-editor-tag-status-${id.toCanonicalString()}'),
);

/// Названия выбранных тегов панели в показанном порядке.
List<String> _chipNames(WidgetTester tester) => [
  for (final name
      in find
          .byWidgetPredicate(
            (widget) => switch (widget.key) {
              ValueKey<String>(:final value) => value.startsWith(
                'intention-editor-tag-name-',
              ),
              _ => false,
            },
          )
          .evaluate())
    (name.widget as Text).data!,
];

String _text(WidgetTester tester, String key) =>
    tester.widget<TextField>(_field(key)).controller!.text;

ScrollPosition _fieldsScroll(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const ValueKey('intention-creation-sheet-fields')),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

/// Ожидание настоящего хранилища: реальное время для его операций и кадры
/// для интерфейса.
Future<void> _waitForStorage(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 100 && !done(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue);
}

/// Даёт хранилищу время: запущенная запись успела бы завершиться.
Future<void> _letStorageRun(WidgetTester tester) async {
  for (var attempt = 0; attempt < 5; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _until(WidgetTester tester, Finder finder) =>
    _waitForStorage(tester, () => finder.evaluate().isNotEmpty);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _until(tester, finder);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}
