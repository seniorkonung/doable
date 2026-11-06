import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/quick_creation/quick_creation_button.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/design_system/components/relation_head.dart';
import 'package:doable/src/design_system/components/sheet.dart';
import 'package:doable/src/design_system/doable_icon.dart';
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
import 'package:doable/src/intention/presentation/details/intention_options.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_page.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../intention/presentation/details/details_test_support.dart';
import '../../long_term_relation/presentation/details/relation_details_test_support.dart'
    show ControlledRelationWatch, testRelationDetails;
import '../../long_term_relation/presentation/relation_graph_test_support.dart'
    show testRelationId;
import '../../support/app_root_pages.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/in_memory_quick_creation_mode_store.dart';
import '../../support/intention_catalog_controls.dart';
import '../../support/intention_options.dart';

const _failure =
    'Архивирование — «Намерение»: Не удалось изменить состояние намерения. Повторите попытку.';
const _deleteSuccess = 'Удаление — «Намерение»: Намерение удалено.';
const _deleteFailure =
    'Удаление — «Намерение»: Не удалось удалить намерение. Повторите попытку.';
const _relationDeleteSuccess = 'Удаление — «связь»: Связь удалена.';

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
      'сохраняет повторно открытую панель той же связи', (tester) async {
    final app = await _ControlledApp.start(tester);
    await app.openRelationSourceDetails(tester);
    await app.openRelationDetails(tester);
    await app.deleteRelation(tester);
    await app.openParticipantAbovePanel(tester);

    await _select(tester, destination, settle: false);
    await app.openRelationSourceDetails(tester);
    await app.openRelationDetails(tester);

    app.completeRelationDelete();
    await _until(
      tester,
      () => !app.coordinator.isRelationRunning(app.relationDetails.relation.id),
    );
    await tester.pumpAndSettle();

    // Панель — не страница: в истории только страница намерения под ней.
    expect(find.byType(Sheet), findsOneWidget);
    expect(app.router.stack.map((page) => page.name), [
      AppShellRoute.name,
      IntentionDetailsRoute.name,
    ]);
    expect(app.router.hasPagelessTopRoute, isTrue);
    final l10n = AppLocalizations.of(tester.element(find.byType(Sheet)));
    expect(find.text(l10n.relationDetailsNotFound), findsOneWidget);
    expect(find.byType(RelationHead), findsNothing);
    _expectSelected(tester, destination);
    // Сообщение показано над нижней частью открытой панели.
    expect(
      find.descendant(
        of: find.byType(Sheet),
        matching: find.text(_relationDeleteSuccess),
      ),
      findsOneWidget,
    );
    await _expireMessages(tester);
    expect(find.byType(Sheet), findsOneWidget);
    expect(
      app.repository.relationCommands.single,
      isA<DeleteLongTermRelation>(),
    );
    expect(app.repository.commands, isEmpty);
    await _systemBack(tester);
    expect(find.byType(Sheet, skipOffstage: false), findsNothing);
    await app.answerSourceReread(tester);
    await _expectSourceActiveRelationCount(tester, 0);
    unawaited(app.router.maybePop());
    await tester.pumpAndSettle();
    _expectRoot(tester, app.router, destination);
  });

  testWidgets('позднее удаление связи после сброса к другому пункту '
      'сохраняет новую страницу намерения до освобождения прежней страницы', (
    tester,
  ) async {
    final app = await _ControlledApp.start(tester);
    await app.openRelationSourceDetails(tester);
    await app.openRelationDetails(tester);
    await app.deleteRelation(tester);
    await app.openParticipantAbovePanel(tester);

    await _select(tester, destination, settle: false);
    await app.openRelationSourceDetails(tester);
    await app.openOtherDetails(tester);

    app.completeRelationDelete();
    await _until(
      tester,
      () => !app.coordinator.isRelationRunning(app.relationDetails.relation.id),
    );
    await tester.pumpAndSettle();

    expect(find.text('Другое намерение'), findsWidgets);
    expect(app.router.stack.map((page) => page.name), [
      AppShellRoute.name,
      IntentionDetailsRoute.name,
      IntentionDetailsRoute.name,
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
    expect(find.byType(Sheet, skipOffstage: false), findsNothing);
    await app.answerSourceReread(tester);
    await _expectSourceActiveRelationCount(tester, 0);
    unawaited(app.router.maybePop());
    await tester.pumpAndSettle();
    _expectRoot(tester, app.router, destination);
  });

  testWidgets('позднее удаление намерения после сброса к другому пункту '
      'сохраняет новую страницу намерения до освобождения прежней страницы', (
    tester,
  ) async {
    final app = await _ControlledApp.start(tester);
    await app.openDetails(tester);
    await app.delete(tester);

    await _select(tester, destination, settle: false);
    await app.openOtherDetails(tester);

    app.complete(
      testDetailsDeletedResult(
        app.intention,
        revision: const TestDetailsRevision(1),
      ),
    );
    await _until(tester, () => !app.coordinator.isRunning(app.intention.id));
    await tester.pumpAndSettle();

    expect(find.text('Другое намерение'), findsWidgets);
    expect(app.router.stack.map((page) => page.name), [
      AppShellRoute.name,
      IntentionDetailsRoute.name,
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
  });

  testWidgets('удаление связи с актуальной верхней страницы закрывает только '
      'её панель и один раз предъявляет результат', (tester) async {
    final app = await _ControlledApp.start(tester);
    await app.openRelationSourceDetails(tester);
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
    expect(app.router.hasPagelessTopRoute, isFalse);
    expect(find.byType(IntentionDetailsPage), findsOneWidget);
    expect(find.byType(Sheet, skipOffstage: false), findsNothing);
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
    final add = intentionCatalogTagFilterControl;
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

  testWidgets('позднее удаление намерения сохраняет панель создания с '
      'несохранённым описанием, открытую после сброса истории', (tester) async {
    const draft = 'Несохранённое описание';
    final app = await _ControlledApp.start(tester);
    await app.openDetails(tester);
    await app.delete(tester);

    await _select(tester, AppDestination.intentionGraph, settle: false);
    // Панель навигации принимает нажатие только после перелёта общего Hero,
    // поэтому кнопку нажимаем в первый же доступный момент.
    final quickCreation = find.byType(QuickCreationButton).hitTestable();
    await _until(tester, () => quickCreation.evaluate().isNotEmpty);
    await tester.tap(quickCreation.first);
    await tester.pump();
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('intention-editor-description')),
      draft,
    );
    await tester.pump();

    app.complete(
      testDetailsDeletedResult(
        app.intention,
        revision: const TestDetailsRevision(1),
      ),
    );
    await _until(tester, () => !app.coordinator.isRunning(app.intention.id));
    await tester.pumpAndSettle();

    expect(find.byType(IntentionEditorPage), findsOneWidget);
    expect(find.text(draft), findsOneWidget);
    expect(
      find.byType(IntentionDetailsPage, skipOffstage: false),
      findsNothing,
    );
    expect(
      tester.widget<AppNavigationBar>(find.byType(AppNavigationBar)).selected,
      AppDestination.intentionGraph,
    );
    // Одно сообщение рисуется в каждом корневом `Scaffold`.
    expect(find.text(_deleteSuccess), findsWidgets);
    await _expireMessages(tester);
    expect(find.text(draft), findsOneWidget);
    expect(app.repository.commands.single, isA<DeleteIntention>());
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
    expect(find.text(_deleteFailure), findsOneWidget);
    await _expireMessages(tester);

    // Повтор — новое удаление с новым токеном.
    await app.delete(tester);
    expect(app.repository.commands, hasLength(2));
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

  testWidgets('ошибка архивирования на открытой странице показана общей '
      'поверхностью один раз и не повторяется после сброса', (tester) async {
    final app = await _ControlledApp.start(tester);
    await app.openDetails(tester);
    await app.archive(tester);
    app.complete(const ResultFailure(IntentionUnavailableFailure()));
    await _until(tester, () => !app.coordinator.isRunning(app.intention.id));
    await tester.pumpAndSettle();
    expect(find.byType(IntentionDetailsPage), findsOneWidget);
    expect(find.text(_failure), findsOneWidget);
    expect(
      find.byType(OperationFailurePresentation, skipOffstage: false),
      findsNothing,
    );

    await _select(tester, AppDestination.home);
    await tester.pumpAndSettle();
    _expectRoot(tester, app.router, AppDestination.home);
    await _expireMessages(tester);
    expect(app.repository.commands, hasLength(1));
  });
}

/// Кнопка параметров в шапке панели связи.
final _relationOptionsButton = find.descendant(
  of: find.byType(RelationHead),
  matching: find.byWidgetPredicate(
    (widget) => widget is DoableIcon && widget.icon == DoableIconData.more,
  ),
);

Future<void> _systemBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
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

/// Вкладка «Связи» страницы исходного намерения подтверждает [count]
/// активных связей без архивированных.
Future<void> _expectSourceActiveRelationCount(
  WidgetTester tester,
  int count,
) async {
  await tester.tap(find.text('Связи').first);
  await tester.pumpAndSettle();
  final l10n = AppLocalizations.of(
    tester.element(find.byType(IntentionDetailsPage)),
  );
  expect(
    find.bySemanticsLabel(l10n.detailsRelationsTabSemantic(count, 0)),
    findsOneWidget,
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
    relationId: testRelationId(1),
    sourceId: testDetailsIntentionId(1),
    relatedId: testDetailsIntentionId(2),
    sourceTitle: 'Намерение',
    relatedTitle: 'Другое намерение',
  );
  final _relationWatches = <ControlledRelationWatch>[];
  var completedCommands = 0;
  var completedRelationCommands = 0;
  var _relationDeleted = false;
  var _answeredDetailRequests = 0;
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
              testDetailsRelationRow(
                ownerId: intention.id,
                index: 1,
                neighborId: relationDetails.related.id,
                neighborTitle: relationDetails.related.title,
              ),
          ],
          counts: counts,
          nextCursor: null,
          revision: TestDetailsRevision(_relationDeleted ? 1 : 0),
        ),
      );
    };
    await _openDetails(tester, intention, activeNeedOutgoing: 1);
    await _expectSourceActiveRelationCount(tester, 1);
  }

  Future<void> _openDetails(
    WidgetTester tester,
    Intention shown, {
    int activeNeedOutgoing = 0,
  }) async {
    final requests = repository.detailRequests.length;
    unawaited(router.push(IntentionDetailsRoute(intentionId: shown.id)));
    await tester.pump();
    await tester.pump();
    await _answerDetails(tester, shown, from: requests, activeNeedOutgoing);
  }

  /// Страница и её соседство наблюдают намерение; общий поток получает
  /// только первая открытая страница, поэтому отвечаем каждому новому запросу
  /// начиная с [from]. Страница, открытая заново до освобождения прежней, тех
  /// же данных не запрашивает.
  Future<void> _answerDetails(
    WidgetTester tester,
    Intention shown,
    int activeNeedOutgoing, {
    required int from,
  }) async {
    for (final request in repository.detailRequests.skip(from)) {
      request.add(
        ResultSuccess(shown),
        relationCounts: testRelationCounts(
          activeNeedOutgoing: activeNeedOutgoing,
        ),
      );
    }
    _answeredDetailRequests = repository.detailRequests.length;
    await tester.pumpAndSettle();
  }

  /// Отвечает перечитыванию страницы исходного намерения после подтверждённого
  /// удаления связи: сводка наблюдения уже не содержит удалённую связь.
  Future<void> answerSourceReread(WidgetTester tester) async {
    for (final request in repository.detailRequests.skip(
      _answeredDetailRequests,
    )) {
      request.add(
        ResultSuccess(intention),
        revision: const TestDetailsRevision(1),
      );
    }
    _answeredDetailRequests = repository.detailRequests.length;
    await tester.pumpAndSettle();
  }

  /// Нажимает на строку связи на странице исходного намерения: панель
  /// открывается над страницей, а чтение связи отвечает [relationDetails].
  Future<void> openRelationDetails(WidgetTester tester) async {
    repository.onWatchRelation = (id) {
      expect(id, relationDetails.relation.id);
      final watch = ControlledRelationWatch(id);
      addTearDown(watch.close);
      _relationWatches.add(watch);
      return watch.stream;
    };
    final row = find.byKey(
      ValueKey(
        'intention-relations-row-${relationDetails.relation.id.toCanonicalString()}',
      ),
    );
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pump();
    await tester.pump();
    _relationWatches.last.emitDetails(
      relationDetails,
      revision: const TestDetailsRevision(0),
    );
    await tester.pumpAndSettle();
    expect(find.byType(RelationHead), findsOneWidget);
  }

  /// Нажимает на название связанного участника панели: страница его
  /// намерения встаёт над панелью, и её панель навигации доступна.
  Future<void> openParticipantAbovePanel(WidgetTester tester) async {
    final requests = repository.detailRequests.length;
    await tester.tap(
      find.descendant(
        of: find.byType(RelationHead),
        matching: find.text(relationDetails.related.title),
      ),
    );
    await tester.pump();
    await tester.pump();
    await _answerDetails(
      tester,
      testDetailsIntention(index: 2, title: relationDetails.related.title),
      0,
      from: requests,
    );
  }

  /// Удаляет связь параметрами панели и подтверждает вопрос.
  Future<void> deleteRelation(WidgetTester tester) async {
    await tester.tap(_relationOptionsButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить'));
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
    await chooseIntentionOption(tester, IntentionOption.archive);
    expect(repository.commands.last, isA<ArchiveIntention>());
    expect(coordinator.isRunning(intention.id), isTrue);
  }

  Future<void> delete(WidgetTester tester) async {
    await chooseIntentionOption(tester, IntentionOption.delete);
    await tester.pumpAndSettle();
    await tester.tap(intentionDeletionConfirm);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(repository.commands.last, isA<DeleteIntention>());
    expect(coordinator.isRunning(intention.id), isTrue);
  }

  void complete(Result<IntentionCommandSuccess> result) {
    repository.completeCommand(completedCommands++, result);
  }
}
