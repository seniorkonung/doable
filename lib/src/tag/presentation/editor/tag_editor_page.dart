import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/tag_color_picker.dart';
import '../../../design_system/components/tag_dot.dart';
import '../../../design_system/doable_metrics.dart';
import '../../../graph/presentation/operation_failure_presentation.dart';
import '../../application/tag_read_result.dart';
import '../../application/tag_result.dart';
import '../../domain/tag.dart';
import '../tag_color_presentation.dart';
import '../tag_failure_message.dart';
import 'tag_editor_state.dart';
import 'tag_editor_view_model.dart';

@RoutePage()
final class TagEditorPage extends ConsumerStatefulWidget {
  const TagEditorPage({required this.editorContext, super.key});

  final TagEditorContext editorContext;

  @override
  ConsumerState<TagEditorPage> createState() => _TagEditorPageState();
}

final class _TagEditorPageState extends ConsumerState<TagEditorPage> {
  late final TextEditingController _nameController;

  /// Живая область включается первым выбором пользователя,
  /// поэтому открытие формы ничего не объявляет.
  var _announcesColor = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: switch (widget.editorContext) {
        TagEditorCreating() => '',
        TagEditorRenaming(:final tag) => tag.name.value,
      },
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final provider = tagEditorViewModelProvider(widget.editorContext);
    final state = ref.watch(provider);
    final model = ref.read(provider.notifier);
    ref.listen(provider, (previous, next) {
      if (next.event
          case TagEditorSaved(:final tag) ||
              TagEditorExistingSelected(:final tag)) {
        model.consumeEvent();
        unawaited(context.router.maybePop<Tag>(tag));
      }
    });

    // Отказ принятой отправки предъявляет общая поверхность, поэтому форма
    // рисует только собственную проверку названия и прерванную отправку.
    final fieldFailure = switch (state.status) {
      TagEditorNameInvalid(:final reason) => tagFailureMessage(
        l10n,
        TagNameInputFailure(reason),
      ),
      _ => null,
    };
    final generalFailure = switch (state.status) {
      TagEditorSubmissionInterrupted() => tagFailureMessage(
        l10n,
        const TagUnexpectedFailure(),
      ),
      _ => null,
    };
    final readStatus = _readStatus(l10n, state.status);
    final creating = state.context is TagEditorCreating;
    final selectedColor = tagColorPresentation(state.color);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          creating ? l10n.tagEditorCreateTitle : l10n.tagEditorRenameTitle,
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              key: const ValueKey('tag-editor-name'),
              controller: _nameController,
              autofocus: true,
              minLines: 1,
              maxLines: 3,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                prefixIcon: Center(
                  widthFactor: 1,
                  heightFactor: 1,
                  child: TagDot(color: selectedColor, size: TagDotSize.large),
                ),
                labelText: l10n.tagEditorNameLabel,
                helperText: l10n.tagEditorNameLimit,
                helperMaxLines: 2,
                error: fieldFailure == null
                    ? null
                    : OperationFailurePresentation(
                        claim: null,
                        message: fieldFailure,
                        messageKey: const ValueKey('tag-editor-field-failure'),
                      ),
              ),
              onChanged: model.changeName,
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
            if (generalFailure != null) ...[
              const SizedBox(height: 16),
              OperationFailurePresentation(
                claim: null,
                message: generalFailure,
                messageKey: const ValueKey('tag-editor-general-failure'),
              ),
            ],
            if (readStatus != null) ...[
              const SizedBox(height: 16),
              Semantics(
                key: state.status is TagEditorAlreadyRunning
                    ? const ValueKey('tag-editor-already-running')
                    : null,
                container: true,
                liveRegion: true,
                child: Text(readStatus),
              ),
            ],
            if (state.status case TagEditorSubmissionFailed(
              failure: TagNameOccupiedFailure(),
            )) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                key: const ValueKey('tag-editor-use-existing'),
                onPressed: model.useExisting,
                child: Text(l10n.tagEditorUseExisting),
              ),
            ],
            if (state.status case TagEditorExistingReadFailed(canRetry: true))
              OutlinedButton(
                key: const ValueKey('tag-editor-retry-existing'),
                onPressed: model.useExisting,
                child: Text(l10n.commonRetry),
              ),
            if (state.status case TagEditorCommittedReadFailed(canRetry: true))
              OutlinedButton(
                key: const ValueKey('tag-editor-retry-committed'),
                onPressed: model.retryCommittedRead,
                child: Text(l10n.commonRetry),
              ),
            const SizedBox(height: 24),
            FilledButton(
              key: const ValueKey('tag-editor-submit'),
              onPressed: state.canSubmit ? model.submit : null,
              child: Text(
                state.status is TagEditorSubmitting
                    ? l10n.tagEditorSaving
                    : creating
                    ? l10n.tagEditorCreateAction
                    : l10n.tagEditorRenameAction,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              key: const ValueKey('tag-editor-cancel'),
              onPressed: () => unawaited(context.router.maybePop()),
              child: Text(l10n.tagEditorCancel),
            ),
          ],
        ),
      ),
    );
  }
}

String? _readStatus(AppLocalizations l10n, TagEditorStatus status) =>
    switch (status) {
      TagEditorAlreadyRunning() => l10n.tagEditorAlreadyRunning,
      TagEditorReadingCommitted() => l10n.tagEditorReadingCommitted,
      TagEditorCommittedReadFailed(:final failure) =>
        '${l10n.tagEditorCommittedReadFailed} ${_readFailure(l10n, failure)}',
      TagEditorCommittedMissing() => l10n.tagEditorCommittedMissing,
      TagEditorReadingExisting() => l10n.tagEditorReadingExisting,
      TagEditorExistingReadFailed(:final failure) => _readFailure(
        l10n,
        failure,
      ),
      TagEditorExistingMissing() => l10n.tagEditorExistingMissing,
      _ => null,
    };

String _readFailure(AppLocalizations l10n, TagReadFailure failure) =>
    switch (failure) {
      TagReadUnavailableFailure() => l10n.tagEditorReadUnavailable,
      TagReadCorruptionFailure() => l10n.tagEditorReadCorruption,
      TagReadUnexpectedFailure() => l10n.tagEditorReadUnexpected,
    };
