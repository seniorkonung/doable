import 'package:auto_route/auto_route.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/design_system/components/badge.dart';
import 'package:doable/src/design_system/components/option_row.dart';
import 'package:doable/src/design_system/components/page_head.dart';
import 'package:doable/src/design_system/components/sheet.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/presentation/graph_operation_presenter.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/edit/intention_edit_page.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:flutter/material.dart' hide Badge;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/ordinary_page_test_app.dart';
import 'details_test_support.dart';

void main() {
  setUp(() {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  testWidgets('кнопки параметров нет при загрузке и отказе чтения, а после '
      'получения подробных данных она есть', (tester) async {
    final semantics = tester.ensureSemantics();
    final repository = ControlledDetailsRepository();
    final intention = testDetailsIntention();
    await _pumpPage(tester, repository, intention);
    await waitForDetailRequests(repository, 1);
    expect(_optionsButton, findsNothing);

    repository.detailRequests.single.add(
      const ResultFailure(IntentionUnavailableFailure()),
    );
    await tester.pumpAndSettle();
    expect(_optionsButton, findsNothing);

    await tester.tap(find.text('Повторить'));
    await waitForDetailRequests(repository, 2);
    repository.detailRequests[1].add(ResultSuccess(intention));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(_optionsButton),
      isSemantics(
        label: 'Параметры намерения',
        isButton: true,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('архивирование из параметров: лист «Намерение» поясняет '
      'архивирование связей, выбор сразу архивирует, а шапка показывает '
      'архивное состояние', (tester) async {
    final repository = ControlledDetailsRepository();
    final intention = testDetailsIntention(title: 'Бегать');
    final archived = testDetailsIntention(
      title: 'Бегать',
      archiveState: IntentionArchiveState.archived,
    );
    await _openLoaded(
      tester,
      repository,
      intention,
      counts: testRelationCounts(activeNeedIncoming: 1),
    );

    await _openOptions(tester);
    expect(
      find.descendant(of: find.byType(Sheet), matching: find.text('Намерение')),
      findsOneWidget,
    );
    expect(_rows(tester).map((row) => (row.name, row.hint)), [
      ('Изменить', null),
      ('Архивировать', 'Его связи архивируются вместе с ним'),
      ('Удалить', 'Сначала удалите его связи'),
    ]);

    await _choose(tester, 'Архивировать');
    expect(find.byType(Sheet), findsNothing);
    expect(find.byType(Dialog), findsNothing);
    expect(repository.commands.single, isA<ArchiveIntention>());

    repository.completeCommand(
      0,
      testDetailsSavedResult(archived, before: intention),
    );
    await tester.pump();
    await waitForDetailRequests(repository, 2);
    repository.detailRequests[1].add(ResultSuccess(archived));
    await tester.pumpAndSettle();
    final head = tester.widget<PageHead>(find.byType(PageHead));
    expect(head.muted, isTrue);
    expect(head.badge, isA<Badge>());
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('отказ архивирования из параметров показан общим сообщением, а '
      'намерение остаётся активным', (tester) async {
    final repository = ControlledDetailsRepository();
    final intention = testDetailsIntention(title: 'Бегать');
    await _openLoaded(
      tester,
      repository,
      intention,
      locale: const Locale('en'),
    );

    await _openOptions(tester, label: 'Options of the intention');
    await _choose(tester, 'Archive');
    repository.completeCommand(
      0,
      const ResultFailure(IntentionUnavailableFailure()),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Archive — “Бегать”: The intention state couldn’t be changed. '
        'Try again.',
      ),
      findsOneWidget,
    );
    expect(tester.widget<PageHead>(find.byType(PageHead)).badge, isNull);
  });

  testWidgets('восстановление из параметров сразу восстанавливает '
      'архивированное намерение', (tester) async {
    final repository = ControlledDetailsRepository();
    final archived = testDetailsIntention(
      archiveState: IntentionArchiveState.archived,
    );
    await _openLoaded(tester, repository, archived);

    await _openOptions(tester);
    await _choose(tester, 'Восстановить из архива');

    expect(find.byType(Sheet), findsNothing);
    expect(repository.commands.single, isA<RestoreIntention>());
  });

  testWidgets('«Изменить» открывает экран изменения с курсором в конце '
      'названия', (tester) async {
    final repository = ControlledDetailsRepository();
    final intention = testDetailsIntention(title: 'Бегать');
    await _openLoaded(tester, repository, intention);

    await _openOptions(tester);
    await _choose(tester, 'Изменить');
    await tester.pumpAndSettle();

    expect(find.byType(Sheet), findsNothing);
    expect(find.byType(IntentionEditPage), findsOneWidget);
    final title = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey('intention-edit-title')),
        matching: find.byType(EditableText),
      ),
    );
    expect(title.controller.text, 'Бегать');
    expect(title.focusNode.hasFocus, isTrue);
    expect(
      title.controller.selection,
      const TextSelection.collapsed(offset: 'Бегать'.length),
    );
  });

  testWidgets('выбор «Архивировать» отбрасывается, если до окончания '
      'закрытия листа над страницей открыт второй лист', (tester) async {
    final repository = ControlledDetailsRepository();
    await _openLoaded(tester, repository, testDetailsIntention());

    await _openOptions(tester);
    await tester.tap(_inSheet('Архивировать'));
    await tester.pump();
    await tester.tap(_optionsButton);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(repository.commands, isEmpty);
    expect(find.byType(Sheet), findsOneWidget);
    expect(_rows(tester).map((row) => row.name), contains('Архивировать'));
  });

  testWidgets('во время изменяющей операции открытый лист не даёт выбрать '
      'пункты, а после её окончания открывает их', (tester) async {
    final repository = ControlledDetailsRepository();
    final intention = testDetailsIntention(title: 'Бегать');
    final ready = testDetailsIntention(
      title: 'Бегать',
      readiness: IntentionReadiness.ready,
    );
    await _openLoaded(tester, repository, intention);
    await tester.tap(find.text('Действие').last);
    await tester.pump();
    expect(repository.commands.single, isA<EnableIntentionReadiness>());

    await _openOptions(tester, settle: false);
    expect(_rows(tester).map((row) => row.onPressed), everyElement(isNull));
    expect(
      _rows(tester).map((row) => row.hint),
      everyElement('Дождитесь окончания текущего изменения'),
    );
    await tester.tap(_inSheet('Изменить'), warnIfMissed: false);
    // Индикатор выполняющейся команды не даёт кадрам успокоиться.
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(Sheet), findsOneWidget);
    expect(find.byType(IntentionEditPage), findsNothing);

    repository.completeCommand(
      0,
      testDetailsSavedResult(ready, before: intention),
    );
    await tester.pump();
    await waitForDetailRequests(repository, 2);
    repository.detailRequests[1].add(ResultSuccess(ready));
    await tester.pumpAndSettle();
    expect(find.byType(Sheet), findsOneWidget);
    expect(_rows(tester).map((row) => row.onPressed), everyElement(isNotNull));
  });

  testWidgets('подтверждённое удаление активного намерения удаляет его и '
      'закрывает страницу', (tester) async {
    final repository = ControlledDetailsRepository();
    final intention = testDetailsIntention(title: 'Бегать');
    await _openLoaded(tester, repository, intention);

    await _openOptions(tester);
    expect(_rows(tester).last.hint, 'Его теги сохранятся');
    await _choose(tester, 'Удалить');
    expect(find.byType(Sheet), findsNothing);
    expect(find.text('Удалить намерение?'), findsOneWidget);
    expect(
      find.text(
        'Намерение Бегать будет безвозвратно удалено вместе с описанием. '
        'Его теги сохранятся.',
        findRichText: true,
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(of: find.byType(Dialog), matching: find.text('Удалить')),
    );
    await tester.pump();
    expect(repository.commands.single, isA<DeleteIntention>());
    repository.completeCommand(0, testDetailsDeletedResult(intention));
    await tester.pumpAndSettle();
    expect(find.byType(IntentionDetailsPage), findsNothing);
  });

  testWidgets('отмена удаления сохраняет намерение', (tester) async {
    final repository = ControlledDetailsRepository();
    final intention = testDetailsIntention(title: 'Бегать');
    await _openLoaded(tester, repository, intention);

    await _openOptions(tester);
    await _choose(tester, 'Удалить');
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();

    expect(find.text('Удалить намерение?'), findsNothing);
    expect(repository.commands, isEmpty);
    expect(find.widgetWithText(PageHead, 'Бегать'), findsOneWidget);
  });

  for (final (scenario, counts, reason) in [
    (
      'архивированная входящая связь',
      testRelationCounts(archivedCanIncoming: 1),
      'Сначала удалите его связи',
    ),
    (
      'дневной выбор, начатый намерением,',
      testRelationCounts(dailySource: 1),
      'Сначала удалите его дневные выборы',
    ),
    (
      'дневной выбор, выбравший намерение,',
      testRelationCounts(dailySelected: 1),
      'Сначала удалите его дневные выборы',
    ),
  ]) {
    testWidgets('$scenario блокирует удаление: «Удалить» выключено и называет '
        'причину', (tester) async {
      final repository = ControlledDetailsRepository();
      await _openLoaded(
        tester,
        repository,
        testDetailsIntention(),
        counts: counts,
      );

      await _openOptions(tester);
      final delete = _rows(tester).last;
      expect(delete.onPressed, isNull);
      expect(delete.hint, reason);
      await tester.tap(_inSheet('Удалить'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(Sheet), findsOneWidget);
      expect(find.text('Удалить намерение?'), findsNothing);
      expect(repository.commands, isEmpty);
    });
  }

  testWidgets('утрата подробных данных закрывает открытый лист', (
    tester,
  ) async {
    final repository = ControlledDetailsRepository();
    await _openLoaded(tester, repository, testDetailsIntention());

    await _openOptions(tester);
    repository.detailRequests.single.add(
      const ResultFailure(IntentionUnavailableFailure()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Sheet), findsNothing);
    expect(_optionsButton, findsNothing);
    // Затемнение листа больше не перехватывает нажатия на странице.
    await tester.tap(find.text('Повторить'));
    await tester.pump();
    expect(repository.detailRequests, hasLength(2));
  });
}

Finder _inSheet(String text) =>
    find.descendant(of: find.byType(Sheet), matching: find.text(text));

/// Выбор закрывает лист; действие может запустить индикатор выполнения,
/// который не даёт кадрам успокоиться.
Future<void> _choose(WidgetTester tester, String name) async {
  await tester.tap(_inSheet(name));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

Finder get _optionsButton => find.bySemanticsLabel('Параметры намерения');

List<OptionRow> _rows(WidgetTester tester) => tester
    .widgetList<OptionRow>(
      find.descendant(of: find.byType(Sheet), matching: find.byType(OptionRow)),
    )
    .toList();

Future<void> _openOptions(
  WidgetTester tester, {
  String label = 'Параметры намерения',
  bool settle = true,
}) async {
  await tester.tap(find.bySemanticsLabel(label));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }
}

Future<void> _openLoaded(
  WidgetTester tester,
  ControlledDetailsRepository repository,
  Intention intention, {
  Locale locale = const Locale('ru'),
  RelationCounts? counts,
}) async {
  await _pumpPage(tester, repository, intention, locale: locale);
  await waitForDetailRequests(repository, 1);
  repository.detailRequests.single.add(
    ResultSuccess(intention),
    relationCounts: counts,
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpPage(
  WidgetTester tester,
  ControlledDetailsRepository repository,
  Intention intention, {
  Locale locale = const Locale('ru'),
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
      retry: (retryCount, error) => null,
      child: OrdinaryPageTestApp(
        locale: locale,
        routes: [AutoRoute(page: IntentionEditRoute.page)],
        builder: (context, child) =>
            GraphOperationPresenter(child: child ?? const SizedBox.shrink()),
        home: IntentionDetailsPage(intentionId: intention.id),
      ),
    ),
  );
  await tester.pump();
}
