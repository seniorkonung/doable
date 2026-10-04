import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/data/local/app_database.dart'
    show
        LocalDatabaseConnectionObserver,
        LocalDatabaseSqlOperation,
        LocalDatabaseSqlStatement,
        observeConfiguredLocalDatabaseConnection,
        openFileBackedLocalDatabase;
import 'package:doable/src/favorite/presentation/home/home_page.dart';
import 'package:doable/src/favorite/presentation/home/home_state.dart';
import 'package:doable/src/favorite/presentation/home/home_view_model.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_catalog.dart'
    show IntentionCatalogCreated, IntentionCommandSuccess, IntentionSaved;
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_state.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/intention_summary_view.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/presentation/assignments/tag_assignments_state.dart';
import 'package:doable/src/tag/presentation/assignments/tag_assignments_view_model.dart';
import 'package:doable/src/tag/presentation/navigation/tag_navigation_page.dart';
import 'package:doable/src/tag/presentation/navigation/tag_navigation_state.dart';
import 'package:doable/src/tag/presentation/navigation/tag_navigation_view_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/favorite_storage_fixture.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/local_database_harness.dart';
import '../support/tag_storage_fixture.dart';

// Названия намерений и тегов — данные человека: они одинаковы в обеих
// локалях.

/// «Гулять», готово к действию, избранное на месте 1, с тегом «Дом».
const _walk = 1;

/// «Читать», архивированное избранное на месте 2.
const _read = 2;

/// «Плавать», не готово к действию, избранное на месте 3, с тегом «Работа».
const _swim = 3;

const _homeTag = 301;
const _gardenTag = 302;
const _workTag = 303;

/// Тег, которого нет в хранилище.
const _missingTag = 304;

const _tagNames = {_homeTag: 'Дом', _gardenTag: 'Сад', _workTag: 'Работа'};

/// Название создаваемого намерения.
const _created = 'Рисовать';

/// Описание создаваемого намерения в сценариях отказа.
const _createdDescription = 'Акварелью, по выходным';

const _message = ValueKey('graph-operation-message');

/// Отказ полного создания на настоящем хранилище.
enum _CreationFailure {
  /// Один из выбранных тегов отсутствует при проверке в транзакции.
  missingTag('отсутствующий выбранный тег'),

  /// Хранилище недоступно внутри ещё не подтверждённой транзакции создания,
  /// когда в ней уже записано всё заданное командой начальное состояние
  /// намерения: название и описание, готовность к действию, активное
  /// состояние, назначение каждого выбранного тега и место избранного.
  storageAfterInitialState(
    'недоступность хранилища после записи всего начального состояния',
  );

  const _CreationFailure(this.description);

  final String description;
}

