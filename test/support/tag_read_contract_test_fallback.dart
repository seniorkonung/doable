import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_assignments_page.dart';
import 'package:doable/src/tag/application/tag_assignment_status.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_target.dart';

mixin TagReadContractTestFallback implements TagReadContract {
  @override
  Future<TagAssignmentStatusResult> getTagAssignmentStatus(
    TagId tagId,
    TagTarget target,
  ) async => const TagAssignmentStatusError(TagAssignmentStatusUnexpected());

  @override
  Future<TagAssignmentsPageResult> getTagAssignmentsPage(
    TagAssignmentsQuery query,
  ) async => const TagAssignmentsPageError(TagAssignmentsUnexpectedFailure());

  @override
  Future<TagCatalogPageResult> getTagCatalogPage(TagCatalogQuery query) async =>
      const TagCatalogPageError(TagCatalogUnexpectedFailure());

  @override
  Stream<TagReadResult> watchTag(TagId id) =>
      Stream.value(const TagReadError(TagReadUnexpectedFailure()));
}
