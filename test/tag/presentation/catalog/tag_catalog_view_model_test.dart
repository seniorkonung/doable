import 'dart:async';

import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_assignment_status.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_assignment.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_state.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_view_model.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/tag_assignment_changed.dart';

void main() {
  test('отсутствие намерения не отменяется поздним полным снимком', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.repository.page(0, []);
    await pumpEventQueue();
    h.model.setMode(TagCatalogSelectionMode(_intentionId(1)));
    h.repository.selectionPage(1, _intentionId(1), [
      TagSelectionRow(tag: _tag(1, 'Дом'), isAssigned: false),
    ]);
    await pumpEventQueue();
    h.model.selectTag(_id(52));
    h.repository.tagRead(_tag(52, 'Из редактора'));
    await h.renamed(_tag(1, 'Дом'), _tag(1, 'Быт'), revision: 2);
    h.repository.statusReads.last.complete(
      const TagAssignmentStatusError(TagAssignmentStatusIntentionNotFound()),
    );
    await pumpEventQueue();
    expect(h.state, isA<TagCatalogIntentionMissing>());

    h.repository.selectionPage(2, _intentionId(1), [
      TagSelectionRow(tag: _tag(52, 'Из редактора'), isAssigned: false),
    ], revision: 2);
    await pumpEventQueue();
    expect(h.state, isA<TagCatalogIntentionMissing>());
    expect(h.model.assignSelected(), isNull);

    await h.renamed(_tag(1, 'Быт'), _tag(1, 'Новое имя'), revision: 3);
    await pumpEventQueue();
    expect(h.state, isA<TagCatalogIntentionMissing>());
    expect(h.repository.queries, hasLength(3));
  });

  test(
    'выбор показывает назначения и назначает тег только по явной команде',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.model.setMode(TagCatalogSelectionMode(_intentionId(1)));
      expect(h.repository.queries.single, const TagCatalogBrowseMode());
      h.repository.page(0, [_tag(9, 'Старый')]);
      await pumpEventQueue();
      expect(h.repository.queries[1], TagCatalogSelectionMode(_intentionId(1)));
      h.repository.selectionPage(1, _intentionId(1), [
        TagSelectionRow(tag: _tag(1, 'Дом'), isAssigned: true),
        TagSelectionRow(tag: _tag(2, 'Работа'), isAssigned: false),
      ]);
      await pumpEventQueue();
      final loaded = h.state as TagCatalogLoaded;
      expect(loaded.mode, TagCatalogSelectionMode(_intentionId(1)));
      expect(loaded.selectionRows.map((row) => row.isAssigned), [true, false]);
      expect(h.repository.commands, isEmpty);

      h.model.selectTag(_id(2));
      h.repository.tagRead(_tag(2, 'Работа'));
      await pumpEventQueue();
      expect(h.model.assignSelected(), isA<TagCommandAccepted>());
      expect(h.repository.commands, hasLength(1));
      expect(
        (h.state as TagCatalogLoaded).assignmentStatus,
        isA<TagCatalogAssignmentSubmitting>(),
      );
      h.repository.completeCommand(
        testTagAssignmentChanged(
          TagAssignmentChangedChange(
            revision: const _Revision(2),
            assignment: TagAssignment(
              tagId: _id(2),
              intentionId: _intentionId(1),
            ),
            state: TagAssignmentState.assigned,
          ),
        ),
        const _Revision(2),
      );
      await pumpEventQueue();
      expect(
        (h.state as TagCatalogLoaded).assignmentStatus,
        isA<TagCatalogAssignmentIdle>(),
      );
      expect(
        h.repository.queries.last,
        TagCatalogSelectionMode(_intentionId(1)),
      );
    },
  );

  test('смена получателя отбрасывает поздний снимок и прежний выбор', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.repository.page(0, [_tag(1, 'Дом')]);
    await pumpEventQueue();
    h.model.setMode(TagCatalogSelectionMode(_intentionId(1)));
    h.repository.selectionPage(1, _intentionId(1), [
      TagSelectionRow(tag: _tag(1, 'Дом'), isAssigned: false),
    ]);
    await pumpEventQueue();
    h.model.selectTag(_id(52));
    h.repository.tagRead(_tag(52, 'Созданный'));
    await pumpEventQueue();
    expect((h.state as TagCatalogLoaded).selection.id, _id(52));

    await h.renamed(_tag(1, 'Дом'), _tag(1, 'Быт'), revision: 2);
    h.model.setMode(TagCatalogSelectionMode(_intentionId(2)));
    h.repository.statusRead(0, false);
    h.repository.selectionPage(2, _intentionId(1), [
      TagSelectionRow(tag: _tag(1, 'Быт'), isAssigned: true),
    ], revision: 2);
    await pumpEventQueue();
    expect(h.repository.queries[3], TagCatalogSelectionMode(_intentionId(2)));
    h.repository.selectionPage(3, _intentionId(2), [
      TagSelectionRow(tag: _tag(3, 'Новый'), isAssigned: true),
    ], revision: 2);
    await pumpEventQueue();
    final loaded = h.state as TagCatalogLoaded;
    expect(loaded.mode, TagCatalogSelectionMode(_intentionId(2)));
    expect(loaded.items.map((tag) => tag.id), [_id(3)]);
    expect(loaded.selection, isA<TagCatalogNoSelection>());
    expect(h.model.assignSelected(), isNull);
  });

  test(
    'отсутствие выбранного тега раньше пакета убирает строку выбора',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.repository.page(0, []);
      await pumpEventQueue();
      h.model.setMode(TagCatalogSelectionMode(_intentionId(1)));
      h.repository.selectionPage(1, _intentionId(1), [
        TagSelectionRow(tag: _tag(1, 'Дом'), isAssigned: false),
      ]);
      await pumpEventQueue();
      h.model.selectTag(_id(1));
      h.repository.tagRead(_tag(1, 'Дом'));
      await pumpEventQueue();
      h.repository.tagRead(null, revision: 2);
      await pumpEventQueue();
      final refreshing = h.state as TagCatalogLoaded;
      expect(refreshing.items, isEmpty);
      expect(refreshing.selectionRows, isEmpty);
      expect(refreshing.selection, isA<TagCatalogNoSelection>());
      expect(h.model.assignSelected(), isNull);
      h.repository.selectionPage(2, _intentionId(1), [
        TagSelectionRow(tag: _tag(1, 'Дом'), isAssigned: false),
      ]);
      await pumpEventQueue();
      h.repository.selectionPage(3, _intentionId(1), [], revision: 2);
      await pumpEventQueue();
      expect((h.state as TagCatalogLoaded).selectionRows, isEmpty);
    },
  );

  test('отсутствие получателя и занятый ключ прекращают назначение', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.repository.page(0, []);
    await pumpEventQueue();
    h.model.setMode(TagCatalogSelectionMode(_intentionId(1)));
    h.repository.fail(1, const TagCatalogIntentionNotFound());
    await pumpEventQueue();
    expect(h.state, isA<TagCatalogIntentionMissing>());
    expect(h.model.assignSelected(), isNull);

    h.model.setMode(TagCatalogSelectionMode(_intentionId(2)));
    h.repository.selectionPage(2, _intentionId(2), [
      TagSelectionRow(tag: _tag(2, 'Работа'), isAssigned: false),
    ]);
    await pumpEventQueue();
    h.model.selectTag(_id(2));
    h.repository.tagRead(_tag(2, 'Работа'));
    await pumpEventQueue();
    final original = h.coordinator.acceptTagAssign(
      AssignTag(tagId: _id(9), intentionId: _intentionId(2)),
    ) as TagCommandAccepted;
    expect(h.model.assignSelected(), isA<TagCommandAlreadyRunning>());
    expect(
      (h.state as TagCatalogLoaded).assignmentStatus,
      isA<TagCatalogAssignmentKeysBusy>(),
    );
    h.repository.completeCommandFailure(const TagUnavailableFailure());
    await original.future;
    await pumpEventQueue();
    expect(
      (h.state as TagCatalogLoaded).assignmentStatus,
      isA<TagCatalogAssignmentIdle>(),
    );
  });

  test('отсутствие получателя в результате команды закрывает выбор', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.repository.page(0, []);
    await pumpEventQueue();
    h.model.setMode(TagCatalogSelectionMode(_intentionId(1)));
    h.repository.selectionPage(1, _intentionId(1), [
      TagSelectionRow(tag: _tag(1, 'Дом'), isAssigned: false),
    ]);
    await pumpEventQueue();
    h.model.selectTag(_id(1));
    h.repository.tagRead(_tag(1, 'Дом'));
    await pumpEventQueue();
    final started = h.model.assignSelected() as TagCommandAccepted;
    h.repository.completeCommandFailure(
      TagIntentionNotFoundFailure(_intentionId(1)),
    );
    await started.future;
    expect(h.state, isA<TagCatalogIntentionMissing>());
    expect(h.model.assignSelected(), isNull);
  });

  test(
    'отсутствие тега в результате команды убирает строку и действие',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.repository.page(0, []);
      await pumpEventQueue();
      h.model.setMode(TagCatalogSelectionMode(_intentionId(1)));
      h.repository.selectionPage(1, _intentionId(1), [
        TagSelectionRow(tag: _tag(1, 'Дом'), isAssigned: false),
      ]);
      await pumpEventQueue();
      h.model.selectTag(_id(1));
      h.repository.tagRead(_tag(1, 'Дом'));
      await pumpEventQueue();
      final started = h.model.assignSelected() as TagCommandAccepted;
      h.repository.completeCommandFailure(TagNotFoundFailure(_id(1)));
      await started.future;
      final refreshing = h.state as TagCatalogLoaded;
      expect(refreshing.items, isEmpty);
      expect(refreshing.selectionRows, isEmpty);
      expect(refreshing.selection, isA<TagCatalogNoSelection>());
      expect(h.model.assignSelected(), isNull);
      h.repository.selectionPage(2, _intentionId(1), [], revision: 2);
      await pumpEventQueue();
      expect((h.state as TagCatalogLoaded).items, isEmpty);
    },
  );

  test('выбор из редактора сохраняет id после переименования и полной актуализации', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.repository.page(0, []);
    await pumpEventQueue();
    h.model.setMode(TagCatalogSelectionMode(_intentionId(1)));
    h.repository.selectionPage(1, _intentionId(1), [
      TagSelectionRow(tag: _tag(1, 'Дом'), isAssigned: true),
    ]);
    await pumpEventQueue();
    h.model.selectTag(_id(1));
    expect(h.model.assignSelected(), isNull);

    h.model.selectTag(_id(52));
    h.repository.tagRead(_tag(52, 'Старое'));
    await pumpEventQueue();
    await h.renamed(_tag(52, 'Старое'), _tag(52, 'Новое'), revision: 2);
    final refreshing = h.state as TagCatalogLoaded;
    expect(refreshing.selection.id, _id(52));
    expect(
      (refreshing.selection as TagCatalogSelectionReady).tag.name.value,
      'Новое',
    );
    expect(h.model.assignSelected(), isNull);
    h.repository.selectionPage(2, _intentionId(1), [
      TagSelectionRow(tag: _tag(1, 'Дом'), isAssigned: true),
      TagSelectionRow(tag: _tag(52, 'Новое'), isAssigned: false),
    ], revision: 2);
    await pumpEventQueue();
    expect(h.model.assignSelected(), isA<TagCommandAccepted>());
    h.repository.completeCommand(
      testTagAssignmentChanged(
        TagAssignmentChangedChange(
          revision: const _Revision(3),
          assignment: TagAssignment(
            tagId: _id(52),
            intentionId: _intentionId(1),
          ),
          state: TagAssignmentState.assigned,
        ),
      ),
      const _Revision(3),
    );
    await pumpEventQueue();
  });

  test('пакет назначения обновляет признак строки до нового снимка', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.repository.page(0, []);
    await pumpEventQueue();
    h.model.setMode(TagCatalogSelectionMode(_intentionId(1)));
    h.repository.selectionPage(1, _intentionId(1), [
      TagSelectionRow(tag: _tag(1, 'Дом'), isAssigned: false),
    ]);
    await pumpEventQueue();
    final original = h.coordinator.acceptTagAssign(
      AssignTag(tagId: _id(1), intentionId: _intentionId(1)),
    ) as TagCommandAccepted;
    h.repository.completeCommand(
      testTagAssignmentChanged(
        TagAssignmentChangedChange(
          revision: const _Revision(2),
          assignment: TagAssignment(
            tagId: _id(1),
            intentionId: _intentionId(1),
          ),
          state: TagAssignmentState.assigned,
        ),
      ),
      const _Revision(2),
    );
    await original.future;
    final refreshing = h.state as TagCatalogLoaded;
    expect(refreshing.selectionRows.single.isAssigned, isTrue);
    expect(refreshing.freshness, TagCatalogFreshness.refreshing);
    h.repository.selectionPage(2, _intentionId(1), [
      TagSelectionRow(tag: _tag(1, 'Дом'), isAssigned: true),
    ], revision: 2);
    await pumpEventQueue();
    expect(
      (h.state as TagCatalogLoaded).selectionRows.single.isAssigned,
      isTrue,
    );
    expect(
      (h.state as TagCatalogLoaded).freshness,
      TagCatalogFreshness.current,
    );
  });

  for (final (intentionId, recipient) in [
    (_intentionId(1), 'намерения'),
    (_intentionId(2), 'другого намерения'),
  ]) {
    for (final assigned in [false, true]) {
      test(
        'повтор восстанавливает бюджет устаревших проверок $recipient: ${assigned ? 'назначен' : 'свободен'}',
        () async {
          final h = _Harness();
          addTearDown(h.dispose);
          h.repository.page(0, []);
          await pumpEventQueue();
          h.model.setMode(TagCatalogSelectionMode(intentionId));
          h.repository.selectionPage(1, intentionId, [
            TagSelectionRow(tag: _tag(1, 'Первый'), isAssigned: false),
          ], revision: 2);
          await pumpEventQueue();
          h.model.selectTag(_id(52));
          h.repository.tagRead(_tag(52, 'Из редактора'), revision: 2);
          await pumpEventQueue();

          for (var index = 0; index < 8; index++) {
            h.repository.statusRead(index, false, revision: 1);
            await pumpEventQueue();
          }
          expect(h.repository.statusQueries, hasLength(8));
          expect(
            (h.state as TagCatalogLoaded).selectedAssignment,
            TagCatalogSelectedAssignment.unavailable,
          );
          expect(h.model.assignSelected(), isNull);

          h.model.retrySelectedAssignment();
          expect(h.repository.statusQueries, hasLength(9));
          for (var index = 8; index < 11; index++) {
            h.repository.statusRead(index, false, revision: 1);
            await pumpEventQueue();
            expect(
              (h.state as TagCatalogLoaded).selectedAssignment,
              TagCatalogSelectedAssignment.unknown,
            );
            expect(h.repository.statusQueries, hasLength(index + 2));
            expect(h.model.assignSelected(), isNull);
          }
          h.repository.statusRead(11, assigned, revision: 2);
          await pumpEventQueue();
          expect(
            (h.state as TagCatalogLoaded).selectedAssignment,
            assigned
                ? TagCatalogSelectedAssignment.assigned
                : TagCatalogSelectedAssignment.available,
          );
          expect(
            h.model.assignSelected(),
            assigned ? isNull : isA<TagCommandAccepted>(),
          );
        },
      );
    }
    for (final assigned in [false, true]) {
      test(
        'поздний отказ проверки не заменяет статус полного снимка для $recipient: ${assigned ? 'назначен' : 'свободен'}',
        () async {
          final h = _Harness();
          addTearDown(h.dispose);
          h.repository.page(0, []);
          await pumpEventQueue();
          h.model.setMode(TagCatalogSelectionMode(intentionId));
          h.repository.selectionPage(1, intentionId, [
            TagSelectionRow(tag: _tag(1, 'Первый'), isAssigned: false),
          ]);
          await pumpEventQueue();
          h.model.selectTag(_id(52));
          h.repository.tagRead(_tag(52, 'Из редактора'));
          await pumpEventQueue();
          expect(h.repository.statusQueries.single, (_id(52), intentionId));
          expect(h.model.assignSelected(), isNull);

          await h.created(_tag(52, 'Из редактора'), revision: 2);
          h.repository.selectionPage(2, intentionId, [
            TagSelectionRow(
              tag: _tag(52, 'Из редактора'),
              isAssigned: assigned,
            ),
          ], revision: 2);
          await pumpEventQueue();
          expect(
            (h.state as TagCatalogLoaded).selectedAssignment,
            assigned
                ? TagCatalogSelectedAssignment.assigned
                : TagCatalogSelectedAssignment.available,
          );

          h.repository.statusReads.first.complete(
            const TagAssignmentStatusError(TagAssignmentStatusUnavailable()),
          );
          await pumpEventQueue();
          expect(
            (h.state as TagCatalogLoaded).selectedAssignment,
            assigned
                ? TagCatalogSelectedAssignment.assigned
                : TagCatalogSelectedAssignment.available,
          );
          expect(h.repository.statusQueries, hasLength(2));
          expect(
            h.model.assignSelected(),
            assigned ? isNull : isA<TagCommandAccepted>(),
          );
        },
      );
    }
    for (final assigned in [false, true]) {
      for (final tagReadFirst in [false, true]) {
        test(
          'повтор проверки пары $recipient после ${tagReadFirst ? 'раннего' : 'позднего'} наблюдения тега: ${assigned ? 'назначен' : 'свободен'}',
          () async {
            final h = _Harness();
            addTearDown(h.dispose);
            h.repository.page(0, []);
            await pumpEventQueue();
            h.model.setMode(TagCatalogSelectionMode(intentionId));
            h.repository.selectionPage(1, intentionId, [
              TagSelectionRow(tag: _tag(1, 'Первый'), isAssigned: false),
            ]);
            await pumpEventQueue();
            h.model.selectTag(_id(52));
            if (tagReadFirst) h.repository.tagRead(_tag(52, 'Из редактора'));
            h.repository.statusReads.single.complete(
              const TagAssignmentStatusError(TagAssignmentStatusUnavailable()),
            );
            await pumpEventQueue();
            if (!tagReadFirst) {
              h.repository.tagRead(_tag(52, 'Из редактора'));
              await pumpEventQueue();
            }
            expect(
              (h.state as TagCatalogLoaded).selectedAssignment,
              TagCatalogSelectedAssignment.unavailable,
            );
            expect(h.model.assignSelected(), isNull);
            h.model.retrySelectedAssignment();
            expect(h.repository.statusQueries, hasLength(2));
            expect(h.model.assignSelected(), isNull);
            h.repository.statusRead(1, assigned);
            await pumpEventQueue();
            expect(
              (h.state as TagCatalogLoaded).selectedAssignment,
              assigned
                  ? TagCatalogSelectedAssignment.assigned
                  : TagCatalogSelectedAssignment.available,
            );
            expect(
              h.model.assignSelected(),
              assigned ? isNull : isA<TagCommandAccepted>(),
            );
          },
        );
      }
    }
    for (final assigned in [false, true]) {
      test(
        'точечное чтение выбора из редактора до обновления снимка для $recipient: ${assigned ? 'назначен' : 'свободен'}',
        () async {
          final h = _Harness();
          addTearDown(h.dispose);
          h.repository.page(0, []);
          await pumpEventQueue();
          h.model.setMode(TagCatalogSelectionMode(intentionId));
          h.repository.selectionPage(1, intentionId, [
            TagSelectionRow(tag: _tag(1, 'Первый'), isAssigned: false),
          ]);
          await pumpEventQueue();
          h.model.selectTag(_id(52));
          h.repository.tagRead(_tag(52, 'Из редактора'));
          await pumpEventQueue();
          expect(h.repository.statusQueries.single, (_id(52), intentionId));
          expect(h.model.assignSelected(), isNull);
          h.repository.statusRead(0, assigned);
          await pumpEventQueue();
          expect(
            (h.state as TagCatalogLoaded).selectedAssignment,
            assigned
                ? TagCatalogSelectedAssignment.assigned
                : TagCatalogSelectedAssignment.available,
          );
          expect(
            h.model.assignSelected(),
            assigned ? isNull : isA<TagCommandAccepted>(),
          );
        },
      );
    }
  }

  test(
    'автоматические проверки после ручного повтора остаются ограниченными',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.repository.page(0, []);
      await pumpEventQueue();
      h.model.setMode(TagCatalogSelectionMode(_intentionId(1)));
      h.repository.selectionPage(1, _intentionId(1), [
        TagSelectionRow(tag: _tag(1, 'Первый'), isAssigned: false),
      ], revision: 2);
      await pumpEventQueue();
      h.model.selectTag(_id(52));
      h.repository.tagRead(_tag(52, 'Из редактора'), revision: 2);
      await pumpEventQueue();

      for (var index = 0; index < 8; index++) {
        h.repository.statusRead(index, false, revision: 1);
        await pumpEventQueue();
      }
      expect(h.repository.statusQueries, hasLength(8));
      h.model.retrySelectedAssignment();
      for (var index = 8; index < 16; index++) {
        h.repository.statusRead(index, false, revision: 1);
        await pumpEventQueue();
      }
      expect(h.repository.statusQueries, hasLength(16));
      expect(
        (h.state as TagCatalogLoaded).selectedAssignment,
        TagCatalogSelectedAssignment.unavailable,
      );
      expect(h.model.assignSelected(), isNull);
    },
  );

  test(
    'поздние ответы прежнего выбора и ревизии не открывают назначение',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.repository.page(0, []);
      await pumpEventQueue();
      h.model.setMode(TagCatalogSelectionMode(_intentionId(1)));
      h.repository.selectionPage(1, _intentionId(1), [
        TagSelectionRow(tag: _tag(1, 'Первый'), isAssigned: false),
      ]);
      await pumpEventQueue();
      h.model.selectTag(_id(52));
      h.repository.tagRead(_tag(52, 'Старый'));
      h.model.selectTag(_id(53));
      h.repository.tagRead(_tag(53, 'Текущий'));
      await pumpEventQueue();
      h.repository.statusRead(0, false);
      h.repository.statusRead(1, true);
      await pumpEventQueue();
      expect((h.state as TagCatalogLoaded).selection.id, _id(53));
      expect(
        (h.state as TagCatalogLoaded).selectedAssignment,
        TagCatalogSelectedAssignment.assigned,
      );
      expect(h.model.assignSelected(), isNull);

      await h.renamed(_tag(1, 'Первый'), _tag(1, 'Новый'), revision: 2);
      expect(h.repository.statusQueries, hasLength(3));
      h.repository.statusRead(2, false, revision: 1);
      await pumpEventQueue();
      expect(h.repository.statusQueries, hasLength(4));
      expect(h.model.assignSelected(), isNull);
      h.repository.selectionPage(2, _intentionId(1), [
        TagSelectionRow(tag: _tag(1, 'Новый'), isAssigned: false),
        TagSelectionRow(tag: _tag(53, 'Текущий'), isAssigned: true),
      ], revision: 2);
      await pumpEventQueue();
      h.repository.statusRead(3, false, revision: 1);
      await pumpEventQueue();
      final confirmed = h.state as TagCatalogLoaded;
      expect(confirmed.selection.id, _id(53));
      expect(
        confirmed.selectedAssignment,
        TagCatalogSelectedAssignment.assigned,
      );
      expect(confirmed.freshness, TagCatalogFreshness.current);
      expect(h.repository.statusQueries, hasLength(4));
      expect(h.model.assignSelected(), isNull);
    },
  );

  test(
    'поздний ответ прежнего выбора не скрывает отказ текущей пары',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.repository.page(0, []);
      await pumpEventQueue();
      h.model.setMode(TagCatalogSelectionMode(_intentionId(1)));
      h.repository.selectionPage(1, _intentionId(1), [
        TagSelectionRow(tag: _tag(1, 'Первый'), isAssigned: false),
      ]);
      await pumpEventQueue();
      h.model.selectTag(_id(52));
      h.model.selectTag(_id(53));
      h.repository.statusReads[1].complete(
        const TagAssignmentStatusError(TagAssignmentStatusUnavailable()),
      );
      h.repository.tagRead(_tag(53, 'Текущий'));
      await pumpEventQueue();
      h.repository.statusRead(0, false);
      await pumpEventQueue();
      expect(
        (h.state as TagCatalogLoaded).selectedAssignment,
        TagCatalogSelectedAssignment.unavailable,
      );
      expect(h.model.assignSelected(), isNull);
    },
  );

  test(
    'поздний ответ прежнего получателя не скрывает отказ текущей пары',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.repository.page(0, []);
      await pumpEventQueue();
      h.model.setMode(TagCatalogSelectionMode(_intentionId(1)));
      h.repository.selectionPage(1, _intentionId(1), [
        TagSelectionRow(tag: _tag(1, 'Первый'), isAssigned: false),
      ]);
      await pumpEventQueue();
      h.model.selectTag(_id(52));
      h.model.setMode(TagCatalogSelectionMode(_intentionId(2)));
      h.repository.selectionPage(2, _intentionId(2), [
        TagSelectionRow(tag: _tag(1, 'Первый'), isAssigned: false),
      ]);
      await pumpEventQueue();
      h.model.selectTag(_id(52));
      h.repository.statusReads[1].complete(
        const TagAssignmentStatusError(TagAssignmentStatusUnavailable()),
      );
      h.repository.tagRead(_tag(52, 'Текущий'));
      await pumpEventQueue();
      h.repository.statusRead(0, false);
      await pumpEventQueue();
      expect(
        (h.state as TagCatalogLoaded).selectedAssignment,
        TagCatalogSelectedAssignment.unavailable,
      );
      expect(h.model.assignSelected(), isNull);
    },
  );

  test('ответ прежней ревизии не скрывает отказ текущей проверки', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.repository.page(0, []);
    await pumpEventQueue();
    h.model.setMode(TagCatalogSelectionMode(_intentionId(1)));
    h.repository.selectionPage(1, _intentionId(1), [
      TagSelectionRow(tag: _tag(1, 'Первый'), isAssigned: false),
    ]);
    await pumpEventQueue();
    h.model.selectTag(_id(52));
    h.repository.tagRead(_tag(52, 'Из редактора'));
    await h.renamed(_tag(1, 'Первый'), _tag(1, 'Новый'), revision: 2);
    expect(h.repository.statusReads, hasLength(2));
    h.repository.statusReads[1].complete(
      const TagAssignmentStatusError(TagAssignmentStatusUnavailable()),
    );
    h.repository.statusRead(0, false);
    await pumpEventQueue();
    expect(
      (h.state as TagCatalogLoaded).selectedAssignment,
      TagCatalogSelectedAssignment.unavailable,
    );
    expect(h.model.assignSelected(), isNull);
  });

  test('ответ точечного чтения другой эпохи не открывает назначение', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.repository.page(0, []);
    await pumpEventQueue();
    h.model.setMode(TagCatalogSelectionMode(_intentionId(1)));
    h.repository.selectionPage(1, _intentionId(1), [
      TagSelectionRow(tag: _tag(1, 'Первый'), isAssigned: false),
    ]);
    await pumpEventQueue();
    h.model.selectTag(_id(52));
    h.repository.tagRead(_tag(52, 'Из редактора'));
    h.repository.statusRead(0, false, epoch: 1);
    await pumpEventQueue();
    expect(h.model.assignSelected(), isNull);
    expect(h.repository.statusQueries, hasLength(2));
    h.repository.statusRead(1, true);
    await pumpEventQueue();
    expect(
      (h.state as TagCatalogLoaded).selectedAssignment,
      TagCatalogSelectedAssignment.assigned,
    );
    expect(h.model.assignSelected(), isNull);
  });

  test(
    'отсутствие получателя и отказ точечного чтения не разрешают назначение',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.repository.page(0, []);
      await pumpEventQueue();
      h.model.setMode(TagCatalogSelectionMode(_intentionId(1)));
      h.repository.selectionPage(1, _intentionId(1), [
        TagSelectionRow(tag: _tag(1, 'Первый'), isAssigned: false),
      ]);
      await pumpEventQueue();
      h.model.selectTag(_id(52));
      h.repository.tagRead(_tag(52, 'Из редактора'));
      h.repository.statusReads[0].complete(
        const TagAssignmentStatusError(TagAssignmentStatusUnavailable()),
      );
      await pumpEventQueue();
      expect(h.model.assignSelected(), isNull);
      h.model.selectTag(_id(53));
      h.repository.tagRead(_tag(53, 'Другой'));
      h.repository.statusReads[1].complete(
        const TagAssignmentStatusError(TagAssignmentStatusIntentionNotFound()),
      );
      await pumpEventQueue();
      expect(h.state, isA<TagCatalogIntentionMissing>());
      expect(h.model.assignSelected(), isNull);
    },
  );

  test(
    'точечное отсутствие тега снимает выбор из редактора до обновления снимка',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.repository.page(0, []);
      await pumpEventQueue();
      h.model.setMode(TagCatalogSelectionMode(_intentionId(1)));
      h.repository.selectionPage(1, _intentionId(1), [
        TagSelectionRow(tag: _tag(1, 'Первый'), isAssigned: false),
      ]);
      await pumpEventQueue();
      h.model.selectTag(_id(52));
      h.repository.tagRead(_tag(52, 'Удалённый'));
      h.repository.statusReads.single.complete(
        const TagAssignmentStatusError(TagAssignmentStatusTagNotFound()),
      );
      await pumpEventQueue();
      expect(
        (h.state as TagCatalogLoaded).selection,
        isA<TagCatalogNoSelection>(),
      );
      expect(h.model.assignSelected(), isNull);
      expect(h.repository.commands, isEmpty);
    },
  );

  for (final (intentionId, recipient) in [
    (_intentionId(1), 'намерения'),
    (_intentionId(2), 'другого намерения'),
  ]) {
    for (final assigned in [false, true]) {
      test(
        'полный снимок сохраняет выбор и признак назначения для $recipient: ${assigned ? 'назначен' : 'свободен'}',
        () async {
          final h = _Harness();
          addTearDown(h.dispose);
          h.repository.page(0, []);
          await pumpEventQueue();
          h.model.setMode(TagCatalogSelectionMode(intentionId));
          h.repository.selectionPage(1, intentionId, [
            TagSelectionRow(tag: _tag(1, 'Первый'), isAssigned: false),
            TagSelectionRow(tag: _tag(52, 'Выбранный'), isAssigned: assigned),
          ]);
          await pumpEventQueue();
          h.model.selectTag(_id(52));
          expect(
            (h.state as TagCatalogLoaded).selection,
            isA<TagCatalogSelectionReady>(),
          );
          expect(h.repository.statusQueries, isEmpty);

          await h.renamed(
            _tag(1, 'Первый'),
            _tag(1, 'Изменённый'),
            revision: 2,
          );
          expect((h.state as TagCatalogLoaded).selection.id, _id(52));
          expect(h.model.assignSelected(), isNull);
          h.repository.selectionPage(2, intentionId, [
            TagSelectionRow(tag: _tag(1, 'Изменённый'), isAssigned: false),
            TagSelectionRow(tag: _tag(52, 'Выбранный'), isAssigned: assigned),
          ], revision: 2);
          await pumpEventQueue();
          final loaded = h.state as TagCatalogLoaded;
          expect(loaded.selection.id, _id(52));
          expect(loaded.selectionRows.map((row) => row.tag.id), [
            _id(1),
            _id(52),
          ]);
          expect(
            loaded.selectedAssignment,
            assigned
                ? TagCatalogSelectedAssignment.assigned
                : TagCatalogSelectedAssignment.available,
          );
          expect(h.repository.statusQueries, isEmpty);
          expect(
            h.model.assignSelected(),
            assigned ? isNull : isA<TagCommandAccepted>(),
          );
          expect(h.repository.commands, hasLength(assigned ? 1 : 2));
        },
      );
    }
  }

  test('актуализация блокирует признак назначения до полного подтверждённого снимка', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.repository.page(0, []);
    await pumpEventQueue();
    h.model.setMode(TagCatalogSelectionMode(_intentionId(1)));
    h.repository.selectionPage(1, _intentionId(1), [
      TagSelectionRow(tag: _tag(1, 'Первый'), isAssigned: false),
      TagSelectionRow(tag: _tag(52, 'Выбранный'), isAssigned: false),
    ]);
    await pumpEventQueue();
    h.model.selectTag(_id(52));
    expect(
      (h.state as TagCatalogLoaded).selectedAssignment,
      TagCatalogSelectedAssignment.available,
    );

    await h.renamed(_tag(1, 'Первый'), _tag(1, 'Изменённый'), revision: 2);
    expect(
      (h.state as TagCatalogLoaded).freshness,
      TagCatalogFreshness.refreshing,
    );
    expect(h.model.assignSelected(), isNull);
    h.repository.selectionPage(2, _intentionId(1), [
      TagSelectionRow(tag: _tag(1, 'Первый'), isAssigned: false),
      TagSelectionRow(tag: _tag(52, 'Выбранный'), isAssigned: false),
    ]);
    await pumpEventQueue();
    expect(h.model.assignSelected(), isNull);
    expect((h.state as TagCatalogLoaded).selection.id, _id(52));
    h.repository.selectionPage(3, _intentionId(1), [
      TagSelectionRow(tag: _tag(1, 'Изменённый'), isAssigned: false),
      TagSelectionRow(tag: _tag(52, 'Выбранный'), isAssigned: true),
    ], revision: 2);
    await pumpEventQueue();
    expect(
      (h.state as TagCatalogLoaded).selectedAssignment,
      TagCatalogSelectedAssignment.assigned,
    );
    expect(h.model.assignSelected(), isNull);
  });

  test(
    'полный каталог выбора показывает все 150 тегов и назначения одним чтением',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.repository.page(0, []);
      await pumpEventQueue();
      h.model.setMode(TagCatalogSelectionMode(_intentionId(1)));
      final rows = [
        for (var index = 1; index <= 150; index++)
          TagSelectionRow(
            tag: _tag(index, 'Тег $index'),
            isAssigned: index.isEven,
          ),
      ];
      h.repository.selectionPage(1, _intentionId(1), rows);
      await pumpEventQueue();
      final loaded = h.state as TagCatalogLoaded;
      expect(loaded.items, rows.map((row) => row.tag));
      expect(loaded.selectionRows, rows);
      h.model.selectTag(_id(149));
      expect(
        (h.state as TagCatalogLoaded).selection,
        isA<TagCatalogSelectionReady>(),
      );
      expect(
        (h.state as TagCatalogLoaded).selectedAssignment,
        TagCatalogSelectedAssignment.available,
      );
      expect(h.repository.statusQueries, isEmpty);
      expect(h.repository.queries, [
        const TagCatalogBrowseMode(),
        TagCatalogSelectionMode(_intentionId(1)),
      ]);
      expect(h.repository.commands, isEmpty);
    },
  );

  test(
    'снимок выбора перед пакетом сохраняет подтверждённый признак',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.repository.page(0, []);
      await pumpEventQueue();
      h.model.setMode(TagCatalogSelectionMode(_intentionId(1)));
      h.repository.selectionPage(1, _intentionId(1), [
        TagSelectionRow(tag: _tag(1, 'Дом'), isAssigned: true),
      ], revision: 2);
      await pumpEventQueue();
      final original = h.coordinator.acceptTagAssign(
        AssignTag(tagId: _id(1), intentionId: _intentionId(1)),
      ) as TagCommandAccepted;
      h.repository.completeCommand(
        testTagAssignmentChanged(
          TagAssignmentChangedChange(
            revision: const _Revision(2),
            assignment: TagAssignment(
              tagId: _id(1),
              intentionId: _intentionId(1),
            ),
            state: TagAssignmentState.assigned,
          ),
        ),
        const _Revision(2),
      );
      await original.future;
      expect(
        (h.state as TagCatalogLoaded).selectionRows.single.isAssigned,
        isTrue,
      );
      expect(
        (h.state as TagCatalogLoaded).freshness,
        TagCatalogFreshness.current,
      );
      expect(h.repository.queries, hasLength(2));
    },
  );

  test('отсутствие выбранного тега до пакета убирает строку и отбрасывает старые снимки', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.repository.page(0, [_tag(1, 'Дом'), _tag(2, 'Работа')]);
    await pumpEventQueue();
    h.model.selectTag(_id(1));
    h.repository.tagRead(null, revision: 2);
    await pumpEventQueue();
    final refreshing = h.state as TagCatalogLoaded;
    expect(refreshing.items.map((tag) => tag.id), [_id(2)]);
    expect(refreshing.selection, isA<TagCatalogNoSelection>());
    expect(refreshing.freshness, TagCatalogFreshness.refreshing);
    expect(h.model.canActOn(_id(1)), isFalse);
    expect(h.model.canActOn(_id(2)), isFalse);

    h.repository.page(1, [_tag(1, 'Дом'), _tag(2, 'Работа')]);
    await pumpEventQueue();
    expect((h.state as TagCatalogLoaded).items.map((tag) => tag.id), [_id(2)]);
    expect(h.repository.queries, hasLength(3));
    h.repository.page(2, [_tag(2, 'Работа'), _tag(3, 'Новый')], revision: 2);
    await pumpEventQueue();
    final fresh = h.state as TagCatalogLoaded;
    expect(fresh.freshness, TagCatalogFreshness.current);
    expect(fresh.items.map((tag) => tag.id), [_id(2), _id(3)]);
    expect(h.model.canActOn(_id(2)), isTrue);
  });

  test('отсутствие выбранного тега из редактора до обновления снимка очищает выбор до пакета', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.repository.page(0, [_tag(1, 'Дом')]);
    await pumpEventQueue();
    h.model.selectTag(_id(52));
    h.repository.tagRead(_tag(52, 'Далёкий'));
    await pumpEventQueue();

    h.repository.tagRead(null, revision: 2);
    await pumpEventQueue();
    final refreshing = h.state as TagCatalogLoaded;
    expect(refreshing.selection, isA<TagCatalogNoSelection>());
    expect(refreshing.freshness, TagCatalogFreshness.refreshing);
    expect(h.model.canActOn(_id(52)), isFalse);
    expect(h.model.canActOn(_id(1)), isFalse);
    expect(h.repository.queries, hasLength(2));

    h.repository.page(1, [_tag(1, 'Дом')], revision: 2);
    await pumpEventQueue();
    expect(
      (h.state as TagCatalogLoaded).freshness,
      TagCatalogFreshness.current,
    );
    expect(h.model.canActOn(_id(1)), isTrue);
  });

  test('старое отсутствие не очищает выбор с нового снимка', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.repository.page(0, [_tag(1, 'Дом')], revision: 3);
    await pumpEventQueue();
    h.model.selectTag(_id(1));
    h.repository.tagRead(_tag(1, 'Дом'));
    await pumpEventQueue();

    h.repository.tagRead(null, revision: 2);
    await pumpEventQueue();
    final loaded = h.state as TagCatalogLoaded;
    expect(loaded.selection, isA<TagCatalogSelectionReady>());
    expect(loaded.items.single.id, _id(1));
    expect(loaded.freshness, TagCatalogFreshness.current);
    expect(h.model.canActOn(_id(1)), isTrue);
    expect(h.repository.queries, hasLength(1));
  });

  test(
    'отсутствие вне нового снимка очищает выбор после постороннего пакета',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.repository.page(0, [_tag(1, 'Дом')], revision: 3);
      await pumpEventQueue();
      h.model.selectTag(_id(52));
      h.repository.tagRead(_tag(52, 'Далёкий'));
      await pumpEventQueue();
      await h.created(_tag(2, 'Работа'), revision: 3);

      h.repository.tagRead(null, revision: 2);
      await pumpEventQueue();
      final loaded = h.state as TagCatalogLoaded;
      expect(loaded.selection, isA<TagCatalogNoSelection>());
      expect(loaded.items.map((tag) => tag.id), [_id(1)]);
      expect(loaded.freshness, TagCatalogFreshness.current);
      expect(h.model.canActOn(_id(52)), isFalse);
      expect(h.model.canActOn(_id(1)), isTrue);
      expect(h.repository.queries, hasLength(1));
    },
  );

  test('снимок новой ревизии перед пакетом обновляет выбранное имя', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.repository.page(0, [_tag(1, 'Дом')], revision: 2);
    await pumpEventQueue();
    h.model.selectTag(_id(52));
    h.repository.tagRead(_tag(52, 'Старое имя'));
    await pumpEventQueue();

    await h.renamed(_tag(52, 'Старое имя'), _tag(52, 'Новое имя'), revision: 2);
    h.repository.tagRead(_tag(52, 'Старое имя'));
    await pumpEventQueue();

    final loaded = h.state as TagCatalogLoaded;
    expect(
      loaded.selection,
      isA<TagCatalogSelectionReady>().having(
        (selection) => selection.tag.name.value,
        'название',
        'Новое имя',
      ),
    );
    expect(h.model.canActOn(_id(52)), isTrue);
    expect(h.repository.queries, hasLength(1));
  });

  test('снимок новой ревизии перед пакетом очищает удалённый выбор', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.repository.page(0, [_tag(1, 'Дом')], revision: 2);
    await pumpEventQueue();
    h.model.selectTag(_id(52));
    h.repository.tagRead(_tag(52, 'Старое имя'));
    await pumpEventQueue();

    await h.deleted(_id(52), revision: 2);
    h.repository.tagRead(_tag(52, 'Старое имя'));
    await pumpEventQueue();

    final loaded = h.state as TagCatalogLoaded;
    expect(loaded.selection, isA<TagCatalogNoSelection>());
    expect(loaded.items.map((tag) => tag.id), [_id(1)]);
    expect(h.model.canActOn(_id(52)), isFalse);
    expect(h.repository.queries, hasLength(1));
  });

  test('пакет прежней ревизии не откатывает более поздний выбор', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.repository.page(0, [_tag(52, 'Последнее имя')], revision: 3);
    await pumpEventQueue();
    h.model.selectTag(_id(52));
    h.repository.tagRead(_tag(52, 'Старое имя'));
    await pumpEventQueue();

    await h.renamed(
      _tag(52, 'Старое имя'),
      _tag(52, 'Промежуточное имя'),
      revision: 2,
    );
    h.repository.tagRead(_tag(52, 'Старое имя'));
    await pumpEventQueue();

    final loaded = h.state as TagCatalogLoaded;
    expect(loaded.items.single.name.value, 'Последнее имя');
    expect(
      loaded.selection,
      isA<TagCatalogSelectionReady>().having(
        (selection) => selection.tag.name.value,
        'название',
        'Последнее имя',
      ),
    );
    expect(h.model.canActOn(_id(52)), isTrue);
    expect(h.repository.queries, hasLength(1));
  });

  test('поздний полный снимок не откатывает более новую основу', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.repository.page(0, [_tag(52, 'Последнее имя')], revision: 3);
    await pumpEventQueue();
    h.model.selectTag(_id(52));
    h.repository.tagRead(_tag(52, 'Старое имя'));
    await pumpEventQueue();

    await h.created(_tag(53, 'Новый'), revision: 4);
    h.repository.page(1, [_tag(52, 'Промежуточное имя')], revision: 2);
    await pumpEventQueue();
    expect(h.repository.queries, hasLength(3));
    await h.renamed(
      _tag(52, 'Старое имя'),
      _tag(52, 'Промежуточное имя'),
      revision: 2,
    );
    expect(
      (h.state as TagCatalogLoaded).items.single.name.value,
      'Последнее имя',
    );

    h.repository.page(2, [_tag(52, 'Промежуточное имя')], revision: 2);
    await pumpEventQueue();
    expect(h.repository.queries, hasLength(4));
    expect(
      (h.state as TagCatalogLoaded).revision,
      isA<_Revision>().having((revision) => revision.number, 'номер', 3),
    );

    h.repository.page(3, [
      _tag(52, 'Последнее имя'),
      _tag(53, 'Новый'),
    ], revision: 4);
    await pumpEventQueue();
    final loaded = h.state as TagCatalogLoaded;
    expect(loaded.items.first.name.value, 'Последнее имя');
    expect(loaded.freshness, TagCatalogFreshness.current);
    expect(
      (loaded.selection as TagCatalogSelectionReady).tag.name.value,
      'Последнее имя',
    );
  });

  test('выбор из редактора до обновления снимка следует подтверждённому переименованию и удалению', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.repository.page(0, [_tag(1, 'Дом')]);
    await pumpEventQueue();

    h.model.selectTag(_id(52));
    h.repository.tagRead(_tag(52, 'Старое имя'));
    await pumpEventQueue();
    expect(
      (h.state as TagCatalogLoaded).selection,
      isA<TagCatalogSelectionReady>().having(
        (value) => value.tag.name.value,
        'название',
        'Старое имя',
      ),
    );

    await h.renamed(_tag(52, 'Старое имя'), _tag(52, 'Новое имя'), revision: 2);
    expect(
      (h.state as TagCatalogLoaded).selection,
      isA<TagCatalogSelectionReady>().having(
        (value) => value.tag.name.value,
        'название',
        'Новое имя',
      ),
    );
    h.repository.tagRead(_tag(52, 'Старое имя'));
    await pumpEventQueue();
    expect(
      (h.state as TagCatalogLoaded).selection,
      isA<TagCatalogSelectionReady>().having(
        (value) => value.tag.name.value,
        'название',
        'Новое имя',
      ),
    );

    h.repository.page(1, [_tag(1, 'Дом')]);
    await pumpEventQueue();
    expect(
      (h.state as TagCatalogLoaded).selection,
      isA<TagCatalogSelectionReady>().having(
        (value) => value.tag.name.value,
        'название',
        'Новое имя',
      ),
    );
    expect(h.repository.queries, hasLength(3));

    await h.deleted(_id(52), revision: 3);
    h.repository.tagRead(_tag(52, 'Старое имя'));
    await pumpEventQueue();
    expect(
      (h.state as TagCatalogLoaded).selection,
      isA<TagCatalogNoSelection>(),
    );
    expect(h.model.canActOn(_id(52)), isFalse);
    h.repository.page(2, [_tag(1, 'Дом')]);
    await pumpEventQueue();
    h.repository.page(3, [_tag(1, 'Дом')], revision: 3);
    await pumpEventQueue();
    expect(
      (h.state as TagCatalogLoaded).selection,
      isA<TagCatalogNoSelection>(),
    );
    expect(h.repository.queries, hasLength(4));
  });

  test(
    'отказ чтения выбранного тега запрещает действия до нового чтения',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.repository.page(0, [_tag(52, 'Старое имя')]);
      await pumpEventQueue();
      h.model.selectTag(_id(52));
      h.repository.tagRead(_tag(52, 'Старое имя'));
      await pumpEventQueue();
      expect(h.model.canActOn(_id(52)), isTrue);
      h.repository.tagReadError(const TagReadUnavailableFailure());
      await pumpEventQueue();
      expect(
        (h.state as TagCatalogLoaded).selection,
        isA<TagCatalogSelectionFailure>(),
      );
      expect(h.model.canActOn(_id(52)), isFalse);
      h.model.retrySelectedTag();
      h.repository.tagRead(_tag(52, 'Актуальное имя'));
      await pumpEventQueue();
      expect(
        (h.state as TagCatalogLoaded).selection,
        isA<TagCatalogSelectionReady>().having(
          (value) => value.tag.name.value,
          'название',
          'Актуальное имя',
        ),
      );
    },
  );

  test(
    'повтор актуализации читает полный список и сохраняет видимые строки',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.repository.page(0, [_tag(1, 'Дом')]);
      await pumpEventQueue();
      await h.created(_tag(2, 'Работа'), revision: 2);
      expect(h.repository.queries, hasLength(2));
      expect((h.state as TagCatalogLoaded).items.single.name.value, 'Дом');
      h.repository.fail(1, const TagCatalogUnavailableFailure());
      await pumpEventQueue();
      final failed = h.state as TagCatalogLoaded;
      expect(failed.items.map((tag) => tag.id), [_id(1)]);
      expect(failed.freshness, TagCatalogFreshness.stale);
      expect(failed.refreshFailure, isA<TagCatalogUnavailableFailure>());
      expect(h.model.canActOn(_id(1)), isFalse);
      final retry = h.model.retryRefresh();
      final duplicate = h.model.retryRefresh();
      expect(h.repository.queries, hasLength(3));
      h.repository.page(2, [_tag(1, 'Дом'), _tag(2, 'Работа')], revision: 2);
      await Future.wait([retry, duplicate]);
      expect((h.state as TagCatalogLoaded).items.map((tag) => tag.id), [
        _id(1),
        _id(2),
      ]);
      expect(h.model.canActOn(_id(1)), isTrue);
      expect(h.repository.commands, hasLength(1));
    },
  );

  test('завершение до первого снимка отклоняет старый снимок', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.created(_tag(2, 'Работа'), revision: 2);
    h.repository.page(0, [_tag(1, 'Дом')]);
    await pumpEventQueue();
    expect(h.repository.queries, hasLength(2));
    expect(h.state, isA<TagCatalogInitialLoading>());
    h.repository.page(1, [_tag(1, 'Дом'), _tag(2, 'Работа')], revision: 2);
    await pumpEventQueue();
    expect((h.state as TagCatalogLoaded).items.map((tag) => tag.id), [
      _id(1),
      _id(2),
    ]);
  });

  test(
    'переименование во время актуализации не возвращает старое имя',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.repository.page(0, [_tag(1, 'Дом')]);
      await pumpEventQueue();
      await h.created(_tag(2, 'Работа'), revision: 2);
      await h.renamed(_tag(1, 'Дом'), _tag(1, 'Семья'), revision: 3);
      final refreshing = h.state as TagCatalogLoaded;
      expect(refreshing.items.single.name.value, 'Семья');
      expect(refreshing.freshness, TagCatalogFreshness.refreshing);
      expect(refreshing.canUseCurrentItems, isFalse);
      h.repository.page(1, [_tag(1, 'Дом'), _tag(2, 'Работа')], revision: 2);
      await pumpEventQueue();
      expect((h.state as TagCatalogLoaded).items.single.name.value, 'Семья');
      h.repository.page(2, [_tag(1, 'Семья'), _tag(2, 'Работа')], revision: 3);
      await pumpEventQueue();
      expect((h.state as TagCatalogLoaded).items.map((tag) => tag.name.value), [
        'Семья',
        'Работа',
      ]);
    },
  );

  test(
    'удаление убирает строку и отказ актуализации не повторяет команду',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.repository.page(0, [_tag(1, 'Дом'), _tag(2, 'Работа')]);
      await pumpEventQueue();
      await h.deleted(_id(1), revision: 2);
      expect((h.state as TagCatalogLoaded).items.map((tag) => tag.id), [
        _id(2),
      ]);
      h.repository.fail(1, const TagCatalogUnavailableFailure());
      await pumpEventQueue();
      final stale = h.state as TagCatalogLoaded;
      expect(stale.freshness, TagCatalogFreshness.stale);
      expect(stale.canUseCurrentItems, isFalse);
      expect(stale.refreshFailure, isA<TagCatalogUnavailableFailure>());
      final retry = h.model.retryRefresh();
      expect(h.repository.commands, hasLength(1));
      h.repository.page(2, [_tag(2, 'Работа')], revision: 2);
      await retry;
      expect(
        (h.state as TagCatalogLoaded).freshness,
        TagCatalogFreshness.current,
      );
    },
  );

  test('позднее чтение после удаления не возвращает удалённый тег', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.repository.page(0, [_tag(1, 'Дом')]);
    await pumpEventQueue();
    await h.created(_tag(2, 'Работа'), revision: 2);
    await h.deleted(_id(1), revision: 3);
    expect((h.state as TagCatalogLoaded).items, isEmpty);
    h.repository.page(1, [_tag(1, 'Дом'), _tag(2, 'Работа')], revision: 2);
    await pumpEventQueue();
    expect((h.state as TagCatalogLoaded).items, isEmpty);
    h.repository.page(2, [_tag(2, 'Работа')], revision: 3);
    await pumpEventQueue();
    expect((h.state as TagCatalogLoaded).items.map((tag) => tag.id), [_id(2)]);
  });

  test('учтённое завершение не запускает повторное чтение', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.repository.page(0, [_tag(1, 'Дом')], revision: 2);
    await pumpEventQueue();
    await h.created(_tag(1, 'Дом'), revision: 2);
    expect(h.repository.queries, hasLength(1));
    expect(
      (h.state as TagCatalogLoaded).freshness,
      TagCatalogFreshness.current,
    );
  });

  test('новая эпоха отбрасывает поздний полный снимок прежней эпохи', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.repository.page(0, [_tag(1, 'Дом')]);
    await pumpEventQueue();
    await h.created(_tag(2, 'Работа'), revision: 2);
    await h.deleted(_id(1), revision: 1, epoch: 1);
    h.repository.page(1, [_tag(2, 'Работа')], revision: 2);
    await pumpEventQueue();
    h.repository.page(2, [_tag(3, 'Другое')], revision: 1, epoch: 1);
    await pumpEventQueue();
    final loaded = h.state as TagCatalogLoaded;
    expect(loaded.items.map((tag) => tag.id), [_id(3)]);
    expect(
      loaded.revision.compareTo(const _Revision(1, 1)),
      GraphRevisionOrder.same,
    );
  });

  test(
    'повторяющиеся идентификаторы полного снимка не заменяют видимые строки',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.repository.page(0, [_tag(1, 'Дом')]);
      await pumpEventQueue();
      await h.created(_tag(2, 'Работа'), revision: 2);
      h.repository.page(1, [_tag(1, 'Дом'), _tag(1, 'Дубликат')], revision: 2);
      await pumpEventQueue();
      final stale = h.state as TagCatalogLoaded;
      expect(stale.items.single.name.value, 'Дом');
      expect(stale.freshness, TagCatalogFreshness.stale);
      expect(stale.refreshFailure, isA<TagCatalogUnexpectedFailure>());
      expect(h.repository.queries, hasLength(2));
    },
  );

  test(
    'повторяющийся старый снимок заканчивается явным отказом чтения',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      await h.created(_tag(2, 'Работа'), revision: 2);
      for (var index = 0; index < 8; index++) {
        h.repository.page(index, [_tag(1, 'Дом')]);
        await pumpEventQueue();
      }
      expect(h.repository.queries, hasLength(8));
      expect(h.state, isA<TagCatalogInitialFailure>());
      expect(
        (h.state as TagCatalogInitialFailure).failure,
        isA<TagCatalogUnavailableFailure>(),
      );
    },
  );
}

