import 'package:auto_route/auto_route.dart';
import 'package:doable/src/action/application/action_details.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/design_system/components/action_head.dart';
import 'package:doable/src/design_system/components/action_path.dart' as ui;
import 'package:doable/src/design_system/components/detail_row.dart';
import 'package:doable/src/design_system/doable_priority.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/action_panel_controls.dart';
import '../../../support/action_panel_fixture.dart';

void main() {
  setUp(() {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  testWidgets('панель открывается на «Обзоре», а «Путь» показывает путь только '
      'для чтения и называет число намерений', (tester) async {
    final semantics = tester.ensureSemantics();
    final repository = await openActionPanel(tester);
    repository.emit(actionDetailsFixture(pathLength: 3));
    await tester.pumpAndSettle();

    expect(_overviewFields, findsOneWidget);
    expect(find.byType(ui.ActionPath), findsNothing);
    expect(find.bySemanticsLabel('Путь, 3 намерения'), findsOneWidget);

    await _openPathTab(tester);

    expect(_overviewFields, findsNothing);
    expect(_pathNames(tester), ['Быть здоровым', 'Намерение 2', 'Намерение 3']);
    expect(find.text('Нужно'), findsNWidgets(2));
    expect(find.text('В архиве'), findsNothing);
    expect(find.text('Удалено'), findsNothing);
    semantics.dispose();
  });

  testWidgets('путь показывает текущие названия и данные связей в прежнем '
      'порядке', (tester) async {
    final repository = await openActionPanel(tester);
    repository.emit(actionDetailsFixture(pathLength: 2));
    await tester.pumpAndSettle();
    await _openPathTab(tester);

    repository.emit(
      _details(_intention(1, 'Быть здоровым'), [
        (
          link: _existingLink(
            1,
            type: LongTermRelationType.can,
            priority: RelationPriority.p3,
          ),
          intention: _intention(2, 'Ходить пешком'),
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(_pathNames(tester), ['Быть здоровым', 'Ходить пешком']);
    expect(find.text('Можно'), findsOneWidget);
    expect(find.text('Нужно'), findsNothing);
    final relation =
        _pathLinks(tester).single.relation as ui.ActionPathExistingRelation;
    expect(relation.priority, DoablePriority.p3);
  });

  testWidgets('архивные намерение и связь остаются на местах с отметкой «В '
      'архиве», вкладка несёт отметку архива, а под путём стоит строка', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final repository = await openActionPanel(tester);
    repository.emit(
      _details(_intention(1, 'Быть здоровым'), [
        (
          link: _existingLink(
            1,
            type: LongTermRelationType.can,
            priority: RelationPriority.p3,
            scope: RelationScope.archived,
          ),
          intention: _intention(2, 'Много ходить', archived: true),
        ),
      ]),
    );
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel('Путь, 2 намерения, в пути есть архив'),
      findsOneWidget,
    );

    await _openPathTab(tester);

    expect(_pathNames(tester), ['Быть здоровым', 'Много ходить']);
    expect(find.text('В архиве'), findsNWidgets(2));
    final path = tester.widget<ui.ActionPath>(find.byType(ui.ActionPath));
    expect((path.root as ui.ActionPathExistingStep).archived, isFalse);
    final relation =
        _pathLinks(tester).single.relation as ui.ActionPathExistingRelation;
    expect(relation.archived, isTrue);
    expect(relation.kind, ui.ActionPathRelationKind.can);
    expect(relation.priority, DoablePriority.p3);
    expect(find.text('Удалено'), findsNothing);
    expect(
      find.text('Архивные намерения и связи остаются в сохранённом пути.'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('удалённые намерение и связь остаются с названием и типом при '
      'удалении, не открываются и не помечают вкладку архивом', (tester) async {
    final semantics = tester.ensureSemantics();
    final repository = await openActionPanel(tester, routes: [_intentionPage]);
    repository.emit(
      _details(_intention(1, 'Быть здоровым'), [
        (
          link: const DeletedActionPathLink(LongTermRelationType.need),
          intention: DeletedActionPathIntention(
            id: intentionIdOf(12),
            title: 'Ходить пешком',
          ),
        ),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Путь, 2 намерения'), findsOneWidget);
    await _openPathTab(tester);

    expect(_pathNames(tester), ['Быть здоровым', 'Ходить пешком']);
    expect(find.text('Нужно'), findsOneWidget);
    expect(find.text('Удалено'), findsNWidgets(2));
    expect(
      find.text(
        'Удалённые намерения и связи остаются в сохранённом пути такими, '
        'какими были.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Ходить пешком'));
    await tester.tap(find.text('Нужно'));
    await tester.pumpAndSettle();

    expect(repository.watchedRelations, isEmpty);
    expect(find.textContaining(_openedIntentionPrefix), findsNothing);
    semantics.dispose();
  });

  testWidgets('архивные и удалённые звенья вместе называются одной строкой', (
    tester,
  ) async {
    final repository = await openActionPanel(tester);
    repository.emit(
      _details(_intention(1, 'Быть здоровым', archived: true), [
        (
          link: const DeletedActionPathLink(LongTermRelationType.need),
          intention: DeletedActionPathIntention(
            id: intentionIdOf(12),
            title: 'Ходить пешком',
          ),
        ),
      ]),
    );
    await tester.pumpAndSettle();
    await _openPathTab(tester);

    expect(
      find.text(
        'Архивные и удалённые намерения и связи остаются в '
        'сохранённом пути.',
      ),
      findsOneWidget,
    );
  });

  for (final (name, root, mark) in <(String, ActionPathIntention, String)>[
    ('архивное', _intention(1, 'Быть здоровым', archived: true), 'В архиве'),
    (
      'удалённое',
      DeletedActionPathIntention(id: intentionIdOf(11), title: 'Быть здоровым'),
      'Удалено',
    ),
  ]) {
    testWidgets('$name корневое намерение несёт в шапке отметку «$mark»', (
      tester,
    ) async {
      final repository = await openActionPanel(tester);
      repository.emit(_details(root, const []));
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: actionPanelReady, matching: find.text(mark)),
        findsOneWidget,
      );
    });
  }

  testWidgets('нажатие на корень с цепочкой в шапке открывает «Путь», где этот '
      'элемент не действует', (tester) async {
    final repository = await openActionPanel(tester);
    repository.emit(actionDetailsFixture(pathLength: 2));
    await tester.pumpAndSettle();
    expect(shownActionHead(tester).path, isA<ActionHeadButtonAvailable>());

    await tester.tap(
      find.descendant(
        of: actionPanelReady,
        matching: find.text('Быть здоровым'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ui.ActionPath), findsOneWidget);
    expect(_overviewFields, findsNothing);
    expect(shownActionHead(tester).path, isA<ActionHeadButtonUnavailable>());

    await tester.tap(find.text('Обзор'));
    await tester.pumpAndSettle();

    expect(_overviewFields, findsOneWidget);
    expect(shownActionHead(tester).path, isA<ActionHeadButtonAvailable>());
  });

  testWidgets('существующие намерение и связь открываются поверх панели, а '
      'возврат показывает «Путь»', (tester) async {
    final repository = await openActionPanel(tester, routes: [_intentionPage]);
    repository.emit(actionDetailsFixture(pathLength: 3));
    await tester.pumpAndSettle();
    await _openPathTab(tester);

    await tester.tap(find.text('Нужно').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(repository.watchedRelations, [relationIdOf(101)]);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ui.ActionPath), findsOneWidget);

    await tester.tap(find.text('Намерение 2'));
    await tester.pumpAndSettle();
    expect(
      find.text('$_openedIntentionPrefix${intentionIdOf(11)}'),
      findsOneWidget,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(ui.ActionPath), findsOneWidget);
    expect(_overviewFields, findsNothing);
  });

  testWidgets('изменение названия, начатое на «Пути», возвращает «Путь»', (
    tester,
  ) async {
    final repository = await openActionPanel(tester);
    repository.emit(actionDetailsFixture(title: 'Пробежка'));
    await tester.pumpAndSettle();
    await _openPathTab(tester);

    await tester.tap(
      find.descendant(of: actionPanelReady, matching: find.text('Пробежка')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Изменить действие'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Назад к действию'));
    await tester.pumpAndSettle();

    expect(find.byType(ui.ActionPath), findsOneWidget);
    expect(_overviewFields, findsNothing);
  });
}

/// Поля вкладки «Обзор»; на вкладке «Путь» их нет.
Finder get _overviewFields => find.widgetWithText(DetailRow, 'Дата');

Future<void> _openPathTab(WidgetTester tester) async {
  await tester.tap(find.text('Путь'));
  await tester.pumpAndSettle();
}

/// Названия намерений пути от корневого до конечного.
List<String> _pathNames(WidgetTester tester) {
  final path = tester.widget<ui.ActionPath>(find.byType(ui.ActionPath));
  return [path.root.name, for (final link in path.links) link.step.name];
}

List<ui.ActionPathLink> _pathLinks(WidgetTester tester) =>
    tester.widget<ui.ActionPath>(find.byType(ui.ActionPath)).links;

const _openedIntentionPrefix = 'Страница намерения ';

/// Страница намерения, которую панель открывает поверх себя.
final _intentionPage = NamedRouteDef(
  name: IntentionDetailsRoute.name,
  builder: (_, data) => Scaffold(
    body: Text(
      '$_openedIntentionPrefix'
      '${data.argsAs<IntentionDetailsRouteArgs>().intentionId}',
    ),
  ),
);

ActionPathIntention _intention(
  int number,
  String title, {
  bool archived = false,
}) => ExistingActionPathIntention(
  Intention(
    id: intentionIdOf(10 + number),
    title: title,
    description: null,
    kind: IntentionKind.main,
    archiveState: archived
        ? IntentionArchiveState.archived
        : IntentionArchiveState.active,
    createdAt: IntentionTimestamp(DateTime.utc(2026, 10, 6)),
    updatedAt: IntentionTimestamp(DateTime.utc(2026, 10, 6)),
  ),
);

/// Связь между намерениями [number] и [number] + 1 пути.
ActionPathLink _existingLink(
  int number, {
  required LongTermRelationType type,
  required RelationPriority priority,
  RelationScope scope = RelationScope.active,
}) => ExistingActionPathLink(
  LongTermRelation(
    id: relationIdOf(100 + number),
    sourceIntentionId: intentionIdOf(10 + number),
    relatedIntentionId: intentionIdOf(11 + number),
    type: type,
    priority: priority,
    scope: scope,
    creationSequence: RelationCreationSequence(number),
    createdAt: RelationTimestamp(DateTime.utc(2026, 10, 6)),
    updatedAt: RelationTimestamp(DateTime.utc(2026, 10, 6)),
  ),
);

/// Действие с сохранённым путём из корня и шагов.
ActionDetails _details(
  ActionPathIntention root,
  List<({ActionPathLink link, ActionPathIntention intention})> steps,
) => ActionDetails(
  action: actionDetailsFixture().action,
  path: ActionSavedPath(
    root: root,
    steps: [
      for (final step in steps)
        ActionPathStep(link: step.link, intention: step.intention),
    ],
  ),
);