/// Итоговая контрольная точка полного создания намерения: настоящее
/// приложение и файловое хранилище, координатор команд, общая поверхность
/// сообщений и все потребители результата загружены одновременно.
void main() {
  for (final locale in const [Locale('ru'), Locale('en')]) {
    final code = locale.languageCode;

    testWidgets(
      'полное создание одним пакетом согласует одновременно загруженные '
      'каталог, скрытую Главную, навигацию по тегам и назначения, '
      'предъявляется один раз и сохраняется после перезапуска на $code',
      (tester) async {
        final install = await _install(tester, locale);
        final l10n = install.l10n;
        final app = await _launch(tester, install, seed: _seedGraph);
        final marks = storedFavoriteMarks(app.raw);
        await _openConsumers(tester, app);
        final catalogBefore = _catalog(app);
        final events = app.diagnostics.events.length;
        final completions = <GraphCommandCompletion>[];
        final subscription = app.coordinator.completions.listen(
          completions.add,
        );
        addTearDown(subscription.cancel);

        // Всё начальное состояние принимается координатором одной командой,
        // как её отправит форма создания.
        final accepted = app.coordinator.acceptCreation(
          IntentionCreationFormKey(),
          CreateIntention.withInitialState(
            title: _created,
            description: null,
            readiness: IntentionReadiness.ready,
            favoriteMark: FavoriteMark.favorite,
            tagIds: [_tagId(_homeTag), _tagId(_gardenTag)],
          ),
        ) as IntentionCommandAccepted;
        final completion = await _completionOf(tester, accepted);
        final created = switch (completion.result) {
          ResultSuccess(value: IntentionSaved(:final intention)) =>
            intention.id,
          final result => fail('Создание не подтверждено: $result'),
        };
        final revision = completion.revision!;

        // Один окончательный пакет: полный снимок и оба назначения на одной
        // ревизии.
        expect(completions, [same(completion)]);
        expect(completion.confirmedChange!.changes, [
          isA<IntentionCatalogCreated>(),
          isA<TagAssignmentChangedChange>(),
          isA<TagAssignmentChangedChange>(),
        ]);
        expect(
          completion.confirmedChange!.changes.map((change) => change.revision),
          everyElement(same(revision)),
        );

        // Все потребители согласуются с одной ревизией, пока другие
        // страницы закрывают Главную и каталог.
        await _waitFor(
          tester,
          () => _allCurrentAt(tester, app, revision),
          reason: () => _consumerStates(tester, app).toString(),
        );
        expect(_selected(tester), AppDestination.intentionGraph);

        final home = _home(app) as HomeList;
        expect(
          [for (final row in home.items) row.id],
          [_intentionId(_walk), _intentionId(_swim), created],
        );
        expect(home.items.last.title, _created);
        expect(home.items.last.readiness, IntentionReadiness.ready);
        expect(storedFavoriteMarks(app.raw), [
          ...marks,
          (created.toCanonicalString(), 4),
        ]);

        final catalog = _catalog(app);
        final createdSummaries = [
          for (final item in catalog.items)
            if (item.id == created) item,
        ];
        expect(createdSummaries, hasLength(1));
        final summary = createdSummaries.single;
        expect(summary.title, _created);
        expect(summary.readiness, IntentionReadiness.ready);
        expect(summary.favoriteMark, FavoriteMark.favorite);
        expect(
          [for (final tag in summary.tags) tag.name.value],
          ['Дом', 'Сад'],
        );
        expect(catalog.totalCount, catalogBefore.totalCount + 1);
        expect(
          [
            for (final item in catalog.items)
              if (item.id != created) item.id,
          ],
          [for (final item in catalogBefore.items) item.id],
        );

        expect(_navigationIds(tester, _homeTag), [
          _intentionId(_walk),
          created,
        ]);
        expect(_navigationIds(tester, _gardenTag), [created]);
        expect(_navigationIds(tester, _workTag), [_intentionId(_swim)]);

        // Создание — одна команда с одним исходом: самостоятельные отметка,
        // готовность и назначения тегов не выполнялись.
        expect(_commandEvents(app, since: events), [
          _createEvent(
            IntentionCreationCommandDiagnosticsStage.resultRead,
            isA<DiagnosticsSucceeded>(),
          ),
        ]);
        await _acceptMessage(
          tester,
          l10n.graphOperationMessage(
            l10n.graphOperationCreate,
            _created,
            l10n.editorCreated,
          ),
        );
        expect(completions, hasLength(1));

        // Видимые страницы показывают тот же результат без повторов.
        expect(_visibleTitles(tester, TagNavigationPage), ['Плавать']);
        await _pop(tester, app);
        expect(_visibleTitles(tester, TagNavigationPage), [_created]);
        await _pop(tester, app);
        expect(_visibleTitles(tester, TagNavigationPage), ['Гулять', _created]);
        await _pop(tester, app);
        expect(
          find.descendant(
            of: find.byType(IntentionCatalogPage),
            matching: find.widgetWithText(IntentionSummaryView, _created),
          ),
          findsOneWidget,
        );
        await _select(tester, AppDestination.home);
        expect(_shownHome(tester), ['Гулять', 'Плавать', _created]);

        // Назначения созданного намерения — весь сохранённый набор.
        await _openDetails(tester, app, created);
        expect(_assignedNames(app, created), ['Дом', 'Сад']);
        for (final tag in [_homeTag, _gardenTag]) {
          expect(
            find.byKey(
              ValueKey('tag-assignment-row-${tagFixtureId(tag)}'),
              skipOffstage: false,
            ),
            findsOneWidget,
          );
        }
        expect(find.byKey(_message), findsNothing);
        expect(tester.takeException(), isNull);

        // Полный перезапуск восстанавливает весь подтверждённый набор.
        await app.shutdown(tester);
        final restarted = await _launch(tester, install);
        await _waitFor(
          tester,
          () => listEquals(_shownHome(tester), ['Гулять', 'Плавать', _created]),
          reason: () => 'Главная: ${_shownHome(tester)}',
        );
        expect(storedFavoriteMarks(restarted.raw), [
          ...marks,
          (created.toCanonicalString(), 4),
        ]);
        await _openConsumers(tester, restarted);
        final restored = [
          for (final item in _catalog(restarted).items)
            if (item.id == created) item,
        ].single;
        expect(restored.title, _created);
        expect(restored.readiness, IntentionReadiness.ready);
        expect(restored.favoriteMark, FavoriteMark.favorite);
        expect(
          [for (final tag in restored.tags) tag.name.value],
          ['Дом', 'Сад'],
        );
        expect(_catalog(restarted).totalCount, catalogBefore.totalCount + 1);
        expect(_navigationIds(tester, _homeTag), [
          _intentionId(_walk),
          created,
        ]);
        expect(_navigationIds(tester, _gardenTag), [created]);
        await _openDetails(tester, restarted, created);
        expect(_assignedNames(restarted, created), ['Дом', 'Сад']);
        expect(tester.takeException(), isNull);
      },
    );

    for (final failure in _CreationFailure.values) {
      testWidgets(
        '${failure.description} отклоняет всё полное создание без изменения '
        'подтверждённых данных одновременно загруженных каталога, скрытой '
        'Главной, навигации по тегам и назначений, а общая поверхность '
        'предъявляет отказ один раз после ухода формы на $code',
        (tester) async {
          final install = await _install(tester, locale);
          final l10n = install.l10n;
          final app = await _launch(tester, install, seed: _seedGraph);
          await _openConsumers(tester, app);
          await _openDetails(tester, app, _intentionId(_walk));
          final stored = _storedGraph(app.raw);
          final shown = _consumerStates(
            tester,
            app,
            details: _intentionId(_walk),
          );
          final shownRevisions = _revisions(shown);
          final events = app.diagnostics.events.length;
          final completions = <GraphCommandCompletion>[];
          final subscription = app.coordinator.completions.listen(
            completions.add,
          );
          addTearDown(subscription.cancel);

          if (failure == _CreationFailure.storageAfterInitialState) {
            install.faults.failAfterFavoritePlaceWrite();
          }
          final accepted = app.coordinator.acceptCreation(
            IntentionCreationFormKey(),
            CreateIntention.withInitialState(
              title: _created,
              description: _createdDescription,
              readiness: IntentionReadiness.ready,
              favoriteMark: FavoriteMark.favorite,
              tagIds: switch (failure) {
                _CreationFailure.missingTag => [
                  _tagId(_homeTag),
                  _tagId(_missingTag),
                ],
                _CreationFailure.storageAfterInitialState => [
                  _tagId(_homeTag),
                  _tagId(_gardenTag),
                ],
              },
            ),
          ) as IntentionCommandAccepted;
          final completion = await _completionOf(tester, accepted);

          expect(
            completion.result,
            isA<ResultFailure<IntentionCommandSuccess>>().having(
              (result) => result.failure,
              'отказ',
              switch (failure) {
                _CreationFailure.missingTag =>
                  isA<IntentionCreationTagsMissingFailure>().having(
                    (failure) => failure.missingTagIds,
                    'отсутствующие теги',
                    {_tagId(_missingTag)},
                  ),
                _CreationFailure.storageAfterInitialState =>
                  isA<IntentionUnavailableFailure>(),
              },
            ),
          );
          expect(completion.confirmedChange, isNull);
          if (failure == _CreationFailure.storageAfterInitialState) {
            // Отказ сработал в открытой транзакции, когда в ней уже было
            // записано всё заданное командой начальное состояние: название
            // и описание, готовность к действию, активное состояние,
            // назначение каждого выбранного тега и место избранного. Учтена
            // каждая запись после взвода отказа — вставка, обновление,
            // удаление, пакет или произвольный оператор: это только вставки
            // строки намерения, назначений и места избранного в этом
            // порядке. Запись начального состояния, отложенная за место
            // избранного, к моменту отказа не выполнена, поэтому неполное
            // состояние роняет сценарий.
            final fault = install.faults.faultPoint;
            expect(fault, isNotNull, reason: 'Отказ хранилища не сработал');
            expect(fault!.inTransaction, isTrue);
            expect(fault.writes, [
              'insert intentions',
              'insert tag_assignments',
              'insert tag_assignments',
              'insert favorite_intentions',
            ]);
            expect(fault.created.intentions, [
              (
                title: _created,
                description: _createdDescription,
                readiness: IntentionReadiness.ready,
                archiveState: IntentionArchiveState.active,
              ),
            ]);
            expect(
              fault.created.tags,
              unorderedEquals([
                tagFixtureId(_homeTag),
                tagFixtureId(_gardenTag),
              ]),
            );
            expect(fault.created.places, [4]);
          }
          expect(completions, [same(completion)]);
          expect(_commandEvents(app, since: events), [
            switch (failure) {
              _CreationFailure.missingTag => _createEvent(
                IntentionCreationCommandDiagnosticsStage.validation,
                _failedWith(DiagnosticsFailureCode.validation),
              ),
              _CreationFailure.storageAfterInitialState => _createEvent(
                IntentionCreationCommandDiagnosticsStage.write,
                _failedWith(DiagnosticsFailureCode.unavailable),
              ),
            },
          ]);

          // Свежее чтение графа после отклонённого создания сообщает ту же
          // ревизию, что подтверждённые снимки потребителей до него.
          final revision = await _freshRevision(tester, app);
          for (final MapEntry(key: consumer, value: shownRevision)
              in shownRevisions.entries) {
            expect(
              revision.compareTo(shownRevision),
              GraphRevisionOrder.same,
              reason: consumer,
            );
          }

          // Ни части записи в хранилище: потребители сохраняют те же
          // подтверждённые снимки, а живая форма удерживает своё сообщение.
          await _settleStorage(tester);
          expect(_storedGraph(app.raw), stored);
          _expectSameStates(
            _consumerStates(tester, app, details: _intentionId(_walk)),
            shown,
          );
          expect(find.byKey(_message), findsNothing);

          app.coordinator.releaseInitiatorPresentation(accepted.token);
          await _acceptMessage(
            tester,
            l10n.graphOperationMessage(
              l10n.graphOperationCreate,
              l10n.graphOperationNewIntention,
              switch (failure) {
                _CreationFailure.missingTag => l10n.editorInvalidInput,
                _CreationFailure.storageAfterInitialState =>
                  l10n.editorCreateUnavailable,
              },
            ),
          );
          await _settleStorage(tester);
          expect(_storedGraph(app.raw), stored);
          _expectSameStates(
            _consumerStates(tester, app, details: _intentionId(_walk)),
            shown,
          );
          expect(completions, hasLength(1));
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

/// Три намерения, из них два активных; три тега; единый порядок избранного
/// «Гулять», архивированное «Читать», «Плавать».
void _seedGraph(sqlite.Database database) {
  for (final (number, title, ready, archived) in [
    (_walk, 'Гулять', 1, 0),
    (_read, 'Читать', 1, 1),
    (_swim, 'Плавать', 0, 0),
  ]) {
    database.execute(
      'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
      [tagFixtureId(number), title, ready, archived, number, number],
    );
  }
  for (final MapEntry(key: number, value: name) in _tagNames.entries) {
    database.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
      tagFixtureId(number),
      name,
    ]);
  }
  for (final (tag, intention) in [(_homeTag, _walk), (_workTag, _swim)]) {
    database.execute(
      'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
      [tagFixtureId(tag), tagFixtureId(intention)],
    );
  }
  for (final (index, intention) in [_walk, _read, _swim].indexed) {
    storeFavoriteMark(
      database,
      intentionId: tagFixtureId(intention),
      position: index + 1,
    );
  }
}

/// Намерения с поисковой проекцией, теги, назначения и избранное
/// хранилища.
Map<String, List<List<Object?>>> _storedGraph(sqlite.Database raw) => {
  for (final table in [
    'intentions',
    'intention_titles_fts',
    'tags',
    'tag_assignments',
    'favorite_intentions',
  ])
    table: raw
        .select('SELECT * FROM $table ORDER BY rowid')
        .map((row) => row.values.toList())
        .toList(),
};

/// Установка приложения: постоянное хранилище, переживающее перезапуски, и
/// управляемый отказ записи.
final class _Install {
  _Install(this.harness, this.l10n);

  final LocalDatabaseHarness harness;
  final AppLocalizations l10n;
  final faults = _CreationFaults();
}

Future<_Install> _install(WidgetTester tester, Locale locale) async {
  // Общая поверхность показывает сообщения только работающему приложению.
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  tester.binding.platformDispatcher.localesTestValue = [locale];
  addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final harness = (await tester.runAsync(LocalDatabaseHarness.fileBacked))!;
  addTearDown(harness.dispose);
  return _Install(harness, lookupAppLocalizations(locale));
}

/// Один запуск приложения на хранилище установки.
final class _Launch {
  _Launch(this.runtime, this.raw, this.container, this.diagnostics);

  final AppRuntime runtime;
  final sqlite.Database raw;
  final ProviderContainer container;
  final InMemoryDiagnosticsSink diagnostics;

  AppRouter get router => container.read(appRouterProvider);

  GraphCommandCoordinator get coordinator =>
      container.read(graphCommandCoordinatorProvider.notifier);

  /// Полное завершение: дерево приложения снято, хранилище закрыто.
  Future<void> shutdown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(runtime.shutdown);
  }
}

/// Запускает приложение на хранилище [install], засевает его [seed] и ждёт,
/// пока Главная закончит первоначальное получение.
Future<_Launch> _launch(
  WidgetTester tester,
  _Install install, {
  void Function(sqlite.Database database)? seed,
}) async {
  late sqlite.Database raw;
  final diagnostics = InMemoryDiagnosticsSink();
  final runtime = AppRuntime(
    connectionFactory: () => observeConfiguredLocalDatabaseConnection(
      openFileBackedLocalDatabase(
        install.harness.databaseFile,
        setup: (database) => raw = database,
      ),
      install.faults,
    ),
    diagnosticsSink: diagnostics,
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await runtime.shutdown();
  });
  final ready = (await tester.runAsync(runtime.bootstrap)) as AppRuntimeReady;
  install.faults.connection = raw;
  seed?.call(raw);
  await tester.pumpWidget(MainApp(runtime: runtime));
  await _until(tester, find.byType(HomePage));
  await _waitFor(
    tester,
    () => find.text(install.l10n.homeLoading).evaluate().isEmpty,
  );
  await tester.pumpAndSettle();
  return _Launch(runtime, raw, ready.container, diagnostics);
}

/// Загружает потребителей результата создания: каталог намерений на
/// выбранном пункте панели, а поверх него — навигацию по тегам «Дом»,
/// «Сад» и «Работа». Главная остаётся загруженной, но не выбранной.
Future<void> _openConsumers(WidgetTester tester, _Launch app) async {
  expect(_home(app), isA<HomeList>());
  await _select(tester, AppDestination.intentionGraph);
  await _waitFor(
    tester,
    () => _catalogState(app) is IntentionCatalogLoaded,
    reason: () => 'Каталог: ${_catalogState(app).runtimeType}',
  );
  for (final tag in [_homeTag, _gardenTag, _workTag]) {
    unawaited(app.router.push(TagNavigationRoute(tagId: _tagId(tag))));
    await _until(tester, _navigationPage(tag));
    await _waitFor(
      tester,
      () => switch (_navigation(tester, tag)) {
        final TagNavigationLoaded state => state.canUseCurrentItems,
        _ => false,
      },
      reason: () =>
          'Навигация «${_tagNames[tag]}»: ${_navigation(tester, tag)}',
    );
  }
  await tester.pumpAndSettle();
  expect(_selected(tester), AppDestination.intentionGraph);
  expect(_home(app), isA<HomeList>());
}

/// Открывает подробности намерения [intention] поверх текущих страниц и
/// ждёт актуальных назначений.
Future<void> _openDetails(
  WidgetTester tester,
  _Launch app,
  IntentionId intention,
) async {
  unawaited(app.router.push(IntentionDetailsRoute(intentionId: intention)));
  await _until(
    tester,
    find.byWidgetPredicate(
      (widget) =>
          widget is IntentionDetailsPage && widget.intentionId == intention,
    ),
  );
  await _waitFor(
    tester,
    () => switch (_assignments(app, intention)) {
      final TagAssignmentsLoaded state => state.canUseCurrentItems,
      _ => false,
    },
    reason: () => 'Назначения: ${_assignments(app, intention)}',
  );
  await tester.pumpAndSettle();
}

Future<IntentionCommandCompletion> _completionOf(
  WidgetTester tester,
  IntentionCommandAccepted accepted,
) async {
  IntentionCommandCompletion? completion;
  unawaited(accepted.future.then((value) => completion = value));
  await _waitFor(tester, () => completion != null);
  return completion!;
}

HomeState _home(_Launch app) => app.container.read(homeViewModelProvider);

IntentionCatalogState? _catalogState(_Launch app) => app.container
    .read(intentionCatalogViewModelProvider(const BrowseIntentionCatalog()))
    .value;

IntentionCatalogLoaded _catalog(_Launch app) =>
    _catalogState(app) as IntentionCatalogLoaded;

/// Состояние навигации по тегу [tag]: каждая её страница владеет
/// собственным экземпляром модели.
TagNavigationState _navigation(WidgetTester tester, int tag) =>
    ProviderScope.containerOf(
      tester.element(_navigationPage(tag)),
      listen: false,
    ).read(tagNavigationViewModelProvider(_tagId(tag)));

Finder _navigationPage(int tag) => find.byWidgetPredicate(
  (widget) => widget is TagNavigationPage && widget.tagId == _tagId(tag),
  skipOffstage: false,
);

List<IntentionId> _navigationIds(WidgetTester tester, int tag) => [
  for (final item in (_navigation(tester, tag) as TagNavigationLoaded).items)
    item.id,
];

TagAssignmentsState _assignments(_Launch app, IntentionId intention) =>
    app.container.read(tagAssignmentsViewModelProvider(intention));

List<String> _assignedNames(_Launch app, IntentionId intention) => [
  for (final tag
      in (_assignments(app, intention) as TagAssignmentsLoaded).items)
    tag.name.value,
];

/// Главная, каталог и навигация всех трёх тегов показывают актуальные
/// данные ревизии [revision].
bool _allCurrentAt(WidgetTester tester, _Launch app, GraphRevision revision) {
  bool at(GraphRevision shown) =>
      shown.compareTo(revision) == GraphRevisionOrder.same;
  return switch (_home(app)) {
        final HomeList home =>
          at(home.revision) && home.freshness is HomeFreshnessCurrent,
        _ => false,
      } &&
      switch (_catalogState(app)) {
        final IntentionCatalogLoaded catalog => at(catalog.revision),
        _ => false,
      } &&
      [_homeTag, _gardenTag, _workTag].every(
        (tag) => switch (_navigation(tester, tag)) {
          final TagNavigationLoaded state =>
            at(state.revision) && state.canUseCurrentItems,
          _ => false,
        },
      );
}

/// Подтверждённые снимки загруженных потребителей: Главной, каталога,
/// навигации по тегам и, если открыты подробности намерения [details], его
/// назначений.
Map<String, Object?> _consumerStates(
  WidgetTester tester,
  _Launch app, {
  IntentionId? details,
}) => {
  'Главная': _home(app),
  'каталог': _catalogState(app),
  for (final tag in [_homeTag, _gardenTag, _workTag])
    'навигация «${_tagNames[tag]}»': _navigation(tester, tag),
  if (details != null) 'назначения': _assignments(app, details),
};

/// Ревизии подтверждённых снимков потребителей [states].
Map<String, GraphRevision> _revisions(Map<String, Object?> states) => {
  for (final MapEntry(:key, :value) in states.entries)
    key: switch (value) {
      HomeLoaded(:final revision) ||
      IntentionCatalogConfirmedState(:final revision) ||
      TagNavigationLoaded(:final revision) ||
      TagAssignmentsLoaded(:final revision) => revision,
      _ => fail('У потребителя «$key» нет подтверждённого снимка: $value'),
    },
};

/// Ревизия графа по свежему публичному чтению модуля графа.
Future<GraphRevision> _freshRevision(WidgetTester tester, _Launch app) async {
  final repository = app.container.read(personalGraphRepositoryProvider);
  final result = await tester.runAsync(
    () => repository.getRelationCounts(_intentionId(_walk)),
  );
  return switch (result) {
    ResultSuccess(:final value) => value.revision,
    final result => fail('Чтение графа не удалось: $result'),
  };
}

void _expectSameStates(
  Map<String, Object?> actual,
  Map<String, Object?> expected,
) {
  expect(actual.keys, expected.keys);
  for (final MapEntry(:key, :value) in expected.entries) {
    expect(actual[key], same(value), reason: key);
  }
}

/// События самостоятельных команд намерений, тегов и порядка избранного
/// после первых [since] событий.
List<DiagnosticsEvent> _commandEvents(_Launch app, {required int since}) => [
  for (final event in app.diagnostics.events.skip(since))
    if (event is IntentionCommandDiagnosticsEvent ||
        event is TagCommandDiagnosticsEvent ||
        event is FavoriteOrderCommandDiagnosticsEvent)
      event,
];

Matcher _createEvent(
  IntentionCreationCommandDiagnosticsStage stage,
  Matcher status,
) => isA<IntentionCommandDiagnosticsEvent>()
    .having(
      (event) => event.commandType,
      'команда',
      IntentionCommandDiagnosticsType.create,
    )
    .having((event) => event.stage, 'этап', stage)
    .having((event) => event.status, 'исход', status);

Matcher _failedWith(DiagnosticsFailureCode code) =>
    isA<DiagnosticsFailed>().having((status) => status.code, 'категория', code);

/// Названия намерений, показанные видимой страницей [page], в порядке
/// дерева виджетов.
List<String> _visibleTitles(WidgetTester tester, Type page) => [
  for (final text in tester.widgetList<Text>(
    find.descendant(
      of: find.byType(page),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            {'Гулять', 'Читать', 'Плавать', _created}.contains(widget.data),
      ),
    ),
  ))
    text.data!,
];

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

