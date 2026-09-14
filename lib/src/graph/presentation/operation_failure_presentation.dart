import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/presentation/presentation_frame_evidence.dart';
import '../application/graph_command_coordinator.dart';

/// Подтверждает initiator claim ошибки, когда её сообщение [child] фактически
/// доступно в видимой части текущего маршрута.
final class OperationFailurePresentation extends ConsumerWidget {
  const OperationFailurePresentation({
    required this.claim,
    required this.child,
    super.key,
  });

  final IntentionInitiatorPresentationClaim? claim;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      PresentationFrameEvidence<IntentionInitiatorPresentationClaim>(
        subject: claim,
        onPresented: ref
            .read(graphCommandCoordinatorProvider.notifier)
            .confirmPresentation,
        child: child,
      );
}
