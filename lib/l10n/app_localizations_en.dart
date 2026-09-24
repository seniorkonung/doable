// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Doable';

  @override
  String get navigationActiveIntentions => 'Active intentions';

  @override
  String get navigationArchive => 'Archive';

  @override
  String get commonLoading => 'Loading…';

  @override
  String get commonEmpty => 'Nothing here yet';

  @override
  String get commonError => 'Something went wrong';

  @override
  String get commonRetry => 'Try again';

  @override
  String get bootstrapLoading => 'Preparing local data…';

  @override
  String get bootstrapMigrationFailure =>
      'Local data couldn’t be prepared. Your data wasn’t changed. Try again.';

  @override
  String get bootstrapCorruption =>
      'Local data is damaged and can’t be opened.';

  @override
  String get bootstrapIncompatibleSchema =>
      'Install a compatible Doable update to continue.';

  @override
  String get bootstrapUnexpectedFailure =>
      'Local data couldn’t be opened because of an unexpected error.';

  @override
  String get catalogLoading => 'Loading intentions…';

  @override
  String get catalogTitle => 'Intentions';

  @override
  String get catalogScopeLabel => 'Scope';

  @override
  String get catalogScopeActive => 'Active';

  @override
  String get catalogScopeArchived => 'Archived';

  @override
  String get catalogScopeAll => 'All';

  @override
  String get catalogFilterLabel => 'Filter by title';

  @override
  String get catalogFilterInvalidUnicode =>
      'Enter valid Unicode text without NUL.';

  @override
  String get catalogFilterTooLong => 'Use no more than 255 characters.';

  @override
  String get catalogOrderLabel => 'Order';

  @override
  String get catalogOrderCreatedNewest => 'Created: newest first';

  @override
  String get catalogOrderCreatedOldest => 'Created: oldest first';

  @override
  String get catalogOrderUpdatedNewest => 'Updated: newest first';

  @override
  String get catalogOrderUpdatedOldest => 'Updated: oldest first';

  @override
  String catalogTotalCount(int count) {
    return 'Total intentions: $count';
  }

  @override
  String get catalogActiveEmpty => 'No active intentions yet.';

  @override
  String get catalogArchivedEmpty => 'No archived intentions yet.';

  @override
  String get catalogAllEmpty => 'No intentions yet.';

  @override
  String get catalogUnavailable => 'Intentions couldn’t be loaded. Try again.';

  @override
  String get catalogCorruption =>
      'Stored intention data is damaged and can’t be shown.';

  @override
  String get catalogUnexpectedFailure =>
      'Intentions couldn’t be loaded because of an unexpected error.';

  @override
  String get catalogLoadingMore => 'Loading more intentions…';

  @override
  String get catalogLoadMoreUnavailable =>
      'More intentions couldn’t be loaded.';

  @override
  String get catalogLoadMoreCorruption =>
      'Stored intention data is damaged; no more intentions can be shown.';

  @override
  String get catalogLoadMoreUnexpected =>
      'More intentions couldn’t be loaded because of an unexpected error.';

  @override
  String get catalogLoadMoreValidation =>
      'The saved catalog position is no longer valid.';

  @override
  String get catalogReload => 'Reload catalog';

  @override
  String get catalogReloading => 'Reloading catalog…';

  @override
  String get catalogReady => 'Ready for action';

  @override
  String get catalogNotReady => 'Not ready for action';

  @override
  String get catalogHasDescription => 'Has description';

  @override
  String get catalogNoDescription => 'No description';

  @override
  String intentionActiveRelationCount(int count) {
    return 'Active relations: $count';
  }

  @override
  String get intentionActiveRelationCountRefreshFailed =>
      'The active relation count couldn’t be refreshed.';

  @override
  String get intentionActiveRelationCountLoading =>
      'Loading the active relation count…';

  @override
  String get intentionActiveRelationCountUnknown =>
      'The active relation count is unknown.';

  @override
  String get relationNeighborhoodTitle => 'Relations';

  @override
  String relationNeighborhoodSelectedCount(int count) {
    return 'Selected relations: $count';
  }

  @override
  String get relationNeighborhoodAddToSelection => 'Add to selection';

  @override
  String get relationNeighborhoodRemoveFromSelection => 'Remove from selection';

  @override
  String get blockingRelationsReviewAction => 'Review selected relations';

  @override
  String get blockingRelationsConfirmationTitle =>
      'Delete selected relations permanently?';

  @override
  String get blockingRelationsConfirmationWarning =>
      'Review every selected relation. This can’t be undone. The intention will remain; deleting it requires separate confirmation.';

  @override
  String blockingRelationsConfirmationCount(int count) {
    return 'To delete: $count';
  }

  @override
  String blockingRelationsParticipantId(String id) {
    return 'Identifier: $id';
  }

  @override
  String get blockingRelationsDeleting => 'Deleting selected relations…';

  @override
  String get blockingRelationsBusy =>
      'Another change to these relations or the intention is already running.';

  @override
  String get blockingRelationsDraining =>
      'The app is closing. The change was not accepted.';

  @override
  String get blockingRelationsEditSelectionAction => 'Return to selection';

  @override
  String get blockingRelationsRefreshSelectionAction => 'Refresh selection';

  @override
  String get blockingRelationsRefreshingSelection =>
      'Checking selected relations…';

  @override
  String blockingRelationsInvalidSelectedRelationId(String id) {
    return 'Relation: $id';
  }

  @override
  String get blockingRelationsInvalidMissing =>
      'This relation no longer exists. Remove it from the selection and confirm the remaining set again.';

  @override
  String get blockingRelationsInvalidMoved =>
      'This relation no longer belongs to this intention. Remove it from the selection and confirm the remaining set again.';

  @override
  String get blockingRelationsInvalidProtected =>
      'This relation is used in a saved daily path. First delete the daily choice separately, then select and confirm deletion of the freed long-term relation again. The entire selected set remains unchanged.';

  @override
  String get blockingRelationsRefreshIntentionNotFound =>
      'This intention no longer exists. Its relations cannot be deleted here.';

  @override
  String get blockingRelationsRefreshUnavailable =>
      'Selected relations could not be checked. Your selection is unchanged; try checking again.';

  @override
  String get blockingRelationsRefreshCorruption =>
      'Selected relations could not be checked because the data is damaged. Deletion was not started.';

  @override
  String get blockingRelationsRefreshUnexpected =>
      'Selected relations could not be checked. Deletion was not started.';

  @override
  String get blockingRelationsDeleteMissing =>
      'A selected relation no longer exists. Refresh the selection and confirm it again.';

  @override
  String get blockingRelationsDeleteMoved =>
      'A selected relation no longer belongs to this intention. Refresh the selection and confirm it again.';

  @override
  String get blockingRelationsDeleteProhibited =>
      'A selected relation is now used in a saved daily path. The entire set remains unchanged. First delete the daily choice separately, then select and confirm deletion of the freed long-term relation again.';

  @override
  String get relationNeighborhoodSummaryLoading =>
      'Loading relations and summary…';

  @override
  String get relationNeighborhoodSummaryUnavailable =>
      'The relation summary couldn’t be loaded.';

  @override
  String get relationNeighborhoodSavedSummaryRefreshing =>
      'Updating saved relation numbers…';

  @override
  String get relationNeighborhoodSavedSummaryStale =>
      'Saved relation numbers are out of date because the refresh failed.';

  @override
  String relationNeighborhoodTotal(int count) {
    return 'Total relations: $count';
  }

  @override
  String relationNeighborhoodActiveTotal(int count) {
    return 'Active relations: $count';
  }

  @override
  String relationNeighborhoodArchivedTotal(int count) {
    return 'Archived relations: $count';
  }

  @override
  String relationNeighborhoodNeedTotal(int count) {
    return 'Need: $count';
  }

  @override
  String relationNeighborhoodCanTotal(int count) {
    return 'Can: $count';
  }

  @override
  String relationNeighborhoodDailyTotal(int count) {
    return 'Daily choices: $count';
  }

  @override
  String get relationNeighborhoodDailySourceRole => 'Source intention';

  @override
  String get relationNeighborhoodDailySelectedRole => 'Selected action';

  @override
  String get relationNeighborhoodLongTermGroups => 'Long-term relations';

  @override
  String get relationNeighborhoodScopeLabel => 'Relation state';

  @override
  String get relationNeighborhoodScopeActive => 'Active relations';

  @override
  String get relationNeighborhoodScopeArchived => 'Archived relations';

  @override
  String get relationNeighborhoodTypeLabel => 'Relation type';

  @override
  String get relationNeighborhoodTypeNeed => 'Need';

  @override
  String get relationNeighborhoodTypeCan => 'Can';

  @override
  String get relationNeighborhoodDirectionLabel => 'Direction';

  @override
  String get relationNeighborhoodDirectionIncoming => 'Incoming';

  @override
  String get relationNeighborhoodDirectionOutgoing => 'Outgoing';

  @override
  String relationNeighborhoodSelectedGroupCount(int count) {
    return 'In the whole selected group: $count';
  }

  @override
  String get relationNeighborhoodInitialUnavailable =>
      'The relations and summary couldn’t be loaded. Try again.';

  @override
  String get relationNeighborhoodInitialCorruption =>
      'Stored relation data is damaged and can’t be shown.';

  @override
  String get relationNeighborhoodInitialUnexpected =>
      'The relations couldn’t be loaded because of an unexpected error.';

  @override
  String get relationNeighborhoodInitialInvalid =>
      'The selected relation group can no longer be opened.';

  @override
  String get relationNeighborhoodIntentionNotFound =>
      'The intention whose relations were being viewed no longer exists.';

  @override
  String get relationNeighborhoodEmpty =>
      'There are no relations in this group.';

  @override
  String get relationNeighborhoodLoadingMore => 'Loading more relations…';

  @override
  String get relationNeighborhoodLoadMoreUnavailable =>
      'The next relations couldn’t be loaded.';

  @override
  String get relationNeighborhoodLoadMoreCorruption =>
      'Stored data is damaged; the next relations can’t be shown.';

  @override
  String get relationNeighborhoodLoadMoreUnexpected =>
      'The next relations couldn’t be loaded because of an unexpected error.';

  @override
  String get relationNeighborhoodLoadMoreInvalid =>
      'The continuation for this group is no longer valid.';

  @override
  String get relationNeighborhoodRefreshing => 'Refreshing relations…';

  @override
  String get relationNeighborhoodRefreshFailed =>
      'The relations couldn’t be refreshed. Previously loaded data is still shown.';

  @override
  String get relationNeighborhoodConfirmedEnd =>
      'All relations in this group are loaded.';

  @override
  String get relationNeighborhoodRelationActive => 'Active relation';

  @override
  String get relationNeighborhoodRelationArchived => 'Archived relation';

  @override
  String relationNeighborhoodPriority(String priority) {
    return 'Priority $priority';
  }

  @override
  String get relationNeighborhoodSourceParticipant => 'Source intention';

  @override
  String get relationNeighborhoodRelatedParticipant => 'Related intention';

  @override
  String relationNeighborhoodNeedPhrase(String source, String related) {
    return 'To $source, you need $related';
  }

  @override
  String relationNeighborhoodCanPhrase(String source, String related) {
    return 'To $source, you can $related';
  }

  @override
  String get detailsTitle => 'Intention details';

  @override
  String get detailsLoading => 'Loading intention…';

  @override
  String get detailsNotFound => 'Intention not found.';

  @override
  String get detailsUnavailable =>
      'The intention couldn’t be loaded. Try again.';

  @override
  String get detailsCorruption =>
      'Stored intention data is damaged and can’t be shown.';

  @override
  String get detailsUnexpected =>
      'The intention couldn’t be loaded because of an unexpected error.';

  @override
  String get detailsOperationRunning => 'Saving changes…';

  @override
  String get detailsDescriptionLabel => 'Description';

  @override
  String get detailsNoDescription => 'No description';

  @override
  String get detailsReadinessLabel => 'Readiness';

  @override
  String get detailsArchiveStateLabel => 'State';

  @override
  String get detailsActive => 'Active';

  @override
  String get detailsArchived => 'Archived';

  @override
  String get detailsEditAction => 'Edit';

  @override
  String get detailsSaveAction => 'Save changes';

  @override
  String get detailsCancelEditAction => 'Cancel';

  @override
  String get detailsSaved => 'Changes saved.';

  @override
  String get detailsEnableReadinessAction => 'Mark as ready for action';

  @override
  String get detailsDisableReadinessAction => 'Mark as not ready for action';

  @override
  String get detailsReadinessConfirmationTitle => 'Ready for action?';

  @override
  String get detailsReadinessOneDayCriterion =>
      'It can be completed fully within one day.';

  @override
  String get detailsReadinessClarityCriterion =>
      'It is clear enough for a person to carry out.';

  @override
  String get detailsConfirmReadinessAction => 'Mark as ready';

  @override
  String get detailsArchiveAction => 'Archive';

  @override
  String get detailsRestoreAction => 'Restore';

  @override
  String get detailsDeleteAction => 'Delete permanently';

  @override
  String get detailsDeleteConfirmationTitle => 'Delete intention permanently?';

  @override
  String get detailsDeleteConfirmationMessage =>
      'This can’t be undone. The intention and its description will be permanently deleted.';

  @override
  String get detailsConfirmDeleteAction => 'Delete permanently';

  @override
  String get detailsDeleted => 'Intention deleted.';

  @override
  String get detailsReadinessEnabled => 'Marked as ready for action.';

  @override
  String get detailsReadinessDisabled => 'Marked as not ready for action.';

  @override
  String get detailsArchivedSuccess => 'Intention archived.';

  @override
  String get detailsRestoredSuccess => 'Intention restored.';

  @override
  String get detailsStateChangeInvalid =>
      'The intention state couldn’t be changed.';

  @override
  String get detailsStateChangeNotFound =>
      'The intention no longer exists. Its state wasn’t changed.';

  @override
  String get detailsStateChangeConflict =>
      'The intention changed elsewhere. Its state wasn’t changed.';

  @override
  String get detailsStateChangeUnavailable =>
      'The intention state couldn’t be changed. Try again.';

  @override
  String get detailsStateChangeCorruption =>
      'Stored data is damaged. The intention state wasn’t changed.';

  @override
  String get detailsStateChangeUnexpected =>
      'The intention state couldn’t be changed because of an unexpected error.';

  @override
  String get detailsDeleteInvalid => 'The intention couldn’t be deleted.';

  @override
  String get detailsDeleteNotFound =>
      'The intention no longer exists. It wasn’t deleted.';

  @override
  String get detailsDeleteConflict =>
      'The intention changed elsewhere. It wasn’t deleted.';

  @override
  String get detailsDeleteBlockedByRelations =>
      'The intention wasn’t deleted: its relations still block deletion. Archived relations and relations that aren’t loaded yet block it too.';

  @override
  String get detailsShowBlockingRelationsAction => 'Show blocking relations';

  @override
  String get detailsArchiveCascadeExplanation =>
      'Archiving also archives the intention’s direct relations. Neighbouring intentions and their other relations stay unchanged.';

  @override
  String detailsRestoreRelationsExplanation(int count) {
    return 'Restoring returns only the intention. Its relations stay archived: $count.';
  }

  @override
  String get detailsShowArchivedRelationsAction => 'Show archived relations';

  @override
  String get detailsDeleteUnavailable =>
      'The intention couldn’t be deleted. Try again.';

  @override
  String get detailsDeleteCorruption =>
      'Stored data is damaged. The intention wasn’t deleted.';

  @override
  String get detailsDeleteUnexpected =>
      'The intention couldn’t be deleted because of an unexpected error.';

  @override
  String get detailsUpdateInvalidInput => 'Check the entered data.';

  @override
  String get detailsUpdateNotFound =>
      'The intention no longer exists. Your changes weren’t saved.';

  @override
  String get detailsUpdateConflict =>
      'The intention changed elsewhere. Your changes weren’t saved.';

  @override
  String get detailsUpdateUnavailable =>
      'The changes couldn’t be saved. Try again.';

  @override
  String get detailsUpdateCorruption =>
      'Stored data is damaged. The changes weren’t saved.';

  @override
  String get detailsUpdateUnexpected =>
      'The changes couldn’t be saved because of an unexpected error.';

  @override
  String get editorTitle => 'Create intention';

  @override
  String get editorCreateAction => 'Create intention';

  @override
  String get editorCreating => 'Creating…';

  @override
  String get editorTitleLabel => 'Title';

  @override
  String get editorDescriptionLabel => 'Description (optional)';

  @override
  String get editorTitleEmpty => 'Enter a title.';

  @override
  String get editorTitleTooLong => 'Use no more than 255 characters.';

  @override
  String get editorTitleInvalidUnicode =>
      'Enter valid Unicode text without NUL.';

  @override
  String get editorDescriptionTooLong => 'Use no more than 4096 characters.';

  @override
  String get editorDescriptionInvalidUnicode =>
      'Enter valid Unicode text without NUL.';

  @override
  String get editorInvalidInput => 'Check the entered data.';

  @override
  String get editorCreateConflict =>
      'The intention couldn’t be created because of a conflict.';

  @override
  String get editorCreateUnavailable =>
      'The intention couldn’t be created. Try again.';

  @override
  String get editorCreateCorruption =>
      'Stored data is damaged. The intention wasn’t created.';

  @override
  String get editorCreateUnexpected =>
      'The intention couldn’t be created because of an unexpected error.';

  @override
  String get editorCreated => 'Intention created.';

  @override
  String get graphOperationCreate => 'Create';

  @override
  String get graphOperationUpdate => 'Edit';

  @override
  String get graphOperationEnableReadiness => 'Mark ready';

  @override
  String get graphOperationDisableReadiness => 'Mark not ready';

  @override
  String get graphOperationArchive => 'Archive';

  @override
  String get graphOperationRestore => 'Restore';

  @override
  String get graphOperationDelete => 'Delete';

  @override
  String get graphOperationDeleteBlockingRelations =>
      'Delete selected relations';

  @override
  String get blockingRelationsDeleted => 'Selected relations deleted.';

  @override
  String get blockingRelationsDeleteIntentionNotFound =>
      'This intention no longer exists. Relations weren’t deleted.';

  @override
  String get blockingRelationsDeleteConflict =>
      'The selected relations changed. Refresh the selection and confirm again.';

  @override
  String get blockingRelationsDeleteUnavailable =>
      'Selected relations couldn’t be deleted. Try again.';

  @override
  String get blockingRelationsDeleteCorruption =>
      'Stored data is damaged. Selected relations weren’t deleted.';

  @override
  String get blockingRelationsDeleteUnexpected =>
      'Selected relations couldn’t be deleted because of an unexpected error.';

  @override
  String get graphOperationNewIntention => 'new intention';

  @override
  String get graphOperationIntention => 'intention';

  @override
  String graphOperationMessage(
    String operation,
    String target,
    String outcome,
  ) {
    return '$operation — “$target”: $outcome';
  }

  @override
  String get graphOperationNewRelation => 'new relation';

  @override
  String get graphOperationRelation => 'relation';

  @override
  String get graphOperationDailyChoice => 'daily choice';

  @override
  String get dailyChoiceCreated => 'Daily choice created.';

  @override
  String get dailyChoiceUpdated => 'Daily choice updated.';

  @override
  String get dailyChoicePathReplaced => 'Daily choice path replaced.';

  @override
  String get dailyChoiceDeleted => 'Daily choice deleted.';

  @override
  String get dailyChoiceDeleteAction => 'Delete daily choice permanently';

  @override
  String get dailyChoiceDeleteConfirmationTitle =>
      'Delete daily choice permanently?';

  @override
  String dailyChoiceDeleteConfirmationMessage(
    String phrase,
    String date,
    String choiceId,
  ) {
    return 'Choice: $phrase\nDate: $date\nChoice ID: $choiceId\n\nThis cannot be undone. Intentions, long-term relations, and other daily choices will remain.';
  }

  @override
  String get dailyChoiceDeleteConfirmAction => 'Delete permanently';

  @override
  String get dailyChoiceSourceInvalid =>
      'Check the source intention of the daily choice.';

  @override
  String get dailyChoiceSelectedInvalid =>
      'Check the selected intention of the daily choice.';

  @override
  String get dailyChoiceDateInvalid => 'Check the daily choice date.';

  @override
  String get dailyChoiceDescriptionInvalid =>
      'Check the daily choice description.';

  @override
  String get dailyChoicePathInvalid => 'Check the daily choice path.';

  @override
  String get dailyChoiceOperationNotFound =>
      'This daily choice no longer exists.';

  @override
  String get dailyChoiceOperationConflict =>
      'The data changed. Refresh it and confirm again.';

  @override
  String get dailyChoiceOperationUnavailable =>
      'Could not complete the daily choice operation. Try again.';

  @override
  String get dailyChoiceOperationCorruption =>
      'Stored data is damaged. The daily choice was not changed.';

  @override
  String get dailyChoiceOperationUnexpected =>
      'The daily choice operation failed because of an unexpected error.';

  @override
  String get relationEditorCreated => 'Relation created.';

  @override
  String get relationEditorCreateInvalidInput =>
      'Check the selected intentions and relation details.';

  @override
  String get relationEditorCreatePairOccupied =>
      'A relation with this direction already exists between the selected intentions.';

  @override
  String get relationEditorCreateParticipantNotFound =>
      'One of the selected intentions no longer exists.';

  @override
  String get relationEditorCreateParticipantArchived =>
      'Only active intentions can be linked.';

  @override
  String get relationEditorCreateUnavailable =>
      'The relation couldn’t be created. Try again.';

  @override
  String get relationEditorCreateCorruption =>
      'Stored data is damaged. The relation wasn’t created.';

  @override
  String get relationEditorCreateUnexpected =>
      'The relation couldn’t be created because of an unexpected error.';

  @override
  String get relationEditorUpdated => 'Relation updated.';

  @override
  String get relationEditorUpdateInvalidInput =>
      'Check the selected intentions and relation changes.';

  @override
  String get relationEditorUpdatePairOccupied =>
      'A relation with this direction already exists between the selected intentions.';

  @override
  String get relationEditorUpdateNotFound => 'This relation no longer exists.';

  @override
  String get relationEditorUpdateParticipantNotFound =>
      'One of the selected intentions no longer exists.';

  @override
  String get relationEditorUpdateParticipantArchived =>
      'An active relation can only link active intentions.';

  @override
  String get relationEditorUpdateReferencedByDailyPath =>
      'This relation is used by a saved daily path. Its type and participants can’t be changed.';

  @override
  String get relationEditorPathProtection =>
      'This relation is used in a saved daily path. Its type and participants cannot be changed. Its description and priority remain editable.';

  @override
  String get relationEditorPathProtectionWithDraft =>
      'This relation is used in a saved daily path. Restore the original type and participants to save description and priority changes.';

  @override
  String get relationEditorUpdateUnavailable =>
      'The relation couldn’t be updated. Try again.';

  @override
  String get relationEditorUpdateCorruption =>
      'Stored data is damaged. The relation wasn’t updated.';

  @override
  String get relationEditorUpdateUnexpected =>
      'The relation couldn’t be updated because of an unexpected error.';

  @override
  String get relationArchived => 'Relation archived.';

  @override
  String get relationArchiveNotFound => 'This relation no longer exists.';

  @override
  String get relationArchiveConflict =>
      'The relation couldn’t be archived because its current state conflicts with the operation.';

  @override
  String get relationArchiveUnavailable =>
      'The relation couldn’t be archived. Try again.';

  @override
  String get relationArchiveCorruption =>
      'Stored data is damaged. The relation wasn’t archived.';

  @override
  String get relationArchiveUnexpected =>
      'The relation couldn’t be archived because of an unexpected error.';

  @override
  String get relationRestored => 'Relation restored.';

  @override
  String get relationRestoreNotFound => 'This relation no longer exists.';

  @override
  String get relationRestoreConflict =>
      'The relation couldn’t be restored because its current state conflicts with the operation.';

  @override
  String get relationRestoreSourceNotFound =>
      'The source intention no longer exists. The relation wasn’t restored.';

  @override
  String get relationRestoreRelatedNotFound =>
      'The related intention no longer exists. The relation wasn’t restored.';

  @override
  String get relationRestoreSourceArchived =>
      'Restore the source intention before restoring this relation.';

  @override
  String get relationRestoreRelatedArchived =>
      'Restore the related intention before restoring this relation.';

  @override
  String get relationRestoreUnavailable =>
      'The relation couldn’t be restored. Try again.';

  @override
  String get relationRestoreCorruption =>
      'Stored data is damaged. The relation wasn’t restored.';

  @override
  String get relationRestoreUnexpected =>
      'The relation couldn’t be restored because of an unexpected error.';

  @override
  String get relationDeleted => 'Relation deleted.';

  @override
  String get relationDeleteNotFound => 'This relation no longer exists.';

  @override
  String get relationDeleteConflict =>
      'The relation couldn’t be deleted because its current state conflicts with the operation.';

  @override
  String get relationDeleteReferencedByDailyPath =>
      'This relation is used by a saved daily path. Delete or replace the daily choices that use it first.';

  @override
  String get relationDeleteUnavailable =>
      'The relation couldn’t be deleted. Try again.';

  @override
  String get relationDeleteCorruption =>
      'Stored data is damaged. The relation wasn’t deleted.';

  @override
  String get relationDeleteUnexpected =>
      'The relation couldn’t be deleted because of an unexpected error.';

  @override
  String get relationNeighborhoodOpenRelation => 'Opens the relation details';

  @override
  String get relationNeighborhoodOpenDailyChoice =>
      'Open the full saved daily path';

  @override
  String get relationDetailsTitle => 'Relation';

  @override
  String get relationDetailsLoading => 'Loading the relation…';

  @override
  String get relationDetailsNotFound => 'This relation no longer exists.';

  @override
  String get relationDetailsUnavailable =>
      'The relation couldn’t be loaded. Try again.';

  @override
  String get relationDetailsCorruption =>
      'Stored relation data is damaged and can’t be shown.';

  @override
  String get relationDetailsUnexpected =>
      'The relation couldn’t be loaded because of an unexpected error.';

  @override
  String get relationDetailsRefreshing => 'Refreshing relation details…';

  @override
  String get relationDetailsRefreshUnavailable =>
      'The relation details couldn’t be refreshed. Previously confirmed data is still shown.';

  @override
  String get relationDetailsRefreshCorruption =>
      'Stored data is damaged. Previously confirmed relation details are still shown.';

  @override
  String get relationDetailsRefreshUnexpected =>
      'The relation details couldn’t be refreshed because of an unexpected error. Previously confirmed data is still shown.';

  @override
  String get relationDetailsTypeLabel => 'Relation type';

  @override
  String get relationDetailsPriorityLabel => 'Priority';

  @override
  String get relationDetailsScopeLabel => 'Relation state';

  @override
  String get relationDetailsDescriptionLabel => 'Description';

  @override
  String get relationDetailsNoDescription => 'No description';

  @override
  String get relationDetailsOpenParticipant =>
      'Opens the intention and its own relations';

  @override
  String get relationDetailsEditAction => 'Edit relation';

  @override
  String get relationDetailsArchiveAction => 'Archive relation';

  @override
  String get relationDetailsRestoreAction => 'Restore relation';

  @override
  String get relationDetailsDeleteAction => 'Delete relation permanently';

  @override
  String get relationDetailsPathProtection =>
      'This relation is used in a saved daily path. It cannot be deleted, and its type and participants cannot be changed. Its description, priority, and archive state remain editable.';

  @override
  String get relationDetailsDeletionChecking =>
      'Deletion is unavailable until this relation’s dependencies are confirmed.';

  @override
  String get relationDetailsDeleteConfirmationTitle =>
      'Delete relation permanently?';

  @override
  String relationDetailsDeleteConfirmationMessage(
    String phrase,
    String sourceTitle,
    String relatedTitle,
    String scope,
  ) {
    return 'Relation: $phrase\nSource intention: $sourceTitle\nRelated intention: $relatedTitle\nRelation state: $scope\n\nThis can’t be undone. Both intentions and all other relations will remain.';
  }

  @override
  String get relationDetailsConfirmDeleteAction => 'Delete permanently';

  @override
  String get relationDetailsOpenSourceParticipantAction =>
      'Open source intention';

  @override
  String get relationDetailsOpenRelatedParticipantAction =>
      'Open related intention';

  @override
  String get participantPickerTitle => 'Select a participant';

  @override
  String get actionPickerTitle => 'Select an action';

  @override
  String get actionPickerCancel => 'Cancel action selection';

  @override
  String get actionPickerLoading => 'Loading actions…';

  @override
  String get actionPickerEmpty => 'No active actions are available.';

  @override
  String get actionPickerNoMatches => 'No actions match this title.';

  @override
  String get actionPickerUnavailable =>
      'Actions couldn’t be loaded. Try again.';

  @override
  String get actionPickerCorruption =>
      'Saved action data is damaged and can’t be shown.';

  @override
  String get actionPickerUnexpected =>
      'Actions couldn’t be loaded because of an unexpected error.';

  @override
  String get actionPickerSelectHint => 'Selects this action to find its reason';

  @override
  String get actionPickerOpenDetails => 'Open action details';

  @override
  String actionPickerTotalCount(int count) {
    return 'Total actions: $count';
  }

  @override
  String get sourcePickerTitle => 'Select a reason';

  @override
  String get sourcePickerCancel => 'Cancel reason selection';

  @override
  String get sourcePickerLoading => 'Loading intentions…';

  @override
  String get sourcePickerEmpty => 'No active intentions are available.';

  @override
  String get sourcePickerNoMatches => 'No intentions match this title.';

  @override
  String get sourcePickerUnavailable =>
      'Intentions couldn’t be loaded. Try again.';

  @override
  String get sourcePickerCorruption =>
      'Saved intention data is damaged and can’t be shown.';

  @override
  String get sourcePickerUnexpected =>
      'Intentions couldn’t be loaded because of an unexpected error.';

  @override
  String get sourcePickerSelectHint =>
      'Selects this intention as the new reason';

  @override
  String get sourcePickerOpenDetails => 'Open intention details';

  @override
  String sourcePickerTotalCount(int count) {
    return 'Total intentions: $count';
  }

  @override
  String get participantPickerCancel => 'Cancel the selection';

  @override
  String get participantPickerEmpty =>
      'No other intentions are available to select.';

  @override
  String get participantPickerSelectHint =>
      'Selects this intention as a relation participant';

  @override
  String get participantPickerOpenDetails => 'Open intention details';

  @override
  String get relationEditorTitle => 'New relation';

  @override
  String get relationEditorEditTitle => 'Edit relation';

  @override
  String get relationEditorPhraseLabel => 'Relation phrase';

  @override
  String get relationEditorSourceLabel => 'Source intention';

  @override
  String get relationEditorRelatedLabel => 'Related intention';

  @override
  String get relationEditorParticipantSelected => 'Selected';

  @override
  String get relationEditorParticipantNotSelected => 'Not selected';

  @override
  String get relationEditorSelectSourceAction => 'Select the source intention';

  @override
  String get relationEditorChangeSourceAction => 'Change the source intention';

  @override
  String get relationEditorSelectRelatedAction =>
      'Select the related intention';

  @override
  String get relationEditorChangeRelatedAction =>
      'Change the related intention';

  @override
  String get relationEditorTypeLabel => 'Relation type';

  @override
  String get relationEditorTypeNeed => 'Need';

  @override
  String get relationEditorTypeCan => 'Can';

  @override
  String get relationEditorPriorityLabel => 'Priority';

  @override
  String get relationEditorDescriptionLabel => 'Description (optional)';

  @override
  String get relationEditorDescriptionTooLong =>
      'Use no more than 4096 characters.';

  @override
  String get relationEditorDescriptionInvalidUnicode =>
      'Enter valid Unicode text without NUL.';

  @override
  String get relationEditorCreateSameParticipants =>
      'An intention can’t be related to itself.';

  @override
  String get relationEditorMissingTitle => 'To create the relation, provide:';

  @override
  String get relationEditorMissingSource => 'the source intention';

  @override
  String get relationEditorMissingRelated => 'the related intention';

  @override
  String get relationEditorMissingType => 'the relation type';

  @override
  String get relationEditorMissingPriority => 'a priority from P1 to P4';

  @override
  String get relationEditorOpenExistingRelation => 'Open the existing relation';

  @override
  String get relationEditorSubmitAction => 'Create relation';

  @override
  String get relationEditorCreating => 'Creating…';

  @override
  String get relationEditorSaveAction => 'Save changes';

  @override
  String get relationEditorSaving => 'Saving…';

  @override
  String get relationNeighborhoodCreateOutgoingAction =>
      'Create an outgoing relation';

  @override
  String get relationNeighborhoodCreateIncomingAction =>
      'Create an incoming relation';

  @override
  String relationEditorPriorityOption(String priority) {
    return 'Priority $priority';
  }

  @override
  String get detailsChoosePathAction => 'Choose an action along a path';

  @override
  String get choicePathTitle => 'Choose a path to an action';

  @override
  String get choicePathBottomTitle => 'Choose a source for the action';

  @override
  String get choicePathBottomTraversal =>
      'Exploration: from the action to a source';

  @override
  String get choicePathBottomPathDirection =>
      'Relation direction: from the source to the action';

  @override
  String choicePathFixedAction(String action) {
    return 'Selected action: $action';
  }

  @override
  String get choicePathActionPending => 'Loading the selected action…';

  @override
  String choicePathCurrentSource(String source) {
    return 'Source: $source';
  }

  @override
  String get choicePathSourceSelected => 'Source confirmed';

  @override
  String choicePathSelectSource(String source) {
    return 'Confirm source “$source”';
  }

  @override
  String get choicePathBottomNoPath =>
      'There are no valid incoming relations for this action right now. Choose another action.';

  @override
  String get choicePathDirection =>
      'Path from the source intention to an action';

  @override
  String choicePathSource(String source) {
    return 'Source intention: $source';
  }

  @override
  String get choicePathSourcePending => 'Loading the source intention…';

  @override
  String choicePathReturnTo(String source) {
    return 'Return to “$source”';
  }

  @override
  String choicePathStepSemantics(int index, String phrase, String priority) {
    return 'Step $index: $phrase. Priority $priority';
  }

  @override
  String get choicePathActionSelected => 'Action selected';

  @override
  String choicePathSelectAction(String action) {
    return 'Choose action “$action”';
  }

  @override
  String get choicePathSelectionNotSaved =>
      'The daily choice has not been created yet.';

  @override
  String get choicePathContinuations => 'Available continuations';

  @override
  String get choicePathLoading => 'Checking available continuations…';

  @override
  String get choicePathNoPath =>
      'There is no valid path from this intention to another action right now.';

  @override
  String get choicePathNoFurtherPath =>
      'There are no further valid continuations.';

  @override
  String get choicePathConflict =>
      'The graph has changed. Refresh the path before continuing.';

  @override
  String get choicePathRefresh => 'Refresh path';

  @override
  String get choicePathNotFound =>
      'An intention on this path no longer exists.';

  @override
  String get choicePathInvalid =>
      'Continuations could not be checked because of an invalid request.';

  @override
  String get choicePathUnavailable =>
      'Continuations are temporarily unavailable. Try again.';

  @override
  String get choicePathCorruption =>
      'Saved path data is damaged. Continuation is unavailable.';

  @override
  String get choicePathUnexpected =>
      'Continuations could not be checked because of an unexpected error.';

  @override
  String get choicePathLoadMore => 'Show more continuations';

  @override
  String get choicePathLoadingMore => 'Loading the next page…';

  @override
  String choicePathContinueSemantics(String phrase, String priority) {
    return 'Continue along relation: $phrase. Priority $priority';
  }

  @override
  String get dailyChoiceCreationTitle => 'Confirm daily choice';

  @override
  String get dailyChoiceCatalogTitle => 'Daily choices';

  @override
  String get dailyChoiceCreateFromAction => 'Create a choice from an action';

  @override
  String get dailyChoiceCatalogLoading => 'Loading daily choices…';

  @override
  String get dailyChoiceCatalogDateFilter => 'Date';

  @override
  String get dailyChoiceCatalogApplyDate => 'Apply date';

  @override
  String get dailyChoiceCatalogDateInvalid =>
      'Enter a valid date as YYYY-MM-DD.';

  @override
  String get dailyChoiceCatalogCompletionFilter => 'Completion';

  @override
  String get dailyChoiceCatalogAllStates => 'All states';

  @override
  String get dailyChoiceCatalogIncomplete => 'Not completed';

  @override
  String get dailyChoiceCatalogCompleted => 'Completed';

  @override
  String get dailyChoiceCatalogClearFilters => 'Clear filters';

  @override
  String dailyChoiceCatalogTotalCount(int count) {
    return 'Total daily choices: $count';
  }

  @override
  String get dailyChoiceCatalogEmpty => 'No daily choices match the filters.';

  @override
  String get dailyChoiceCatalogRefreshing => 'Refreshing daily choices…';

  @override
  String get dailyChoiceCatalogLoadingMore => 'Loading more daily choices…';

  @override
  String get dailyChoiceCatalogLoadMore => 'Show more daily choices';

  @override
  String get dailyChoiceCatalogUnavailable =>
      'Could not load daily choices. Try again.';

  @override
  String get dailyChoiceCatalogCorruption =>
      'Stored daily choice data is damaged and cannot be shown.';

  @override
  String get dailyChoiceCatalogExpired =>
      'The catalog changed. Refresh it to continue.';

  @override
  String get dailyChoiceCatalogInvalid =>
      'The catalog position is no longer valid.';

  @override
  String get dailyChoiceCatalogUnexpected =>
      'Could not load daily choices because of an unexpected error.';

  @override
  String dailyChoiceCatalogRowLabel(
    int number,
    String phrase,
    String date,
    String completion,
  ) {
    return 'Choice #$number. $phrase. $date. $completion';
  }

  @override
  String get dailyChoiceDetailsTitle => 'Daily choice';

  @override
  String get dailyChoiceEditTitle => 'Edit daily choice';

  @override
  String get dailyChoiceEditSave => 'Save changes';

  @override
  String get dailyChoiceEditRefresh => 'Return to details and refresh';

  @override
  String get dailyChoiceDetailsLoading => 'Loading daily choice…';

  @override
  String get dailyChoiceDetailsNotFound =>
      'This daily choice no longer exists.';

  @override
  String get dailyChoiceDetailsUnavailable =>
      'Could not load this daily choice. Try again.';

  @override
  String get dailyChoiceDetailsCorruption =>
      'The stored path is damaged and cannot be shown.';

  @override
  String get dailyChoiceDetailsUnexpected =>
      'Could not load this daily choice because of an unexpected error.';

  @override
  String dailyChoiceDetailsPhrase(String source, String selected) {
    return 'To $source, today I $selected';
  }

  @override
  String dailyChoiceDetailsDate(String date) {
    return 'Daily choice date: $date';
  }

  @override
  String get dailyChoiceDetailsCompleted => 'Completed';

  @override
  String get dailyChoiceDetailsNotCompleted => 'Not completed';

  @override
  String get dailyChoiceDetailsDescription => 'Description';

  @override
  String get dailyChoiceDetailsPath => 'Stored path';

  @override
  String get dailyChoiceDetailsSource => 'Source intention';

  @override
  String get dailyChoiceDetailsIntermediate => 'Intermediate intention';

  @override
  String get dailyChoiceDetailsSelectedAction => 'Selected action';

  @override
  String get dailyChoiceDetailsArchived => 'Archived';

  @override
  String get dailyChoiceDetailsActive => 'Active';

  @override
  String get dailyChoiceDetailsReady => 'Ready for action';

  @override
  String get dailyChoiceDetailsNotReady => 'Not ready for action';

  @override
  String dailyChoiceDetailsStep(int number) {
    return 'Transition $number';
  }

  @override
  String get dailyChoiceCreationPath => 'Path to confirm';

  @override
  String dailyChoiceCreationAction(String action) {
    return 'Selected action: $action';
  }

  @override
  String get dailyChoiceCreationDate => 'Daily choice date';

  @override
  String get dailyChoiceCreationDateHint => 'Enter YYYY-MM-DD (0001–9999)';

  @override
  String get dailyChoiceCreationDescription => 'Description (optional)';

  @override
  String get dailyChoiceCreationCompleted => 'Already completed';

  @override
  String get dailyChoiceCreationCompletedHint =>
      'Mark if the action was already done for this date';

  @override
  String get dailyChoiceCreationSave => 'Save daily choice';

  @override
  String get dailyChoiceCreationSaving => 'Saving…';

  @override
  String get dailyChoiceCreationCancel => 'Cancel';

  @override
  String get dailyChoiceCreationRefreshPath =>
      'Return to the path and refresh it';

  @override
  String get dailyChoiceReplaceTitle => 'Confirm path replacement';

  @override
  String get dailyChoiceReplacePreparing =>
      'Preparing the new path confirmation…';

  @override
  String get dailyChoiceReplaceCurrent => 'Daily choice to replace';

  @override
  String get dailyChoiceReplaceNewPath => 'New path from source to action';

  @override
  String get dailyChoiceReplaceNoDescription => 'No description';

  @override
  String get dailyChoiceReplaceFieldsPreserved =>
      'The date, description, and completion will stay unchanged when the path is replaced.';

  @override
  String get dailyChoiceReplaceCompletionPreserved =>
      'Completion stays on even if a different action is selected.';

  @override
  String get dailyChoiceReplaceConfirm => 'Replace path only';

  @override
  String get dailyChoiceReplaceSubmitting => 'Replacing path…';

  @override
  String get dailyChoiceReplaceChooseAgain => 'Return to path selection';

  @override
  String get choicePathOpenConfirmation => 'Continue to choice confirmation';

  @override
  String get choiceSuggestionTitle => 'Previous routes';

  @override
  String get choiceSuggestionLoading => 'Loading previous route suggestions…';

  @override
  String get choiceSuggestionEmpty =>
      'No previous routes for this participant.';

  @override
  String get choiceSuggestionUpdating =>
      'Refreshing suggestions. Route selection is temporarily unavailable.';

  @override
  String get choiceSuggestionNotFound =>
      'The selected intention no longer exists.';

  @override
  String get choiceSuggestionUnavailable =>
      'Couldn’t load suggestions. Try again.';

  @override
  String get choiceSuggestionCorruption =>
      'Stored suggestion data is damaged and can’t be confirmed.';

  @override
  String get choiceSuggestionUnexpected =>
      'Couldn’t load suggestions because of an unexpected error.';

  @override
  String choiceSuggestionPosition(int index, int total) {
    return 'Suggestion $index of $total';
  }

  @override
  String choiceSuggestionSource(String source) {
    return 'Source: $source';
  }

  @override
  String choiceSuggestionAction(String action) {
    return 'Selected action: $action';
  }

  @override
  String get choiceSuggestionView => 'View full route';

  @override
  String get choiceSuggestionSelect => 'Select route';

  @override
  String get choiceSuggestionArchivedIntention =>
      'Route unavailable: an intention is archived.';

  @override
  String get choiceSuggestionArchivedRelation =>
      'Route unavailable: a relation in the route is archived.';

  @override
  String get choiceSuggestionActionNotReady =>
      'Route unavailable: the final action is no longer ready for action.';

  @override
  String get choiceSuggestionPreviewTitle => 'Full route';

  @override
  String get choiceSuggestionDirection =>
      'Route direction: from source to action';

  @override
  String choiceSuggestionStep(int index, int total) {
    return 'Step $index of $total';
  }
}
