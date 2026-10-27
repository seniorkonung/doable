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
  String get appDestinationHome => 'Home';

  @override
  String get appDestinationDailyChoices => 'Daily choices';

  @override
  String get appDestinationIntentionGraph => 'Intention graph';

  @override
  String get statisticsSourceIntentions => 'Source intentions';

  @override
  String get statisticsIntermediateIntentions => 'Intermediate intentions';

  @override
  String get statisticsSelectedActions => 'Selected actions';

  @override
  String get statisticsThroughRelations => 'Total contribution';

  @override
  String get statisticsMonthTab => 'Month';

  @override
  String get statisticsYearTab => 'Year';

  @override
  String statisticsMonthPeriod(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMM(localeName);
    final String dateString = dateDateFormat.format(date);

    return '$dateString';
  }

  @override
  String statisticsYearPeriod(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.y(localeName);
    final String dateString = dateDateFormat.format(date);

    return '$dateString';
  }

  @override
  String statisticsMonthName(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.MMMM(localeName);
    final String dateString = dateDateFormat.format(date);

    return '$dateString';
  }

  @override
  String get statisticsPreviousMonth => 'Previous month';

  @override
  String get statisticsNextMonth => 'Next month';

  @override
  String get statisticsPreviousYear => 'Previous year';

  @override
  String get statisticsNextYear => 'Next year';

  @override
  String get statisticsExpandPeriodSelector => 'Expand period selection';

  @override
  String get statisticsCollapsePeriodSelector => 'Collapse period selection';

  @override
  String get statisticsCurrentPeriod => 'Current period';

  @override
  String get statisticsPeriodSummary => 'Period summary';

  @override
  String get statisticsViewLabel => 'Statistics view';

  @override
  String statisticsTotalItems(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString items',
      one: '$countString item',
    );
    return '$_temp0';
  }

  @override
  String statisticsPlannedContribution(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'Planned contribution: $countString';
  }

  @override
  String statisticsContribution(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'Contribution: $countString';
  }

  @override
  String statisticsMissed(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'Missed: $countString';
  }

  @override
  String statisticsUpcoming(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'Upcoming: $countString';
  }

  @override
  String statisticsContributionCounts(int contribution, int planned) {
    final intl.NumberFormat contributionNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String contributionString = contributionNumberFormat.format(
      contribution,
    );
    final intl.NumberFormat plannedNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String plannedString = plannedNumberFormat.format(planned);

    return '$contributionString of $plannedString';
  }

  @override
  String statisticsContributionCountsSemantics(int contribution, int planned) {
    final intl.NumberFormat contributionNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String contributionString = contributionNumberFormat.format(
      contribution,
    );
    final intl.NumberFormat plannedNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String plannedString = plannedNumberFormat.format(planned);

    return 'Contribution: $contributionString. Planned contribution: $plannedString';
  }

  @override
  String statisticsContributionShare(num share) {
    final intl.NumberFormat shareNumberFormat =
        intl.NumberFormat.percentPattern(localeName);
    final String shareString = shareNumberFormat.format(share);

    return 'Share of the period’s contribution: $shareString';
  }

  @override
  String get statisticsNoContributionShare =>
      'No share: the period’s contribution is zero';

  @override
  String get statisticsLoading => 'Loading statistics…';

  @override
  String get statisticsEmpty =>
      'No daily choices are credited to this view for the selected period.';

  @override
  String get statisticsRefreshing => 'Updating statistics…';

  @override
  String get statisticsLoadingMore => 'Loading more items…';

  @override
  String get statisticsUnavailable => 'Could not load statistics. Try again.';

  @override
  String get statisticsCorruption =>
      'Stored data is damaged. Statistics cannot be shown.';

  @override
  String get statisticsUnexpectedFailure =>
      'Could not load statistics because of an unexpected error.';

  @override
  String get statisticsRefreshUnavailable =>
      'Statistics are out of date: changes could not be loaded. Try again.';

  @override
  String get statisticsRefreshCorruption =>
      'Statistics are out of date: stored data is damaged.';

  @override
  String get statisticsRefreshUnexpectedFailure =>
      'Statistics are out of date because of an unexpected error.';

  @override
  String get statisticsLoadMoreUnavailable =>
      'Could not load more items. Try again.';

  @override
  String get statisticsLoadMoreCorruption =>
      'More items cannot be shown: stored data is damaged.';

  @override
  String get statisticsLoadMoreUnexpectedFailure =>
      'Could not load more items because of an unexpected error.';

  @override
  String get statisticsSectionTitle => 'Statistics';

  @override
  String get statisticsBreakdownSourceIntentions => 'By source intentions';

  @override
  String get statisticsBreakdownSelectedActions => 'By selected actions';

  @override
  String get statisticsBreakdownRelations => 'By relations';

  @override
  String statisticsExplicitPathChoices(int count, int planned) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);
    final intl.NumberFormat plannedNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String plannedString = plannedNumberFormat.format(planned);

    return 'Daily choices with this intention on the saved selection path: $countString of $plannedString';
  }

  @override
  String statisticsBreakdownContributionShare(num share) {
    final intl.NumberFormat shareNumberFormat =
        intl.NumberFormat.percentPattern(localeName);
    final String shareString = shareNumberFormat.format(share);

    return 'Share of this intention’s contribution in this view: $shareString';
  }

  @override
  String get statisticsBreakdownNoContributionShare =>
      'No share: this intention’s contribution in this view is zero';

  @override
  String get statisticsRefreshUnavailableShort => 'Update unavailable.';

  @override
  String get statisticsRefreshCorruptionShort => 'Damaged data.';

  @override
  String get statisticsRefreshUnexpectedShort => 'Update error.';

  @override
  String get statisticsCalendarDayAllCompleted =>
      'All credited daily choices are completed';

  @override
  String get statisticsCalendarDayHasIncomplete =>
      'There is an incomplete credited daily choice';

  @override
  String get statisticsCalendarDayNoChoices => 'No credited daily choices';

  @override
  String statisticsCalendarDaySemantics(DateTime date, String dayStatus) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMMEEEEd(
      localeName,
    );
    final String dateString = dateDateFormat.format(date);

    return '$dateString. $dayStatus';
  }

  @override
  String statisticsMonthBarSemantics(DateTime month, String counts) {
    final intl.DateFormat monthDateFormat = intl.DateFormat.yMMMM(localeName);
    final String monthString = monthDateFormat.format(month);

    return '$monthString. $counts';
  }

  @override
  String statisticsViewCardSemantics(
    String view,
    String period,
    String counts,
  ) {
    return '$view. $period. $counts';
  }

  @override
  String get quickCreationLabel => 'Quick create';

  @override
  String get quickCreationChangeMode => 'Change mode';

  @override
  String get quickCreationMenuTitle => 'What the button creates';

  @override
  String get quickCreationMenuPrompt =>
      'A tap on plus will create the selected item';

  @override
  String get quickCreationLongPressHint => 'Touch and hold to change mode';

  @override
  String get quickCreationModeIntention => 'New intention';

  @override
  String get quickCreationModeIntentionHint =>
      'Something you want to do or change';

  @override
  String get quickCreationModeRelation => 'New relation';

  @override
  String get quickCreationModeRelationHint => 'To …, you need or can …';

  @override
  String get quickCreationModeDailyChoice => 'New daily choice';

  @override
  String get quickCreationModeDailyChoiceHint =>
      'An action for an intention on a chosen day';

  @override
  String get quickCreationDailyChoiceStartPrompt => 'Choose where to start';

  @override
  String get quickCreationDailyChoiceFromIntention => 'From an intention';

  @override
  String get quickCreationDailyChoiceFromIntentionHint =>
      'Pick an intention, then an action for it';

  @override
  String get quickCreationDailyChoiceFromAction => 'From an action';

  @override
  String get quickCreationDailyChoiceFromActionHint =>
      'Pick an action, then the intention it serves';

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
  String get catalogTagConditionsEmpty =>
      'No intentions match the tag conditions.';

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
  String get catalogReady => 'Ready for action';

  @override
  String get catalogNotReady => 'Not ready for action';

  @override
  String get catalogHasDescription => 'Has description';

  @override
  String get catalogNoDescription => 'No description';

  @override
  String intentionSummaryTags(String tags) {
    return 'Tags: $tags';
  }

  @override
  String get intentionSummaryNoTags => 'No tags';

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
      'Review each selected relation. Only the selected relations will be deleted. Selected daily choices will be deleted with all their path steps. This cannot be undone. The intention will remain; deleting it requires a separate confirmation.';

  @override
  String get blockingRelationsConfirmationPreservedTags =>
      'The reusable tags and all their assignments to intentions will remain.';

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
      'This can’t be undone. The intention, its description, and all its tag assignments, including those not shown here, will be permanently deleted. The tags will remain.';

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
  String get editorSaveAction => 'Save';

  @override
  String get editorSaving => 'Saving…';

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
  String get editorCloseDiscardTitle => 'Discard the draft?';

  @override
  String get editorCloseDiscardMessage =>
      'The new intention’s entered data hasn’t been saved and will be lost.';

  @override
  String get editorCloseContinueAction => 'Keep editing';

  @override
  String get editorCloseDiscardAction => 'Discard';

  @override
  String get editorCloseSavingTitle => 'Close the form?';

  @override
  String get editorCloseSavingMessage =>
      'Saving is already in progress and will continue after the form closes. If saving fails, the entered data won’t be restored.';

  @override
  String get editorCloseSavingStayAction => 'Stay';

  @override
  String get editorCloseSavingLeaveAction => 'Close';

  @override
  String get editorCloseFormAction => 'Close the form';

  @override
  String get editorReadinessOption => 'Create as ready for action';

  @override
  String get editorReadinessOptionOn => 'Create as ready for action: on';

  @override
  String get editorReadinessOptionOff => 'Create as ready for action: off';

  @override
  String get editorReadinessConfirmationTitle => 'Create as ready for action?';

  @override
  String get editorReadinessOneDayCriterion =>
      'It can be completed fully within one day.';

  @override
  String get editorReadinessClarityCriterion =>
      'It is clear enough for a person to carry out.';

  @override
  String get editorReadinessCancelAction => 'Cancel';

  @override
  String get editorReadinessConfirmAction => 'Mark as ready';

  @override
  String get editorChooseTags => 'Choose tags';

  @override
  String editorRemoveDraftTag(String tagName) {
    return 'Remove tag $tagName from draft';
  }

  @override
  String get editorDraftTagChecking => 'Checking tag';

  @override
  String get editorDraftTagReadUnavailable => 'Couldn\'t check tag';

  @override
  String get editorDraftTagReadCorruption => 'Tag data is corrupted';

  @override
  String get editorDraftTagReadUnexpected =>
      'Tag not checked due to an unexpected error';

  @override
  String editorRetryDraftTag(String tagName) {
    return 'Check tag $tagName again';
  }

  @override
  String editorCreateTagsMissing(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count selected tags were deleted from the catalog and removed from the draft. Save the intention again.',
      one: 'A selected tag was deleted from the catalog and removed from the draft. Save the intention again.',
    );
    return '$_temp0';
  }

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
  String graphOperationMessageWithOthers(String message, int count) {
    return '$message · $count more';
  }

  @override
  String get graphOperationNewRelation => 'new relation';

  @override
  String get graphOperationRelation => 'relation';

  @override
  String get graphOperationDailyChoice => 'daily choice';

  @override
  String get graphOperationTag => 'tag';

  @override
  String get graphOperationMoveTag => 'Move';

  @override
  String get graphOperationAssignTag => 'Assign';

  @override
  String get graphOperationRemoveTagAssignment => 'Remove';

  @override
  String get graphOperationTagAssignment => 'tag assignment';

  @override
  String get dataExportSaved => 'Data saved to a file';

  @override
  String get dataExportFailed => 'Couldn’t save the file';

  @override
  String get dataExportExistingFile =>
      'That file already exists. Save the copy under a new name';

  @override
  String get dataBackupRestored => 'Copy restored';

  @override
  String get dataBackupRestoreFailed =>
      'Couldn’t restore the copy. Nothing was changed';

  @override
  String get dataReplacementStorageFull =>
      'Not enough space on the device. Free up space and try again. Nothing was changed';

  @override
  String get dataImported => 'Data imported';

  @override
  String get dataImportInvalidFile =>
      'Couldn’t import the file. It isn’t a Doable export, or it’s damaged. Nothing was changed';

  @override
  String get dataImportNewerVersion =>
      'The file was created by a newer version of Doable. Update the app to import it. Nothing was changed';

  @override
  String get dataImportUnreadable =>
      'Couldn’t read the file. Check that you can access it and try again. Nothing was changed';

  @override
  String get dataImportFailed =>
      'Couldn’t import the data. Nothing was changed';

  @override
  String get dataManualBackupFailed => 'Couldn’t back up';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get dataSectionTitle => 'Data';

  @override
  String get dataSectionLocalOnly =>
      'Everything you write is stored only on this device.';

  @override
  String get dataExportTitle => 'Export data';

  @override
  String get dataExportHint => 'Save a copy of everything to a file';

  @override
  String get dataExportNothing => 'Nothing to export yet';

  @override
  String get dataExportRunning => 'Saving to a file…';

  @override
  String dataExportProgress(double share) {
    final intl.NumberFormat shareNumberFormat =
        intl.NumberFormat.percentPattern(localeName);
    final String shareString = shareNumberFormat.format(share);

    return '$shareString';
  }

  @override
  String dataExportComposition(
    int intentions,
    int relations,
    int dailyChoices,
    int tags,
  ) {
    final intl.NumberFormat intentionsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String intentionsString = intentionsNumberFormat.format(intentions);
    final intl.NumberFormat relationsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String relationsString = relationsNumberFormat.format(relations);
    final intl.NumberFormat dailyChoicesNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String dailyChoicesString = dailyChoicesNumberFormat.format(
      dailyChoices,
    );
    final intl.NumberFormat tagsNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String tagsString = tagsNumberFormat.format(tags);

    String _temp0 = intl.Intl.pluralLogic(
      intentions,
      locale: localeName,
      other: '$intentionsString intentions',
      one: '$intentionsString intention',
    );
    String _temp1 = intl.Intl.pluralLogic(
      relations,
      locale: localeName,
      other: '$relationsString relations',
      one: '$relationsString relation',
    );
    String _temp2 = intl.Intl.pluralLogic(
      dailyChoices,
      locale: localeName,
      other: '$dailyChoicesString daily choices',
      one: '$dailyChoicesString daily choice',
    );
    String _temp3 = intl.Intl.pluralLogic(
      tags,
      locale: localeName,
      other: '$tagsString tags',
      one: '$tagsString tag',
    );
    return '$_temp0, $_temp1, $_temp2 and $_temp3 in one file';
  }

  @override
  String get dataExportUnprotected =>
      'The file is not protected. Anyone who has it can read what you wrote.';

  @override
  String get dataExportSave => 'Save to a file';

  @override
  String get dataImportTitle => 'Import data';

  @override
  String get dataImportHint => 'Replace everything with a copy from a file';

  @override
  String get dataImportHintEmptyGraph => 'Bring back a copy from a file';

  @override
  String get dataImportChooseAnotherFile => 'Choose another file';

  @override
  String get dataBackupsTitle => 'Backups';

  @override
  String get dataBackupsExplanation =>
      'A copy is made each day your data changes and stays on this device. The 7 most recent daily copies are kept. Choose a copy to restore it.';

  @override
  String get dataBackupsMakeNow => 'Back up now';

  @override
  String get dataBackupsReadFailed => 'Couldn’t load backups';

  @override
  String get dataBackupsExpand => 'Expand backups panel';

  @override
  String get dataBackupsCollapse => 'Collapse backups panel';

  @override
  String get dataBackupsLastJustNow => 'Last copy just now';

  @override
  String dataBackupsLastToday(String time) {
    return 'Last copy today at $time';
  }

  @override
  String dataBackupsLastYesterday(String time) {
    return 'Last copy yesterday at $time';
  }

  @override
  String dataBackupsLastOn(String date, String time) {
    return 'Last copy on $date at $time';
  }

  @override
  String get dataBackupsNone => 'No backups yet';

  @override
  String get dataBackupsNothing => 'Nothing to back up yet';

  @override
  String dataBackupMadeToday(String time) {
    return 'Today, $time';
  }

  @override
  String dataBackupMadeYesterday(String time) {
    return 'Yesterday, $time';
  }

  @override
  String dataBackupMadeOn(String date, String time) {
    return '$date, $time';
  }

  @override
  String dataBackupRestoreMadeToday(String time) {
    return 'Restore the copy from today, $time';
  }

  @override
  String dataBackupRestoreMadeYesterday(String time) {
    return 'Restore the copy from yesterday, $time';
  }

  @override
  String dataBackupRestoreMadeOn(String date, String time) {
    return 'Restore the copy from $date, $time';
  }

  @override
  String dataBackupAdded(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return '$countString added';
  }

  @override
  String dataBackupChanged(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return '$countString changed';
  }

  @override
  String dataBackupDeleted(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return '$countString removed';
  }

  @override
  String get dataBackupNoChanges => 'No changes';

  @override
  String get dataBackupDataReplaced => 'Data replaced';

  @override
  String get dataRestoreRunning => 'Restoring the copy…';

  @override
  String get dataImportRunning => 'Importing data…';

  @override
  String dataReplacementProgress(double share) {
    final intl.NumberFormat shareNumberFormat =
        intl.NumberFormat.percentPattern(localeName);
    final String shareString = shareNumberFormat.format(share);

    return '$shareString';
  }

  @override
  String get dataReplacementCancel => 'Cancel';

  @override
  String get dataReplacementCancelling => 'Cancelling…';

  @override
  String get dataRestoreConfirmationTitle => 'Restore this copy?';

  @override
  String dataRestoreMadeToday(String time) {
    return 'It was made today at $time.';
  }

  @override
  String dataRestoreMadeYesterday(String time) {
    return 'It was made yesterday at $time.';
  }

  @override
  String dataRestoreMadeOn(String date, String time) {
    return 'It was made on $date at $time.';
  }

  @override
  String dataRestoreChangesSince(String changes) {
    return 'Since then: $changes. Restoring undoes all of it.';
  }

  @override
  String get dataRestoreNoChangesSince => 'Nothing has changed since then.';

  @override
  String get dataRestoreReplacedSince =>
      'The data has been replaced since then. Restoring undoes every change.';

  @override
  String get dataReplacementReplacesEverything =>
      'It will replace everything now in Doable. A backup of the current state is made first.';

  @override
  String get dataReplacementConfirmationCancel => 'Cancel';

  @override
  String get dataRestoreConfirm => 'Restore copy';

  @override
  String get dataImportConfirmationTitle => 'Import this copy?';

  @override
  String dataImportConfirmationFacts(
    String date,
    int intentions,
    int relations,
    int dailyChoices,
    int tags,
  ) {
    final intl.NumberFormat intentionsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String intentionsString = intentionsNumberFormat.format(intentions);
    final intl.NumberFormat relationsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String relationsString = relationsNumberFormat.format(relations);
    final intl.NumberFormat dailyChoicesNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String dailyChoicesString = dailyChoicesNumberFormat.format(
      dailyChoices,
    );
    final intl.NumberFormat tagsNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String tagsString = tagsNumberFormat.format(tags);

    String _temp0 = intl.Intl.pluralLogic(
      intentions,
      locale: localeName,
      other: '$intentionsString intentions',
      one: '$intentionsString intention',
    );
    String _temp1 = intl.Intl.pluralLogic(
      relations,
      locale: localeName,
      other: '$relationsString relations',
      one: '$relationsString relation',
    );
    String _temp2 = intl.Intl.pluralLogic(
      dailyChoices,
      locale: localeName,
      other: '$dailyChoicesString daily choices',
      one: '$dailyChoicesString daily choice',
    );
    String _temp3 = intl.Intl.pluralLogic(
      tags,
      locale: localeName,
      other: '$tagsString tags',
      one: '$tagsString tag',
    );
    return 'It was saved on $date and holds $_temp0, $_temp1, $_temp2 and $_temp3.';
  }

  @override
  String get dataImportConfirm => 'Import and replace';

  @override
  String intentionTagConditionAbsent(String tagName) {
    return 'not $tagName';
  }

  @override
  String intentionTagConditionPresentSemantics(String tagName) {
    return '$tagName, must be present';
  }

  @override
  String intentionTagConditionAbsentSemantics(String tagName) {
    return '$tagName, must be absent';
  }

  @override
  String get intentionTagConditionToggleHint =>
      'Toggle requirement: must be present or must be absent';

  @override
  String intentionTagConditionRemove(String tagName) {
    return 'Remove condition: $tagName';
  }

  @override
  String get intentionTagConditionsAdd => 'Tag';

  @override
  String get intentionTagConditionsAddSemantics => 'Add tag condition';

  @override
  String get tagsPanelTitle => 'Tags';

  @override
  String get tagsPanelAssignmentHint => 'Choose as many as you need';

  @override
  String get tagsPanelFilterTitle => 'Filter by tags';

  @override
  String get tagsPanelFilterHint =>
      'Tap to require a tag, tap again to exclude it';

  @override
  String get tagsPanelResetConditions => 'Reset';

  @override
  String get tagsPanelResetConditionsLabel => 'Reset tag conditions';

  @override
  String tagsPanelFilterPresentLabel(String tagName) {
    return '$tagName, must be present';
  }

  @override
  String tagsPanelFilterAbsentLabel(String tagName) {
    return '$tagName, must be absent';
  }

  @override
  String get tagsPanelSearchPlaceholder => 'Find or create a tag';

  @override
  String get tagsPanelSearchLabel => 'Search tags';

  @override
  String get tagsPanelClearSearch => 'Clear tag search';

  @override
  String get tagsPanelInvalidSearch =>
      'Invalid characters are shown as �. Your input is retained but wasn’t applied; results use the last valid query.';

  @override
  String get tagsPanelDone => 'Done';

  @override
  String get tagsPanelExpand => 'Expand tags panel';

  @override
  String get tagsPanelCollapse => 'Collapse tags panel';

  @override
  String get tagsPanelLoading => 'Loading tags…';

  @override
  String get tagsPanelLoadUnavailable => 'Couldn’t load tags.';

  @override
  String get tagsPanelLoadCorruption =>
      'Saved tag data is corrupted and can’t be shown.';

  @override
  String get tagsPanelLoadUnexpected =>
      'Couldn’t load tags because of an unexpected error.';

  @override
  String get tagsPanelRefreshUnavailable =>
      'Couldn’t update tags. The list may be out of date.';

  @override
  String get tagsPanelRefreshCorruption =>
      'Couldn’t update tags: saved data is corrupted. The list may be out of date.';

  @override
  String get tagsPanelRefreshUnexpected =>
      'Couldn’t update tags because of an unexpected error. The list may be out of date.';

  @override
  String get tagsPanelIntentionMissing => 'This intention no longer exists.';

  @override
  String get tagsPanelEmptyTitle => 'No tags yet';

  @override
  String get tagsPanelEmptyText =>
      'Type a name in search to create the first one';

  @override
  String tagsPanelCreateTag(String query) {
    return 'Create tag “$query”';
  }

  @override
  String tagsPanelTagMenu(String tagName) {
    return 'Tag: $tagName';
  }

  @override
  String get tagsPanelTagHoldHint => 'Long press to open tag actions';

  @override
  String get tagsPanelEditTag => 'Edit tag';

  @override
  String get tagsPanelDuplicateTag => 'Duplicate tag';

  @override
  String get tagsPanelDeleteTag => 'Delete tag';

  @override
  String get tagsPanelDeleteTitle => 'Delete tag?';

  @override
  String get tagsPanelDeleteTextBefore => 'This permanently deletes the tag ';

  @override
  String get tagsPanelDeleteTextAfter =>
      ' and all its assignments to active and archived intentions. The intentions, relations, daily choices and their paths remain.';

  @override
  String get tagsPanelDeleteCancel => 'Cancel';

  @override
  String get tagsPanelDeleteConfirm => 'Delete';

  @override
  String get tagSheetNamePlaceholder => 'Name';

  @override
  String get tagSheetEditTitle => 'Edit tag';

  @override
  String get tagEditorCreateTitle => 'New tag';

  @override
  String get tagEditorNameLabel => 'Tag name';

  @override
  String get tagColorNone => 'No color';

  @override
  String get tagColorBrown => 'Brown';

  @override
  String get tagColorOrange => 'Orange';

  @override
  String get tagColorOlive => 'Olive';

  @override
  String get tagColorGreen => 'Green';

  @override
  String get tagColorTeal => 'Teal';

  @override
  String get tagColorBlue => 'Blue';

  @override
  String get tagColorViolet => 'Violet';

  @override
  String get tagColorPurple => 'Purple';

  @override
  String get tagColorPink => 'Pink';

  @override
  String get tagColorLabel => 'Color';

  @override
  String get tagColorGroupLabel => 'Tag color';

  @override
  String get tagEditorCreateAction => 'Create tag';

  @override
  String get tagEditorRenameAction => 'Save';

  @override
  String get tagEditorSaving => 'Saving tag…';

  @override
  String get tagEditorAlreadyRunning =>
      'Saving this tag is already in progress. Wait for its result.';

  @override
  String get tagAssignmentAlreadyRunning =>
      'A tag assignment change is already in progress. Wait for its result.';

  @override
  String get tagAssignmentIntentionNotFound =>
      'This intention no longer exists. Refresh its details.';

  @override
  String get tagAssignmentUnavailable =>
      'Could not complete the tag assignment operation. Try again.';

  @override
  String get tagAssignmentCorruption =>
      'Stored tag assignment data is damaged. The assignment was not changed.';

  @override
  String get tagAssignmentUnexpected =>
      'The tag assignment operation failed because of an unexpected error.';

  @override
  String get tagAssignmentsTitle => 'Assigned tags';

  @override
  String get tagAssignmentsIntention => 'intention';

  @override
  String get tagAssignmentsActive => 'active';

  @override
  String get tagAssignmentsArchived => 'archived';

  @override
  String tagAssignmentsContext(String targetKind, String archiveState) {
    return 'Tag assignments: $targetKind, $archiveState';
  }

  @override
  String get tagAssignmentsLoading => 'Loading assignments…';

  @override
  String get tagAssignmentsEmpty => 'No tags assigned yet.';

  @override
  String get tagAssignmentsRefreshing => 'Refreshing assignments…';

  @override
  String get tagAssignmentsUnavailable =>
      'Could not load assignments. Try again.';

  @override
  String get tagAssignmentsCorruption =>
      'Stored assignment data is damaged and cannot be shown.';

  @override
  String get tagAssignmentsUnexpected =>
      'Could not load assignments because of an unexpected error.';

  @override
  String get tagAssignmentsChoose => 'Choose a tag';

  @override
  String tagAssignmentsChooseSemantic(String targetKind, String archiveState) {
    return 'Choose a tag for the $archiveState $targetKind';
  }

  @override
  String get tagAssignmentsRemove => 'Remove assignment';

  @override
  String tagAssignmentsRemoveNamed(String tagName) {
    return 'Remove assignment: $tagName';
  }

  @override
  String get tagAssignmentsRemoving => 'Removing assignment…';

  @override
  String get tagNameInvalidUnicode => 'Tag name contains invalid characters.';

  @override
  String get tagNameEmpty => 'Enter a tag name.';

  @override
  String get tagNameTooLong =>
      'Tag name must contain no more than 255 visible characters.';

  @override
  String get tagNameNonCanonical => 'Remove whitespace around the tag name.';

  @override
  String get tagNameOccupied => 'A tag with this name already exists.';

  @override
  String get tagNotFound => 'This tag no longer exists. Refresh the catalog.';

  @override
  String get tagUnavailable =>
      'Could not complete the tag operation. Try again.';

  @override
  String get tagCorruption =>
      'Stored tag data is damaged. The tag was not changed.';

  @override
  String get tagUnexpected =>
      'The tag operation failed because of an unexpected error.';

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
    return 'Relation: $phrase\nSource intention: $sourceTitle\nRelated intention: $relatedTitle\nRelation state: $scope\n\nThis can’t be undone. The relation and its description will be permanently deleted. The tags, all their assignments to intentions, both intentions and all other relations will remain.';
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
  String get actionPickerCancel => 'Cancel action selection';

  @override
  String get actionPickerLoading => 'Loading actions…';

  @override
  String get actionPickerEmpty => 'No active actions are available.';

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
  String get sourcePickerCancel => 'Cancel intention selection';

  @override
  String get sourcePickerEmpty => 'No active intentions are available.';

  @override
  String get dailyChoicePickerPurposeCreationSource =>
      'New daily choice: source intention';

  @override
  String get dailyChoicePickerPurposeCreationAction =>
      'New daily choice: selected action';

  @override
  String get dailyChoicePickerPurposeReplacementSource =>
      'Path replacement: source intention';

  @override
  String get dailyChoicePickerPurposeReplacementAction =>
      'Path replacement: selected action';

  @override
  String get dailyChoicePickerFlowCreationFromSource =>
      'New daily choice, from an intention';

  @override
  String get dailyChoicePickerFlowCreationFromAction =>
      'New daily choice, from an action';

  @override
  String get dailyChoicePickerFlowReplacementFromSource =>
      'Path replacement, from an intention';

  @override
  String get dailyChoicePickerFlowReplacementFromAction =>
      'Path replacement, from an action';

  @override
  String get dailyChoicePickerStepCurrent => 'You are here';

  @override
  String get dailyChoicePickerStepSource => 'Source intention';

  @override
  String get dailyChoicePickerStepAction => 'Selected action';

  @override
  String get dailyChoicePickerStepPathDown => 'Path down to an action';

  @override
  String get dailyChoicePickerStepPathDownNote =>
      'Each next step is what the previous one needs or can use';

  @override
  String get dailyChoicePickerStepPathUp => 'Path up to the source intention';

  @override
  String get dailyChoicePickerStepPathUpNote => 'At least one step is needed';

  @override
  String get dailyChoicePickerStepDetails =>
      'Date, time, priority, and description';

  @override
  String get dailyChoicePickerStepReplacement => 'Replacement confirmation';

  @override
  String get dailyChoicePickerStepReplacementNote =>
      'The date, scheduled time, priority, description, and completion stay the same';

  @override
  String get intentionPickerArchived => 'archived';

  @override
  String get intentionPickerKindAction => 'action';

  @override
  String get intentionPickerKindIntention => 'intention';

  @override
  String intentionPickerOpenActionPage(String title) {
    return 'Open the page of action $title';
  }

  @override
  String intentionPickerOpenIntentionPage(String title) {
    return 'Open the page of intention $title';
  }

  @override
  String get intentionPickerShowAndSortTitle => 'Show and sort';

  @override
  String get intentionPickerShowAndSortHint => 'The list changes as you choose';

  @override
  String get intentionPickerShowAndSortReset => 'Reset';

  @override
  String intentionPickerPurposeLabel(String title, String subtitle) {
    return '$title. $subtitle. Show what you are choosing';
  }

  @override
  String get intentionPickerPurposeSheetTitle => 'What you are choosing';

  @override
  String get intentionPickerPurposeSheetBack => 'Back to the list';

  @override
  String get intentionPickerTypeCaption => 'Type';

  @override
  String get intentionPickerTypeAll => 'All';

  @override
  String get intentionPickerTypeIntentionsOnly => 'Intentions only';

  @override
  String get intentionPickerTypeActionsOnly => 'Actions only';

  @override
  String get intentionPickerActionTypeNote =>
      'Only an action can be the final intention of a daily choice';

  @override
  String get intentionPickerSortCaption => 'Sort by';

  @override
  String get intentionPickerSortCreated => 'Date created';

  @override
  String get intentionPickerSortChanged => 'Date changed';

  @override
  String get intentionPickerSortName => 'Name';

  @override
  String get intentionPickerOrderNewest => 'Newest first';

  @override
  String get intentionPickerOrderOldest => 'Oldest first';

  @override
  String get intentionPickerOrderAToZ => 'A to Z';

  @override
  String get intentionPickerOrderZToA => 'Z to A';

  @override
  String intentionPickerOrderButtonSemantics(
    String currentOrder,
    String nextOrder,
  ) {
    return 'Current order: $currentOrder. Switch to: $nextOrder';
  }

  @override
  String get intentionPickerAllHeader => 'All';

  @override
  String get intentionPickerOrderCreatedNewest => 'Created, newest first';

  @override
  String get intentionPickerOrderCreatedOldest => 'Created, oldest first';

  @override
  String get intentionPickerOrderUpdatedNewest => 'Changed, newest first';

  @override
  String get intentionPickerOrderUpdatedOldest => 'Changed, oldest first';

  @override
  String get intentionPickerOrderTitleAscending => 'Name, A to Z';

  @override
  String get intentionPickerOrderTitleDescending => 'Name, Z to A';

  @override
  String intentionPickerHeaderLabel(String type, String summary) {
    return 'Show and sort. Type: $type. Sorted by: $summary.';
  }

  @override
  String intentionPickerHeaderCountLabel(
    String type,
    int count,
    String summary,
  ) {
    return 'Show and sort. Type: $type, $count. Sorted by: $summary.';
  }

  @override
  String get intentionPickerActionsHeader => 'Actions';

  @override
  String get intentionPickerIntentionsHeader => 'Intentions';

  @override
  String get intentionPickerLoadingMoreActions => 'Loading more actions';

  @override
  String get intentionPickerLoadingMoreIntentions => 'Loading more intentions';

  @override
  String get intentionPickerEmptyScopeTitle => 'Nothing to choose from';

  @override
  String get intentionPickerEmptyTypeTitle => 'No intentions of this type';

  @override
  String get intentionPickerEmptyTypeText =>
      'Show both types to choose from the available intentions.';

  @override
  String get intentionPickerShowBothTypes => 'Show both types';

  @override
  String get intentionPickerActionTitle => 'Choose an action';

  @override
  String get intentionPickerIntentionTitle => 'Choose an intention';

  @override
  String get intentionPickerSearchPlaceholder => 'Search by name';

  @override
  String get intentionPickerClearSearch => 'Clear the name';

  @override
  String intentionPickerFilterLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Filter by tags, $count conditions',
      one: 'Filter by tags, 1 condition',
      zero: 'Filter by tags',
    );
    return '$_temp0';
  }

  @override
  String get intentionPickerNoActionsByTitle => 'No actions with this name';

  @override
  String get intentionPickerNoIntentionsByTitle =>
      'No intentions with this name';

  @override
  String get intentionPickerTryShorterTitle => 'Try a shorter name.';

  @override
  String get intentionPickerNoActionsByTags => 'No actions match these tags';

  @override
  String get intentionPickerNoIntentionsByTags =>
      'No intentions match these tags';

  @override
  String get intentionPickerChangeTags =>
      'Change the tags in the filter or reset it.';

  @override
  String get intentionPickerNoActionsFound => 'No actions found';

  @override
  String get intentionPickerNoIntentionsFound => 'No intentions found';

  @override
  String get intentionPickerChangeTitleOrTags =>
      'Change the name or the tag conditions.';

  @override
  String get intentionPickerResetFilters => 'Reset filters';

  @override
  String get participantPickerCancel => 'Cancel intention selection';

  @override
  String get participantPickerEmpty =>
      'No other intentions are available to select.';

  @override
  String get participantPickerOpenDetails => 'Open intention details';

  @override
  String get participantPickerPurposeCreationSource =>
      'New relation: source intention';

  @override
  String get participantPickerPurposeCreationRelated =>
      'New relation: related intention';

  @override
  String get participantPickerPurposeChangeSource =>
      'Relation change: source intention';

  @override
  String get participantPickerPurposeChangeRelated =>
      'Relation change: related intention';

  @override
  String get participantPickerFlowCreation => 'New relation';

  @override
  String get participantPickerFlowChange => 'Relation change';

  @override
  String get participantPickerRoleSourceNote =>
      'The source intention is what the related intention is needed for or can be used for.';

  @override
  String get participantPickerRoleRelatedNeedNote =>
      'The related intention is what the source intention needs.';

  @override
  String get participantPickerRoleRelatedCanNote =>
      'The related intention is what the source intention can use.';

  @override
  String get participantPickerRoleRelatedUndeterminedNote =>
      'The related intention is what the source intention needs or can use.';

  @override
  String get participantPickerFieldChoosing => 'Choosing now';

  @override
  String get participantPickerFieldFromList => 'From this list';

  @override
  String participantPickerFieldReplacing(String title) {
    return 'Instead of: $title';
  }

  @override
  String get participantPickerFieldNotChosen => 'Not chosen yet';

  @override
  String get participantPickerFieldArchived => 'Archived';

  @override
  String get participantPickerKindUndetermined => 'Need or can: not chosen yet';

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
  String get dailyChoiceScheduleLabel => 'Scheduled time';

  @override
  String get dailyChoiceAllDay => 'All day';

  @override
  String get dailyChoiceSetTime => 'Set time';

  @override
  String dailyChoiceTimeLabel(String time) {
    return 'Time: $time';
  }

  @override
  String get dailyChoicePriorityLabel => 'Priority';

  @override
  String dailyChoicePriorityOption(String priority) {
    return 'Priority $priority';
  }

  @override
  String get dailyChoiceCatalogTitle => 'Daily choices';

  @override
  String get dailyChoiceCreateFromAction => 'Create a choice from an action';

  @override
  String get dailyChoiceCatalogLoading => 'Loading daily choices…';

  @override
  String get dailyChoiceCalendarToday => 'Today';

  @override
  String get dailyChoiceCalendarDayAllCompleted =>
      'All daily choices are completed';

  @override
  String get dailyChoiceCalendarDayHasIncomplete =>
      'There is an incomplete daily choice';

  @override
  String get dailyChoiceCalendarDayMarksUnavailable =>
      'Day marks could not be loaded.';

  @override
  String get dailyChoiceCalendarExpand => 'Expand calendar';

  @override
  String get dailyChoiceCalendarCollapse => 'Collapse calendar';

  @override
  String get dailyChoiceCalendarPreviousMonth => 'Previous month';

  @override
  String get dailyChoiceCalendarNextMonth => 'Next month';

  @override
  String get dailyChoiceCalendarChooseYearAndMonth => 'Choose year and month';

  @override
  String get dailyChoiceCalendarBackToMonthDays =>
      'Back to the days of the month';

  @override
  String get dailyChoiceCalendarPreviousYears => 'Previous years';

  @override
  String get dailyChoiceCalendarNextYears => 'Next years';

  @override
  String get dailyChoiceCalendarPreviousYear => 'Previous year';

  @override
  String get dailyChoiceCalendarNextYear => 'Next year';

  @override
  String get dailyChoiceCatalogIncomplete => 'Not completed';

  @override
  String get dailyChoiceCatalogCompleted => 'Completed';

  @override
  String dailyChoiceCatalogTotalCount(int count) {
    return 'Total daily choices: $count';
  }

  @override
  String get dailyChoiceCatalogEmpty => 'No daily choices for this day.';

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
  String get dailyChoiceCatalogUnexpected =>
      'Could not load daily choices because of an unexpected error.';

  @override
  String dailyChoiceCatalogPathIntentionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count intentions in path',
      one: '$count intention in path',
    );
    return '$_temp0';
  }

  @override
  String dailyChoiceCatalogCompletionLabel(
    int number,
    String phrase,
    String date,
  ) {
    return 'Completion of choice #$number. $phrase. $date';
  }

  @override
  String get dailyChoiceCompletionSaving => 'Saving completion…';

  @override
  String get dailyChoiceCompletionSynchronizing =>
      'Completion saved. Refreshing the catalog…';

  @override
  String get dailyChoiceCompletionRefresh => 'Refresh choice';

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
  String get dailyChoiceReplaceOpen => 'Replace path';

  @override
  String get dailyChoiceReplaceChooseDirection =>
      'Choose the new path direction';

  @override
  String get dailyChoiceReplaceChooseDirectionDescription =>
      'Choose a new source or action to replace the saved path.';

  @override
  String get dailyChoiceReplaceFromSource => 'Start from a new source';

  @override
  String get dailyChoiceReplaceFromAction => 'Start from a new action';

  @override
  String get dailyChoiceReplaceSelectPath => 'Choose a replacement path';

  @override
  String get dailyChoiceReplaceOpenConfirmation => 'Confirm path replacement';

  @override
  String get choicePathOpenConfirmation => 'Continue to choice confirmation';

  @override
  String get creationCancelAction => 'Cancel creation';

  @override
  String get creationLeaveAction => 'Leave creation';

  @override
  String get creationSavingContinues =>
      'Saving will continue after you leave creation.';
}
