import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../shared/presentation/exclusive_operation.dart';
import '../../application/intention_command.dart';
import '../../application/intention_repository.dart';
import '../../application/intention_result.dart';
import '../../domain/intention_id.dart';

part 'intention_command_coordinator.g.dart';

enum IntentionCommandKind {
  create,
  update,
  enableReadiness,
  disableReadiness,
  archive,
  restore,
  delete,
}

final class IntentionOperationToken {
  IntentionOperationToken._();

  @override
  String toString() => 'IntentionOperationToken';
}

final class IntentionCommandCompletion {
  const IntentionCommandCompletion({
    required this.token,
    required this.kind,
    required this.result,
  });

  final IntentionOperationToken token;
  final IntentionCommandKind kind;
  final Result<IntentionCommandSuccess> result;
}

sealed class IntentionCommandStart {
  const IntentionCommandStart();
}

final class IntentionCommandAccepted extends IntentionCommandStart {
  const IntentionCommandAccepted({required this.token, required this.future});

  final IntentionOperationToken token;
  final Future<IntentionCommandCompletion> future;
}

final class IntentionCommandAlreadyRunning extends IntentionCommandStart {
  const IntentionCommandAlreadyRunning();
}

final class IntentionCommandCoordinatorDraining extends IntentionCommandStart {
  const IntentionCommandCoordinatorDraining();
}

sealed class IntentionPresentationClaim {
  const IntentionPresentationClaim._(this.token, this.completion, this._entry);

  final IntentionOperationToken token;
  final IntentionCommandCompletion completion;
  final _PresentationEntry _entry;
}

final class IntentionInitiatorPresentationClaim
    extends IntentionPresentationClaim {
  const IntentionInitiatorPresentationClaim._(
    super.token,
    super.completion,
    super._entry,
  ) : super._();
}

final class IntentionCatalogFallbackPresentationClaim
    extends IntentionPresentationClaim {
  const IntentionCatalogFallbackPresentationClaim._(
    super.token,
    super.completion,
    super._entry,
  ) : super._();
}

@Riverpod(keepAlive: true)
final class IntentionCommandCoordinator extends _$IntentionCommandCoordinator {
  final _completionController =
      StreamController<IntentionCommandCompletion>.broadcast(sync: true);
  final _entries = <IntentionOperationToken, _PresentationEntry>{};
  final _gates =
      <IntentionId, ExclusiveOperation<Result<IntentionCommandSuccess>>>{};
  final _inFlight = <Future<void>>{};
  late IntentionRepository _repository;
  var _isDraining = false;
  Completer<void>? _shutdownCompleter;

  @override
  void build(IntentionRepository repository) {
    _repository = repository;
  }

  Stream<IntentionCommandCompletion> get completions =>
      _completionController.stream;

  bool isRunning(IntentionId intentionId) =>
      _gates[intentionId]?.isRunning ?? false;

  IntentionCommandStart accept(IntentionCommand command) {
    if (_isDraining) {
      return const IntentionCommandCoordinatorDraining();
    }

    final intentionId = _intentionIdOf(command);
    final gate = intentionId == null
        ? ExclusiveOperation<Result<IntentionCommandSuccess>>()
        : _gates.putIfAbsent(
            intentionId,
            ExclusiveOperation<Result<IntentionCommandSuccess>>.new,
          );
    if (gate.isRunning) {
      return const IntentionCommandAlreadyRunning();
    }

    final token = IntentionOperationToken._();
    final entry = _PresentationEntry(
      token: token,
      kind: _kindOf(command),
      completionCompleter: Completer<IntentionCommandCompletion>(),
    );
    _entries[token] = entry;

    final started = gate.start(() => _execute(command));
    if (started
        is ExclusiveOperationAlreadyRunning<Result<IntentionCommandSuccess>>) {
      _entries.remove(token);
      return const IntentionCommandAlreadyRunning();
    }
    final operation =
        started as ExclusiveOperationAccepted<Result<IntentionCommandSuccess>>;

    late final Future<void> tracked;
    tracked = operation.future
        .then<void>((result) {
          _publishCompletion(entry, result);
        })
        .whenComplete(() {
          if (intentionId != null &&
              identical(_gates[intentionId], gate) &&
              !gate.isRunning) {
            _gates.remove(intentionId);
          }
          _inFlight.remove(tracked);
          _completeShutdownIfDrained();
        });
    _inFlight.add(tracked);

    return IntentionCommandAccepted(
      token: token,
      future: entry.completionCompleter.future,
    );
  }

  IntentionInitiatorPresentationClaim? claimInitiator(
    IntentionOperationToken token,
  ) {
    final entry = _entries[token];
    final completion = entry?.completion;
    if (entry == null ||
        completion == null ||
        entry.initiatorReleased ||
        entry.fallbackClaim != null) {
      return null;
    }

    return entry.initiatorClaim ??= IntentionInitiatorPresentationClaim._(
      token,
      completion,
      entry,
    );
  }

  Future<IntentionCatalogFallbackPresentationClaim?> claimCatalogFallback(
    IntentionOperationToken token,
  ) {
    final entry = _entries[token];
    if (entry == null || entry.fallbackRequest != null) {
      return Future.value(null);
    }

    final request = Completer<IntentionCatalogFallbackPresentationClaim?>();
    entry.fallbackRequest = request;
    if (entry.initiatorReleased && entry.completion != null) {
      _grantFallback(entry);
    }
    return request.future;
  }

