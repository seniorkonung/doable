import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_assignments.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/domain/tag_id.dart';

mixin TagReadContractTestFallback implements TagReadContract {
  @override
  Future<TagAssignmentsResult> getTagAssignments(
    IntentionId intentionId,
  ) async => const TagAssignmentsError(TagAssignmentsUnexpectedFailure());

  @override
  Future<TagCatalogResult> getTagCatalog(TagCatalogMode mode) async =>
      const TagCatalogError(TagCatalogUnexpectedFailure());

  @override
  Stream<TagReadResult> watchTag(TagId id) =>
      Stream.value(const TagReadError(TagReadUnexpectedFailure()));
}
