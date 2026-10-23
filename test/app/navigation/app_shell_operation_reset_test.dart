import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/design_system/components/sheet.dart';
import 'package:doable/src/data/local/app_database.dart'
    show openInMemoryLocalDatabase;
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/presentation/operation_failure_presentation.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/presentation/details/relation_details_page.dart';
import 'package:doable/src/long_term_relation/presentation/editor/relation_editor_page.dart';
import 'package:doable/src/long_term_relation/presentation/editor/relation_editor_state.dart';
import 'package:doable/src/long_term_relation/presentation/participant_picker/relation_participant_picker_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../intention/presentation/details/details_test_support.dart';
import '../../long_term_relation/presentation/details/relation_details_test_support.dart'
    show ControlledRelationWatch, testRelationDetails;
import '../../long_term_relation/presentation/neighborhood/neighborhood_test_support.dart'
    show testRelationId;
import '../../support/app_root_pages.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/in_memory_quick_creation_mode_store.dart';

const _archive = ValueKey('intention-details-archive');
const _failure =
    'Архивирование — «Намерение»: Не удалось изменить состояние намерения. Повторите попытку.';
const _deleteSuccess = 'Удаление — «Намерение»: Намерение удалено.';
const _relationDeleteSuccess = 'Удаление — «связь»: Связь удалена.';
const _description = ValueKey('relation-editor-description');

