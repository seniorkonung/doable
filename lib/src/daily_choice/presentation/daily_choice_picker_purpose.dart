import '../../../l10n/app_localizations.dart';
import '../../design_system/components/flow_steps.dart';
import '../../intention/presentation/picker/intention_picker_purpose_sheet.dart';
import 'daily_choice_picker_context.dart';

/// Участник, с которого поток дневного выбора начинает путь. Его задаёт вид
/// поиска: поиск исходного намерения начинает от намерения, поиск действия —
/// от действия.
enum DailyChoicePickerStart { source, action }

/// Назначение поиска дневного выбора: поток из [pickerContext] и направление
/// [start] определяют подзаголовок, строку листа и три шага потока.
IntentionPickerPurposeDescription dailyChoicePickerPurpose(
  AppLocalizations l10n, {
  required DailyChoicePickerContext pickerContext,
  required DailyChoicePickerStart start,
}) {
  final (subtitle, sheetLine) = switch ((pickerContext, start)) {
    (InitialDailyChoicePickerContext(), DailyChoicePickerStart.source) => (
      l10n.dailyChoicePickerPurposeCreationSource,
      l10n.dailyChoicePickerFlowCreationFromSource,
    ),
    (InitialDailyChoicePickerContext(), DailyChoicePickerStart.action) => (
      l10n.dailyChoicePickerPurposeCreationAction,
      l10n.dailyChoicePickerFlowCreationFromAction,
    ),
    (
      PathReplacementDailyChoicePickerContext(),
      DailyChoicePickerStart.source,
    ) =>
      (
        l10n.dailyChoicePickerPurposeReplacementSource,
        l10n.dailyChoicePickerFlowReplacementFromSource,
      ),
    (
      PathReplacementDailyChoicePickerContext(),
      DailyChoicePickerStart.action,
    ) =>
      (
        l10n.dailyChoicePickerPurposeReplacementAction,
        l10n.dailyChoicePickerFlowReplacementFromAction,
      ),
  };
  // Путь выбора не бывает пустым ни в одном направлении, поэтому ни один шаг
  // не назван необязательным.
  final steps = [
    ...switch (start) {
      DailyChoicePickerStart.source => [
        FlowStep(title: l10n.dailyChoicePickerStepSource),
        FlowStep(
          title: l10n.dailyChoicePickerStepPathDown,
          note: l10n.dailyChoicePickerStepPathDownNote,
        ),
      ],
      DailyChoicePickerStart.action => [
        FlowStep(title: l10n.dailyChoicePickerStepAction),
        FlowStep(
          title: l10n.dailyChoicePickerStepPathUp,
          note: l10n.dailyChoicePickerStepPathUpNote,
        ),
      ],
    },
    switch (pickerContext) {
      InitialDailyChoicePickerContext() => FlowStep(
        title: l10n.dailyChoicePickerStepDetails,
      ),
      PathReplacementDailyChoicePickerContext() => FlowStep(
        title: l10n.dailyChoicePickerStepReplacement,
        note: l10n.dailyChoicePickerStepReplacementNote,
      ),
    },
  ];
  return IntentionPickerPurposeDescription(
    subtitle: subtitle,
    sheetLine: sheetLine,
    buildSheetBody: (_) => FlowSteps(
      steps: steps,
      current: 0,
      currentMark: l10n.dailyChoicePickerStepCurrent,
    ),
  );
}
