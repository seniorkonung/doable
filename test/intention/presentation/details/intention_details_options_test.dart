import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/design_system/components/badge.dart';
import 'package:doable/src/design_system/components/option_row.dart';
import 'package:doable/src/design_system/components/page_head.dart';
import 'package:doable/src/design_system/components/sheet.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/presentation/graph_operation_presenter.dart';
import 'package:doable/src/intention/application/cascade/intention_cascade.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/edit/intention_edit_page.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:flutter/material.dart' hide Badge;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/intention_cascade_execution.dart';
import '../../../support/ordinary_page_test_app.dart';
import 'details_test_support.dart';

void main() {
  setUp(() {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  testWidgets('архивирование предлагает оставить вспомогательное главным', (
    tester,
  ) async {
    final child = testDetailsIntentionId(2);
    final withSupporting = ArchiveCascadeComposition(
      departing: [child],
      promoted: [],
      mainsLosingRelation: [],
      archivedRelationCount: 1,
    );
    final onlyThis = ArchiveCascadeComposition(
      departing: [],
      promoted: [child],
      mainsLosingRelation: [],
      archivedRelationCount: 1,
    );
    final preview = ArchiveCascadePreview(
      revision: const TestDetailsRevision(0),
      plan: CascadePlan(
        withSupporting: withSupporting,
        onlyThis: onlyThis,
        asksQuestion: true,
      ),
      titles: {child: 'Много ходить'},
    );
    final repository = ControlledDetailsRepository()
      ..onPreviewCascade = (subject, operation) =>
          operation == CascadeOperation.archive
          ? preview
          : givenCascadePreview(
              subject,
              operation,
              const TestDetailsRevision(0),
            );
    await _openLoaded(tester, repository, testDetailsIntention());
    await _openOptions(tester);
    await _choose(tester, 'Архивировать');
    expect(find.byType(Dialog), findsOneWidget);
    expect(repository.commands, isEmpty);
    await tester.tap(find.text('Только это'));
    await tester.pump();
    final execution =
        (repository.commands.single as ArchiveIntention).execution;
    expect(execution.choice, CascadeChoice.onlyThis);
    expect(execution.expected, same(onlyThis));
  });

  testWidgets('отмена вопроса не архивирует намерение', (tester) async {
    final child = testDetailsIntentionId(2);
    final composition = ArchiveCascadeComposition(
      departing: [child],
      promoted: [],
      mainsLosingRelation: [],
      archivedRelationCount: 1,
    );
    final repository = ControlledDetailsRepository()
      ..onPreviewCascade = (subject, operation) =>
          operation == CascadeOperation.archive
          ? ArchiveCascadePreview(
              revision: const TestDetailsRevision(0),
              plan: CascadePlan(
                withSupporting: composition,
                onlyThis: composition,
                asksQuestion: true,
              ),
              titles: {child: 'Много ходить'},
            )
          : givenCascadePreview(
              subject,
              operation,
              const TestDetailsRevision(0),
            );
    await _openLoaded(tester, repository, testDetailsIntention());
    await _openOptions(tester);
    expect(
      _rows(tester)[1].hint,
      'Вместе с ним в архив уйдут вспомогательные намерения: 1',
    );
    await _choose(tester, 'Архивировать');
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(repository.commands, isEmpty);
  });

  testWidgets('архивирование со вспомогательными передаёт состав каскада', (
    tester,
  ) async {
    final child = testDetailsIntentionId(2);
    final composition = ArchiveCascadeComposition(
      departing: [child],
      promoted: [],
      mainsLosingRelation: [],
      archivedRelationCount: 1,
    );
    final repository = ControlledDetailsRepository()
      ..onPreviewCascade = (subject, operation) =>
          operation == CascadeOperation.archive
          ? ArchiveCascadePreview(
              revision: const TestDetailsRevision(0),
              plan: CascadePlan(
                withSupporting: composition,
                onlyThis: composition,
                asksQuestion: true,
              ),
              titles: {child: 'Много ходить'},
            )
          : givenCascadePreview(
              subject,
              operation,
              const TestDetailsRevision(0),
            );
    await _openLoaded(tester, repository, testDetailsIntention());
    await _openOptions(tester);
    await _choose(tester, 'Архивировать');
    await tester.tap(find.text('Со вспомогательными'));
    await tester.pump();
    final execution =
        (repository.commands.single as ArchiveIntention).execution;
    expect(execution.choice, CascadeChoice.withSupporting);
    expect(execution.expected, same(composition));
  });

  testWidgets('лист объясняет удаление намерения из сохранённого пути', (
    tester,
  ) async {
    final repository = ControlledDetailsRepository()
      ..onPreviewCascade = (subject, operation) {
        final preview = givenCascadePreview(
          subject,
          operation,
          const TestDetailsRevision(0),
        );
        if (preview is IntentionDeleteCascadePreview) {
          return IntentionDeleteCascadePreview(
            revision: preview.revision,
            plan: preview.plan,
            titles: const {},
            isInActionPath: true,
          );
        }
        return preview;
      };
    await _openLoaded(tester, repository, testDetailsIntention());
    await _openOptions(tester);
    expect(
      _rows(tester).last.hint,
      'В сохранённых путях останется с пометкой «Удалено»',
    );
  });

  testWidgets(
    'пока предпросмотр читается и после отказа пункты доступны без пояснений',
    (tester) async {
      final pending = Completer<CascadePreviewResult>();
      final repository = ControlledDetailsRepository()
        ..onPreviewCascade = (_, _) => pending.future;
      await _openLoaded(tester, repository, testDetailsIntention());
      await _openOptions(tester);
      expect(
        _rows(tester).skip(1).map((row) => row.hint),
        everyElement(isNull),
      );
      expect(
        _rows(tester).skip(1).map((row) => row.onPressed),
        everyElement(isNotNull),
      );
      pending.complete(const CascadePreviewUnavailable());
      await tester.pumpAndSettle();
      expect(
        _rows(tester).skip(1).map((row) => row.hint),
        everyElement(isNull),
      );
      expect(
        _rows(tester).skip(1).map((row) => row.onPressed),
        everyElement(isNotNull),
      );
    },
  );

  testWidgets(
    'восстановление только этого намерения оставляет вспомогательное в архиве',
    (tester) async {
      final child = testDetailsIntentionId(2);
      final together = RestoreCascadeComposition(
        restored: [child],
        returnedAsMain: null,
        restoredRelationCount: 1,
      );
      final alone = RestoreCascadeComposition(
        restored: [],
        returnedAsMain: null,
        restoredRelationCount: 0,
      );
      final repository = ControlledDetailsRepository()
        ..onPreviewCascade = (subject, operation) =>
            operation == CascadeOperation.restore
            ? RestoreCascadePreview(
                revision: const TestDetailsRevision(0),
                plan: CascadePlan(
                  withSupporting: together,
                  onlyThis: alone,
                  asksQuestion: true,
                ),
                titles: {child: 'Много ходить'},
              )
            : givenCascadePreview(
                subject,
                operation,
                const TestDetailsRevision(0),
              );
      await _openLoaded(
        tester,
        repository,
        testDetailsIntention(archiveState: IntentionArchiveState.archived),
      );
      await _openOptions(tester);
      expect(
        _rows(tester)[1].hint,
        'Вместе с ним вернутся вспомогательные намерения: 1',
      );
      await _choose(tester, 'Восстановить из архива');
      expect(
        find.text('Вместе с ним вернутся вспомогательные намерения: 1.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Только это'));
      await tester.pump();
      final execution =
          (repository.commands.single as RestoreIntention).execution;
      expect(execution.choice, CascadeChoice.onlyThis);
      expect(execution.expected, same(alone));
    },
  );

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
    final composition = ArchiveCascadeComposition(
      departing: [],
      promoted: [],
      mainsLosingRelation: [],
      archivedRelationCount: 1,
    );
    final preview = ArchiveCascadePreview(
      revision: const TestDetailsRevision(0),
      plan: CascadePlan(
        withSupporting: composition,
        onlyThis: composition,
        asksQuestion: false,
      ),
      titles: const {},
    );
    repository.onPreviewCascade = (subject, operation) =>
        operation == CascadeOperation.archive
        ? preview
        : givenCascadePreview(subject, operation, const TestDetailsRevision(0));
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
      ('Удалить', 'Его теги сохранятся'),
    ]);

    await _choose(tester, 'Архивировать');
    expect(find.byType(Sheet), findsNothing);
    expect(find.byType(Dialog), findsNothing);
    final execution =
        (repository.commands.single as ArchiveIntention).execution;
    expect(execution.choice, CascadeChoice.withSupporting);
    expect(execution.expected, same(preview.plan.withSupporting));

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

  testWidgets('отказ чтения предпросмотра при «Архивировать» показан общим '
      'сообщением ровно один раз, а команда архивирования не выполнена', (
    tester,
  ) async {
    final repository = ControlledDetailsRepository()
      ..onPreviewCascade = (_, _) => const CascadePreviewUnavailable();
    final intention = testDetailsIntention(title: 'Бегать');
    await _openLoaded(
      tester,
      repository,
      intention,
      locale: const Locale('en'),
    );

    await _openOptions(tester, label: 'Options of the intention');
    await _choose(tester, 'Archive');
    await tester.pumpAndSettle();

    expect(repository.commands, isEmpty);
    expect(
      find.text(
        'Archive — “Бегать”: The intention state couldn’t be changed. '
        'Try again.',
      ),
      findsOneWidget,
    );
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
      kind: IntentionKind.supporting,
    );
    await _openLoaded(
      tester,
      repository,
      intention,
      counts: testRelationCounts(activeNeedIncoming: 1),
    );
    await tester.tap(find.text('Вспомогательное'));
    await tester.pump();
    expect(repository.commands.single, isA<ChangeIntentionKind>());

    await _openOptions(tester, settle: false);
    expect(_rows(tester).map((row) => row.onPressed), everyElement(isNull));
    expect(_rows(tester).map((row) => row.hint), [
      'Дождитесь окончания текущего изменения',
      'Дождитесь окончания текущего изменения',
      'Дождитесь окончания текущего изменения',
    ]);
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
    repository.detailRequests[1].add(
      ResultSuccess(ready),
      relationCounts: testRelationCounts(activeNeedIncoming: 1),
    );
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

  testWidgets('связи не блокируют удаление: «Удалить» доступно и '
      'спрашивает подтверждение', (tester) async {
    final repository = ControlledDetailsRepository();
    await _openLoaded(
      tester,
      repository,
      testDetailsIntention(title: 'Бегать'),
      counts: testRelationCounts(activeNeedOutgoing: 1, archivedCanIncoming: 1),
    );

    await _openOptions(tester);
    final delete = _rows(tester).last;
    expect(delete.onPressed, isNotNull);
    expect(delete.hint, 'Его теги сохранятся');
    await _choose(tester, 'Удалить');
    await tester.tap(
      find.descendant(of: find.byType(Dialog), matching: find.text('Удалить')),
    );
    await tester.pump();

    expect(repository.commands.single, isA<DeleteIntention>());
  });

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
