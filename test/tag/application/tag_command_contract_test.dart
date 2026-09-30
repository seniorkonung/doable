import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/domain/tag_assignment.dart';
import 'package:doable/src/tag/domain/tag_target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('команды принимают проверенное название и идентичность тега', () {
    final tag = _tag(1, 'Дом');
    final another = _tag(2, 'Дом');
    final name = TagName.fromInput('  Быт  ');

    final TagCommand create = CreateTag(name);
    final TagCommand rename = RenameTag(tagId: tag.id, name: name);
    final TagCommand delete = DeleteTag(tag.id);

    expect((create as CreateTag).name, same(name));
    expect((rename as RenameTag).tagId, tag.id);
    expect(rename.name, same(name));
    expect((delete as DeleteTag).tagId, tag.id);
    expect(delete.tagId, isNot(another.id));
  });

  test('изменения тега различают создание, переименование и удаление', () {
    const revision = _Revision(1);
    final before = _tag(1, 'Дом');
    final after = Tag(id: before.id, name: TagName.fromInput('Быт'));

    final created = TagCreatedChange(revision: revision, after: before);
    final renamed = TagRenamedChange(
      revision: revision,
      before: before,
      after: after,
    );
    final deleted = TagDeletedChange(revision: revision, tagId: before.id);

    expect(created.after, same(before));
    expect(renamed.before, same(before));
    expect(renamed.after, same(after));
    expect(deleted.tagId, before.id);
    expect(deleted, isNot(isA<Iterable>()));
    for (final change in <TagChange>[created, renamed, deleted]) {
      expect(change.revision, same(revision));
    }
  });

  test('переименование не допускает другую идентичность или прежнее имя', () {
    const revision = _Revision(1);
    final before = _tag(1, 'Дом');
    final otherId = _tag(2, 'Быт');
    final sameName = Tag(id: before.id, name: TagName.fromInput('Дом'));

    expect(
      () =>
          TagRenamedChange(revision: revision, before: before, after: otherId),
      throwsA(
        isA<TagChangeValidationException>().having(
          (error) => error.failure,
          'причина',
          TagChangeValidationFailure.identityMismatch,
        ),
      ),
    );
    expect(
      () =>
          TagRenamedChange(revision: revision, before: before, after: sameName),
      throwsA(
        isA<TagChangeValidationException>().having(
          (error) => error.failure,
          'причина',
          TagChangeValidationFailure.nameUnchanged,
        ),
      ),
    );
  });

  test('полностью одинаковое имя даёт непустой подтверждённый результат', () {
    const revision = _Revision(7);
    final tag = _tag(1, 'Дом');
    final unchanged = TagUnchangedChange(revision: revision, tag: tag);
    final outcome = TagUnchanged(unchanged);
    final confirmed = ConfirmedGraphResult<TagCommandSuccess>(
      revision: revision,
      value: outcome,
    );

    expect(outcome.tag, same(tag));
    expect(unchanged.before, same(unchanged.after));
    expect(confirmed.revision, same(revision));
    expect(confirmed.changes, [same(unchanged)]);
    expect(() => confirmed.changes.clear(), throwsUnsupportedError);
  });

  test('пакет команды содержит одно компактное изменение той же ревизии', () {
    const revision = _Revision(8);
    final before = _tag(1, 'Дом');
    final after = Tag(id: before.id, name: TagName.fromInput('Быт'));
    final created = TagCreated(
      TagCreatedChange(revision: revision, after: before),
    );
    final renamed = TagRenamed(
      TagRenamedChange(revision: revision, before: before, after: after),
    );
    final deleted = TagDeleted(
      TagDeletedChange(revision: revision, tagId: before.id),
    );

    for (final outcome in <TagCommandSuccess>[created, renamed, deleted]) {
      final confirmed = ConfirmedGraphResult<TagCommandSuccess>(
        revision: revision,
        value: outcome,
      );
      expect(confirmed.changes, hasLength(1));
      expect(confirmed.changes.single, same(outcome.change));
    }
    expect(created.tag, same(before));
    expect(renamed.before.id, renamed.after.id);
    expect(deleted.tagId, before.id);
  });

  test('занятое имя возвращает id, а остальные причины различимы', () {
    final existingId = _tag(1, 'Дом').id;
    final failures = <TagCommandFailure>[
      const TagNameInputFailure(TagNameFailureReason.empty),
      TagNameOccupiedFailure(existingId),
      TagNotFoundFailure(existingId),
      const TagUnavailableFailure(),
      const TagCorruptionFailure(),
      const TagUnexpectedFailure(),
    ];

    expect(failures.map((failure) => failure.category), [
      GraphFailureCategory.validation,
      GraphFailureCategory.conflict,
      GraphFailureCategory.notFound,
      GraphFailureCategory.unavailable,
      GraphFailureCategory.corruption,
      GraphFailureCategory.unexpected,
    ]);
    expect((failures[1] as TagNameOccupiedFailure).existingTagId, existingId);
    expect((failures[2] as TagNotFoundFailure).tagId, existingId);
  });

  test('команды назначения хранят одну пару обоих видов получателя', () {
    final tagId = _tag(1, 'Дом').id;
    final targets = <TagTarget>[
      IntentionTagTarget(_intentionId(1)),
      LongTermRelationTagTarget(_relationId(1)),
    ];

    for (final target in targets) {
      final TagCommand assign = AssignTag(tagId: tagId, target: target);
      final TagCommand remove = RemoveTagAssignment(
        tagId: tagId,
        target: target,
      );
      final pair = TagAssignment(tagId: tagId, target: target);

      expect((assign as AssignTag).assignment, pair);
      expect((remove as RemoveTagAssignment).assignment, pair);
    }
    expect(targets.first, isNot(targets.last));
  });

  test('изменение назначения и подтверждённый повтор дают один факт', () {
    const oldRevision = _Revision(4);
    const newRevision = _Revision(5);
    final pair = TagAssignment(
      tagId: _tag(1, 'Дом').id,
      target: IntentionTagTarget(_intentionId(2)),
    );

    for (final state in TagAssignmentState.values) {
      final changed = TagAssignmentChanged(
        TagAssignmentChangedChange(
          revision: newRevision,
          assignment: pair,
          state: state,
        ),
      );
      final repeated = TagAssignmentUnchanged(
        TagAssignmentUnchangedChange(
          revision: oldRevision,
          assignment: pair,
          state: state,
        ),
      );
      final confirmedChange = ConfirmedGraphResult<TagCommandSuccess>(
        revision: newRevision,
        value: changed,
      );
      final confirmedRepeat = ConfirmedGraphResult<TagCommandSuccess>(
        revision: oldRevision,
        value: repeated,
      );

      expect(changed.assignment, pair);
      expect(changed.state, state);
      expect(repeated.assignment, pair);
      expect(repeated.state, state);
      expect(confirmedChange.changes, [same(changed.change)]);
      expect(confirmedRepeat.changes, [same(repeated.change)]);
      expect(() => confirmedRepeat.changes.clear(), throwsUnsupportedError);
      expect(
        () => ConfirmedGraphResult<TagCommandSuccess>(
          revision: oldRevision,
          value: changed,
        ),
        throwsA(
          isA<ConfirmedGraphResultValidationException>().having(
            (error) => error.failure,
            'причина',
            ConfirmedGraphResultValidationFailure.revisionMismatch,
          ),
        ),
      );
    }
  });

  test(
    'изменение назначения намерению несёт каталожный снимок той же ревизии',
    () {
      const revision = _Revision(6);
      final tag = _tag(1, 'Дом');
      final intentionId = _intentionId(2);
      final pair = TagAssignment(
        tagId: tag.id,
        target: IntentionTagTarget(intentionId),
      );

      for (final state in TagAssignmentState.values) {
        final mutation = IntentionCatalogUpdated(
          revision: revision,
          before: _entry(intentionId, [
            if (state == TagAssignmentState.absent) tag,
          ]),
          after: _entry(intentionId, [
            if (state == TagAssignmentState.assigned) tag,
          ]),
        );
        final changed = TagAssignmentChanged(
          TagAssignmentChangedChange(
            revision: revision,
            assignment: pair,
            state: state,
          ),
          catalogMutation: mutation,
        );
        final confirmed = ConfirmedGraphResult<TagCommandSuccess>(
          revision: revision,
          value: changed,
        );

        expect(changed.catalogMutation, same(mutation));
        expect(confirmed.changes, [same(changed.change), same(mutation)]);
        expect(confirmed.changes.whereType<IntentionCatalogMutation>(), [
          same(mutation),
        ]);
      }
    },
  );

  test('изменение назначения связи не несёт каталожного снимка', () {
    const revision = _Revision(6);
    final changed = TagAssignmentChanged(
      TagAssignmentChangedChange(
        revision: revision,
        assignment: TagAssignment(
          tagId: _tag(1, 'Дом').id,
          target: LongTermRelationTagTarget(_relationId(1)),
        ),
        state: TagAssignmentState.assigned,
      ),
    );

    expect(changed.catalogMutation, isNull);
    expect(
      ConfirmedGraphResult<TagCommandSuccess>(
        revision: revision,
        value: changed,
      ).changes,
      [same(changed.change)],
    );
  });

  test('каталожный снимок принадлежит только намерению из пары', () {
    const revision = _Revision(6);
    final tagId = _tag(1, 'Дом').id;
    final intentionId = _intentionId(2);
    final otherId = _intentionId(3);
    TagAssignmentChangedChange change(TagTarget target) =>
        TagAssignmentChangedChange(
          revision: revision,
          assignment: TagAssignment(tagId: tagId, target: target),
          state: TagAssignmentState.assigned,
        );
    IntentionCatalogUpdated mutation(IntentionId before, IntentionId after) =>
        IntentionCatalogUpdated(
          revision: revision,
          before: _entry(before, const []),
          after: _entry(after, const []),
        );
    final mismatch = throwsA(
      isA<TagCommandSuccessValidationException>().having(
        (error) => error.failure,
        'причина',
        TagCommandSuccessValidationFailure.catalogMutationTargetMismatch,
      ),
    );

    expect(
      () => TagAssignmentChanged(
        change(LongTermRelationTagTarget(_relationId(1))),
        catalogMutation: mutation(intentionId, intentionId),
      ),
      mismatch,
    );
    for (final (before, after) in [
      (otherId, otherId),
      (intentionId, otherId),
      (otherId, intentionId),
    ]) {
      expect(
        () => TagAssignmentChanged(
          change(IntentionTagTarget(intentionId)),
          catalogMutation: mutation(before, after),
        ),
        mismatch,
      );
    }
  });

  test('каталожный снимок другой ревизии отклоняется пакетом', () {
    final intentionId = _intentionId(2);
    final changed = TagAssignmentChanged(
      TagAssignmentChangedChange(
        revision: const _Revision(6),
        assignment: TagAssignment(
          tagId: _tag(1, 'Дом').id,
          target: IntentionTagTarget(intentionId),
        ),
        state: TagAssignmentState.assigned,
      ),
      catalogMutation: IntentionCatalogUpdated(
        revision: const _Revision(5),
        before: _entry(intentionId, const []),
        after: _entry(intentionId, const []),
      ),
    );

    expect(
      () => ConfirmedGraphResult<TagCommandSuccess>(
        revision: const _Revision(6),
        value: changed,
      ),
      throwsA(
        isA<ConfirmedGraphResultValidationException>().having(
          (error) => error.failure,
          'причина',
          ConfirmedGraphResultValidationFailure.revisionMismatch,
        ),
      ),
    );
  });

  test('отсутствие тега и получателя различаются по идентичности', () {
    final tagId = _tag(1, 'Дом').id;
    final target = LongTermRelationTagTarget(_relationId(2));
    final missingTag = TagNotFoundFailure(tagId);
    final missingTarget = TagTargetNotFoundFailure(target);

    expect(missingTag.category, GraphFailureCategory.notFound);
    expect(missingTarget.category, GraphFailureCategory.notFound);
    expect(missingTag.tagId, tagId);
    expect(missingTarget.target, target);
  });
}

