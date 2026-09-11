import '../../application/intention_result.dart';

sealed class OperationState<TResult> {
  const OperationState();
}

final class OperationIdle<TResult> extends OperationState<TResult> {
  const OperationIdle();
}

final class OperationRunning<TResult> extends OperationState<TResult> {
  const OperationRunning();
}

final class OperationSucceeded<TResult> extends OperationState<TResult> {
  const OperationSucceeded(this.value);

  final TResult value;
}

final class OperationFailed<TResult> extends OperationState<TResult> {
  const OperationFailed(this.failure);

  final IntentionFailure failure;
}
