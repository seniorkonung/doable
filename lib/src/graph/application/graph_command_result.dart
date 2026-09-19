import 'graph_revision.dart';

enum GraphFailureCategory {
  validation,
  notFound,
  conflict,
  unavailable,
  corruption,
  unexpected,
}

abstract interface class GraphCommandFailure {
  GraphFailureCategory get category;
}

abstract interface class GraphCommand<
  T extends GraphCommandOutcome,
  F extends GraphCommandFailure
> {}

sealed class GraphResult<T, F extends GraphCommandFailure> {
  const GraphResult();
}

final class GraphResultSuccess<T, F extends GraphCommandFailure>
    extends GraphResult<T, F> {
  const GraphResultSuccess(this.value);

  final T value;
}

final class GraphResultFailure<T, F extends GraphCommandFailure>
    extends GraphResult<T, F> {
  const GraphResultFailure(this.failure);

  final F failure;
}

typedef GraphCommandResult<
  T extends GraphCommandOutcome,
  F extends GraphCommandFailure
> = GraphResult<ConfirmedGraphResult<T>, F>;

typedef GraphCommandSucceeded<
  T extends GraphCommandOutcome,
  F extends GraphCommandFailure
> = GraphResultSuccess<ConfirmedGraphResult<T>, F>;

typedef GraphCommandFailed<
  T extends GraphCommandOutcome,
  F extends GraphCommandFailure
> = GraphResultFailure<ConfirmedGraphResult<T>, F>;