AppDestination _selected(WidgetTester tester) => tester
    .widget<AppNavigationBar>(
      find.byType(AppNavigationBar, skipOffstage: false),
    )
    .selected;

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

/// Закрывает верхнюю страницу.
Future<void> _pop(WidgetTester tester, _Launch app) async {
  unawaited(app.router.maybePop());
  await tester.pumpAndSettle();
}

/// Дожидается ровно одного сообщения [text] общей поверхности и закрывает
/// его; предъявленный результат не показывается повторно.
Future<void> _acceptMessage(WidgetTester tester, String text) async {
  await _until(tester, find.byKey(_message));
  await tester.pumpAndSettle();
  expect(find.byType(SnackBar), findsOneWidget);
  expect(find.text(text), findsOneWidget);
  ScaffoldMessenger.of(tester.element(find.byKey(_message)))
      .hideCurrentSnackBar();
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
  expect(find.byKey(_message), findsNothing);
}

/// Даёт хранилищу и кадрам время: запущенное чтение успело бы завершиться.
Future<void> _settleStorage(WidgetTester tester) async {
  for (var attempt = 0; attempt < 5; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pumpAndSettle();
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

/// Поля строки намерения, которые задаёт команда создания.
typedef _IntentionRow = ({
  String title,
  String? description,
  IntentionReadiness readiness,
  IntentionArchiveState archiveState,
});

/// Строки намерений, которых нет в исходном графе, теги их назначений и
/// места избранного.
typedef _CreatedRows = ({
  List<_IntentionRow> intentions,
  List<String> tags,
  List<int> places,
});

/// Строки намерений вне исходного графа, видимые на соединении [raw],
/// включая записи ещё не подтверждённой транзакции.
_CreatedRows _createdRows(sqlite.Database raw) {
  const created = 'SELECT id FROM intentions WHERE id NOT IN (?, ?, ?)';
  final seeded = [
    for (final intention in [_walk, _read, _swim]) tagFixtureId(intention),
  ];
  return (
    intentions: [
      for (final row in raw.select(
        'SELECT title, description, is_action_ready, is_archived '
        'FROM intentions WHERE id IN ($created)',
        seeded,
      ))
        (
          title: row['title'] as String,
          description: row['description'] as String?,
          readiness: row['is_action_ready'] == 1
              ? IntentionReadiness.ready
              : IntentionReadiness.notReady,
          archiveState: row['is_archived'] == 1
              ? IntentionArchiveState.archived
              : IntentionArchiveState.active,
        ),
    ],
    tags: [
      for (final row in raw.select(
        'SELECT tag_id FROM tag_assignments WHERE intention_id IN ($created)',
        seeded,
      ))
        row['tag_id'] as String,
    ],
    places: [
      for (final row in raw.select(
        'SELECT position FROM favorite_intentions '
        'WHERE intention_id IN ($created)',
        seeded,
      ))
        row['position'] as int,
    ],
  );
}

/// Состояние хранилища в момент управляемого отказа: открыта ли
/// транзакция, все записи после взвода отказа в порядке выполнения и
/// видимые на соединении строки создаваемого намерения.
typedef _CreationFaultPoint = ({
  bool inTransaction,
  List<String> writes,
  _CreatedRows created,
});

/// По требованию прерывает ближайшую запись места избранного сразу после
/// её выполнения устранимой недоступностью хранилища и фиксирует, что к
/// этому моменту записано на соединении приложения. Отказ не проверяет
/// состав записей сам: его проверяет сценарий по [faultPoint].
final class _CreationFaults extends LocalDatabaseConnectionObserver {
  /// Таблица, которую изменяет оператор SQL.
  static final _writtenTable = RegExp(
    r'^\s*(?:INSERT(?:\s+OR\s+\w+)?\s+INTO|REPLACE\s+INTO|'
    r'UPDATE(?:\s+OR\s+\w+)?|DELETE\s+FROM)\s+"?(\w+)"?',
    caseSensitive: false,
  );

  /// Соединение запущенного приложения: на нём видны записи ещё не
  /// подтверждённой транзакции.
  late sqlite.Database connection;

  /// Записи после взвода отказа: вид операции и изменяемые таблицы либо
  /// оператор, если таблицу не удаётся определить; `null`, пока отказ не
  /// взведён.
  List<String>? _writes;

  /// Состояние хранилища в момент отказа; `null`, пока отказ не сработал.
  _CreationFaultPoint? faultPoint;

  void failAfterFavoritePlaceWrite() => _writes = [];

  /// Учитывает каждую операцию, кроме чтения: вставку, обновление,
  /// удаление, пакет и произвольный оператор.
  @override
  void afterStatement(LocalDatabaseSqlStatement statement) {
    final writes = _writes;
    if (writes == null ||
        statement.operation == LocalDatabaseSqlOperation.select) {
      return;
    }
    final tables = [
      for (final sql in statement.statements)
        _writtenTable.firstMatch(sql)?.group(1) ?? sql,
    ];
    writes.add('${statement.operation.name} ${tables.join(', ')}');
    if (!tables.contains('favorite_intentions')) return;
    _writes = null;
    faultPoint = (
      inTransaction: !connection.autocommit,
      writes: List.unmodifiable(writes),
      created: _createdRows(connection),
    );
    throw sqlite.SqliteException(
      extendedResultCode: sqlite.SqlError.SQLITE_BUSY,
      message: 'Управляемый отказ после записи места избранного',
    );
  }
}
