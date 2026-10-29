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

/// Показывает поверх панели тегов лист «Новый тег» или «Изменить тег».
///
/// Закрытие свайпом, касанием затемнения или «назад» завершает только
/// экранную сессию листа и не меняет тег: принятое создание продолжается у
/// того, кому его отдал [TagEditorCreating.onCreationAccepted]. Подтверждённое
/// создание или изменение закрывает лист, если он ещё открыт. Отказ записи
/// общая поверхность показывает поверх листа, а лист сохраняет название и
/// цвет.
Future<void> showTagSheet(BuildContext context, TagEditorContext editing) =>
    showDoableSheet<void>(
      context: context,
      hostsMessages: true,
      builder: (_, sheet) => _TagSheet(sheet, editing),
    );

final class _TagSheet extends ConsumerStatefulWidget {
  const _TagSheet(this.sheet, this.editing);

  final SheetPresentation sheet;
  final TagEditorContext editing;

  @override
  ConsumerState<_TagSheet> createState() => _TagSheetState();
}

final class _TagSheetState extends ConsumerState<_TagSheet> {
  late final _nameController = TextEditingController(
    text: TagEditorState.initialInput(widget.editing),
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
    final provider = tagEditorViewModelProvider(widget.editing);
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
    final (title, action) = switch (state.context) {
      TagEditorCreating() => (
        l10n.tagEditorCreateTitle,
        l10n.tagEditorCreateAction,
      ),
      TagEditorRenaming() => (
        l10n.tagSheetEditTitle,
        l10n.tagEditorRenameAction,
      ),
    };

    return Sheet(
      widget.sheet,
      title: title,
      footer: Button.primary(
        label: state.status is TagEditorSubmitting
            ? l10n.tagEditorSaving
            : action,
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
              error: fieldFailure == null ? null : Text(fieldFailure),
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
