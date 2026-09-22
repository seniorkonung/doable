import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/presentation/presentation_frame_evidence.dart';
import '../application/graph_command_coordinator.dart';

/// Рисует локализованное сообщение ошибки и владеет её initiator claim до
/// первого пригодного кадра либо исчезновения этого renderer.
///
/// Узкий интерфейс не позволяет внешнему виджету подменить собственную область
/// сообщения при проверке фактического предъявления.
final class OperationFailurePresentation extends ConsumerStatefulWidget {
  const OperationFailurePresentation({
    required this.claim,
    required this.message,
    this.messageKey,
    super.key,
  });

  final GraphInitiatorPresentationClaim? claim;
  final String message;
  final Key? messageKey;

  @override
  ConsumerState<OperationFailurePresentation> createState() =>
      _OperationFailurePresentationState();
}

final class _OperationFailureRenderer {
  const _OperationFailureRenderer(this.claim);

  final GraphInitiatorPresentationClaim? claim;
}

final class _OperationFailurePresentationState
    extends ConsumerState<OperationFailurePresentation> {
  late final GraphCommandCoordinator _coordinator;
  late _OperationFailureRenderer _renderer;
  GraphInitiatorPresentationClaim? _confirmedClaim;
  GraphInitiatorPresentationClaim? _releasedClaim;

  @override
  void initState() {
    super.initState();
    _coordinator = ref.read(graphCommandCoordinatorProvider.notifier);
    _renderer = _OperationFailureRenderer(widget.claim);
  }

  @override
  void didUpdateWidget(OperationFailurePresentation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.claim, widget.claim)) {
      _releaseIfPending(oldWidget.claim);
      _renderer = _OperationFailureRenderer(widget.claim);
    }
  }

  @override
  void dispose() {
    _releaseIfPending(widget.claim);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final claim = widget.claim;
    final mayConfirm =
        claim != null &&
        !identical(claim, _confirmedClaim) &&
        !identical(claim, _releasedClaim);
    return PresentationFrameEvidence<_OperationFailureRenderer>(
      key: ObjectKey(_renderer),
      subject: mayConfirm ? _renderer : null,
      onPresented: _confirm,
      child: Semantics(
        key: widget.messageKey,
        container: true,
        liveRegion: true,
        label: widget.message,
        child: ExcludeSemantics(
          child: Text(
            widget.message,
            style: DefaultTextStyle.of(context).style
                .copyWith(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ),
    );
  }

  void _confirm(_OperationFailureRenderer renderer) {
    if (!identical(renderer, _renderer)) {
      return;
    }
    final claim = renderer.claim;
    if (claim == null ||
        identical(claim, _releasedClaim) ||
        identical(claim, _confirmedClaim)) {
      return;
    }
    _confirmedClaim = claim;
    _coordinator.confirmPresentation(claim);
  }

  void _releaseIfPending(GraphInitiatorPresentationClaim? claim) {
    if (claim == null ||
        identical(claim, _confirmedClaim) ||
        identical(claim, _releasedClaim)) {
      return;
    }
    _releasedClaim = claim;
    _coordinator.releaseInitiatorClaim(claim);
  }
}
