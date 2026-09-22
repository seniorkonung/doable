import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_description.dart';
import 'package:doable/src/long_term_relation/presentation/editor/relation_editor_state.dart';
import 'package:doable/src/long_term_relation/presentation/editor/relation_editor_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_test_support.dart';

void main() {
  group('Черновик создания связи', () {
    test('исходящая группа предвыбирает текущее намерение исходным', () {
      final harness = _EditorHarness.outgoing();

      expect(harness.state.sourceIntentionId, testEditorIntentionId(1));
      expect(harness.state.sourceParticipant?.title, 'Намерение 1');
      expect(harness.state.relatedIntentionId, isNull);
      expect(
        harness.state.completeness,
        isA<RelationDraftIncomplete>().having(
          (value) => value.missing,
          'недостающее',
          containsAll(<RelationDraftRequirement>[
            RelationDraftRequirement.relatedParticipant,
            RelationDraftRequirement.type,
            RelationDraftRequirement.priority,
          ]),
        ),
      );
      expect(harness.state.canSubmit, isFalse);
    });

    test('входящая группа предвыбирает текущее намерение связанным', () {
      final harness = _EditorHarness.incoming();

      expect(harness.state.relatedIntentionId, testEditorIntentionId(1));
      expect(harness.state.sourceIntentionId, isNull);
      expect(
        harness.state.completeness,
        isA<RelationDraftIncomplete>().having(
          (value) => value.missing,
          'недостающее',
          contains(RelationDraftRequirement.sourceParticipant),
        ),
      );
    });

    test('оба предвыбранных участника доступны для замены', () {
      final harness = _EditorHarness.outgoing();

      harness.viewModel
        ..selectParticipant(
          RelationParticipantRole.related,
          testEditorParticipant(2),
        )
        ..selectParticipant(
          RelationParticipantRole.source,
          testEditorParticipant(3),
        );

      expect(harness.state.sourceIntentionId, testEditorIntentionId(3));
      expect(harness.state.relatedIntentionId, testEditorIntentionId(2));
      expect(harness.state.sourceParticipant?.title, 'Намерение 3');
      expect(harness.state.relatedParticipant?.title, 'Намерение 2');
    });

    test('отсутствие явного приоритета не даёт готовой команды', () {
      final harness = _EditorHarness.outgoing();

      harness.viewModel
        ..selectParticipant(
          RelationParticipantRole.related,
          testEditorParticipant(2),
        )
        ..selectType(LongTermRelationType.need);

      expect(harness.state.priority, isNull);
      expect(
        harness.state.completeness,
        isA<RelationDraftIncomplete>().having(
          (value) => value.missing,
          'недостающее',
          <RelationDraftRequirement>{RelationDraftRequirement.priority},
        ),
      );
      expect(harness.state.canSubmit, isFalse);

      harness.viewModel.submit();
      expect(harness.repository.commandCount, isZero);

      harness.viewModel.selectPriority(RelationPriority.p3);
      expect(harness.state.completeness, isA<RelationDraftComplete>());
      expect(harness.state.canSubmit, isTrue);
    });

    test('отмена выбора участника сохраняет прежний черновик', () {
      final harness = _EditorHarness.outgoing()
        ..fillDraft(description: 'Черновик описания');

      // Отменённый выбор не сообщает ViewModel ничего, поэтому черновик
      // остаётся прежним целиком.
      expect(harness.state.relatedIntentionId, testEditorIntentionId(2));
      expect(harness.state.type, LongTermRelationType.need);
      expect(harness.state.priority, RelationPriority.p2);
      expect(harness.state.description, 'Черновик описания');
    });
  });

  group('Отправка черновика', () {
    test('отправляет проверенную команду ровно один раз', () async {
      final harness = _EditorHarness.outgoing()..fillDraft(description: '  ');

      harness.viewModel
        ..submit()
        ..submit();

      expect(harness.state.operation, isA<RelationEditorSubmitting>());
      expect(harness.repository.commandCount, 1);
      final command = harness.repository.createCommandAt(0);
      expect(command.sourceIntentionId, testEditorIntentionId(1));
      expect(command.relatedIntentionId, testEditorIntentionId(2));
      expect(command.type, LongTermRelationType.need);
      expect(command.priority, RelationPriority.p2);
      expect(command.description, isNull);

      harness.repository.completeRelationCreated(0);
      await harness.settle();

      expect(harness.repository.commandCount, 1);
    });

    test('успех даёт событие создания без права предъявления формы', () async {
      final harness = _EditorHarness.outgoing()..fillDraft();
      final presenter = harness.coordinator.registerAppPresentation();

      harness.viewModel.submit();
      final relation = harness.repository.completeRelationCreated(0);
      await harness.settle();

      expect(
        harness.state.operation,
        isA<RelationEditorSucceeded>().having(
          (value) => value.relation.id,
          'связь',
          relation.id,
        ),
      );
      expect(
        harness.state.event,
        isA<RelationEditorCreated>().having(
          (value) => value.relationId,
          'связь',
          relation.id,
        ),
      );
      expect(harness.state.failurePresentation, isNull);

      final claim = await presenter.nextClaim();
      expect(claim, isNotNull);
      harness.coordinator.confirmPresentation(claim!);

      harness.viewModel.consumeEvent();
      expect(harness.state.event, isNull);
    });

    test('ошибка сохраняет поля и выдаёт форме право предъявления', () async {
      final harness = _EditorHarness.outgoing()
        ..fillDraft(description: 'Сохранить буквально');

      harness.viewModel.submit();
      harness.repository.failRelationCommand(
        0,
        const LongTermRelationUnexpectedFailure(),
      );
      await harness.settle();

      expect(
        harness.state.operation,
        isA<RelationEditorFailed>().having(
          (value) => value.failure,
          'причина',
          isA<RelationEditorUnexpected>(),
        ),
      );
      expect(harness.state.description, 'Сохранить буквально');
      expect(harness.state.type, LongTermRelationType.need);
      expect(harness.state.priority, RelationPriority.p2);
      expect(harness.state.relatedIntentionId, testEditorIntentionId(2));
      expect(harness.state.sourceParticipant?.title, 'Намерение 1');
      expect(harness.state.relatedParticipant?.title, 'Намерение 2');
      expect(
        harness.state.failurePresentation,
        isA<GraphInitiatorPresentationClaim>(),
      );
    });
  });

  group('Черновик изменения связи', () {
    test('начинается с подтверждённой основы и требует явной правки', () {
      final details = testEditorRelationDetails();
      final harness = _EditorHarness.editing(details);

      expect(harness.state.context, isA<RelationEditingContext>());
      expect(harness.state.editingBasis, same(details));
      expect(harness.state.sourceParticipant, same(details.source));
      expect(harness.state.relatedParticipant, same(details.related));
      expect(harness.state.type, details.relation.type);
      expect(harness.state.priority, details.relation.priority);
      expect(harness.state.description, details.description?.value);
      expect(harness.state.hasChanges, isFalse);
      expect(harness.state.canSubmit, isFalse);
    });

    test('отправляет только изменённое описание через ключ связи', () async {
      final details = testEditorRelationDetails();
      final harness = _EditorHarness.editing(details);

      harness.viewModel
        ..changeDescription('Новое описание')
        ..submit();

      expect(harness.repository.commandCount, 1);
      final command = harness.repository.updateCommandAt(0);
      expect(command.relationId, details.relation.id);
      expect(command.patch.type, isA<LongTermRelationFieldUnchanged>());
      expect(command.patch.priority, isA<LongTermRelationFieldUnchanged>());
      expect(
        command.patch.sourceIntentionId,
        isA<LongTermRelationFieldUnchanged>(),
      );
      expect(
        command.patch.relatedIntentionId,
        isA<LongTermRelationFieldUnchanged>(),
      );
      expect(
        command.patch.description,
        isA<LongTermRelationDescriptionReplaced>().having(
          (value) => value.value.value,
          'текст',
          'Новое описание',
        ),
      );

      final after = LongTermRelation(
        id: details.relation.id,
        sourceIntentionId: details.relation.sourceIntentionId,
        relatedIntentionId: details.relation.relatedIntentionId,
        type: details.relation.type,
        priority: details.relation.priority,
        scope: RelationScope.archived,
        creationSequence: details.relation.creationSequence,
      );
      harness.repository.completeRelationUpdated(
        0,
        before: details.relation,
        after: after,
        description: LongTermRelationDescription.fromInput('Новое описание'),
      );
      await harness.settle();

      expect(
        harness.state.operation,
        isA<RelationEditorSucceeded>().having(
          (value) => value.relation.scope,
          'параллельный архив',
          RelationScope.archived,
        ),
      );
      expect(harness.state.event, isA<RelationEditorUpdated>());
    });

    test('очистка описания выражается отдельно от неизменённого поля', () {
      final harness = _EditorHarness.editing(testEditorRelationDetails());

      harness.viewModel
        ..changeDescription('   ')
        ..submit();

      final command = harness.repository.updateCommandAt(0);
      expect(
        command.patch.description,
        isA<LongTermRelationDescriptionCleared>(),
      );
      expect(command.patch.type, isA<LongTermRelationFieldUnchanged>());
    });

    test('пробельный ввод не меняет уже отсутствующее описание', () {
      final harness = _EditorHarness.editing(
        testEditorRelationDetails(description: null),
      );

      harness.viewModel.changeDescription('  \n ');

      expect(harness.state.hasChanges, isFalse);
      expect(harness.state.canSubmit, isFalse);
      harness.viewModel.submit();
      expect(harness.repository.commandCount, isZero);
    });

    test('возврат поля к исходному значению удаляет явную правку', () {
      final harness = _EditorHarness.editing(testEditorRelationDetails());

      harness.viewModel
        ..selectPriority(RelationPriority.p4)
        ..selectPriority(RelationPriority.p2);

      expect(harness.state.hasChanges, isFalse);
      expect(harness.state.canSubmit, isFalse);
      harness.viewModel.submit();
      expect(harness.repository.commandCount, isZero);
    });

    test(
      'фоновый снимок обновляет отображение, но не черновик и ошибку пары',
      () async {
        final details = testEditorRelationDetails();
        final harness = _EditorHarness.editing(details);
        harness.viewModel
          ..changeDescription('Введённый текст')
          ..submit();
        harness.repository.failRelationCommand(
          0,
          LongTermRelationPairOccupiedFailure(testRelationId(7)),
        );
        await harness.settle();
        final presentation = harness.state.failurePresentation;

        final refreshed = testEditorRelationDetails(
          type: LongTermRelationType.can,
          priority: RelationPriority.p4,
          description: 'Чужое изменение',
        );
        harness.viewModel.refreshConfirmedDetails(
          LongTermRelationDetails(
            relation: refreshed.relation,
            source: testEditorParticipant(1, title: 'Новое исходное название'),
            related: testEditorParticipant(
              2,
              title: 'Новое связанное название',
            ),
            description: refreshed.description,
          ),
        );

        expect(harness.state.description, 'Введённый текст');
        expect(harness.state.type, LongTermRelationType.need);
        expect(harness.state.priority, RelationPriority.p2);
        expect(harness.state.sourceIntentionId, testEditorIntentionId(1));
        expect(harness.state.relatedIntentionId, testEditorIntentionId(2));
        expect(
          harness.state.sourceParticipant?.title,
          'Новое исходное название',
        );
        expect(
          harness.state.relatedParticipant?.title,
          'Новое связанное название',
        );
        expect(
          harness.state.operation,
          isA<RelationEditorFailed>().having(
            (value) => value.failure,
            'ошибка',
            isA<RelationEditorPairOccupied>(),
          ),
        );
        expect(harness.state.failurePresentation, same(presentation));
      },
    );

    test('чужое изменение незапрошенного поля не входит в patch', () {
      final harness = _EditorHarness.editing(testEditorRelationDetails());

      harness.viewModel
        ..selectType(LongTermRelationType.can)
        ..refreshConfirmedDetails(
          testEditorRelationDetails(
            priority: RelationPriority.p4,
            description: 'Чужое описание',
          ),
        )
        ..submit();

      final patch = harness.repository.updateCommandAt(0).patch;
      expect(
        patch.type,
        isA<LongTermRelationFieldSet<LongTermRelationType>>().having(
          (value) => value.value,
          'тип',
          LongTermRelationType.can,
        ),
      );
      expect(patch.priority, isA<LongTermRelationFieldUnchanged>());
      expect(patch.description, isA<LongTermRelationDescriptionUnchanged>());
    });

    test('явно заменённые участник и приоритет входят в patch', () {
      final harness = _EditorHarness.editing(testEditorRelationDetails());

      harness.viewModel
        ..selectParticipant(
          RelationParticipantRole.related,
          testEditorParticipant(3),
        )
        ..selectPriority(RelationPriority.p4)
        ..submit();

      final patch = harness.repository.updateCommandAt(0).patch;
      expect(
        patch.relatedIntentionId,
        isA<LongTermRelationFieldSet<IntentionId>>().having(
          (value) => value.value,
          'участник',
          testEditorIntentionId(3),
        ),
      );
      expect(
        patch.priority,
        isA<LongTermRelationFieldSet<RelationPriority>>().having(
          (value) => value.value,
          'приоритет',
          RelationPriority.p4,
        ),
      );
      expect(patch.type, isA<LongTermRelationFieldUnchanged>());
      expect(patch.description, isA<LongTermRelationDescriptionUnchanged>());
    });

    test('отказ сохраняет обе ссылки, а исправленная отправка получает новый token', () async {
      final harness = _EditorHarness.editing(testEditorRelationDetails());
      final tokens = <LongTermRelationOperationToken>[];
      final subscription = harness.coordinator.completions.listen((completion) {
        if (completion is LongTermRelationCommandCompletion) {
          tokens.add(completion.token);
        }
      });
      addTearDown(subscription.cancel);

      harness.viewModel
        ..selectParticipant(
          RelationParticipantRole.related,
          testEditorParticipant(3),
        )
        ..submit();
      harness.repository.failRelationCommand(
        0,
        LongTermRelationParticipantArchivedFailure(
          role: RelationParticipantRole.related,
          intentionId: testEditorIntentionId(3),
        ),
      );
      await harness.settle();

      expect(harness.state.sourceParticipant?.id, testEditorIntentionId(1));
      expect(harness.state.relatedParticipant?.id, testEditorIntentionId(3));

      harness.viewModel
        ..selectParticipant(
          RelationParticipantRole.related,
          testEditorParticipant(4),
        )
        ..submit();
      expect(harness.repository.commandCount, 2);
      expect(tokens, hasLength(1));

      harness.repository.failRelationCommand(
        1,
        const LongTermRelationUnavailableFailure(),
      );
      await harness.settle();

      expect(tokens, hasLength(2));
      expect(identical(tokens.first, tokens.last), isFalse);
      expect(harness.state.relatedParticipant?.id, testEditorIntentionId(4));
    });

    test(
      'отсутствующая связь сохраняет черновик и блокирует тот же контекст',
      () async {
        final harness = _EditorHarness.editing(testEditorRelationDetails());
        harness.viewModel
          ..selectPriority(RelationPriority.p3)
          ..submit();
        harness.repository.failRelationCommand(
          0,
          LongTermRelationNotFoundFailure(testRelationId(1)),
        );
        await harness.settle();

        expect(harness.state.priority, RelationPriority.p3);
        expect(
          harness.state.operation,
          isA<RelationEditorFailed>().having(
            (value) => value.failure,
            'ошибка',
            isA<RelationEditorRelationNotFound>(),
          ),
        );
        expect(harness.state.canSubmit, isFalse);
        harness.viewModel.submit();
        expect(harness.repository.commandCount, 1);
      },
    );

    test('уход не сохраняет отменённый черновик', () async {
      final harness = _EditorHarness.editing(testEditorRelationDetails());
      harness.viewModel.changeDescription('Отменённая правка');

      harness.leaveForm();
      await harness.settle();

      expect(harness.repository.commandCount, isZero);
    });

    test('принятое изменение продолжается после ухода', () async {
      final details = testEditorRelationDetails();
      final harness = _EditorHarness.editing(details);
      final presenter = harness.coordinator.registerAppPresentation();
      harness.viewModel
        ..selectPriority(RelationPriority.p3)
        ..submit();

      harness.leaveForm();
      await harness.settle();
      harness.repository.failRelationCommand(
        0,
        const LongTermRelationUnavailableFailure(),
      );
      await harness.settle();

      final claim = await presenter.nextClaim();
      expect(claim, isNotNull);
      expect(claim!.completion.isFailure, isTrue);
      expect(harness.repository.commandCount, 1);
      harness.coordinator.confirmPresentation(claim);
    });
  });

  group('Отдельные причины отказа', () {
    test('описание из 4097 графем остаётся доступным для исправления', () {
      final tooLong =
          'я' * (LongTermRelationDescription.maxGraphemeClusters + 1);
      final harness = _EditorHarness.outgoing()
        ..fillDraft(description: tooLong);

      harness.viewModel.submit();

      expect(harness.repository.commandCount, isZero);
      expect(harness.state.description, tooLong);
      expect(
        harness.state.operation,
        isA<RelationEditorFailed>().having(
          (value) => value.failure,
          'причина',
          isA<RelationEditorDescriptionInvalid>().having(
            (value) => value.failure.reason,
            'причина текста',
            LongTermRelationTextValidationReason.tooLong,
          ),
        ),
      );
      expect(harness.state.canSubmit, isFalse);

      harness.viewModel.changeDescription('Короткое описание');
      expect(harness.state.operation, isA<RelationEditorIdle>());
      expect(harness.state.canSubmit, isTrue);
    });

    test('недопустимый Unicode отличается от превышения длины', () {
      final invalid = 'Описание${String.fromCharCode(0)}';
      final harness = _EditorHarness.outgoing()
        ..fillDraft(description: invalid);

      harness.viewModel.submit();

      expect(harness.repository.commandCount, isZero);
      expect(harness.state.description, invalid);
      expect(
        harness.state.operation,
        isA<RelationEditorFailed>().having(
          (value) => value.failure,
          'причина',
          isA<RelationEditorDescriptionInvalid>().having(
            (value) => value.failure.reason,
            'причина текста',
            LongTermRelationTextValidationReason.invalidUnicodeRepertoire,
          ),
        ),
      );
    });

    final pairFailureCases =
        <
          ({
            String name,
            LongTermRelationCommandFailure repositoryFailure,
            Matcher editorFailure,
          })
        >[
          (
            name: 'занятая пара',
            repositoryFailure: LongTermRelationPairOccupiedFailure(
              testRelationId(7),
            ),
            editorFailure: isA<RelationEditorPairOccupied>().having(
              (value) => value.existingRelationId,
              'существующая связь',
              testRelationId(7),
            ),
          ),
          (
            name: 'совпадающие участники',
            repositoryFailure: const LongTermRelationCommandValidationFailure(
              CreateLongTermRelationValidationFailure.sameIntention,
            ),
            editorFailure: isA<RelationEditorSameParticipants>(),
          ),
        ];

    for (final failureCase in pairFailureCases) {
      for (final role in RelationParticipantRole.values) {
        final roleName = switch (role) {
          RelationParticipantRole.source => 'исходного участника',
          RelationParticipantRole.related => 'связанного участника',
        };

        test(
          '${failureCase.name}: снимок $roleName не исправляет прежнюю пару',
          () async {
            final harness = _EditorHarness.outgoing()..fillDraft();

            harness.viewModel.submit();
            harness.repository.failRelationCommand(
              0,
              failureCase.repositoryFailure,
            );
            await harness.settle();

            final presentation = harness.state.failurePresentation;
            expect(presentation, isNotNull);
            expect(
              harness.state.operation,
              isA<RelationEditorFailed>().having(
                (value) => value.failure,
                'причина',
                failureCase.editorFailure,
              ),
            );

            final currentIndex = switch (role) {
              RelationParticipantRole.source => 1,
              RelationParticipantRole.related => 2,
            };
            harness.viewModel.selectParticipant(
              role,
              testEditorParticipant(
                currentIndex,
                title: 'Обновлённое намерение $currentIndex',
                archiveState: IntentionArchiveState.archived,
                activeRelationCount: 7,
              ),
            );

            final updatedParticipant = switch (role) {
              RelationParticipantRole.source => harness.state.sourceParticipant,
              RelationParticipantRole.related =>
                harness.state.relatedParticipant,
            };
            expect(
              updatedParticipant?.title,
              'Обновлённое намерение $currentIndex',
            );
            expect(
              updatedParticipant?.archiveState,
              IntentionArchiveState.archived,
            );
            expect(updatedParticipant?.activeRelationCount, 7);
            expect(
              harness.state.operation,
              isA<RelationEditorFailed>().having(
                (value) => value.failure,
                'причина',
                failureCase.editorFailure,
              ),
            );
            expect(harness.state.failurePresentation, same(presentation));
            expect(harness.state.canSubmit, isFalse);

            harness.viewModel.submit();
            expect(harness.repository.commandCount, 1);

            harness.viewModel.selectParticipant(role, testEditorParticipant(5));

            expect(harness.state.operation, isA<RelationEditorIdle>());
            expect(harness.state.failurePresentation, isNull);
            expect(harness.state.canSubmit, isTrue);

            harness.viewModel.submit();
            expect(harness.repository.commandCount, 2);
            final corrected = harness.repository.createCommandAt(1);
            expect(switch (role) {
              RelationParticipantRole.source => corrected.sourceIntentionId,
              RelationParticipantRole.related => corrected.relatedIntentionId,
            }, testEditorIntentionId(5));
            expect(
              switch (role) {
                RelationParticipantRole.source => corrected.relatedIntentionId,
                RelationParticipantRole.related => corrected.sourceIntentionId,
              },
              switch (role) {
                RelationParticipantRole.source => testEditorIntentionId(2),
                RelationParticipantRole.related => testEditorIntentionId(1),
              },
            );

            harness.repository.completeRelationCreated(1, revision: 2);
            await harness.settle();
          },
        );
      }
    }

    test('архивированный участник называет свою роль', () async {
      final harness = _EditorHarness.outgoing()
        ..fillDraft(description: 'Описание');

      harness.viewModel.submit();
      harness.repository.failRelationCommand(
        0,
        LongTermRelationParticipantArchivedFailure(
          role: RelationParticipantRole.related,
          intentionId: testEditorIntentionId(2),
        ),
      );
      await harness.settle();

      expect(
        harness.state.operation,
        isA<RelationEditorFailed>().having(
          (value) => value.failure,
          'причина',
          isA<RelationEditorParticipantRejected>()
              .having(
                (value) => value.role,
                'роль',
                RelationParticipantRole.related,
              )
              .having(
                (value) => value.rejection,
                'состояние',
                RelationParticipantRejection.archived,
              ),
        ),
      );
      expect(harness.state.description, 'Описание');
      expect(harness.state.relatedParticipant?.title, 'Намерение 2');

      // Исправляет только замена отклонённого участника.
      harness.viewModel.selectParticipant(
        RelationParticipantRole.source,
        testEditorParticipant(4),
      );
      expect(harness.state.operation, isA<RelationEditorFailed>());

      harness.viewModel.selectParticipant(
        RelationParticipantRole.related,
        testEditorParticipant(5),
      );
      expect(harness.state.operation, isA<RelationEditorIdle>());
    });

    test('удалённый участник отличается от архивированного', () async {
      final harness = _EditorHarness.outgoing()..fillDraft();

      harness.viewModel.submit();
      harness.repository.failRelationCommand(
        0,
        LongTermRelationParticipantNotFoundFailure(
          role: RelationParticipantRole.source,
          intentionId: testEditorIntentionId(1),
        ),
      );
      await harness.settle();

      expect(
        harness.state.operation,
        isA<RelationEditorFailed>().having(
          (value) => value.failure,
          'причина',
          isA<RelationEditorParticipantRejected>().having(
            (value) => value.rejection,
            'состояние',
            RelationParticipantRejection.missing,
          ),
        ),
      );
      expect(harness.state.sourceParticipant?.id, testEditorIntentionId(1));
      expect(harness.state.sourceParticipant?.title, 'Намерение 1');
    });

    test('исправленная повторная отправка получает новый token', () async {
      final harness = _EditorHarness.outgoing()..fillDraft();
      final tokens = <LongTermRelationOperationToken>[];
      final subscription = harness.coordinator.completions.listen((completion) {
        if (completion is LongTermRelationCommandCompletion) {
          tokens.add(completion.token);
        }
      });
      addTearDown(subscription.cancel);

      harness.viewModel.submit();
      harness.repository.failRelationCommand(
        0,
        const LongTermRelationUnavailableFailure(),
      );
      await harness.settle();

      expect(harness.state.canRetry, isTrue);
      expect(harness.state.canSubmit, isTrue);

      harness.viewModel.submit();
      expect(harness.repository.commandCount, 2);
      expect(harness.state.operation, isA<RelationEditorSubmitting>());

      harness.repository.completeRelationCreated(1, revision: 2);
      await harness.settle();

      expect(tokens, hasLength(2));
      expect(identical(tokens.first, tokens.last), isFalse);
      expect(harness.state.operation, isA<RelationEditorSucceeded>());
    });
  });

  test('уход из формы завершает черновик, не отменяя выполнение', () async {
    final harness = _EditorHarness.outgoing()..fillDraft();
    final presenter = harness.coordinator.registerAppPresentation();

    harness.viewModel.submit();
    expect(harness.repository.commandCount, 1);

    harness.leaveForm();
    await harness.settle();
    harness.repository.failRelationCommand(
      0,
      const LongTermRelationUnexpectedFailure(),
    );
    await harness.settle();

    final claim = await presenter.nextClaim();
    expect(claim, isNotNull);
    expect(claim!.completion.isFailure, isTrue);
    expect(harness.repository.commandCount, 1);
    harness.coordinator.confirmPresentation(claim);
  });
}

