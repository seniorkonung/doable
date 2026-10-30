import 'dart:async';

import 'package:doable/src/daily_choice/application/daily_choice_day_statuses.dart';
import 'package:doable/src/daily_choice/application/daily_choice_catalog.dart';
import 'package:doable/src/daily_choice/application/choice_path_continuations.dart';

import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/design_system/components/option_tiles.dart';
import 'package:doable/src/design_system/components/sheet.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:auto_route/auto_route.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/data/local/app_database.dart'
    show openInMemoryLocalDatabase;
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart'
    as catalog_page;
import 'package:doable/src/intention/presentation/details/intention_options.dart';
import 'package:doable/src/intention/presentation/edit/intention_edit_page.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_page.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/design_system/components/page_head.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_root_pages.dart';
import '../support/intention_catalog_controls.dart';
import '../support/intention_type_counts.dart';
import '../support/in_memory_diagnostics_sink.dart';
import '../support/intention_options.dart';
import '../support/tag_read_contract_test_fallback.dart';
import '../support/statistics_read_contract_test_fallback.dart';
import '../support/in_memory_quick_creation_mode_store.dart';
import '../support/quick_creation.dart';
import '../support/intention_description_preview.dart';
import '../support/intention_edit_screen.dart';
import '../support/intention_title_order_key.dart';

void main() {
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
      expect(intentionCatalogTotal(1), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(
        find.text('Create — “Быть здоровым”: Intention created.'),
        findsNothing,
      );

      await tester.tap(find.text(created.title));
      await _pumpUntil(tester, () => repository.detailRequests.length == 1);
      repository.emitDetail(0, created);
      await tester.pumpAndSettle();
      expect(find.text(created.description!), findsOneWidget);

      await tester.tap(intentionHeadTitle);
      await tester.pumpAndSettle();
      await tester.enterText(intentionEditTitleField, 'Укреплять здоровье');
      await tester.enterText(intentionEditDescriptionField, 'Новое описание');
      await tester.pump();
      await tester.tap(intentionEditSave);
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
      await _pumpUntil(tester, () => repository.detailRequests.length == 2);
      // Успешное сохранение закрывает экран изменения без сообщения.
      await _pumpUntil(
        tester,
        () => find.byType(IntentionEditPage).evaluate().isEmpty,
      );

      repository.emitDetail(0, created);
      await tester.pump();
      await _scrollCurrentPageToTop(tester);
      expect(
        tester
            .widget<PageHead>(
              find.byKey(const ValueKey('intention-details-title')),
            )
            .name,
        created.title,
      );
      expect(find.text(updated.title), findsNothing);
      repository.emitDetail(2, updated);
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);

      final actionTile = find.descendant(
        of: find.byType(OptionTiles<IntentionReadiness>),
        matching: find.text('Action'),
      );
      await Scrollable.ensureVisible(
        tester.element(actionTile),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(actionTile);
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
      await _pumpUntil(tester, () => repository.detailRequests.length == 3);
      repository.emitDetail(3, ready);
      await tester.pumpAndSettle();
      await _scrollCurrentPageToTop(tester);
      expect(
        tester
            .widget<OptionTiles<IntentionReadiness>>(
              find.byType(OptionTiles<IntentionReadiness>),
            )
            .value,
        IntentionReadiness.ready,
      );
      await _closeOperationMessage(tester);

      await chooseIntentionOption(tester, IntentionOption.archive);
      final archived = _copyIntention(
        ready,
        archiveState: IntentionArchiveState.archived,
        updatedDay: 4,
      );
      repository.completeCommand(
        3,
        _saved(archived, before: ready, revision: 4),
      );
      await _pumpUntil(tester, () => repository.detailRequests.length == 4);
      repository.emitDetail(4, archived);
      await tester.pumpAndSettle();
      await _scrollCurrentPageToTop(tester);
      expect(find.text('Archived'), findsOneWidget);
      await _closeOperationMessage(tester);

      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
      expect(find.text('No active intentions'), findsOneWidget);
      await selectIntentionCatalogScope(tester, IntentionScope.archived);
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
      await _pumpUntil(tester, () => repository.detailRequests.length == 5);
      repository.emitDetail(4, archived);
      await tester.pumpAndSettle();
      await tester.tap(intentionHeadRestore);
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
      await _pumpUntil(tester, () => repository.detailRequests.length == 6);
      repository.emitDetail(5, restored);
      await tester.pumpAndSettle();
      await _scrollCurrentPageToTop(tester);
      expect(find.text('Archived'), findsNothing);
      await _closeOperationMessage(tester);

      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Nothing in the archive'), findsOneWidget);
      await selectIntentionCatalogScope(tester, IntentionScope.active);
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
      await _pumpUntil(tester, () => repository.detailRequests.length == 7);
      repository.emitDetail(6, restored);
      await tester.pumpAndSettle();
      await tester.tap(intentionOptionsButton);
      await tester.pumpAndSettle();
      await tester.tap(intentionOption(IntentionOption.delete));
      await tester.pumpAndSettle();
      await tester.tap(intentionDeletionConfirm);
      await tester.pump();
      expect(repository.commands.last, isA<DeleteIntention>());

      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(catalog_page.IntentionCatalogPage), findsOneWidget);
      repository.completeCommand(5, _deleted(restored, revision: 6));
      await tester.pumpAndSettle();

      expect(
        find.text('Delete — “Укреплять здоровье”: Intention deleted.'),
        findsOneWidget,
      );
      expect(find.text(restored.title), findsNothing);
      expect(find.text('No intentions yet'), findsOneWidget);
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
      expect(intentionCatalogTotal(1), findsOneWidget);
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
  chooser('панель тегов над панелью создания'),
  editor('лист тега над панелью тегов');

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
        expect(_tagsPanel, findsOneWidget);
      case _SheetTransition.editor:
        await _openNewTagSheet(tester);
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
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(_tagsPanel, findsNothing);
        expect(_fieldText(tester), 'Черновик');
      case _SheetTransition.editor:
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(_newTagSheet, findsNothing);
        expect(_tagsPanel, findsOneWidget);
    }
  }
}

