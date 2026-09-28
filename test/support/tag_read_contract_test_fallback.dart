import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_assignments.dart';
import 'package:doable/src/tag/application/tag_assignment_status.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/application/tagged_entities_page.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_target.dart';

mixin TagReadContractTestFallback implements TagReadContract {
  @override
  Future<TagAssignmentStatusResult> getTagAssignmentStatus(
    TagId tagId,
    TagTarget target,
  ) async => const TagAssignmentStatusError(TagAssignmentStatusUnexpected());

  @override
  Future<TagAssignmentsResult> getTagAssignments(TagTarget target) async =>
      const TagAssignmentsError(TagAssignmentsUnexpectedFailure());

  @override
  Future<TagCatalogResult> getTagCatalog(TagCatalogMode mode) async =>
      const TagCatalogError(TagCatalogUnexpectedFailure());

  @override
  Future<TaggedEntitiesPageResult> getTaggedEntitiesPage(
    TaggedEntitiesQuery query,
  ) async => const TaggedEntitiesPageError(TaggedEntitiesUnexpectedFailure());

  @override
  Stream<TagReadResult> watchTag(TagId id) =>
      Stream.value(const TagReadError(TagReadUnexpectedFailure()));
}
