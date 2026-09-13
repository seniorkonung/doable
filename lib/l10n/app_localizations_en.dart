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
      'The intention is still linked and can’t be deleted.';

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
}
