import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_assignments.dart';
import 'package:doable/src/tag/application/tag_assignment_status.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/application/tagged_intentions_page.dart';
import 'package:doable/src/tag/domain/tag_id.dart';

mixin TagReadContractTestFallback implements TagReadContract {
  @override
  Future<TagAssignmentStatusResult> getTagAssignmentStatus(
    TagId tagId,
    IntentionId intentionId,
  ) async => const TagAssignmentStatusError(TagAssignmentStatusUnexpected());

  @override
  Future<TagAssignmentsResult> getTagAssignments(
    IntentionId intentionId,
  ) async => const TagAssignmentsError(TagAssignmentsUnexpectedFailure());

  @override
  Future<TagCatalogResult> getTagCatalog(TagCatalogMode mode) async =>
      const TagCatalogError(TagCatalogUnexpectedFailure());

  @override
  Future<TaggedIntentionsPageResult> getTaggedIntentionsPage(
    TaggedIntentionsQuery query,
  ) async =>
      const TaggedIntentionsPageError(TaggedIntentionsUnexpectedFailure());

  @override
  Stream<TagReadResult> watchTag(TagId id) =>
      Stream.value(const TagReadError(TagReadUnexpectedFailure()));
}
