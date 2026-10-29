import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/option_row.dart';
import '../../../design_system/components/options_menu.dart';
import '../../../design_system/doable_icon.dart';
import '../../domain/intention.dart';
import 'intention_details_state.dart';

/// Действие, выбранное в параметрах намерения на его странице.
enum IntentionOption { edit, archive, restore, delete }

/// Пункты листа «Намерение» по последнему принятому снимку страницы.
///
/// Пока для намерения выполняется изменяющая операция, все пункты
/// недоступны и просят дождаться её окончания. Исключение — удаление,
/// которое блокируют связи или дневные выборы: окончание операции его не
/// откроет, поэтому оно сохраняет свою причину.
List<OptionsMenuItem<IntentionOption>> intentionOptions(
  AppLocalizations localizations,
  IntentionDetailsLoaded loaded,
) {
  final counts = loaded.details.relationCounts;
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

  final (stateValue, stateIcon, stateName, stateHint) = archived
      ? (
          IntentionOption.restore,
          DoableIconData.unarchive,
          localizations.detailsRestoreFromArchiveAction,
          counts.longTermTotal > 0
              ? localizations.detailsOptionRestoreWithRelations
              : localizations.detailsOptionRestoreAlone,
        )
      : (
          IntentionOption.archive,
          DoableIconData.archive,
          localizations.detailsOptionArchive,
          counts.active > 0
              ? localizations.detailsOptionArchiveWithRelations
              : localizations.detailsOptionArchiveAlone,
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

  final blockedReason = switch ((
    counts.longTermTotal > 0,
    counts.dailyTotal > 0,
  )) {
    (true, true) =>
      localizations.detailsOptionDeleteRelationsAndDailyChoicesFirst,
    (true, false) => localizations.detailsOptionDeleteRelationsFirst,
    (false, true) => localizations.detailsOptionDeleteDailyChoicesFirst,
    (false, false) => busy ? wait : null,
  };
  final delete = blockedReason == null
      ? OptionsMenuItem(
          value: IntentionOption.delete,
          icon: DoableIconData.delete,
          name: localizations.detailsOptionDelete,
          hint: localizations.detailsOptionDeleteKeepsTags,
          tone: OptionRowTone.danger,
        )
      : OptionsMenuItem<IntentionOption>.unavailable(
          icon: DoableIconData.delete,
          name: localizations.detailsOptionDelete,
          reason: blockedReason,
        );

  return [edit, stateChange, delete];
}
