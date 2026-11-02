import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/routing/app_router.gr.dart';
import '../../../intention/domain/intention_id.dart';
import '../../../intention/presentation/catalog/intention_catalog_purpose.dart';
import '../../../intention/presentation/picker/intention_picker_view.dart';
import '../../application/intention_relation_group.dart';
import '../../application/relation_pair_probe.dart';
import 'relation_batch_view_model.dart';

/// Поиск участников одной группы с отметками на время жизни страницы.
@RoutePage()
final class RelationBatchPickerPage extends ConsumerStatefulWidget {
  const RelationBatchPickerPage({
    required this.pageIntentionId,
    required this.pageTitle,
    required this.group,
    super.key,
  });

  final IntentionId pageIntentionId;
  final String pageTitle;
  final IntentionRelationGroup group;

  @override
  ConsumerState<RelationBatchPickerPage> createState() =>
      _RelationBatchPickerPageState();
}

final class _RelationBatchPickerPageState
    extends ConsumerState<RelationBatchPickerPage> {
  final _session = IntentionSearchSession();

  late final _purpose = SelectRelationParticipant(
    session: _session,
    pairProbe: RelationPairProbe.forGroup(
      intentionId: widget.pageIntentionId,
      group: widget.group,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final provider = relationBatchViewModelProvider(
      _session,
      widget.pageIntentionId,
      widget.pageTitle,
    );
    final batch = ref.watch(provider);
    return IntentionPickerView(
      purpose: _purpose,
      closeLabel: l10n.participantPickerCancel,
      emptyScopeMessage: l10n.participantPickerEmpty,
      onClose: () => unawaited(context.router.maybePop()),
      rowBehavior: IntentionPickerCheckable(
        group: widget.group,
        selectedIds: {for (final selection in batch.selected) selection.id},
        onToggle: (pick) =>
            ref.read(provider.notifier).toggle(pick.value.id, pick.value.title),
      ),
      onOpenDetails: (id) => unawaited(
        context.router.push(IntentionDetailsRoute(intentionId: id)),
      ),
    );
  }
}
