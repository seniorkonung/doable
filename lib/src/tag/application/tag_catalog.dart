import '../../graph/application/graph_command_result.dart';
import '../../graph/application/graph_revision.dart';
import '../domain/tag.dart';
import '../domain/tag_target.dart';

sealed class TagCatalogMode {
  const TagCatalogMode();
}

final class TagCatalogBrowseMode extends TagCatalogMode {
  const TagCatalogBrowseMode();

  @override
  bool operator ==(Object other) => other is TagCatalogBrowseMode;

  @override
  int get hashCode => 0;
}

final class TagCatalogSelectionMode extends TagCatalogMode {
  const TagCatalogSelectionMode(this.target);

  final TagTarget target;

  @override
  bool operator ==(Object other) =>
      other is TagCatalogSelectionMode && other.target == target;

  @override
  int get hashCode => Object.hash(TagCatalogSelectionMode, target);
}

/// Полный неизменяемый каталог на одной подтверждённой ревизии.
sealed class TagCatalogSnapshot {
  factory TagCatalogSnapshot({
    required List<Tag> items,
    required GraphRevision revision,
  }) => TagBrowseSnapshot._(List.unmodifiable(items), revision);

  factory TagCatalogSnapshot.selection({
    required TagTarget target,
    required List<TagSelectionRow> rows,
    required GraphRevision revision,
  }) {
    final immutableRows = List<TagSelectionRow>.unmodifiable(rows);
    return TagSelectionSnapshot._(
      target,
      immutableRows,
      List<Tag>.unmodifiable(immutableRows.map((row) => row.tag)),
      revision,
    );
  }

  const TagCatalogSnapshot._(this.items, this.revision);
  final List<Tag> items;
  final GraphRevision revision;
}

final class TagBrowseSnapshot extends TagCatalogSnapshot {
  const TagBrowseSnapshot._(super.items, super.revision) : super._();
}

final class TagSelectionRow {
  const TagSelectionRow({required this.tag, required this.isAssigned});
  final Tag tag;
  final bool isAssigned;
}

final class TagSelectionSnapshot extends TagCatalogSnapshot {
  const TagSelectionSnapshot._(
    this.target,
    this.rows,
    super.items,
    super.revision,
  ) : super._();
  final TagTarget target;
  final List<TagSelectionRow> rows;
}

sealed class TagCatalogReadFailure implements GraphCommandFailure {
  const TagCatalogReadFailure();
}

final class TagCatalogTargetNotFound extends TagCatalogReadFailure {
  const TagCatalogTargetNotFound();

  @override
  GraphFailureCategory get category => GraphFailureCategory.notFound;
}

final class TagCatalogUnavailableFailure extends TagCatalogReadFailure {
  const TagCatalogUnavailableFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unavailable;
}

final class TagCatalogCorruptionFailure extends TagCatalogReadFailure {
  const TagCatalogCorruptionFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.corruption;
}

final class TagCatalogUnexpectedFailure extends TagCatalogReadFailure {
  const TagCatalogUnexpectedFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unexpected;
}

typedef TagCatalogResult =
    GraphResult<TagCatalogSnapshot, TagCatalogReadFailure>;
typedef TagCatalogSuccess =
    GraphResultSuccess<TagCatalogSnapshot, TagCatalogReadFailure>;
typedef TagCatalogError =
    GraphResultFailure<TagCatalogSnapshot, TagCatalogReadFailure>;
