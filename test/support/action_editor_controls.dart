/// Лист нового действия над обычной страницей и репозиторий его команд.
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:doable/src/action/application/action_command.dart';
import 'package:doable/src/action/application/action_day_statuses.dart';
import 'package:doable/src/action/application/action_result.dart';
import 'package:doable/src/action/domain/action.dart';
import 'package:doable/src/action/presentation/editor/action_editor_page.dart';
import 'package:doable/src/action/presentation/editor/action_editor_state.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/presentation/graph_operation_presenter.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:doable/src/shared/presentation/local_day/local_date_provider.dart';
import 'package:flutter/material.dart' hide Action;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'action_panel_fixture.dart';
import 'action_read_contract_test_fallback.dart';
import 'controlled_local_date.dart';
import 'ordinary_page_test_app.dart';
import 'tag_read_contract_test_fallback.dart';

/// Открытый лист нового действия.
Finder get actionEditor => find.byType(ActionEditorPage);

/// Поле названия листа.
Finder get actionEditorTitleField => find
    .descendant(of: actionEditor, matching: find.byType(EditableText))
    .first;

/// Поле описания листа.
Finder get actionEditorDescriptionField =>
    find.descendant(of: actionEditor, matching: find.byType(EditableText)).last;

/// Кнопка «Создать действие».
Finder get actionEditorCreateButton => find.descendant(
  of: actionEditor,
  matching: find.widgetWithText(FilledButton, 'Создать действие'),
);

/// Доступна ли «Создать действие».
bool actionEditorCanCreate(WidgetTester tester) =>
    tester.widget<FilledButton>(actionEditorCreateButton).onPressed != null;

/// Значение [value] в листе.
Finder actionEditorValue(String value) =>
    find.descendant(of: actionEditor, matching: find.text(value));

/// Путь из «Быть здоровым» и «Много ходить» по связи «нужно».
ActionDraftPath twoIntentionDraftPath() => ActionDraftPath(
  root: ActionDraftIntention(id: intentionIdOf(11), title: 'Быть здоровым'),
  steps: [
    ActionDraftPathStep(
      relation: LongTermRelationType.need,
      intention: ActionDraftIntention(
        id: intentionIdOf(12),
        title: 'Много ходить',
      ),
    ),
  ],
);

/// Сегодня в листе — 2026-10-08.
final actionEditorToday = CalendarDate.fromParts(2026, 10, 8);

/// Окружение листа: страница с кнопкой «Новое действие», открывающей лист с
/// новым запуском, и репозиторий команд.
final class ActionEditorHarness {
  ActionEditorHarness._(this.repository);

  final ActionEditorRepository repository;

  /// Открывает новый лист с путём [path] и датой [date].
  Future<void> open(
    WidgetTester tester, {
    ActionDraftPath? path,
    CalendarDate? date,
  }) async {
    _path = path;
    _date = date ?? actionEditorToday;
    await tester.tap(find.text('Новое действие'));
    await tester.pumpAndSettle();
    expect(actionEditor, findsOneWidget);
  }

  ActionDraftPath? _path;
  CalendarDate _date = actionEditorToday;

  /// Вводит название и описание.
  Future<void> enterTexts(
    WidgetTester tester, {
    String? title,
    String? description,
  }) async {
    if (title != null) {
      await tester.enterText(actionEditorTitleField, title);
    }
    if (description != null) {
      await tester.enterText(actionEditorDescriptionField, description);
    }
    await tester.pump();
  }

  /// Нажимает «Создать действие» и ждёт принятия команды.
  Future<void> create(WidgetTester tester) async {
    await tester.tap(actionEditorCreateButton);
    await tester.pump();
  }
}

/// Показывает страницу, из которой открывается лист нового действия.
Future<ActionEditorHarness> pumpActionEditorPage(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // Общая поверхность показывает сообщения только видимому приложению.
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  final repository = ActionEditorRepository();
  final harness = ActionEditorHarness._(repository);
  final localDate = ControlledLocalDate(actionEditorToday);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWith((ref) => repository),
        localDateSourceProvider.overrideWithValue(localDate.read),
      ],
      child: OrdinaryPageTestApp(
        locale: const Locale('ru'),
        routes: [
          CustomRoute<void>(
            page: ActionEditorRoute.page,
            customRouteBuilder: actionEditorRoute,
          ),
        ],
        builder: (context, child) =>
            GraphOperationPresenter(child: child ?? const SizedBox.shrink()),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => unawaited(
                  context.router.push(
                    ActionEditorRoute(
                      launch: ActionEditorLaunch(
                        date: harness._date,
                        path: harness._path,
                      ),
                    ),
                  ),
                ),
                child: const Text('Новое действие'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return harness;
}

final class _Change implements GraphChange {
  const _Change(this.revision);

  @override
  final GraphRevision revision;
}

/// Репозиторий листа: команда создания остаётся незавершённой, пока тест не
/// подтвердит или не отклонит её.
final class ActionEditorRepository
    with TagReadContractTestFallback, ActionReadContractTestFallback
    implements PersonalGraphRepository {
  final creations = <CreateAction>[];
  final _requests = <Completer<ActionCommandResult>>[];
  var _revision = 0;

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    creations.add(command as CreateAction);
    final request = Completer<ActionCommandResult>();
    _requests.add(request);
    return await request.future as GraphCommandResult<TSuccess, TFailure>;
  }

  /// Листу даты отметки дней не нужны: ни у одного дня нет действий.
  @override
  Future<ActionDayStatusesReadResult> getActionDayStatuses(
    ActionDayStatusQuery query,
  ) async => ActionDayStatusesReadSuccess(
    GraphSnapshot(
      revision: FixtureRevision(_revision),
      value: ActionDayStatuses(query: query, statuses: const {}),
    ),
  );

  /// Подтверждает последнюю команду создания.
  void succeed() {
    final command = creations.last;
    final created = DateTime.utc(2026, 10, 8, 9);
    _requests.last.complete(
      GraphCommandSucceeded(
        ConfirmedGraphResult(
          revision: FixtureRevision(++_revision),
          value: ActionCreated(
            action: Action(
              id: actionIdOf(creations.length),
              title: command.title,
              description: command.description,
              path: command.path,
              date: command.date,
              schedule: command.schedule,
              priority: command.priority,
              isCompleted: false,
              creationSequence: ActionCreationSequence(creations.length),
              createdAt: ActionTimestamp(created),
              updatedAt: ActionTimestamp(created),
            ),
            changes: [_Change(FixtureRevision(_revision))],
          ),
        ),
      ),
    );
  }

  /// Отклоняет последнюю команду создания.
  void fail(ActionCommandFailure failure) =>
      _requests.last.complete(GraphCommandFailed(failure));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
