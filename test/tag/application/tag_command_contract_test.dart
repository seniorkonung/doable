import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
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
}

Tag _tag(int suffix, String name) {
  final text = '00000000-0000-4000-8000-${suffix.toString().padLeft(12, '0')}';
  final decoded = TagId.decode(text) as TagIdDecodingSuccess;
  return Tag(id: decoded.id, name: TagName.fromInput(name));
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
