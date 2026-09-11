import 'dart:async';

sealed class ExclusiveOperationStart<TResult> {
  const ExclusiveOperationStart();
}

final class ExclusiveOperationAccepted<TResult>
    extends ExclusiveOperationStart<TResult> {
  const ExclusiveOperationAccepted(this.future);

  final Future<TResult> future;
}

final class ExclusiveOperationAlreadyRunning<TResult>
    extends ExclusiveOperationStart<TResult> {
  const ExclusiveOperationAlreadyRunning();
}

final class ExclusiveOperation<TResult> {
  var _isRunning = false;

  bool get isRunning => _isRunning;

  ExclusiveOperationStart<TResult> start(FutureOr<TResult> Function() action) {
    if (_isRunning) {
      return const ExclusiveOperationAlreadyRunning();
    }

    _isRunning = true;
    final future = Future<TResult>.sync(action).whenComplete(() {
      _isRunning = false;
    });
    return ExclusiveOperationAccepted(future);
  }
}
