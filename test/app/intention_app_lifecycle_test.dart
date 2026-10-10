import 'dart:async';

import 'package:doable/src/daily_choice/application/daily_choice_catalog.dart';
import 'package:doable/src/daily_choice/application/choice_path_continuations.dart';
import 'package:doable/src/daily_choice/application/choice_path_suggestions.dart';

import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:auto_route/auto_route.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/data/local/app_database.dart'
    show openInMemoryLocalDatabase;
import 'package:doable/src/graph/application/delete_blocking_relations.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/selected_relations.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart'
    as catalog_page;
import 'package:doable/src/intention/presentation/editor/intention_editor_page.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_root_pages.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/favorite_read_contract_test_fallback.dart';
import '../support/tag_read_contract_test_fallback.dart';
import '../support/catalog_reconciliation_test_fallback.dart';
import '../support/in_memory_quick_creation_mode_store.dart';
import '../support/quick_creation.dart';

void main() {
  testWidgets(
    'ошибка массового удаления после ухода из собранного экрана предъявляется один раз',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final semantics = tester.ensureSemantics();
      tester.binding.platformDispatcher.localesTestValue = const [Locale('en')];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      final intentionA = _intention(title: 'A', description: null);
      final intentionB = _intention(
        uuid: '018f0000-0000-7000-8000-000000000002',
        title: 'B',
        description: null,
      );
      final repository = _DelayedPersonalGraphRepository(
        relation: _relationSummary(intentionA, intentionB),
      );
      final runtime = await _pumpCatalog(tester, repository, [
        intentionA,
        intentionB,
      ]);
      await _openDetails(tester, repository, intentionA, requestIndex: 0);
      await tester.ensureVisible(
        find.byKey(const ValueKey('intention-details-delete')),
      );
      await tester.tap(find.byKey(const ValueKey('intention-details-delete')));
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('intention-details-confirm-delete')),
      );
      await _pumpUntil(tester, () => repository.commands.length == 1);
      repository.completeCommand(
        0,
        ResultFailure(IntentionHasBlockingRelationsFailure(intentionA.id)),
      );
      await _pumpUntil(
        tester,
        () => find
            .byKey(const ValueKey('intention-details-show-blocking-relations'))
            .evaluate()
            .isNotEmpty,
      );
      final showBlocking = find.byKey(
        const ValueKey('intention-details-show-blocking-relations'),
      );
      await tester.ensureVisible(showBlocking);
      await tester.tap(showBlocking);
      await tester.pumpAndSettle();
      final select = find.byKey(
        ValueKey(
          'relation-neighborhood-select-${_relationId.toCanonicalString()}',
        ),
      );
      await tester.ensureVisible(select);
      await tester.tap(select);
      await tester.pumpAndSettle();
      final review = find.byKey(const ValueKey('blocking-relations-review'));
      await tester.ensureVisible(review);
      await tester.tap(review);
      await _pumpUntil(
        tester,
        () => find
            .byKey(const ValueKey('blocking-relations-confirm-delete'))
            .evaluate()
            .isNotEmpty,
      );
      await tester.tap(
        find.byKey(const ValueKey('blocking-relations-confirm-delete')),
      );
      await _pumpUntil(
        tester,
        () => repository.blockingRelationsCommands.length == 1,
      );
      expect(repository.blockingRelationsCommands.single.relationIds, {
        _relationId,
      });

      await tester.pumpAndSettle();
      await _goBack(tester);
      await _openDetails(tester, repository, intentionB, requestIndex: 1);
      expect(runtime.commandCoordinator.isRunning(intentionA.id), isTrue);
      repository.completeBlockingRelationsCommand(
        0,
        const GraphCommandFailed<
          BlockingRelationsDeleted,
          DeleteBlockingRelationsFailure
        >(DeleteBlockingRelationsUnavailableFailure()),
      );
      await tester.pumpAndSettle();
      const message =
          'Delete selected relations — “A”: Selected relations couldn’t be deleted. Try again.';
      expect(find.text(message), findsOneWidget);
      expect(
        tester.getSemantics(
          find.byKey(const ValueKey('graph-operation-message')),
        ),
        matchesSemantics(
          label: message,
          isLiveRegion: true,
          textDirection: TextDirection.ltr,
        ),
      );
      await _closeOperationMessage(tester);
      expect(find.text(message), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets(
    'проходит полный app-level lifecycle через задерживаемый repository',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.binding.platformDispatcher.localesTestValue = const [Locale('en')];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      final repository = _DelayedPersonalGraphRepository();
      final runtime = AppRuntime(
        quickCreationModeStore: InMemoryQuickCreationModeStore(),
        connectionFactory: openInMemoryLocalDatabase,
        diagnosticsSink: InMemoryDiagnosticsSink(),
        repositoryFactory: (_) => repository,
      );
      addTearDown(() async {
        await runtime.shutdown();
        await repository.close();
      });

      await tester.pumpWidget(MainApp(runtime: runtime));
      await openIntentionGraph(
        tester,
        waitFor: (tester, finder) =>
            _pumpUntil(tester, () => finder.evaluate().isNotEmpty),
      );
      await _pumpUntil(tester, () => repository.pageQueries.isNotEmpty);
      repository.completePage(
        0,
        IntentionCatalogFirstPage(
          items: const [],
          totalCount: 0,
          nextCursor: null,
          revision: const _Revision(0),
        ),
      );
      await tester.pumpAndSettle();

      await _openPanel(tester);
      await tester.enterText(
        find.byKey(const ValueKey('intention-editor-title')),
        '  Быть здоровым  ',
      );
      await tester.enterText(
        find.byKey(const ValueKey('intention-editor-description')),
        '  Пользовательское описание\n',
      );
      await tester.tap(find.byKey(const ValueKey('intention-editor-submit')));
      await tester.pump();
      expect(repository.commands.single, isA<CreateIntention>());
      expect(find.text('Saving…'), findsOneWidget);

      // Уход во время принятой отправки подтверждается и её не отменяет.
      await tester.tap(find.byKey(const ValueKey('intention-editor-close')));
      await tester.pumpAndSettle();
      expect(find.text('Close the form?'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('intention-editor-close-discard')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('intention-editor-title')),
        findsNothing,
      );
      final created = _intention(
        title: 'Быть здоровым',
        description: '  Пользовательское описание\n',
      );
      repository.completeCommand(0, _saved(created, revision: 1));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(
        find.text('Create — “Быть здоровым”: Intention created.'),
        findsOneWidget,
      );
      expect(find.text(created.title), findsOneWidget);
      expect(find.text('Total intentions: 1'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(
        find.text('Create — “Быть здоровым”: Intention created.'),
        findsNothing,
      );

      await tester.tap(find.text(created.title));
      await _pumpUntil(tester, () => repository.detailRequests.length == 2);
      repository.emitDetail(0, created);
      await tester.pumpAndSettle();
      expect(find.text(created.description!), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const ValueKey('intention-details-edit')),
      );
      await tester.tap(find.byKey(const ValueKey('intention-details-edit')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('intention-details-edit-title')),
        'Укреплять здоровье',
      );
      await tester.enterText(
        find.byKey(const ValueKey('intention-details-edit-description')),
        'Новое описание',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('intention-details-edit-submit')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('intention-details-edit-submit')),
      );
      await tester.pump();
      final updated = _copyIntention(
        created,
        title: 'Укреплять здоровье',
        description: 'Новое описание',
        updatedDay: 2,
      );
      repository.completeCommand(
        1,
        _saved(updated, before: created, revision: 2),
      );
      await _pumpUntil(tester, () => repository.detailRequests.length == 3);

      repository.emitDetail(0, created);
      await tester.pump();
      await _scrollCurrentPageToTop(tester);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('intention-details-title')))
            .data,
        created.title,
      );
      expect(find.text(updated.title), findsNothing);
      repository.emitDetail(2, updated);
      await tester.pumpAndSettle();
      expect(
        find.text('Edit — “Укреплять здоровье”: Changes saved.'),
        findsOneWidget,
      );
      await _closeOperationMessage(tester);

      final enableReadiness = find.byKey(
        const ValueKey('intention-details-enable-readiness'),
      );
      await Scrollable.ensureVisible(
        tester.element(enableReadiness),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(enableReadiness);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Mark as ready'));
      await tester.pump();
      final ready = _copyIntention(
        updated,
        readiness: IntentionReadiness.ready,
        updatedDay: 3,
      );
      repository.completeCommand(
        2,
        _saved(ready, before: updated, revision: 3),
      );
      await _pumpUntil(tester, () => repository.detailRequests.length == 4);
      repository.emitDetail(3, ready);
      await tester.pumpAndSettle();
      await _scrollCurrentPageToTop(tester);
      expect(find.text('Ready for action'), findsOneWidget);
      await _closeOperationMessage(tester);

      await tester.ensureVisible(
        find.byKey(const ValueKey('intention-details-archive')),
      );
      await tester.tap(find.byKey(const ValueKey('intention-details-archive')));
      await tester.pump();
      final archived = _copyIntention(
        ready,
        archiveState: IntentionArchiveState.archived,
        updatedDay: 4,
      );
      repository.completeCommand(
        3,
        _saved(archived, before: ready, revision: 4),
      );
      await _pumpUntil(tester, () => repository.detailRequests.length == 5);
      repository.emitDetail(4, archived);
      await tester.pumpAndSettle();
      await _scrollCurrentPageToTop(tester);
      expect(find.text('Archived'), findsOneWidget);
      await _closeOperationMessage(tester);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('No active intentions yet.'), findsOneWidget);
      await _selectScope(tester, 'Archived');
      await _pumpUntil(tester, () => repository.pageQueries.length == 2);
      repository.completePage(
        1,
        IntentionCatalogFirstPage(
          items: [_summary(archived)],
          totalCount: 1,
          nextCursor: null,
          revision: const _Revision(4),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(archived.title), findsOneWidget);

      await tester.tap(find.text(archived.title));
      await _pumpUntil(tester, () => repository.detailRequests.length == 7);
      repository.emitDetail(4, archived);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('intention-details-restore')),
      );
      await tester.tap(find.byKey(const ValueKey('intention-details-restore')));
      await tester.pump();
      final restored = _copyIntention(
        archived,
        archiveState: IntentionArchiveState.active,
        updatedDay: 5,
      );
      repository.completeCommand(
        4,
        _saved(restored, before: archived, revision: 5),
      );
      await _pumpUntil(tester, () => repository.detailRequests.length == 8);
      repository.emitDetail(5, restored);
      await tester.pumpAndSettle();
      await _scrollCurrentPageToTop(tester);
      expect(find.text('Active'), findsOneWidget);
      await _closeOperationMessage(tester);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('No archived intentions yet.'), findsOneWidget);
      await _selectScope(tester, 'Active');
      await _pumpUntil(tester, () => repository.pageQueries.length == 3);
      repository.completePage(
        2,
        IntentionCatalogFirstPage(
          items: [_summary(restored)],
          totalCount: 1,
          nextCursor: null,
          revision: const _Revision(5),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(restored.title));
      await _pumpUntil(tester, () => repository.detailRequests.length == 10);
      repository.emitDetail(6, restored);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('intention-details-delete')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('intention-details-delete')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('intention-details-confirm-delete')),
      );
      await tester.pump();
      expect(repository.commands.last, isA<DeleteIntention>());

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(catalog_page.IntentionCatalogPage), findsOneWidget);
      repository.completeCommand(5, _deleted(restored, revision: 6));
      await tester.pumpAndSettle();

      expect(
        find.text('Delete — “Укреплять здоровье”: Intention deleted.'),
        findsOneWidget,
      );
      expect(find.text(restored.title), findsNothing);
      expect(find.text('No active intentions yet.'), findsOneWidget);
    },
  );

  group('общие сообщения и завершение отправки модальной панели', () {
    testWidgets('отказ чтения созданного намерения повторяет только чтение '
        'того же идентификатора без новых команд и сообщений', (tester) async {
      final repository = _DelayedPersonalGraphRepository();
      final runtime = await _pumpCatalog(tester, repository, const []);
      final completions = _collectCompletions(runtime);
      await _openPanel(tester);
      final router = tester.element(find.byType(IntentionEditorPage)).router;
      await tester.enterText(find.byKey(_editorTitle), 'Сохранённое намерение');
      await tester.tap(find.byKey(_submit));
      await _pumpUntil(tester, () => repository.commands.length == 1);

      final created = _intention(
        title: 'Сохранённое намерение',
        description: null,
      );
      repository.completeCommand(0, _saved(created, revision: 1));
      await _pumpUntil(tester, () => repository.detailIds.contains(created.id));
      expect(router.current.name, IntentionDetailsRoute.name);
      expect(
        router.current.argsAs<IntentionDetailsRouteArgs>().intentionId,
        created.id,
      );
      final completion = completions.single;
      final saved = switch (completion.result) {
        ResultSuccess(value: IntentionSaved(:final intention)) => intention,
        final result => fail('Создание не подтверждено: $result'),
      };
      expect(saved.id, created.id);

      for (var attempt = 0; attempt < 2; attempt++) {
        for (final request in repository.detailRequests) {
          request.add(const ResultFailure(IntentionUnavailableFailure()));
        }
        await tester.pumpAndSettle();
        expect(
          _visible('The intention couldn’t be loaded. Try again.'),
          findsOneWidget,
        );
        expect(find.byType(IntentionEditorPage), findsNothing);
        expect(router.current.name, IntentionDetailsRoute.name);
        if (attempt == 0) {
          expect(
            _visible('Create — “Сохранённое намерение”: Intention created.'),
            findsOneWidget,
          );
          await _closeOperationMessage(tester);
        }
        final previousReads = repository.detailRequests.length;
        await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
        await _pumpUntil(
          tester,
          () => repository.detailRequests.length == previousReads + 1,
        );
        expect(repository.detailIds.last, created.id);
        repository.emitDetail(1, created);
        await tester.pumpAndSettle();
        expect(find.text(created.title), findsOneWidget);
        expect(router.current.name, IntentionDetailsRoute.name);
        expect(find.byType(SnackBar, skipOffstage: false), findsNothing);
      }
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(repository.commands, hasLength(1));
      expect(find.byType(SnackBar, skipOffstage: false), findsNothing);
      await returnToIntentionGraphAfterCreation(tester, router);
      expect(find.text('Total intentions: 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final transition in _SheetTransition.values) {
      testWidgets(
        '${transition.description} не дублирует и не перезапускает текущее '
        'сообщение, а следующий исход ждёт его закрытия',
        (tester) async {
          final repository = _DelayedPersonalGraphRepository();
          final runtime = await _pumpCatalog(tester, repository, const []);
          await transition.prepare(tester);
          final first = await _failOtherIntentionDelete(
            tester,
            runtime,
            repository,
            uuid: '018f0000-0000-7000-8000-000000000011',
            title: 'Первое',
          );
          await tester.pumpAndSettle();
          expect(_visible(first), findsOneWidget);
          final second = await _failOtherIntentionDelete(
            tester,
            runtime,
            repository,
            uuid: '018f0000-0000-7000-8000-000000000012',
            title: 'Второе',
          );
          await tester.pumpAndSettle();
          expect(_anywhere(second), findsNothing);

          await transition.cover(tester);
          expect(_anywhere(first), findsWidgets);
          expect(_visible(first).evaluate().length, lessThanOrEqualTo(1));
          expect(_anywhere(second), findsNothing);
          await transition.uncover(tester);
          expect(_visible(first), findsOneWidget);
          expect(_anywhere(second), findsNothing);

          await _closeOperationMessage(tester);
          expect(_anywhere(first), findsNothing);
          expect(_visible(second), findsOneWidget);
          await _closeOperationMessage(tester);
          expect(find.byType(SnackBar, skipOffstage: false), findsNothing);
          await _closeOperationMessage(tester);
          expect(find.byType(SnackBar, skipOffstage: false), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }

    for (final overlay in _FormOverlay.values) {
      testWidgets('${overlay.description} не уводит отказ панели на общую '
          'поверхность: он предъявляется в панели после возвращения', (
        tester,
      ) async {
        final repository = _DelayedPersonalGraphRepository();
        await _pumpCatalog(tester, repository, const []);
        await _failSubmissionWithoutFocus(tester, repository);

        await overlay.cover(tester);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar, skipOffstage: false), findsNothing);
        await overlay.uncoverPartly(tester);
        expect(find.byType(SnackBar, skipOffstage: false), findsNothing);

        await overlay.uncover(tester);
        expect(find.byKey(_pinnedFailure).hitTestable(), findsOneWidget);
        await _closeOperationMessage(tester);
        expect(find.byType(SnackBar, skipOffstage: false), findsNothing);
        expect(_fieldText(tester), 'Намерение');
      });
    }
  });
}

const _editorTitle = ValueKey('intention-editor-title');
const _submit = ValueKey('intention-editor-submit');
const _close = ValueKey('intention-editor-close');
const _chooseTags = ValueKey('intention-editor-choose-tags');
const _pinnedFailure = ValueKey('intention-editor-failure');

/// Закреплённое сообщение панели о её отказе сохранения.
const _inlineCreationFailure = 'The intention couldn’t be created. Try again.';

/// Копии текста, доступные человеку: копия под модальным фоном или
/// непрозрачной страницей нажатий не получает.
Finder _visible(String text) => find.text(text).hitTestable();

/// Все построенные копии текста, в том числе под непрозрачной страницей.
Finder _anywhere(String text) => find.text(text, skipOffstage: false);

String? _fieldText(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(_editorTitle)).controller?.text;

Future<void> _openPanel(WidgetTester tester) async {
  await openQuickCreation(
    tester,
    QuickCreationMode.intention,
    openedPage: find.byType(IntentionEditorPage),
    wait: (tester, finder) =>
        _pumpUntil(tester, () => finder.evaluate().isNotEmpty),
  );
}

List<IntentionCommandCompletion> _collectCompletions(AppRuntime runtime) {
  final completions = <IntentionCommandCompletion>[];
  final subscription = runtime.commandCoordinator.intentionCompletions.listen(
    completions.add,
  );
  addTearDown(subscription.cancel);
  return completions;
}

/// Принимает удаление другого намерения без живого инициатора и завершает его
/// отказом: результат принадлежит только общей поверхности. Возвращает текст
/// её сообщения.
Future<String> _failOtherIntentionDelete(
  WidgetTester tester,
  AppRuntime runtime,
  _DelayedPersonalGraphRepository repository, {
  required String uuid,
  required String title,
}) async {
  final other = _intention(uuid: uuid, title: title, description: null);
  final index = repository.commands.length;
  final accepted = runtime.commandCoordinator.acceptExisting(
    DeleteIntention(other.id),
    presentationTitle: other.title,
  ) as IntentionCommandAccepted;
  runtime.commandCoordinator.releaseInitiatorPresentation(accepted.token);
  await _pumpUntil(tester, () => repository.commands.length == index + 1);
  repository.completeCommand(
    index,
    const ResultFailure(IntentionUnavailableFailure()),
  );
  return 'Delete — “$title”: The intention couldn’t be deleted. Try again.';
}

/// Отправляет черновик панели и получает отказ, пока приложение без фокуса:
/// renderer панели получает право ошибки, но ещё не предъявил её.
Future<void> _failSubmissionWithoutFocus(
  WidgetTester tester,
  _DelayedPersonalGraphRepository repository,
) async {
  await _openPanel(tester);
  await tester.enterText(find.byKey(_editorTitle), 'Намерение');
  await tester.tap(find.byKey(_submit));
  await _pumpUntil(tester, () => repository.commands.length == 1);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  repository.completeCommand(
    0,
    const ResultFailure(IntentionUnavailableFailure()),
  );
  await tester.pumpAndSettle();
  expect(find.text(_inlineCreationFailure), findsOneWidget);
}

/// Переход, во время которого общая поверхность уже показывает сообщение.
enum _SheetTransition {
  panel('открытие и закрытие панели'),
  confirmation('подтверждение закрытия над панелью'),
  chooser('выбор тегов над панелью'),
  editor('редактор тега над выбором');

  const _SheetTransition(this.description);

  final String description;

  /// Состояние до сообщения: каталог или открытая панель с черновиком.
  Future<void> prepare(WidgetTester tester) async {
    switch (this) {
      case _SheetTransition.panel:
        return;
      case _SheetTransition.confirmation ||
          _SheetTransition.chooser ||
          _SheetTransition.editor:
        await _openPanel(tester);
        await tester.enterText(find.byKey(_editorTitle), 'Черновик');
        await tester.pump();
        switch (this) {
          case _SheetTransition.editor:
            await _FormOverlay.chooser.cover(tester);
          case _SheetTransition.panel ||
              _SheetTransition.confirmation ||
              _SheetTransition.chooser:
            break;
        }
    }
  }

  Future<void> cover(WidgetTester tester) async {
    switch (this) {
      case _SheetTransition.panel:
        await _openPanel(tester);
      case _SheetTransition.confirmation:
        await tester.tap(find.byKey(_close));
        await tester.pumpAndSettle();
        expect(find.text('Discard the draft?'), findsOneWidget);
      case _SheetTransition.chooser:
        // Сообщение временно перекрывает нижний край полей. Из названия
        // переходим через описание к выбору тегов клавиатурой, сохраняя
        // сообщение на экране и его место в очереди.
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.byType(BackButton), findsOneWidget);
      case _SheetTransition.editor:
        await tester.tap(find.byKey(const ValueKey('tag-catalog-create')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('tag-editor-name')), findsOneWidget);
    }
  }

  Future<void> uncover(WidgetTester tester) async {
    switch (this) {
      case _SheetTransition.panel:
        await tester.tap(find.byKey(_close));
        await tester.pumpAndSettle();
        expect(find.byType(IntentionEditorPage), findsNothing);
      case _SheetTransition.confirmation:
        await tester.tap(
          find.byKey(const ValueKey('intention-editor-close-continue')),
        );
        await tester.pumpAndSettle();
        expect(_fieldText(tester), 'Черновик');
      case _SheetTransition.chooser:
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(_fieldText(tester), 'Черновик');
      case _SheetTransition.editor:
        await tester.tap(find.byKey(const ValueKey('tag-editor-cancel')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('tag-editor-name')), findsNothing);
    }
  }
}

/// Временное перекрытие живой панели.
enum _FormOverlay {
  chooser('непрозрачный выбор тегов'),
  editor('непрозрачный редактор тега над выбором'),
  dialog('диалог объяснения готовности');

  const _FormOverlay(this.description);

  final String description;

  Future<void> cover(WidgetTester tester) async {
    switch (this) {
      case _FormOverlay.chooser:
        await tester.tap(find.byKey(_chooseTags));
        await tester.pumpAndSettle();
        expect(find.byType(BackButton), findsOneWidget);
      case _FormOverlay.editor:
        await _FormOverlay.chooser.cover(tester);
        await tester.tap(find.byKey(const ValueKey('tag-catalog-create')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('tag-editor-name')), findsOneWidget);
      case _FormOverlay.dialog:
        await tester.tap(
          find.byKey(const ValueKey('intention-editor-readiness')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('intention-editor-readiness-confirmation')),
          findsOneWidget,
        );
    }
  }

  /// Снимает верхнюю из нескольких перекрывающих страниц, оставляя панель
  /// перекрытой.
  Future<void> uncoverPartly(WidgetTester tester) async {
    switch (this) {
      case _FormOverlay.chooser || _FormOverlay.dialog:
        return;
      case _FormOverlay.editor:
        await tester.tap(find.byKey(const ValueKey('tag-editor-cancel')));
        await tester.pumpAndSettle();
        expect(find.byType(BackButton), findsOneWidget);
    }
  }

  Future<void> uncover(WidgetTester tester) async {
    switch (this) {
      case _FormOverlay.chooser || _FormOverlay.editor:
        await tester.tap(find.byType(BackButton));
      case _FormOverlay.dialog:
        await tester.tap(
          find.byKey(const ValueKey('intention-editor-readiness-cancel')),
        );
    }
    await tester.pumpAndSettle();
    expect(find.byType(IntentionEditorPage), findsOneWidget);
  }
}

Future<void> _closeOperationMessage(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

Future<void> _selectScope(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const ValueKey('catalog-scope-control')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pump();
}

Future<void> _goBack(WidgetTester tester) async {
  await tester.tap(find.byType(BackButton));
  await tester.pumpAndSettle();
}

Future<void> _scrollCurrentPageToTop(WidgetTester tester) async {
  final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
  scrollable.position.jumpTo(scrollable.position.minScrollExtent);
  await tester.pump();
}

Future<AppRuntime> _pumpCatalog(
  WidgetTester tester,
  _DelayedPersonalGraphRepository repository,
  List<Intention> intentions,
) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  final runtime = AppRuntime(
    quickCreationModeStore: InMemoryQuickCreationModeStore(),
    connectionFactory: openInMemoryLocalDatabase,
    diagnosticsSink: InMemoryDiagnosticsSink(),
    repositoryFactory: (_) => repository,
  );
  addTearDown(() async {
    await runtime.shutdown();
    await repository.close();
  });

  await tester.pumpWidget(MainApp(runtime: runtime));
  await openIntentionGraph(
    tester,
    waitFor: (tester, finder) =>
        _pumpUntil(tester, () => finder.evaluate().isNotEmpty),
  );
  await _pumpUntil(tester, () => repository.pageQueries.isNotEmpty);
  repository.completePage(
    0,
    IntentionCatalogFirstPage(
      items: intentions.map(_summary).toList(growable: false),
      totalCount: intentions.length,
      nextCursor: null,
      revision: const _Revision(0),
    ),
  );
  await tester.pumpAndSettle();
  return runtime;
}

Future<void> _openDetails(
  WidgetTester tester,
  _DelayedPersonalGraphRepository repository,
  Intention intention, {
  required int requestIndex,
}) async {
  await tester.tap(find.text(intention.title));
  await _pumpUntil(
    tester,
    () => repository.detailIds.where((id) => id == intention.id).length >= 2,
  );
  repository.emitDetail(requestIndex, intention);
  await tester.pumpAndSettle();
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 1000; attempt += 1) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 1));
  }
  fail('Условие app-level теста не выполнено.');
}

