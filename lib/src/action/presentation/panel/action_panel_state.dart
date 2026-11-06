import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_revision.dart';
import '../../application/action_details.dart';
import '../../application/action_result.dart';

sealed class ActionPanelState {
  const ActionPanelState();
}

final class ActionPanelLoading extends ActionPanelState {
  const ActionPanelLoading();
}

final class ActionPanelLoaded extends ActionPanelState {
  const ActionPanelLoaded(this.details, this.revision);

  final ActionDetails details;
  final GraphRevision revision;
}

final class ActionPanelNotFound extends ActionPanelState {
  const ActionPanelNotFound();
}

final class ActionPanelUnavailable extends ActionPanelState {
  const ActionPanelUnavailable();
}

final class ActionPanelCorruption extends ActionPanelState {
  const ActionPanelCorruption();
}

final class ActionPanelUnexpected extends ActionPanelState {
  const ActionPanelUnexpected();
}

/// Записывающая операция действия. Живёт отдельно от снимка: новые значения
/// приходят только из подписки, а отказ снимает только следующая операция.
sealed class ActionPanelOperation {
  const ActionPanelOperation();
}

final class ActionPanelOperationIdle extends ActionPanelOperation {
  const ActionPanelOperationIdle();
}

final class ActionPanelOperationWriting extends ActionPanelOperation {
  const ActionPanelOperationWriting();
}

/// Собственное изменение подтверждено, но подписка ещё не показала снимок с
/// ревизией не старше [revision]. Панель недоступна, как во время записи.
final class ActionPanelOperationAwaitingSnapshot extends ActionPanelOperation {
  const ActionPanelOperationAwaitingSnapshot(this.revision);

  final GraphRevision revision;
}

final class ActionPanelOperationFailed extends ActionPanelOperation {
  const ActionPanelOperationFailed(this.failure, {this.failurePresentation});

  final ActionCommandFailure failure;
  final GraphInitiatorPresentationClaim? failurePresentation;
}
