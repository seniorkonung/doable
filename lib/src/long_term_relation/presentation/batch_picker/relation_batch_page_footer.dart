import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/button.dart';
import '../../../design_system/components/docked_footer.dart';
import '../../../graph/application/graph_change.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../intention/domain/intention.dart';
import '../../../intention/domain/intention_id.dart';
import '../../../intention/presentation/catalog/pair_occupant_reconciliation.dart';
import '../../application/intention_relation_group.dart';
import '../../application/relation_pair_probe.dart';
import '../relation_group_name.dart';
import 'relation_batch_view_model.dart';

/// Строка поиска участника, стрелка которой открыла страницу намерения.
final class RelationBatchRowContext {
  const RelationBatchRowContext({
    required this.batch,
    required this.group,
    required this.probe,
    required this.occupant,
  });

  final RelationBatchViewModelProvider batch;
  final IntentionRelationGroup group;
  final RelationPairProbe probe;

  /// Связь, занимавшая пару строки при открытии страницы.
  final PairOccupant? occupant;
}

/// Кнопка отметки на месте панели навигации страницы, открытой стрелкой.
///
/// Виджет живёт всё время страницы, в том числе без данных [intention]:
/// занятость он согласует своей подпиской, потому что строка могла уйти из
/// выдачи поиска.
final class RelationBatchPageFooter extends ConsumerStatefulWidget {
  const RelationBatchPageFooter({
    required this.row,
    required this.intentionId,
    required this.intention,
    super.key,
  });

  final RelationBatchRowContext row;
  final IntentionId intentionId;
  final Intention? intention;

  @override
  ConsumerState<RelationBatchPageFooter> createState() =>
      _RelationBatchPageFooterState();
}

final class _RelationBatchPageFooterState
    extends ConsumerState<RelationBatchPageFooter> {
  late final StreamSubscription<ConfirmedGraphChangePackage> _changes;
  late PairOccupant? _occupant = widget.row.occupant;

  @override
  void initState() {
    super.initState();
    _changes = ref.read(relationBatchChangesProvider).listen(_onPackage);
  }

  @override
  void dispose() {
    unawaited(_changes.cancel());
    super.dispose();
  }

  void _onPackage(ConfirmedGraphChangePackage package) {
    final id = widget.intentionId;
    final occupant = reconcilePairOccupants(
      probe: widget.row.probe,
      occupants: {id: ?_occupant},
      rowIds: {id},
      changes: package.changes.whereType<LongTermRelationChange>(),
    )[id];
    if (occupant != _occupant) setState(() => _occupant = occupant);
  }

  void _toggle(Intention intention) {
    ref.read(widget.row.batch.notifier).toggle(intention.id, intention.title);
    unawaited(context.router.maybePop());
  }

  @override
  Widget build(BuildContext context) {
    final intention = widget.intention;
    if (intention == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final chosen = ref.watch(
      widget.row.batch.select(
        (batch) =>
            batch.selected.any((selection) => selection.id == intention.id),
      ),
    );
    return DockedFooter(
      child: switch ((intention.archiveState, _occupant, chosen)) {
        (IntentionArchiveState.archived, _, _) => Button.primary(
          label: l10n.batchPageArchived,
          onPressed: null,
        ),
        (IntentionArchiveState.active, final occupant?, _) => Button.primary(
          label: relationPairReasonName(
            l10n,
            RelationPairReason.from(
              group: widget.row.group,
              occupant: occupant,
            ),
          ),
          onPressed: null,
        ),
        (IntentionArchiveState.active, null, true) => Button.quietBlock(
          label: l10n.batchPageRemove,
          onPressed: () => _toggle(intention),
        ),
        (IntentionArchiveState.active, null, false) => Button.primary(
          label: l10n.batchPageAdd,
          onPressed: () => _toggle(intention),
        ),
      },
    );
  }
}
