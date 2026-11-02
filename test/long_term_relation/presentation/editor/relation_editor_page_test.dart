import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/localization/app_locale_resolution.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/design_system/components/relation_head.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/presentation/graph_operation_presenter.dart';
import 'package:doable/src/intention/application/intention_catalog.dart'
    hide IntentionCatalogPage;
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/long_term_relation/application/intention_relation_group.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_permissions.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_description.dart';
import 'package:doable/src/long_term_relation/presentation/editor/relation_editor_page.dart';
import 'package:doable/src/long_term_relation/presentation/editor/relation_editor_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../intention/presentation/catalog/catalog_test_support.dart'
    show TestCatalogRevision, testSummary;
import '../../../support/app_root_pages.dart';
import '../details/relation_details_test_support.dart' show testRelationDetails;
import 'relation_form_test_support.dart';
import 'relation_participant_selection_scenarios.dart';

import '../../../support/in_memory_quick_creation_mode_store.dart';

void main() {
  defineRelationParticipantSelectionTests(openForm: _openForm);
  defineRelationBlankCreationTests(
    openForm: (tester, repository, locale) =>
        _openForm(tester, repository, null, locale: locale),
  );

  setUp(() {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  testWidgets('связь из сохранённого пути меняет тип', (tester) async {
    final repository = ControlledRelationFormRepository();
    addTearDown(repository.dispose);
    final details = testRelationDetails(
      relationId: testFormRelationId(151),
      sourceId: testSummary(index: 1).id,
      relatedId: testSummary(index: 2).id,
      permissions: const LongTermRelationPermissions.referencedByDailyPath(),
    );
    await _openDetailsForEditing(tester, repository, details);
    await tester.tap(
      find.byKey(const ValueKey('relation-details-edit-relation')),
    );
    await tester.pumpAndSettle();

    await _selectType(tester, 'can');
    await tester.tap(find.byKey(const ValueKey('relation-editor-submit')));
    await tester.pump();

    expect(repository.relationUpdateCommands, hasLength(1));
    expect(
      repository.relationUpdateCommands.single.patch.type,
      isA<LongTermRelationFieldSet<LongTermRelationType>>().having(
        (field) => field.value,
        'тип',
        LongTermRelationType.can,
      ),
    );
  });

  testWidgets(
    'исходящая группа «Можно использовать» предвыбирает намерение исходным '
    'участником и тип «можно»',
    (tester) async {
      final repository = ControlledRelationFormRepository();
      addTearDown(repository.dispose);
      await _openForm(tester, repository, IntentionRelationGroup.canUse);

      expect(find.text('Текущее намерение'), findsOneWidget);
      expect(_isChipSelected(tester, 'relation-editor-type-can'), isTrue);
      expect(_isChipSelected(tester, 'relation-editor-type-need'), isFalse);
      expect(find.text('the related intention'), findsOneWidget);
      expect(find.text('a priority from P1 to P4'), findsOneWidget);
      await _selectParticipant(
        tester,
        repository,
        actionKey: 'relation-editor-select-related',
        catalogIndex: 1,
        title: 'Много ходить',
        index: 2,
      );
      expect(find.text('Много ходить'), findsOneWidget);
      await _selectPriority(tester, 'p1');
      await tester.tap(find.byKey(const ValueKey('relation-editor-submit')));
      await tester.pump();

      expect(repository.relationCommands, hasLength(1));
      final command = repository.commandAt(0);
      expect(command.sourceIntentionId, _contextIntentionId);
      expect(command.relatedIntentionId, testSummary(index: 2).id);
      expect(command.type, LongTermRelationType.can);
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
        IntentionRelationGroup.needs,
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
      await _openForm(tester, repository, IntentionRelationGroup.neededFor);

      expect(_isChipSelected(tester, 'relation-editor-type-need'), isTrue);
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
      await _openForm(tester, repository, null);

      expect(find.text('To create the relation, provide:'), findsOneWidget);
      expect(find.text('the source intention'), findsOneWidget);
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
        actionKey: 'relation-editor-select-source',
        catalogIndex: 1,
        title: 'Быть здоровым',
        index: 3,
      );
      await _selectParticipant(
        tester,
        repository,
        actionKey: 'relation-editor-select-related',
        catalogIndex: 2,
        title: 'Много ходить',
        index: 2,
      );
      await _selectType(tester, 'need');

      expect(find.text('the source intention'), findsNothing);
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
    await _openForm(tester, repository, IntentionRelationGroup.needs);
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
    await _openForm(tester, repository, IntentionRelationGroup.needs);
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
        IntentionRelationGroup.needs,
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
      expect(repository.relationWatches.last.relationId, existingId);
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

      const archivedNote =
          'Archived relations stay in saved paths and are not offered in new '
          'ones.';
      expect(find.text(archivedNote), findsOneWidget);
      expect(repository.relationCommands, hasLength(1));

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text(archivedNote), findsNothing);
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
    'успех открывает связь до предъявления сообщения и возвращает в исходную историю',
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
        IntentionRelationGroup.needs,
      );
      await _completeDraft(tester, repository);
      await _occupySharedSurface(tester, repository);

      expect(find.text(busyMessage), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('relation-editor-submit')));
      await tester.pump();
      final created = repository.completeRelationCreated(1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(repository.relationWatches.last.relationId, created.id);
      repository.relationWatches.last.emitDetails(
        testRelationDetails(
          relationId: created.id,
          sourceId: created.sourceIntentionId,
          relatedId: created.relatedIntentionId,
        ),
        revision: const TestCatalogRevision(2),
      );
      await tester.pumpAndSettle();

      expect(find.byType(RelationHead), findsOneWidget);
      expectIntentionGraphRootPage(router);
      expect(
        find.byKey(const ValueKey('relation-editor-submit')),
        findsNothing,
      );
      expect(find.text(busyMessage).hitTestable(), findsOneWidget);
      expect(find.text(successMessage), findsNothing);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(RelationHead), findsNothing);
      expectIntentionGraphRootPage(router);

      await _closeOperationMessage(tester);

      expect(find.text(successMessage), findsOneWidget);

      await _closeOperationMessage(tester);

      expect(find.text(successMessage), findsNothing);
    },
  );

  testWidgets(
    'сообщение об отказе, снятое правкой формы, предъявляется оболочкой один раз',
    (tester) async {
      const message = 'Only active intentions can be linked.';
      final repository = ControlledRelationFormRepository();
      addTearDown(repository.dispose);
      final router = await _openForm(
        tester,
        repository,
        IntentionRelationGroup.needs,
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

      expect(find.text(message), findsOneWidget);
      expect(find.text('Текущее намерение'), findsOneWidget);
      expect(find.text('Много ходить'), findsOneWidget);

      // Исправление участника снимает сообщение из формы, не уходя с маршрута.
      await _selectParticipant(
        tester,
        repository,
        actionKey: 'relation-editor-change-related',
        catalogIndex: 2,
        title: 'Другое намерение',
        index: 5,
      );

      expect(router.current.name, RelationEditorRoute.name);
      expect(find.text(message), findsNothing);

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
    'отказ создания остаётся в форме после перекрытия поиском и не повторяется в оболочке',
    (tester) async {
      const message = 'The relation couldn’t be created. Try again.';
      const shellMessage = 'Create — “new relation”: $message';
      final repository = ControlledRelationFormRepository();
      addTearDown(repository.dispose);
      final router = await _openForm(
        tester,
        repository,
        IntentionRelationGroup.needs,
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

  testWidgets('из подробного просмотра редактирует приоритет и описание '
      'архивной связи, а тип не предлагает', (tester) async {
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
    // Участники в редакторе связи — представление без поиска: тегов и условий в нём нет.
    expect(find.textContaining('Tags:'), findsNothing);
    expect(find.text('No tags'), findsNothing);
    // Участники существующей связи неизменны: слоты предлагают только переход.
    for (final role in RelationParticipantRole.values) {
      expect(
        find.byKey(ValueKey('relation-editor-select-${role.name}')),
        findsNothing,
      );
      expect(
        find.byKey(ValueKey('relation-editor-change-${role.name}')),
        findsNothing,
      );
      expect(
        find.byKey(ValueKey('relation-editor-open-${role.name}-details')),
        findsOneWidget,
      );
    }

    for (final type in LongTermRelationType.values) {
      expect(
        tester
            .widget<ChoiceChip>(
              find.byKey(ValueKey('relation-editor-type-${type.name}')),
            )
            .onSelected,
        isNull,
      );
    }
    await _selectPriority(tester, 'p4');
    await tester.enterText(
      find.byKey(const ValueKey('relation-editor-description')),
      'Новое описание',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('relation-editor-submit')));
    await tester.pump();

    expect(repository.relationUpdateCommands, hasLength(1));
    final command = repository.updateCommandAt(0);
    expect(command.relationId, details.relation.id);
    expect(command.patch.type, isA<LongTermRelationFieldUnchanged>());
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
      sourceIntentionId: details.relation.sourceIntentionId,
      relatedIntentionId: details.relation.relatedIntentionId,
      type: LongTermRelationType.can,
      priority: RelationPriority.p4,
      scope: RelationScope.archived,
      creationSequence: details.relation.creationSequence,
      createdAt: RelationTimestamp(DateTime.utc(2026)),
      updatedAt: RelationTimestamp(DateTime.utc(2026)),
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
    repository
        .watchAt(1)
        .emitDetails(
          testRelationDetails(
            relationId: updated.id,
            sourceId: updated.sourceIntentionId,
            relatedId: updated.relatedIntentionId,
            sourceTitle: 'Исходное',
            relatedTitle: 'Связанное',
            type: updated.type,
            priority: updated.priority,
            scope: updated.scope,
            creationSequence: updated.creationSequence.value,
            description: 'Новое описание',
          ),
          revision: const TestCatalogRevision(1),
        );
    await tester.pumpAndSettle();

    expect(find.text('To Исходное, you can Связанное'), findsOneWidget);
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
    'открытая форма получает подтверждённые снимки без потери черновика и ошибки изменения',
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
        const LongTermRelationUnexpectedFailure(),
      );
      await tester.pumpAndSettle();

      final renamed = testRelationDetails(
        relationId: relationId,
        sourceId: sourceId,
        relatedId: relatedId,
        sourceTitle: 'Исходное после переименования',
        relatedTitle: 'Связанное после переименования',
        relatedArchiveState: IntentionArchiveState.archived,
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
          'The relation couldn’t be updated because of an unexpected error.',
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
    },
  );

  testWidgets('отказ смены типа архивированной связи назван и снимается '
      'возвратом прежнего типа', (tester) async {
    final repository = ControlledRelationFormRepository();
    addTearDown(repository.dispose);
    final details = testRelationDetails(
      relationId: testFormRelationId(93),
      sourceId: testSummary(index: 1).id,
      relatedId: testSummary(index: 2).id,
      type: LongTermRelationType.need,
    );
    await _openDetailsForEditing(tester, repository, details);
    await tester.tap(
      find.byKey(const ValueKey('relation-details-edit-relation')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('relation-editor-type-can')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('relation-editor-submit')));
    await tester.pump();
    expect(repository.relationUpdateCommands, hasLength(1));

    repository.failRelationCommand(
      0,
      LongTermRelationArchivedTypeChangeFailure(testFormRelationId(93)),
    );
    await tester.pump();
    await tester.pump();

    const message = 'This relation is archived, so its type can’t be changed.';
    expect(find.text(message), findsOneWidget);
    expect(_isChipSelected(tester, 'relation-editor-type-can'), isTrue);

    await tester.tap(find.byKey(const ValueKey('relation-editor-type-need')));
    await tester.pumpAndSettle();

    expect(find.text(message), findsNothing);
  });

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
      IntentionRelationGroup.needs,
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

  testWidgets('форма проходит accessibility guidelines', (tester) async {
    final semantics = tester.ensureSemantics();

    final repository = ControlledRelationFormRepository();
    addTearDown(repository.dispose);
    await _openForm(tester, repository, IntentionRelationGroup.needs);
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
}) {
  final summary = testSummary(index: index, title: title);
  return RelationParticipantSummary(
    id: summary.id,
    title: summary.title,
    archiveState: summary.archiveState,
  );
}

Future<AppRouter> _openForm(
  WidgetTester tester,
  ControlledRelationFormRepository repository,
  IntentionRelationGroup? group, {
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
        inMemoryQuickCreationModeOverride,
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
      retry: (retryCount, error) => null,
      child: MaterialApp.router(
        theme: doableTheme(Brightness.light),
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
  await openIntentionGraph(tester);
  repository.completeCatalogPage(0, const []);
  await tester.pumpAndSettle();
  unawaited(
    router.push(
      RelationEditorRoute(
        editorContext: switch (group) {
          null => const RelationBlankCreationContext(),
          final group => RelationCreationContext(
            participant: _contextParticipant,
            group: group,
          ),
        },
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
        inMemoryQuickCreationModeOverride,
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
      retry: (retryCount, error) => null,
      child: MaterialApp.router(
        theme: doableTheme(Brightness.light),
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
  await openIntentionGraph(tester);
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
  void Function()? whilePickerOpen,
}) async {
  await tester.tap(find.byKey(ValueKey(actionKey)));
  await _settlePicker(tester);
  whilePickerOpen?.call();
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