final class _Harness {
  _Harness() {
    container = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWith((ref) => repository),
      ],
    );
    subscription = container.listen(tagCatalogViewModelProvider(), (_, _) {});
  }

  final repository = _Repository();
  late final ProviderContainer container;
  late final ProviderSubscription<TagCatalogState> subscription;
  TagCatalogViewModel get model =>
      container.read(tagCatalogViewModelProvider().notifier);
  TagCatalogState get state => container.read(tagCatalogViewModelProvider());
  GraphCommandCoordinator get coordinator =>
      container.read(graphCommandCoordinatorProvider.notifier);

  Future<void> created(Tag tag, {required int revision}) async {
    final accepted = coordinator.acceptTagCreation(
      TagCreationFormKey(),
      CreateTag(tag.name),
    ) as TagCommandAccepted;
    final r = _Revision(revision);
    repository.completeCommand(
      TagCreated(TagCreatedChange(revision: r, after: tag)),
      r,
    );
    await accepted.future;
  }

  Future<void> renamed(Tag before, Tag after, {required int revision}) async {
    final accepted = coordinator.acceptTagRename(
      RenameTag(tagId: before.id, name: after.name),
    ) as TagCommandAccepted;
    final r = _Revision(revision);
    repository.completeCommand(
      TagRenamed(TagRenamedChange(revision: r, before: before, after: after)),
      r,
    );
    await accepted.future;
  }

  Future<void> deleted(TagId id, {required int revision, int epoch = 0}) async {
    final accepted =
        coordinator.acceptTagDelete(DeleteTag(id)) as TagCommandAccepted;
    final r = _Revision(revision, epoch);
    repository.completeCommand(
      TagDeleted(TagDeletedChange(revision: r, tagId: id)),
      r,
    );
    await accepted.future;
  }

  void dispose() {
    subscription.close();
    container.dispose();
  }
}

