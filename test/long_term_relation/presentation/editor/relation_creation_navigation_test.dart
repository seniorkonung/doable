import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/presentation/graph_operation_presenter.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/presentation/details/relation_details_page.dart';
import 'package:doable/src/long_term_relation/presentation/editor/relation_editor_page.dart';
import 'package:doable/src/long_term_relation/presentation/editor/relation_editor_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../intention/presentation/catalog/catalog_test_support.dart';
import '../../../support/app_root_pages.dart';
import '../details/relation_details_test_support.dart';
import 'relation_form_test_support.dart';

enum _Failure { none, beforeForm, afterForm, afterResult, delayed }

void main() {
  setUp(() {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  for (final direction in <RelationDirection?>[
    null,
    ...RelationDirection.values,
  ]) {
    testWidgets(
      'вход $direction открывает созданный ID и сохраняет глубокую историю с черновиком',
      (tester) async {
        final app = await _launch(tester);
        final history = app.router.stackData
            .map((route) => route.matchId)
            .toList();
        await _openForm(tester, app, direction);
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
          app.router.stackData
              .take(history.length)
              .map((route) => route.matchId),
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
        expect(app.errors, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final point in [
    _Failure.beforeForm,
    _Failure.afterForm,
    _Failure.afterResult,
  ]) {
    testWidgets(
      'отказ $point сохраняет успех, фактическую историю и обычный выход',
      (tester) async {
        final app = await _launch(tester, failure: point);
        final history = app.router.stackData
            .map((route) => route.matchId)
            .toList();
        await _openForm(tester, app, RelationDirection.outgoing);
        await _fill(tester, app);
        await _tap(tester, 'relation-editor-submit');
        app.repository.completeRelationCreated(0);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        if (point == _Failure.afterResult) {
          expect(app.router.current.name, RelationDetailsRoute.name);
          app.repository.relationWatches.last.emitDetails(
            testRelationDetails(
              relationId: testFormRelationId(1),
              sourceId: testSummary(index: 1).id,
              relatedId: testSummary(index: 2).id,
            ),
            revision: const TestCatalogRevision(2),
          );
          await tester.pumpAndSettle();
          final installed = app.router.stackData.last.matchId;
          app.router.release();
          await tester.pumpAndSettle();
          expect(app.router.stackData.last.matchId, installed);
          await tester.binding.handlePopRoute();
        } else if (point == _Failure.beforeForm) {
          await tester.pumpAndSettle();
          expect(app.router.current.name, RelationEditorRoute.name);
          expect(
            tester
                .widget<FilledButton>(_key('relation-editor-submit'))
                .onPressed,
            isNull,
          );
          expect(
            tester
                .widget<TextField>(_key('relation-editor-description'))
                .enabled,
            isFalse,
          );
          expect(
            tester
                .widget<OutlinedButton>(_key('relation-editor-change-source'))
                .onPressed,
            isNull,
          );
          expect(
            tester
                .widget<IconButton>(_key('relation-editor-open-source-details'))
                .onPressed,
            isNull,
          );
          await tester.binding.handlePopRoute();
        }
        await tester.pumpAndSettle();
        expect(app.router.stackData.map((route) => route.matchId), history);
        expect(find.byType(RelationDetailsPage), findsOneWidget);
        expect(app.repository.relationCommands, hasLength(1));
        expect(app.errors, hasLength(1));
        expect(
          app.errors.single.exception.toString(),
          isNot(contains('Секрет')),
        );
        expect(find.textContaining('Relation created.'), findsOneWidget);
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        expect(find.textContaining('Relation created.'), findsNothing);
        expect(app.router.replacements, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

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

  for (final reset in [false, true]) {
    testWidgets(
      'поздний успех после ${reset ? 'сброса' : 'закрытия'} до dispose сохраняет новую форму',
      (tester) async {
        final app = await _launch(tester);
        await _openForm(tester, app, RelationDirection.outgoing);
        await _fill(tester, app);
        await _tap(tester, 'relation-editor-submit');
        final old = tester.state(find.byType(RelationEditorPage));
        final oldMatch = app.router.stackData.last.matchId;
        if (reset) {
          app.router.popUntilRoot();
        } else {
          await app.router.maybePop();
        }
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
        expect(app.router.replacements, 0);
        expect(app.repository.relationCommands, hasLength(1));
        expect(find.textContaining('Relation created.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'поздний отказ перехода после ухода сохраняет новый маршрут и ввод',
    (tester) async {
      final app = await _launch(tester, failure: _Failure.delayed);
      await _openForm(tester, app, RelationDirection.outgoing);
      await _fill(tester, app);
      await _tap(tester, 'relation-editor-submit');
      app.repository.completeRelationCreated(0);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await _openForm(tester, app, null);
      await tester.enterText(
        _key('relation-editor-description'),
        'Новый черновик',
      );
      final history = app.router.stackData
          .map((route) => route.matchId)
          .toList();
      app.router.release();
      await tester.pumpAndSettle();
      expect(app.router.stackData.map((route) => route.matchId), history);
      expect(_description(tester), 'Новый черновик');
      expect(app.repository.relationCommands, hasLength(1));
      expect(app.errors, hasLength(1));
      expect(app.router.replacements, 1);
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
  _App(this.router, this.repository, this.errors);
  final _FailingRouter router;
  final ControlledRelationFormRepository repository;
  final List<FlutterErrorDetails> errors;
}

Future<_App> _launch(
  WidgetTester tester, {
  _Failure failure = _Failure.none,
}) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repository = ControlledRelationFormRepository();
  final router = _FailingRouter(failure);
  final errors = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.library == 'relation editor') {
      errors.add(details);
    } else {
      previous?.call(details);
    }
  };
  addTearDown(() async {
    FlutterError.onError = previous;
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    await repository.dispose();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
      retry: (retryCount, error) => null,
      child: MaterialApp.router(
        locale: const Locale('en'),
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
  final app = _App(router, repository, errors);
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

final class _FailingRouter extends RootStackRouter {
  _FailingRouter(this.failure);
  final _Failure failure;
  final _gate = Completer<void>();
  var replacements = 0;
  void release() => _gate.complete();
  @override
  List<AutoRoute> get routes => AppRouter().routes;
  @override
  Future<T?> replace<T extends Object?>(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
  }) {
    replacements++;
    switch (failure) {
      case _Failure.none:
        return super.replace<T>(route, onFailure: onFailure);
      case _Failure.beforeForm:
        throw StateError('Секретный черновик');
      case _Failure.afterForm:
        removeRoute(stackData.last, notify: false);
        return Future<T?>.error(StateError('Секретный черновик'));
      case _Failure.afterResult:
        unawaited(super.replace<T>(route, onFailure: onFailure));
        return _gate.future.then<T?>(
          (_) => throw StateError('Секретный черновик'),
        );
      case _Failure.delayed:
        return _gate.future.then<T?>(
          (_) => throw StateError('Секретный черновик'),
        );
    }
  }
}
