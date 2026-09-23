import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/routing/app_router.gr.dart';
import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../graph/application/personal_graph_repository_provider.dart';
import '../../../graph/presentation/operation_failure_presentation.dart';
import '../../../intention/application/intention_result.dart';
import '../../../intention/domain/intention.dart';
import '../../../intention/domain/intention_id.dart';
import '../../../intention/presentation/catalog/intention_catalog_purpose.dart';
import '../../../intention/presentation/details/intention_details_state.dart';
import '../../../intention/presentation/details/intention_details_view_model.dart';
import '../../application/long_term_relation_command.dart';
import '../../application/long_term_relation_projection.dart';
import '../../domain/long_term_relation.dart';
import '../../domain/long_term_relation_description.dart';
import '../../domain/long_term_relation_id.dart';
import '../details/relation_details_state.dart';
import '../details/relation_details_view_model.dart';
import 'relation_editor_state.dart';
import 'relation_editor_view_model.dart';

/// Форма создания или изменения долговременной связи.
///
/// Типизированный контекст задаёт исходный черновик. Подтверждённые данные
/// участников поступают через наблюдение подробного просмотра связи и
/// выбранных на замену намерений; черновик и результат принадлежат ViewModel,
/// а успех предъявляет presenter оболочки.
@RoutePage()
final class RelationEditorPage extends ConsumerStatefulWidget {
  const RelationEditorPage({required this.editorContext, super.key});

  final RelationEditorContext editorContext;

  @override
  ConsumerState<RelationEditorPage> createState() => _RelationEditorPageState();
}

final class _RelationEditorPageState extends ConsumerState<RelationEditorPage> {
  final _formKey = LongTermRelationCreationFormKey();
  final _replacementSubscriptions =
      <RelationParticipantRole, ProviderSubscription<IntentionDetailsState>>{};
  final _basisReads = <RelationParticipantRole, IntentionId>{};
  late final TextEditingController _descriptionController;