void main() {
  setUp(() {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  // Сброс идёт одним путём для текущего и другого пункта; берём переход на
  // другой пункт, где меняется ещё и выбранная вкладка.
  const destination = AppDestination.home;
  testWidgets('позднее удаление намерения после сброса к другому пункту '
      'сохраняет повторно открытую страницу того же намерения', (tester) async {
    final app = await _ControlledApp.start(tester);
    await app.openDetails(tester);
    await app.delete(tester);

    await _select(tester, destination, settle: false);
    unawaited(
      app.router.push(IntentionDetailsRoute(intentionId: app.intention.id)),
    );
    await tester.pump();
    await tester.pump();

    app.complete(
      testDetailsDeletedResult(
        app.intention,
        revision: const TestDetailsRevision(1),
      ),
    );
    await _until(tester, () => !app.coordinator.isRunning(app.intention.id));
    await tester.pumpAndSettle();

    // Повторно открытая страница осталась единственной и сообщает, что
    // намерения больше нет; сообщение о результате показано один раз.
    expect(find.byType(IntentionDetailsPage), findsOneWidget);
    expect(app.router.stack.map((page) => page.name), [
      AppShellRoute.name,
      IntentionDetailsRoute.name,
    ]);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(IntentionDetailsPage)),
    );
    expect(find.text(l10n.detailsNotFound), findsOneWidget);
    expect(find.text(app.intention.title), findsNothing);
    _expectSelected(tester, destination);
    expect(find.text(_deleteSuccess), findsOneWidget);
    await _expireMessages(tester);
    expect(find.byType(IntentionDetailsPage), findsOneWidget);
    expect(app.repository.commands.single, isA<DeleteIntention>());
    unawaited(app.router.maybePop());
    await tester.pumpAndSettle();
    _expectRoot(tester, app.router, destination);
    await _select(tester, AppDestination.intentionGraph);
    expect(find.text(app.intention.title), findsNothing);
  });

  testWidgets('позднее удаление связи после сброса к другому пункту '
      'сохраняет повторно открытый просмотр той же связи', (tester) async {
    final app = await _ControlledApp.start(tester);
    await app.openRelationDetails(tester);
    await app.deleteRelation(tester);

    await _select(tester, destination, settle: false);
    await app.openRelationSourceDetails(tester);
    unawaited(
      app.router.push(
        RelationDetailsRoute(relationId: app.relationDetails.relation.id),
      ),
    );
    await tester.pump();
    await tester.pump();

    app.completeRelationDelete();
    await _until(
      tester,
      () => !app.coordinator.isRelationRunning(app.relationDetails.relation.id),
    );
    await tester.pumpAndSettle();

    expect(find.byType(RelationDetailsPage), findsOneWidget);
    expect(app.router.stack.map((page) => page.name), [
      AppShellRoute.name,
      IntentionDetailsRoute.name,
      RelationDetailsRoute.name,
    ]);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(RelationDetailsPage)),
    );
    expect(find.text(l10n.relationDetailsNotFound), findsOneWidget);
    expect(find.byKey(const ValueKey('relation-details-phrase')), findsNothing);
    _expectSelected(tester, destination);
    expect(find.text(_relationDeleteSuccess), findsOneWidget);
    await _expireMessages(tester);
    expect(find.byType(RelationDetailsPage), findsOneWidget);
    expect(
      app.repository.relationCommands.single,
      isA<DeleteLongTermRelation>(),
    );
    expect(app.repository.commands, isEmpty);
    unawaited(app.router.maybePop());
    await tester.pumpAndSettle();
    await _expectSourceActiveRelationCount(tester, 0);
    unawaited(app.router.maybePop());
    await tester.pumpAndSettle();
    _expectRoot(tester, app.router, destination);
  });

  testWidgets('позднее удаление связи после сброса к другому пункту '
      'сохраняет новую форму и её ввод до освобождения прежней страницы', (
    tester,
  ) async {
    final app = await _ControlledApp.start(tester);
    await app.openRelationDetails(tester);
    await app.deleteRelation(tester);

    await _select(tester, destination, settle: false);
    await app.openRelationSourceDetails(tester);
    unawaited(
      app.router.push(
        RelationEditorRoute(
          editorContext: RelationCreationContext(
            participant: RelationParticipantSummary(
              id: testDetailsIntentionId(3),
              title: 'Независимый участник',
              archiveState: IntentionArchiveState.active,
              activeRelationCount: 0,
            ),
            direction: RelationDirection.outgoing,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    const text = 'Несохранённое описание после сброса просмотра связи';
    await tester.enterText(find.byKey(_description), text);
    expect(find.text(text), findsOneWidget);

    app.completeRelationDelete();
    await _until(
      tester,
      () => !app.coordinator.isRelationRunning(app.relationDetails.relation.id),
    );
    await tester.pumpAndSettle();

    expect(find.text(text), findsOneWidget);
    expect(app.router.stack.map((page) => page.name), [
      AppShellRoute.name,
      IntentionDetailsRoute.name,
      RelationEditorRoute.name,
    ]);
    expect(find.text(_relationDeleteSuccess), findsOneWidget);
    await _expireMessages(tester);
    expect(
      app.repository.relationCommands.single,
      isA<DeleteLongTermRelation>(),
    );
    expect(app.repository.commands, isEmpty);

    unawaited(app.router.maybePop());
    await tester.pumpAndSettle();
    expect(find.byType(RelationDetailsPage, skipOffstage: false), findsNothing);
    await _expectSourceActiveRelationCount(tester, 0);
    unawaited(app.router.maybePop());
    await tester.pumpAndSettle();
    _expectRoot(tester, app.router, destination);
  });
  testWidgets(
    'позднее удаление намерения после сброса к другому пункту '
    'сохраняет новую форму связи и её ввод до освобождения прежней страницы',
    (tester) async {
      final app = await _ControlledApp.start(tester);
      await app.openDetails(tester);
      await app.delete(tester);

      await _select(tester, destination, settle: false);
      unawaited(
        app.router.push(
          RelationEditorRoute(
            editorContext: RelationCreationContext(
              participant: RelationParticipantSummary(
                id: testDetailsIntentionId(2),
                title: 'Независимый участник',
                archiveState: IntentionArchiveState.active,
                activeRelationCount: 0,
              ),
              direction: RelationDirection.outgoing,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      const text = 'Несохранённое описание новой связи';
      await tester.enterText(find.byKey(_description), text);
      expect(find.text(text), findsOneWidget);

      app.complete(
        testDetailsDeletedResult(
          app.intention,
          revision: const TestDetailsRevision(1),
        ),
      );
      await _until(tester, () => !app.coordinator.isRunning(app.intention.id));
      await tester.pumpAndSettle();

      expect(find.text(text), findsOneWidget);
      expect(app.router.stack.map((page) => page.name), [
        AppShellRoute.name,
        RelationEditorRoute.name,
      ]);
      expect(find.text(_deleteSuccess), findsOneWidget);
      await _expireMessages(tester);
      expect(app.repository.commands.single, isA<DeleteIntention>());
      expect(app.repository.relationCommands, isEmpty);

      unawaited(app.router.maybePop());
      await tester.pumpAndSettle();
      _expectRoot(tester, app.router, destination);
      await _select(tester, AppDestination.intentionGraph);
      expect(find.text(app.intention.title), findsNothing);
    },
  );

  testWidgets('удаление связи с актуальной верхней страницы закрывает только '
      'её просмотр и один раз предъявляет результат', (tester) async {
    final app = await _ControlledApp.start(tester);
    await app.openDetails(tester);
    await app.openRelationDetails(tester);
    await app.deleteRelation(tester);

    app.completeRelationDelete();
    await _until(
      tester,
      () => !app.coordinator.isRelationRunning(app.relationDetails.relation.id),
    );
    await tester.pumpAndSettle();

    expect(app.router.stack.map((page) => page.name), [
      AppShellRoute.name,
      IntentionDetailsRoute.name,
    ]);
    expect(find.byType(IntentionDetailsPage), findsOneWidget);
    expect(find.byType(RelationDetailsPage, skipOffstage: false), findsNothing);
    expect(find.text(_relationDeleteSuccess), findsOneWidget);
    await _expireMessages(tester);
    expect(
      app.repository.relationCommands.single,
      isA<DeleteLongTermRelation>(),
    );
    expect(app.repository.commands, isEmpty);
  });

  testWidgets('позднее удаление намерения сохраняет панель тегов, '
      'открытую кнопкой «+ Тег» до освобождения сброшенной страницы', (
    tester,
  ) async {
    final l10n = lookupAppLocalizations(const Locale('ru'));
    final app = await _ControlledApp.start(tester);
    await app.openDetails(tester);
    await app.delete(tester);

    await _select(tester, AppDestination.intentionGraph, settle: false);
    // Каталог возвращается на место вместе с анимацией закрытия страницы;
    // «+ Тег» нажимаем, как только кнопка доступна, а страница ещё не
    // освобождена.
    final add = find.byKey(const ValueKey('intention-tag-conditions-add'));
    await _until(tester, () => add.hitTestable().evaluate().isNotEmpty);
    expect(
      find.byType(IntentionDetailsPage, skipOffstage: false),
      findsOneWidget,
    );
    await tester.tap(add);
    await tester.pump();
    await tester.pump();
    expect(find.text(l10n.tagsPanelFilterTitle), findsOneWidget);

    app.complete(
      testDetailsDeletedResult(
        app.intention,
        revision: const TestDetailsRevision(1),
      ),
    );
    await _until(tester, () => !app.coordinator.isRunning(app.intention.id));
    await tester.pumpAndSettle();

    expect(find.text(l10n.tagsPanelFilterTitle), findsOneWidget);
    expect(app.router.stack.map((page) => page.name), [AppShellRoute.name]);
    expect(app.router.topRoute.name, IntentionCatalogRoute.name);
    expect(
      find.byType(IntentionDetailsPage, skipOffstage: false),
      findsNothing,
    );
    // Сообщение показано над нижней частью открытой панели.
    expect(
      find.descendant(
        of: find.byType(Sheet),
        matching: find.text(_deleteSuccess),
      ),
      findsOneWidget,
    );
    await _expireMessages(tester);
    expect(app.repository.commands.single, isA<DeleteIntention>());
    await tester.tap(find.text(l10n.tagsPanelDone));
    await tester.pumpAndSettle();
    expect(find.text(l10n.tagsPanelFilterTitle), findsNothing);
    _expectRoot(tester, app.router, AppDestination.intentionGraph);
    _expectSelected(tester, AppDestination.intentionGraph);
    expect(find.text(app.intention.title), findsNothing);
  });

  testWidgets('успешный повтор удаления после отказа закрывает только '
      'принявшую повтор страницу', (tester) async {
    final app = await _ControlledApp.start(tester);
    await app.openOtherDetails(tester);
    await app.openDetails(tester);
    await app.delete(tester);
    app.complete(const ResultFailure(IntentionUnavailableFailure()));
    await _until(tester, () => !app.coordinator.isRunning(app.intention.id));
    await tester.pumpAndSettle();
    expect(find.byType(IntentionDetailsPage), findsOneWidget);

    final retry = find.byKey(
      const ValueKey('intention-details-state-change-retry'),
    );
    await tester.ensureVisible(retry);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 100));
    await tester.pumpAndSettle();
    await tester.tap(retry);
    await tester.pump();
    expect(app.repository.commands.last, isA<DeleteIntention>());
    app.complete(
      testDetailsDeletedResult(
        app.intention,
        revision: const TestDetailsRevision(1),
      ),
    );
    await _until(tester, () => !app.coordinator.isRunning(app.intention.id));
    await tester.pumpAndSettle();

    expect(find.text('Другое намерение'), findsOneWidget);
    expect(app.router.stack.map((page) => page.name), [
      AppShellRoute.name,
      IntentionDetailsRoute.name,
    ]);
    expect(find.text(_deleteSuccess), findsOneWidget);
    await _expireMessages(tester);
  });

  testWidgets('ошибка архивирования после сброса переходит общей поверхности '
      'без восстановления страницы или повтора команды', (tester) async {
    final app = await _ControlledApp.start(tester);
    await app.openDetails(tester);
    await app.archive(tester);
    await _select(tester, AppDestination.intentionGraph);

    app.complete(const ResultFailure(IntentionUnavailableFailure()));
    await _until(tester, () => !app.coordinator.isRunning(app.intention.id));
    await tester.pumpAndSettle();

    expect(find.text(_failure), findsOneWidget);
    _expectRoot(tester, app.router, AppDestination.intentionGraph);
    await _expireMessages(tester);
    expect(app.repository.commands, hasLength(1));
  });

  testWidgets('сброс до пригодного кадра отдаёт ошибку общей поверхности, и '
      'она показана один раз после возвращения в приложение', (tester) async {
    final app = await _ControlledApp.start(tester);
    await app.openDetails(tester);
    await app.archive(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    app.complete(const ResultFailure(IntentionUnavailableFailure()));
    await _until(tester, () => !app.coordinator.isRunning(app.intention.id));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar, skipOffstage: false), findsNothing);

    await _select(tester, AppDestination.home);
    expect(
      find.byType(OperationFailurePresentation, skipOffstage: false),
      findsNothing,
    );
    expect(find.byType(SnackBar, skipOffstage: false), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text(_failure), findsOneWidget);
    _expectRoot(tester, app.router, AppDestination.home);
    await _expireMessages(tester);
    expect(app.repository.commands, hasLength(1));
  });

  testWidgets('сброс после пригодного кадра не предъявляет уже показанную '
      'инлайн-ошибку повторно', (tester) async {
    final app = await _ControlledApp.start(tester);
    await app.openDetails(tester);
    await app.archive(tester);
    app.complete(const ResultFailure(IntentionUnavailableFailure()));
    await _until(tester, () => !app.coordinator.isRunning(app.intention.id));
    await tester.pumpAndSettle();
    expect(
      find.byType(OperationFailurePresentation).hitTestable(),
      findsOneWidget,
    );

    await _select(tester, AppDestination.home);
    await tester.pumpAndSettle();
    _expectRoot(tester, app.router, AppDestination.home);
    await _expireMessages(tester);
    expect(app.repository.commands, hasLength(1));
  });

  testWidgets('сброс над поиском участника возвращает отмену и освобождает '
      'ожидающую форму без продолжения потока', (tester) async {
    final app = await _ControlledApp.start(tester);
    unawaited(
      app.router.push(
        RelationEditorRoute(
          editorContext: RelationCreationContext(
            participant: RelationParticipantSummary(
              id: testDetailsIntentionId(2),
              title: 'Исходное намерение',
              archiveState: IntentionArchiveState.active,
              activeRelationCount: 0,
            ),
            direction: RelationDirection.outgoing,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('relation-editor-select-related')),
    );
    await tester.pumpAndSettle();
    final picker = find.byType(RelationParticipantPickerPage);
    final l10n = AppLocalizations.of(tester.element(picker));
    await tester.tap(find.byTooltip(l10n.participantPickerOpenDetails));
    await tester.pump();
    await tester.pump();
    app.repository.detailRequests.single.add(ResultSuccess(app.intention));
    await tester.pumpAndSettle();

    await _select(tester, AppDestination.home);

    expect(find.byType(RelationEditorPage, skipOffstage: false), findsNothing);
    expect(picker, findsNothing);
    _expectRoot(tester, app.router, AppDestination.home);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    _expectRoot(tester, app.router, AppDestination.home);
    expect(app.repository.commands, isEmpty);
    expect(app.repository.relationCommands, isEmpty);
  });
}

Future<void> _select(
  WidgetTester tester,
  AppDestination destination, {
  bool settle = true,
}) async {
  await tester.tap(appNavigationDestination(destination));
  if (settle) await tester.pumpAndSettle();
}

void _expectRoot(
  WidgetTester tester,
  AppRouter router,
  AppDestination destination,
) {
  expect(router.stack.map((page) => page.name), [AppShellRoute.name]);
  expect(router.topRoute.name, destination.page.name);
  expect(router.hasPagelessTopRoute, isFalse);
  expect(find.byType(IntentionDetailsPage, skipOffstage: false), findsNothing);
  expect(tester.takeException(), isNull);
}

/// Панель объявляет пункт [destination] выбранным.
void _expectSelected(WidgetTester tester, AppDestination destination) {
  expect(
    tester
        .getSemantics(appNavigationDestination(destination))
        .flagsCollection
        .isSelected,
    Tristate.isTrue,
  );
}

/// Сводка связей на странице исходного намерения подтверждает [count]
/// активных связей.
Future<void> _expectSourceActiveRelationCount(
  WidgetTester tester,
  int count,
) async {
  final summary = find.byKey(
    const ValueKey('relation-neighborhood-summary-numbers'),
  );
  await tester.scrollUntilVisible(
    summary,
    300,
    scrollable: find
        .descendant(
          of: find.byType(IntentionDetailsPage),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  final l10n = AppLocalizations.of(tester.element(summary));
  expect(
    tester.getSemantics(summary).label,
    contains(l10n.relationNeighborhoodActiveTotal(count)),
  );
}

Future<void> _expireMessages(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
  expect(find.byType(SnackBar, skipOffstage: false), findsNothing);
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
  expect(find.byType(SnackBar, skipOffstage: false), findsNothing);
  expect(tester.takeException(), isNull);
}

Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 100 && !done(); attempt++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue);
}

final class _ControlledApp {
  _ControlledApp(this.runtime, this.router, this.repository);

  final AppRuntime runtime;
  final AppRouter router;
  final ControlledDetailsRepository repository;
  final intention = testDetailsIntention(description: null);
  final relationDetails = testRelationDetails(
    relationId: testRelationId(101),
    sourceId: testDetailsIntentionId(1),
    relatedId: testDetailsIntentionId(2),
    sourceTitle: 'Намерение',
  );
  var completedCommands = 0;
  var completedRelationCommands = 0;
  var _relationDeleted = false;
  GraphCommandCoordinator get coordinator => runtime.commandCoordinator;

  static Future<_ControlledApp> start(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.binding.platformDispatcher.localesTestValue = const [Locale('ru')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    final repository = ControlledDetailsRepository()
      ..catalogResult = ResultSuccess(
        IntentionCatalogFirstPage(
          items: [testDetailsSummary(testDetailsIntention(description: null))],
          totalCount: 1,
          nextCursor: null,
          revision: const TestDetailsRevision(0),
        ),
      );
    final runtime = AppRuntime(
      quickCreationModeStore: InMemoryQuickCreationModeStore(),
      connectionFactory: () => openInMemoryLocalDatabase(),
      diagnosticsSink: InMemoryDiagnosticsSink(),
      repositoryFactory: (_) => repository,
    );
    final ready = (await tester.runAsync(runtime.bootstrap)) as AppRuntimeReady;
    final app = _ControlledApp(
      runtime,
      ready.container.read(appRouterProvider),
      repository,
    );
    addTearDown(() async {
      while (app.completedCommands < repository.commands.length) {
        app.complete(const ResultFailure(IntentionUnavailableFailure()));
      }
      while (app.completedRelationCommands <
          repository.relationCommands.length) {
        repository.completeRelationCommand(
          app.completedRelationCommands++,
          const GraphCommandFailed(LongTermRelationUnavailableFailure()),
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await runtime.shutdown();
      for (final request in repository.detailRequests) {
        await request.close();
      }
    });
    await tester.pumpWidget(MainApp(runtime: runtime));
    await tester.pumpAndSettle();
    await _select(tester, AppDestination.intentionGraph);
    return app;
  }

  Future<void> openDetails(WidgetTester tester) =>
      _openDetails(tester, intention);

  /// Открывает страницу другого намерения — обычную страницу, которую
  /// операции над [intention] не затрагивают.
  Future<void> openOtherDetails(WidgetTester tester) => _openDetails(
    tester,
    testDetailsIntention(index: 2, title: 'Другое намерение'),
  );

  /// Открывает страницу исходного намерения [relationDetails]: её сводка
  /// подтверждает одну активную связь, пока удаление связи не завершено.
  Future<void> openRelationSourceDetails(WidgetTester tester) async {
    repository.onRelationGroupPage = (query) {
      final counts = _relationDeleted
          ? testRelationCounts()
          : testRelationCounts(activeNeedOutgoing: 1);
      return GraphResultSuccess(
        RelationGroupFirstPage(
          items: [
            if (counts.forSelection(query.group) > 0)
              testDetailsRelationRow(ownerId: intention.id, index: 1),
          ],
          counts: counts,
          nextCursor: null,
          revision: TestDetailsRevision(_relationDeleted ? 1 : 0),
        ),
      );
    };
    await _openDetails(tester, intention);
    await _expectSourceActiveRelationCount(tester, 1);
  }

  Future<void> _openDetails(WidgetTester tester, Intention shown) async {
    final requests = repository.detailRequests.length;
    unawaited(router.push(IntentionDetailsRoute(intentionId: shown.id)));
    await tester.pump();
    await tester.pump();
    // Страница и её соседство наблюдают намерение; общий поток получает
    // только первая открытая страница, поэтому отвечаем каждому новому.
    final opened = repository.detailRequests.skip(requests).toList();
    expect(opened, isNotEmpty);
    for (final request in opened) {
      request.add(ResultSuccess(shown));
    }
    await tester.pumpAndSettle();
  }

  Future<void> openRelationDetails(WidgetTester tester) async {
    final watch = ControlledRelationWatch(relationDetails.relation.id);
    addTearDown(watch.close);
    repository.onWatchRelation = (id) {
      expect(id, relationDetails.relation.id);
      return watch.stream;
    };
    unawaited(
      router.push(
        RelationDetailsRoute(relationId: relationDetails.relation.id),
      ),
    );
    await tester.pump();
    await tester.pump();
    watch.emitDetails(relationDetails, revision: const TestDetailsRevision(0));
    await tester.pumpAndSettle();
  }

  Future<void> deleteRelation(WidgetTester tester) async {
    final delete = find.byKey(
      const ValueKey('relation-details-delete-relation'),
    );
    await tester.ensureVisible(delete);
    await tester.tap(delete);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('relation-details-confirm-delete')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(repository.relationCommands.single, isA<DeleteLongTermRelation>());
    expect(coordinator.isRelationRunning(relationDetails.relation.id), isTrue);
  }

  void completeRelationDelete() {
    const revision = TestDetailsRevision(1);
    _relationDeleted = true;
    repository.completeRelationCommand(
      completedRelationCommands++,
      GraphCommandSucceeded(
        ConfirmedGraphResult(
          revision: revision,
          value: LongTermRelationDeleted(
            relation: relationDetails.relation,
            changes: [
              LongTermRelationDeletedChange(
                revision: revision,
                relation: relationDetails.relation,
              ),
              for (final id in [
                relationDetails.source.id,
                relationDetails.related.id,
              ])
                IntentionRelationCountsChanged(
                  revision: revision,
                  intentionId: id,
                  counts: testRelationCounts(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> archive(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(_archive));
    await tester.tap(find.byKey(_archive));
    await tester.pump();
    expect(repository.commands.last, isA<ArchiveIntention>());
    expect(coordinator.isRunning(intention.id), isTrue);
  }

  Future<void> delete(WidgetTester tester) async {
    final delete = find.byKey(const ValueKey('intention-details-delete'));
    await tester.ensureVisible(delete);
    await tester.tap(delete);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('intention-details-confirm-delete')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(repository.commands.single, isA<DeleteIntention>());
    expect(coordinator.isRunning(intention.id), isTrue);
  }

  void complete(Result<IntentionCommandSuccess> result) {
    repository.completeCommand(completedCommands++, result);
  }
}
