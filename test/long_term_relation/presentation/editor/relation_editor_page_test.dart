import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/presentation/graph_operation_presenter.dart';
import 'package:doable/src/graph/presentation/operation_failure_presentation.dart';
import 'package:doable/src/intention/application/intention_catalog.dart'
    hide IntentionCatalogPage;
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_description.dart';
import 'package:doable/src/long_term_relation/presentation/editor/relation_editor_page.dart';
import 'package:doable/src/long_term_relation/presentation/editor/relation_editor_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../intention/presentation/catalog/catalog_test_support.dart'
    show TestCatalogRevision, testSummary;
import '../details/relation_details_test_support.dart' show testRelationDetails;
import 'relation_form_test_support.dart';

void main() {
  setUp(() {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  testWidgets(
    'исходящая группа предвыбирает текущее намерение исходным участником',
    (tester) async {
      final repository = ControlledRelationFormRepository();
      addTearDown(repository.dispose);
      await _openForm(tester, repository, RelationDirection.outgoing);

      await _selectParticipant(
        tester,
        repository,
        actionKey: 'relation-editor-select-related',
        catalogIndex: 1,
        title: 'Много ходить',
        index: 2,
      );
      await _selectType(tester, 'need');
      await _selectPriority(tester, 'p1');
      await tester.tap(find.byKey(const ValueKey('relation-editor-submit')));
      await tester.pump();

      expect(repository.relationCommands, hasLength(1));
      final command = repository.commandAt(0);
      expect(command.sourceIntentionId, _contextIntentionId);
      expect(command.relatedIntentionId, testSummary(index: 2).id);
      expect(command.type, LongTermRelationType.need);
      expect(command.priority, RelationPriority.p1);
      expect(command.description, isNull);
    },
  );

  testWidgets(
    'входящая группа предвыбирает текущее намерение связанным участником',
    (tester) async {
      final repository = ControlledRelationFormRepository();
      addTearDown(repository.dispose);
      await _openForm(tester, repository, RelationDirection.incoming);

      await _selectParticipant(
        tester,
        repository,
        actionKey: 'relation-editor-select-source',
        catalogIndex: 1,
        title: 'Быть здоровым',
        index: 3,
      );
      await _selectType(tester, 'can');
      await _selectPriority(tester, 'p4');
      await tester.tap(find.byKey(const ValueKey('relation-editor-submit')));
      await tester.pump();

      final command = repository.commandAt(0);
      expect(command.sourceIntentionId, testSummary(index: 3).id);
      expect(command.relatedIntentionId, _contextIntentionId);
      expect(command.type, LongTermRelationType.can);
      expect(command.priority, RelationPriority.p4);
      // Выбор второго участника исключает уже занятое намерение пары.
      expect(repository.catalogQueries[1].scope, IntentionScope.active);
    },
  );

  testWidgets(
    'объясняет недостающий обязательный выбор и не отправляет команду',
    (tester) async {
      final repository = ControlledRelationFormRepository();
      addTearDown(repository.dispose);
      await _openForm(tester, repository, RelationDirection.outgoing);

      expect(find.text('To create the relation, provide:'), findsOneWidget);
      expect(find.text('the related intention'), findsOneWidget);
      expect(find.text('the relation type'), findsOneWidget);
      expect(find.text('a priority from P1 to P4'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('relation-editor-submit')),
            )
            .onPressed,
        isNull,
      );

      await _selectParticipant(
        tester,
        repository,
        actionKey: 'relation-editor-select-related',
        catalogIndex: 1,
        title: 'Много ходить',
        index: 2,
      );
      await _selectType(tester, 'need');

      expect(find.text('the related intention'), findsNothing);
      expect(find.text('the relation type'), findsNothing);
      expect(find.text('a priority from P1 to P4'), findsOneWidget);
      expect(repository.relationCommands, isEmpty);
    },
  );

  testWidgets('передаёт описание в команду целиком и без усечения', (
    tester,
  ) async {
    final repository = ControlledRelationFormRepository();
    addTearDown(repository.dispose);
    await _openForm(tester, repository, RelationDirection.outgoing);
    await _completeDraft(tester, repository);

    const description = '  Сохранить буквально\nвторая строка  ';
    await tester.enterText(
      find.byKey(const ValueKey('relation-editor-description')),
      description,
    );
    await tester.tap(find.byKey(const ValueKey('relation-editor-submit')));
    await tester.pump();

    expect(repository.commandAt(0).description?.value, description);
  });

  testWidgets('отклоняет слишком длинное описание, сохраняя введённый текст', (
    tester,
  ) async {
    final repository = ControlledRelationFormRepository();
    addTearDown(repository.dispose);
    await _openForm(tester, repository, RelationDirection.outgoing);
    await _completeDraft(tester, repository);

    final tooLong = 'я' * (LongTermRelationDescription.maxGraphemeClusters + 1);
    await tester.enterText(
      find.byKey(const ValueKey('relation-editor-description')),
      tooLong,
    );
    await tester.tap(find.byKey(const ValueKey('relation-editor-submit')));
    await tester.pumpAndSettle();

    expect(repository.relationCommands, isEmpty);
    expect(find.text('Use no more than 4096 characters.'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('relation-editor-description')),
          )
          .controller
          ?.text,
      tooLong,
    );
  });

  testWidgets(
    'конфликт пары открывает архивную связь и сохраняет черновик после возврата',
    (tester) async {
      final repository = ControlledRelationFormRepository();
      addTearDown(repository.dispose);
      final router = await _openForm(
        tester,
        repository,
        RelationDirection.outgoing,
      );
      await _completeDraft(tester, repository);
      await tester.enterText(
        find.byKey(const ValueKey('relation-editor-description')),
        'Черновик остаётся',
      );
      await tester.tap(find.byKey(const ValueKey('relation-editor-submit')));
      final existingId = testFormRelationId(7);
      repository.failRelationCommand(
        0,
        LongTermRelationPairOccupiedFailure(existingId),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'A relation with this direction already exists between the selected '
          'intentions.',
        ),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('relation-editor-open-existing')),
      );
      // Чтение открытой связи показывает индикатор: кадры перехода явные.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      repository.relationWatches.last.emitDetails(
        testRelationDetails(
          relationId: existingId,
          sourceId: _contextIntentionId,
          relatedId: testSummary(index: 2).id,
          scope: RelationScope.archived,
        ),
        revision: const TestCatalogRevision(2),
      );
      await tester.pumpAndSettle();

      expect(router.current.name, RelationDetailsRoute.name);
      expect(find.text('Archived relation'), findsOneWidget);
      expect(repository.relationCommands, hasLength(1));

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(router.current.name, RelationEditorRoute.name);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('relation-editor-description')),
            )
            .controller
            ?.text,
        'Черновик остаётся',
      );
      expect(_isChipSelected(tester, 'relation-editor-type-need'), isTrue);
      expect(_isChipSelected(tester, 'relation-editor-priority-p1'), isTrue);
      expect(find.text('Selected'), findsNWidgets(2));
    },
  );

  testWidgets(
    'success закрывает форму и предъявляется один раз после занятого сообщения',
    (tester) async {
      const busyMessage =
          'Create — “new relation”: The relation couldn’t be created. Try '
          'again.';
      const successMessage = 'Create — “new relation”: Relation created.';
      final repository = ControlledRelationFormRepository();
      addTearDown(repository.dispose);
      final router = await _openForm(
        tester,
        repository,
        RelationDirection.outgoing,
      );
      await _completeDraft(tester, repository);
      await _occupySharedSurface(tester, repository);

      expect(find.text(busyMessage), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('relation-editor-submit')));
      await tester.pump();
      repository.completeRelationCreated(1);
      await tester.pumpAndSettle();

      expect(router.current.name, IntentionCatalogRoute.name);
      expect(find.text(busyMessage), findsOneWidget);
      expect(find.text(successMessage), findsNothing);

      await _closeOperationMessage(tester);

      expect(find.text(successMessage), findsOneWidget);

      await _closeOperationMessage(tester);

      expect(find.text(successMessage), findsNothing);
    },
  );

  testWidgets(
    'удаление renderer ошибки до подтверждённого кадра передаёт её оболочке один раз',
    (tester) async {
      const message = 'Only active intentions can be linked.';
      final repository = ControlledRelationFormRepository();
      addTearDown(repository.dispose);
      final router = await _openForm(
        tester,
        repository,
        RelationDirection.outgoing,
      );
      await _completeDraft(tester, repository);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.tap(find.byKey(const ValueKey('relation-editor-submit')));
      repository.failRelationCommand(
        0,
        LongTermRelationParticipantArchivedFailure(
          role: RelationParticipantRole.related,
          intentionId: testSummary(index: 2).id,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OperationFailurePresentation), findsOneWidget);
      expect(find.text(message), findsOneWidget);

      // Исправление участника удаляет renderer ошибки, не уходя с маршрута.
      await _selectParticipant(
        tester,
        repository,
        actionKey: 'relation-editor-change-related',
        catalogIndex: 2,
        title: 'Другое намерение',
        index: 5,
      );

      expect(router.current.name, RelationEditorRoute.name);
      expect(find.byType(OperationFailurePresentation), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      final shellMessage =
          'Create — “new relation”: Only active intentions can be linked.';
      expect(find.text(shellMessage), findsOneWidget);
      expect(repository.relationCommands, hasLength(1));

      await _closeOperationMessage(tester);

      expect(find.text(shellMessage), findsNothing);
    },
  );

  testWidgets(
    'временная невидимость renderer удерживает право формы до подтверждённого кадра',
    (tester) async {
      const message = 'The relation couldn’t be created. Try again.';
      const shellMessage = 'Create — “new relation”: $message';
      final repository = ControlledRelationFormRepository();
      addTearDown(repository.dispose);
      final router = await _openForm(
        tester,
        repository,
        RelationDirection.outgoing,
      );
      await _completeDraft(tester, repository);

      await tester.tap(find.byKey(const ValueKey('relation-editor-submit')));
      repository.failRelationCommand(
        0,
        const LongTermRelationUnavailableFailure(),
      );
      await tester.idle();
      await tester.pump();

      // Перекрытие маршрутом выбора не потребляет результат и не передаёт его.
      await tester.tap(
        find.byKey(const ValueKey('relation-editor-change-related')),
      );
      await _settlePicker(tester);
      expect(find.text(shellMessage), findsNothing);

      await tester.tap(find.byKey(const ValueKey('participant-picker-cancel')));
      await tester.pumpAndSettle();

      expect(router.current.name, RelationEditorRoute.name);
      expect(find.text(message), findsOneWidget);
      expect(find.text(shellMessage), findsNothing);

      // Подтверждённое сообщение не предъявляется повторно после ухода.
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text(shellMessage), findsNothing);
      expect(find.text(message), findsNothing);
    },
  );

  testWidgets('локализует форму создания связи на русском', (tester) async {
    final repository = ControlledRelationFormRepository();
    addTearDown(repository.dispose);
    await _openForm(
      tester,
      repository,
      RelationDirection.outgoing,
      locale: const Locale('ru'),
    );

    expect(find.text('Новая связь'), findsWidgets);
    expect(find.text('Исходное намерение'), findsOneWidget);
    expect(find.text('Связанное намерение'), findsOneWidget);
    expect(find.text('Тип связи'), findsOneWidget);
    expect(find.text('Приоритет'), findsOneWidget);
    expect(find.text('Описание (необязательно)'), findsOneWidget);
    expect(find.text('Создать связь'), findsWidgets);
    expect(find.text('Чтобы создать связь, укажите:'), findsOneWidget);
    expect(find.text('связанное намерение'), findsOneWidget);
  });

  testWidgets('форма проходит accessibility guidelines при масштабе 200%', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
    );
    final repository = ControlledRelationFormRepository();
    addTearDown(repository.dispose);
    await _openForm(tester, repository, RelationDirection.outgoing);
    await tester.ensureVisible(
      find.byKey(const ValueKey('relation-editor-submit')),
    );
    await tester.pumpAndSettle();

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    semantics.dispose();
  });
}

