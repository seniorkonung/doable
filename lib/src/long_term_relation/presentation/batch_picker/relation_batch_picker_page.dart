import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/routing/app_router.gr.dart';
import '../../../design_system/components/button.dart';
import '../../../design_system/components/confirm_dialog.dart';
import '../../../design_system/components/docked_footer.dart';
import '../../../design_system/components/notice.dart';
import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/presentation/operation_failure_presentation.dart';
import '../../../intention/domain/intention_id.dart';
import '../../../intention/presentation/catalog/intention_catalog_purpose.dart';
import '../../../intention/presentation/editor/intention_creation_launch.dart';
import '../../../intention/presentation/picker/intention_picker_view.dart';
import '../../application/intention_relation_group.dart';
import '../../application/relation_pair_probe.dart';
import '../../domain/long_term_relation.dart';
import '../relation_command_failure_message.dart';
import 'relation_batch_picker_purpose.dart';
import 'relation_batch_state.dart';
import 'relation_batch_view_model.dart';

/// Поиск участников одной группы с отметками на время жизни страницы.
@RoutePage()
final class RelationBatchPickerPage extends ConsumerStatefulWidget {
  const RelationBatchPickerPage({
    required this.pageIntentionId,
    required this.pageTitle,
    required this.group,
    this.anchor = const RelationBatchPageAnchor(),
    super.key,
  });

  final IntentionId pageIntentionId;
  final String pageTitle;
  final IntentionRelationGroup group;
  final RelationBatchAnchor anchor;

  @override
  ConsumerState<RelationBatchPickerPage> createState() =>
      _RelationBatchPickerPageState();
}

final class _RelationBatchPickerPageState
    extends ConsumerState<RelationBatchPickerPage> {
  final _session = IntentionSearchSession();
  bool _confirmingClose = false;

  late final _purpose = SelectRelationParticipant(
    session: _session,
    pairProbe: RelationPairProbe.forGroup(
      intentionId: widget.pageIntentionId,
      group: widget.group,
    ),
  );

  /// Исход добавления якорь пути получает из самой команды: уход с поиска во
  /// время записи его не теряет.
  void _submit(RelationBatchViewModelProvider provider) {
    final added = ref.read(provider.notifier).submit();
    if (widget.anchor case RelationBatchPathEndAnchor(:final onAdded)) {
      unawaited(
        added.then((relations) {
          if (relations != null) onAdded(relations);
        }),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final provider = relationBatchViewModelProvider(
      _session,
      widget.pageIntentionId,
      widget.group,
      widget.pageTitle,
    );
    final batch = ref.watch(provider);
    ref.listen(provider, (previous, next) {
      if (next.operation is RelationBatchAdded &&
          previous?.operation is! RelationBatchAdded) {
        // removeRoute снимает маршрут по его matchId, что бы ни стояло над ним:
        // https://pub.dev/documentation/auto_route/11.1.0/auto_route/StackRouter/removeRoute.html
        context.router.removeRoute(context.routeData);
      }
    });
    return PopScope<void>(
      canPop: batch.selected.isEmpty || !batch.canEdit,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          ref.read(provider.notifier).leave();
        } else if (batch.selected.isNotEmpty &&
            batch.canEdit &&
            !_confirmingClose) {
          _confirmingClose = true;
          unawaited(() async {
            final discard = await showDiscardDialog(
              context: context,
              title: l10n.batchDiscardTitle,
              text: [
                l10n.batchDiscardMessage(batch.selected.length),
                if (batch.hasCreatedIntentions) l10n.batchCreatedRemain,
              ].join(' '),
              discardLabel: l10n.batchDiscardAction,
              keepLabel: l10n.batchContinueAction,
            );
            _confirmingClose = false;
            if (discard && context.mounted) {
              ref.read(provider.notifier).leave();
              context.router.removeRoute(context.routeData);
            }
          }());
        }
      },
      child: IntentionPickerView(
        purpose: _purpose,
        purposeDescription: relationBatchPickerPurpose(
          l10n,
          widget.group,
          widget.anchor,
          provider,
          batch.selected.length,
        ),
        closeLabel: l10n.participantPickerCancel,
        emptyScopeMessage: l10n.participantPickerEmpty,
        onClose: () => unawaited(context.router.maybePop()),
        rowBehavior: IntentionPickerCheckable(
          group: widget.group,
          selectedIds: {for (final selection in batch.selected) selection.id},
          onToggle: (pick) => ref
              .read(provider.notifier)
              .toggle(pick.value.id, pick.value.title),
          onCreate: (title, clearTitle) {
            final router = context.router;
            final pickerMatchId = context.routeData.matchId;
            if (!ref.read(provider).canEdit ||
                router.stackData
                    .skipWhile((entry) => entry.matchId != pickerMatchId)
                    .skip(1)
                    .any((entry) => entry.name == IntentionEditorRoute.name)) {
              return;
            }
            unawaited(
              router.push(
                IntentionEditorRoute(
                  launch: IntentionCreationForSearch(
                    initialTitle: title,
                    placement: switch (widget.group.direction) {
                      RelationDirection.outgoing =>
                        CreatedIntentionPlacement.belowPage,
                      RelationDirection.incoming =>
                        CreatedIntentionPlacement.abovePage,
                    },
                    onCreated: (id, createdTitle, kind) {
                      if (!mounted || !ref.read(provider).canEdit) return;
                      ref
                          .read(provider.notifier)
                          .acceptCreated(id, createdTitle, kind);
                      if (widget.anchor case RelationBatchPathEndAnchor(
                        :final onIntentionCreated,
                      )) {
                        onIntentionCreated();
                      }
                      clearTitle();
                    },
                  ),
                ),
              ),
            );
          },
        ),
        onOpenDetails: (id) {
          if (!ref.read(provider).canEdit) return;
          unawaited(
            context.router.push(IntentionDetailsRoute(intentionId: id)),
          );
        },
        notice: switch (batch.operation) {
          RelationBatchFailed(:final failure, :final claim) => Notice.content(
            message: OperationFailurePresentation(
              claim: claim,
              message: longTermRelationCommandFailureMessage(
                l10n,
                LongTermRelationCommandKind.add,
                failure,
              ),
              inheritsColor: true,
            ),
          ),
          RelationBatchIdle() ||
          RelationBatchSubmitting() ||
          RelationBatchAdded() => null,
        },
        footer: DockedFooter(
          child: Button.primary(
            label: switch (batch.operation) {
              RelationBatchSubmitting() ||
              RelationBatchAdded() => l10n.batchAdding,
              RelationBatchIdle() ||
              RelationBatchFailed() => switch (batch.selected.length) {
                0 => l10n.batchAddNone,
                final count => l10n.batchAddCount(count),
              },
            },
            onPressed: batch.canSubmit ? () => _submit(provider) : null,
          ),
        ),
      ),
    );
  }
}
