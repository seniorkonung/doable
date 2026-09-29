import '../../graph/application/graph_command_result.dart';
import '../../graph/application/graph_revision.dart';
import '../../intention/domain/intention_id.dart';
import '../domain/tag.dart';

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
  const TagCatalogSelectionMode(this.intentionId);

  final IntentionId intentionId;

  @override
  bool operator ==(Object other) =>
      other is TagCatalogSelectionMode && other.intentionId == intentionId;

  @override
  int get hashCode => Object.hash(TagCatalogSelectionMode, intentionId);
}

/// Полный неизменяемый каталог в порядке создания тегов на одной ревизии.
sealed class TagCatalogSnapshot {
  factory TagCatalogSnapshot({
    required List<Tag> items,
    required GraphRevision revision,
  }) => TagBrowseSnapshot._(List.unmodifiable(items), revision);

  factory TagCatalogSnapshot.selection({
    required IntentionId intentionId,
    required List<TagSelectionRow> rows,
    required GraphRevision revision,
  }) {
    final immutableRows = List<TagSelectionRow>.unmodifiable(rows);
    return TagSelectionSnapshot._(
      intentionId,
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
    this.intentionId,
    this.rows,
    super.items,
    super.revision,
  ) : super._();
  final IntentionId intentionId;
  final List<TagSelectionRow> rows;
}

sealed class TagCatalogReadFailure implements GraphCommandFailure {
  const TagCatalogReadFailure();
}

final class TagCatalogIntentionNotFound extends TagCatalogReadFailure {
  const TagCatalogIntentionNotFound();

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
