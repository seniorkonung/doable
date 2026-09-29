import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_revision.dart';
import '../../application/tag_catalog.dart';
import '../../application/tag_read_result.dart';
import '../../domain/tag.dart';
import '../../domain/tag_id.dart';
import '../../../intention/domain/intention_id.dart';

sealed class TagCatalogState {
  const TagCatalogState();
}

final class TagCatalogInitialLoading extends TagCatalogState {
  const TagCatalogInitialLoading({this.mode = const TagCatalogBrowseMode()});

  final TagCatalogMode mode;
}

final class TagCatalogInitialFailure extends TagCatalogState {
  const TagCatalogInitialFailure(
    this.failure, {
    this.mode = const TagCatalogBrowseMode(),
  });

  final TagCatalogReadFailure failure;
  final TagCatalogMode mode;
  bool get canRetry => failure is TagCatalogUnavailableFailure;
}

final class TagCatalogIntentionMissing extends TagCatalogState {
  const TagCatalogIntentionMissing(this.intentionId);

  final IntentionId intentionId;
}

enum TagCatalogFreshness { current, refreshing, stale }

/// Признак относится только к выбранному тегу и получателю текущего режима.
/// Неизвестный признак не разрешает отправку назначения.
enum TagCatalogSelectedAssignment {
  unknown,
  available,
  assigned,
  unavailable,
  corruption,
  unexpected,
}

sealed class TagCatalogSelection {
  const TagCatalogSelection();

  TagId? get id;
}

final class TagCatalogNoSelection extends TagCatalogSelection {
  const TagCatalogNoSelection();

  @override
  TagId? get id => null;
}

final class TagCatalogSelectionLoading extends TagCatalogSelection {
  const TagCatalogSelectionLoading(this.id);

  @override
  final TagId id;
}

final class TagCatalogSelectionReady extends TagCatalogSelection {
  const TagCatalogSelectionReady(this.tag);

  final Tag tag;

  @override
  TagId get id => tag.id;
}

final class TagCatalogSelectionFailure extends TagCatalogSelection {
  const TagCatalogSelectionFailure(this.id, this.failure);

  @override
  final TagId id;
  final TagReadFailure failure;
  bool get canRetry => failure is TagReadUnavailableFailure;
}

sealed class TagCatalogAssignmentStatus {
  const TagCatalogAssignmentStatus();
}

final class TagCatalogAssignmentIdle extends TagCatalogAssignmentStatus {
  const TagCatalogAssignmentIdle();
}

final class TagCatalogAssignmentSubmitting extends TagCatalogAssignmentStatus {
  const TagCatalogAssignmentSubmitting(this.tagId, this.token);

  final TagId tagId;
  final TagOperationToken token;
}

final class TagCatalogAssignmentKeysBusy extends TagCatalogAssignmentStatus {
  const TagCatalogAssignmentKeysBusy(this.tagId);

  final TagId tagId;
}

/// Строки принадлежат одному полному отображаемому снимку. При актуализации
/// известные имена и удаления учитываются сразу, но список остаётся неактуальным.
final class TagCatalogLoaded extends TagCatalogState {
  TagCatalogLoaded({
    required this.mode,
    required List<Tag> items,
    List<TagSelectionRow> selectionRows = const [],
    required this.revision,
    this.selection = const TagCatalogNoSelection(),
    this.freshness = TagCatalogFreshness.current,
    this.refreshFailure,
    this.assignmentStatus = const TagCatalogAssignmentIdle(),
    this.selectedAssignment = TagCatalogSelectedAssignment.unknown,
  }) : items = List.unmodifiable(items),
       selectionRows = List.unmodifiable(selectionRows);

  final TagCatalogMode mode;
  final List<Tag> items;
  final List<TagSelectionRow> selectionRows;
  final GraphRevision revision;
  final TagCatalogSelection selection;
  final TagCatalogFreshness freshness;
  final TagCatalogReadFailure? refreshFailure;
  final TagCatalogAssignmentStatus assignmentStatus;
  final TagCatalogSelectedAssignment selectedAssignment;

  bool get isEmpty => items.isEmpty;
  bool get canUseCurrentItems => freshness == TagCatalogFreshness.current;

  TagCatalogLoaded withStatus({
    List<Tag>? items,
    List<TagSelectionRow>? selectionRows,
    TagCatalogFreshness? freshness,
    TagCatalogReadFailure? refreshFailure,
    TagCatalogSelection? selection,
    TagCatalogAssignmentStatus? assignmentStatus,
    TagCatalogSelectedAssignment? selectedAssignment,
  }) => TagCatalogLoaded(
    mode: mode,
    items: items ?? this.items,
    selectionRows: selectionRows ?? this.selectionRows,
    revision: revision,
    selection: selection ?? this.selection,
    freshness: freshness ?? this.freshness,
    refreshFailure: refreshFailure ?? this.refreshFailure,
    assignmentStatus: assignmentStatus ?? this.assignmentStatus,
    selectedAssignment: selectedAssignment ?? this.selectedAssignment,
  );
}