final class _Repository extends Fake implements PersonalGraphRepository {
  final queries = <TagCatalogMode>[];
  final pages = <Completer<TagCatalogResult>>[];
  final commands = <Completer<TagCommandResult>>[];
  final tagReads = <StreamController<TagReadResult>>[];
  final statusQueries = <(TagId, IntentionId)>[];
  final statusReads = <Completer<TagAssignmentStatusResult>>[];

  @override
  Future<TagAssignmentStatusResult> getTagAssignmentStatus(
    TagId id,
    IntentionId intentionId,
  ) {
    statusQueries.add((id, intentionId));
    final completer = Completer<TagAssignmentStatusResult>();
    statusReads.add(completer);
    return completer.future;
  }

  void statusRead(
    int index,
    bool assigned, {
    int revision = 1,
    int epoch = 0,
  }) => statusReads[index].complete(
    TagAssignmentStatusSuccess(
      GraphSnapshot(value: assigned, revision: _Revision(revision, epoch)),
    ),
  );

  @override
  Stream<TagReadResult> watchTag(TagId id) {
    final controller = StreamController<TagReadResult>.broadcast();
    tagReads.add(controller);
    return controller.stream;
  }

  void tagRead(Tag? tag, {int revision = 1}) => tagReads.last.add(
    TagReadSuccess(GraphSnapshot(value: tag, revision: _Revision(revision))),
  );

