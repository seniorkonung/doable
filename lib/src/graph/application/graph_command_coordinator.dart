import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../intention/application/intention_command.dart';
import '../../intention/application/intention_repository.dart';
import '../../intention/application/intention_result.dart';
import '../../intention/domain/intention_id.dart';
import '../../shared/presentation/exclusive_operation.dart';
import 'graph_revision.dart';
import 'personal_graph_repository.dart';
import 'personal_graph_repository_provider.dart';

part 'graph_command_coordinator.g.dart';

enum IntentionCommandKind {
  create,
  update,
  enableReadiness,
  disableReadiness,
  archive,
  restore,
  delete,
}

sealed class GraphCommandKey {
  const GraphCommandKey();
}

final class IntentionCreationFormKey extends GraphCommandKey {
  IntentionCreationFormKey();
}

final class ExistingIntentionKey extends GraphCommandKey {
  const ExistingIntentionKey(this.intentionId);

  final IntentionId intentionId;

  @override
  bool operator ==(Object other) =>
      other is ExistingIntentionKey && other.intentionId == intentionId;

  @override
  int get hashCode => intentionId.hashCode;
}

final class IntentionOperationToken {
  IntentionOperationToken._();

  @override
  String toString() => 'IntentionOperationToken';
}

final class IntentionCommandCompletion {
  const IntentionCommandCompletion._({
    required this.token,
    required this.kind,
    required this.target,
    required this.confirmedResult,
  });

  final IntentionOperationToken token;
  final IntentionCommandKind kind;
  final IntentionOperationTarget target;
  final Result<ConfirmedGraphResult<IntentionCommandSuccess>> confirmedResult;

  Result<IntentionCommandSuccess> get result => switch (confirmedResult) {
    ResultSuccess(:final value) => ResultSuccess(value.value),
    ResultFailure(:final failure) => ResultFailure(failure),
  };

  GraphRevision? get revision => switch (confirmedResult) {
    ResultSuccess(:final value) => value.revision,
    ResultFailure() => null,
  };

  String? get presentationTitle => switch (result) {
    ResultSuccess(value: IntentionSaved(:final intention)) => intention.title,
    ResultSuccess(value: IntentionDeleted()) ||
    ResultFailure() => switch (target) {
      ExistingIntentionOperationTarget(:final title) => title,
      CreatingIntentionOperationTarget() ||
      UnlabelledIntentionOperationTarget() => null,
    },
  };
}

sealed class IntentionOperationTarget {
  const IntentionOperationTarget();
}

final class CreatingIntentionOperationTarget extends IntentionOperationTarget {
  const CreatingIntentionOperationTarget();
}

final class ExistingIntentionOperationTarget extends IntentionOperationTarget {
  const ExistingIntentionOperationTarget({
    required this.intentionId,
    required this.title,
  });

  final IntentionId intentionId;
  final String title;
}

