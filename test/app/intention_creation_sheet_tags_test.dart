import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/data/local/app_database.dart';
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
final _search = find.byKey(const ValueKey('tag-catalog-search'));
final _addToDraft = find.byKey(const ValueKey('tag-catalog-add-to-draft'));
final _createTag = find.byKey(const ValueKey('tag-catalog-create'));
final _tagEditorName = find.byKey(const ValueKey('tag-editor-name'));
final _tagEditorSubmit = find.byKey(const ValueKey('tag-editor-submit'));
final _submit = find.byKey(const ValueKey('intention-editor-submit'));
final _failure = find.byKey(const ValueKey('intention-editor-failure'));
final _removeMissing = find.byKey(
  const ValueKey('intention-editor-remove-missing-tags'),
);
final _message = find.byKey(const ValueKey('graph-operation-message'));

/// Теги панели создания и общий выбор тегов на настоящих маршрутах
/// приложения, настоящем редакторе тега и Drift-адаптере in-memory
/// хранилища.
///
/// Набор черновика виден по элементам панели и по контексту открытого
/// выбора, граф — по строкам хранилища. Панель открывается через меню и
/// общую кнопку, а выбор — её действием, сохраняя настоящую сборку контекста.
void main() {
  testWidgets(
    'выбор из компактной панели создаёт самостоятельный тег настоящим '
    'редактором, возвращает ту же панель и её прокрутку, а сброс черновика '
    'сохраняет созданный тег',
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

      await app.openChooser(tester);
      await _tap(tester, _row(home));
      await _tap(tester, _addToDraft);

      // Настоящий редактор открывается над выбором и сразу сохраняет
      // самостоятельный тег, не включая его в черновик.
      await _tap(tester, _createTag);
      await _until(tester, _tagEditorName);
      await tester.pumpAndSettle();
      await tester.enterText(_tagEditorName, 'Сарай');
      await _tap(tester, _tagEditorSubmit);
      await _waitForStorage(tester, () => _tagEditorName.evaluate().isEmpty);
      final shed = app.storedTagId('Сарай');
      await _until(tester, _row(shed));
      await tester.pumpAndSettle();
      expect(
        _rowStatus(shed, l10n.tagCatalogAvailableForDraft),
        findsOneWidget,
      );

      // Новый тег входит в черновик только явным добавлением.
      await _tap(tester, _row(shed));
      await _tap(tester, _addToDraft);

      // Возврат показывает ту же компактную панель с прежней прокруткой.
      await _tap(tester, find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(_sheet, findsOneWidget);
      expect(_search, findsNothing);
      _expectCompactPanel(tester);
      expect(tester.getRect(_sheet), sheetRect);
      expect(_fieldsScroll(tester).pixels, fieldsOffset);
      expect(_text(tester, 'intention-editor-title'), _rawTitle);
      expect(_text(tester, 'intention-editor-description'), _longDescription);
      expect(_chipNames(tester), ['Дом', 'Сарай']);
      // Сообщение о созданном теге видно и над вернувшейся панелью.
      await app.closeMessage(tester);

      // Сброс черновика не создаёт намерение и назначения, а созданный
      // выбором тег остаётся самостоятельной меткой.
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
      await app.openChooser(tester);
      expect(
        _rowStatus(shed, l10n.tagCatalogAvailableForDraft),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'выбор, открытый одновременно с закрытием неизменённой панели, не меняет '
    'закрытую сессию и не влияет на новое открытие панели',
    (tester) async {
      final app = await _App.start(tester);
      final l10n = app.l10n;
      final home = _tagId(_homeTag);

      await app.openPanel(tester);
      await tester.tap(_chooseTags);
      await tester.tap(_close);
      await tester.pump();
      await _until(tester, _row(home));
      await tester.pumpAndSettle();

      // Неизменённая панель закрылась сразу, а запоздалый выбор открыт над
      // каталогом с набором уже закрытой сессии.
      expect(_sheet, findsNothing);
      expect(find.text(l10n.tagCatalogDraftClosed), findsOneWidget);
      await _tap(tester, _row(home));
      expect(tester.widget<FilledButton>(_addToDraft).onPressed, isNull);

      await _tap(tester, find.byType(BackButton));
      await tester.pumpAndSettle();
      expectIntentionGraphRootPage(app.router);

      // Новая панель получает собственный набор, на который прежний выбор
      // не влияет.
      await app.openPanel(tester);
      expect(_chipNames(tester), isEmpty);
      await app.openChooser(tester);
      await _tap(tester, _row(home));
      await _tap(tester, _addToDraft);
      await _tap(tester, find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(_chipNames(tester), ['Дом']);
      expect(app.storedTable('intentions'), isEmpty);
      expect(app.storedTable('tag_assignments'), isEmpty);
    },
  );

  testWidgets(
    'панель показывает переименование и удаление выбранного тега другим '
    'экраном, отказ сохранения сохраняет набор с объяснением, а явное '
    'исправление снимает только удалённый тег и не отправляет сохранение',
    (tester) async {
      final app = await _App.start(tester);
      final l10n = app.l10n;
      final home = _tagId(_homeTag);
      final work = _tagId(_workTag);

      await app.openPanel(tester);
      await tester.enterText(_field('intention-editor-title'), _rawTitle);
      await app.openChooser(tester);
      await _tap(tester, _row(home));
      await _tap(tester, _addToDraft);
      await _tap(tester, _row(work));
      await _tap(tester, _addToDraft);
      await _tap(tester, find.byType(BackButton));
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

      // Удалённый тег остаётся в черновике с последним названием, а
      // одноимённый новый тег его не заменяет.
      await app.runTagCommand(
        tester,
        app.coordinator.acceptTagDelete(DeleteTag(home)),
      );
      await app.runTagCommand(
        tester,
        app.coordinator.acceptTagCreation(
          TagCreationFormKey(),
          CreateTag(name: TagName.fromInput('Быт'), color: null),
        ),
      );
      await _until(tester, _chipStatus(home));
      await tester.pumpAndSettle();
      expect(_chipNames(tester), ['Быт', 'Работа']);
      expect(
        tester.widget<Text>(_chipStatus(home)).data,
        l10n.editorDraftTagMissing,
      );
      final graphBefore = app.storedGraph();

      // Сохранение отклоняется целиком и объясняет исправление набора.
      await _tap(tester, _submit);
      await _until(tester, _failure);
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(_failure),
        isSemantics(label: l10n.editorCreateTagsMissing(1)),
      );
      expect(_chipNames(tester), ['Быт', 'Работа']);
      expect(tester.widget<FilledButton>(_submit).onPressed, isNull);
      expect(app.storedGraph(), graphBefore);

      // Исправление снимает только удалённый тег и само не сохраняет.
      await _tap(tester, _removeMissing);
      await tester.pumpAndSettle();
      expect(_chipNames(tester), ['Работа']);
      expect(_failure, findsNothing);
      await _letStorageRun(tester);
      expect(app.storedGraph(), graphBefore);

      // Явное сохранение создаёт намерение только с оставшимся тегом.
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
        raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
          tagFixtureId(number),
          name,
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

  /// Открывает общий выбор тегов действием панели и ждёт каталог тегов.
  Future<void> openChooser(WidgetTester tester) async {
    await _tap(tester, _chooseTags);
    await _until(tester, _row(_tagId(_homeTag)));
    await tester.pumpAndSettle();
    expect(router.current.name, TagCatalogRoute.name);
  }

  /// Дожидается успеха команды тега другого экрана и закрывает её сообщение
  /// общей поверхности, чтобы оно не перекрывало панель.
  Future<void> runTagCommand(WidgetTester tester, TagCommandStart start) async {
    final accepted = start as TagCommandAccepted;
    TagCommandCompletion? completion;
    unawaited(accepted.future.then((value) => completion = value));
    await _waitForStorage(tester, () => completion != null);
    expect(
      completion!.result,
      isA<GraphResultSuccess<TagCommandSuccess, TagCommandFailure>>(),
    );
    await closeMessage(tester);
  }

  /// Закрывает текущее сообщение общей поверхности. Над панелью оно лежит
  /// поверх нижнего края её полей и перехватывает нажатия на них.
  Future<void> closeMessage(WidgetTester tester) async {
    await _until(tester, _message);
    await tester.pumpAndSettle();
    // Все копии сообщения принадлежат одной общей поверхности.
    ScaffoldMessenger.of(tester.element(_message.first)).hideCurrentSnackBar();
    await tester.pumpAndSettle();
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

Finder _row(TagId id) =>
    find.byKey(ValueKey('tag-catalog-row-${id.toCanonicalString()}'));

Finder _rowStatus(TagId id, String status) =>
    find.descendant(of: _row(id), matching: find.text(status));

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