final class _DelayedPersonalGraphRepository
    with
        TagReadContractTestFallback,
        FavoriteReadContractTestFallback,
        CatalogReconciliationTestFallback
    implements PersonalGraphRepository {
  @override
  Future<ChoicePathSuggestionsResult> getChoicePathSuggestions(
    ChoicePathSuggestionsQuery query,
  ) => throw UnimplementedError();

  @override
  Future<ChoicePathContinuationResult> getChoicePathContinuations(
    ChoicePathContinuationQuery query,
  ) => throw UnimplementedError();

  @override
  Future<DailyChoiceReadResult> getDailyChoice(DailyChoiceId id) =>
      throw UnsupportedError(
        'Чтение дневного выбора не используется этим тестом.',
      );

  @override
  Stream<DailyChoiceReadResult> watchDailyChoice(DailyChoiceId id) =>
      throw UnsupportedError(
        'Наблюдение дневного выбора не используется этим тестом.',
      );

  @override
  Future<SelectedRelationsReadResult> getSelectedRelations(
    SelectedRelationsQuery query,
  ) async => _selectedSnapshot(query);

  @override
  Stream<SelectedRelationsReadResult> watchSelectedRelations(
    SelectedRelationsQuery query,
  ) => Stream.value(_selectedSnapshot(query));

  SelectedRelationsReadResult _selectedSnapshot(
    SelectedRelationsQuery query,
  ) => SelectedRelationsReadSuccess(
    GraphSnapshot(
      revision: _Revision(_revisions[query.intentionId] ?? 0),
      value: SelectedRelationsSnapshot(
        query: query,
        entries: {
          for (final id in query.relationIds)
            id: relation == null || relation!.relation.id != id
                ? SelectedRelationMissing(id)
                : relation!.relation.sourceIntentionId != query.intentionId &&
                      relation!.relation.relatedIntentionId != query.intentionId
                ? SelectedRelationNoLongerBlocking(id)
                : SelectedRelationPresent(
                    LongTermRelationDetails(
                      relation: relation!.relation,
                      source: relation!.source,
                      related: relation!.related,
                      description: null,
                    ),
                  ),
        },
      ),
    ),
  );

  _DelayedPersonalGraphRepository({this.relation});

  final LongTermRelationSummary? relation;

  RelationCounts _countsFor(IntentionId id) => RelationCounts(
    activeNeedIncoming: relation?.relation.relatedIntentionId == id ? 1 : 0,
    activeNeedOutgoing: relation?.relation.sourceIntentionId == id ? 1 : 0,
    activeCanIncoming: 0,
    activeCanOutgoing: 0,
    archivedNeedIncoming: 0,
    archivedNeedOutgoing: 0,
    archivedCanIncoming: 0,
    archivedCanOutgoing: 0,
  );
  final pageQueries = <IntentionCatalogQuery>[];
  final detailIds = <IntentionId>[];
  final detailRequests =
      <StreamController<Result<GraphSnapshot<IntentionDetails?>>>>[];
  final commands = <IntentionCommand>[];
  final blockingRelationsCommands = <DeleteBlockingRelations>[];
  final _pages = <Completer<Result<IntentionCatalogPage>>>[];
  final _commands =
      <Completer<Result<ConfirmedGraphResult<IntentionCommandSuccess>>>>[];
  final _blockingRelationsRequests =
      <Completer<DeleteBlockingRelationsResult>>[];
  final _revisions = <IntentionId, int>{};

  @override
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  ) {
    pageQueries.add(query);
    final request = Completer<Result<IntentionCatalogPage>>();
    _pages.add(request);
    return request.future;
  }

  @override
  Future<Result<GraphSnapshot<RelationCounts>>> getRelationCounts(
    IntentionId intentionId,
  ) => Future.value(
    ResultSuccess(
      GraphSnapshot(
        value: _countsFor(intentionId),
        revision: _Revision(_revisions[intentionId] ?? 0),
      ),
    ),
  );

  @override
  Future<DailyChoiceCatalogPageResult> getDailyChoiceCatalogPage(
    DailyChoiceCatalogQuery query,
  ) => throw UnsupportedError(
    'Каталог дневных выборов не используется в этом тесте.',
  );

  @override
  Future<RelationGroupPageResult> getRelationGroupPage(
    RelationGroupPageQuery query,
  ) => Future.value(
    GraphResultSuccess(
      RelationGroupFirstPage(
        items:
            relation != null &&
                query.intentionId == relation!.relation.sourceIntentionId &&
                query.group ==
                    const LongTermRelationGroup(
                      scope: RelationScope.active,
                      type: LongTermRelationType.need,
                      direction: RelationDirection.outgoing,
                    )
            ? [relation!]
            : const [],
        counts: _countsFor(query.intentionId),
        nextCursor: null,
        revision: _Revision(_revisions[query.intentionId] ?? 0),
      ),
    ),
  );

  @override
  Stream<LongTermRelationReadResult> watchRelation(LongTermRelationId id) =>
      Stream.value(
        GraphResultSuccess(
          GraphSnapshot(
            value: relation == null || relation!.relation.id != id
                ? null
                : LongTermRelationDetails(
                    relation: relation!.relation,
                    source: relation!.source,
                    related: relation!.related,
                    description: null,
                  ),
            revision: const _Revision(0),
          ),
        ),
      );

  @override
  Stream<Result<GraphSnapshot<IntentionDetails?>>> watchIntention(
    IntentionId id,
  ) {
    final request =
        StreamController<Result<GraphSnapshot<IntentionDetails?>>>();
    detailIds.add(id);
    detailRequests.add(request);
    return request.stream;
  }

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    if (command is DeleteBlockingRelations) {
      blockingRelationsCommands.add(command as DeleteBlockingRelations);
      final request = Completer<DeleteBlockingRelationsResult>();
      _blockingRelationsRequests.add(request);
      return await request.future as GraphCommandResult<TSuccess, TFailure>;
    }
    if (command is! IntentionCommand) {
      throw UnsupportedError('Команды связей не используются в этих тестах.');
    }
    return await _executeIntention(command as IntentionCommand)
        as GraphCommandResult<TSuccess, TFailure>;
  }

  Future<Result<ConfirmedGraphResult<IntentionCommandSuccess>>>
  _executeIntention(IntentionCommand command) {
    commands.add(command);
    final request =
        Completer<Result<ConfirmedGraphResult<IntentionCommandSuccess>>>();
    _commands.add(request);
    return request.future;
  }

  void completePage(int index, IntentionCatalogPage page) {
    _pages[index].complete(ResultSuccess(page));
  }

  void emitDetail(int index, Intention intention) {
    _revisions[intention.id] = index;
    for (
      var requestIndex = 0;
      requestIndex < detailRequests.length;
      requestIndex += 1
    ) {
      if (detailIds[requestIndex] == intention.id) {
        detailRequests[requestIndex].add(
          ResultSuccess(
            GraphSnapshot(
              value: IntentionDetails(
                intention: intention,
                relationCounts: _countsFor(intention.id),
                favoriteMark: FavoriteMark.notFavorite,
              ),
              revision: _Revision(index),
            ),
          ),
        );
      }
    }
  }

  void completeCommand(
    int index,
    Result<ConfirmedGraphResult<IntentionCommandSuccess>> result,
  ) {
    _commands[index].complete(result);
  }

  void completeBlockingRelationsCommand(
    int index,
    DeleteBlockingRelationsResult result,
  ) => _blockingRelationsRequests[index].complete(result);

  Future<void> close() async {
    for (final request in detailRequests) {
      if (!request.isClosed) await request.close();
    }
  }
}