  @override
  void initState() {
    super.initState();
    _descriptionController = TextEditingController(
      text: switch (widget.editorContext) {
        RelationCreationContext() => '',
        RelationEditingContext(:final details) =>
          details.description?.value ?? '',
      },
    );
    if (widget.editorContext case RelationEditingContext(:final details)) {
      final editorProvider = relationEditorViewModelProvider(
        _formKey,
        widget.editorContext,
      );
      void refresh(RelationDetailsState next) {
        if (next case RelationDetailsLoaded(
          refreshStatus: RelationDetailsFresh(),
          :final details,
          :final revision,
        )) {
          final needsNewBasis = ref
              .read(editorProvider.notifier)
              .refreshConfirmedDetails(details, revision);
          for (final role in needsNewBasis) {
            final id = role == RelationParticipantRole.source
                ? details.source.id
                : details.related.id;
            unawaited(_refreshParticipantBasis(role, id));
          }
        }
      }

      final subscription = ref.listenManual(
        relationDetailsViewModelProvider(details.relation.id),
        (previous, next) => refresh(next),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          refresh(subscription.read());
        }
      });
    }
  }

  @override
  void dispose() {
    for (final subscription in _replacementSubscriptions.values) {
      subscription.close();
    }
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final provider = relationEditorViewModelProvider(
      _formKey,
      widget.editorContext,
    );
    final editor = ref.watch(provider);
    final notifier = ref.read(provider.notifier);
    ref.listen(provider, (previous, next) {
      if (next.event case RelationEditorCreated() || RelationEditorUpdated()) {
        notifier.consumeEvent();
        // Сообщение об успехе предъявляет общий presenter оболочки.
        unawaited(context.router.maybePop());
      }
    });

    final isSubmitting = editor.operation is RelationEditorSubmitting;
    final descriptionFailure = _descriptionFailure(localizations, editor);
    final generalFailure = _generalFailure(localizations, editor);
    final occupiedPair = _occupiedPair(editor);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          editor.context is RelationEditingContext
              ? localizations.relationEditorEditTitle
              : localizations.relationEditorTitle,
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _ParticipantSlot(
              role: RelationParticipantRole.source,
              participant: editor.sourceParticipant,
              enabled: !isSubmitting,
              onSelect: () =>
                  unawaited(_selectParticipant(RelationParticipantRole.source)),
              onOpenDetails: editor.sourceParticipant == null
                  ? null
                  : () => unawaited(
                      context.router.push(
                        IntentionDetailsRoute(
                          intentionId: editor.sourceParticipant!.id,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            _ParticipantSlot(
              role: RelationParticipantRole.related,
              participant: editor.relatedParticipant,
              enabled: !isSubmitting,
              onSelect: () => unawaited(
                _selectParticipant(RelationParticipantRole.related),
              ),
              onOpenDetails: editor.relatedParticipant == null
                  ? null
                  : () => unawaited(
                      context.router.push(
                        IntentionDetailsRoute(
                          intentionId: editor.relatedParticipant!.id,
                        ),
                      ),
                    ),
            ),
            if (_relationPhrase(localizations, editor) case final phrase?) ...[
              const SizedBox(height: 24),
              Semantics(
                container: true,
                label: '${localizations.relationEditorPhraseLabel}: $phrase',
                excludeSemantics: true,
                child: Text(
                  phrase,
                  key: const ValueKey('relation-editor-phrase'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
            const SizedBox(height: 24),
            _TypeChoice(
              selected: editor.type,
              enabled: !isSubmitting,
              onSelected: notifier.selectType,
            ),
            const SizedBox(height: 24),
            _PriorityChoice(
              selected: editor.priority,
              enabled: !isSubmitting,
              onSelected: notifier.selectPriority,
            ),
            const SizedBox(height: 24),
            TextField(
              key: const ValueKey('relation-editor-description'),
              controller: _descriptionController,
              enabled: !isSubmitting,
              minLines: 4,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                labelText: localizations.relationEditorDescriptionLabel,
                alignLabelWithHint: true,
                error: descriptionFailure == null
                    ? null
                    : OperationFailurePresentation(
                        claim: editor.failurePresentation,
                        message: descriptionFailure,
                      ),
              ),
              onChanged: notifier.changeDescription,
            ),
            if (generalFailure != null) ...[
              const SizedBox(height: 16),
              OperationFailurePresentation(
                claim: editor.failurePresentation,
                message: generalFailure,
                messageKey: const ValueKey('relation-editor-failure'),
              ),
            ],
            if (occupiedPair case final relationId?) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  key: const ValueKey('relation-editor-open-existing'),
                  onPressed: () => unawaited(
                    context.router.push(
                      RelationDetailsRoute(relationId: relationId),
                    ),
                  ),
                  child: Text(localizations.relationEditorOpenExistingRelation),
                ),
              ),
            ],
            if (editor.completeness
                case final RelationDraftIncomplete draft) ...[
              const SizedBox(height: 16),
              _MissingRequirements(missing: draft.missing),
            ],
            const SizedBox(height: 24),
            FilledButton(
              key: const ValueKey('relation-editor-submit'),
              onPressed: editor.canSubmit ? notifier.submit : null,
              child: Text(_submitLabel(localizations, editor)),
            ),
          ],
        ),
      ),
    );
  }

  /// Открывает выбор участника и применяет только явно выбранное намерение.
  ///
  /// Исключается намерение, уже занятое парой: второй участник, а до его
  /// выбора — текущее значение самой роли. Отмена оставляет черновик прежним.
  Future<void> _selectParticipant(RelationParticipantRole role) async {
    final provider = relationEditorViewModelProvider(
      _formKey,
      widget.editorContext,
    );
    final notifier = ref.read(provider.notifier);
    final draft = ref.read(provider);
    final excluded = switch (role) {
      RelationParticipantRole.source =>
        draft.relatedIntentionId ?? draft.sourceIntentionId,
      RelationParticipantRole.related =>
        draft.sourceIntentionId ?? draft.relatedIntentionId,
    };
    if (excluded == null) {
      return;
    }
    final selected = await context.router
        .push<GraphSnapshot<RelationParticipantSummary>>(
          RelationParticipantPickerRoute(
            excludedIntentionId: excluded,
            selectionContext: switch (draft.editingBasis?.relation.scope) {
              RelationScope.archived =>
                RelationParticipantSelectionContext.archivedRelation,
              RelationScope.active ||
              null => RelationParticipantSelectionContext.activeRelation,
            },
          ),
        );
    if (!mounted || selected == null) {
      return;
    }
    final needsNewBasis = notifier.selectParticipant(role, selected);
    _watchReplacement(role, selected.value.id);
    if (needsNewBasis) {
      unawaited(_refreshParticipantBasis(role, selected.value.id));
    }
  }

  void _watchReplacement(RelationParticipantRole role, IntentionId id) {
    _replacementSubscriptions.remove(role)?.close();
    final editing = widget.editorContext;
    if (editing is! RelationEditingContext) {
      return;
    }
    final originalId = switch (role) {
      RelationParticipantRole.source =>
        editing.details.relation.sourceIntentionId,
      RelationParticipantRole.related =>
        editing.details.relation.relatedIntentionId,
    };
    if (id == originalId) {
      return;
    }
    final editorProvider = relationEditorViewModelProvider(
      _formKey,
      widget.editorContext,
    );
    void refresh(IntentionDetailsState next) {
      if (!mounted || next is! IntentionDetailsLoaded) {
        return;
      }
      final intention = next.intention;
      final needsNewBasis = ref
          .read(editorProvider.notifier)
          .refreshConfirmedParticipant(
            role,
            RelationParticipantSummary(
              id: intention.id,
              title: intention.title,
              archiveState: intention.archiveState,
              activeRelationCount: next.details.activeRelationCount,
            ),
            next.revision,
          );
      if (needsNewBasis) {
        unawaited(_refreshParticipantBasis(role, id));
      }
    }

    final subscription = ref.listenManual(
      intentionDetailsViewModelProvider(id),
      (previous, next) => refresh(next),
    );
    _replacementSubscriptions[role] = subscription;
    refresh(subscription.read());
  }

  Future<void> _refreshParticipantBasis(
    RelationParticipantRole role,
    IntentionId id,
  ) async {
    if (_basisReads[role] == id) {
      return;
    }
    final editorProvider = relationEditorViewModelProvider(
      _formKey,
      widget.editorContext,
    );
    final expectedRevision = ref.read(editorProvider).revisionFor(role);
    if (expectedRevision == null) {
      return;
    }
    _basisReads[role] = id;
    try {
      final result = await ref
          .read(personalGraphRepositoryProvider)
          .watchIntention(id)
          .first;
      if (!mounted) {
        return;
      }
      if (result case ResultSuccess(
        value: GraphSnapshot(value: final details?, :final revision),
      )) {
        final intention = details.intention;
        ref
            .read(editorProvider.notifier)
            .rebaseConfirmedParticipant(
              role,
              GraphSnapshot(
                revision: revision,
                value: RelationParticipantSummary(
                  id: intention.id,
                  title: intention.title,
                  archiveState: intention.archiveState,
                  activeRelationCount: details.activeRelationCount,
                ),
              ),
              expectedRevision,
            );
      }
    } on Object {
      // Последний сравнимый снимок остаётся видимым до следующего подтверждения.
    } finally {
      if (_basisReads[role] == id) {
        _basisReads.remove(role);
      }
    }
  }

  String _submitLabel(
    AppLocalizations localizations,
    RelationEditorState editor,
  ) => switch ((editor.context, editor.operation)) {
    (RelationEditingContext(), RelationEditorSubmitting()) =>
      localizations.relationEditorSaving,
    (RelationCreationContext(), RelationEditorSubmitting()) =>
      localizations.relationEditorCreating,
    (_, RelationEditorFailed()) when editor.canRetry =>
      localizations.commonRetry,
    (RelationEditingContext(), _) => localizations.relationEditorSaveAction,
    (RelationCreationContext(), _) => localizations.relationEditorSubmitAction,
  };

  String? _relationPhrase(
    AppLocalizations localizations,
    RelationEditorState editor,
  ) {
    final source = editor.sourceParticipant;
    final related = editor.relatedParticipant;
    return switch ((source, related, editor.type)) {
      (final source?, final related?, LongTermRelationType.need) =>
        localizations.relationNeighborhoodNeedPhrase(
          source.title,
          related.title,
        ),
      (final source?, final related?, LongTermRelationType.can) =>
        localizations.relationNeighborhoodCanPhrase(
          source.title,
          related.title,
        ),
      _ => null,
    };
  }

  String? _descriptionFailure(
    AppLocalizations localizations,
    RelationEditorState editor,
  ) {
    if (editor.operation case RelationEditorFailed(
      failure: RelationEditorDescriptionInvalid(:final failure),
    )) {
      return switch (failure.reason) {
        LongTermRelationTextValidationReason.tooLong =>
          localizations.relationEditorDescriptionTooLong,
        LongTermRelationTextValidationReason.invalidUnicodeRepertoire =>
          localizations.relationEditorDescriptionInvalidUnicode,
      };
    }
    return null;
  }

  String? _generalFailure(
    AppLocalizations localizations,
    RelationEditorState editor,
  ) {
    final isEditing = editor.context is RelationEditingContext;
    return switch (editor.operation) {
      RelationEditorIdle() ||
      RelationEditorSubmitting() ||
      RelationEditorSucceeded() => null,
      RelationEditorFailed(:final failure) => switch (failure) {
        // Ошибка описания принадлежит своему полю.
        RelationEditorDescriptionInvalid() => null,
        RelationEditorParticipantRejected(:final rejection) =>
          switch (rejection) {
            RelationParticipantRejection.missing =>
              isEditing
                  ? localizations.relationEditorUpdateParticipantNotFound
                  : localizations.relationEditorCreateParticipantNotFound,
            RelationParticipantRejection.archived =>
              isEditing
                  ? localizations.relationEditorUpdateParticipantArchived
                  : localizations.relationEditorCreateParticipantArchived,
          },
        RelationEditorPairOccupied() =>
          isEditing
              ? localizations.relationEditorUpdatePairOccupied
              : localizations.relationEditorCreatePairOccupied,
        RelationEditorSameParticipants() =>
          localizations.relationEditorCreateSameParticipants,
        RelationEditorRelationNotFound() =>
          localizations.relationEditorUpdateNotFound,
        RelationEditorUnavailable() =>
          isEditing
              ? localizations.relationEditorUpdateUnavailable
              : localizations.relationEditorCreateUnavailable,
        RelationEditorCorruption() =>
          isEditing
              ? localizations.relationEditorUpdateCorruption
              : localizations.relationEditorCreateCorruption,
        RelationEditorUnexpected() =>
          isEditing
              ? localizations.relationEditorUpdateUnexpected
              : localizations.relationEditorCreateUnexpected,
      },
    };
  }

  LongTermRelationId? _occupiedPair(RelationEditorState editor) =>
      switch (editor.operation) {
        RelationEditorFailed(
          failure: RelationEditorPairOccupied(:final existingRelationId),
        ) =>
          existingRelationId,
        RelationEditorIdle() ||
        RelationEditorSubmitting() ||
        RelationEditorSucceeded() ||
        RelationEditorFailed() => null,
      };
}

