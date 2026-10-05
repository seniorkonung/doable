import 'package:auto_route/auto_route.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/intention/presentation/editor/intention_draft_tag_set.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_page.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_page.dart';
import 'package:doable/src/tag/presentation/catalog/tag_selection_context.dart';
import 'package:doable/src/tag/presentation/editor/tag_editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/app_root_pages.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/tag_storage_fixture.dart';

const _homeTag = 301;
const _workTag = 302;
const _gardenTag = 303;

const _rawTitle = '  Купить семена ';
const _description = 'Для грядок у дома';

/// Описание, которое не помещается в развёрнутую панель и прокручивается.
final _longDescription = [for (var line = 1; line <= 40; line++) 'Строка $line']
    .join('\n');

/// Таблицы, в которые пишет только создание намерения.
const _creationTables = [
  'intentions',
  'intention_titles_fts',
  'tag_assignments',
  'favorite_intentions',
];

final _sheet = find.byKey(const ValueKey('intention-creation-sheet'));
final _chooseTags = find.byKey(const ValueKey('intention-editor-choose-tags'));
final _resize = find.byKey(const ValueKey('intention-creation-sheet-resize'));
final _favorite = find.byKey(const ValueKey('intention-editor-favorite'));
final _search = find.byKey(const ValueKey('tag-catalog-search'));
final _addToDraft = find.byKey(const ValueKey('tag-catalog-add-to-draft'));
final _createTag = find.byKey(const ValueKey('tag-catalog-create'));
final _tagEditorName = find.byKey(const ValueKey('tag-editor-name'));
final _tagEditorSubmit = find.byKey(const ValueKey('tag-editor-submit'));
final _tagEditorCancel = find.byKey(const ValueKey('tag-editor-cancel'));