@Deprecated('Передавайте presentationTitle при принятии команды.')
final class UnlabelledIntentionOperationTarget
    extends IntentionOperationTarget {
  const UnlabelledIntentionOperationTarget(this.intentionId);

  final IntentionId intentionId;
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

final class IntentionAppPresentationClaim extends IntentionPresentationClaim {
  const IntentionAppPresentationClaim._(
    super.token,
    super.completion,
    super._entry,
  ) : super._();
}

@Deprecated('Используйте IntentionAppPresentationClaim.')
typedef IntentionCatalogFallbackPresentationClaim =
    IntentionAppPresentationClaim;

@Riverpod(keepAlive: true)
final class GraphCommandCoordinator extends _$GraphCommandCoordinator {
  final _completionController =
      StreamController<IntentionCommandCompletion>.broadcast(sync: true);
  final _entries = <IntentionOperationToken, _PresentationEntry>{};
  final _gates =
      <
        GraphCommandKey,
        ExclusiveOperation<
          Result<ConfirmedGraphResult<IntentionCommandSuccess>>
        >
      >{};
  final _inFlight = <Future<void>>{};
  late GraphCommandRepository _repository;
  Future<void> _publicationTail = Future<void>.value();
  var _isDraining = false;
  Completer<void>? _shutdownCompleter;

  @override
  void build() {
    _repository = ref.watch(personalGraphRepositoryProvider);
  }

  Stream<IntentionCommandCompletion> get completions =>
      _completionController.stream;

  bool isRunning(IntentionId intentionId) =>
      isKeyRunning(ExistingIntentionKey(intentionId));

  bool isKeyRunning(GraphCommandKey key) => _gates[key]?.isRunning ?? false;

  IntentionCommandStart acceptCreation(
    IntentionCreationFormKey formKey,
    CreateIntention command,
  ) => _accept(formKey, command, const CreatingIntentionOperationTarget());

  IntentionCommandStart acceptExisting(
    ExistingIntentionCommand command, {
    String? presentationTitle,
  }) => _accept(
    ExistingIntentionKey(command.id),
    command,
    presentationTitle == null
        ? UnlabelledIntentionOperationTarget(command.id)
        : ExistingIntentionOperationTarget(
            intentionId: command.id,
            title: presentationTitle,
          ),
  );

  @Deprecated('Используйте acceptCreation с ключом формы или acceptExisting.')
  IntentionCommandStart accept(IntentionCommand command) => switch (command) {
    CreateIntention() => acceptCreation(IntentionCreationFormKey(), command),
    ExistingIntentionCommand() => acceptExisting(command),
  };

  IntentionCommandStart _accept(
    GraphCommandKey key,
    IntentionCommand command,
    IntentionOperationTarget target,
  ) {
    if (_isDraining) {
      return const IntentionCommandCoordinatorDraining();
    }

    final gate = _gates.putIfAbsent(
      key,
      ExclusiveOperation<Result<ConfirmedGraphResult<IntentionCommandSuccess>>>
          .new,
    );
    if (gate.isRunning) {
      return const IntentionCommandAlreadyRunning();
    }

    final token = IntentionOperationToken._();
    final entry = _PresentationEntry(
      token: token,
      kind: _kindOf(command),
      target: target,
      completionCompleter: Completer<IntentionCommandCompletion>(),
    );
    _entries[token] = entry;

    final started = gate.start(() => _execute(command));
    if (started
        is ExclusiveOperationAlreadyRunning<
          Result<ConfirmedGraphResult<IntentionCommandSuccess>>
        >) {
      _entries.remove(token);
      return const IntentionCommandAlreadyRunning();
    }
    final operation =
        started
            as ExclusiveOperationAccepted<
              Result<ConfirmedGraphResult<IntentionCommandSuccess>>
            >;
    final operationFuture = operation.future;

    unawaited(
      operationFuture.whenComplete(() {
        if (identical(_gates[key], gate) && !gate.isRunning) {
          _gates.remove(key);
        }
      }),
    );

    late final Future<void> tracked;
    final publication = _publicationTail.then<void>((_) async {
      final result = await operationFuture;
      _publishCompletion(entry, result);
    });
    _publicationTail = publication;
    tracked = publication.whenComplete(() {
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

  Future<IntentionAppPresentationClaim?> claimAppPresentation(
    IntentionOperationToken token,
  ) {
    final entry = _entries[token];
    if (entry == null || entry.fallbackRequest != null) {
      return Future.value(null);
    }

    final request = Completer<IntentionAppPresentationClaim?>();
    entry.fallbackRequest = request;
    if (entry.initiatorReleased && entry.completion != null) {
      _grantFallback(entry);
    }
    return request.future;
  }

  @Deprecated('Используйте claimAppPresentation.')
  Future<IntentionCatalogFallbackPresentationClaim?> claimCatalogFallback(
    IntentionOperationToken token,
  ) => claimAppPresentation(token);

  void releaseInitiatorPresentation(IntentionOperationToken token) {
    final entry = _entries[token];
    if (entry == null || entry.initiatorReleased) {
      return;
    }

    entry.initiatorReleased = true;
    entry.initiatorClaim = null;
    if (entry.completion != null && entry.fallbackRequest != null) {
      _grantFallback(entry);
    }
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
      case IntentionAppPresentationClaim():
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

  Future<Result<ConfirmedGraphResult<IntentionCommandSuccess>>> _execute(
    IntentionCommand command,
  ) async {
    try {
      return await _repository.execute(command);
    } on Object {
      return const ResultFailure<ConfirmedGraphResult<IntentionCommandSuccess>>(
        IntentionUnexpectedFailure(),
      );
    }
  }

  void _publishCompletion(
    _PresentationEntry entry,
    Result<ConfirmedGraphResult<IntentionCommandSuccess>> confirmedResult,
  ) {
    final completion = IntentionCommandCompletion._(
      token: entry.token,
      kind: entry.kind,
      target: entry.target,
      confirmedResult: confirmedResult,
    );
    entry.completion = completion;
    _completionController.add(completion);
    entry.completionCompleter.complete(completion);

    if (entry.initiatorReleased && entry.fallbackRequest != null) {
      _grantFallback(entry);
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

    final claim = IntentionAppPresentationClaim._(
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
    required this.target,
    required this.completionCompleter,
  });

  final IntentionOperationToken token;
  final IntentionCommandKind kind;
  final IntentionOperationTarget target;
  final Completer<IntentionCommandCompletion> completionCompleter;
  IntentionCommandCompletion? completion;
  bool initiatorReleased = false;
  IntentionInitiatorPresentationClaim? initiatorClaim;
  Completer<IntentionAppPresentationClaim?>? fallbackRequest;
  IntentionAppPresentationClaim? fallbackClaim;
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
