import '../../../l10n/app_localizations.dart';
import '../application/intention_relation_group.dart';
import '../application/relation_pair_probe.dart';
import '../domain/long_term_relation.dart';

String relationGroupName(AppLocalizations l10n, IntentionRelationGroup group) =>
    switch (group) {
      IntentionRelationGroup.needs => l10n.detailsRelationsGroupNeeds,
      IntentionRelationGroup.canUse => l10n.detailsRelationsGroupCanUse,
      IntentionRelationGroup.neededFor => l10n.detailsRelationsGroupNeededFor,
      IntentionRelationGroup.canBeUsedFor =>
        l10n.detailsRelationsGroupCanBeUsedFor,
    };

String relationPairReasonName(
  AppLocalizations l10n,
  RelationPairReason reason,
) => switch (reason) {
  RelationPairSameGroup(scope: RelationScope.active) =>
    l10n.relationPairAlreadyAdded,
  RelationPairSameGroup(scope: RelationScope.archived) =>
    l10n.relationPairAlreadyAddedArchived,
  RelationPairOtherGroup(:final group, scope: RelationScope.active) =>
    l10n.relationPairOtherGroup(relationGroupName(l10n, group)),
  RelationPairOtherGroup(:final group, scope: RelationScope.archived) =>
    l10n.relationPairOtherGroupArchived(relationGroupName(l10n, group)),
};
