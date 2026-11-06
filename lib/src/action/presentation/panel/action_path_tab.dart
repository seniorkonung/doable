import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart' hide Badge;

import '../../../../l10n/app_localizations.dart';
import '../../../app/routing/app_router.gr.dart';
import '../../../design_system/components/action_path.dart' as ui;
import '../../../design_system/components/badge.dart';
import '../../../design_system/doable_metrics.dart';
import '../../../design_system/doable_priority.dart';
import '../../../intention/domain/intention.dart';
import '../../../long_term_relation/domain/long_term_relation.dart';
import '../../../long_term_relation/presentation/details/relation_details_sheet.dart';
import '../../application/action_details.dart';
import 'action_field_labels.dart';

/// В пути есть архивное намерение или архивная связь. Удалённые отметки вкладки
/// не несут.
bool actionPathHasArchive(ActionSavedPath path) =>
    _isArchived(path.root) ||
    path.steps.any(
      (step) => _isArchivedLink(step.link) || _isArchived(step.intention),
    );

/// Отметка корневого намерения после его названия в шапке: «В архиве»,
/// «Удалено» или ничего у активного.
Widget? actionPathRootBadge(
  AppLocalizations localizations,
  ActionPathIntention root,
) => switch (root) {
  DeletedActionPathIntention() => Badge.deletedInline(
    word: localizations.actionPathDeletedBadge,
  ),
  _ when _isArchived(root) => Badge.archivedInline(
    word: localizations.detailsArchived,
  ),
  _ => null,
};

bool _isArchived(ActionPathIntention intention) => switch (intention) {
  ExistingActionPathIntention(:final intention) =>
    intention.archiveState == IntentionArchiveState.archived,
  DeletedActionPathIntention() => false,
};

bool _isArchivedLink(ActionPathLink link) => switch (link) {
  ExistingActionPathLink(:final relation) =>
    relation.scope == RelationScope.archived,
  DeletedActionPathLink() => false,
};

/// Вкладка «Путь»: сохранённый путь действия только для чтения.
///
/// Существующее намерение, в том числе архивное, открывает свою страницу
/// поверх панели, а существующая связь — подробный просмотр; возврат с них
/// оставляет панель на этой вкладке. Удалённые намерения и связи не
/// открываются.
final class ActionPathTab extends StatelessWidget {
  const ActionPathTab({required this.details, super.key});

  final ActionDetails details;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final path = details.path;
    final steps = path.steps;
    final lastIndex = steps.length;

    ui.ActionPathStep step(ActionPathIntention value, int index) {
      switch (value) {
        case ExistingActionPathIntention(:final intention):
          final archived =
              intention.archiveState == IntentionArchiveState.archived;
          final role = switch (index) {
            0 => localizations.actionPathRoleRoot,
            _ when index == lastIndex => localizations.actionPathRoleFinal,
            _ => localizations.actionPathRoleIntermediate,
          };
          return ui.ActionPathStep.existing(
            name: intention.title,
            semanticLabel: [
              role,
              intention.title,
              if (archived) localizations.detailsArchived,
            ].join(', '),
            archived: archived,
            onOpen: () => unawaited(
              context.router.push(
                IntentionDetailsRoute(intentionId: intention.id),
              ),
            ),
          );
        case DeletedActionPathIntention(:final title):
          return ui.ActionPathStep.deleted(name: title);
      }
    }

    ui.ActionPathLink link(int index) {
      final stepAt = steps[index];
      final kind = switch (stepAt.link.type) {
        LongTermRelationType.need => ui.ActionPathRelationKind.need,
        LongTermRelationType.can => ui.ActionPathRelationKind.can,
      };
      final relation = switch (stepAt.link) {
        ExistingActionPathLink(:final relation) =>
          ui.ActionPathRelation.existing(
            kind: kind,
            priority: _designPriority(relation.priority),
            semanticLabel: [
              localizations.actionPathRelationLabel(
                _kindWord(localizations, kind),
                index == 0 ? path.root.title : steps[index - 1].intention.title,
                stepAt.intention.title,
                localizations.actionPriorityOption(
                  actionPriorityName(_designPriority(relation.priority)),
                ),
              ),
              if (relation.scope == RelationScope.archived)
                localizations.detailsArchived,
            ].join(', '),
            archived: relation.scope == RelationScope.archived,
            onOpen: () =>
                unawaited(showRelationDetailsSheet(context, relation.id)),
          ),
        DeletedActionPathLink() => ui.ActionPathRelation.deleted(kind: kind),
      };
      return ui.ActionPathLink(
        relation: relation,
        step: step(stepAt.intention, index + 1),
      );
    }

    return SliverPadding(
      // Вместе с нижним полем полосы вкладок даёт 6 под областью их нажатия.
      padding: const EdgeInsets.fromLTRB(
        DoableMetrics.space5,
        2,
        DoableMetrics.space5,
        DoableMetrics.space4,
      ),
      sliver: SliverToBoxAdapter(
        child: ui.ActionPath(
          root: step(path.root, 0),
          links: [
            for (var index = 0; index < steps.length; index++) link(index),
          ],
          priority: actionDesignPriority(details.action.priority),
          done: details.action.isCompleted,
          kindWord: (kind) => _kindWord(localizations, kind),
          archivedBadge: Badge.archived(word: localizations.detailsArchived),
          deletedBadge: Badge.deleted(
            word: localizations.actionPathDeletedBadge,
          ),
          notes: ui.ActionPathNotes(
            archived: localizations.actionPathNoteArchived,
            deleted: localizations.actionPathNoteDeleted,
            archivedAndDeleted: localizations.actionPathNoteArchivedAndDeleted,
          ),
        ),
      ),
    );
  }
}

String _kindWord(
  AppLocalizations localizations,
  ui.ActionPathRelationKind kind,
) => switch (kind) {
  ui.ActionPathRelationKind.need => localizations.relationNeighborhoodTypeNeed,
  ui.ActionPathRelationKind.can => localizations.relationNeighborhoodTypeCan,
};

DoablePriority _designPriority(RelationPriority priority) => switch (priority) {
  RelationPriority.p1 => DoablePriority.p1,
  RelationPriority.p2 => DoablePriority.p2,
  RelationPriority.p3 => DoablePriority.p3,
  RelationPriority.p4 => DoablePriority.p4,
};
