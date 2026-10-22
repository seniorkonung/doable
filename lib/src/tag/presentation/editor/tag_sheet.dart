import 'package:flutter/material.dart' hide TextField;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/button.dart';
import '../../../design_system/components/notice.dart';
import '../../../design_system/components/sheet.dart';
import '../../../design_system/components/tag_color_picker.dart';
import '../../../design_system/components/tag_dot.dart';
import '../../../design_system/components/text_field.dart';
import '../../../design_system/doable_metrics.dart';
import '../../application/tag_result.dart';
import '../tag_color_presentation.dart';
import '../tag_failure_message.dart';
import 'tag_editor_state.dart';
import 'tag_editor_view_model.dart';

/// Показывает лист «Новый тег» поверх панели тегов.
///
/// Закрытие свайпом, касанием затемнения или «назад» завершает только
/// экранную сессию листа: принятое создание продолжается у того, кому его
/// отдал [TagEditorCreating.onCreationAccepted]. Подтверждённое создание
/// закрывает лист, если он ещё открыт. Отказ записи общая поверхность
/// показывает поверх листа, а лист сохраняет название и цвет.
Future<void> showTagSheet(BuildContext context, TagEditorCreating creating) =>
    showDoableSheet<void>(
      context: context,
      hostsMessages: true,
      builder: (_, sheet) => _TagSheet(sheet, creating),
    );

final class _TagSheet extends ConsumerStatefulWidget {
  const _TagSheet(this.sheet, this.creating);

  final ContentSheetCapability sheet;
  final TagEditorCreating creating;

  @override
  ConsumerState<_TagSheet> createState() => _TagSheetState();
}

final class _TagSheetState extends ConsumerState<_TagSheet> {
  late final _nameController = TextEditingController(
    text: TagEditorState.initialInput(widget.creating),
  );

  /// Живая область включается первым выбором пользователя,
  /// поэтому открытие листа ничего не объявляет.
  var _announcesColor = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final provider = tagEditorViewModelProvider(widget.creating);
    final state = ref.watch(provider);
    final model = ref.read(provider.notifier);
    ref.listen(provider, (previous, next) {
      if (next.event case TagEditorSaved()) {
        model.consumeEvent();
        if (ModalRoute.of(context)?.isCurrent ?? false) Navigator.pop(context);
      }
    });

    // Отказ принятой отправки предъявляет общая поверхность, поэтому лист
    // рисует только собственную проверку названия и прерванную отправку.
    final fieldFailure = switch (state.nameCheck) {
      TagEditorNameInvalid(:final reason) => tagFailureMessage(
        l10n,
        TagNameInputFailure(reason),
      ),
      TagEditorNameOccupied() => l10n.tagNameOccupied,
      TagEditorNameAccepted() || TagEditorNameEmpty() => null,
    };
    final statusMessage = switch (state.status) {
      TagEditorSubmissionInterrupted() => tagFailureMessage(
        l10n,
        const TagUnexpectedFailure(),
      ),
      TagEditorAlreadyRunning() => l10n.tagEditorAlreadyRunning,
      TagEditorIdle() ||
      TagEditorSubmitting() ||
      TagEditorSubmissionFailed() ||
      TagEditorCompleted() => null,
    };
    final selectedColor = tagColorPresentation(state.color);

    return Sheet(
      widget.sheet,
      title: l10n.tagEditorCreateTitle,
      footer: Button.primary(
        label: state.status is TagEditorSubmitting
            ? l10n.tagEditorSaving
            : l10n.tagEditorCreateAction,
        onPressed: state.canSubmit ? model.submit : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: DoableMetrics.space2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              placeholder: l10n.tagSheetNamePlaceholder,
              label: l10n.tagEditorNameLabel,
              leading: TagDot(color: selectedColor, size: TagDotSize.large),
              onChanged: model.changeName,
              error: fieldFailure,
            ),
            const SizedBox(height: DoableMetrics.space1),
            TagColorPicker(
              value: selectedColor,
              label: l10n.tagColorLabel,
              groupLabel: l10n.tagColorGroupLabel,
              colorLabel: (color) => tagColorLabel(l10n, color),
              announcesValue: _announcesColor,
              onChanged: (color) {
                if (color == selectedColor) return;
                model.changeColor(tagColorFromPresentation(color));
                setState(() => _announcesColor = true);
              },
            ),
            if (statusMessage != null) ...[
              const SizedBox(height: DoableMetrics.space2),
              Notice(message: statusMessage),
            ],
          ],
        ),
      ),
    );
  }
}
