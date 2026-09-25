import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../graph/presentation/operation_failure_presentation.dart';
import '../../application/tag_read_result.dart';
import '../../application/tag_result.dart';
import '../../domain/tag.dart';
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

    final failure = switch (state.status) {
      TagEditorSubmissionFailed(:final failure) => failure,
      _ => null,
    };
    final fieldFailure = switch (failure) {
      TagNameInputFailure() ||
      TagNameOccupiedFailure() => tagFailureMessage(l10n, failure!),
      _ => null,
    };
    final generalFailure = switch (failure) {
      null || TagNameInputFailure() || TagNameOccupiedFailure() => null,
      _ => tagFailureMessage(l10n, failure),
    };
    final readStatus = _readStatus(l10n, state.status);
    final creating = state.context is TagEditorCreating;

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
                labelText: l10n.tagEditorNameLabel,
                helperText: l10n.tagEditorNameLimit,
                helperMaxLines: 2,
                error: fieldFailure == null
                    ? null
                    : OperationFailurePresentation(
                        claim: state.failurePresentation,
                        message: fieldFailure,
                        messageKey: const ValueKey('tag-editor-field-failure'),
                      ),
              ),
              onChanged: model.changeName,
            ),
            if (generalFailure != null) ...[
              const SizedBox(height: 16),
              OperationFailurePresentation(
                claim: state.failurePresentation,
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
