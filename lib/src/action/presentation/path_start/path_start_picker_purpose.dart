import 'package:flutter/widgets.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/flow_steps.dart';
import '../../../intention/presentation/picker/intention_picker_purpose_sheet.dart';
import 'path_start_picker_page.dart';

IntentionPickerPurposeDescription pathStartPickerPurpose(
  AppLocalizations l10n,
  PathStartFlow flow,
) {
  final name = switch (flow) {
    PathStartFlow.newAction => l10n.pathStartNewAction,
    PathStartFlow.editPath => l10n.pathStartEditPath,
  };
  return IntentionPickerPurposeDescription(
    subtitle: l10n.pathStartSubtitle(name),
    sheetLine: name,
    buildSheetBody: (BuildContext context) => FlowSteps(
      current: 0,
      currentMark: l10n.pathStartCurrentStep,
      steps: [
        FlowStep(title: l10n.pathStartFirstStep, note: l10n.pathStartFirstNote),
        FlowStep(
          title: l10n.pathStartSecondStep,
          note: l10n.pathStartSecondNote,
        ),
      ],
    ),
  );
}
