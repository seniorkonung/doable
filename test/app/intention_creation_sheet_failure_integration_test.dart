import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_page.dart';
import 'package:doable/src/shared/diagnostics/developer_diagnostics_sink.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/app_root_pages.dart';
import '../support/favorite_storage_fixture.dart';
import '../support/local_database_harness.dart';
import '../support/intention_creation_storage_observer.dart';
import '../support/tag_storage_fixture.dart';

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
final _confirmation = _key('intention-editor-close-confirmation');
final _message = _key('graph-operation-message');
final _failure = _key('intention-editor-failure');

void main() {
  testWidgets(
    'переименование сохраняет выбранную идентичность; удаление с одноимённой '
    'заменой отклоняет весь черновик без записей и допускает новое создание '
    'только после явного исправления через панель и общий выбор',
    (tester) async {
      final app = await _launch(tester);
      final sport = await _prepare(tester, app);
      await _runTag(
        tester,
        app,
        app.coordinator.acceptTagRename(
          RenameTag(tagId: _home, name: TagName.fromInput('Быт')),
        ),
        app.l10n.tagRenamed,
      );
      await _wait(
        tester,
        () =>
            tester
                .widget<Text>(
                  _key(
                    'intention-editor-tag-name-${_home.toCanonicalString()}',
                  ),
                )
                .data ==
            'Быт',
      );
      _expectDraft(tester, [_home, sport]);
      await _runTag(
        tester,
        app,
        app.coordinator.acceptTagDelete(DeleteTag(sport)),
        app.l10n.tagDeleted,
      );
      await _tap(tester, _key('intention-editor-choose-tags'));
      final replacement = await _newTag(tester, app);
      expect(replacement, isNot(sport));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      _expectDraft(tester, [_home, sport]);
      expect(_chip(replacement), findsNothing);
      final before = _storedGraph(app.raw);
      final revision = await _revision(tester, app);
      app.storage.observeCreation();
      await _tap(tester, _submit);
      final failed = await _creation(tester, app);
      await tester.pumpAndSettle();
      expect(
        failed.result,
        isA<ResultFailure>().having(
          (result) => result.failure,
          'причина',
          isA<IntentionCreationTagsMissingFailure>().having(
            (failure) => failure.missingTagIds,
            'отсутствующие идентификаторы',
            {sport},
          ),
        ),
      );
      expect(failed.confirmedChange, isNull);
      expect(_storedGraph(app.raw), before);
      expect(app.storage.writes, isEmpty);
      expect(
        (await _revision(tester, app)).compareTo(revision),
        GraphRevisionOrder.same,
      );
      _expectDraft(tester, [_home, sport]);
      _expectInlineFailure(
        tester,
        app,
        failed,
        app.l10n.editorCreateTagsMissing(1),
      );
      expect(tester.widget<FilledButton>(_submit).onPressed, isNull);

      // Нерелевантная правка текста не разрешает повтор и не меняет набор.
      await tester.enterText(
        _key('intention-editor-description'),
        '$_description!',
      );
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(_submit).onPressed, isNull);
      await tester.enterText(
        _key('intention-editor-description'),
        _description,
      );
      await _tap(tester, _key('intention-editor-remove-missing-tags'));
      await tester.pumpAndSettle();
      expect(_chip(sport), findsNothing);
      expect(_chip(_home), findsOneWidget);
      expect(app.creations, [same(failed)]);
      expect(_storedGraph(app.raw), before);
      await _tap(tester, _key('intention-editor-choose-tags'));
      await _add(tester, replacement);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      _expectDraft(tester, [_home, replacement]);
      expect(app.creations, [same(failed)]);
      expect(app.storage.writes, isEmpty);

      await _tap(tester, _submit);
      final saved = await _creation(tester, app, count: 2);
      await _wait(tester, () => _sheet.evaluate().isEmpty);
      _expectSaved(app, saved, [_home, replacement]);
      expect(saved.token, isNot(same(failed.token)));
      expect(
        (saved.confirmedChange!.changes.first as IntentionCatalogCreated)
            .entry
            .summary
            .tags
            .map((tag) => tag.name.value),
        ['Быт', _sport],
      );
      expect(app.storage.writes, _fullWrites);
      await _acceptMessage(tester, _successMessage(app));
      expect(_intentionEvents(app), [
        _createEvent(
          _failedWith(DiagnosticsFailureCode.validation),
          IntentionCreationCommandDiagnosticsStage.validation,
        ),
        _createEvent(
          isA<DiagnosticsSucceeded>(),
          IntentionCreationCommandDiagnosticsStage.resultRead,
        ),
      ]);
      app.diagnostics.expectPrivateDataHidden(app.raw);
      expect(tester.takeException(), isNull);
    },
  );

  for (final leave in _Leave.values) {
    testWidgets(
      'подтверждённый сброс полного черновика через ${leave.description} '
      'не пишет намерение, назначения или избранное и сохраняет тег редактора',
      (tester) async {
        final app = await _launch(tester);
        final before = _storedGraph(app.raw);
        final sport = await _prepare(tester, app);
        final revision = await _revision(tester, app);
        final withTag = _storedGraph(app.raw);
        expect(withTag, {...before, 'tags': withTag['tags']});
        expect(withTag['tags'], hasLength(before['tags']!.length + 1));
        expect(withTag['tags']!.take(before['tags']!.length), before['tags']);
        expect(app.creations, isEmpty);
        expect(app.diagnostics.commands, hasLength(2));

        await leave.request(tester);
        await _tap(tester, _key('intention-editor-close-continue'));
        await tester.pumpAndSettle();
        _expectDraft(tester, [_home, sport]);
        expect(_storedGraph(app.raw), withTag);

        await leave.request(tester);
        await _tap(tester, _key('intention-editor-close-discard'));
        await tester.pumpAndSettle();
        expect(_sheet, findsNothing);
        expect(_storedGraph(app.raw), withTag);
        expect(storedFavoriteMarks(app.raw), [
          (tagFixtureId(1), 1),
          (tagFixtureId(2), 2),
        ]);
        expect(
          (await _revision(tester, app)).compareTo(revision),
          GraphRevisionOrder.same,
        );
        expect(app.creations, isEmpty);
        expect(app.diagnostics.commands, hasLength(2));
        app.diagnostics.expectPrivateDataHidden(app.raw);

        await _open(tester);
        expect(_text(tester, 'intention-editor-title'), isEmpty);
        expect(_text(tester, 'intention-editor-description'), isEmpty);
        expect(_chip(_home), findsNothing);
        expect(_chip(sport), findsNothing);
        expect(_icon(tester, 'intention-editor-favorite'), Icons.star_border);
        expect(
          _icon(tester, 'intention-editor-readiness'),
          Icons.check_circle_outline,
        );
        await leave.request(tester, changed: false);
        expect(_sheet, findsNothing);
        expect(_confirmation, findsNothing);
        expect(_message, findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('отказ файлового хранилища после всех записей полного черновика '
      'откатывает граф, FTS, порядок и ревизию; компактная панель '
      'предъявляет один отказ и явный повтор сохраняет одно намерение '
      'на экране 568×320 с открытой клавиатурой и масштабом 200% '
      'даже при отказе диагностики', (tester) async {
    final app = await _launch(tester);
    final sport = await _prepare(tester, app);
    tester.view.physicalSize = const Size(568, 320);
    tester.view.padding = const FakeViewPadding(top: 24, right: 48);
    tester.view.viewPadding = const FakeViewPadding(top: 24, right: 48);
    tester.view.viewInsets = const FakeViewPadding(bottom: 160);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    final before = _storedGraph(app.raw);
    final revision = await _revision(tester, app);
    final marks = storedFavoriteMarks(app.raw);
    final sheetElement = tester.element(_sheet);
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
    expect(storedFavoriteMarks(app.raw), marks);
    expect(
      (await _revision(tester, app)).compareTo(revision),
      GraphRevisionOrder.same,
    );
    _expectDraft(tester, [_home, sport]);
    expect(tester.element(_sheet), same(sheetElement));
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
    _expectInlineFailure(tester, app, failed, app.l10n.editorCreateUnavailable);
    expect(
      tester.getSemantics(_failure),
      isSemantics(label: app.l10n.editorCreateUnavailable),
    );
    expect(_submit.hitTestable(), findsOneWidget);
    expect(tester.widget<FilledButton>(_submit).onPressed, isNotNull);
    expect(_intentionEvents(app), [
      _createEvent(
        _failedWith(DiagnosticsFailureCode.unavailable),
        IntentionCreationCommandDiagnosticsStage.write,
      ),
    ]);
    expect(app.diagnostics.thrown, 1);

    // Одноразовый hook уже снял отказ. Сами поля и исправления не
    // отправляют новую команду: повтор выполняется только кнопкой панели.
    expect(app.creations, [same(failed)]);
    expect(app.storage.creationAttempts, 1);
    _expectTightKeyboard(tester);
    await _tap(tester, _submit);
    final saved = await _creation(tester, app, count: 2);
    await _wait(tester, () => _sheet.evaluate().isEmpty);
    final id = _expectSaved(app, saved, [_home, sport]);
    expect(
      app.creations.map((completion) => completion.token).toSet(),
      hasLength(2),
    );
    expect(app.storage.writes, [..._fullWrites, ..._fullWrites]);
    expect(storedFavoriteMarks(app.raw), [
      ...marks,
      (id.toCanonicalString(), 3),
    ]);
    expect(saved.revision!.compareTo(revision), GraphRevisionOrder.newer);
    expect(
      (await _revision(tester, app)).compareTo(saved.revision!),
      GraphRevisionOrder.same,
    );
    expect(app.diagnostics.thrown, 2);
    await _acceptMessage(tester, _successMessage(app));
    expect(_intentionEvents(app), [
      _createEvent(
        _failedWith(DiagnosticsFailureCode.unavailable),
        IntentionCreationCommandDiagnosticsStage.write,
      ),
      _createEvent(
        isA<DiagnosticsSucceeded>(),
        IntentionCreationCommandDiagnosticsStage.resultRead,
      ),
    ]);
    app.diagnostics.expectPrivateDataHidden(app.raw);
    expect(tester.takeException(), isNull);
  });
  for (final leave in _Leave.values) {
    for (final outcome in _Outcome.values) {
      for (final surface in _AtResult.values) {
        testWidgets(
          '${outcome.description} задержанной отправки; уход через ${leave.description} '
          '${surface.description}: команда продолжается один раз, результат '
          'получает один владелец и чужая сессия не меняется',
          (tester) async {
            final app = await _launch(tester);
            final sport = await _prepare(tester, app);
            final before = _storedGraph(app.raw);
            final revision = await _revision(tester, app);
            app.storage.observeCreation(fail: outcome == _Outcome.failure);
            app.storage.hold();
            await _tap(tester, _submit);
            await _wait(tester, () => app.storage.isHolding);
            expect(app.creations, isEmpty);
            expect(app.storage.creationAttempts, 1);
            expect(tester.widget<FilledButton>(_submit).onPressed, isNull);
            expect(
              tester.widget<TextField>(_key('intention-editor-title')).readOnly,
              isTrue,
            );
            expect(
              tester
                  .widget<TextField>(_key('intention-editor-description'))
                  .readOnly,
              isTrue,
            );
            for (final key in [
              'intention-editor-favorite',
              'intention-editor-readiness',
              'intention-editor-choose-tags',
              for (final tag in [_home, sport])
                'intention-editor-tag-remove-${tag.toCanonicalString()}',
            ]) {
              expect(tester.widget<IconButton>(_key(key)).onPressed, isNull);
            }
            // Настоящее повторное нажатие по недоступному сохранению не
            // запускает и не ставит в очередь вторую команду.
            await tester.tap(_submit);
            await leave.request(tester);
            final lateDiscard = tester
                .widget<FilledButton>(_key('intention-editor-close-discard'))
                .onPressed!;
            expect(
              find.text(app.l10n.editorCloseSavingMessage),
              findsOneWidget,
            );
            if (surface != _AtResult.confirmation) {
              await _tap(tester, _key('intention-editor-close-discard'));
              await tester.pumpAndSettle();
              expect(_sheet, findsNothing);
              expect(app.storage.isHolding, isTrue);
              if (surface == _AtResult.newOpening) {
                await _open(tester);
                await tester.enterText(
                  _key('intention-editor-title'),
                  'Другое намерение',
                );
                await tester.enterText(
                  _key('intention-editor-description'),
                  'Другой черновик',
                );
              }
            }
            expect(_storedGraph(app.raw), before);
            app.storage.release();
            final completion = await _creation(tester, app);
            await tester.pumpAndSettle();
            expect(app.storage.creationAttempts, 1);
            expect(app.storage.writes, _fullWrites);
            expect(app.creations, [same(completion)]);

            switch (outcome) {
              case _Outcome.success:
                final id = _expectSaved(app, completion, [_home, sport]);
                expect(storedFavoriteMarks(app.raw), [
                  (tagFixtureId(1), 1),
                  (tagFixtureId(2), 2),
                  (id.toCanonicalString(), 3),
                ]);
                expect(
                  completion.revision!.compareTo(revision),
                  GraphRevisionOrder.newer,
                );
                expect(
                  (await _revision(
                    tester,
                    app,
                  )).compareTo(completion.revision!),
                  GraphRevisionOrder.same,
                );
                if (surface != _AtResult.newOpening) {
                  expect(_sheet, findsNothing);
                  expect(_confirmation, findsNothing);
                }
                await _acceptMessage(tester, _successMessage(app));
              case _Outcome.failure:
                expect(
                  completion.result,
                  isA<ResultFailure>().having(
                    (result) => result.failure,
                    'причина',
                    isA<IntentionUnavailableFailure>(),
                  ),
                );
                expect(completion.confirmedChange, isNull);
                _expectFaultPoint(app, [_home, sport]);
                expect(_storedGraph(app.raw), before);
                expect(
                  (await _revision(tester, app)).compareTo(revision),
                  GraphRevisionOrder.same,
                );
                if (surface == _AtResult.confirmation) {
                  // Отказ меняет состояние отправки: прежнее подтверждение
                  // недействительно, а право ошибки остаётся живой панели.
                  expect(_confirmation, findsNothing);
                  expect(_message, findsNothing);
                  _expectDraft(tester, [_home, sport]);
                  _expectInlineFailure(
                    tester,
                    app,
                    completion,
                    app.l10n.editorCreateUnavailable,
                  );
                  await leave.request(tester);
                  await _tap(tester, _key('intention-editor-close-discard'));
                  await tester.pumpAndSettle();
                  // Предъявленный формой отказ не появляется повторно после
                  // окончательного ухода инициатора.
                  expect(_message, findsNothing);
                } else {
                  expect(_failure, findsNothing);
                  await _acceptMessage(
                    tester,
                    app.l10n.graphOperationMessage(
                      app.l10n.graphOperationCreate,
                      app.l10n.graphOperationNewIntention,
                      app.l10n.editorCreateUnavailable,
                    ),
                  );
                }
            }
            expect(
              app.coordinator.claimInitiatorFailure(completion.token),
              isNull,
            );
            // Callback уже показанного подтверждения может запоздать.
            // Он не закрывает новую панель и не повторяет принятую команду.
            lateDiscard();
            await tester.pumpAndSettle();
            if (surface == _AtResult.newOpening) {
              expect(_sheet, findsOneWidget);
              expect(
                _text(tester, 'intention-editor-title'),
                'Другое намерение',
              );
              expect(
                _text(tester, 'intention-editor-description'),
                'Другой черновик',
              );
              expect(_chip(_home), findsNothing);
              expect(_chip(sport), findsNothing);
              expect(
                _icon(tester, 'intention-editor-favorite'),
                Icons.star_border,
              );
              expect(
                _icon(tester, 'intention-editor-readiness'),
                Icons.check_circle_outline,
              );
              expect(tester.widget<FilledButton>(_submit).onPressed, isNotNull);
              expect(_confirmation, findsNothing);
            }
            expect(_intentionEvents(app), [
              _createEvent(
                outcome == _Outcome.success
                    ? isA<DiagnosticsSucceeded>()
                    : _failedWith(DiagnosticsFailureCode.unavailable),
                outcome == _Outcome.success
                    ? IntentionCreationCommandDiagnosticsStage.resultRead
                    : IntentionCreationCommandDiagnosticsStage.write,
              ),
            ]);
            await tester.pump(const Duration(seconds: 5));
            await tester.pumpAndSettle();
            expect(_message, findsNothing);
            expect(app.creations, hasLength(1));
            expect(app.storage.creationAttempts, 1);
            app.diagnostics.expectPrivateDataHidden(app.raw);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}

enum _Outcome {
  success('успех'),
  failure('отказ');

  const _Outcome(this.description);
  final String description;
}

enum _AtResult {
  catalog('при закрытой панели'),
  confirmation('при открытом подтверждении'),
  newOpening('после нового открытия');

  const _AtResult(this.description);
  final String description;
}

/// Все источники запроса закрытия вызываются настоящими действиями панели.
enum _Leave {
  barrier('нажатие по фону'),
  handle('свайп ручки'),
  back('системное «назад»');

  const _Leave(this.description);
  final String description;

  Future<void> request(WidgetTester tester, {bool changed = true}) async {
    switch (this) {
      case barrier:
        await tester.tapAt(Offset(20, tester.getRect(_sheet).top / 2));
      case handle:
        await tester.drag(
          _key('intention-creation-sheet-handle'),
          const Offset(0, 240),
        );
      case back:
        await tester.binding.handlePopRoute();
    }
    await tester.pumpAndSettle();
    expect(_confirmation, changed ? findsOneWidget : findsNothing);
  }
}

final class _App {
  _App(
    this.raw,
    this.container,
    this.diagnostics,
    this.completions,
    this.storage,
  );

  final sqlite.Database raw;
  final ProviderContainer container;
  final _Diagnostics diagnostics;
  final List<GraphCommandCompletion> completions;
  final IntentionCreationStorageObserver storage;
  GraphCommandCoordinator get coordinator =>
      container.read(graphCommandCoordinatorProvider.notifier);
  List<IntentionCommandCompletion> get creations =>
      completions.whereType<IntentionCommandCompletion>().toList();
  AppLocalizations get l10n => lookupAppLocalizations(const Locale('ru'));
}

Future<_App> _launch(WidgetTester tester) async {
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
    storage.release();
    await tester.pumpWidget(const SizedBox.shrink());
    await runtime.shutdown();
  });
  final ready = (await tester.runAsync(runtime.bootstrap)) as AppRuntimeReady;
  storage.connection = raw;
  for (final (id, title, archived) in [(1, 'Гулять', 0), (2, 'Читать', 1)]) {
    raw.execute(
      'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, 0, ?, 1, 1)',
      [tagFixtureId(id), title, archived],
    );
    storeFavoriteMark(raw, intentionId: tagFixtureId(id), position: id);
  }
  raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
    tagFixtureId(301),
    'Дом',
  ]);
  raw.execute(
    'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
    [tagFixtureId(301), tagFixtureId(1)],
  );
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
  return _App(raw, ready.container, diagnostics, completions, storage);
}

Future<void> _open(WidgetTester tester) async {
  await _tap(tester, _key('catalog-create-intention'));
  await tester.pumpAndSettle();
  expect(_sheet, findsOneWidget);
  expect(find.byType(IntentionEditorPage), findsOneWidget);
}

/// Команда создаётся исключительно формой: все пять полей и отдельный тег
/// подготавливаются реальными панелью, общим выбором и редактором тега.
Future<TagId> _prepare(WidgetTester tester, _App app) async {
  await _open(tester);
  await tester.enterText(_key('intention-editor-title'), _rawTitle);
  await tester.enterText(_key('intention-editor-description'), _description);
  await _tap(tester, _key('intention-editor-favorite'));
  await _tap(tester, _key('intention-editor-readiness'));
  await _tap(tester, _key('intention-editor-readiness-confirm'));
  await _tap(tester, _key('intention-editor-choose-tags'));
  await _add(tester, _home);
  // Локальные правки не маскируются событиями постоянных команд.
  expect(app.completions, isEmpty);
  expect(app.diagnostics.commands, isEmpty);
  final sport = await _newTag(tester, app);
  await _add(tester, sport);
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
  _expectDraft(tester, [_home, sport]);
  expect(app.completions.single, isA<TagCommandCompletion>());
  expect(app.diagnostics.commands, [
    isA<TagCommandDiagnosticsEvent>(),
    isA<TagCommandDiagnosticsEvent>(),
  ]);
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

/// Имитирует подтверждённое изменение тега другим потребителем графа;
/// создание намерения остаётся исключительно пользовательским UI-путём.
Future<void> _runTag(
  WidgetTester tester,
  _App app,
  TagCommandStart start,
  String outcome,
) async {
  final completion = await tester.runAsync(
    () => (start as TagCommandAccepted).future,
  );
  expect(completion!.isFailure, isFalse);
  await _acceptMessage(
    tester,
    app.l10n.graphOperationMessage(
      completion.kind == TagCommandKind.rename
          ? app.l10n.graphOperationUpdate
          : app.l10n.graphOperationDelete,
      app.l10n.graphOperationTag,
      outcome,
    ),
  );
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
  expect(_icon(tester, 'intention-editor-favorite'), Icons.star);
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
    'favorite_intentions',
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

Future<GraphRevision> _revision(WidgetTester tester, _App app) async =>
    switch (await tester.runAsync(
      () => app.container
          .read(personalGraphRepositoryProvider)
          .getRelationCounts(_seededIntention),
    )) {
      ResultSuccess(:final value) => value.revision,
      final result => fail('Не удалось прочитать публичную ревизию: $result'),
    };

final class _Diagnostics implements DiagnosticsSink {
  final events = <DiagnosticsEvent>[];
  final lines = <String>[];
  final privateValues = <String>[];
  var throwOnIntentionCommand = false;
  var thrown = 0;
  List<DiagnosticsEvent> get commands => events
      .where(
        (event) =>
            event is IntentionCommandDiagnosticsEvent ||
            event is TagCommandDiagnosticsEvent ||
            event is FavoriteOrderCommandDiagnosticsEvent,
      )
      .toList();

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
      'favorite_intentions',
      ...privateValues,
      for (final table in ['tags', 'intentions'])
        for (final row in raw.select('SELECT id FROM $table'))
          row['id'] as String,
    ]) {
      expect(recorded, isNot(contains(value)), reason: value);
    }
  }
}

const _fullWrites = [
  'intentions',
  'tag_assignments',
  'tag_assignments',
  'favorite_intentions',
];

/// Свидетельство, что отказ сработал после полного набора внутри транзакции,
/// а не раньше записи тегов, отметок, готовности или временных меток.
void _expectFaultPoint(_App app, List<TagId> tags) {
  final point = app.storage.faultPoint!;
  expect(point.inTransaction, isTrue);
  expect(point.writes, _fullWrites);
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
  expect(
    point.graph['tag_assignments']!.skip(1),
    unorderedEquals([
      for (final tag in tags)
        [
          isA<int>(),
          tag.toCanonicalString(),
          point.graph['tags']!.singleWhere(
            (stored) => stored[1] == tag.toCanonicalString(),
          )[0],
          row.first,
        ],
    ]),
  );
  expect(point.graph['favorite_intentions']!.last, [row.first, 3]);
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

IntentionId _expectSaved(
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
  final mutation = saved.catalogMutation as IntentionCatalogCreated;
  expect(mutation.entry.summary.favoriteMark, FavoriteMark.favorite);
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
  return intention.id;
}

void _expectInlineFailure(
  WidgetTester tester,
  _App app,
  IntentionCommandCompletion completion,
  String text,
) {
  expect(_failure.hitTestable(), findsOneWidget);
  expect(find.text(text).hitTestable(), findsOneWidget);
  expect(_message, findsNothing);
  expect(find.byType(SnackBar), findsNothing);
  expect(app.coordinator.claimInitiatorFailure(completion.token), isNull);
}

String _successMessage(_App app) => app.l10n.graphOperationMessage(
  app.l10n.graphOperationCreate,
  _title,
  app.l10n.editorCreated,
);
List<DiagnosticsEvent> _intentionEvents(_App app) => app.diagnostics.events
    .whereType<IntentionCommandDiagnosticsEvent>()
    .toList();
Matcher _failedWith(DiagnosticsFailureCode code) =>
    isA<DiagnosticsFailed>().having((status) => status.code, 'категория', code);
Matcher _createEvent(
  Matcher status,
  IntentionCreationCommandDiagnosticsStage stage,
) => isA<IntentionCommandDiagnosticsEvent>()
    .having(
      (event) => event.commandType,
      'команда',
      IntentionCommandDiagnosticsType.create,
    )
    .having((event) => event.stage, 'этап', stage)
    .having((event) => event.status, 'исход', status);

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
  expect(tester.platformDispatcher.textScaleFactor, 2);
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
