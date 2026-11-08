import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/option_row.dart';
import '../../../design_system/components/options_menu.dart';
import '../../../design_system/doable_icon.dart';
import '../../application/cascade/intention_cascade.dart';
import '../../domain/intention.dart';
import 'intention_details_state.dart';

/// Действие, выбранное в параметрах намерения на его странице.
enum IntentionOption { edit, archive, restore, delete }

/// Пункты листа «Намерение» по последнему принятому снимку страницы.
///
/// Пока для намерения выполняется изменяющая операция, все пункты
/// недоступны и просят дождаться её окончания.
List<OptionsMenuItem<IntentionOption>> intentionOptions(
  AppLocalizations localizations,
  IntentionDetailsLoaded loaded, {
  CascadePreviewResult? statePreview,
  CascadePreviewResult? deletePreview,
}) {
  final busy = loaded.isOperationRunning;
  final wait = localizations.detailsOptionWait;
  final archived =
      loaded.intention.archiveState == IntentionArchiveState.archived;

  // Правка ещё ждёт и снимок с последним подтверждённым текстом.
  final edit = busy || loaded.isAwaitingConfirmedSnapshot
      ? OptionsMenuItem<IntentionOption>.unavailable(
          icon: DoableIconData.edit,
          name: localizations.detailsOptionEdit,
          reason: wait,
        )
      : OptionsMenuItem(
          value: IntentionOption.edit,
          icon: DoableIconData.edit,
          name: localizations.detailsOptionEdit,
        );

  final String? stateHint = switch (statePreview) {
    ArchiveCascadePreview(:final plan) =>
      plan.withSupporting.departing.isNotEmpty
          ? localizations.detailsCascadeArchiveHint(
              plan.withSupporting.departing.length,
            )
          : plan.withSupporting.archivedRelationCount > 0
          ? localizations.detailsOptionArchiveWithRelations
          : localizations.detailsOptionArchiveAlone,
    RestoreCascadePreview(:final plan) =>
      plan.withSupporting.restored.isNotEmpty
          ? localizations.detailsCascadeRestoreHint(
              plan.withSupporting.restored.length,
            )
          : plan.withSupporting.restoredRelationCount > 0
          ? localizations.detailsOptionRestoreWithRelations
          : localizations.detailsOptionRestoreAlone,
    _ => null,
  };
  final (stateValue, stateIcon, stateName) = archived
      ? (
          IntentionOption.restore,
          DoableIconData.unarchive,
          localizations.detailsRestoreFromArchiveAction,
        )
      : (
          IntentionOption.archive,
          DoableIconData.archive,
          localizations.detailsOptionArchive,
        );
  final stateChange = busy
      ? OptionsMenuItem<IntentionOption>.unavailable(
          icon: stateIcon,
          name: stateName,
          reason: wait,
        )
      : OptionsMenuItem(
          value: stateValue,
          icon: stateIcon,
          name: stateName,
          hint: stateHint,
        );

  final String? deleteHint = switch (deletePreview) {
    IntentionDeleteCascadePreview(:final plan, :final isInActionPath) =>
      plan.withSupporting.departing.isNotEmpty ||
              plan.withSupporting.archivedByInvariant.isNotEmpty
          ? [
              if (plan.withSupporting.departing.isNotEmpty)
                localizations.detailsCascadeDeleteHint(
                  plan.withSupporting.departing.length,
                ),
              if (plan.withSupporting.archivedByInvariant.isNotEmpty)
                localizations.detailsCascadeDeleteArchiveHint(
                  plan.withSupporting.archivedByInvariant.length,
                ),
            ].join('. ')
          : isInActionPath
          ? localizations.detailsOptionDeleteKeepsPaths
          : localizations.detailsOptionDeleteKeepsTags,
    _ => null,
  };
  final delete = busy
      ? OptionsMenuItem<IntentionOption>.unavailable(
          icon: DoableIconData.delete,
          name: localizations.detailsOptionDelete,
          reason: wait,
        )
      : OptionsMenuItem(
          value: IntentionOption.delete,
          icon: DoableIconData.delete,
          name: localizations.detailsOptionDelete,
          hint: deleteHint,
          tone: OptionRowTone.danger,
        );

  return [edit, stateChange, delete];
}