  void tagReadError(TagReadFailure failure) =>
      tagReads.last.add(TagReadError(failure));

  @override
  Future<TagCatalogResult> getTagCatalog(TagCatalogMode mode) {
    queries.add(mode);
    final completer = Completer<TagCatalogResult>();
    pages.add(completer);
    return completer.future;
  }

  void page(int index, List<Tag> tags, {int revision = 1, int epoch = 0}) {
    pages[index].complete(
      TagCatalogSuccess(
        TagCatalogSnapshot(items: tags, revision: _Revision(revision, epoch)),
      ),
    );
  }

  void fail(int index, TagCatalogReadFailure failure) =>
      pages[index].complete(TagCatalogError(failure));

  void selectionPage(
    int index,
    IntentionId intentionId,
    List<TagSelectionRow> rows, {

    int revision = 1,
  }) => pages[index].complete(
    TagCatalogSuccess(
      TagCatalogSnapshot.selection(
        intentionId: intentionId,
        rows: rows,

        revision: _Revision(revision),
      ),
    ),
  );

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    final completer = Completer<TagCommandResult>();
    commands.add(completer);
    return await completer.future as GraphCommandResult<TSuccess, TFailure>;
  }

  void completeCommand(TagCommandSuccess success, _Revision revision) {
    commands.last.complete(
      TagCommandSucceeded(
        ConfirmedGraphResult(revision: revision, value: success),
      ),
    );
  }

  void completeCommandFailure(TagCommandFailure failure) =>
      commands.last.complete(TagCommandFailed(failure));
}

final class _Revision implements GraphRevision {
  const _Revision(this.number, [this.epoch = 0]);
  final int number;
  final int epoch;

  @override
  GraphRevisionOrder compareTo(GraphRevision other) => switch (other) {
    _Revision(epoch: final e) when e != epoch =>
      GraphRevisionOrder.differentEpoch,
    _Revision(number: final n) when number < n => GraphRevisionOrder.older,
    _Revision(number: final n) when number > n => GraphRevisionOrder.newer,
    _Revision() => GraphRevisionOrder.same,
    _ => GraphRevisionOrder.differentEpoch,
  };
}

TagId _id(int number) => (TagId.decode(
  '00000000-0000-4000-8000-${number.toString().padLeft(12, '0')}',
) as TagIdDecodingSuccess).id;
IntentionId _intentionId(int number) => (IntentionId.decode(
  '00000000-0000-4000-8000-${number.toString().padLeft(12, '0')}',
) as IntentionIdDecodingSuccess).id;
Tag _tag(int number, String name) =>
    Tag(id: _id(number), name: TagName.fromInput(name));
