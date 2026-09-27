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
import 'package:doable/src/tag/domain/tag_target.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_state.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_view_model.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'выбор показывает назначения и назначает тег только по явной команде',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.model.setMode(TagCatalogSelectionMode(_target(1)));
      expect(h.repository.queries.single.mode, const TagCatalogBrowseMode());
      h.repository.page(0, [_tag(9, 'Старый')]);
      await pumpEventQueue();
      expect(h.repository.queries[1].mode, TagCatalogSelectionMode(_target(1)));
      h.repository.selectionPage(1, _target(1), [
        TagSelectionRow(tag: _tag(1, 'Дом'), isAssigned: true),
        TagSelectionRow(tag: _tag(2, 'Работа'), isAssigned: false),
      ]);
      await pumpEventQueue();
      final loaded = h.state as TagCatalogLoaded;
      expect(loaded.mode, TagCatalogSelectionMode(_target(1)));
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
        TagAssignmentChanged(
          TagAssignmentChangedChange(
            revision: const _Revision(2),
            assignment: TagAssignment(tagId: _id(2), target: _target(1)),
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
        h.repository.queries.last.mode,
        TagCatalogSelectionMode(_target(1)),
      );
    },
  );

  test('смена получателя отбрасывает позднюю порцию и прежний выбор', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.repository.page(0, [_tag(1, 'Дом')]);
    await pumpEventQueue();
    h.model.setMode(TagCatalogSelectionMode(_target(1)));
    h.repository.selectionPage(1, _target(1), [
      TagSelectionRow(tag: _tag(1, 'Дом'), isAssigned: false),
    ], cursor: _Cursor());
    await pumpEventQueue();
    h.model.selectTag(_id(52));
    h.repository.tagRead(_tag(52, 'Далёкий'));
    await pumpEventQueue();
    expect((h.state as TagCatalogLoaded).selection.id, _id(52));

    final pending = h.model.loadMore();
    h.model.setMode(TagCatalogSelectionMode(_target(2)));
    h.repository.statusRead(0, false);
    h.repository.selectionPage(2, _target(1), [
      TagSelectionRow(tag: _tag(2, 'Старый'), isAssigned: true),
    ]);
    await pending;
    expect(h.repository.queries[3].mode, TagCatalogSelectionMode(_target(2)));
    h.repository.selectionPage(3, _target(2), [
      TagSelectionRow(tag: _tag(3, 'Новый'), isAssigned: true),
    ]);
    await pumpEventQueue();
    final loaded = h.state as TagCatalogLoaded;
    expect(loaded.mode, TagCatalogSelectionMode(_target(2)));
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
      h.model.setMode(TagCatalogSelectionMode(_target(1)));
      h.repository.selectionPage(1, _target(1), [
        TagSelectionRow(tag: _tag(1, 'Дом'), isAssigned: false),
      ], cursor: _Cursor());
      await pumpEventQueue();
      h.model.selectTag(_id(1));
      h.repository.tagRead(_tag(1, 'Дом'));
      await pumpEventQueue();
      final pending = h.model.loadMore();
      h.repository.tagRead(null, revision: 2);
      await pumpEventQueue();
      final refreshing = h.state as TagCatalogLoaded;
      expect(refreshing.items, isEmpty);
      expect(refreshing.selectionRows, isEmpty);
      expect(refreshing.selection, isA<TagCatalogNoSelection>());
      expect(h.model.assignSelected(), isNull);
      h.repository.selectionPage(2, _target(1), [
        TagSelectionRow(tag: _tag(1, 'Дом'), isAssigned: false),
      ]);
      await pending;
      h.repository.selectionPage(3, _target(1), [], revision: 2);
      await pumpEventQueue();
      expect((h.state as TagCatalogLoaded).selectionRows, isEmpty);
    },
  );

  test('отсутствие получателя и занятый ключ прекращают назначение', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.repository.page(0, []);
    await pumpEventQueue();
    h.model.setMode(TagCatalogSelectionMode(_target(1)));
    h.repository.fail(1, const TagCatalogTargetNotFound());
    await pumpEventQueue();
    expect(h.state, isA<TagCatalogTargetMissing>());
    expect(h.model.assignSelected(), isNull);

    h.model.setMode(TagCatalogSelectionMode(_target(2)));
    h.repository.selectionPage(2, _target(2), [
      TagSelectionRow(tag: _tag(2, 'Работа'), isAssigned: false),
    ]);
    await pumpEventQueue();
    h.model.selectTag(_id(2));
    h.repository.tagRead(_tag(2, 'Работа'));
    await pumpEventQueue();
    final original = h.coordinator.acceptTagAssign(
      AssignTag(tagId: _id(9), target: _target(2)),
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
    h.model.setMode(TagCatalogSelectionMode(_target(1)));
    h.repository.selectionPage(1, _target(1), [
      TagSelectionRow(tag: _tag(1, 'Дом'), isAssigned: false),
    ]);
    await pumpEventQueue();
    h.model.selectTag(_id(1));
    h.repository.tagRead(_tag(1, 'Дом'));
    await pumpEventQueue();
    final started = h.model.assignSelected() as TagCommandAccepted;
    h.repository.completeCommandFailure(TagTargetNotFoundFailure(_target(1)));
    await started.future;
    expect(h.state, isA<TagCatalogTargetMissing>());
    expect(h.model.assignSelected(), isNull);
  });

  test(
    'отсутствие тега в результате команды убирает строку и действие',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.repository.page(0, []);
      await pumpEventQueue();
      h.model.setMode(TagCatalogSelectionMode(_target(1)));
      h.repository.selectionPage(1, _target(1), [
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
      h.repository.selectionPage(2, _target(1), [], revision: 2);
      await pumpEventQueue();
      expect((h.state as TagCatalogLoaded).items, isEmpty);
    },
  );

  test('выбранный тег вне порции сохраняет id после переименования', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.repository.page(0, []);
    await pumpEventQueue();
    h.model.setMode(TagCatalogSelectionMode(_target(1)));
    h.repository.selectionPage(1, _target(1), [
      TagSelectionRow(tag: _tag(1, 'Дом'), isAssigned: true),
    ], cursor: _Cursor());
    await pumpEventQueue();
    h.model.selectTag(_id(1));
    h.repository.tagRead(_tag(1, 'Дом'));
    await pumpEventQueue();
    expect(h.model.assignSelected(), isNull);

    h.model.selectTag(_id(52));
    h.repository.tagRead(_tag(52, 'Старое'));
    await pumpEventQueue();
    await h.renamed(_tag(52, 'Старое'), _tag(52, 'Новое'), revision: 2);
    final refreshing = h.state as TagCatalogLoaded;
    expect(refreshing.selection.id, _id(52));
    expect(
      refreshing.selection,
      isA<TagCatalogSelectionReady>().having(
        (selection) => selection.tag.name.value,
        'название',
        'Новое',
      ),
    );
    h.repository.selectionPage(
      2,
      _target(1),
      [TagSelectionRow(tag: _tag(1, 'Дом'), isAssigned: true)],
      cursor: _Cursor(),
      revision: 2,
    );
    await pumpEventQueue();
    expect(h.model.assignSelected(), isNull);
    final next = h.model.loadMore();
    h.repository.selectionPage(3, _target(1), [
      TagSelectionRow(tag: _tag(52, 'Новое'), isAssigned: false),
    ], revision: 2);
    await next;
    expect(h.model.assignSelected(), isA<TagCommandAccepted>());
    h.repository.completeCommand(
      TagAssignmentChanged(
        TagAssignmentChangedChange(
          revision: const _Revision(3),
          assignment: TagAssignment(tagId: _id(52), target: _target(1)),
          state: TagAssignmentState.assigned,
        ),
      ),
      const _Revision(3),
    );
    await pumpEventQueue();
  });

  test('пакет назначения обновляет признак строки до новой порции', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.repository.page(0, []);
    await pumpEventQueue();
    h.model.setMode(TagCatalogSelectionMode(_target(1)));
    h.repository.selectionPage(1, _target(1), [
      TagSelectionRow(tag: _tag(1, 'Дом'), isAssigned: false),
    ]);
    await pumpEventQueue();
    final original = h.coordinator.acceptTagAssign(
      AssignTag(tagId: _id(1), target: _target(1)),
    ) as TagCommandAccepted;
    h.repository.completeCommand(
      TagAssignmentChanged(
        TagAssignmentChangedChange(
          revision: const _Revision(2),
          assignment: TagAssignment(tagId: _id(1), target: _target(1)),
          state: TagAssignmentState.assigned,
        ),
      ),
      const _Revision(2),
    );
    await original.future;
    final refreshing = h.state as TagCatalogLoaded;
    expect(refreshing.selectionRows.single.isAssigned, isTrue);
    expect(refreshing.freshness, TagCatalogFreshness.refreshing);
    h.repository.selectionPage(2, _target(1), [
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

  for (final (target, recipient) in [
    (_target(1), 'намерения'),
    (_relationTarget(1), 'долговременной связи'),
  ]) {
    for (final assigned in [false, true]) {
      test(
        'точечное чтение выбора вне порции для $recipient: ${assigned ? 'назначен' : 'свободен'}',
        () async {
          final h = _Harness();
          addTearDown(h.dispose);
          h.repository.page(0, []);
          await pumpEventQueue();
          h.model.setMode(TagCatalogSelectionMode(target));
          h.repository.selectionPage(1, target, [
            TagSelectionRow(tag: _tag(1, 'Первый'), isAssigned: false),
          ], cursor: _Cursor());
          await pumpEventQueue();
          h.model.selectTag(_id(52));
          h.repository.tagRead(_tag(52, 'Вне порции'));
          await pumpEventQueue();
          expect(h.repository.statusQueries.single, (_id(52), target));
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
    'поздние ответы прежнего выбора и ревизии не открывают назначение',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.repository.page(0, []);
      await pumpEventQueue();
      h.model.setMode(TagCatalogSelectionMode(_target(1)));
      h.repository.selectionPage(1, _target(1), [
        TagSelectionRow(tag: _tag(1, 'Первый'), isAssigned: false),
      ], cursor: _Cursor());
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
      h.repository.selectionPage(
        2,
        _target(1),
        [TagSelectionRow(tag: _tag(1, 'Новый'), isAssigned: false)],
        cursor: _Cursor(),
        revision: 2,
      );
      await pumpEventQueue();
      h.repository.statusRead(2, false, revision: 1);
      await pumpEventQueue();
      expect(h.repository.statusQueries, hasLength(4));
      expect(h.model.assignSelected(), isNull);
      h.repository.statusRead(3, true, revision: 2);
      await pumpEventQueue();
      expect(h.model.assignSelected(), isNull);
    },
  );

  test('ответ точечного чтения другой эпохи не открывает назначение', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.repository.page(0, []);
    await pumpEventQueue();
    h.model.setMode(TagCatalogSelectionMode(_target(1)));
    h.repository.selectionPage(1, _target(1), [
      TagSelectionRow(tag: _tag(1, 'Первый'), isAssigned: false),
    ], cursor: _Cursor());
    await pumpEventQueue();
    h.model.selectTag(_id(52));
    h.repository.tagRead(_tag(52, 'Вне порции'));
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
      h.model.setMode(TagCatalogSelectionMode(_target(1)));
      h.repository.selectionPage(1, _target(1), [
        TagSelectionRow(tag: _tag(1, 'Первый'), isAssigned: false),
      ], cursor: _Cursor());
      await pumpEventQueue();
      h.model.selectTag(_id(52));
      h.repository.tagRead(_tag(52, 'Вне порции'));
      h.repository.statusReads[0].complete(
        const TagAssignmentStatusError(TagAssignmentStatusUnavailable()),
      );
      await pumpEventQueue();
      expect(h.model.assignSelected(), isNull);
      h.model.selectTag(_id(53));
      h.repository.tagRead(_tag(53, 'Другой'));
      h.repository.statusReads[1].complete(
        const TagAssignmentStatusError(TagAssignmentStatusTargetNotFound()),
      );
      await pumpEventQueue();
      expect(h.state, isA<TagCatalogTargetMissing>());
      expect(h.model.assignSelected(), isNull);
    },
  );

  test('точечное отсутствие тега снимает выбор вне порции', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.repository.page(0, []);
    await pumpEventQueue();
    h.model.setMode(TagCatalogSelectionMode(_target(1)));
    h.repository.selectionPage(1, _target(1), [
      TagSelectionRow(tag: _tag(1, 'Первый'), isAssigned: false),
    ], cursor: _Cursor());
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
  });

  for (final (target, recipient) in [
    (_target(1), 'намерения'),
    (_relationTarget(1), 'долговременной связи'),
  ]) {
    test(
      'назначенный тег второй порции остаётся назначенным после обновления для $recipient',
      () async {
        final h = _Harness();
        addTearDown(h.dispose);
        h.repository.page(0, []);
        await pumpEventQueue();
        h.model.setMode(TagCatalogSelectionMode(target));
        h.repository.selectionPage(1, target, [
          TagSelectionRow(tag: _tag(1, 'Первый'), isAssigned: false),
        ], cursor: _Cursor());
        await pumpEventQueue();
        final second = h.model.loadMore();
        h.repository.selectionPage(2, target, [
          TagSelectionRow(tag: _tag(52, 'Выбранный'), isAssigned: true),
        ]);
        await second;
        h.model.selectTag(_id(52));
        h.repository.tagRead(_tag(52, 'Выбранный'));
        await pumpEventQueue();
        expect(h.model.assignSelected(), isNull);

        await h.renamed(_tag(1, 'Первый'), _tag(1, 'Изменённый'), revision: 2);
        h.repository.selectionPage(
          3,
          target,
          [TagSelectionRow(tag: _tag(1, 'Изменённый'), isAssigned: false)],
          cursor: _Cursor(),
          revision: 2,
        );
        await pumpEventQueue();

        final loaded = h.state as TagCatalogLoaded;
        expect(loaded.selection.id, _id(52));
        expect(loaded.selectionRows.map((row) => row.tag.id), [_id(1)]);
        expect(h.model.assignSelected(), isNull);
        expect(h.repository.commands, hasLength(1));
      },
    );

    test(
      'свободный тег второй порции остаётся доступным после обновления для $recipient',
      () async {
        final h = _Harness();
        addTearDown(h.dispose);
        h.repository.page(0, []);
        await pumpEventQueue();
        h.model.setMode(TagCatalogSelectionMode(target));
        h.repository.selectionPage(1, target, [
          TagSelectionRow(tag: _tag(1, 'Первый'), isAssigned: false),
        ], cursor: _Cursor());
        await pumpEventQueue();
        final second = h.model.loadMore();
        h.repository.selectionPage(2, target, [
          TagSelectionRow(tag: _tag(52, 'Выбранный'), isAssigned: false),
        ]);
        await second;
        h.model.selectTag(_id(52));
        h.repository.tagRead(_tag(52, 'Выбранный'));
        await pumpEventQueue();

        await h.renamed(_tag(1, 'Первый'), _tag(1, 'Изменённый'), revision: 2);
        h.repository.selectionPage(
          3,
          target,
          [TagSelectionRow(tag: _tag(1, 'Изменённый'), isAssigned: false)],
          cursor: _Cursor(),
          revision: 2,
        );
        await pumpEventQueue();

        expect(h.repository.statusQueries.single, (_id(52), target));
        h.repository.statusRead(0, false, revision: 2);
        await pumpEventQueue();

        expect(h.model.assignSelected(), isA<TagCommandAccepted>());
        expect(h.repository.commands, hasLength(2));
        h.repository.completeCommand(
          TagAssignmentChanged(
            TagAssignmentChangedChange(
              revision: const _Revision(3),
              assignment: TagAssignment(tagId: _id(52), target: target),
              state: TagAssignmentState.assigned,
            ),
          ),
          const _Revision(3),
        );
        await pumpEventQueue();
        expect(h.model.assignSelected(), isNull);
      },
    );
  }

  test(
    'опережающее обновление первой порции блокирует неподтверждённый признак',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.repository.page(0, []);
      await pumpEventQueue();
      h.model.setMode(TagCatalogSelectionMode(_target(1)));
      h.repository.selectionPage(1, _target(1), [
        TagSelectionRow(tag: _tag(1, 'Первый'), isAssigned: false),
      ], cursor: _Cursor());
      await pumpEventQueue();
      final second = h.model.loadMore();
      h.repository.selectionPage(2, _target(1), [
        TagSelectionRow(tag: _tag(52, 'Выбранный'), isAssigned: false),
      ], cursor: _Cursor());
      await second;
      h.model.selectTag(_id(52));
      h.repository.tagRead(_tag(52, 'Выбранный'));
      await pumpEventQueue();
      expect(
        (h.state as TagCatalogLoaded).selectedAssignment,
        TagCatalogSelectedAssignment.available,
      );

      final stale = h.model.loadMore();
      h.repository.fail(3, const TagCatalogSnapshotExpired());
      await stale;
      await pumpEventQueue();
      h.repository.selectionPage(
        4,
        _target(1),
        [TagSelectionRow(tag: _tag(1, 'Первый'), isAssigned: false)],
        cursor: _Cursor(),
        revision: 2,
      );
      await pumpEventQueue();
      expect(
        (h.state as TagCatalogLoaded).selectedAssignment,
        TagCatalogSelectedAssignment.unknown,
      );
      expect(h.model.assignSelected(), isNull);

      final confirmed = h.model.loadMore();
      h.repository.selectionPage(5, _target(1), [
        TagSelectionRow(tag: _tag(52, 'Выбранный'), isAssigned: false),
      ], revision: 2);
      await confirmed;
      expect(
        (h.state as TagCatalogLoaded).selectedAssignment,
        TagCatalogSelectedAssignment.available,
      );
      expect(h.model.assignSelected(), isA<TagCommandAccepted>());
      h.repository.completeCommandFailure(const TagUnavailableFailure());
      await pumpEventQueue();
    },
  );

  test(
    'выбор объединяет порции одного получателя без повторной подгрузки',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.repository.page(0, []);
      await pumpEventQueue();
      h.model.setMode(TagCatalogSelectionMode(_target(1)));
      final cursor = _Cursor();
      h.repository.selectionPage(1, _target(1), [
        TagSelectionRow(tag: _tag(1, 'Дом'), isAssigned: false),
      ], cursor: cursor);
      await pumpEventQueue();
      final first = h.model.loadMore();
      final repeated = h.model.loadMore();
      expect(identical(first, repeated), isTrue);
      expect(h.repository.queries, hasLength(3));
      expect(h.repository.queries.last.cursor, same(cursor));
      expect(
        h.repository.queries.last.mode,
        TagCatalogSelectionMode(_target(1)),
      );
      h.repository.selectionPage(2, _target(1), [
        TagSelectionRow(tag: _tag(2, 'Работа'), isAssigned: true),
      ]);
      await first;
      final loaded = h.state as TagCatalogLoaded;
      expect(loaded.items.map((tag) => tag.id), [_id(1), _id(2)]);
      expect(loaded.selectionRows.map((row) => row.isAssigned), [false, true]);
    },
  );

  test(
    'страница выбора перед пакетом сохраняет подтверждённый признак',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.repository.page(0, []);
      await pumpEventQueue();
      h.model.setMode(TagCatalogSelectionMode(_target(1)));
      h.repository.selectionPage(1, _target(1), [
        TagSelectionRow(tag: _tag(1, 'Дом'), isAssigned: true),
      ], revision: 2);
      await pumpEventQueue();
      final original = h.coordinator.acceptTagAssign(
        AssignTag(tagId: _id(1), target: _target(1)),
      ) as TagCommandAccepted;
      h.repository.completeCommand(
        TagAssignmentChanged(
          TagAssignmentChangedChange(
            revision: const _Revision(2),
            assignment: TagAssignment(tagId: _id(1), target: _target(1)),
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

  test('отсутствие выбранного тега до пакета убирает строку и отбрасывает старые страницы', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    final cursor = _Cursor();
    h.repository.page(0, [_tag(1, 'Дом'), _tag(2, 'Работа')], cursor: cursor);
    await pumpEventQueue();
    h.model.selectTag(_id(1));
    h.repository.tagRead(_tag(1, 'Дом'));
    await pumpEventQueue();

    final pending = h.model.loadMore();
    h.repository.tagRead(null, revision: 2);
    await pumpEventQueue();
    final refreshing = h.state as TagCatalogLoaded;
    expect(refreshing.items.map((tag) => tag.id), [_id(2)]);
    expect(refreshing.selection, isA<TagCatalogNoSelection>());
    expect(refreshing.freshness, TagCatalogFreshness.refreshing);
    expect(h.model.canActOn(_id(1)), isFalse);
    expect(h.model.canActOn(_id(2)), isFalse);

    h.repository.page(1, [_tag(1, 'Дом'), _tag(3, 'Поздний')]);
    await pending;
    expect(h.repository.queries[2].cursor, isNull);
    h.repository.page(2, [_tag(1, 'Дом'), _tag(2, 'Работа')]);
    await pumpEventQueue();
    expect((h.state as TagCatalogLoaded).items.map((tag) => tag.id), [_id(2)]);
    expect(h.repository.queries[3].cursor, isNull);

    final freshCursor = _Cursor();
    h.repository.page(3, [_tag(2, 'Работа')], cursor: freshCursor, revision: 2);
    await pumpEventQueue();
    final fresh = h.state as TagCatalogLoaded;
    expect(fresh.freshness, TagCatalogFreshness.current);
    expect(fresh.items.map((tag) => tag.id), [_id(2)]);
    expect(h.model.canActOn(_id(2)), isTrue);
    final more = h.model.loadMore();
    expect(h.repository.queries[4].cursor, same(freshCursor));
    h.repository.page(4, [_tag(3, 'Поздний')], revision: 2);
    await more;
    expect((h.state as TagCatalogLoaded).items.map((tag) => tag.id), [
      _id(2),
      _id(3),
    ]);
    expect(
      h.repository.queries.every((query) => query.pageSize <= 100),
      isTrue,
    );
  });

  test(
    'отсутствие выбранного тега вне порции очищает выбор до пакета',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.repository.page(0, [_tag(1, 'Дом')], cursor: _Cursor());
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
    },
  );

  test('старое отсутствие не очищает выбор с новой страницы', () async {
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
    'отсутствие вне новой порции очищает выбор после постороннего пакета',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.repository.page(0, [_tag(1, 'Дом')], cursor: _Cursor(), revision: 3);
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

  test(
    'страница новой ревизии перед пакетом обновляет выбранное имя',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.repository.page(0, [_tag(1, 'Дом')], cursor: _Cursor(), revision: 2);
      await pumpEventQueue();
      h.model.selectTag(_id(52));
      h.repository.tagRead(_tag(52, 'Старое имя'));
      await pumpEventQueue();

      await h.renamed(
        _tag(52, 'Старое имя'),
        _tag(52, 'Новое имя'),
        revision: 2,
      );
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
    },
  );

  test(
    'страница новой ревизии перед пакетом очищает удалённый выбор',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.repository.page(0, [_tag(1, 'Дом')], cursor: _Cursor(), revision: 2);
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
    },
  );

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

  test('поздняя первая страница не откатывает более новую основу', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.repository.page(
      0,
      [_tag(52, 'Последнее имя')],
      cursor: _Cursor(),
      revision: 3,
    );
    await pumpEventQueue();
    h.model.selectTag(_id(52));
    h.repository.tagRead(_tag(52, 'Старое имя'));
    await pumpEventQueue();

    final more = h.model.loadMore();
    h.repository.page(1, [_tag(52, 'Промежуточное имя')], revision: 2);
    await more;
    await pumpEventQueue();
    expect(h.repository.queries, hasLength(3));
    await h.renamed(
      _tag(52, 'Старое имя'),
      _tag(52, 'Промежуточное имя'),
      revision: 2,
    );

    h.repository.page(2, [_tag(52, 'Промежуточное имя')], revision: 2);
    await pumpEventQueue();
    expect(h.repository.queries, hasLength(4));
    expect(
      (h.state as TagCatalogLoaded).revision,
      isA<_Revision>().having((revision) => revision.number, 'номер', 3),
    );

    h.repository.page(3, [_tag(52, 'Последнее имя')], revision: 3);
    await pumpEventQueue();
    final loaded = h.state as TagCatalogLoaded;
    expect(loaded.items.single.name.value, 'Последнее имя');
    expect(loaded.freshness, TagCatalogFreshness.current);
    expect(
      loaded.selection,
      isA<TagCatalogSelectionReady>().having(
        (selection) => selection.tag.name.value,
        'название',
        'Последнее имя',
      ),
    );
  });

  test(
    'выбор вне порции следует подтверждённому переименованию и удалению',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.repository.page(0, [_tag(1, 'Дом')], cursor: _Cursor());
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

      await h.renamed(
        _tag(52, 'Старое имя'),
        _tag(52, 'Новое имя'),
        revision: 2,
      );
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
      expect(
        h.repository.queries.every((query) => query.pageSize <= 100),
        isTrue,
      );
    },
  );

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
    'подгрузка запрашивается один раз и повторяет сохранённый курсор',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      final cursor = _Cursor();
      h.repository.page(0, [_tag(1, 'Дом')], cursor: cursor);
      await pumpEventQueue();
      final first = h.model.loadMore();
      final duplicate = h.model.loadMore();
      expect(h.repository.queries, hasLength(2));
      expect(h.repository.queries[1].cursor, same(cursor));
      h.repository.fail(1, const TagCatalogUnavailableFailure());
      await Future.wait([first, duplicate]);
      final failed = h.state as TagCatalogLoaded;
      expect(failed.items.map((tag) => tag.id), [_id(1)]);
      expect(failed.nextCursor, same(cursor));
      expect(failed.pageStatus, isA<TagCatalogPageFailure>());
      final retry = h.model.retryLoadMore();
      expect(h.repository.queries[2].cursor, same(cursor));
      h.repository.page(2, [_tag(2, 'Работа')]);
      await retry;
      expect((h.state as TagCatalogLoaded).items.map((tag) => tag.id), [
        _id(1),
        _id(2),
      ]);
    },
  );

  test('завершение до первой порции отклоняет старый снимок', () async {
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

  test('переименование во время подгрузки не возвращает старое имя', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    final cursor = _Cursor();
    h.repository.page(0, [_tag(1, 'Дом')], cursor: cursor);
    await pumpEventQueue();
    final pending = h.model.loadMore();
    await h.renamed(_tag(1, 'Дом'), _tag(1, 'Семья'), revision: 2);
    final refreshing = h.state as TagCatalogLoaded;
    expect(refreshing.items.single.name.value, 'Семья');
    expect(refreshing.freshness, TagCatalogFreshness.refreshing);
    expect(refreshing.canUseCurrentItems, isFalse);
    h.repository.page(1, [_tag(2, 'Работа')]);
    await pending;
    expect(h.repository.queries[2].cursor, isNull);
    h.repository.page(2, [_tag(1, 'Семья'), _tag(2, 'Работа')], revision: 2);
    await pumpEventQueue();
    expect((h.state as TagCatalogLoaded).items.map((tag) => tag.name.value), [
      'Семья',
      'Работа',
    ]);
  });

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
    h.repository.page(0, [_tag(1, 'Дом')], cursor: _Cursor());
    await pumpEventQueue();
    final pending = h.model.loadMore();
    await h.deleted(_id(1), revision: 2);
    expect((h.state as TagCatalogLoaded).items, isEmpty);
    h.repository.page(1, [_tag(1, 'Дом'), _tag(2, 'Работа')]);
    await pending;
    expect(h.repository.queries[2].cursor, isNull);
    h.repository.page(2, [_tag(2, 'Работа')], revision: 2);
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

  test('новая эпоха отбрасывает позднюю порцию прежней эпохи', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.repository.page(0, [_tag(1, 'Дом')], cursor: _Cursor());
    await pumpEventQueue();
    final pending = h.model.loadMore();
    await h.deleted(_id(1), revision: 1, epoch: 1);
    h.repository.page(1, [_tag(2, 'Работа')]);
    await pending;
    expect(h.repository.queries[2].cursor, isNull);
    h.repository.page(2, [_tag(3, 'Другое')], revision: 1, epoch: 1);
    await pumpEventQueue();
    final loaded = h.state as TagCatalogLoaded;
    expect(loaded.items.map((tag) => tag.id), [_id(3)]);
    expect(
      loaded.revision.compareTo(const _Revision(1, 1)),
      GraphRevisionOrder.same,
    );
  });

  test('недопустимое продолжение начинает чтение с первой порции', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.repository.page(0, [_tag(1, 'Дом')], cursor: _Cursor());
    await pumpEventQueue();
    final pending = h.model.loadMore();
    h.repository.fail(1, const TagCatalogInvalidCursor());
    await pending;
    expect(h.repository.queries[2].cursor, isNull);
    h.repository.page(2, [_tag(1, 'Дом'), _tag(2, 'Работа')]);
    await pumpEventQueue();
    expect((h.state as TagCatalogLoaded).items.map((tag) => tag.id), [
      _id(1),
      _id(2),
    ]);
  });

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
  final queries = <TagCatalogQuery>[];
  final pages = <Completer<TagCatalogPageResult>>[];
  final commands = <Completer<TagCommandResult>>[];
  final tagReads = <StreamController<TagReadResult>>[];
  final statusQueries = <(TagId, TagTarget)>[];
  final statusReads = <Completer<TagAssignmentStatusResult>>[];

  @override
  Future<TagAssignmentStatusResult> getTagAssignmentStatus(
    TagId id,
    TagTarget target,
  ) {
    statusQueries.add((id, target));
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
  Future<TagCatalogPageResult> getTagCatalogPage(TagCatalogQuery query) {
    queries.add(query);
    final completer = Completer<TagCatalogPageResult>();
    pages.add(completer);
    return completer.future;
  }

  void page(
    int index,
    List<Tag> tags, {
    TagCatalogCursor? cursor,
    int revision = 1,
    int epoch = 0,
  }) {
    pages[index].complete(
      TagCatalogPageSuccess(
        TagCatalogPage(
          items: tags,
          pageSize: TagCatalogQuery.defaultPageSize,
          nextCursor: cursor,
          revision: _Revision(revision, epoch),
        ),
      ),
    );
  }

  void fail(int index, TagCatalogReadFailure failure) =>
      pages[index].complete(TagCatalogPageError(failure));

  void selectionPage(
    int index,
    TagTarget target,
    List<TagSelectionRow> rows, {
    TagCatalogCursor? cursor,
    int revision = 1,
  }) => pages[index].complete(
    TagCatalogPageSuccess(
      TagCatalogPage.selection(
        target: target,
        rows: rows,
        pageSize: TagCatalogQuery.defaultPageSize,
        nextCursor: cursor,
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

final class _Cursor implements TagCatalogCursor {}

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
TagTarget _target(int number) => IntentionTagTarget(
  (IntentionId.decode(
    '00000000-0000-4000-8000-${number.toString().padLeft(12, '0')}',
  ) as IntentionIdDecodingSuccess).id,
);
TagTarget _relationTarget(int number) => LongTermRelationTagTarget(
  (LongTermRelationId.decode(
    '00000000-0000-4000-8000-${number.toString().padLeft(12, '0')}',
  ) as LongTermRelationIdDecodingSuccess).id,
);
Tag _tag(int number, String name) =>
    Tag(id: _id(number), name: TagName.fromInput(name));