IntentionId _intentionId(int suffix) => (IntentionId.decode(
  '00000000-0000-4000-8000-${suffix.toString().padLeft(12, '0')}',
) as IntentionIdDecodingSuccess).id;

LongTermRelationId _relationId(int suffix) => (LongTermRelationId.decode(
  '00000000-0000-4000-8000-${suffix.toString().padLeft(12, '0')}',
) as LongTermRelationIdDecodingSuccess).id;

Tag _tag(int suffix, String name) {
  final text = '00000000-0000-4000-8000-${suffix.toString().padLeft(12, '0')}';
  final decoded = TagId.decode(text) as TagIdDecodingSuccess;
  return Tag(id: decoded.id, name: TagName.fromInput(name));
}

IntentionCatalogEntrySnapshot _entry(IntentionId id, List<Tag> tags) => _Entry(
  IntentionSummary(
    id: id,
    title: 'Намерение',
    hasDescription: false,
    readiness: IntentionReadiness.notReady,
    archiveState: IntentionArchiveState.active,
    activeRelationCount: 0,
    createdAt: IntentionTimestamp(DateTime.utc(2026, 9, 1)),
    updatedAt: IntentionTimestamp(DateTime.utc(2026, 9, 2)),
    tags: tags,
  ),
);

final class _Entry implements IntentionCatalogEntrySnapshot {
  const _Entry(this.summary);

  @override
  final IntentionSummary summary;

  @override
  bool matches(IntentionCatalogQuery query) => true;
}

final class _Revision implements GraphRevision {
  const _Revision(this.value);

  final int value;

  @override
  GraphRevisionOrder compareTo(GraphRevision other) => switch (other) {
    _Revision(value: final otherValue) when value < otherValue =>
      GraphRevisionOrder.older,
    _Revision(value: final otherValue) when value > otherValue =>
      GraphRevisionOrder.newer,
    _Revision() => GraphRevisionOrder.same,
    _ => GraphRevisionOrder.differentEpoch,
  };
}