/// Одна открытая форма связи поверх управляемого графа.
final class _EditorHarness {
  _EditorHarness(RelationEditorContext context)
    : provider = relationEditorViewModelProvider(
        LongTermRelationCreationFormKey(),
        context,
      ) {
    container = ProviderContainer.test(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    _subscription = container.listen(provider, (_, _) {});
    addTearDown(leaveForm);
  }

  factory _EditorHarness.outgoing() => _EditorHarness(
    RelationCreationContext(
      participant: testEditorParticipant(1),
      direction: RelationDirection.outgoing,
    ),
  );

  factory _EditorHarness.incoming() => _EditorHarness(
    RelationCreationContext(
      participant: testEditorParticipant(1),
      direction: RelationDirection.incoming,
    ),
  );

  factory _EditorHarness.editing(LongTermRelationDetails details) =>
      _EditorHarness(RelationEditingContext(details));

  final RelationEditorViewModelProvider provider;
  final repository = ControlledRelationEditorRepository();
  late final ProviderContainer container;
  ProviderSubscription<RelationEditorState>? _subscription;

  GraphCommandCoordinator get coordinator =>
      container.read(graphCommandCoordinatorProvider.notifier);

  RelationEditorViewModel get viewModel => container.read(provider.notifier);

  RelationEditorState get state => container.read(provider);

  void fillDraft({String description = ''}) {
    viewModel
      ..selectParticipant(
        RelationParticipantRole.related,
        testEditorParticipant(2),
      )
      ..selectType(LongTermRelationType.need)
      ..selectPriority(RelationPriority.p2)
      ..changeDescription(description);
  }

  /// Завершает экранную сессию формы, не трогая принятое выполнение.
  void leaveForm() {
    _subscription?.close();
    _subscription = null;
  }

  Future<void> settle() async {
    await container.pump();
    await container.pump();
  }
}
