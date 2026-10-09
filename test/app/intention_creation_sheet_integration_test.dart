import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/data/local/app_database.dart'
    show
        LocalDatabaseConnectionObserver,
        LocalDatabaseSqlStatement,
        observeConfiguredLocalDatabaseConnection,
        openFileBackedLocalDatabase;
import 'package:doable/src/favorite/presentation/home/home_page.dart';
import 'package:doable/src/favorite/presentation/home/home_state.dart';
import 'package:doable/src/favorite/presentation/home/home_view_model.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/presentation/graph_operation_presenter.dart';
import 'package:doable/src/intention/application/intention_catalog.dart'
    show
        IntentionCatalogCreated,
        IntentionCatalogFirstPage,
        IntentionCatalogOrder,
        IntentionCatalogQuery,
        IntentionReadinessFilter,
        IntentionSaved,
        IntentionScope,
        IntentionSummary,
        IntentionTagFilter;
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_state.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/details/intention_details_state.dart';
import 'package:doable/src/intention/presentation/details/intention_details_view_model.dart';
import 'package:doable/src/intention/presentation/editor/intention_draft_tag_set.dart';
import 'package:doable/src/intention/presentation/intention_summary_view.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/presentation/assignments/tag_assignments_state.dart';
import 'package:doable/src/tag/presentation/assignments/tag_assignments_view_model.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_page.dart';
import 'package:doable/src/tag/presentation/catalog/tag_selection_context.dart';
import 'package:doable/src/tag/presentation/navigation/tag_navigation_page.dart';
import 'package:doable/src/tag/presentation/navigation/tag_navigation_state.dart';
import 'package:doable/src/tag/presentation/navigation/tag_navigation_view_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/app_root_pages.dart';
import '../support/favorite_storage_fixture.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/intention_creation_origin.dart';
import '../support/intention_creation_storage_observer.dart';
import '../support/local_database_harness.dart';
import '../support/tag_storage_fixture.dart';
import '../support/in_memory_quick_creation_mode_store.dart';
import '../support/quick_creation.dart';

// Названия намерений и тегов — данные человека: они одинаковы в обеих
// локалях.

/// «Гулять» — активное готовое избранное на месте 1 с тегом «Дом»; название
/// не совпадает с поиском каталога.
const _walk = 1;

/// «Плавать» — активное неготовое избранное на месте 2 без тегов.
const _swim = 2;

/// «Читать» — архивированное избранное на последнем месте 3 единого порядка.
const _read = 3;

/// «Рисовать на работе» — теги «Дом» и «Работа»: исключённый тег убирает его
/// из выдачи каталога.
const _atWork = 4;

/// «Рисовать в саду» — только тег «Сад»: без обязательного «Дом» в выдачу не
/// входит.
const _inGarden = 5;

/// Уже существовавшее одноимённое намерение без тегов и отметок.
const _namesake = 6;

/// Этюды с тегом «Дом» совпадают со всеми условиями выдачи каталога; каждый
/// четвёртый архивирован и виден, потому что каталог показывает оба охвата.
const _firstSketch = 11;
const _sketchCount = 16;

const _homeTag = 301;
const _gardenTag = 302;
const _workTag = 303;

const _tagNames = {_homeTag: 'Дом', _gardenTag: 'Сад', _workTag: 'Работа'};

/// Текст поиска каталога: ему соответствуют этюды и создаваемое намерение.
const _catalogFilter = 'рисовать';

/// Сырое название черновика: создание нормализует его в [_title].
const _rawTitle = '  Рисовать акварель ';
const _title = 'Рисовать акварель';
const _description = 'Пейзаж у реки';

/// Тег, который человек создаёт настоящим редактором из общего выбора.
const _sport = 'Спорт';

/// Название намерения, созданного с минимальными данными: поиску каталога
/// оно не соответствует.
const _minimalTitle = 'Лепить';

/// Таблицы, в которые пишет только создание намерения.
const _creationTables = [
  'intentions',
  'intention_titles_fts',
  'tag_assignments',
  'favorite_intentions',
];

final _catalogList = find.byKey(
  const PageStorageKey<String>('intention-catalog-list'),
);
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
final _submit = find.byKey(const ValueKey('intention-editor-submit'));
final _addToDraftAction = find.byKey(
  const ValueKey('tag-catalog-add-to-draft'),
);
final _createTagAction = find.byKey(const ValueKey('tag-catalog-create'));
final _tagEditorName = find.byKey(const ValueKey('tag-editor-name'));
final _tagEditorSubmit = find.byKey(const ValueKey('tag-editor-submit'));
final _message = find.byKey(const ValueKey('graph-operation-message'));