  void releaseInitiatorPresentation(IntentionOperationToken token) {
    final entry = _entries[token];
    if (entry == null || entry.initiatorReleased) {
      return;
    }

    entry.initiatorReleased = true;
    entry.initiatorClaim = null;
    if (entry.completion == null) {
      return;
    }
    if (entry.fallbackRequest == null) {
      if (entry.isPublishingCompletion) {
        return;
      }
      _discardEntry(entry);
      return;
    }
    _grantFallback(entry);
  }

  void confirmPresentation(IntentionPresentationClaim claim) {
    final entry = _entries[claim.token];
    if (!identical(entry, claim._entry)) {
      return;
    }

    switch (claim) {
      case IntentionInitiatorPresentationClaim():
        if (!identical(entry!.initiatorClaim, claim)) {
          return;
        }
        _discardEntry(entry);
      case IntentionCatalogFallbackPresentationClaim():
        if (!identical(entry!.fallbackClaim, claim)) {
          return;
        }
        _discardEntry(entry);
    }
  }

  Future<void> shutdown() {
    final existing = _shutdownCompleter;
    if (existing != null) {
      return existing.future;
    }

    _isDraining = true;
    final shutdown = Completer<void>();
    _shutdownCompleter = shutdown;
    _completeShutdownIfDrained();
    return shutdown.future;
  }

  Future<Result<IntentionCommandSuccess>> _execute(
    IntentionCommand command,
  ) async {
    try {
      return await _repository.execute(command);
    } on Object {
      return const ResultFailure<IntentionCommandSuccess>(
        IntentionUnexpectedFailure(),
      );
    }
  }

  void _publishCompletion(
    _PresentationEntry entry,
    Result<IntentionCommandSuccess> result,
  ) {
    final completion = IntentionCommandCompletion(
      token: entry.token,
      kind: entry.kind,
      result: result,
    );
    entry.completion = completion;
    entry.isPublishingCompletion = true;
    try {
      _completionController.add(completion);
    } finally {
      entry.isPublishingCompletion = false;
    }
    entry.completionCompleter.complete(completion);

    if (entry.initiatorReleased) {
      if (entry.fallbackRequest == null) {
        _discardEntry(entry);
      } else {
        _grantFallback(entry);
      }
    }
  }

  void _grantFallback(_PresentationEntry entry) {
    final completion = entry.completion;
    final request = entry.fallbackRequest;
    if (completion == null ||
        request == null ||
        request.isCompleted ||
        entry.fallbackClaim != null) {
      return;
    }

    final claim = IntentionCatalogFallbackPresentationClaim._(
      entry.token,
      completion,
      entry,
    );
    entry.fallbackClaim = claim;
    request.complete(claim);
  }

  void _discardEntry(_PresentationEntry entry) {
    if (!identical(_entries[entry.token], entry)) {
      return;
    }
    final fallbackRequest = entry.fallbackRequest;
    if (fallbackRequest != null && !fallbackRequest.isCompleted) {
      fallbackRequest.complete(null);
    }
    _entries.remove(entry.token);
  }

  void _completeShutdownIfDrained() {
    final shutdown = _shutdownCompleter;
    if (shutdown == null || shutdown.isCompleted || _inFlight.isNotEmpty) {
      return;
    }

    for (final entry in _entries.values.toList(growable: false)) {
      _discardEntry(entry);
    }
    _gates.clear();
    unawaited(_completionController.close());
    shutdown.complete();
  }
}

final class _PresentationEntry {
  _PresentationEntry({
    required this.token,
    required this.kind,
    required this.completionCompleter,
  });

  final IntentionOperationToken token;
  final IntentionCommandKind kind;
  final Completer<IntentionCommandCompletion> completionCompleter;
  IntentionCommandCompletion? completion;
  bool isPublishingCompletion = false;
  bool initiatorReleased = false;
  IntentionInitiatorPresentationClaim? initiatorClaim;
  Completer<IntentionCatalogFallbackPresentationClaim?>? fallbackRequest;
  IntentionCatalogFallbackPresentationClaim? fallbackClaim;
}

IntentionCommandKind _kindOf(IntentionCommand command) => switch (command) {
  CreateIntention() => IntentionCommandKind.create,
  UpdateIntention() => IntentionCommandKind.update,
  EnableIntentionReadiness() => IntentionCommandKind.enableReadiness,
  DisableIntentionReadiness() => IntentionCommandKind.disableReadiness,
  ArchiveIntention() => IntentionCommandKind.archive,
  RestoreIntention() => IntentionCommandKind.restore,
  DeleteIntention() => IntentionCommandKind.delete,
};

IntentionId? _intentionIdOf(IntentionCommand command) => switch (command) {
  CreateIntention() => null,
  UpdateIntention(:final id) ||
  EnableIntentionReadiness(:final id) ||
  DisableIntentionReadiness(:final id) ||
  ArchiveIntention(:final id) ||
  RestoreIntention(:final id) ||
  DeleteIntention(:final id) => id,
};