Intention _intention({
  String uuid = '018f0000-0000-7000-8000-000000000001',
  required String title,
  required String? description,
}) {
  final id = switch (IntentionId.decode(uuid)) {
    IntentionIdDecodingSuccess(:final id) => id,
    InvalidIntentionIdDecoding() => throw StateError(
      'Некорректный fixture ID.',
    ),
  };
  final timestamp = IntentionTimestamp(DateTime.utc(2026, 1));
  return Intention(
    id: id,
    title: title,
    description: description,
    readiness: IntentionReadiness.notReady,
    archiveState: IntentionArchiveState.active,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

Intention _copyIntention(
  Intention source, {
  String? title,
  String? description,
  IntentionReadiness? readiness,
  IntentionArchiveState? archiveState,
  required int updatedDay,
}) => Intention(
  id: source.id,
  title: title ?? source.title,
  description: description ?? source.description,
  readiness: readiness ?? source.readiness,
  archiveState: archiveState ?? source.archiveState,
  createdAt: source.createdAt,
  updatedAt: IntentionTimestamp(DateTime.utc(2026, 1, updatedDay)),
);

IntentionSummary _summary(Intention intention) => IntentionSummary(
  id: intention.id,
  title: intention.title,
  hasDescription: intention.description != null,
  readiness: intention.readiness,
  archiveState: intention.archiveState,
  activeRelationCount: 0,
  createdAt: intention.createdAt,
  updatedAt: intention.updatedAt,
  favoriteMark: FavoriteMark.notFavorite,
);

final _relationId = switch (LongTermRelationId.decode(
  '018f0000-0000-7000-8000-000000000003',
)) {
  LongTermRelationIdDecodingSuccess(:final id) => id,
  InvalidLongTermRelationIdDecoding() => throw StateError(
    'Некорректный fixture связи.',
  ),
};

LongTermRelationSummary _relationSummary(Intention source, Intention related) =>
    LongTermRelationSummary(
      relation: LongTermRelation(
        id: _relationId,
        sourceIntentionId: source.id,
        relatedIntentionId: related.id,
        type: LongTermRelationType.need,
        priority: RelationPriority.p2,
        scope: RelationScope.active,
        creationSequence: RelationCreationSequence(1),
      ),
      source: RelationParticipantSummary(
        id: source.id,
        title: source.title,
        archiveState: source.archiveState,
        activeRelationCount: 1,
      ),
      related: RelationParticipantSummary(
        id: related.id,
        title: related.title,
        archiveState: related.archiveState,
        activeRelationCount: 1,
      ),
      hasDescription: false,
    );

Result<ConfirmedGraphResult<IntentionCommandSuccess>> _saved(
  Intention intention, {
  Intention? before,
  required int revision,
}) {
  final after = _Snapshot(intention);
  final mutation = before == null
      ? IntentionCatalogCreated(revision: _Revision(revision), entry: after)
      : IntentionCatalogUpdated(
          revision: _Revision(revision),
          before: _Snapshot(before),
          after: after,
        );
  final value = IntentionSaved(intention, catalogMutation: mutation);
  return ResultSuccess(
    ConfirmedGraphResult(revision: _Revision(revision), value: value),
  );
}

Result<ConfirmedGraphResult<IntentionCommandSuccess>> _deleted(
  Intention intention, {
  required int revision,
}) {
  final value = IntentionDeleted(
    intention.id,
    catalogMutation: IntentionCatalogDeleted(
      revision: _Revision(revision),
      entry: _Snapshot(intention),
    ),
  );
  return ResultSuccess(
    ConfirmedGraphResult(revision: _Revision(revision), value: value),
  );
}

final class _Snapshot implements IntentionCatalogEntrySnapshot {
  _Snapshot(Intention intention) : summary = _summary(intention);

  @override
  final IntentionSummary summary;

  @override
  bool matches(IntentionCatalogQuery query) => query.includes(summary);
}

final class _Revision implements GraphRevision {
  const _Revision(this.sequence);

  final int sequence;

  @override
  GraphRevisionOrder compareTo(GraphRevision other) {
    if (other is! _Revision) {
      return GraphRevisionOrder.differentEpoch;
    }
    final comparison = sequence.compareTo(other.sequence);
    if (comparison < 0) return GraphRevisionOrder.older;
    if (comparison > 0) return GraphRevisionOrder.newer;
    return GraphRevisionOrder.same;
  }
}