/// Теги панели создания и общий выбор тегов на настоящих маршрутах
/// приложения, настоящем редакторе тега и Drift-адаптере in-memory
/// хранилища.
///
/// Набор черновика виден по элементам панели и по контексту открытого
/// выбора, граф — по строкам хранилища. Панель открывается кнопкой каталога,
/// а выбор — её действием, поэтому проверки не подменяют сборку контекста.
void main() {
  testWidgets(
    'выбор из компактной панели добавляет несколько тегов только в черновик, '
    '«назад» закрывает только выбор и возвращает ту же панель, а снятие тега '
    'меняет только набор',
    (tester) async {
      final app = await _App.start(tester);
      final l10n = app.l10n;
      final home = _tagId(_homeTag);
      final work = _tagId(_workTag);

      await app.openPanel(tester);
      await tester.enterText(_field('intention-editor-title'), _rawTitle);
      await tester.enterText(
        _field('intention-editor-description'),
        _description,
      );
      await tester.tap(_favorite);
      await tester.pump();
      final graphBefore = app.storedGraph();

      // Выбор открывается полноэкранно над панелью в том же корневом стеке:
      // панель с сессией остаётся под ним, основная навигация скрыта.
      await app.openChooser(tester);
      expect(app.stackNames(), [
        AppShellRoute.name,
        IntentionEditorRoute.name,
        TagCatalogRoute.name,
      ]);
      expect(
        tester.getRect(find.byType(TagCatalogPage)),
        Offset.zero & _screen(tester),
      );
      expect(find.byType(AppNavigationBar), findsNothing);
      expect(find.byType(IntentionEditorPage, skipOffstage: false), findsOne);
      expect(find.text(l10n.tagCatalogSelectionTitle), findsOneWidget);
      final tagSet = app.chooserTagSet();
      expect(tagSet.current.tagIds, isEmpty);
      expect(tagSet.current.availability, IntentionDraftAvailability.editable);

      // Выбор строки — только кандидат; добавление — явное действие.
      await _tap(tester, _row(home));
      expect(tagSet.current.tagIds, isEmpty);
      await _tap(tester, _addToDraft);
      await _tap(tester, _row(work));
      await _tap(tester, _addToDraft);
      expect(tagSet.current.tagIds, [home, work]);
      expect(_rowStatus(home, l10n.tagCatalogInDraft), findsOneWidget);
      expect(_rowStatus(work, l10n.tagCatalogInDraft), findsOneWidget);
      expect(
        _rowStatus(_tagId(_gardenTag), l10n.tagCatalogAvailableForDraft),
        findsOneWidget,
      );
      expect(app.storedGraph(), graphBefore);

      // Системное «назад» закрывает только выбор.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(app.stackNames(), [AppShellRoute.name, IntentionEditorRoute.name]);
      expect(find.byType(TagCatalogPage), findsNothing);
      expect(_sheet, findsOneWidget);
      expect(_text(tester, 'intention-editor-title'), _rawTitle);
      expect(_text(tester, 'intention-editor-description'), _description);
      expect(_iconOf(tester, _favorite), Icons.star);
      expect(_iconOf(tester, _resize), Icons.open_in_full);
      expect(_chipNames(tester), ['Дом', 'Работа']);
      expect(
        find.byTooltip(l10n.editorRemoveDraftTag('Работа')),
        findsOneWidget,
      );
      expect(app.storedGraph(), graphBefore);

      // Снятие меняет только черновик и не требует перехода в выбор.
      await _tap(tester, _chipRemove(work));
      expect(_chipNames(tester), ['Дом']);
      expect(tagSet.current.tagIds, [home]);
      expect(app.storedGraph(), graphBefore);

      // Новое открытие выбора принадлежит той же сессии и видит её набор.
      await app.openChooser(tester);
      expect(app.chooserTagSet(), same(tagSet));
      expect(_rowStatus(home, l10n.tagCatalogInDraft), findsOneWidget);
      expect(
        _rowStatus(work, l10n.tagCatalogAvailableForDraft),
        findsOneWidget,
      );
      await _tap(tester, find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(app.stackNames(), [AppShellRoute.name, IntentionEditorRoute.name]);
      expect(_text(tester, 'intention-editor-title'), _rawTitle);
      expect(_chipNames(tester), ['Дом']);
      expect(app.storedGraph(), graphBefore);
    },
  );

  testWidgets(
    'выбор из развёрнутой панели сохраняет поиск при сохранении и отмене '
    'настоящего редактора, не включает новый тег без явного добавления, '
    'возвращает режим и прокрутку панели, а сброс черновика сохраняет '
    'созданный тег',
    (tester) async {
      final app = await _App.start(tester);
      final l10n = app.l10n;
      final home = _tagId(_homeTag);
      final garden = _tagId(_gardenTag);

      await app.openPanel(tester);
      await tester.enterText(_field('intention-editor-title'), _rawTitle);
      await tester.enterText(
        _field('intention-editor-description'),
        _longDescription,
      );
      await _tap(tester, _resize);
      await tester.pumpAndSettle();
      expect(_iconOf(tester, _resize), Icons.close_fullscreen);
      final graphBefore = app.storedGraph();

      // Действие выбора лежит в конце прокрученных полей.
      await tester.ensureVisible(_chooseTags);
      await tester.pumpAndSettle();
      final fieldsOffset = _fieldsScroll(tester).pixels;
      expect(fieldsOffset, greaterThan(0));
      final sheetRect = tester.getRect(_sheet);

      await app.openChooser(tester);
      final tagSet = app.chooserTagSet();
      await _tap(tester, _row(home));
      await _tap(tester, _addToDraft);
      expect(tagSet.current.tagIds, [home]);

      // Поиск скрывает включённый тег, не снимая его из черновика.
      await tester.enterText(_search, 'са');
      await tester.pump();
      expect(_row(home), findsNothing);
      expect(_row(garden), findsOneWidget);
      expect(tagSet.current.tagIds, [home]);

      // Настоящий редактор открывается над выбором в том же стеке и сразу
      // сохраняет самостоятельный тег, не включая его в черновик.
      await _tap(tester, _createTag);
      await _until(tester, _tagEditorName);
      await tester.pumpAndSettle();
      expect(app.stackNames(), [
        AppShellRoute.name,
        IntentionEditorRoute.name,
        TagCatalogRoute.name,
        TagEditorRoute.name,
      ]);
      expect(find.byType(TagEditorPage), findsOneWidget);
      await tester.enterText(_tagEditorName, 'Сарай');
      await _tap(tester, _tagEditorSubmit);
      await _waitForStorage(tester, () => _tagEditorName.evaluate().isEmpty);
      final shed = app.storedTagId('Сарай');
      await _until(tester, _row(shed));
      await tester.pumpAndSettle();
      expect(app.stackNames().last, TagCatalogRoute.name);
      expect(_searchText(tester), 'са');
      expect(
        _rowStatus(shed, l10n.tagCatalogAvailableForDraft),
        findsOneWidget,
      );
      expect(tagSet.current.tagIds, [home]);
      expect(app.storedTagNames(), ['Дом', 'Работа', 'Сад', 'Сарай']);
      expect(app.storedGraph(), graphBefore);

      // Отмена редактора не создаёт тег и сохраняет поиск и набор.
      await _tap(tester, _createTag);
      await _until(tester, _tagEditorName);
      await tester.enterText(_tagEditorName, 'Самовар');
      await _tap(tester, _tagEditorCancel);
      await _until(tester, _row(shed));
      await tester.pumpAndSettle();
      expect(app.stackNames().last, TagCatalogRoute.name);
      expect(_searchText(tester), 'са');
      expect(app.storedTagNames(), ['Дом', 'Работа', 'Сад', 'Сарай']);
      expect(tagSet.current.tagIds, [home]);

      // Новый тег входит в черновик только явным добавлением.
      await _tap(tester, _row(shed));
      expect(tagSet.current.tagIds, [home]);
      await _tap(tester, _addToDraft);
      expect(tagSet.current.tagIds, [home, shed]);

      // Возврат показывает ту же развёрнутую панель с прежней прокруткой.
      await _tap(tester, find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(app.stackNames(), [AppShellRoute.name, IntentionEditorRoute.name]);
      expect(_iconOf(tester, _resize), Icons.close_fullscreen);
      expect(tester.getRect(_sheet), sheetRect);
      expect(_fieldsScroll(tester).pixels, fieldsOffset);
      expect(_text(tester, 'intention-editor-title'), _rawTitle);
      expect(_text(tester, 'intention-editor-description'), _longDescription);
      expect(_chipNames(tester), ['Дом', 'Сарай']);
      expect(app.storedGraph(), graphBefore);

      // Повторное открытие выбора начинает новый поиск над тем же набором.
      await app.openChooser(tester);
      expect(app.chooserTagSet(), same(tagSet));
      expect(_searchText(tester), isEmpty);
      expect(_rowStatus(shed, l10n.tagCatalogInDraft), findsOneWidget);
      await _tap(tester, find.byType(BackButton));
      await tester.pumpAndSettle();

      // Сброс черновика не создаёт намерение и назначения, а созданный
      // выбором тег остаётся самостоятельной меткой.
      await _tap(tester, find.byKey(const ValueKey('intention-editor-close')));
      await tester.pumpAndSettle();
      await _tap(
        tester,
        find.byKey(const ValueKey('intention-editor-close-discard')),
      );
      await tester.pumpAndSettle();
      expectIntentionGraphRootPage(app.router);
      expect(app.storedGraph(), graphBefore);
      expect(app.storedTagNames(), ['Дом', 'Работа', 'Сад', 'Сарай']);
      expect(tagSet.current.availability, IntentionDraftAvailability.closed);

      // Новое открытие панели начинает пустой набор новой сессии.
      await app.openPanel(tester);
      expect(_chipNames(tester), isEmpty);
      expect(_iconOf(tester, _resize), Icons.open_in_full);
      await app.openChooser(tester);
      final nextTagSet = app.chooserTagSet();
      expect(nextTagSet, isNot(same(tagSet)));
      expect(nextTagSet.current.tagIds, isEmpty);
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
      await tester.tap(find.byKey(const ValueKey('intention-editor-close')));
      await tester.pump();
      await _until(tester, _row(home));
      await tester.pumpAndSettle();

      // Неизменённая панель закрылась сразу, а запоздалый выбор открыт над
      // каталогом с набором уже закрытой сессии.
      expect(app.stackNames(), [AppShellRoute.name, TagCatalogRoute.name]);
      final closedTagSet = app.chooserTagSet();
      expect(
        closedTagSet.current.availability,
        IntentionDraftAvailability.closed,
      );
      expect(find.text(l10n.tagCatalogDraftClosed), findsOneWidget);
      await _tap(tester, _row(home));
      expect(tester.widget<FilledButton>(_addToDraft).onPressed, isNull);
      expect(closedTagSet.current.tagIds, isEmpty);

      await _tap(tester, find.byType(BackButton));
      await tester.pumpAndSettle();
      expectIntentionGraphRootPage(app.router);

      // Новая панель получает собственный набор, на который прежний выбор
      // не влияет.
      await app.openPanel(tester);
      expect(_chipNames(tester), isEmpty);
      await app.openChooser(tester);
      final tagSet = app.chooserTagSet();
      expect(tagSet, isNot(same(closedTagSet)));
      await _tap(tester, _row(home));
      await _tap(tester, _addToDraft);
      expect(tagSet.current.tagIds, [home]);
      expect(closedTagSet.current.tagIds, isEmpty);
      await _tap(tester, find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(_chipNames(tester), ['Дом']);
      expect(app.storedTable('intentions'), isEmpty);
      expect(app.storedTable('tag_assignments'), isEmpty);
    },
  );
}

/// Приложение на Drift-адаптере in-memory хранилища с тегами «Дом»,
/// «Работа» и «Сад» и пустым каталогом намерений.
final class _App {
  _App(this.raw, this.router, this.l10n);

  final sqlite.Database raw;
  final StackRouter router;
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
      connectionFactory: () =>
          openInMemoryLocalDatabase(setup: (database) => raw = database),
      diagnosticsSink: InMemoryDiagnosticsSink(),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await runtime.shutdown();
    });
    final ready = (await tester.runAsync(runtime.bootstrap)) as AppRuntimeReady;
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
    final l10n = lookupAppLocalizations(locale);
    await tester.pumpWidget(MainApp(runtime: runtime));
    await openIntentionGraph(tester, waitFor: _until);
    await _until(tester, find.text(l10n.catalogActiveEmpty));
    await tester.pumpAndSettle();
    return _App(raw, ready.container.read(appRouterProvider), l10n);
  }

  /// Открывает панель создания кнопкой каталога.
  Future<void> openPanel(WidgetTester tester) async {
    await _tap(tester, find.byKey(const ValueKey('catalog-create-intention')));
    await _until(tester, _sheet);
    await tester.pumpAndSettle();
    expect(router.current.name, IntentionEditorRoute.name);
  }

  /// Открывает общий выбор тегов действием панели и ждёт каталог тегов.
  Future<void> openChooser(WidgetTester tester) async {
    await _tap(tester, _chooseTags);
    await _until(tester, _row(_tagId(_homeTag)));
    await tester.pumpAndSettle();
    expect(router.current.name, TagCatalogRoute.name);
  }

  /// Набор черновика, который панель передала открытому выбору.
  IntentionDraftTagSet chooserTagSet() => switch (router.current
      .argsAs<TagCatalogRouteArgs>()
      .selectionContext) {
    TagDraftContext(:final tagSet) => tagSet,
    final other => throw StateError('Выбор открыт не для черновика: $other'),
  };

  List<String> stackNames() => [
    for (final page in router.stack) page.routeData.name,
  ];

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

Finder _field(String key) => find.byKey(ValueKey(key));

Finder _row(TagId id) =>
    find.byKey(ValueKey('tag-catalog-row-${id.toCanonicalString()}'));

Finder _rowStatus(TagId id, String status) =>
    find.descendant(of: _row(id), matching: find.text(status));

Finder _chipRemove(TagId id) => find.byKey(
  ValueKey('intention-editor-tag-remove-${id.toCanonicalString()}'),
);

/// Названия выбранных тегов панели в показанном порядке.
List<String> _chipNames(WidgetTester tester) => [
  for (final chip
      in find
          .byWidgetPredicate(
            (widget) => switch (widget.key) {
              ValueKey<String>(:final value) =>
                value.startsWith('intention-editor-tag-') &&
                    !value.startsWith('intention-editor-tag-remove-'),
              _ => false,
            },
          )
          .evaluate())
    tester
        .widget<Text>(
          find.descendant(
            of: find.byWidget(chip.widget),
            matching: find.byType(Text),
          ),
        )
        .data!,
];

String _text(WidgetTester tester, String key) =>
    tester.widget<TextField>(_field(key)).controller!.text;

String _searchText(WidgetTester tester) =>
    tester.widget<TextField>(_search).controller!.text;

IconData? _iconOf(WidgetTester tester, Finder button) => tester
    .widget<Icon>(find.descendant(of: button, matching: find.byType(Icon)))
    .icon;

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

Future<void> _until(WidgetTester tester, Finder finder) =>
    _waitForStorage(tester, () => finder.evaluate().isNotEmpty);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _until(tester, finder);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}
