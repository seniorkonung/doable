import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/presentation/graph_operation_presenter.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/presentation/details/relation_details_page.dart';
import 'package:doable/src/long_term_relation/presentation/editor/relation_editor_page.dart';
import 'package:doable/src/long_term_relation/presentation/editor/relation_editor_state.dart';
import 'package:doable/src/shared/presentation/creation_exit_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../intention/presentation/catalog/catalog_test_support.dart';
import '../../../support/app_root_pages.dart';
import '../details/relation_details_test_support.dart';
import 'relation_form_test_support.dart';

import '../../../support/in_memory_quick_creation_mode_store.dart';

void main() {
  setUp(() {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  testWidgets('поздний выбор участника после выхода сохраняет новую форму', (
    tester,
  ) async {
    final app = await _launch(tester);
    await _openForm(tester, app, RelationDirection.outgoing);
    app.router.holdPickerResult = true;
    await tester.tap(_key('relation-editor-change-source'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    app.repository.completeCatalogPage(
      app.repository.catalogQueries.length - 1,
      [testSummary(index: 3, title: 'Поздний участник')],
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Поздний участник'));
    await tester.pumpAndSettle();
    expect(find.text('Участник 1'), findsOneWidget);
    tester.widget<CreationExitAction>(find.byType(CreationExitAction)).onExit();
    await tester.pumpAndSettle();
    await _openForm(tester, app, RelationDirection.outgoing);
    final matchId = app.router.stackData.last.matchId;
    app.router.releasePicker();
    await tester.pumpAndSettle();
    expect(app.router.stackData.last.matchId, matchId);
    expect(find.text('Участник 1'), findsOneWidget);
    expect(find.text('Поздний участник'), findsNothing);
    expect(app.repository.relationCommands, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'обычное закрытие поиска сохраняет прежний черновик и возможность отправки',
    (tester) async {
      final app = await _launch(tester);
      await _openForm(tester, app, RelationDirection.outgoing);
      await _fill(tester, app);
      await tester.enterText(
        _key('relation-editor-description'),
        'Прежний черновик',
      );
      final matchId = app.router.stackData.last.matchId;
      await tester.tap(_key('relation-editor-change-related'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(app.router.stackData.last.matchId, matchId);
      expect(_description(tester), 'Прежний черновик');
      expect(
        tester.widget<FilledButton>(_key('relation-editor-submit')).onPressed,
        isNotNull,
      );
      expect(find.text('Cancel creation'), findsOneWidget);
      expect(app.repository.relationCommands, isEmpty);
    },
  );

  testWidgets('выход доступен на телефоне с клавиатурой', (tester) async {
    final semantics = tester.ensureSemantics();
    final app = await _launch(tester, locale: const Locale('ru'));
    await _openForm(tester, app, null);
    await _fill(tester, app);
    await _tap(tester, 'relation-editor-submit');
    tester.view.physicalSize = const Size(400, 800);
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);

    await tester.pumpAndSettle();
    const label = 'Выйти из создания';
    final button = find.widgetWithText(TextButton, label);
    await tester.scrollUntilVisible(
      button,
      300,
      scrollable: find
          .descendant(
            of: find.byType(RelationEditorPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(button.hitTestable(), findsOneWidget);
    final node = tester
        .getSemantics(find.bySemanticsLabel(label))
        .getSemanticsData();
    expect(node.label, label);
    expect(node.hint, contains('продолжится'));
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byType(RelationDetailsPage), findsOneWidget);
    expect(app.repository.relationCommands, hasLength(1));
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('отмена входа до отправки сохраняет исходную историю', (
    tester,
  ) async {
    final app = await _launch(tester);
    final history = app.router.stackData.map((route) => route.matchId).toList();
    await _openForm(tester, app, null);
    await _fill(tester, app);
    final submit = tester
        .widget<FilledButton>(_key('relation-editor-submit'))
        .onPressed!;
    final exit = tester
        .widget<CreationExitAction>(find.byType(CreationExitAction))
        .onExit;
    expect(find.text('Cancel creation'), findsOneWidget);
    exit();
    submit();
    exit();
    await tester.pumpAndSettle();
    expect(app.router.stackData.map((route) => route.matchId), history);
    expect(app.repository.relationCommands, isEmpty);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_description(tester), 'Нижний черновик');
    expect(tester.takeException(), isNull);
  });

  testWidgets('отправка перед выходом и поздний успех сохраняют новую форму', (
    tester,
  ) async {
    final app = await _launch(tester);
    final history = app.router.stackData.map((route) => route.matchId).toList();
    await _openForm(tester, app, null);
    await _fill(tester, app);
    final submit = tester
        .widget<FilledButton>(_key('relation-editor-submit'))
        .onPressed!;
    final exit = tester
        .widget<CreationExitAction>(find.byType(CreationExitAction))
        .onExit;
    submit();
    exit();
    submit();
    await tester.pump();
    expect(app.repository.relationCommands, hasLength(1));
    expect(app.router.stackData.map((route) => route.matchId), history);
    await _openForm(tester, app, null);
    await tester.enterText(
      _key('relation-editor-description'),
      'Новый черновик',
    );
    final newMatch = app.router.stackData.last.matchId;
    app.repository.completeRelationCreated(0);
    exit();
    await tester.pumpAndSettle();
    expect(app.router.stackData.last.matchId, newMatch);
    expect(_description(tester), 'Новый черновик');
    expect(app.repository.relationCommands, hasLength(1));
    expect(find.textContaining('Relation created.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.textContaining('Relation created.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'выход при записи объясняет продолжение, после отказа доступна отмена',
    (tester) async {
      final app = await _launch(tester);
      await _openForm(tester, app, null);
      await _fill(tester, app);
      await _tap(tester, 'relation-editor-submit');
      expect(find.text('Leave creation'), findsOneWidget);
      expect(find.textContaining('Saving will continue'), findsOneWidget);
      app.repository.failRelationCommand(
        0,
        const LongTermRelationUnavailableFailure(),
      );
      await tester.pumpAndSettle();
      expect(find.text('Cancel creation'), findsOneWidget);
      await tester.tap(find.text('Cancel creation'));
      await tester.pumpAndSettle();
      expect(find.byType(RelationDetailsPage), findsOneWidget);
      expect(app.repository.relationCommands, hasLength(1));
    },
  );

  testWidgets(
    'вход открывает созданный ID и сохраняет глубокую историю с черновиком',
    (tester) async {
      final app = await _launch(tester);
      final history = app.router.stackData
          .map((route) => route.matchId)
          .toList();
      await _openForm(tester, app, null);
      await _fill(tester, app);
      await _tap(tester, 'relation-editor-submit');
      final created = app.repository.completeRelationCreated(0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(app.router.current.name, RelationDetailsRoute.name);
      app.repository.relationWatches.last.emitDetails(
        testRelationDetails(
          relationId: created.id,
          sourceId: created.sourceIntentionId,
          relatedId: created.relatedIntentionId,
        ),
        revision: const TestCatalogRevision(2),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<RelationDetailsPage>(find.byType(RelationDetailsPage))
            .relationId,
        created.id,
      );
      expect(
        app.router.stackData.take(history.length).map((route) => route.matchId),
        history,
      );
      expect(app.router.stackData, hasLength(history.length + 1));
      expect(app.repository.relationCommands, hasLength(1));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(app.router.stackData.map((route) => route.matchId), history);
      expect(find.byType(RelationDetailsPage), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_description(tester), 'Нижний черновик');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'принятая отправка сразу запрещает старые обработчики открытия участников',
    (tester) async {
      final app = await _launch(tester);
      await _openForm(tester, app, RelationDirection.outgoing);
      await _fill(tester, app);
      final openDetails = tester
          .widget<IconButton>(_key('relation-editor-open-source-details'))
          .onPressed!;
      final select = tester
          .widget<OutlinedButton>(_key('relation-editor-change-related'))
          .onPressed!;
      tester.widget<FilledButton>(_key('relation-editor-submit')).onPressed!();
      openDetails();
      select();
      await tester.pumpAndSettle();
      expect(app.router.current.name, RelationEditorRoute.name);
      expect(app.repository.relationCommands, hasLength(1));
      expect(
        tester
            .widget<IconButton>(_key('relation-editor-open-source-details'))
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'поздний успех после закрытия формы до dispose сохраняет новую форму',
    (tester) async {
      final app = await _launch(tester);
      await _openForm(tester, app, RelationDirection.outgoing);
      await _fill(tester, app);
      await _tap(tester, 'relation-editor-submit');
      final old = tester.state(find.byType(RelationEditorPage));
      final oldMatch = app.router.stackData.last.matchId;
      await app.router.maybePop();
      final newFormKey = UniqueKey();
      unawaited(
        app.router.push(
          RelationEditorRoute(
            key: newFormKey,
            editorContext: const RelationBlankCreationContext(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(old.mounted, isTrue);
      final newMatch = app.router.stackData.last.matchId;
      expect(newMatch, isNot(oldMatch));
      expect(
        app.router.stackData.any((route) => route.matchId == oldMatch),
        isFalse,
      );
      final newDescription = find.descendant(
        of: find.byKey(newFormKey),
        matching: _key('relation-editor-description'),
      );
      await tester.enterText(newDescription, 'Новый черновик');
      expect(
        tester.widget<TextField>(newDescription).controller!.text,
        'Новый черновик',
      );
      app.repository.completeRelationCreated(0);
      await tester.pumpAndSettle();
      expect(app.router.stackData.last.matchId, newMatch);
      expect(_description(tester), 'Новый черновик');
      expect(app.repository.relationCommands, hasLength(1));
      expect(find.textContaining('Relation created.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Finder _key(String key) => find.byKey(ValueKey(key));
String _description(WidgetTester tester) => tester
    .widget<TextField>(_key('relation-editor-description'))
    .controller!
    .text;

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(_key(key));
  await tester.pumpAndSettle();
}

Future<void> _openForm(
  WidgetTester tester,
  _App app,
  RelationDirection? direction,
) async {
  unawaited(
    app.router.push(
      RelationEditorRoute(
        editorContext: direction == null
            ? const RelationBlankCreationContext()
            : RelationCreationContext(
                participant: _participant(1),
                direction: direction,
              ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

RelationParticipantSummary _participant(int index) {
  final summary = testSummary(index: index, title: 'Участник $index');
  return RelationParticipantSummary(
    id: summary.id,
    title: summary.title,
    archiveState: summary.archiveState,
    activeRelationCount: summary.activeRelationCount,
  );
}

Future<void> _fill(WidgetTester tester, _App app) async {
  final sourceIndex =
      _key('relation-editor-change-related').evaluate().isNotEmpty ? 2 : 1;
  for (final (role, index) in [('source', sourceIndex), ('related', 2)]) {
    if (_key('relation-editor-select-$role').evaluate().isEmpty) continue;
    await tester.tap(_key('relation-editor-select-$role'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    app.repository.completeCatalogPage(
      app.repository.catalogQueries.length - 1,
      [testSummary(index: index, title: 'Выбор $role')],
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выбор $role'));
    await tester.pumpAndSettle();
  }
  await _tap(tester, 'relation-editor-type-need');
  await _tap(tester, 'relation-editor-priority-p1');
}

final class _App {
  _App(this.router, this.repository);
  final _PickerHoldingRouter router;
  final ControlledRelationFormRepository repository;
}

Future<_App> _launch(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repository = ControlledRelationFormRepository();
  final router = _PickerHoldingRouter();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    await repository.dispose();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        inMemoryQuickCreationModeOverride,
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
      retry: (retryCount, error) => null,
      child: MaterialApp.router(
        theme: doableTheme(Brightness.light),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router.config(),
        builder: (context, child) =>
            GraphOperationPresenter(child: child ?? const SizedBox.shrink()),
      ),
    ),
  );
  await tester.pump();
  await openIntentionGraph(tester);
  repository.completeCatalogPage(0, const []);
  await tester.pumpAndSettle();
  final app = _App(router, repository);
  await _openForm(tester, app, RelationDirection.outgoing);
  await tester.enterText(
    _key('relation-editor-description'),
    'Нижний черновик',
  );
  unawaited(
    router.push(RelationDetailsRoute(relationId: testFormRelationId(99))),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  repository.relationWatches.last.emitDetails(
    testRelationDetails(
      relationId: testFormRelationId(99),
      sourceId: testSummary(index: 8).id,
      relatedId: testSummary(index: 9).id,
    ),
    revision: const TestCatalogRevision(1),
  );
  await tester.pumpAndSettle();
  return app;
}

/// Настоящий стек приложения, который задерживает доставку результата поиска
/// участника его владельцу.
final class _PickerHoldingRouter extends RootStackRouter {
  final _pickerGate = Completer<void>();
  var holdPickerResult = false;
  void releasePicker() => _pickerGate.complete();
  @override
  List<AutoRoute> get routes => AppRouter().routes;
  @override
  Future<T?> push<T extends Object?>(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
  }) async {
    final result = await super.push<T>(route, onFailure: onFailure);
    if (holdPickerResult &&
        route.routeName == RelationParticipantPickerRoute.name) {
      await _pickerGate.future;
    }
    return result;
  }
}
