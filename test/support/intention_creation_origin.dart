import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/presentation/editor/relation_editor_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_root_pages.dart';

/// Исходные страницы самостоятельного создания, включая чужой черновик.
enum IntentionCreationOrigin {
  home('Главной', AppDestination.home),
  dailyChoices('каталогом дневных выборов', AppDestination.dailyChoices),
  graph('каталогом намерений', AppDestination.intentionGraph),
  deep('правкой намерения над черновиком связи', AppDestination.intentionGraph);

  const IntentionCreationOrigin(this.description, this.destination);
  final String description;
  final AppDestination destination;

  Future<IntentionCreationHistory> open(
    WidgetTester tester,
    StackRouter router, {
    required IntentionId participantId,
    required RootPageWait waitFor,
  }) async {
    final selected = tester
        .widget<AppNavigationBar>(find.byType(AppNavigationBar))
        .selected;
    if (selected != destination) {
      switch (destination) {
        case AppDestination.home:
          await openHome(tester, waitFor: waitFor);
        case AppDestination.dailyChoices:
          await openDailyChoices(tester);
        case AppDestination.intentionGraph:
          await openIntentionGraph(tester, waitFor: waitFor);
      }
      await tester.pumpAndSettle();
    }
    if (this == deep) {
      unawaited(
        router.push<void>(
          RelationEditorRoute(
            editorContext: const RelationBlankCreationContext(),
          ),
        ),
      );
      final description = find.byKey(
        const ValueKey('relation-editor-description'),
      );
      await waitFor(tester, description);
      await tester.pumpAndSettle();
      await tester.enterText(
        description,
        IntentionCreationHistory.relationDraft,
      );
      unawaited(
        router.push<void>(IntentionDetailsRoute(intentionId: participantId)),
      );
      final edit = find.byKey(const ValueKey('intention-details-edit'));
      await waitFor(tester, edit);
      await tester.pumpAndSettle();
      await tester.tap(edit);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('intention-details-edit-title')),
        IntentionCreationHistory.intentionDraft,
      );
      await tester.pumpAndSettle();
    }
    return IntentionCreationHistory(this, List.of(router.stackData));
  }
}

/// Точные экземпляры исходных маршрутов и несохранённые данные под созданием.
final class IntentionCreationHistory {
  IntentionCreationHistory(this.origin, this.routes);
  final IntentionCreationOrigin origin;
  final List<RouteData> routes;
  static const relationDraft = 'Несохранённое описание связи';
  static const intentionDraft = 'Несохранённое название исходной страницы';

  void expectPrefix(StackRouter router) => expect(
    router.stackData.take(routes.length),
    orderedEquals(routes.map(same)),
  );

  void expectRestored(WidgetTester tester, StackRouter router) {
    expectPrefix(router);
    expect(router.stackData, hasLength(routes.length));
    expect(
      tester.widget<AppNavigationBar>(find.byType(AppNavigationBar)).selected,
      origin.destination,
    );
    if (origin == IntentionCreationOrigin.deep) {
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('intention-details-edit-title')),
            )
            .controller!
            .text,
        intentionDraft,
      );
    }
  }

  Future<void> expectUnderlyingDraft(
    WidgetTester tester,
    StackRouter router,
  ) async {
    if (origin != IntentionCreationOrigin.deep) return;
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      router.stackData,
      orderedEquals(routes.take(routes.length - 1).map(same)),
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('relation-editor-description')),
          )
          .controller!
          .text,
      relationDraft,
    );
  }
}
