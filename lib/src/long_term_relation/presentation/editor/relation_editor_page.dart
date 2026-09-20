import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/routing/app_router.gr.dart';
import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/presentation/operation_failure_presentation.dart';
import '../../../intention/domain/intention_id.dart';
import '../../application/long_term_relation_command.dart';
import '../../domain/long_term_relation.dart';
import '../../domain/long_term_relation_description.dart';
import '../../domain/long_term_relation_id.dart';
import 'relation_editor_state.dart';
import 'relation_editor_view_model.dart';

/// Форма создания долговременной связи из выбранной группы соседства.
///
/// Контекст группы задаёт роль текущего намерения, но оба участника остаются
/// заменяемыми: второй выбирается в общем каталоге намерений. Тип и приоритет
/// выбираются явно, а описание сохраняется целиком. Страница не читает граф
/// самостоятельно: черновик и результат принадлежат ViewModel, а сообщение об
/// успехе предъявляет общий presenter оболочки.
@RoutePage()
final class RelationEditorPage extends ConsumerStatefulWidget {
  const RelationEditorPage({required this.creationContext, super.key});

  final RelationCreationContext creationContext;

  @override
  ConsumerState<RelationEditorPage> createState() => _RelationEditorPageState();
}

final class _RelationEditorPageState extends ConsumerState<RelationEditorPage> {
  final _formKey = LongTermRelationCreationFormKey();
  final _descriptionController = TextEditingController();

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final provider = relationEditorViewModelProvider(
      _formKey,
      widget.creationContext,
    );
    final editor = ref.watch(provider);
    final notifier = ref.read(provider.notifier);
    ref.listen(provider, (previous, next) {
      if (next.event case RelationEditorCreated()) {
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
      appBar: AppBar(title: Text(localizations.relationEditorTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _ParticipantSlot(
              role: RelationParticipantRole.source,
              intentionId: editor.sourceIntentionId,
              enabled: !isSubmitting,
              onSelect: () =>
                  unawaited(_selectParticipant(RelationParticipantRole.source)),
            ),
            const SizedBox(height: 16),
            _ParticipantSlot(
              role: RelationParticipantRole.related,
              intentionId: editor.relatedIntentionId,
              enabled: !isSubmitting,
              onSelect: () => unawaited(
                _selectParticipant(RelationParticipantRole.related),
              ),
            ),
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
      widget.creationContext,
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
    final selected = await context.router.push<IntentionId>(
      RelationParticipantPickerRoute(excludedIntentionId: excluded),
    );
    if (!mounted || selected == null) {
      return;
    }
    notifier.selectParticipant(role, selected);
  }

  String _submitLabel(
    AppLocalizations localizations,
    RelationEditorState editor,
  ) => switch (editor.operation) {
    RelationEditorSubmitting() => localizations.relationEditorCreating,
    RelationEditorFailed() when editor.canRetry => localizations.commonRetry,
    RelationEditorIdle() ||
    RelationEditorFailed() ||
    RelationEditorSucceeded() => localizations.relationEditorSubmitAction,
  };

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
  ) => switch (editor.operation) {
    RelationEditorIdle() ||
    RelationEditorSubmitting() ||
    RelationEditorSucceeded() => null,
    RelationEditorFailed(:final failure) => switch (failure) {
      // Ошибка описания принадлежит своему полю.
      RelationEditorDescriptionInvalid() => null,
      RelationEditorParticipantRejected(:final rejection) =>
        switch (rejection) {
          RelationParticipantRejection.missing =>
            localizations.relationEditorCreateParticipantNotFound,
          RelationParticipantRejection.archived =>
            localizations.relationEditorCreateParticipantArchived,
        },
      RelationEditorPairOccupied() =>
        localizations.relationEditorCreatePairOccupied,
      RelationEditorSameParticipants() =>
        localizations.relationEditorCreateSameParticipants,
      RelationEditorUnavailable() =>
        localizations.relationEditorCreateUnavailable,
      RelationEditorCorruption() =>
        localizations.relationEditorCreateCorruption,
      RelationEditorUnexpected() =>
        localizations.relationEditorCreateUnexpected,
    },
  };

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
    required this.intentionId,
    required this.enabled,
    required this.onSelect,
  });

  final RelationParticipantRole role;
  final IntentionId? intentionId;
  final bool enabled;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final isSelected = intentionId != null;
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Text(
          isSelected
              ? localizations.relationEditorParticipantSelected
              : localizations.relationEditorParticipantNotSelected,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            key: actionKey,
            onPressed: enabled ? onSelect : null,
            child: Text(action),
          ),
        ),
      ],
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