/// Временное перекрытие живой панели.
enum _FormOverlay {
  chooser('панель тегов'),
  editor('лист тега над панелью тегов'),
  dialog('диалог объяснения готовности');

  const _FormOverlay(this.description);

  final String description;

  Future<void> cover(WidgetTester tester) async {
    switch (this) {
      case _FormOverlay.chooser:
        await tester.tap(find.byKey(_chooseTags));
        await tester.pumpAndSettle();
        expect(_tagsPanel, findsOneWidget);
      case _FormOverlay.editor:
        await _FormOverlay.chooser.cover(tester);
        await _openNewTagSheet(tester);
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

  /// Снимает верхнее из нескольких перекрытий, оставляя панель перекрытой.
  Future<void> uncoverPartly(WidgetTester tester) async {
    switch (this) {
      case _FormOverlay.chooser || _FormOverlay.dialog:
        return;
      case _FormOverlay.editor:
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(_newTagSheet, findsNothing);
        expect(_tagsPanel, findsOneWidget);
    }
  }

  Future<void> uncover(WidgetTester tester) async {
    switch (this) {
      case _FormOverlay.chooser || _FormOverlay.editor:
        await tester.tap(find.text('Done'));
      case _FormOverlay.dialog:
        await tester.tap(
          find.byKey(const ValueKey('intention-editor-readiness-cancel')),
        );
    }
    await tester.pumpAndSettle();
    expect(find.byType(IntentionEditorPage), findsOneWidget);
  }
}

/// Панель тегов над панелью создания и лист «Новый тег» над ней.
final _tagsPanel = find.widgetWithText(Sheet, 'Tags');
final _newTagSheet = find.widgetWithText(Sheet, 'New tag');

/// Открывает лист «Новый тег» строкой создания открытой панели тегов.
Future<void> _openNewTagSheet(WidgetTester tester) async {
  await tester.enterText(
    find.descendant(of: _tagsPanel, matching: find.byType(TextField)),
    'Новый',
  );
  await tester.pump();
  await tester.tap(find.text('Create tag “Новый”'));
  await tester.pumpAndSettle();
  expect(_newTagSheet, findsOneWidget);
}

Future<void> _closeOperationMessage(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

Future<void> _scrollCurrentPageToTop(WidgetTester tester) async {
  final scrollable = tester.state<ScrollableState>(
    find.byType(Scrollable).first,
  );
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

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 1000; attempt += 1) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 1));
  }
  fail('Условие app-level теста не выполнено.');
}

final class _DelayedPersonalGraphRepository
    with StatisticsReadContractTestFallback, TagReadContractTestFallback
    implements PersonalGraphRepository {
  /// Панель тегов над панелью создания показывает пустой каталог и строку
  /// создания по запросу.
  @override
  Future<TagCatalogResult> getTagCatalog(TagCatalogMode mode) async =>
      TagCatalogSuccess(
        TagCatalogSnapshot(items: const [], revision: const _Revision(0)),
      );

  @override
  Future<DailyChoiceDayStatusesReadResult> getDailyChoiceDayStatuses(
    DailyChoiceDayStatusQuery query,
  ) => throw UnsupportedError(
    'Чтение состояний дней не используется в этом тесте.',
  );

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

  RelationCounts _countsFor(IntentionId id) => RelationCounts(
    activeNeedIncoming: 0,
    activeNeedOutgoing: 0,
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
  final _pages = <Completer<Result<IntentionCatalogPage>>>[];
  final _commands =
      <Completer<Result<ConfirmedGraphResult<IntentionCommandSuccess>>>>[];
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
        items: const [],
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
          GraphSnapshot(value: null, revision: const _Revision(0)),
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
    _pages[index].complete(
      answerCatalogQuery(pageQueries[index], ResultSuccess(page)),
    );
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
  descriptionPreview: testDescriptionPreview(intention.description),
  readiness: intention.readiness,
  archiveState: intention.archiveState,
  createdAt: intention.createdAt,
  updatedAt: intention.updatedAt,
  titleOrderKey: testTitleOrderKey(intention.title),
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
