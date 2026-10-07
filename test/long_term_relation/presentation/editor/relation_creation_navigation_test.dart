import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
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

enum _Failure {
  none,
  beforeForm,
  afterForm,
  afterResult,
  delayed,
  exitBeforeForm,
  exitAfterForm,
}

void main() {
  setUp(() {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  for (final success in [true, false]) {
    testWidgets(
      'поздний ${success ? 'успех' : 'отказ'} после неудачного выхода не возвращает права формы',
      (tester) async {
        final app = await _launch(tester, failure: _Failure.exitBeforeForm);
        await _openForm(tester, app, null);
        await _fill(tester, app);
        await _tap(tester, 'relation-editor-submit');
        tester
            .widget<CreationExitAction>(find.byType(CreationExitAction))
            .onExit();
        await tester.pump();
        expect(
          tester
              .widget<CreationExitAction>(find.byType(CreationExitAction))
              .state,
          CreationExitState.submitting,
        );
        if (success) {
          app.repository.completeRelationCreated(0);
        } else {
          app.repository.failRelationCommand(
            0,
            const LongTermRelationUnavailableFailure(),
          );
        }
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<CreationExitAction>(find.byType(CreationExitAction))
              .state,
          CreationExitState.terminal,
        );
        expect(
          tester.widget<FilledButton>(_key('relation-editor-submit')).onPressed,
          isNull,
        );
        expect(
          tester.widget<TextField>(_key('relation-editor-description')).enabled,
          isFalse,
        );
        expect(app.router.replacements, 0);
        expect(app.repository.relationCommands, hasLength(1));
        expect(
          find.textContaining(
            success ? 'Relation created.' : 'The relation couldn’t be created.',
          ),
          findsOneWidget,
        );
        app.router.allowExit = true;
        tester
            .widget<CreationExitAction>(find.byType(CreationExitAction))
            .onExit();
        await tester.pumpAndSettle();
        expect(find.byType(RelationDetailsPage), findsOneWidget);
        expect(app.errors, hasLength(1));
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final retained in [true, false]) {
    testWidgets(
      'поздний выбор участника после выхода сохраняет ${retained ? 'покинутую' : 'новую'} форму',
      (tester) async {
        final app = await _launch(
          tester,
          failure: retained ? _Failure.exitBeforeForm : _Failure.none,
        );
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
        tester
            .widget<CreationExitAction>(find.byType(CreationExitAction))
            .onExit();
        await tester.pumpAndSettle();
        if (!retained) await _openForm(tester, app, RelationDirection.outgoing);
        final matchId = app.router.stackData.last.matchId;
        app.router.releasePicker();
        await tester.pumpAndSettle();
        expect(app.router.stackData.last.matchId, matchId);
        expect(find.text('Участник 1'), findsOneWidget);
        expect(find.text('Поздний участник'), findsNothing);
        expect(app.repository.relationCommands, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

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

  for (final locale in [const Locale('ru'), const Locale('en')]) {
    testWidgets(
      'выход доступен на телефоне с текстом 2.6 и клавиатурой на ${locale.languageCode}',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final app = await _launch(tester, locale: locale);
        await _openForm(tester, app, null);
        await _fill(tester, app);
        await _tap(tester, 'relation-editor-submit');
        tester.view.physicalSize = const Size(400, 800);
        tester.view.viewInsets = const FakeViewPadding(bottom: 260);
        tester.platformDispatcher.textScaleFactorTestValue = 2.6;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpAndSettle();
        final label = locale.languageCode == 'ru'
            ? 'Выйти из создания'
            : 'Leave creation';
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
        expect(
          node.hint,
          contains(locale.languageCode == 'ru' ? 'продолжится' : 'continue'),
        );
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(find.byType(RelationDetailsPage), findsOneWidget);
        expect(app.repository.relationCommands, hasLength(1));
        semantics.dispose();
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final direction in <RelationDirection?>[
    null,
    ...RelationDirection.values,
  ]) {
    testWidgets(
      'отмена входа $direction до отправки сохраняет исходную историю',
      (tester) async {
        final app = await _launch(tester);
        final history = app.router.stackData
            .map((route) => route.matchId)
            .toList();
        await _openForm(tester, app, direction);
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
        expect(app.errors, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final success in [true, false]) {
    testWidgets(
      'отправка перед выходом и поздний ${success ? 'успех' : 'отказ'} сохраняют новую форму',
      (tester) async {
        final app = await _launch(tester);
        final history = app.router.stackData
            .map((route) => route.matchId)
            .toList();
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
        if (success) {
          app.repository.completeRelationCreated(0);
        } else {
          app.repository.failRelationCommand(
            0,
            const LongTermRelationUnavailableFailure(),
          );
        }
        exit();
        await tester.pumpAndSettle();
        expect(app.router.stackData.last.matchId, newMatch);
        expect(_description(tester), 'Новый черновик');
        expect(app.router.replacements, 0);
        expect(app.repository.relationCommands, hasLength(1));
        expect(
          find.textContaining(
            success ? 'Relation created.' : 'The relation couldn’t be created.',
          ),
          findsOneWidget,
        );
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        expect(
          find.textContaining(
            success ? 'Relation created.' : 'The relation couldn’t be created.',
          ),
          findsNothing,
        );
        expect(app.errors, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final point in [_Failure.exitBeforeForm, _Failure.exitAfterForm]) {
    testWidgets(
      'отказ выхода $point не возобновляет создание и сохраняет повтор выхода',
      (tester) async {
        final app = await _launch(tester, failure: point);
        final history = app.router.stackData
            .map((route) => route.matchId)
            .toList();
        await _openForm(tester, app, null);
        await _fill(tester, app);
        final submit = tester
            .widget<FilledButton>(_key('relation-editor-submit'))
            .onPressed!;
        final select = tester
            .widget<OutlinedButton>(_key('relation-editor-change-source'))
            .onPressed!;
        final changeDescription = tester
            .widget<TextField>(_key('relation-editor-description'))
            .onChanged!;
        final exit = tester
            .widget<CreationExitAction>(find.byType(CreationExitAction))
            .onExit;
        exit();
        submit();
        select();
        changeDescription('Поздняя правка');
        await tester.pumpAndSettle();
        if (point == _Failure.exitBeforeForm) {
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
          expect(find.text('Leave creation'), findsOneWidget);
          app.router.allowExit = true;
          tester
              .widget<CreationExitAction>(find.byType(CreationExitAction))
              .onExit();
          await tester.pumpAndSettle();
        }
        expect(app.router.stackData.map((route) => route.matchId), history);
        expect(app.repository.relationCommands, isEmpty);
        expect(app.errors, hasLength(1));
        expect(
          app.errors.single.exception.toString(),
          isNot(contains('Секрет')),
        );
        await _openForm(tester, app, null);
        await tester.enterText(
          _key('relation-editor-description'),
          'Новый черновик',
        );
        final newMatch = app.router.stackData.last.matchId;
        exit();
        await tester.pumpAndSettle();
        expect(app.router.stackData.last.matchId, newMatch);
        expect(_description(tester), 'Новый черновик');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'выход при записи объясняет продолжение, после отказа доступна отмена',
    (tester) async {
      final app = await _launch(tester);
      await _openForm(tester, app, null);
      await _fill(tester, app);
      await _tap(tester, 'relation-editor-submit');
      expect(
        tester
            .widget<CreationExitAction>(find.byType(CreationExitAction))
            .state,
        CreationExitState.submitting,
      );
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
      expect(app.errors, isEmpty);
    },
  );

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
  Locale locale = const Locale('en'),
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
  final _pickerGate = Completer<void>();
  var replacements = 0;
  var allowExit = false;
  var holdPickerResult = false;
  void release() => _gate.complete();
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

  @override
  void removeRoute(RouteData route, {bool notify = true}) {
    if (!allowExit && route.name == RelationEditorRoute.name) {
      if (failure == _Failure.exitBeforeForm) {
        throw StateError('Секретный черновик');
      }
      if (failure == _Failure.exitAfterForm) {
        super.removeRoute(route, notify: false);
        throw StateError('Секретный черновик');
      }
    }
    super.removeRoute(route, notify: notify);
  }

  @override
  Future<T?> replace<T extends Object?>(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
  }) {
    replacements++;
    switch (failure) {
      case _Failure.none:
      case _Failure.exitBeforeForm:
      case _Failure.exitAfterForm:
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
