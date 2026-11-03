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
import '../../../intention/presentation/catalog/intention_catalog_state.dart';
import '../../../intention/presentation/catalog/intention_catalog_view_model.dart';
import '../../../intention/presentation/editor/intention_creation_launch.dart';
import '../../../intention/presentation/picker/intention_picker_view.dart';
import '../../application/intention_relation_group.dart';
import '../../application/relation_pair_probe.dart';
import '../relation_command_failure_message.dart';
import 'relation_batch_page_footer.dart';
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
  bool _confirmingClose = false;
  bool _openingCreation = false;

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
            if (_openingCreation || !ref.read(provider).canEdit) return;
            _openingCreation = true;
            unawaited(() async {
              try {
                await context.router.push(
                  IntentionEditorRoute(
                    launch: IntentionCreationForSearch(
                      initialTitle: title,
                      onCreated: (id, createdTitle) {
                        if (!mounted || !ref.read(provider).canEdit) return;
                        ref
                            .read(provider.notifier)
                            .acceptCreated(id, createdTitle);
                        clearTitle();
                      },
                    ),
                  ),
                );
              } finally {
                _openingCreation = false;
              }
            }());
          },
        ),
        onOpenDetails: (id) {
          if (!ref.read(provider).canEdit) return;
          final catalog = ref
              .read(intentionCatalogViewModelProvider(_purpose))
              .value;
          unawaited(
            context.router.push(
              IntentionDetailsRoute(
                intentionId: id,
                batchRow: RelationBatchRowContext(
                  batch: provider,
                  group: widget.group,
                  probe: _purpose.pairProbe,
                  // Строки со стрелкой строит только загруженная выдача.
                  occupant: catalog is IntentionCatalogLoaded
                      ? catalog.pairOccupants[id]
                      : null,
                ),
              ),
            ),
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
            onPressed: batch.canSubmit
                ? ref.read(provider.notifier).submit
                : null,
          ),
        ),
      ),
    );
  }
}
