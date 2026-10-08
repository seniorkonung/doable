import 'dart:async';
import 'dart:ui' show SemanticsRole;

import 'package:auto_route/auto_route.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/intention/application/intention_catalog.dart'
    show IntentionSaved;
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/editor/intention_draft_tag_set.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_page.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_page.dart';
import 'package:doable/src/tag/presentation/catalog/tag_selection_context.dart';
import 'package:doable/src/tag/presentation/editor/tag_editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/app_root_pages.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/tag_storage_fixture.dart';
import '../support/in_memory_quick_creation_mode_store.dart';

const _homeTag = 301;
const _workTag = 302;
const _gardenTag = 303;

const _rawTitle = '  Купить семена ';
const _description = 'Для грядок у дома';

/// Описание, которое не помещается в компактную панель и прокручивается.
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
final _favorite = find.byKey(const ValueKey('intention-editor-favorite'));
final _readiness = find.byKey(const ValueKey('intention-editor-readiness'));
final _readinessConfirmation = find.byKey(
  const ValueKey('intention-editor-readiness-confirmation'),
);
final _readinessConfirm = find.byKey(
  const ValueKey('intention-editor-readiness-confirm'),
);
final _close = find.byKey(const ValueKey('intention-editor-close'));
final _closeConfirmation = find.byKey(
  const ValueKey('intention-editor-close-confirmation'),
);
final _closeContinue = find.byKey(
  const ValueKey('intention-editor-close-continue'),
);
final _search = find.byKey(const ValueKey('tag-catalog-search'));
final _addToDraft = find.byKey(const ValueKey('tag-catalog-add-to-draft'));
final _createTag = find.byKey(const ValueKey('tag-catalog-create'));
final _tagEditorName = find.byKey(const ValueKey('tag-editor-name'));
final _tagEditorSubmit = find.byKey(const ValueKey('tag-editor-submit'));
final _tagEditorCancel = find.byKey(const ValueKey('tag-editor-cancel'));
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
      _expectCompactPanel(tester);
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
    'выбор из компактной панели сохраняет поиск при сохранении и отмене '
    'настоящего редактора, не включает новый тег без явного добавления, '
    'возвращает ту же панель и её прокрутку, а сброс черновика сохраняет '
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
      final sheetElement = tester.element(_sheet);

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

      // Возврат показывает ту же компактную панель с прежней прокруткой.
      await _tap(tester, find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(app.stackNames(), [AppShellRoute.name, IntentionEditorRoute.name]);
      expect(tester.element(_sheet), same(sheetElement));
      _expectCompactPanel(tester);
      expect(tester.getRect(_sheet), sheetRect);
      expect(_fieldsScroll(tester).pixels, fieldsOffset);
      expect(_text(tester, 'intention-editor-title'), _rawTitle);
      expect(_text(tester, 'intention-editor-description'), _longDescription);
      expect(_chipNames(tester), ['Дом', 'Сарай']);
      expect(app.storedGraph(), graphBefore);
      // Сообщение о созданном теге видно и над вернувшейся панелью.
      await app.closeMessage(tester);

      // Повторное открытие выбора начинает новый поиск над тем же набором.
      await app.openChooser(tester);
      expect(app.chooserTagSet(), same(tagSet));
      expect(_searchText(tester), isEmpty);
      expect(_rowStatus(shed, l10n.tagCatalogInDraft), findsOneWidget);
      await _tap(tester, find.byType(BackButton));
      await tester.pumpAndSettle();

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
      expect(tagSet.current.availability, IntentionDraftAvailability.closed);

      // Новое открытие панели начинает пустой набор новой сессии.
      await app.openPanel(tester);
      expect(_chipNames(tester), isEmpty);
      _expectCompactPanel(tester);
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
    'все пять полей, подготовленные в панели и общем выборе, переживают '
    'объяснение готовности, переходы из компактной панели в выбор '
    'и настоящий редактор тега и продолжение после запроса закрытия, а '
    'гонка выбора и сохранения записывает актуальный черновик только '
    'после возврата и нового «Сохранить»',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final app = await _App.start(tester);
      final l10n = app.l10n;
      final home = _tagId(_homeTag);
      final creations = <IntentionCommandCompletion>[];
      final subscription = app.coordinator.completions.listen((completion) {
        if (completion is IntentionCommandCompletion) creations.add(completion);
      });
      addTearDown(subscription.cancel);

      /// Панель показывает текст, обе включённые отметки и набор [tags].
      void expectPreparedFields(List<String> tags) {
        expect(_text(tester, 'intention-editor-title'), _rawTitle);
        expect(_text(tester, 'intention-editor-description'), _description);
        expect(_iconOf(tester, _favorite), Icons.star);
        expect(_iconOf(tester, _readiness), Icons.check_circle);
        expect(_chipNames(tester), tags);
      }

      await app.openPanel(tester);
      await tester.enterText(_field('intention-editor-title'), _rawTitle);
      await tester.enterText(
        _field('intention-editor-description'),
        _description,
      );
      await _tap(tester, _favorite);
      final graphBefore = app.storedGraph();

      // Объяснение готовности — временная поверхность над той же панелью:
      // подтверждение меняет только черновик.
      await _tap(tester, _readiness);
      await tester.pumpAndSettle();
      expect(_readinessConfirmation, findsOneWidget);
      expect(_text(tester, 'intention-editor-title'), _rawTitle);
      await _tap(tester, _readinessConfirm);
      await tester.pumpAndSettle();
      expect(_readinessConfirmation, findsNothing);
      expect(app.stackNames(), [AppShellRoute.name, IntentionEditorRoute.name]);
      expectPreparedFields([]);
      expect(app.storedGraph(), graphBefore);

      _expectCompactPanel(tester);
      final sheetElement = tester.element(_sheet);

      // Первый тег уже принадлежит исходному черновику до гонки действий.
      await _expectProtectedNavigation(tester);
      await app.openChooser(tester);
      await _expectProtectedNavigation(tester);
      expect(find.byTooltip(l10n.tagNavigationTitle), findsNothing);
      final tagSet = app.chooserTagSet();
      await _tap(tester, _row(home));
      await _tap(tester, _addToDraft);
      await _tap(tester, find.byType(BackButton));
      await tester.pumpAndSettle();
      expectPreparedFields(['Дом']);
      final formRoute = app.router.stackData.last;
      final staleSubmit = tester.widget<FilledButton>(_submit).onPressed!;

      // Между быстрыми нажатиями нет кадра с обновлёнными кнопками.
      await tester.tap(_chooseTags);
      await tester.tap(_submit);
      await _until(tester, _row(home));
      await tester.pumpAndSettle();
      await _letStorageRun(tester);
      expect(app.chooserTagSet(), same(tagSet));
      expect(app.router.stackData[1], same(formRoute));
      expect(tagSet.current.tagIds, [home]);
      expect(creations, isEmpty);
      expect(app.storedGraph(), graphBefore);
      expect(app.stackNames(), [
        AppShellRoute.name,
        IntentionEditorRoute.name,
        TagCatalogRoute.name,
      ]);

      // Выбор и настоящий редактор над компактной панелью: существующий тег
      // и созданный самостоятельной операцией входят в набор только явным
      // добавлением.
      await _tap(tester, _createTag);
      await _until(tester, _tagEditorName);
      await tester.pumpAndSettle();
      await _expectProtectedNavigation(tester);
      staleSubmit();
      await _letStorageRun(tester);
      expect(creations, isEmpty);
      expect(app.storedGraph(), graphBefore);
      await tester.enterText(_tagEditorName, 'Сарай');
      await _tap(tester, _tagEditorSubmit);
      await _waitForStorage(tester, () => _tagEditorName.evaluate().isEmpty);
      final shed = app.storedTagId('Сарай');
      await app.closeMessage(tester);
      await _until(tester, _row(shed));
      await tester.pumpAndSettle();
      expect(tagSet.current.tagIds, [home]);
      await _tap(tester, _row(shed));
      await _tap(tester, _addToDraft);
      expect(tagSet.current.tagIds, [home, shed]);
      await _tap(tester, find.byType(BackButton));
      await tester.pumpAndSettle();

      // Возврат показывает ту же компактную панель со всеми пятью полями;
      // граф получил только самостоятельный тег.
      expect(app.stackNames(), [AppShellRoute.name, IntentionEditorRoute.name]);
      expect(tester.element(_sheet), same(sheetElement));
      _expectCompactPanel(tester);
      expectPreparedFields(['Дом', 'Сарай']);
      expect(app.storedGraph(), graphBefore);
      expect(app.storedTagNames(), ['Дом', 'Работа', 'Сад', 'Сарай']);
      await _letStorageRun(tester);
      expect(creations, isEmpty);
      expect(tester.widget<FilledButton>(_submit).onPressed, isNotNull);

      expect(_closeConfirmation, findsNothing);

      // Продолжение после запроса закрытия оставляет ту же сессию.
      await _tap(tester, _close);
      await tester.pumpAndSettle();
      expect(_closeConfirmation, findsOneWidget);
      await _tap(tester, _closeContinue);
      await tester.pumpAndSettle();
      expect(_closeConfirmation, findsNothing);
      expect(app.stackNames(), [AppShellRoute.name, IntentionEditorRoute.name]);
      expect(tester.element(_sheet), same(sheetElement));
      _expectCompactPanel(tester);
      expectPreparedFields(['Дом', 'Сарай']);
      expect(tagSet.current.tagIds, [home, shed]);
      expect(tagSet.current.availability, IntentionDraftAvailability.editable);
      expect(app.storedGraph(), graphBefore);

      // Отметки сообщают назначение и включённое состояние черновика.
      expect(
        tester.getSemantics(_favorite),
        isSemantics(
          label: l10n.editorFavoriteOption,
          hasToggledState: true,
          isToggled: true,
        ),
      );
      expect(
        tester.getSemantics(_readiness),
        isSemantics(
          label: l10n.editorReadinessOption,
          hasToggledState: true,
          isToggled: true,
        ),
      );
      expect(find.byTooltip(l10n.editorFavoriteOptionOn), findsOneWidget);
      expect(find.byTooltip(l10n.editorReadinessOptionOn), findsOneWidget);

      // Только «Сохранить» записывает намерение со всеми пятью полями.
      // В обратном порядке выбор тегов не открывается даже до нового кадра.
      final submit = tester.widget<FilledButton>(_submit).onPressed!;
      final chooseTags = tester.widget<IconButton>(_chooseTags).onPressed!;
      submit();
      chooseTags();
      await _waitForStorage(tester, () => _sheet.evaluate().isEmpty);
      expect(creations, hasLength(1));
      final id = switch (creations.single.result) {
        ResultSuccess(value: IntentionSaved(:final intention)) => intention.id,
        final result => fail('Создание не подтверждено: $result'),
      };
      expect(app.router.current.name, IntentionDetailsRoute.name);
      expect(
        app.router.current.argsAs<IntentionDetailsRouteArgs>().intentionId,
        id,
      );
      expect(app.stackNames(), [
        AppShellRoute.name,
        IntentionDetailsRoute.name,
      ]);
      final page = find.byType(IntentionDetailsPage);
      await _until(
        tester,
        find.byKey(const ValueKey('intention-details-title')),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<IntentionDetailsPage>(page).intentionId, id);
      expect(
        find.descendant(of: page, matching: find.text(_rawTitle.trim())),
        findsOneWidget,
      );
      expect(
        find.descendant(of: page, matching: find.text(_description)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: page, matching: find.text(l10n.catalogReady)),
        findsOneWidget,
      );
      expect(
        _iconOf(
          tester,
          find.byKey(const ValueKey('intention-details-favorite-mark')),
        ),
        Icons.star,
      );
      for (final (tag, name) in [(home, 'Дом'), (shed, 'Сарай')]) {
        final row = find.byKey(
          ValueKey('tag-assignment-row-${tag.toCanonicalString()}'),
        );
        await tester.scrollUntilVisible(
          row,
          200,
          scrollable: find.descendant(
            of: page,
            matching: find.byType(Scrollable),
          ),
        );
        await _until(tester, row);
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: row, matching: find.text(name)),
          findsOneWidget,
        );
      }
      expect(find.byType(AppNavigationBar), findsOneWidget);
      expect(
        find.byType(NavigationDestination, skipOffstage: false).hitTestable(),
        findsExactly(3),
      );
      expect(
        find.semantics.byPredicate((node) => node.role == SemanticsRole.tab),
        findsExactly(3),
      );
      expect(
        find.byType(IntentionEditorPage, skipOffstage: false),
        findsNothing,
      );
      expect(_closeConfirmation, findsNothing);

      final created = app.raw
          .select(
            'SELECT id, title, description, is_action_ready FROM intentions',
          )
          .single;
      expect(created['id'], id.toCanonicalString());
      expect(created['title'], _rawTitle.trim());
      expect(created['description'], _description);
      expect(created['is_action_ready'], 1);
      expect(
        [
          for (final row in app.raw.select(
            'SELECT intention_id FROM favorite_intentions',
          ))
            row['intention_id'],
        ],
        [created['id']],
      );
      expect(
        [
          for (final row in app.raw.select(
            'SELECT intention_id, tag_id FROM tag_assignments ORDER BY rowid',
          ))
            (row['intention_id'], row['tag_id']),
        ],
        [
          (created['id'], home.toCanonicalString()),
          (created['id'], shed.toCanonicalString()),
        ],
      );

      // Дополнительные кадры сохраняют одну запись, один маршрут и одно
      // сообщение успеха до возвращения в каталог.
      final detailsRoute = app.router.stackData.last;
      final savedGraph = app.storedGraph();
      await _until(tester, _message);
      expect(
        find.text(
          l10n.graphOperationMessage(
            l10n.graphOperationCreate,
            _rawTitle.trim(),
            l10n.editorCreated,
          ),
        ),
        findsOneWidget,
      );
      await app.closeMessage(tester);
      await tester.pump(const Duration(seconds: 1));
      await _letStorageRun(tester);
      expect(_message, findsNothing);
      expect(creations, hasLength(1));
      expect(app.storedGraph(), savedGraph);
      expect(app.router.stackData.last, same(detailsRoute));

      // «Назад» возвращает каталог, минуя завершённую панель и её диалог.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(app.stackNames(), [AppShellRoute.name]);
      expect(
        find.byType(IntentionEditorPage, skipOffstage: false),
        findsNothing,
      );
      expect(_closeConfirmation, findsNothing);
      expect(find.byType(AppNavigationBar), findsOneWidget);
      expect(creations, hasLength(1));
      expect(
        id.toCanonicalString(),
        app.raw.select('SELECT id FROM intentions').single['id'],
      );
      expectIntentionGraphRootPage(app.router);
      expect(tagSet.current.availability, IntentionDraftAvailability.closed);
      semantics.dispose();
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
        app.coordinator.acceptTagRename(
          RenameTag(tagId: home, name: TagName.fromInput('Быт')),
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
          CreateTag(TagName.fromInput('Быт')),
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
    return _App(
      raw,
      ready.container.read(appRouterProvider),
      ready.container.read(graphCommandCoordinatorProvider.notifier),
      l10n,
    );
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

Finder _chipRemove(TagId id) => find.byKey(
  ValueKey('intention-editor-tag-remove-${id.toCanonicalString()}'),
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

/// Модальная сессия и её задачи не дают добраться до основной навигации
/// нажатием, экранным диктором или последовательным обходом фокуса.
Future<void> _expectProtectedNavigation(WidgetTester tester) async {
  expect(
    find.byType(NavigationDestination, skipOffstage: false).hitTestable(),
    findsNothing,
  );
  expect(
    find.semantics.byPredicate((node) => node.role == SemanticsRole.tab),
    findsNothing,
  );
  for (var step = 0; step < 12; step++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<AppNavigationBar>(),
      isNull,
    );
  }
}
