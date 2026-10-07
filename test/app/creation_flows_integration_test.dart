import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/daily_choice/application/choice_path_draft.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_page.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_view_model.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/presentation/graph_operation_presenter.dart';
import 'package:doable/src/favorite/presentation/home/home_page.dart';
import 'package:doable/src/daily_choice/presentation/daily_choice_creation_launcher.dart';
import 'package:doable/src/intention/application/intention_catalog.dart'
    show IntentionCatalogOrder;
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/intention_summary_view.dart';
import 'package:doable/src/long_term_relation/presentation/editor/relation_editor_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/daily_choice_durability_fixture.dart';
import '../support/daily_choice_local_date.dart';
import '../support/intention_creation_origin.dart';
import '../support/local_database_harness.dart';

part 'creation_flows_test_support.dart';
part 'creation_flows_accessibility_scenarios.dart';

void main() {
  setUp(
    () => WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    ),
  );
  _registerAccessibilityTests();
  for (final flow in _Flow.values) {
    for (final origin in IntentionCreationOrigin.values) {
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
          tester
              .widget<AppNavigationBar>(find.byType(AppNavigationBar))
              .selected,
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
}