IntentionId get _contextIntentionId => testSummary(index: 1).id;

Future<AppRouter> _openForm(
  WidgetTester tester,
  ControlledRelationFormRepository repository,
  RelationDirection direction, {
  Locale locale = const Locale('en'),
}) async {
  // Высокая поверхность держит поля формы построенными без прокрутки.
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = AppRouter();
  addTearDown(router.dispose);
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
  repository.completeCatalogPage(0, const []);
  await tester.pumpAndSettle();
  unawaited(
    router.push(
      RelationEditorRoute(
        creationContext: RelationCreationContext(
          intentionId: _contextIntentionId,
          direction: direction,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

/// Доводит черновик до отправляемого состояния: второй участник, тип и P1.
Future<void> _completeDraft(
  WidgetTester tester,
  ControlledRelationFormRepository repository,
) async {
  await _selectParticipant(
    tester,
    repository,
    actionKey: 'relation-editor-select-related',
    catalogIndex: 1,
    title: 'Много ходить',
    index: 2,
  );
  await _selectType(tester, 'need');
  await _selectPriority(tester, 'p1');
}

Future<void> _selectParticipant(
  WidgetTester tester,
  ControlledRelationFormRepository repository, {
  required String actionKey,
  required int catalogIndex,
  required String title,
  required int index,
}) async {
  await tester.tap(find.byKey(ValueKey(actionKey)));
  await _settlePicker(tester);
  repository.completeCatalogPage(catalogIndex, [
    testSummary(index: index, title: title),
  ]);
  await tester.pumpAndSettle();
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

/// Завершает переход к выбору участника без подтверждённой порции каталога.
Future<void> _settlePicker(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _selectType(WidgetTester tester, String type) async {
  await tester.tap(find.byKey(ValueKey('relation-editor-type-$type')));
  await tester.pumpAndSettle();
}

Future<void> _selectPriority(WidgetTester tester, String priority) async {
  await tester.tap(find.byKey(ValueKey('relation-editor-priority-$priority')));
  await tester.pumpAndSettle();
}

/// Занимает общую поверхность сообщением другой операции графа.
Future<void> _occupySharedSurface(
  WidgetTester tester,
  ControlledRelationFormRepository repository,
) async {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(RelationEditorPage)),
  );
  final coordinator = container.read(graphCommandCoordinatorProvider.notifier);
  final busy = coordinator.acceptRelationCreation(
    LongTermRelationCreationFormKey(),
    CreateLongTermRelation(
      sourceIntentionId: testSummary(index: 8).id,
      relatedIntentionId: testSummary(index: 9).id,
      type: LongTermRelationType.can,
      priority: RelationPriority.p2,
      description: null,
    ),
  ) as LongTermRelationCommandAccepted;
  coordinator.releaseInitiatorPresentation(busy.token);
  await tester.pump();
  repository.failRelationCommand(0, const LongTermRelationUnavailableFailure());
  await tester.pumpAndSettle();
}

Future<void> _closeOperationMessage(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

bool _isChipSelected(WidgetTester tester, String key) =>
    tester.widget<ChoiceChip>(find.byKey(ValueKey(key))).selected;
