import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/quick_creation/quick_creation_daily_choice_start_sheet.dart';
import 'package:doable/src/daily_choice/application/choice_path_draft.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/design_system/components/filter_button.dart';
import 'package:doable/src/design_system/components/picker_row.dart';
import 'package:doable/src/design_system/components/sheet.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/presentation/graph_operation_presenter.dart';
import 'package:doable/src/intention/application/intention_catalog.dart'
    show IntentionCatalogOrder, IntentionTagFilter;
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_state.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
import 'package:doable/src/intention/presentation/picker/intention_picker_view.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/daily_choice_catalog_provider.dart';
import '../support/daily_choice_durability_fixture.dart';
import '../support/daily_choice_local_date.dart';
import '../support/graph_seed.dart';
import '../support/intention_creation_origin.dart';
import '../support/local_database_harness.dart';
import '../support/in_memory_quick_creation_mode_store.dart';
import '../support/quick_creation.dart';
import '../support/tag_positions.dart';

part 'creation_flows_test_support.dart';
part 'creation_flows_accessibility_scenarios.dart';
part 'quick_creation/quick_creation_flow_scenarios.dart';

void main() {
  setUp(
    () => WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    ),
  );
  _registerAccessibilityTests();
  _registerQuickCreationFlowTests();
  _registerNestedQuickCreationTests();
  testWidgets('создание при занятой поверхности закрывает форму и обновляет '
      'каталог до сообщения, а возвращение не повторяет результат', (
    tester,
  ) async {
    final app = await _start(tester, fileBacked: true);
    const origin = IntentionCreationOrigin.graph;
    const flow = _Flow.intention;
    final history = await origin.open(
      tester,
      app.router,
      participantId: durabilityIntention(2),
      waitFor: (tester, finder) =>
          _until(tester, () => finder.evaluate().isNotEmpty),
    );
    await flow.open(tester, app, origin);
    await flow.fill(tester);
    const title = 'Намерение новое';
    await tester.enterText(_key('intention-editor-title'), title);
    final coordinator = app.container.read(
      graphCommandCoordinatorProvider.notifier,
    );
    final completions = <GraphCommandCompletion>[];
    final subscription = coordinator.completions.listen(completions.add);
    addTearDown(subscription.cancel);
    coordinator.acceptRelationArchive(
      ArchiveLongTermRelation(durabilityRelation(104)),
    );
    await _until(tester, () => completions.length == 1);
    await tester.pumpAndSettle();
    final first = app.l10n.graphOperationMessage(
      app.l10n.graphOperationArchive,
      app.l10n.graphOperationRelation,
      app.l10n.relationArchived,
    );
    final createdMessage = app.l10n.graphOperationMessage(
      app.l10n.graphOperationCreate,
      title,
      app.l10n.editorCreated,
    );
    expect(find.text(first).hitTestable(), findsOneWidget);

    app.observer.observe(flow.table);
    await _submit(tester, app, flow);
    await _until(tester, () => app.router.current.name == flow.resultRoute);
    await tester.pumpAndSettle();
    expect(_key('intention-editor-title'), findsNothing);
    expect(find.text(title), findsOneWidget);
    expect(find.text(first).hitTestable(), findsOneWidget);
    expect(find.text(createdMessage, skipOffstage: false), findsNothing);
    final stored = (await tester.runAsync(
      () => durabilityRows(app.database, flow.table),
    ))!;
    expect(stored, hasLength(flow.initialRows + 1));
    expect(stored.last['title'], title);
    expect(stored.last['description'], 'Сохранённое описание');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    history.expectRestored(tester, app.router);
    expect(find.text(title), findsOneWidget);
    expect(find.text(app.l10n.catalogTotalCount(6)), findsOneWidget);
    expect(find.text(first).hitTestable(), findsOneWidget);
    expect(find.text(createdMessage, skipOffstage: false), findsNothing);
    await tester.drag(find.text(first), const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(find.text(createdMessage).hitTestable(), findsOneWidget);
    await tester.drag(find.text(createdMessage), const Offset(600, 0));
    await tester.pumpAndSettle();
    await _tap(tester, find.text(title));
    await _until(tester, () => app.router.current.name == flow.resultRoute);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    history.expectRestored(tester, app.router);
    expect(find.byType(SnackBar, skipOffstage: false), findsNothing);
    expect(app.observer.attempts, 1);
    expect(completions, hasLength(2));
    expect(
      await tester.runAsync(() => durabilityRows(app.database, flow.table)),
      stored,
    );
    expect(tester.takeException(), isNull);
  });

  // Варианты потоков связи и дневного выбора принадлежат их собственным
  // тестам. Здесь намерение проверяется над корневой и глубокой историей, а
  // дневной выбор от действия — как одна связка общей кнопки с другим потоком.
  for (final (flow, origin) in const [
    (_Flow.intention, IntentionCreationOrigin.dailyChoices),
    (_Flow.intention, IntentionCreationOrigin.deep),
    (_Flow.bottomUp, IntentionCreationOrigin.deep),
  ]) {
    testWidgets('${flow.label}: успех над ${origin.description} сохраняет '
        'ID, историю, выбранный пункт и параметры каталогов', (tester) async {
      final app = await _start(
        tester,
        fileBacked:
            flow == _Flow.bottomUp && origin == IntentionCreationOrigin.deep,
      );
      final history = await origin.open(
        tester,
        app.router,
        participantId: durabilityIntention(2),
        waitFor: (tester, finder) =>
            _until(tester, () => finder.evaluate().isNotEmpty),
      );
      final catalogs = app.catalogs;
      await flow.open(tester, app, origin);
      history.expectPrefix(app.router);
      await flow.fill(tester);
      app.observer.observe(flow.table);
      await _tap(tester, _key(flow.submit));
      await _until(tester, () => app.router.current.name == flow.resultRoute);
      await tester.pumpAndSettle();
      history.expectPrefix(app.router);
      expect(app.router.stackData, hasLength(history.routes.length + 1));
      expect(
        tester.widget<AppNavigationBar>(find.byType(AppNavigationBar)).selected,
        origin.destination,
      );
      final rows = (await tester.runAsync(
        () => durabilityRows(app.database, flow.table),
      ))!;
      final created = rows.last;
      expect(rows, hasLength(flow.initialRows + 1));
      expect(app.observer.attempts, 1);
      final resultId = switch (app.router.current.args) {
        IntentionDetailsRouteArgs(:final intentionId) =>
          intentionId.toCanonicalString(),
        RelationDetailsRouteArgs(:final relationId) =>
          relationId.toCanonicalString(),
        DailyChoiceDetailsRouteArgs(:final choiceId) =>
          choiceId.toCanonicalString(),
        _ => throw StateError('Ожидался маршрут созданной сущности.'),
      };
      expect(resultId, created['id']);
      flow.expectStored(created);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      history.expectRestored(tester, app.router);
      expect(app.catalogs, catalogs);
      await history.expectUnderlyingDraft(tester, app.router);
      expect(tester.takeException(), isNull);
    });
  }
  const flow = _Flow.intention;
  for (final origin in const [
    IntentionCreationOrigin.dailyChoices,
    IntentionCreationOrigin.deep,
  ]) {
    for (final leave in [false, true]) {
      testWidgets(
        '${flow.label}: ${leave ? 'выход во время записи' : 'отмена'} '
        'над ${origin.description} сохраняет исходную сессию',
        (tester) async {
          final app = await _start(tester);
          final history = await origin.open(
            tester,
            app.router,
            participantId: durabilityIntention(2),
            waitFor: (tester, finder) =>
                _until(tester, () => finder.evaluate().isNotEmpty),
          );
          final catalogs = app.catalogs;
          await flow.open(tester, app, origin);
          await flow.fill(tester);
          app.observer.observe(flow.table, hold: leave);
          if (leave) await _submit(tester, app, flow);
          await _closeCreation(tester, app, flow);
          history.expectRestored(tester, app.router);
          final current = app.router.stackData.last.matchId;
          app.observer.release();
          if (leave) {
            await _until(
              tester,
              () => _key('graph-operation-message').evaluate().isNotEmpty,
            );
            await tester.pumpAndSettle();
          }
          expect(app.router.stackData.last.matchId, current);
          history.expectRestored(tester, app.router);
          expect(app.catalogs, catalogs);
          final rows = await durabilityRows(app.database, flow.table);
          expect(rows, hasLength(flow.initialRows + (leave ? 1 : 0)));
          expect(app.observer.attempts, leave ? 1 : 0);
          if (leave) flow.expectStored(rows.last);
          await history.expectUnderlyingDraft(tester, app.router);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