/// Сквозная проверка быстрого создания намерения: меню и кнопка общей
/// панели, компактная форма, общий выбор тегов и настоящий редактор тега
/// на настоящих AppRouter, сессии черновика, координаторе команд, общей
/// поверхности сообщений и Drift-адаптере через настроенное файловое
/// соединение.
///
/// Команду создания формирует только сама панель по нажатию «Сохранить».
/// Записи видны через наблюдатель соединения, граф — по строкам хранилища и
/// публичным чтениям модуля графа, результат — по завершениям координатора и
/// сообщениям общей поверхности, согласование — по подтверждённым снимкам
/// каталога, Главной и навигации по тегу и по видимой выдаче каталога.
///
/// Навигация по тегу — страница поверх корневой: под модальной панелью,
/// открытой из каталога, она существовать не может. Поэтому её проверка
/// открывает навигацию после результата, а заранее загруженной и скрытой во
/// время создания остаётся Главная.
void main() {
  for (final origin in [
    IntentionCreationOrigin.graph,
    IntentionCreationOrigin.deep,
  ]) {
    for (final point in _CreatedNavigationFailure.values) {
      for (final close
          in point == _CreatedNavigationFailure.beforeRemoval
              ? _CloseMethod.values
              : [_CloseMethod.back]) {
        testWidgets(
          'отказ перехода ${point.description} над ${origin.description}: ${close.description} сохраняет успех и новую сессию',
          (tester) async {
            final install = await _install(tester, const Locale('ru'));
            final router = _FailingCreatedRouteRouter(
              synchronous: false,
              point: point,
            );
            final storage = IntentionCreationStorageObserver(
              snapshotGraph: _storedGraph,
            );
            final app = await _launch(
              tester,
              install,
              seed: _seedGraph,
              navigationRouter: router,
              storage: storage,
            );
            await openIntentionGraph(tester, waitFor: _until);
            final history = await origin.open(
              tester,
              router,
              participantId: _intentionId(_walk),
              waitFor: _until,
            );
            await _openSheet(tester, app);
            await tester.enterText(
              find.byKey(const ValueKey('intention-editor-title')),
              _title,
            );
            final staleClose = tester
                .widget<IconButton>(
                  find.byKey(const ValueKey('intention-editor-close')),
                )
                .onPressed!;
            storage.observeCreation();
            storage.hold();
            await _tap(tester, _submit);
            await _waitFor(tester, () => storage.isHolding);
            VoidCallback? staleDiscard;
            if (point == _CreatedNavigationFailure.beforeRemoval) {
              staleClose();
              await tester.pumpAndSettle();
              expect(
                find.text(app.l10n.editorCloseSavingMessage),
                findsOneWidget,
              );
              staleDiscard = tester
                  .widget<FilledButton>(
                    find.byKey(
                      const ValueKey('intention-editor-close-discard'),
                    ),
                  )
                  .onPressed!;
            }
            final errors = <FlutterErrorDetails>[];
            final previousHandler = FlutterError.onError;
            late IntentionCommandCompletion creation;
            RouteData? nextBeforeFailure;
            FlutterError.onError = errors.add;
            try {
              storage.release();
              creation = await _creation(tester, app);
              await _waitFor(tester, () => router.replacementAttempts == 1);
              if (point == _CreatedNavigationFailure.afterNewSession) {
                await tester.pumpAndSettle();
                expect(
                  router.current
                      .argsAs<IntentionDetailsRouteArgs>()
                      .intentionId,
                  _createdId(creation),
                );
                await tester.binding.handlePopRoute();
                await tester.pumpAndSettle();
                history.expectRestored(tester, router);
                await _acceptMessage(
                  tester,
                  app.l10n.graphOperationMessage(
                    app.l10n.graphOperationCreate,
                    _title,
                    app.l10n.editorCreated,
                  ),
                );
                await _openSheet(tester, app);
                nextBeforeFailure = router.stackData.last;
                await tester.enterText(
                  find.byKey(const ValueKey('intention-editor-title')),
                  'Черновик до позднего отказа',
                );
              }
              router.releaseFailure();
              await _waitFor(tester, () => errors.isNotEmpty);
              await tester.pumpAndSettle();
            } finally {
              FlutterError.onError = previousHandler;
            }
            expect(errors, hasLength(1));
            expect(errors.single.exception, same(router.failure));
            expect(storage.creationAttempts, 1);
            final id = _createdId(creation);
            _expectStoredIntention(
              app.raw,
              id,
              title: _title,
              description: null,
              readiness: IntentionReadiness.notReady,
            );
            history.expectPrefix(router);
            if (point == _CreatedNavigationFailure.afterNewSession) {
              staleClose();
              await tester.pumpAndSettle();
              expect(router.stackData.last, same(nextBeforeFailure));
              expect(
                _text(tester, 'intention-editor-title'),
                'Черновик до позднего отказа',
              );
              expect(router.replacementAttempts, 1);
              expect(_message, findsNothing);
              expect(app.completions.whereType<IntentionCommandCompletion>(), [
                same(creation),
              ]);
              expect(tester.takeException(), isNull);
              return;
            }
            if (point == _CreatedNavigationFailure.beforeRemoval) {
              expect(_sheet, findsOneWidget);
              expect(tester.widget<FilledButton>(_submit).onPressed, isNull);
              expect(
                find.byType(AlertDialog, skipOffstage: false),
                findsNothing,
              );
              await close.request(tester);
              await tester.pumpAndSettle();
            } else if (point == _CreatedNavigationFailure.afterResult) {
              expect(
                router.current.argsAs<IntentionDetailsRouteArgs>().intentionId,
                id,
              );
              staleClose();
              await tester.pumpAndSettle();
              expect(
                router.current.argsAs<IntentionDetailsRouteArgs>().intentionId,
                id,
              );
              await tester.binding.handlePopRoute();
              await tester.pumpAndSettle();
            }
            expect(_sheet, findsNothing);
            history.expectRestored(tester, router);
            await _acceptMessage(
              tester,
              app.l10n.graphOperationMessage(
                app.l10n.graphOperationCreate,
                _title,
                app.l10n.editorCreated,
              ),
            );
            await _openSheet(tester, app);
            final nextForm = router.stackData.last;
            await tester.enterText(
              find.byKey(const ValueKey('intention-editor-title')),
              'Новый черновик',
            );
            staleDiscard?.call();
            staleClose();
            await tester.pumpAndSettle();
            expect(router.stackData.last, same(nextForm));
            expect(_text(tester, 'intention-editor-title'), 'Новый черновик');
            expect(router.replacementAttempts, 1);
            expect(storage.creationAttempts, 1);
            expect(app.completions.whereType<IntentionCommandCompletion>(), [
              same(creation),
            ]);
            expect(find.byType(AlertDialog, skipOffstage: false), findsNothing);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
  for (final origin in IntentionCreationOrigin.values) {
    testWidgets(
      'общая кнопка над ${origin.description}: новый ID, теги и исходная история сохраняются без ожидания сообщения',
      (tester) async {
        final install = await _install(tester, const Locale('ru'));
        final app = await _launch(tester, install, seed: _seedGraph);
        await _searchCatalog(tester, app);
        await _scrollCatalog(tester);
        final catalogBefore = _catalog(app);
        final viewBefore = _catalogView(tester);
        final history = await origin.open(
          tester,
          app.router,
          participantId: _intentionId(_walk),
          waitFor: _until,
        );
        final sport = await _prepareFullDraft(
          tester,
          app,
          tags: [_homeTag, _workTag],
        );
        final previous =
            app.container
                    .read(graphCommandCoordinatorProvider.notifier)
                    .acceptTagRename(
                      RenameTag(
                        tagId: _tagId(_gardenTag),
                        name: TagName.fromInput('Огород'),
                      ),
                    )
                as TagCommandAccepted;
        await _readStorage(tester, () => previous.future);
        final previousMessage = app.l10n.graphOperationMessage(
          app.l10n.graphOperationUpdate,
          app.l10n.graphOperationTag,
          app.l10n.tagRenamed,
        );
        await _until(tester, find.text(previousMessage).hitTestable());
        await tester.pumpAndSettle();
        final snackbar = tester.widget<SnackBar>(
          find.byType(SnackBar).hitTestable(),
        );
        await _tap(tester, _submit);
        final creation = await _creation(tester, app);
        await _waitFor(tester, () => _sheet.evaluate().isEmpty);
        await _expectCreatedPage(
          tester,
          app,
          creation,
          title: _title,
          description: _description,
          tags: ['Дом', 'Работа', _sport],
          readiness: IntentionReadiness.ready,
          favoriteMark: FavoriteMark.favorite,
          history: history,
        );
        expect(_createdId(creation), isNot(_intentionId(_namesake)));
        expect(
          tester.widget<SnackBar>(find.byType(SnackBar).hitTestable()),
          same(snackbar),
        );
        expect(
          _storedAssignments(app.raw, _createdId(creation)),
          unorderedEquals([
            _tagId(_homeTag).toCanonicalString(),
            _tagId(_workTag).toCanonicalString(),
            sport.toCanonicalString(),
          ]),
        );
        history.expectPrefix(app.router);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        history.expectRestored(tester, app.router);
        await _waitFor(
          tester,
          () => _catalogCurrentAt(app, creation.revision!),
        );
        _expectSameSearch(_catalog(app), catalogBefore);
        expect(_ids(_catalog(app)), _ids(catalogBefore));
        expect(_catalog(app).totalCount, catalogBefore.totalCount);
        ScaffoldMessenger.of(tester.element(_message.hitTestable()))
            .hideCurrentSnackBar();
        await tester.pumpAndSettle();
        await _acceptMessage(
          tester,
          app.l10n.graphOperationMessage(
            app.l10n.graphOperationCreate,
            _title,
            app.l10n.editorCreated,
          ),
        );
        await _openSheet(tester, app);
        expect(_text(tester, 'intention-editor-title'), isEmpty);
        expect(_text(tester, 'intention-editor-description'), isEmpty);
        expect(_chipNames(tester), isEmpty);
        await _tap(
          tester,
          find.byKey(const ValueKey('intention-editor-close')),
        );
        await tester.pumpAndSettle();
        history.expectRestored(tester, app.router);
        await history.expectUnderlyingDraft(tester, app.router);
        if (origin == IntentionCreationOrigin.deep) {
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
        }
        if (origin != IntentionCreationOrigin.graph) {
          await _select(tester, AppDestination.intentionGraph);
        }
        _expectSameView(_catalogView(tester), viewBefore);
        expect(app.completions.whereType<IntentionCommandCompletion>(), [
          same(creation),
        ]);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final locale in const [Locale('ru'), Locale('en')]) {
    final code = locale.languageCode;

    testWidgets(
      'намерение, подготовленное через общую кнопку, панель, общий выбор и '
      'настоящий редактор тега, открывается по новому идентификатору при '
      'совпадении названия и сохраняется одним подтверждённым результатом, '
      'учитывается ровно один раз в выдаче с прежними условиями и позицией, '
      'отражается скрытой Главной и навигацией по тегам и читается после '
      'повторного открытия хранилища вместе с минимальным созданием на $code',
      (tester) async {
        final install = await _install(tester, locale);
        final l10n = install.l10n;
        final app = await _launch(tester, install, seed: _seedGraph);
        final home = _tagId(_homeTag);
        final marks = storedFavoriteMarks(app.raw);
        await _searchCatalog(tester, app);
        await _scrollCatalog(tester);
        final catalogBefore = _catalog(app);
        final viewBefore = _catalogView(tester);
        final graphBefore = _storedGraph(app.raw);
        final intentionsBefore = _storedIntentionIds(app.raw);
        _expectStoredIntention(
          app.raw,
          _intentionId(_namesake),
          title: _title,
          description: null,
          readiness: IntentionReadiness.notReady,
        );
        final events = app.diagnostics.events.length;
        expect(_home(app), isA<HomeList>());
        expect(app.completions, isEmpty);

        // Все пять полей черновика готовятся только через интерфейс панели,
        // общего выбора и редактора тега.
        app.writes.start();
        final sport = await _prepareFullDraft(tester, app, tags: [_homeTag]);
        expect(_text(tester, 'intention-editor-title'), _rawTitle);
        expect(_text(tester, 'intention-editor-description'), _description);
        expect(_iconOf(tester, _favorite), Icons.star);
        expect(_iconOf(tester, _readiness), Icons.check_circle);
        expect(_chipNames(tester), ['Дом', _sport]);

        // До отправки граф получил только самостоятельный тег: ни намерения,
        // ни назначений, ни избранного, а ревизию продвинуло лишь создание
        // тега.
        final tagCompletion = app.completions.single as TagCommandCompletion;
        expect(app.writes.take(), [
          (write: 'insert tags', inTransaction: true),
        ]);
        expect(_storedCreationTables(app.raw), _creationTablesOf(graphBefore));
        expect(_storedTagNames(app.raw), ['Дом', 'Сад', 'Работа', _sport]);
        final revisionBeforeSave = await _freshRevision(tester, app);
        expect(
          revisionBeforeSave.compareTo(tagCompletion.revision!),
          GraphRevisionOrder.same,
        );

        // «Сохранить» записывает всё начальное состояние внутри транзакции
        // без посторонних записей и подтверждает его одним результатом на
        // одной ревизии. Оба обработчика получены до нового кадра: выбор
        // тегов после принятой отправки не открывает страницу.
        final submit = tester.widget<FilledButton>(_submit).onPressed!;
        final chooseTags = tester.widget<IconButton>(_chooseTags).onPressed!;
        submit();
        chooseTags();
        final creation = await _creation(tester, app);
        await _waitFor(tester, () => _sheet.evaluate().isEmpty);
        await _expectCreatedPage(
          tester,
          app,
          creation,
          title: _title,
          description: _description,
          tags: ['Дом', _sport],
          readiness: IntentionReadiness.ready,
          favoriteMark: FavoriteMark.favorite,
        );
        final created = _createdId(creation);
        expect(created, isNot(_intentionId(_namesake)));
        expect(
          app.raw
              .select(
                'SELECT id FROM intentions WHERE title = ? ORDER BY rowid',
                [_title],
              )
              .map((row) => row['id']),
          [
            _intentionId(_namesake).toCanonicalString(),
            created.toCanonicalString(),
          ],
        );
        _expectStoredIntention(
          app.raw,
          _intentionId(_namesake),
          title: _title,
          description: null,
          readiness: IntentionReadiness.notReady,
        );
        final revision = creation.revision!;
        expect(app.completions, [same(tagCompletion), same(creation)]);
        expect(app.writes.take(), _fullCreationWrites(tags: 2));
        _expectConfirmedPackage(
          creation,
          tags: ['Дом', _sport],
          readiness: IntentionReadiness.ready,
          favoriteMark: FavoriteMark.favorite,
        );
        expect(_storedIntentionIds(app.raw), [...intentionsBefore, created]);
        _expectStoredIntention(
          app.raw,
          created,
          title: _title,
          description: _description,
          readiness: IntentionReadiness.ready,
        );
        expect(_storedAssignments(app.raw, created), [
          home.toCanonicalString(),
          sport.toCanonicalString(),
        ]);
        // Место нового избранного — после архивированного последнего места.
        expect(storedFavoriteMarks(app.raw), [
          ...marks,
          (created.toCanonicalString(), 4),
        ]);

        // Каталог и скрытая Главная согласуются с той же ревизией без нового
        // чтения выдачи.
        await _waitFor(
          tester,
          () => _currentAt(app, revision),
          reason: () => '${_home(app)} ${_catalogState(app)}',
        );
        await _closeCreatedPage(tester, app);
        expectIntentionGraphRootPage(app.router);
        expect(_selected(tester), AppDestination.intentionGraph);
        final homeList = _home(app) as HomeList;
        expect(
          [for (final row in homeList.items) row.id],
          [_intentionId(_walk), _intentionId(_swim), created],
        );
        expect(homeList.items.last.title, _title);
        expect(homeList.items.last.readiness, IntentionReadiness.ready);

        await _acceptMessage(
          tester,
          l10n.graphOperationMessage(
            l10n.graphOperationCreate,
            _title,
            l10n.editorCreated,
          ),
        );
        expect(_commandEvents(app, since: events), [
          _tagCreateEvent(),
          _createEvent(IntentionCreationCommandDiagnosticsStage.resultRead),
        ]);

        // Подходящее намерение учтено ровно один раз в начале выдачи по
        // изменению; условия, выдача и видимые строки остались прежними.
        final catalog = _catalog(app);
        _expectSameSearch(catalog, catalogBefore);
        expect(catalog.totalCount, catalogBefore.totalCount + 1);
        expect(_ids(catalog), [created, ..._ids(catalogBefore)]);
        final summary = catalog.items.first;
        expect(summary.title, _title);
        expect(summary.hasDescription, isTrue);
        expect(summary.readiness, IntentionReadiness.ready);
        expect(summary.archiveState, IntentionArchiveState.active);
        expect(summary.favoriteMark, FavoriteMark.favorite);
        expect(summary.createdAt.value, summary.updatedAt.value);
        expect(
          [for (final tag in summary.tags) tag.name.value],
          ['Дом', _sport],
        );
        // Новая строка встала над видимыми: список сдвинулся на неё, а
        // видимые строки остались на своих местах экрана.
        final viewAfter = _catalogView(tester);
        expect(viewAfter.page, viewBefore.page);
        expect(viewAfter.rows, viewBefore.rows);
        expect(viewAfter.list, greaterThan(viewBefore.list));

        // Над прежними строками видна одна строка нового намерения.
        await _scrollCatalogToTop(tester);
        final createdRows = find.descendant(
          of: _catalogList,
          matching: find.widgetWithText(IntentionSummaryView, _title),
        );
        expect(createdRows, findsOneWidget);
        expect(_visibleCatalogRows(tester).first.title, _title);
        expect(
          find.descendant(
            of: createdRows,
            matching: find.text(l10n.intentionSummaryTags('Дом, $_sport')),
          ),
          findsOneWidget,
        );

        // Навигация по каждому выбранному тегу показывает новое намерение
        // ровно один раз на ревизии создания.
        await _openTagNavigation(tester, app, home);
        _expectNavigationAt(tester, home, revision);
        expect(_navigationIds(tester, home), [
          _intentionId(_walk),
          _intentionId(_atWork),
          for (final number in _activeSketches) _intentionId(number),
          created,
        ]);
        await _closeTop(tester, TagNavigationPage);
        await _openTagNavigation(tester, app, sport, fromTagCatalog: true);
        _expectNavigationAt(tester, sport, revision);
        expect(_navigationIds(tester, sport), [created]);
        await _closeTop(tester, TagNavigationPage);
        await _closeTop(tester, TagCatalogPage);
        expectIntentionGraphRootPage(app.router);

        // Минимальное создание через ту же кнопку по-прежнему даёт пустой
        // набор и выключенные отметки, не попадает в неподходящую выдачу и
        // не затрагивает избранное Главной.
        final catalogAfterFull = _catalog(app);
        final homeAfterFull = _home(app);
        await _openSheet(tester, app);
        await tester.enterText(
          find.byKey(const ValueKey('intention-editor-title')),
          _minimalTitle,
        );
        await _tap(tester, _submit);
        final minimalCreation = await _creation(tester, app, count: 2);
        await _waitFor(tester, () => _sheet.evaluate().isEmpty);
        await _expectCreatedPage(
          tester,
          app,
          minimalCreation,
          title: _minimalTitle,
          description: null,
          tags: [],
          readiness: IntentionReadiness.notReady,
          favoriteMark: FavoriteMark.notFavorite,
        );
        final minimal = _createdId(minimalCreation);
        expect(app.completions.last, same(minimalCreation));
        expect(app.writes.take(), _minimalCreationWrites);
        _expectConfirmedPackage(
          minimalCreation,
          tags: [],
          readiness: IntentionReadiness.notReady,
          favoriteMark: FavoriteMark.notFavorite,
        );
        _expectStoredIntention(
          app.raw,
          minimal,
          title: _minimalTitle,
          description: null,
          readiness: IntentionReadiness.notReady,
        );
        expect(_storedAssignments(app.raw, minimal), isEmpty);
        expect(storedFavoriteMarks(app.raw), [
          ...marks,
          (created.toCanonicalString(), 4),
        ]);
        await _waitFor(
          tester,
          () => _catalogCurrentAt(app, minimalCreation.revision!),
          reason: () => '${_catalogState(app)}',
        );
        await _acceptMessage(
          tester,
          l10n.graphOperationMessage(
            l10n.graphOperationCreate,
            _minimalTitle,
            l10n.editorCreated,
          ),
        );
        _expectSameSearch(_catalog(app), catalogBefore);
        expect(_ids(_catalog(app)), _ids(catalogAfterFull));
        expect(_catalog(app).totalCount, catalogAfterFull.totalCount);
        expect(_home(app), same(homeAfterFull));

        // Ранее скрытая Главная показывает новое избранное в конце.
        await _closeCreatedPage(tester, app, systemBack: true);
        await _select(tester, AppDestination.home);
        expect(_shownHome(tester), ['Гулять', 'Плавать', _title]);
        expect(_message, findsNothing);
        expect(tester.takeException(), isNull);

        // После повторного открытия файлового хранилища полный и минимальный
        // результаты читаются через публичную границу модуля графа.
        await app.shutdown(tester);
        final reopened = await _launch(tester, install);
        expect(_shownHome(tester), ['Гулять', 'Плавать', _title]);
        await _expectDurableIntention(
          tester,
          reopened,
          created,
          title: _title,
          description: _description,
          readiness: IntentionReadiness.ready,
          favoriteMark: FavoriteMark.favorite,
          tags: ['Дом', _sport],
        );
        await _expectDurableIntention(
          tester,
          reopened,
          minimal,
          title: _minimalTitle,
          description: null,
          readiness: IntentionReadiness.notReady,
          favoriteMark: FavoriteMark.notFavorite,
          tags: [],
        );
        expect(await _favoriteIds(tester, reopened), [
          _intentionId(_walk),
          _intentionId(_swim),
          created,
        ]);
        final found = await _catalogPage(tester, reopened, catalogBefore.query);
        expect(found.totalCount, catalogBefore.totalCount + 1);
        expect(
          [for (final item in found.items) item.id],
          [created, ..._ids(catalogBefore)],
        );
        expect(tester.takeException(), isNull);
      },
    );

    for (final synchronous in [true, false]) {
      for (final systemBack in [false, true]) {
        testWidgets(
          '${synchronous ? 'синхронный' : 'асинхронный'} отказ открытия после записи возвращает сохранённый каталог ${systemBack ? 'системным «назад»' : 'кнопкой закрытия'} на $code',
          (tester) async {
            final install = await _install(tester, locale);
            final router = _FailingCreatedRouteRouter(synchronous: synchronous);
            final app = await _launch(
              tester,
              install,
              seed: _seedGraph,
              navigationRouter: router,
            );
            await _searchCatalog(tester, app);
            await _scrollCatalog(tester);
            final shell = router.stackData.first;
            final catalogBefore = _catalog(app);
            final viewBefore = _catalogView(tester);
            final idsBefore = _storedIntentionIds(app.raw);
            final marksBefore = storedFavoriteMarks(app.raw);
            final sport = await _prepareFullDraft(
              tester,
              app,
              tags: [_homeTag, _workTag],
            );
            final form = router.stackData.last;
            // Другая операция занимает общую поверхность до создания.
            final rename =
                app.container
                        .read(graphCommandCoordinatorProvider.notifier)
                        .acceptTagRename(
                          RenameTag(
                            tagId: _tagId(_gardenTag),
                            name: TagName.fromInput('Огород'),
                          ),
                        )
                    as TagCommandAccepted;
            final renamed = await _readStorage(tester, () => rename.future);
            expect(renamed.isFailure, isFalse);
            final previousMessage = install.l10n.graphOperationMessage(
              install.l10n.graphOperationUpdate,
              install.l10n.graphOperationTag,
              install.l10n.tagRenamed,
            );
            final successMessage = install.l10n.graphOperationMessage(
              install.l10n.graphOperationCreate,
              _title,
              install.l10n.editorCreated,
            );
            await _until(tester, _message.hitTestable());
            await tester.pumpAndSettle();
            expect(find.text(previousMessage).hitTestable(), findsOneWidget);
            final previousSnackBar = tester.widget<SnackBar>(
              find.byType(SnackBar).hitTestable(),
            );
            app.writes.start();
            final errors = <FlutterErrorDetails>[];
            final previousHandler = FlutterError.onError;
            FlutterError.onError = errors.add;
            late IntentionCommandCompletion creation;
            try {
              await _tap(tester, _submit);
              creation = await _creation(tester, app);
              await _waitFor(tester, () => router.replacementAttempts == 1);
              router.releaseFailure();
              await _waitFor(tester, () => errors.isNotEmpty);
              await _waitFor(tester, () => _currentAt(app, creation.revision!));
              await tester.pumpAndSettle();
            } finally {
              FlutterError.onError = previousHandler;
            }
            expect(errors, hasLength(1));
            expect(errors.single.exception, same(router.failure));
            expect(
              errors.single.context.toString(),
              contains('при открытии созданного намерения'),
            );
            expect(router.stackData, [same(shell), same(form)]);
            expect(
              tester.widget<SnackBar>(find.byType(SnackBar).hitTestable()),
              same(previousSnackBar),
            );
            expect(find.text(previousMessage).hitTestable(), findsOneWidget);
            expect(
              find.text(successMessage, skipOffstage: false),
              findsNothing,
            );
            expect(
              find.byKey(const ValueKey('intention-editor-failure')),
              findsNothing,
            );
            expect(tester.widget<FilledButton>(_submit).onPressed, isNull);
            expect(
              tester
                  .widget<TextField>(
                    find.byKey(const ValueKey('intention-editor-title')),
                  )
                  .readOnly,
              isTrue,
            );
            expect(app.writes.take(), _fullCreationWrites(tags: 3));
            final created = _createdId(creation);
            _expectStoredIntention(
              app.raw,
              created,
              title: _title,
              description: _description,
              readiness: IntentionReadiness.ready,
            );
            _expectConfirmedPackage(
              creation,
              tags: ['Дом', 'Работа', _sport],
              readiness: IntentionReadiness.ready,
              favoriteMark: FavoriteMark.favorite,
            );
            expect(_storedIntentionIds(app.raw), [...idsBefore, created]);
            expect(
              _storedAssignments(app.raw, created),
              unorderedEquals([
                _tagId(_homeTag).toCanonicalString(),
                _tagId(_workTag).toCanonicalString(),
                sport.toCanonicalString(),
              ]),
            );
            expect(storedFavoriteMarks(app.raw), [
              ...marksBefore,
              (created.toCanonicalString(), 4),
            ]);
            final savedGraph = _storedGraph(app.raw);

            if (systemBack) {
              await tester.binding.handlePopRoute();
            } else {
              await _tap(
                tester,
                find.byKey(const ValueKey('intention-editor-close')),
              );
            }
            await tester.pumpAndSettle();
            expectIntentionGraphRootPage(router);
            expect(router.stackData, [same(shell)]);
            expect(_sheet, findsNothing);
            expect(find.byType(AlertDialog, skipOffstage: false), findsNothing);
            expect(_selected(tester), AppDestination.intentionGraph);
            _expectSameSearch(_catalog(app), catalogBefore);
            expect(_ids(_catalog(app)), _ids(catalogBefore));
            expect(_catalog(app).totalCount, catalogBefore.totalCount);
            _expectSameView(_catalogView(tester), viewBefore);
            expect(find.text(previousMessage).hitTestable(), findsOneWidget);
            expect(
              find.text(successMessage, skipOffstage: false),
              findsNothing,
            );
            ScaffoldMessenger.of(tester.element(_message.hitTestable()))
                .hideCurrentSnackBar();
            await tester.pumpAndSettle();
            await _acceptMessage(tester, successMessage);
            expect(
              find.text(previousMessage, skipOffstage: false),
              findsNothing,
            );
            await tester.pump(const Duration(seconds: 5));
            await tester.pumpAndSettle();
            expect(find.byType(SnackBar, skipOffstage: false), findsNothing);

            // Выход вернул обычную навигацию и самостоятельное создание.
            await _select(tester, AppDestination.home);
            expect(_shownHome(tester), ['Гулять', 'Плавать', _title]);
            await _select(tester, AppDestination.intentionGraph);
            await _openSheet(tester, app);
            final nextForm = router.stackData.last;
            expect(nextForm, isNot(same(form)));
            expect(_text(tester, 'intention-editor-title'), isEmpty);
            expect(_text(tester, 'intention-editor-description'), isEmpty);
            expect(_chipNames(tester), isEmpty);
            expect(_iconOf(tester, _favorite), Icons.star_border);
            expect(_iconOf(tester, _readiness), Icons.check_circle_outline);
            await tester.enterText(
              find.byKey(const ValueKey('intention-editor-title')),
              'Другой черновик',
            );
            await tester.pump(const Duration(seconds: 5));
            await tester.pumpAndSettle();
            expect(router.stackData, [same(shell), same(nextForm)]);
            expect(_text(tester, 'intention-editor-title'), 'Другой черновик');
            expect(app.completions.whereType<IntentionCommandCompletion>(), [
              same(creation),
            ]);
            expect(router.replacementAttempts, 1);
            expect(app.writes.take(), isEmpty);
            expect(_storedGraph(app.raw), savedGraph);
            expect(find.byType(SnackBar, skipOffstage: false), findsNothing);
            expect(tester.takeException(), isNull);

            await app.shutdown(tester);
            final reopened = await _launch(tester, install);
            expect(_storedGraph(reopened.raw), savedGraph);
            await _expectDurableIntention(
              tester,
              reopened,
              created,
              title: _title,
              description: _description,
              readiness: IntentionReadiness.ready,
              favoriteMark: FavoriteMark.favorite,
              tags: ['Дом', 'Работа', _sport],
            );
            expect(_storedIntentionIds(reopened.raw), [...idsBefore, created]);
            expect(reopened.completions, isEmpty);
            expect(find.byType(SnackBar, skipOffstage: false), findsNothing);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    for (final systemBack in [false, true]) {
      testWidgets(
        'намерение, подготовленное через общую кнопку, панель, общий выбор и '
        'настоящий редактор тега с тегом, который исключают условия выдачи, не '
        'вставляется в неподходящую выдачу, сохраняя её условия, количество и '
        'позицию, а скрытая Главная и навигация по тегу отражают полный '
        'результат до возврата ${systemBack ? 'системным «назад»' : 'кнопкой страницы'} на $code',
        (tester) async {
          final install = await _install(tester, locale);
          final l10n = install.l10n;
          final app = await _launch(tester, install, seed: _seedGraph);
          final home = _tagId(_homeTag);
          final work = _tagId(_workTag);
          final marks = storedFavoriteMarks(app.raw);
          await _searchCatalog(tester, app);
          await _scrollCatalog(tester);
          final catalogBefore = _catalog(app);
          final viewBefore = _catalogView(tester);
          final graphBefore = _storedGraph(app.raw);
          final events = app.diagnostics.events.length;

          app.writes.start();
          final sport = await _prepareFullDraft(
            tester,
            app,
            tags: [_homeTag, _workTag],
          );
          expect(_chipNames(tester), ['Дом', 'Работа', _sport]);

          // До отправки граф получил только самостоятельный тег.
          final tagCompletion = app.completions.single as TagCommandCompletion;
          expect(app.writes.take(), [
            (write: 'insert tags', inTransaction: true),
          ]);
          expect(
            _storedCreationTables(app.raw),
            _creationTablesOf(graphBefore),
          );

          // «Сохранить» подтверждает полное создание одним результатом, а
          // Главная согласуется с ним, хотя выдача каталога его не принимает.
          // Быстрый выбор тегов после отправки не меняет стек и её данные.
          final submit = tester.widget<FilledButton>(_submit).onPressed!;
          final chooseTags = tester.widget<IconButton>(_chooseTags).onPressed!;
          submit();
          chooseTags();
          final creation = await _creation(tester, app);
          await _waitFor(tester, () => _sheet.evaluate().isEmpty);
          await _expectCreatedPage(
            tester,
            app,
            creation,
            title: _title,
            description: _description,
            tags: ['Дом', 'Работа', _sport],
            readiness: IntentionReadiness.ready,
            favoriteMark: FavoriteMark.favorite,
          );
          final created = _createdId(creation);
          final revision = creation.revision!;
          expect(app.completions, [same(tagCompletion), same(creation)]);
          expect(app.writes.take(), _fullCreationWrites(tags: 3));
          _expectConfirmedPackage(
            creation,
            tags: ['Дом', 'Работа', _sport],
            readiness: IntentionReadiness.ready,
            favoriteMark: FavoriteMark.favorite,
          );
          _expectStoredIntention(
            app.raw,
            created,
            title: _title,
            description: _description,
            readiness: IntentionReadiness.ready,
          );
          expect(
            _storedAssignments(app.raw, created),
            unorderedEquals([
              home.toCanonicalString(),
              work.toCanonicalString(),
              sport.toCanonicalString(),
            ]),
          );
          expect(storedFavoriteMarks(app.raw), [
            ...marks,
            (created.toCanonicalString(), 4),
          ]);

          await _waitFor(
            tester,
            () => _currentAt(app, revision),
            reason: () => '${_home(app)} ${_catalogState(app)}',
          );
          await _closeCreatedPage(tester, app, systemBack: systemBack);
          expectIntentionGraphRootPage(app.router);
          expect(_selected(tester), AppDestination.intentionGraph);
          expect(
            [for (final row in (_home(app) as HomeList).items) row.id],
            [_intentionId(_walk), _intentionId(_swim), created],
          );
          await _acceptMessage(
            tester,
            l10n.graphOperationMessage(
              l10n.graphOperationCreate,
              _title,
              l10n.editorCreated,
            ),
          );
          expect(_commandEvents(app, since: events), [
            _tagCreateEvent(),
            _createEvent(IntentionCreationCommandDiagnosticsStage.resultRead),
          ]);

          // Исключённый тег из того же создания не пускает намерение в выдачу:
          // её строки, количество, условия и позиция просмотра не изменились.
          final catalog = _catalog(app);
          _expectSameSearch(catalog, catalogBefore);
          expect(catalog.totalCount, catalogBefore.totalCount);
          expect(_ids(catalog), _ids(catalogBefore));
          _expectSameView(_catalogView(tester), viewBefore);
          expect(
            find.descendant(
              of: _catalogList,
              matching: find.widgetWithText(IntentionSummaryView, _title),
            ),
            findsNothing,
          );

          await _openTagNavigation(tester, app, work);
          _expectNavigationAt(tester, work, revision);
          expect(_navigationIds(tester, work), [
            _intentionId(_atWork),
            created,
          ]);
          await _closeTop(tester, TagNavigationPage);
          await _closeTop(tester, TagCatalogPage);
          expectIntentionGraphRootPage(app.router);
          _expectSameView(_catalogView(tester), viewBefore);

          await _select(tester, AppDestination.home);
          expect(_shownHome(tester), ['Гулять', 'Плавать', _title]);
          expect(_message, findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

TagId _tagId(int number) =>
    (TagId.decode(tagFixtureId(number)) as TagIdDecodingSuccess).id;

IntentionId _intentionId(int number) =>
    (IntentionId.decode(tagFixtureId(number)) as IntentionIdDecodingSuccess).id;

Iterable<int> get _sketches =>
    Iterable.generate(_sketchCount, (index) => _firstSketch + index);

bool _isArchivedSketch(int number) => number % 4 == 0;

/// Активные этюды в порядке создания их назначений «Дом».
Iterable<int> get _activeSketches =>
    _sketches.where((number) => !_isArchivedSketch(number));

/// Намерения избранного, этюды и не совпадающие с выдачей намерения; три
/// тега; единый порядок избранного «Гулять», «Плавать», архивированное
/// «Читать».
void _seedGraph(sqlite.Database database) {
  for (final MapEntry(key: number, value: name) in _tagNames.entries) {
    database.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
      tagFixtureId(number),
      name,
    ]);
  }
  void intention(
    int number,
    String title, {
    required bool ready,
    bool archived = false,
    List<int> tags = const [],
  }) {
    database.execute(
      'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
      [
        tagFixtureId(number),
        title,
        ready ? 1 : 0,
        archived ? 1 : 0,
        number,
        number,
      ],
    );
    for (final tag in tags) {
      database.execute(
        'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
        [tagFixtureId(tag), tagFixtureId(number)],
      );
    }
  }

  intention(_walk, 'Гулять', ready: true, tags: [_homeTag]);
  intention(_swim, 'Плавать', ready: false);
  intention(_read, 'Читать', ready: true, archived: true);
  intention(
    _atWork,
    'Рисовать на работе',
    ready: true,
    tags: [_homeTag, _workTag],
  );
  intention(_inGarden, 'Рисовать в саду', ready: false, tags: [_gardenTag]);
  intention(_namesake, _title, ready: false);
  for (final number in _sketches) {
    intention(
      number,
      'Рисовать этюд ${number - _firstSketch + 1}',
      ready: number.isEven,
      archived: _isArchivedSketch(number),
      tags: [_homeTag],
    );
  }
  for (final (index, number) in [_walk, _swim, _read].indexed) {
    storeFavoriteMark(
      database,
      intentionId: tagFixtureId(number),
      position: index + 1,
    );
  }
}

/// Установка приложения: постоянное хранилище, переживающее перезапуски.
final class _Install {
  _Install(this.harness, this.l10n);

  final LocalDatabaseHarness harness;
  final AppLocalizations l10n;
}

Future<_Install> _install(WidgetTester tester, Locale locale) async {
  // Общая поверхность показывает сообщения только работающему приложению.
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  tester.binding.platformDispatcher.localesTestValue = [locale];
  addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final harness = (await tester.runAsync(LocalDatabaseHarness.fileBacked))!;
  addTearDown(harness.dispose);
  return _Install(harness, lookupAppLocalizations(locale));
}

/// Один запуск приложения на хранилище установки.
final class _Launch {
  _Launch({
    required this.runtime,
    required this.raw,
    required this.container,
    required this.diagnostics,
    required this.writes,
    required this.completions,
    required this.l10n,
    required this.router,
  });

  final AppRuntime runtime;
  final sqlite.Database raw;
  final ProviderContainer container;
  final InMemoryDiagnosticsSink diagnostics;
  final _WriteLog writes;

  /// Все завершения координатора этого запуска в порядке публикации.
  final List<GraphCommandCompletion> completions;
  final AppLocalizations l10n;

  final RootStackRouter router;

  /// Полное завершение: дерево приложения снято, хранилище закрыто.
  Future<void> shutdown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(runtime.shutdown);
  }
}

/// Запускает приложение на хранилище [install] через настроенное файловое
/// соединение, засевает его [seed] и ждёт, пока Главная закончит
/// первоначальное получение.
Future<_Launch> _launch(
  WidgetTester tester,
  _Install install, {
  void Function(sqlite.Database database)? seed,
  RootStackRouter? navigationRouter,
  IntentionCreationStorageObserver? storage,
}) async {
  late sqlite.Database raw;
  final diagnostics = InMemoryDiagnosticsSink();
  final writes = _WriteLog();
  final runtime = AppRuntime(
    quickCreationModeStore: InMemoryQuickCreationModeStore(),
    connectionFactory: () {
      final connection = observeConfiguredLocalDatabaseConnection(
        openFileBackedLocalDatabase(
          install.harness.databaseFile,
          setup: (database) => raw = database,
        ),
        writes,
      );
      return storage == null
          ? connection
          : observeConfiguredLocalDatabaseConnection(connection, storage);
    },
    diagnosticsSink: diagnostics,
  );
  addTearDown(() async {
    storage?.release();
    await tester.pumpWidget(const SizedBox.shrink());
    await runtime.shutdown();
  });
  final ready = (await tester.runAsync(runtime.bootstrap)) as AppRuntimeReady;
  writes.connection = raw;
  if (storage != null) storage.connection = raw;
  seed?.call(raw);
  final completions = <GraphCommandCompletion>[];
  final subscription = ready.container
      .read(graphCommandCoordinatorProvider.notifier)
      .completions
      .listen(completions.add);
  addTearDown(subscription.cancel);
  final RootStackRouter router =
      navigationRouter ?? ready.container.read(appRouterProvider);
  if (navigationRouter != null) addTearDown(navigationRouter.dispose);
  await tester.pumpWidget(
    navigationRouter == null
        ? MainApp(runtime: runtime)
        : UncontrolledProviderScope(
            container: ready.container,
            child: MaterialApp.router(
              locale: Locale(install.l10n.localeName),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routerConfig: router.config(),
              builder: (context, child) => GraphOperationPresenter(
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ),
  );
  await _until(tester, find.byType(HomePage));
  await _waitFor(
    tester,
    () => find.text(install.l10n.homeLoading).evaluate().isEmpty,
  );
  await tester.pumpAndSettle();
  return _Launch(
    runtime: runtime,
    raw: raw,
    container: ready.container,
    diagnostics: diagnostics,
    writes: writes,
    completions: completions,
    l10n: install.l10n,
    router: router,
  );
}

/// Открывает граф намерений и задаёт через его интерфейс все условия выдачи:
/// оба охвата, текст, обязательный «Дом», исключённую «Работу» и порядок по
/// изменению. Ждёт выдачу всех этюдов.
Future<void> _searchCatalog(WidgetTester tester, _Launch app) async {
  final l10n = app.l10n;
  await openIntentionGraph(tester, waitFor: _until);
  await _waitFor(tester, () => _catalogState(app) is IntentionCatalogLoaded);
  await _selectOption(tester, 'catalog-scope-control', l10n.catalogScopeAll);
  await tester.enterText(
    find.byKey(const ValueKey('catalog-filter-field')),
    _catalogFilter,
  );
  await _addCondition(tester, _homeTag, present: true);
  await _addCondition(tester, _workTag, present: false);
  await _selectOption(
    tester,
    'catalog-order-control',
    l10n.catalogOrderUpdatedNewest,
  );
  final sketchesByUpdate = [
    for (final number in _sketches.toList().reversed) _intentionId(number),
  ];
  await _waitFor(
    tester,
    () => switch (_catalogState(app)) {
      final IntentionCatalogLoaded catalog =>
        catalog.selection.order == IntentionCatalogOrder.updatedAtDescending &&
            listEquals(_ids(catalog), sketchesByUpdate),
      _ => false,
    },
    reason: () => '${_catalogState(app)}',
  );
  await tester.pumpAndSettle();
  final catalog = _catalog(app);
  expect(catalog.totalCount, _sketchCount);
  expect(catalog.nextCursor, isNull);
  expect(catalog.selection.scope, IntentionScope.all);
  expect(catalog.selection.titleFilterText, _catalogFilter);
  expect(
    catalog.selection.tagFilter,
    IntentionTagFilter(
      requiredTagIds: [_tagId(_homeTag)],
      excludedTagIds: [_tagId(_workTag)],
    ),
  );
  expect(catalog.query.readinessFilter, IntentionReadinessFilter.all);
}

/// Прокручивает выдачу каталога жестом в видимой области списка.
Future<void> _scrollCatalog(WidgetTester tester) async {
  await tester.dragFrom(
    _visibleCatalogArea(tester).center,
    const Offset(0, -300),
  );
  await tester.pumpAndSettle();
  expect(_catalogListPosition(tester).pixels, greaterThan(0));
}

/// Возвращает выдачу каталога к началу жестом в видимой области списка.
Future<void> _scrollCatalogToTop(WidgetTester tester) async {
  await tester.dragFrom(
    _visibleCatalogArea(tester).center,
    const Offset(0, 3000),
  );
  await tester.pumpAndSettle();
  expect(_catalogListPosition(tester).pixels, 0);
}

/// Открывает панель создания через меню и кнопку общей панели.
Future<void> _openSheet(WidgetTester tester, _Launch app) async {
  final history = List.of(app.router.stackData);
  await openQuickCreation(
    tester,
    QuickCreationMode.intention,
    openedPage: _sheet,
    wait: _until,
  );
  expect(_stack(app), [
    ...history.map((route) => route.name),
    IntentionEditorRoute.name,
  ]);
}

/// Готовит в панели, открытой общей кнопкой, все пять полей черновика: сырое
/// название, описание, избранное, явно подтверждённую готовность и набор из
/// существующих тегов [tags] и тега «Спорт», созданного настоящим редактором
/// из общего выбора. Принимает сообщение о созданном теге, возвращается в
/// ту же панель и возвращает идентификатор созданного тега. Быстрый вызов
/// сохранения после открытия выбора не принимает и не откладывает отправку.
Future<TagId> _prepareFullDraft(
  WidgetTester tester,
  _Launch app, {
  required List<int> tags,
}) async {
  final l10n = app.l10n;
  final history = List.of(app.router.stackData);
  await _openSheet(tester, app);
  expect(_text(tester, 'intention-editor-title'), isEmpty);
  expect(_text(tester, 'intention-editor-description'), isEmpty);
  expect(_chipNames(tester), isEmpty);
  expect(_iconOf(tester, _favorite), Icons.star_border);
  expect(_iconOf(tester, _readiness), Icons.check_circle_outline);
  expect(tester.getRect(_sheet).top, greaterThanOrEqualTo(72));
  expect(
    appNavigationDestinations(skipOffstage: false).hitTestable(),
    findsNothing,
  );
  await tester.enterText(
    find.byKey(const ValueKey('intention-editor-title')),
    _rawTitle,
  );
  await tester.enterText(
    find.byKey(const ValueKey('intention-editor-description')),
    _description,
  );
  await _tap(tester, _favorite);
  await _tap(tester, _readiness);
  await _until(tester, _readinessConfirmation);
  await tester.pumpAndSettle();
  await _tap(tester, _readinessConfirm);
  await tester.pumpAndSettle();
  expect(_readinessConfirmation, findsNothing);

  await _tap(tester, _chooseTags);
  await _until(tester, _row(_tagId(_homeTag)));
  await tester.pumpAndSettle();
  expect(find.byType(AppNavigationBar), findsNothing);
  expect(find.byTooltip(l10n.tagNavigationTitle), findsNothing);
  expect(_stack(app), [
    ...history.map((route) => route.name),
    IntentionEditorRoute.name,
    TagCatalogRoute.name,
  ]);
  for (final tag in tags) {
    await _addToDraft(tester, _tagId(tag));
  }
  final tagSet = switch (app.router.current
      .argsAs<TagCatalogRouteArgs>()
      .selectionContext) {
    TagDraftContext(:final tagSet) => tagSet,
    final other => throw StateError('Выбор открыт не для черновика: $other'),
  };
  await _tap(tester, find.byType(BackButton));
  await tester.pumpAndSettle();
  final sheetElement = tester.element(_sheet);
  final formRoute = app.router.stackData.last;
  final graphBefore = _storedCreationTables(app.raw);
  final staleSubmit = tester.widget<FilledButton>(_submit).onPressed!;

  // Два нажатия до следующего кадра идут через настоящую панель и роутер.
  await tester.tap(_chooseTags);
  await tester.tap(_submit);
  await _until(tester, _row(_tagId(_homeTag)));
  await tester.pumpAndSettle();
  expect(_stack(app), [
    ...history.map((route) => route.name),
    IntentionEditorRoute.name,
    TagCatalogRoute.name,
  ]);
  expect(app.router.stackData[history.length], same(formRoute));
  expect(
    app.router.current.argsAs<TagCatalogRouteArgs>().selectionContext,
    isA<TagDraftContext>().having(
      (context) => context.tagSet,
      'набор',
      same(tagSet),
    ),
  );
  expect(tagSet.current.tagIds, [for (final tag in tags) _tagId(tag)]);
  expect(app.completions, isEmpty);
  expect(_storedCreationTables(app.raw), graphBefore);

  await _tap(tester, _createTagAction);
  await _until(tester, _tagEditorName);
  await tester.pumpAndSettle();
  expect(_stack(app).last, TagEditorRoute.name);
  expect(find.byType(AppNavigationBar), findsNothing);
  staleSubmit();
  await tester.enterText(_tagEditorName, _sport);
  await _tap(tester, _tagEditorSubmit);
  await _waitFor(tester, () => _tagEditorName.evaluate().isEmpty);
  await _acceptMessage(
    tester,
    l10n.graphOperationMessage(
      l10n.graphOperationCreate,
      l10n.graphOperationTag,
      l10n.tagCreated,
    ),
  );
  final sport = _storedTagId(app.raw, _sport);
  await _addToDraft(tester, sport);

  await _tap(tester, find.byType(BackButton));
  await _waitFor(tester, () => find.byType(TagCatalogPage).evaluate().isEmpty);
  await tester.pumpAndSettle();
  expect(_stack(app), [
    ...history.map((route) => route.name),
    IntentionEditorRoute.name,
  ]);
  expect(tester.element(_sheet), same(sheetElement));
  expect(app.router.stackData.last, same(formRoute));
  expect(tagSet.current.availability, IntentionDraftAvailability.editable);
  expect(tagSet.current.tagIds, [for (final tag in tags) _tagId(tag), sport]);
  expect(_text(tester, 'intention-editor-title'), _rawTitle);
  expect(_text(tester, 'intention-editor-description'), _description);
  expect(_iconOf(tester, _favorite), Icons.star);
  expect(_iconOf(tester, _readiness), Icons.check_circle);
  expect(app.completions.whereType<IntentionCommandCompletion>(), isEmpty);
  expect(_storedCreationTables(app.raw), graphBefore);
  expect(tester.widget<FilledButton>(_submit).onPressed, isNotNull);
  return sport;
}

/// Выбирает строку тега [id] кандидатом и явно добавляет его в черновик,
/// дождавшись подтверждения кандидата.
Future<void> _addToDraft(WidgetTester tester, TagId id) async {
  await _tap(tester, _row(id));
  await _waitFor(
    tester,
    () => tester.widget<FilledButton>(_addToDraftAction).onPressed != null,
    reason: () => 'Добавление «$id» не стало доступным',
  );
  await _tap(tester, _addToDraftAction);
  await tester.pumpAndSettle();
}

/// Открывает навигацию по тегу [tag] из каталога тегов, открытого кнопкой
/// каталога намерений либо уже открытого ([fromTagCatalog]), и ждёт её
/// актуальную выдачу.
Future<void> _openTagNavigation(
  WidgetTester tester,
  _Launch app,
  TagId tag, {
  bool fromTagCatalog = false,
}) async {
  if (!fromTagCatalog) {
    await _tap(tester, find.byKey(const ValueKey('catalog-open-tags')));
  }
  await _tap(
    tester,
    find.byKey(ValueKey('tag-catalog-open-${tag.toCanonicalString()}')),
  );
  await _until(tester, _navigationPage(tag));
  await _waitFor(
    tester,
    () => switch (_navigation(tester, tag)) {
      final TagNavigationLoaded state => state.canUseCurrentItems,
      _ => false,
    },
    reason: () => '${_navigation(tester, tag)}',
  );
  await tester.pumpAndSettle();
  expect(app.router.current.name, TagNavigationRoute.name);
}

/// Закрывает верхнюю страницу [page] системным действием «назад».
Future<void> _closeTop(WidgetTester tester, Type page) async {
  await tester.binding.handlePopRoute();
  await _waitFor(tester, () => find.byType(page).evaluate().isEmpty);
  await tester.pumpAndSettle();
}

/// Добавляет условие по тегу [tag] через экран поиска тега действием «Есть»
/// или «Нет».
Future<void> _addCondition(
  WidgetTester tester,
  int tag, {
  required bool present,
}) async {
  await _tap(
    tester,
    find.byKey(const ValueKey('intention-tag-conditions-add')),
  );
  final requirement = present ? 'mustBePresent' : 'mustBeAbsent';
  await _tap(
    tester,
    find.byKey(
      ValueKey('tag-condition-picker-$requirement-${tagFixtureId(tag)}'),
    ),
  );
  await _waitFor(
    tester,
    () => find
        .byKey(ValueKey('intention-tag-condition-${tagFixtureId(tag)}'))
        .evaluate()
        .isNotEmpty,
  );
  await tester.pumpAndSettle();
}

/// Выбирает пункт [label] выпадающего списка параметра [key] каталога.
Future<void> _selectOption(
  WidgetTester tester,
  String key,
  String label,
) async {
  await _tap(tester, find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

/// Выбирает пункт панели и ждёт его корневую страницу.
Future<void> _select(WidgetTester tester, AppDestination destination) async {
  final item = find.descendant(
    of: find.byType(AppNavigationBar),
    matching: find.byIcon(
      _selected(tester) == destination
          ? destination.selectedIcon
          : destination.icon,
    ),
  );
  await _until(tester, item);
  await tester.tap(item);
  await tester.pump();
  await _until(
    tester,
    find.byType(switch (destination) {
      AppDestination.home => HomePage,
      AppDestination.intentionGraph => IntentionCatalogPage,
      AppDestination.dailyChoices => fail('Пункт не используется проверкой'),
    }),
  );
  await tester.pumpAndSettle();
  expect(_selected(tester), destination);
}

AppDestination _selected(WidgetTester tester) => tester
    .widget<AppNavigationBar>(
      find.byType(AppNavigationBar, skipOffstage: false).first,
    )
    .selected;

List<String> _stack(_Launch app) => [
  for (final page in app.router.stack) page.routeData.name,
];

/// Дожидается [count]-го завершения создания намерения и возвращает его.
Future<IntentionCommandCompletion> _creation(
  WidgetTester tester,
  _Launch app, {
  int count = 1,
}) async {
  List<IntentionCommandCompletion> creations() =>
      app.completions.whereType<IntentionCommandCompletion>().toList();
  await _waitFor(
    tester,
    () => creations().length >= count,
    reason: () => 'Создание не завершилось: ${app.completions}',
  );
  expect(creations(), hasLength(count));
  return creations().last;
}

IntentionId _createdId(IntentionCommandCompletion completion) =>
    switch (completion.result) {
      ResultSuccess(value: IntentionSaved(:final intention)) => intention.id,
      final result => fail('Создание не подтверждено: $result'),
    };

/// Непосредственный результат успеха: страница подтверждённого идентификатора
/// с настоящими подробными данными и назначениями, без завершённой формы.
Future<void> _expectCreatedPage(
  WidgetTester tester,
  _Launch app,
  IntentionCommandCompletion completion, {
  required String title,
  required String? description,
  required List<String> tags,
  required IntentionReadiness readiness,
  required FavoriteMark favoriteMark,
  IntentionCreationHistory? history,
}) async {
  final id = _createdId(completion);
  expect(app.router.current.name, IntentionDetailsRoute.name);
  expect(
    app.router.current.argsAs<IntentionDetailsRouteArgs>().intentionId,
    id,
  );
  expect(_stack(app), [
    ...?history?.routes.map((route) => route.name),
    if (history == null) AppShellRoute.name,
    IntentionDetailsRoute.name,
  ]);
  final page = find.byType(IntentionDetailsPage);
  await _until(tester, page);
  final container = ProviderScope.containerOf(
    tester.element(page),
    listen: false,
  );
  await _waitFor(
    tester,
    () =>
        container.read(intentionDetailsViewModelProvider(id))
            is IntentionDetailsLoaded &&
        container.read(tagAssignmentsViewModelProvider(id))
            is TagAssignmentsLoaded,
  );
  await tester.pumpAndSettle();
  expect(tester.widget<IntentionDetailsPage>(page).intentionId, id);
  final state = container.read(
    intentionDetailsViewModelProvider(id),
  ) as IntentionDetailsLoaded;
  expect(state.intention.id, id);
  expect(state.intention.title, title);
  expect(state.intention.description, description);
  expect(state.intention.readiness, readiness);
  expect(state.intention.archiveState, IntentionArchiveState.active);
  expect(state.details.favoriteMark, favoriteMark);
  expect(
    state.revision.compareTo(completion.revision!),
    GraphRevisionOrder.same,
  );
  final assignments = container.read(
    tagAssignmentsViewModelProvider(id),
  ) as TagAssignmentsLoaded;
  expect(assignments.intentionId, id);
  expect([for (final tag in assignments.items) tag.name.value], tags);
  expect(assignments.freshness, TagAssignmentsFreshness.current);
  expect(
    assignments.revision.compareTo(completion.revision!),
    GraphRevisionOrder.same,
  );
  expect(
    tester
        .widget<Text>(find.byKey(const ValueKey('intention-details-title')))
        .data,
    title,
  );
  expect(
    find.descendant(
      of: page,
      matching: find.text(description ?? app.l10n.detailsNoDescription),
    ),
    findsOneWidget,
  );
  expect(
    find.descendant(
      of: page,
      matching: find.text(
        readiness == IntentionReadiness.ready
            ? app.l10n.catalogReady
            : app.l10n.catalogNotReady,
      ),
    ),
    findsOneWidget,
  );
  expect(
    _iconOf(
      tester,
      find.byKey(const ValueKey('intention-details-favorite-mark')),
    ),
    favoriteMark == FavoriteMark.favorite ? Icons.star : Icons.star_border,
  );
  for (final tag in assignments.items) {
    final row = find.byKey(
      ValueKey('tag-assignment-row-${tag.id.toCanonicalString()}'),
    );
    await tester.scrollUntilVisible(
      row,
      200,
      scrollable: find.descendant(of: page, matching: find.byType(Scrollable)),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: row, matching: find.text(tag.name.value)),
      findsOneWidget,
    );
  }
  expect(
    tester.getRect(page),
    Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio),
  );
  expect(find.byType(AppNavigationBar), findsOneWidget);
  expect(
    appNavigationDestinations(skipOffstage: false).hitTestable(),
    findsExactly(3),
  );
  expect(
    _selected(tester),
    history?.origin.destination ?? AppDestination.intentionGraph,
  );
  expect(
    find.byKey(const ValueKey('intention-creation-sheet'), skipOffstage: false),
    findsNothing,
  );
  expect(find.byType(AlertDialog, skipOffstage: false), findsNothing);
}

/// Возвращение действием человека удаляет единственную страницу результата,
/// не показывая завершённую форму или подтверждение ухода.
Future<void> _closeCreatedPage(
  WidgetTester tester,
  _Launch app, {
  bool systemBack = false,
}) async {
  expect(app.router.current.name, IntentionDetailsRoute.name);
  if (systemBack) {
    await tester.binding.handlePopRoute();
  } else {
    await _tap(
      tester,
      find.descendant(
        of: find.byType(IntentionDetailsPage),
        matching: find.byType(BackButton),
      ),
    );
  }
  await _until(tester, find.byType(AppNavigationBar));
  await tester.pumpAndSettle();
  expect(_stack(app), [AppShellRoute.name]);
  expectIntentionGraphRootPage(app.router);
  expect(find.byType(IntentionCatalogPage), findsOneWidget);
  expect(find.byType(IntentionDetailsPage, skipOffstage: false), findsNothing);
  expect(
    find.byKey(const ValueKey('intention-creation-sheet'), skipOffstage: false),
    findsNothing,
  );
  expect(find.byType(AlertDialog, skipOffstage: false), findsNothing);
  expect(_selected(tester), AppDestination.intentionGraph);
}

/// Один подтверждённый пакет создания: полный снимок нового намерения с
/// тегами [tags], готовностью и избранным и одно назначение на каждый тег,
/// все на одной ревизии.
void _expectConfirmedPackage(
  IntentionCommandCompletion completion, {
  required List<String> tags,
  required IntentionReadiness readiness,
  required FavoriteMark favoriteMark,
}) {
  final package = completion.confirmedChange!;
  expect(package.changes, [
    isA<IntentionCatalogCreated>(),
    for (final _ in tags) isA<TagAssignmentChangedChange>(),
  ]);
  expect(
    package.changes.map((change) => change.revision),
    everyElement(same(package.revision)),
  );
  final IntentionSummary summary =
      (package.changes.first as IntentionCatalogCreated).entry.summary;
  expect([for (final tag in summary.tags) tag.name.value], tags);
  expect(summary.readiness, readiness);
  expect(summary.favoriteMark, favoriteMark);
  expect(summary.archiveState, IntentionArchiveState.active);
  expect(summary.createdAt.value, summary.updatedAt.value);
}

/// Записи полного создания с [tags] тегами: намерение, назначения и место
/// избранного — все внутри транзакции.
List<_Write> _fullCreationWrites({required int tags}) => [
  (write: 'insert intentions', inTransaction: true),
  for (var tag = 0; tag < tags; tag++)
    (write: 'insert tag_assignments', inTransaction: true),
  (write: 'insert favorite_intentions', inTransaction: true),
];

/// Записи минимального создания: только строка намерения.
const List<_Write> _minimalCreationWrites = [
  (write: 'insert intentions', inTransaction: true),
];

/// Строка созданного намерения [id]: нормализованное название, сохранённое
/// описание либо его отсутствие, готовность, активное состояние и равные
/// время создания и последнего изменения.
void _expectStoredIntention(
  sqlite.Database raw,
  IntentionId id, {
  required String title,
  required String? description,
  required IntentionReadiness readiness,
}) {
  final row = raw.select(
    'SELECT title, description, is_action_ready, is_archived, created_at, '
    'updated_at FROM intentions WHERE id = ?',
    [id.toCanonicalString()],
  ).single;
  expect(row['title'], title);
  expect(row['description'], description);
  expect(row['is_action_ready'], switch (readiness) {
    IntentionReadiness.ready => 1,
    IntentionReadiness.notReady => 0,
  });
  expect(row['is_archived'], 0);
  expect(row['created_at'], row['updated_at']);
}

/// Полный результат после повторного открытия хранилища, прочитанный
/// публичными чтениями модуля графа: подробности намерения с отметкой
/// избранного и назначения в порядке создания тегов.
Future<void> _expectDurableIntention(
  WidgetTester tester,
  _Launch app,
  IntentionId id, {
  required String title,
  required String? description,
  required IntentionReadiness readiness,
  required FavoriteMark favoriteMark,
  required List<String> tags,
}) async {
  final repository = app.container.read(personalGraphRepositoryProvider);
  final details = switch (await _readStorage(
    tester,
    () => repository.watchIntention(id).first,
  )) {
    ResultSuccess(:final value) => value.value!,
    final result => fail('Чтение намерения не удалось: $result'),
  };
  final intention = details.intention;
  expect(intention.title, title);
  expect(intention.description, description);
  expect(intention.readiness, readiness);
  expect(intention.archiveState, IntentionArchiveState.active);
  expect(intention.createdAt.value, intention.updatedAt.value);
  expect(details.favoriteMark, favoriteMark);
  final assignments = switch (await _readStorage(
    tester,
    () => repository.getTagAssignments(id),
  )) {
    GraphResultSuccess(:final value) => value.items,
    final result => fail('Чтение назначений не удалось: $result'),
  };
  expect([for (final tag in assignments) tag.name.value], tags);
}

/// Результат публичного чтения [read] настоящего хранилища.
///
/// Чтение может ждать очереди репозитория, которую приложение продвигает
/// кадрами, а операции хранилища идут в реальном времени: внутри одного
/// `runAsync` такое чтение после перезапуска не завершается. Поэтому оно
/// продвигается так же, как ожидание завершений команд: реальным временем и
/// кадрами.
Future<T> _readStorage<T>(
  WidgetTester tester,
  Future<T> Function() read,
) async {
  late final T value;
  var isRead = false;
  unawaited(
    read().then((result) {
      value = result;
      isRead = true;
    }),
  );
  await _waitFor(tester, () => isRead);
  return value;
}

/// Активные избранные намерения единого порядка по публичному чтению.
Future<List<IntentionId>> _favoriteIds(WidgetTester tester, _Launch app) async {
  final repository = app.container.read(personalGraphRepositoryProvider);
  return switch (await _readStorage(tester, repository.getFavoriteIntentions)) {
    GraphResultSuccess(:final value) => [for (final row in value.items) row.id],
    final result => fail('Чтение избранного не удалось: $result'),
  };
}

/// Первая порция выдачи по условиям [query] из публичного чтения каталога.
Future<IntentionCatalogFirstPage> _catalogPage(
  WidgetTester tester,
  _Launch app,
  IntentionCatalogQuery query,
) async {
  final repository = app.container.read(personalGraphRepositoryProvider);
  return switch (await _readStorage(
    tester,
    () => repository.getCatalogPage(
      IntentionCatalogQuery(
        scope: query.scope,
        readinessFilter: query.readinessFilter,
        titleFilter: _catalogFilter,
        tagFilter: query.tagFilter,
        order: query.order,
        pageSize: IntentionCatalogQuery.maxPageSize,
      ),
    ),
  )) {
    ResultSuccess(value: final IntentionCatalogFirstPage page) => page,
    final result => fail('Чтение каталога не удалось: $result'),
  };
}

/// Ревизия графа по свежему публичному чтению модуля графа.
Future<GraphRevision> _freshRevision(WidgetTester tester, _Launch app) async {
  final repository = app.container.read(personalGraphRepositoryProvider);
  final result = await _readStorage(
    tester,
    () => repository.getRelationCounts(_intentionId(_walk)),
  );
  return switch (result) {
    ResultSuccess(:final value) => value.revision,
    final result => fail('Чтение графа не удалось: $result'),
  };
}

HomeState _home(_Launch app) => app.container.read(homeViewModelProvider);

IntentionCatalogState? _catalogState(_Launch app) => app.container
    .read(intentionCatalogViewModelProvider(const BrowseIntentionCatalog()))
    .value;

IntentionCatalogLoaded _catalog(_Launch app) =>
    _catalogState(app) as IntentionCatalogLoaded;

List<IntentionId> _ids(IntentionCatalogLoaded catalog) => [
  for (final item in catalog.items) item.id,
];

/// Главная и каталог показывают актуальные данные ревизии [revision].
bool _currentAt(_Launch app, GraphRevision revision) =>
    switch (_home(app)) {
      final HomeList home =>
        home.revision.compareTo(revision) == GraphRevisionOrder.same &&
            home.freshness is HomeFreshnessCurrent,
      _ => false,
    } &&
    _catalogCurrentAt(app, revision);

/// Каталог показывает актуальные данные ревизии [revision].
bool _catalogCurrentAt(_Launch app, GraphRevision revision) =>
    switch (_catalogState(app)) {
      final IntentionCatalogLoaded catalog =>
        catalog.revision.compareTo(revision) == GraphRevisionOrder.same &&
            catalog.refresh is IntentionCatalogRefreshIdle,
      _ => false,
    };

/// Каталог продолжает ту же выдачу: те же параметры и условия, включая
/// готовность, охват и порядок, без нового чтения первой порции.
void _expectSameSearch(
  IntentionCatalogLoaded actual,
  IntentionCatalogLoaded expected,
) {
  expect(actual.selection, same(expected.selection));
  expect(actual.query, same(expected.query));
  expect(actual.nextCursor, isNull);
  expect(actual.continuation, isA<IntentionCatalogContinuationIdle>());
}

/// Состояние навигации по тегу [tag]: каждая её страница владеет
/// собственным экземпляром модели.
TagNavigationState _navigation(WidgetTester tester, TagId tag) =>
    ProviderScope.containerOf(
      tester.element(_navigationPage(tag)),
      listen: false,
    ).read(tagNavigationViewModelProvider(tag));

Finder _navigationPage(TagId tag) => find.byWidgetPredicate(
  (widget) => widget is TagNavigationPage && widget.tagId == tag,
);

/// Навигация по тегу [tag] показывает данные ревизии [revision].
void _expectNavigationAt(
  WidgetTester tester,
  TagId tag,
  GraphRevision revision,
) => expect(
  (_navigation(tester, tag) as TagNavigationLoaded).revision.compareTo(
    revision,
  ),
  GraphRevisionOrder.same,
);

List<IntentionId> _navigationIds(WidgetTester tester, TagId tag) => [
  for (final item in (_navigation(tester, tag) as TagNavigationLoaded).items)
    item.id,
];

/// Видимая строка выдачи каталога: название и положение на экране.
typedef _CatalogRow = ({String title, Rect rect});

/// Позиция просмотра каталога: прокрутка страницы параметров, прокрутка
/// списка выдачи и видимые строки на своих местах экрана.
typedef _CatalogView = ({double page, double list, List<_CatalogRow> rows});

_CatalogView _catalogView(WidgetTester tester) => (
  page: _catalogPagePosition(tester).pixels,
  list: _catalogListPosition(tester).pixels,
  rows: _visibleCatalogRows(tester),
);

/// Совпадение позиций просмотра каталога.
void _expectSameView(_CatalogView actual, _CatalogView expected) {
  expect(actual.page, expected.page);
  expect(actual.list, expected.list);
  expect(actual.rows, expected.rows);
}

/// Видимая область списка выдачи на странице каталога.
Rect _visibleCatalogArea(WidgetTester tester) => tester
    .getRect(_catalogList)
    .intersect(tester.getRect(find.byType(IntentionCatalogPage)));

/// Строки выдачи, видимые в области списка на странице каталога, сверху
/// вниз.
List<_CatalogRow> _visibleCatalogRows(WidgetTester tester) {
  final area = _visibleCatalogArea(tester);
  return [
    for (final element
        in find
            .descendant(
              of: _catalogList,
              matching: find.byType(IntentionSummaryView),
            )
            .evaluate())
      if (_rectOf(element) case final rect when rect.overlaps(area))
        (title: (element.widget as IntentionSummaryView).title, rect: rect),
  ];
}

Rect _rectOf(Element element) {
  final box = element.renderObject! as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}

ScrollPosition _catalogListPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(of: _catalogList, matching: find.byType(Scrollable))
          .first,
    )
    .position;

/// Прокрутка страницы, в которой параметры поиска и выдача прокручиваются
/// вместе.
ScrollPosition _catalogPagePosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.ancestor(of: _catalogList, matching: find.byType(Scrollable)).first,
    )
    .position;

final _homeRows = find.descendant(
  of: find.byType(HomePage, skipOffstage: false),
  matching: find.byType(HomeIntentionRow, skipOffstage: false),
  skipOffstage: false,
);

/// Названия строк Главной в порядке списка.
List<String> _shownHome(WidgetTester tester) => [
  for (final row in tester.widgetList<HomeIntentionRow>(_homeRows))
    row.row.title,
];

Finder _row(TagId id) =>
    find.byKey(ValueKey('tag-catalog-row-${id.toCanonicalString()}'));

String _text(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;

IconData? _iconOf(WidgetTester tester, Finder button) => tester
    .widget<Icon>(find.descendant(of: button, matching: find.byType(Icon)))
    .icon;

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

Map<String, List<List<Object?>>> _storedGraph(sqlite.Database raw) => {
  for (final table in [..._creationTables, 'tags'])
    table: raw
        .select('SELECT * FROM $table ORDER BY rowid')
        .map((row) => row.values.toList())
        .toList(),
};

Map<String, List<List<Object?>>> _creationTablesOf(
  Map<String, List<List<Object?>>> graph,
) => {for (final table in _creationTables) table: graph[table]!};

Map<String, List<List<Object?>>> _storedCreationTables(sqlite.Database raw) =>
    _creationTablesOf(_storedGraph(raw));

List<IntentionId> _storedIntentionIds(sqlite.Database raw) => [
  for (final row in raw.select('SELECT id FROM intentions ORDER BY rowid'))
    (IntentionId.decode(row['id'] as String) as IntentionIdDecodingSuccess).id,
];

List<String> _storedTagNames(sqlite.Database raw) => [
  for (final row in raw.select('SELECT name FROM tags ORDER BY rowid'))
    row['name'] as String,
];

TagId _storedTagId(sqlite.Database raw, String name) => (TagId.decode(
  raw.select('SELECT id FROM tags WHERE name = ?', [name]).single['id']
      as String,
) as TagIdDecodingSuccess).id;

/// Теги, назначенные намерению [id], в порядке записи назначений.
List<String> _storedAssignments(sqlite.Database raw, IntentionId id) => [
  for (final row in raw.select(
    'SELECT tag_id FROM tag_assignments WHERE intention_id = ? ORDER BY rowid',
    [id.toCanonicalString()],
  ))
    row['tag_id'] as String,
];

/// Исходы самостоятельных команд намерений, тегов и порядка избранного
/// после первых [since] событий; начала команд не учитываются.
List<DiagnosticsEvent> _commandEvents(_Launch app, {required int since}) => [
  for (final event in app.diagnostics.events.skip(since))
    if ((event is IntentionCommandDiagnosticsEvent ||
            event is TagCommandDiagnosticsEvent ||
            event is FavoriteOrderCommandDiagnosticsEvent) &&
        event.status is! DiagnosticsStarted)
      event,
];

Matcher _tagCreateEvent() => isA<TagCommandDiagnosticsEvent>()
    .having(
      (event) => event.commandType,
      'команда',
      TagCommandDiagnosticsType.create,
    )
    .having((event) => event.status, 'исход', isA<DiagnosticsSucceeded>());

Matcher _createEvent(IntentionCreationCommandDiagnosticsStage stage) =>
    isA<IntentionCommandDiagnosticsEvent>()
        .having(
          (event) => event.commandType,
          'команда',
          IntentionCommandDiagnosticsType.create,
        )
        .having((event) => event.stage, 'этап', stage)
        .having((event) => event.status, 'исход', isA<DiagnosticsSucceeded>());

/// Дожидается ровно одного сообщения [text] общей поверхности и закрывает
/// его; предъявленный результат не показывается повторно.
Future<void> _acceptMessage(WidgetTester tester, String text) async {
  await _until(tester, _message);
  await tester.pumpAndSettle();
  expect(find.byType(SnackBar), findsOneWidget);
  expect(find.text(text), findsOneWidget);
  ScaffoldMessenger.of(tester.element(_message)).hideCurrentSnackBar();
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
  expect(_message, findsNothing);
}

/// Нажимает элемент [finder], прокручивая к нему, только если он не
/// принимает нажатие: прокрутка к видимому элементу сдвинула бы позицию
/// просмотра каталога.
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

Future<void> _until(WidgetTester tester, Finder finder) =>
    _waitFor(tester, () => finder.evaluate().isNotEmpty);

/// Продвигает кадры и реальное время хранилища, пока не выполнится [done].
Future<void> _waitFor(
  WidgetTester tester,
  bool Function() done, {
  String Function()? reason,
}) async {
  for (var attempt = 0; attempt < 100 && !done(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue, reason: reason?.call());
}

/// Настоящий стек приложения с отказом только открытия созданного намерения.
final class _FailingCreatedRouteRouter extends RootStackRouter {
  _FailingCreatedRouteRouter({
    required this.synchronous,
    this.point = _CreatedNavigationFailure.beforeRemoval,
  });

  final bool synchronous;
  final _CreatedNavigationFailure point;
  final failure = StateError('Управляемый отказ открытия созданного намерения');
  final _failureGate = Completer<void>();
  var replacementAttempts = 0;

  @override
  List<AutoRoute> get routes => AppRouter().routes;

  void releaseFailure() => _failureGate.complete();

  @override
  Future<T?> replace<T extends Object?>(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
  }) {
    if (route.routeName != IntentionDetailsRoute.name) {
      return super.replace<T>(route, onFailure: onFailure);
    }
    replacementAttempts++;
    switch (point) {
      case _CreatedNavigationFailure.beforeRemoval:
        break;
      case _CreatedNavigationFailure.afterRemoval:
        removeRoute(stackData.last, notify: false);
      case _CreatedNavigationFailure.afterResult ||
          _CreatedNavigationFailure.afterNewSession:
        unawaited(super.replace<T>(route, onFailure: onFailure));
    }
    if (synchronous) throw failure;
    return _failureGate.future.then<T?>((_) => throw failure);
  }
}

enum _CreatedNavigationFailure {
  beforeRemoval('до удаления панели'),
  afterRemoval('после удаления панели'),
  afterResult('после открытия результата'),
  afterNewSession('после нового открытия');

  const _CreatedNavigationFailure(this.description);
  final String description;
}

enum _CloseMethod {
  button('кнопка закрытия'),
  barrier('нажатие на фон'),
  handle('свайп ручки'),
  back('системное «назад»');

  const _CloseMethod(this.description);
  final String description;

  Future<void> request(WidgetTester tester) async {
    switch (this) {
      case button:
        await tester.tap(find.byKey(const ValueKey('intention-editor-close')));
      case barrier:
        await tester.tapAt(Offset(20, tester.getRect(_sheet).top / 2));
      case handle:
        await tester.drag(
          find.byKey(const ValueKey('intention-creation-sheet-handle')),
          const Offset(0, 240),
        );
      case back:
        await tester.binding.handlePopRoute();
    }
  }
}

/// Изменяющая данные запись на соединении приложения: вид операции, как его
/// помечает перехватчик соединения, изменяемые таблицы и выполнялась ли она
/// внутри транзакции.
typedef _Write = ({String write, bool inTransaction});

/// Учитывает после [start] каждую операцию соединения приложения, которая
/// изменяет данные, в любом виде: вставку, обновление, удаление, пакет,
/// произвольный оператор и запись с возвратом строк, которую drift выполняет
/// через путь чтения. Изменяет ли оператор данные, определяет сам SQLite.
///
/// Не учитывается только маркер физического соединения, который чтения
/// тегов создают временной таблицей: он живёт в соединении, не входит в
/// граф и не меняет его.
final class _WriteLog extends LocalDatabaseConnectionObserver {
  /// Таблица, которую изменяет оператор SQL.
  static final _writtenTable = RegExp(
    r'^\s*(?:INSERT(?:\s+OR\s+\w+)?\s+INTO|REPLACE\s+INTO|'
    r'UPDATE(?:\s+OR\s+\w+)?|DELETE\s+FROM)\s+"?(\w+)"?',
    caseSensitive: false,
  );

  /// Создание маркера соединения чтений тегов.
  static final _connectionMarker = RegExp(
    r'^\s*CREATE\s+TEMP\s+TABLE\s+IF\s+NOT\s+EXISTS\s+'
    r'doable_catalog_connection\b',
    caseSensitive: false,
  );

  /// Соединение запущенного приложения.
  late sqlite.Database connection;

  /// Записи после [start]; `null`, пока учёт не начат.
  List<_Write>? _writes;

  void start() => _writes = [];

  /// Возвращает записи после [start] либо прошлого вызова и продолжает
  /// учёт.
  List<_Write> take() {
    final writes = _writes ?? (throw StateError('Учёт записей не начат.'));
    _writes = [];
    return List.unmodifiable(writes);
  }

  @override
  void afterStatement(LocalDatabaseSqlStatement statement) {
    final writes = _writes;
    if (writes == null) return;
    final tables = [
      for (final sql in statement.statements)
        for (final written in _dataChangingStatements(sql))
          _writtenTable.firstMatch(written)?.group(1) ?? written,
    ];
    if (tables.isEmpty) return;
    writes.add((
      write: '${statement.operation.name} ${tables.join(', ')}',
      inTransaction: !connection.autocommit,
    ));
  }

  /// Операторы текста [sql], которые по оценке SQLite
  /// (`sqlite3_stmt_readonly`) изменяют данные.
  List<String> _dataChangingStatements(String sql) {
    final prepared = connection.prepareMultiple(sql);
    try {
      return [
        for (final statement in prepared)
          if (!statement.isReadOnly &&
              !_connectionMarker.hasMatch(statement.sql))
            statement.sql,
      ];
    } finally {
      for (final statement in prepared) {
        statement.close();
      }
    }
  }
}
