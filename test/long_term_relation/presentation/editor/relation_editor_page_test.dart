import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/localization/app_locale_resolution.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/presentation/graph_operation_presenter.dart';
import 'package:doable/src/graph/presentation/operation_failure_presentation.dart';
import 'package:doable/src/intention/application/intention_catalog.dart'
    hide IntentionCatalogPage;
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_description.dart';
import 'package:doable/src/long_term_relation/presentation/editor/relation_editor_page.dart';
import 'package:doable/src/long_term_relation/presentation/editor/relation_editor_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../intention/presentation/catalog/catalog_test_support.dart'
    show TestCatalogRevision, testRelationCounts, testSummary;
import '../../../intention/presentation/details/details_test_support.dart'
    show testDetailsIntention;
import '../details/relation_details_test_support.dart' show testRelationDetails;
import 'relation_form_test_support.dart';

void main() {
  setUp(() {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  for (final role in RelationParticipantRole.values) {
    testWidgets('повторный выбор ${role.name} не откатывается снимком связи', (
      tester,
    ) async {
      final repository = ControlledRelationFormRepository();
      addTearDown(repository.dispose);
      final relationId = testFormRelationId(115);
      final sourceId = testSummary(index: 1).id;
      final relatedId = testSummary(index: 2).id;
      final details = testRelationDetails(
        relationId: relationId,
        sourceId: sourceId,
        relatedId: relatedId,
        sourceTitle: 'Исходное',
        relatedTitle: 'Связанное',
        scope: RelationScope.archived,
      );
      await _openDetailsForEditing(tester, repository, details);
      await tester.tap(
        find.byKey(const ValueKey('relation-details-edit-relation')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('relation-editor-description')),
        'Черновик',
      );
      await _selectParticipant(
        tester,
        repository,
        actionKey: role == RelationParticipantRole.source
            ? 'relation-editor-change-source'
            : 'relation-editor-change-related',
        catalogIndex: 1,
        title: 'Название из каталога',
        index: role == RelationParticipantRole.source ? 1 : 2,
        revision: const TestCatalogRevision(5),
        archiveState: IntentionArchiveState.archived,
      );

      repository
          .watchAt(0)
          .emitDetails(
            testRelationDetails(
              relationId: relationId,
              sourceId: sourceId,
              relatedId: relatedId,
              sourceTitle: role == RelationParticipantRole.source
                  ? 'Старое исходное'
                  : 'Исходное',
              relatedTitle: role == RelationParticipantRole.related
                  ? 'Старое связанное'
                  : 'Связанное',
              scope: RelationScope.archived,
            ),
            revision: const TestCatalogRevision(3),
          );
      await tester.pumpAndSettle();
      expect(find.text('Название из каталога'), findsOneWidget);
      expect(
        tester
            .widget<Text>(
              find.byKey(
                ValueKey(
                  'relation-editor-participant-archive-state-${role.name}',
                ),
              ),
            )
            .data,
        'Archived',
      );
      expect(
        find.text(
          'To ${role == RelationParticipantRole.source ? 'Название из каталога' : 'Исходное'}, you need ${role == RelationParticipantRole.related ? 'Название из каталога' : 'Связанное'}',
        ),
        findsOneWidget,
      );

      repository
          .watchAt(0)
          .emitDetails(
            testRelationDetails(
              relationId: relationId,
              sourceId: sourceId,
              relatedId: relatedId,
              sourceTitle: role == RelationParticipantRole.source
                  ? 'Новое исходное'
                  : 'Исходное',
              relatedTitle: role == RelationParticipantRole.related
                  ? 'Новое связанное'
                  : 'Связанное',
              scope: RelationScope.archived,
            ),
            revision: const TestCatalogRevision(6),
          );
      await tester.pumpAndSettle();
      expect(
        find.text(
          role == RelationParticipantRole.source
              ? 'Новое исходное'
              : 'Новое связанное',
        ),
        findsOneWidget,
      );
      expect(find.text('Название из каталога'), findsNothing);
      expect(
        tester
            .widget<Text>(
              find.byKey(
                ValueKey(
                  'relation-editor-participant-archive-state-${role.name}',
                ),
              ),
            )
            .data,
        'Active',
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('relation-editor-description')),
            )
            .controller
            ?.text,
        'Черновик',
      );
      await tester.tap(find.byKey(const ValueKey('relation-editor-submit')));
      await tester.pump();
      expect(repository.relationUpdateCommands, hasLength(1));
      final command = repository.updateCommandAt(0);
      expect(command.relationId, relationId);
      expect(
        command.patch.sourceIntentionId,
        isA<LongTermRelationFieldUnchanged>(),
      );
      expect(
        command.patch.relatedIntentionId,
        isA<LongTermRelationFieldUnchanged>(),
      );
    });
  }

  testWidgets('другая эпоха требует нового подтверждённого снимка участника', (
    tester,
  ) async {
    final repository = ControlledRelationFormRepository();
    addTearDown(repository.dispose);
    final relationId = testFormRelationId(116);
    final sourceId = testSummary(index: 1).id;
    final relatedId = testSummary(index: 2).id;
    await _openDetailsForEditing(
      tester,
      repository,
      testRelationDetails(
        relationId: relationId,
        sourceId: sourceId,
        relatedId: relatedId,
        sourceTitle: 'Исходное',
        relatedTitle: 'Связанное',
        scope: RelationScope.archived,
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey('relation-details-edit-relation')),
    );
    await tester.pumpAndSettle();
    await _selectParticipant(
      tester,
      repository,
      actionKey: 'relation-editor-change-source',
      catalogIndex: 1,
      title: 'Снимок каталога',
      index: 1,
      revision: const TestCatalogRevision(5),
    );

    repository
        .watchAt(0)
        .emitDetails(
          testRelationDetails(
            relationId: relationId,
            sourceId: sourceId,
            relatedId: relatedId,
            sourceTitle: 'Несопоставимое название',
            relatedTitle: 'Связанное',
            scope: RelationScope.archived,
          ),
          revision: const TestCatalogRevision(1, epoch: 1),
        );
    await tester.pumpAndSettle();
    expect(find.text('Снимок каталога'), findsOneWidget);
    expect(find.text('Несопоставимое название'), findsNothing);
    expect(repository.watchedIntentionIds, contains(sourceId));

    repository.emitIntention(
      testDetailsIntention(
        index: 1,
        title: 'Подтверждённая новая эпоха',
        archiveState: IntentionArchiveState.archived,
      ),
      counts: testRelationCounts(),
      revision: const TestCatalogRevision(2, epoch: 1),
    );
    await tester.pumpAndSettle();
    expect(find.text('Подтверждённая новая эпоха'), findsOneWidget);
    expect(find.text('Снимок каталога'), findsNothing);
    expect(
      find.text('To Подтверждённая новая эпоха, you need Связанное'),
      findsOneWidget,
    );
  });

  testWidgets(
    'исходящая группа предвыбирает текущее намерение исходным участником',
    (tester) async {
      final repository = ControlledRelationFormRepository();
      addTearDown(repository.dispose);
      await _openForm(tester, repository, RelationDirection.outgoing);

      expect(find.text('Текущее намерение'), findsOneWidget);
      await _selectParticipant(
        tester,
        repository,
        actionKey: 'relation-editor-select-related',
        catalogIndex: 1,
        title: 'Много ходить',
        index: 2,
      );
      expect(find.text('Много ходить'), findsOneWidget);
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
    'открывает подробные данные по идентификатору выбранного участника',
    (tester) async {
      final repository = ControlledRelationFormRepository();
      addTearDown(repository.dispose);
      final router = await _openForm(
        tester,
        repository,
        RelationDirection.outgoing,
      );
      await _selectParticipant(
        tester,
        repository,
        actionKey: 'relation-editor-select-related',
        catalogIndex: 1,
        title: 'Одинаковое название',
        index: 2,
      );

      await tester.tap(
        find.byKey(const ValueKey('relation-editor-open-related-details')),
      );
      await tester.pump();
      await tester.pump();

      expect(router.current.name, IntentionDetailsRoute.name);
      expect(
        tester
            .widget<IntentionDetailsPage>(find.byType(IntentionDetailsPage))
            .intentionId,
        testSummary(index: 2).id,
      );

      await router.maybePop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(router.current.name, RelationEditorRoute.name);
      expect(find.text('Одинаковое название'), findsOneWidget);
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
      expect(find.text('Текущее намерение'), findsOneWidget);
      expect(find.text('Много ходить'), findsOneWidget);
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
      expect(find.text('Текущее намерение'), findsOneWidget);
      expect(find.text('Много ходить'), findsOneWidget);

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

  testWidgets('смена локали сохраняет владельца непредъявленной ошибки формы', (
    tester,
  ) async {
    tester.binding.platformDispatcher.localesTestValue = const <Locale>[
      Locale('en'),
    ];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    final repository = ControlledRelationFormRepository();
    addTearDown(repository.dispose);
    final router = await _openForm(
      tester,
      repository,
      RelationDirection.outgoing,
      locale: null,
    );
    await _completeDraft(tester, repository);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.tap(find.byKey(const ValueKey('relation-editor-submit')));
    repository.failRelationCommand(
      0,
      const LongTermRelationUnavailableFailure(),
    );
    await tester.pumpAndSettle();

    const englishMessage = 'The relation couldn’t be created. Try again.';
    const russianMessage = 'Не удалось создать связь. Повторите попытку.';
    const shellMessage = 'Создание — «новая связь»: $russianMessage';
    expect(find.text(englishMessage), findsOneWidget);

    tester.binding.platformDispatcher.localesTestValue = const <Locale>[
      Locale('ru'),
    ];
    await tester.pumpAndSettle();

    expect(find.text(englishMessage), findsNothing);
    expect(find.text(russianMessage), findsOneWidget);
    expect(find.text(shellMessage), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text(russianMessage), findsOneWidget);
    expect(find.text(shellMessage), findsNothing);
    expect(repository.relationCommands, hasLength(1));

    await router.maybePop();
    await tester.pumpAndSettle();

    expect(find.text(shellMessage), findsNothing);
    expect(repository.relationCommands, hasLength(1));
  });

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

  testWidgets('из подробного просмотра редактирует все поля архивной связи', (
    tester,
  ) async {
    final repository = ControlledRelationFormRepository();
    addTearDown(repository.dispose);
    final details = testRelationDetails(
      relationId: testFormRelationId(90),
      sourceId: testSummary(index: 1).id,
      relatedId: testSummary(index: 2).id,
      sourceTitle: 'Исходное',
      relatedTitle: 'Связанное',
      type: LongTermRelationType.can,
      priority: RelationPriority.p2,
      scope: RelationScope.archived,
      description: 'Прежнее описание',
    );
    final router = await _openDetailsForEditing(tester, repository, details);

    await tester.tap(
      find.byKey(const ValueKey('relation-details-edit-relation')),
    );
    await tester.pumpAndSettle();

    expect(router.current.name, RelationEditorRoute.name);
    expect(find.text('Edit relation'), findsOneWidget);
    expect(find.text('Исходное'), findsOneWidget);
    expect(find.text('Связанное'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('relation-editor-description')),
          )
          .controller
          ?.text,
      'Прежнее описание',
    );
    expect(_isChipSelected(tester, 'relation-editor-type-can'), isTrue);
    expect(_isChipSelected(tester, 'relation-editor-priority-p2'), isTrue);
    expect(find.text('To Исходное, you can Связанное'), findsOneWidget);

    await _selectParticipant(
      tester,
      repository,
      actionKey: 'relation-editor-change-source',
      catalogIndex: 1,
      title: 'Новое исходное',
      index: 3,
    );
    expect(repository.catalogQueries[1].scope, IntentionScope.all);
    await _selectParticipant(
      tester,
      repository,
      actionKey: 'relation-editor-change-related',
      catalogIndex: 2,
      title: 'Новое связанное',
      index: 4,
    );
    await _selectType(tester, 'need');
    await _selectPriority(tester, 'p4');
    await tester.enterText(
      find.byKey(const ValueKey('relation-editor-description')),
      'Новое описание',
    );
    await tester.pumpAndSettle();

    expect(
      find.text('To Новое исходное, you need Новое связанное'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('relation-editor-submit')));
    await tester.pump();

    expect(repository.relationUpdateCommands, hasLength(1));
    final command = repository.updateCommandAt(0);
    expect(command.relationId, details.relation.id);
    expect(
      command.patch.sourceIntentionId,
      isA<LongTermRelationFieldSet<IntentionId>>().having(
        (field) => field.value,
        'исходный участник',
        testSummary(index: 3).id,
      ),
    );
    expect(
      command.patch.relatedIntentionId,
      isA<LongTermRelationFieldSet<IntentionId>>().having(
        (field) => field.value,
        'связанный участник',
        testSummary(index: 4).id,
      ),
    );
    expect(
      command.patch.type,
      isA<LongTermRelationFieldSet<LongTermRelationType>>().having(
        (field) => field.value,
        'тип',
        LongTermRelationType.need,
      ),
    );
    expect(
      command.patch.priority,
      isA<LongTermRelationFieldSet<RelationPriority>>().having(
        (field) => field.value,
        'приоритет',
        RelationPriority.p4,
      ),
    );
    expect(
      command.patch.description,
      isA<LongTermRelationDescriptionReplaced>().having(
        (field) => field.value.value,
        'описание',
        'Новое описание',
      ),
    );

    final updated = LongTermRelation(
      id: details.relation.id,
      sourceIntentionId: testSummary(index: 3).id,
      relatedIntentionId: testSummary(index: 4).id,
      type: LongTermRelationType.need,
      priority: RelationPriority.p4,
      scope: RelationScope.archived,
      creationSequence: details.relation.creationSequence,
    );
    repository.completeRelationUpdated(
      0,
      before: details.relation,
      after: updated,
      description: LongTermRelationDescription.fromInput('Новое описание'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(router.current.name, RelationDetailsRoute.name);
    expect(repository.relationWatches, hasLength(2));
    repository
        .watchAt(1)
        .emitDetails(
          testRelationDetails(
            relationId: updated.id,
            sourceId: updated.sourceIntentionId,
            relatedId: updated.relatedIntentionId,
            sourceTitle: 'Новое исходное',
            relatedTitle: 'Новое связанное',
            type: updated.type,
            priority: updated.priority,
            scope: updated.scope,
            creationSequence: updated.creationSequence.value,
            description: 'Новое описание',
          ),
          revision: const TestCatalogRevision(1),
        );
    await tester.pumpAndSettle();

    expect(
      find.text('To Новое исходное, you need Новое связанное'),
      findsOneWidget,
    );
    expect(find.text('Новое описание'), findsOneWidget);
  });

  testWidgets('отмена редактирования не отправляет команду', (tester) async {
    final repository = ControlledRelationFormRepository();
    addTearDown(repository.dispose);
    final details = testRelationDetails(
      relationId: testFormRelationId(91),
      sourceId: testSummary(index: 1).id,
      relatedId: testSummary(index: 2).id,
      description: 'Прежнее описание',
    );
    final router = await _openDetailsForEditing(tester, repository, details);

    await tester.tap(
      find.byKey(const ValueKey('relation-details-edit-relation')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('relation-editor-description')),
      'Неподтверждённый черновик',
    );
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(router.current.name, RelationDetailsRoute.name);
    expect(repository.relationUpdateCommands, isEmpty);
    expect(find.text('Прежнее описание'), findsOneWidget);
  });

  testWidgets(
    'открытая форма получает подтверждённые снимки без потери черновика и ошибки пары',
    (tester) async {
      final repository = ControlledRelationFormRepository();
      addTearDown(repository.dispose);
      final relationId = testFormRelationId(93);
      final sourceId = testSummary(index: 1).id;
      final relatedId = testSummary(index: 2).id;
      final details = testRelationDetails(
        relationId: relationId,
        sourceId: sourceId,
        relatedId: relatedId,
        sourceTitle: 'Исходное',
        relatedTitle: 'Связанное',
        scope: RelationScope.archived,
        description: 'Прежнее описание',
      );
      await _openDetailsForEditing(tester, repository, details);
      await tester.tap(
        find.byKey(const ValueKey('relation-details-edit-relation')),
      );
      await tester.pumpAndSettle();
      await _selectType(tester, 'can');
      await tester.enterText(
        find.byKey(const ValueKey('relation-editor-description')),
        'Черновик пользователя',
      );
      await tester.tap(find.byKey(const ValueKey('relation-editor-submit')));
      await tester.pump();
      repository.failRelationCommand(
        0,
        LongTermRelationPairOccupiedFailure(testFormRelationId(94)),
      );
      await tester.pumpAndSettle();

      final renamed = testRelationDetails(
        relationId: relationId,
        sourceId: sourceId,
        relatedId: relatedId,
        sourceTitle: 'Исходное после переименования',
        relatedTitle: 'Связанное после переименования',
        relatedArchiveState: IntentionArchiveState.archived,
        scope: RelationScope.archived,
        description: 'Чужое описание',
      );
      repository
          .watchAt(0)
          .emitDetails(renamed, revision: const TestCatalogRevision(3));
      await tester.pumpAndSettle();

      expect(find.text('Исходное после переименования'), findsOneWidget);
      expect(find.text('Связанное после переименования'), findsOneWidget);
      expect(
        find.text(
          'To Исходное после переименования, you can '
          'Связанное после переименования',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey('relation-editor-participant-archive-state-related'),
        ),
        findsOneWidget,
      );
      expect(find.text('Archived'), findsOneWidget);
      expect(
        find.text(
          'A relation with this direction already exists between the selected '
          'intentions.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('relation-editor-description')),
            )
            .controller
            ?.text,
        'Черновик пользователя',
      );
      expect(repository.relationUpdateCommands, hasLength(1));

      await _selectParticipant(
        tester,
        repository,
        actionKey: 'relation-editor-change-related',
        catalogIndex: 1,
        title: 'Новое связанное',
        index: 3,
      );
      repository
          .watchAt(0)
          .emitDetails(
            testRelationDetails(
              relationId: relationId,
              sourceId: sourceId,
              relatedId: relatedId,
              sourceTitle: 'Актуальное исходное',
              relatedTitle: 'Старое связанное после замены',
              scope: RelationScope.archived,
            ),
            revision: const TestCatalogRevision(4),
          );
      await tester.pumpAndSettle();
      repository
          .watchAt(0)
          .emitDetails(details, revision: const TestCatalogRevision(2));
      await tester.pumpAndSettle();

      expect(find.text('Актуальное исходное'), findsOneWidget);
      expect(find.text('Новое связанное'), findsOneWidget);
      expect(find.text('Старое связанное после замены'), findsNothing);
      expect(find.text('Исходное'), findsNothing);
      expect(
        find.text('To Актуальное исходное, you can Новое связанное'),
        findsOneWidget,
      );
      expect(repository.relationUpdateCommands, hasLength(1));
      await tester.tap(find.byKey(const ValueKey('relation-editor-submit')));
      await tester.pump();
      expect(repository.relationUpdateCommands, hasLength(2));
      final patch = repository.updateCommandAt(1).patch;
      expect(patch.sourceIntentionId, isA<LongTermRelationFieldUnchanged>());
      expect(
        patch.relatedIntentionId,
        isA<LongTermRelationFieldSet<IntentionId>>().having(
          (field) => field.value,
          'выбранный участник',
          testSummary(index: 3).id,
        ),
      );
      expect(
        patch.description,
        isA<LongTermRelationDescriptionReplaced>().having(
          (field) => field.value.value,
          'черновик описания',
          'Черновик пользователя',
        ),
      );
    },
  );

  testWidgets(
    'заменённый участник обновляется по подписке без потери ошибки и черновика',
    (tester) async {
      final repository = ControlledRelationFormRepository();
      addTearDown(repository.dispose);
      final relationId = testFormRelationId(95);
      final sourceId = testSummary(index: 1).id;
      final oldRelatedId = testSummary(index: 2).id;
      final replacementId = testSummary(index: 3).id;
      final details = testRelationDetails(
        relationId: relationId,
        sourceId: sourceId,
        relatedId: oldRelatedId,
        sourceTitle: 'Исходное',
        relatedTitle: 'Прежнее связанное',
        scope: RelationScope.archived,
        description: 'Исходное описание',
      );
      await _openDetailsForEditing(tester, repository, details);
      await tester.tap(
        find.byKey(const ValueKey('relation-details-edit-relation')),
      );
      await tester.pumpAndSettle();
      await _selectParticipant(
        tester,
        repository,
        actionKey: 'relation-editor-change-related',
        catalogIndex: 1,
        title: 'Новый участник',
        index: 3,
      );
      await _selectType(tester, 'can');
      await tester.enterText(
        find.byKey(const ValueKey('relation-editor-description')),
        'Черновик пользователя',
      );
      await tester.tap(find.byKey(const ValueKey('relation-editor-submit')));
      await tester.pump();
      repository.failRelationCommand(
        0,
        LongTermRelationPairOccupiedFailure(testFormRelationId(96)),
      );
      await tester.pumpAndSettle();

      expect(repository.watchedIntentionIds, contains(replacementId));
      repository.emitIntention(
        testDetailsIntention(
          index: 3,
          title: 'Новый участник после переименования',
          archiveState: IntentionArchiveState.archived,
        ),
        counts: testRelationCounts(),
        revision: const TestCatalogRevision(3),
      );
      await tester.pumpAndSettle();
      repository
          .watchAt(0)
          .emitDetails(
            testRelationDetails(
              relationId: relationId,
              sourceId: sourceId,
              relatedId: oldRelatedId,
              sourceTitle: 'Исходное после переименования',
              relatedTitle: 'Прежнее связанное после переименования',
              scope: RelationScope.archived,
            ),
            revision: const TestCatalogRevision(4),
          );
      await tester.pumpAndSettle();

      expect(find.text('Исходное после переименования'), findsOneWidget);
      expect(find.text('Новый участник после переименования'), findsOneWidget);
      expect(find.text('Прежнее связанное после переименования'), findsNothing);
      expect(
        find.text(
          'To Исходное после переименования, you can '
          'Новый участник после переименования',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(
                const ValueKey(
                  'relation-editor-participant-archive-state-related',
                ),
              ),
            )
            .data,
        'Archived',
      );
      expect(
        find.text(
          'A relation with this direction already exists between the selected '
          'intentions.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('relation-editor-description')),
            )
            .controller
            ?.text,
        'Черновик пользователя',
      );
      expect(repository.relationUpdateCommands, hasLength(1));
      expect(
        repository.updateCommandAt(0).patch.relatedIntentionId,
        isA<LongTermRelationFieldSet<IntentionId>>().having(
          (field) => field.value,
          'выбранный участник',
          replacementId,
        ),
      );
    },
  );

  testWidgets(
    'снимок нового исходного участника сохраняет основу правки и команду',
    (tester) async {
      final repository = ControlledRelationFormRepository();
      addTearDown(repository.dispose);
      final relationId = testFormRelationId(97);
      final oldSourceId = testSummary(index: 1).id;
      final relatedId = testSummary(index: 2).id;
      final replacementId = testSummary(index: 3).id;
      final details = testRelationDetails(
        relationId: relationId,
        sourceId: oldSourceId,
        relatedId: relatedId,
        sourceTitle: 'Прежнее исходное',
        relatedTitle: 'Связанное',
        scope: RelationScope.archived,
        description: 'Исходное описание',
      );
      await _openDetailsForEditing(tester, repository, details);
      await tester.tap(
        find.byKey(const ValueKey('relation-details-edit-relation')),
      );
      await tester.pumpAndSettle();
      await _selectParticipant(
        tester,
        repository,
        actionKey: 'relation-editor-change-source',
        catalogIndex: 1,
        title: 'Новое исходное',
        index: 3,
      );
      await tester.enterText(
        find.byKey(const ValueKey('relation-editor-description')),
        'Моё описание',
      );

      expect(repository.watchedIntentionIds, contains(replacementId));
      repository.emitIntention(
        testDetailsIntention(
          index: 3,
          title: 'Новое исходное после переименования',
          archiveState: IntentionArchiveState.archived,
        ),
        counts: testRelationCounts(),
        revision: const TestCatalogRevision(3),
      );
      await tester.pumpAndSettle();
      repository
          .watchAt(0)
          .emitDetails(
            testRelationDetails(
              relationId: relationId,
              sourceId: oldSourceId,
              relatedId: relatedId,
              sourceTitle: 'Прежнее исходное после переименования',
              relatedTitle: 'Связанное',
              scope: RelationScope.archived,
              description: 'Чужое описание',
            ),
            revision: const TestCatalogRevision(4),
          );
      await tester.pumpAndSettle();

      expect(find.text('Новое исходное после переименования'), findsOneWidget);
      expect(find.text('Прежнее исходное после переименования'), findsNothing);
      expect(find.text('Связанное'), findsOneWidget);
      expect(
        find.text('To Новое исходное после переименования, you need Связанное'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(
                const ValueKey(
                  'relation-editor-participant-archive-state-source',
                ),
              ),
            )
            .data,
        'Archived',
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('relation-editor-description')),
            )
            .controller
            ?.text,
        'Моё описание',
      );
      expect(repository.relationUpdateCommands, isEmpty);
      await tester.tap(find.byKey(const ValueKey('relation-editor-submit')));
      await tester.pump();

      expect(repository.relationUpdateCommands, hasLength(1));
      final command = repository.updateCommandAt(0);
      expect(command.relationId, relationId);
      expect(
        command.patch.sourceIntentionId,
        isA<LongTermRelationFieldSet<IntentionId>>().having(
          (field) => field.value,
          'новое исходное намерение',
          replacementId,
        ),
      );
      expect(
        command.patch.relatedIntentionId,
        isA<LongTermRelationFieldUnchanged<IntentionId>>(),
      );
      expect(command.patch.type, isA<LongTermRelationFieldUnchanged>());
      expect(command.patch.priority, isA<LongTermRelationFieldUnchanged>());
      expect(
        command.patch.description,
        isA<LongTermRelationDescriptionReplaced>().having(
          (field) => field.value.value,
          'черновик описания',
          'Моё описание',
        ),
      );
    },
  );

  testWidgets('ошибка изменения сохраняет исправляемый черновик', (
    tester,
  ) async {
    final repository = ControlledRelationFormRepository();
    addTearDown(repository.dispose);
    final details = testRelationDetails(
      relationId: testFormRelationId(92),
      sourceId: testSummary(index: 1).id,
      relatedId: testSummary(index: 2).id,
      description: 'Прежнее описание',
    );
    await _openDetailsForEditing(tester, repository, details);
    await tester.tap(
      find.byKey(const ValueKey('relation-details-edit-relation')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('relation-editor-description')),
      'Исправляемый черновик',
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('relation-editor-submit')),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const ValueKey('relation-editor-submit')));
    await tester.pump();
    expect(repository.relationUpdateCommands, hasLength(1));

    repository.failRelationCommand(
      0,
      const LongTermRelationUnavailableFailure(),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.text('The relation couldn’t be updated. Try again.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('relation-editor-description')),
          )
          .controller
          ?.text,
      'Исправляемый черновик',
    );
  });

  testWidgets(
    'русская форма изменения доступно показывает текущую формулировку',
    (tester) async {
      final semantics = tester.ensureSemantics();
      tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
      );
      final repository = ControlledRelationFormRepository();
      addTearDown(repository.dispose);
      final details = testRelationDetails(
        relationId: testFormRelationId(93),
        sourceId: testSummary(index: 1).id,
        relatedId: testSummary(index: 2).id,
        sourceTitle: 'быть здоровым',
        relatedTitle: 'много ходить',
        description: 'Описание',
      );
      await _openDetailsForEditing(
        tester,
        repository,
        details,
        locale: const Locale('ru'),
      );

      expect(find.text('Редактировать связь'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('relation-details-edit-relation')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Редактирование связи'), findsOneWidget);
      expect(
        find.text('Чтобы быть здоровым, нужно много ходить'),
        findsOneWidget,
      );
      expect(find.text('Сохранить изменения'), findsOneWidget);
      final phraseSemantics = tester.getSemantics(
        find.byKey(const ValueKey('relation-editor-phrase')),
      );
      expect(phraseSemantics.label, contains('Формулировка связи'));
      expect(phraseSemantics.label, contains('быть здоровым'));
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets('неподдерживаемая локаль использует английский fallback', (
    tester,
  ) async {
    final repository = ControlledRelationFormRepository();
    addTearDown(repository.dispose);
    final details = testRelationDetails(
      relationId: testFormRelationId(94),
      sourceId: testSummary(index: 1).id,
      relatedId: testSummary(index: 2).id,
    );
    await _openDetailsForEditing(
      tester,
      repository,
      details,
      locale: const Locale('de'),
    );

    await tester.tap(
      find.byKey(const ValueKey('relation-details-edit-relation')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Edit relation'), findsOneWidget);
    expect(find.text('Save changes'), findsOneWidget);
  });

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
    expect(find.text('Текущее намерение'), findsOneWidget);
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
    final sourceSemantics = tester.getSemantics(
      find.byKey(const ValueKey('relation-editor-participant-source')),
    );
    expect(sourceSemantics.label, contains('Source intention'));
    expect(sourceSemantics.label, contains('Текущее намерение'));
    final detailsSemantics = tester.getSemantics(
      find.byKey(const ValueKey('relation-editor-open-source-details')),
    );
    expect(detailsSemantics.tooltip, 'Open intention details');
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

RelationParticipantSummary get _contextParticipant =>
    _participantSummary(index: 1, title: 'Текущее намерение');

RelationParticipantSummary _participantSummary({
  required int index,
  required String title,
  int activeRelationCount = 0,
}) {
  final summary = testSummary(
    index: index,
    title: title,
    activeRelationCount: activeRelationCount,
  );
  return RelationParticipantSummary(
    id: summary.id,
    title: summary.title,
    archiveState: summary.archiveState,
    activeRelationCount: summary.activeRelationCount,
  );
}

Future<AppRouter> _openForm(
  WidgetTester tester,
  ControlledRelationFormRepository repository,
  RelationDirection direction, {
  Locale? locale = const Locale('en'),
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
        localeListResolutionCallback: resolveAppLocale,
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
        editorContext: RelationCreationContext(
          participant: _contextParticipant,
          direction: direction,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Future<AppRouter> _openDetailsForEditing(
  WidgetTester tester,
  ControlledRelationFormRepository repository,
  LongTermRelationDetails details, {
  Locale locale = const Locale('en'),
}) async {
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
        localeListResolutionCallback: resolveAppLocale,
        routerConfig: router.config(),
        builder: (context, child) =>
            GraphOperationPresenter(child: child ?? const SizedBox.shrink()),
      ),
    ),
  );
  await tester.pump();
  repository.completeCatalogPage(0, const []);
  await tester.pumpAndSettle();
  unawaited(router.push(RelationDetailsRoute(relationId: details.relation.id)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  repository
      .watchAt(0)
      .emitDetails(details, revision: const TestCatalogRevision(0));
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
  GraphRevision revision = const TestCatalogRevision(1),
  IntentionArchiveState archiveState = IntentionArchiveState.active,
}) async {
  await tester.tap(find.byKey(ValueKey(actionKey)));
  await _settlePicker(tester);
  repository.completeCatalogPage(catalogIndex, [
    testSummary(index: index, title: title, archiveState: archiveState),
  ], revision: revision);
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