/// Роль участника связи и переход к его выбору.
final class _ParticipantSlot extends StatelessWidget {
  const _ParticipantSlot({
    required this.role,
    required this.participant,
    required this.enabled,
    required this.onSelect,
    required this.onOpenDetails,
  });

  final RelationParticipantRole role;
  final RelationParticipantSummary? participant;
  final bool enabled;
  final VoidCallback onSelect;
  final VoidCallback? onOpenDetails;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final isSelected = participant != null;
    final archiveStateLabel =
        participant?.archiveState == IntentionArchiveState.archived
        ? localizations.detailsArchived
        : localizations.detailsActive;
    final label = switch (role) {
      RelationParticipantRole.source => localizations.relationEditorSourceLabel,
      RelationParticipantRole.related =>
        localizations.relationEditorRelatedLabel,
    };
    final action = switch ((role, isSelected)) {
      (RelationParticipantRole.source, false) =>
        localizations.relationEditorSelectSourceAction,
      (RelationParticipantRole.source, true) =>
        localizations.relationEditorChangeSourceAction,
      (RelationParticipantRole.related, false) =>
        localizations.relationEditorSelectRelatedAction,
      (RelationParticipantRole.related, true) =>
        localizations.relationEditorChangeRelatedAction,
    };
    final actionKey = switch ((role, isSelected)) {
      (RelationParticipantRole.source, false) => const ValueKey(
        'relation-editor-select-source',
      ),
      (RelationParticipantRole.source, true) => const ValueKey(
        'relation-editor-change-source',
      ),
      (RelationParticipantRole.related, false) => const ValueKey(
        'relation-editor-select-related',
      ),
      (RelationParticipantRole.related, true) => const ValueKey(
        'relation-editor-change-related',
      ),
    };
    final detailsKey = switch (role) {
      RelationParticipantRole.source => const ValueKey(
        'relation-editor-open-source-details',
      ),
      RelationParticipantRole.related => const ValueKey(
        'relation-editor-open-related-details',
      ),
    };
    return Semantics(
      key: ValueKey('relation-editor-participant-${role.name}'),
      container: true,
      label: isSelected
          ? '$label: ${participant!.title}, $archiveStateLabel'
          : label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          if (participant case final selected?) ...[
            Text(
              selected.title,
              key: ValueKey('relation-editor-participant-title-${role.name}'),
            ),
            const SizedBox(height: 4),
            Text(
              archiveStateLabel,
              key: ValueKey(
                'relation-editor-participant-archive-state-${role.name}',
              ),
            ),
            const SizedBox(height: 4),
          ],
          Text(
            isSelected
                ? localizations.relationEditorParticipantSelected
                : localizations.relationEditorParticipantNotSelected,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton(
                key: actionKey,
                onPressed: enabled ? onSelect : null,
                child: Text(action),
              ),
              if (isSelected)
                IconButton(
                  key: detailsKey,
                  icon: const Icon(Icons.info_outline),
                  tooltip: localizations.participantPickerOpenDetails,
                  onPressed: onOpenDetails,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

final class _TypeChoice extends StatelessWidget {
  const _TypeChoice({
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final LongTermRelationType? selected;
  final bool enabled;
  final ValueChanged<LongTermRelationType> onSelected;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return _ChoiceSection(
      label: localizations.relationEditorTypeLabel,
      children: [
        for (final type in LongTermRelationType.values)
          ChoiceChip(
            key: ValueKey('relation-editor-type-${type.name}'),
            label: Text(switch (type) {
              LongTermRelationType.need => localizations.relationEditorTypeNeed,
              LongTermRelationType.can => localizations.relationEditorTypeCan,
            }),
            selected: type == selected,
            onSelected: enabled ? (_) => onSelected(type) : null,
          ),
      ],
    );
  }
}

final class _PriorityChoice extends StatelessWidget {
  const _PriorityChoice({
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final RelationPriority? selected;
  final bool enabled;
  final ValueChanged<RelationPriority> onSelected;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return _ChoiceSection(
      label: localizations.relationEditorPriorityLabel,
      children: [
        for (final priority in RelationPriority.values)
          ChoiceChip(
            key: ValueKey('relation-editor-priority-${priority.name}'),
            label: Text(
              localizations.relationEditorPriorityOption(
                priority.name.toUpperCase(),
              ),
            ),
            selected: priority == selected,
            onSelected: enabled ? (_) => onSelected(priority) : null,
          ),
      ],
    );
  }
}

final class _ChoiceSection extends StatelessWidget {
  const _ChoiceSection({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: label,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: children),
      ],
    ),
  );
}

/// Объяснение обязательного выбора, без которого связь не может быть создана.
final class _MissingRequirements extends StatelessWidget {
  const _MissingRequirements({required this.missing});

  final Set<RelationDraftRequirement> missing;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Semantics(
      container: true,
      liveRegion: true,
      child: Column(
        key: const ValueKey('relation-editor-missing'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(localizations.relationEditorMissingTitle),
          const SizedBox(height: 4),
          for (final requirement in RelationDraftRequirement.values)
            if (missing.contains(requirement))
              Text(switch (requirement) {
                RelationDraftRequirement.sourceParticipant =>
                  localizations.relationEditorMissingSource,
                RelationDraftRequirement.relatedParticipant =>
                  localizations.relationEditorMissingRelated,
                RelationDraftRequirement.type =>
                  localizations.relationEditorMissingType,
                RelationDraftRequirement.priority =>
                  localizations.relationEditorMissingPriority,
              }),
        ],
      ),
    );
  }
}
