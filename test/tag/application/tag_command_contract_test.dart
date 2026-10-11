import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/domain/tag_assignment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

  test('изменение назначения и подтверждённый повтор дают один факт', () {
    const oldRevision = _Revision(4);
    const newRevision = _Revision(5);
    final pair = TagAssignment(
      tagId: _tag(1, 'Дом').id,
      intentionId: _intentionId(2),
    );

    for (final state in TagAssignmentState.values) {
      final mutation = IntentionCatalogUpdated(
        revision: newRevision,
        before: _entry(pair.intentionId, const []),
        after: _entry(pair.intentionId, const []),
      );
      final changed = TagAssignmentChanged(
        TagAssignmentChangedChange(
          revision: newRevision,
          assignment: pair,
          state: state,
        ),
        catalogMutation: mutation,
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

      // Подтверждённое изменение несёт факт и каталожный снимок, а повтор
      // только факт без нового каталожного изменения.
      expect(confirmedChange.changes, [changed.change, mutation]);
      expect(confirmedRepeat.changes, [repeated.change]);
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

  test('каталожный снимок принадлежит только намерению из пары', () {
    const revision = _Revision(6);
    final tagId = _tag(1, 'Дом').id;
    final intentionId = _intentionId(2);
    final otherId = _intentionId(3);
    final change = TagAssignmentChangedChange(
      revision: revision,
      assignment: TagAssignment(tagId: tagId, intentionId: intentionId),
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

    for (final (before, after) in [
      (otherId, otherId),
      (intentionId, otherId),
      (otherId, intentionId),
    ]) {
      expect(
        () => TagAssignmentChanged(
          change,
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
          intentionId: intentionId,
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
}

IntentionId _intentionId(int suffix) => (IntentionId.decode(
  '00000000-0000-4000-8000-${suffix.toString().padLeft(12, '0')}',
) as IntentionIdDecodingSuccess).id;

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
