import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_result.dart';

/// Собирает исход изменения назначения с каталожной мутацией того же
/// намерения и той же ревизии, как в пакете реальной команды тега.
TagAssignmentChanged testTagAssignmentChanged(
  TagAssignmentChangedChange change,
) {
  final entry = _TagAssignmentCatalogEntry(change.assignment.intentionId);
  return TagAssignmentChanged(
    change,
    catalogMutation: IntentionCatalogUpdated(
      revision: change.revision,
      before: entry,
      after: entry,
    ),
  );
}

final class _TagAssignmentCatalogEntry
    implements IntentionCatalogEntrySnapshot {
  _TagAssignmentCatalogEntry(IntentionId id)
    : summary = IntentionSummary(
        id: id,
        title: 'Намерение',
        hasDescription: false,
        readiness: IntentionReadiness.notReady,
        archiveState: IntentionArchiveState.active,
        activeRelationCount: 0,
        createdAt: IntentionTimestamp(DateTime.utc(2026, 9, 1)),
        updatedAt: IntentionTimestamp(DateTime.utc(2026, 9, 2)),
        tags: const [],
      );

  @override
  final IntentionSummary summary;

  @override
  bool matches(IntentionCatalogQuery query) => true;
}
