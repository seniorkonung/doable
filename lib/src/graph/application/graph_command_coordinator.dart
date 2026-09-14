import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../intention/application/intention_command.dart';
import '../../intention/application/intention_catalog.dart';
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
      CreatingIntentionOperationTarget() => null,
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

final class GraphCommandCoordinatorDraining extends IntentionCommandStart {
  const GraphCommandCoordinatorDraining();
}

/// Исключительное право конкретного владельца предъявить terminal outcome.
///
/// Удержание claim само по себе не означает предъявления: подтверждать его
/// может только компонент, получивший свидетельство первого доступного кадра.
sealed class IntentionPresentationClaim {
  const IntentionPresentationClaim._(this.token, this.completion, this._entry);

  final IntentionOperationToken token;
  final IntentionCommandCompletion completion;
  final _PresentationEntry _entry;
}

/// Право открытой экранной сессии предъявить собственную ошибку.
final class IntentionInitiatorPresentationClaim
    extends IntentionPresentationClaim {
  const IntentionInitiatorPresentationClaim._(
    super.token,
    super.completion,
    super._entry,
  ) : super._();
}

/// Право оболочки предъявить success либо fallback-ошибку.
final class IntentionAppPresentationClaim extends IntentionPresentationClaim {
  const IntentionAppPresentationClaim._(
    super.token,
    super.completion,
    super._entry,
    this._registration,
  ) : super._();

  final GraphAppPresentationRegistration _registration;
}

/// Регистрация получателя общего app-канала предъявления.
///
/// Одновременно выдачу получает только самая ранняя действующая регистрация,
/// и у неё не больше одного неподтверждённого claim. Освобождение возвращает
/// coordinator выданный неподтверждённый claim и ожидающий запрос.
final class GraphAppPresentationRegistration {
  GraphAppPresentationRegistration._(this._coordinator);

  final GraphCommandCoordinator _coordinator;
  Completer<IntentionAppPresentationClaim?>? _request;
  IntentionAppPresentationClaim? _issued;
  var _isReleased = false;

  /// Запрашивает следующий доступный app-результат в порядке публикации.
  ///
  /// Возвращает `null`, если регистрация освобождена или coordinator завершил
  /// работу до выдачи.
  Future<IntentionAppPresentationClaim?> nextClaim() =>
      _coordinator._requestAppClaim(this);

  void release() => _coordinator._releaseRegistration(this);
}

@Riverpod(keepAlive: true)
final class GraphCommandCoordinator extends _$GraphCommandCoordinator {
  final _completionController =
      StreamController<IntentionCommandCompletion>.broadcast(sync: true);
  // Публикация завершений последовательна в порядке принятия, поэтому порядок
  // вставки совпадает с порядком публикации terminal outcome.
  final _entries = <IntentionOperationToken, _PresentationEntry>{};
  final _registrations = <GraphAppPresentationRegistration>[];
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
    required String presentationTitle,
  }) => _accept(
    ExistingIntentionKey(command.id),
    command,
    ExistingIntentionOperationTarget(
      intentionId: command.id,
      title: presentationTitle,
    ),
  );

  IntentionCommandStart _accept(
    GraphCommandKey key,
    IntentionCommand command,
    IntentionOperationTarget target,
  ) {
    if (_isDraining) {
      return const GraphCommandCoordinatorDraining();
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

  /// Выдаёт открытой экранной сессии право предъявить её failure.
  ///
  /// Success инициатору не выдаётся: он сразу принадлежит оболочке. После
  /// освобождения сессии или выдачи права оболочке возвращает `null`.
  IntentionInitiatorPresentationClaim? claimInitiatorFailure(
    IntentionOperationToken token,
  ) {
    final entry = _entries[token];
    final completion = entry?.completion;
    if (entry == null ||
        completion == null ||
        completion.result is! ResultFailure<IntentionCommandSuccess> ||
        entry.initiatorReleased ||
        entry.appClaim != null) {
      return null;
    }

    return entry.initiatorClaim ??= IntentionInitiatorPresentationClaim._(
      token,
      completion,
      entry,
    );
  }

  /// Завершает экранную сессию инициатора.
  ///
  /// Неподтверждённая ошибка становится доступной оболочке в своём прежнем
  /// порядке; прежний initiator claim больше не может её подтвердить.
  void releaseInitiatorPresentation(IntentionOperationToken token) {
    final entry = _entries[token];
    if (entry == null || entry.initiatorReleased) {
      return;
    }

    _releaseInitiatorEntry(entry);
  }

  /// Освобождает право только пока [claim] остаётся действующим правом
  /// инициатора.
  ///
  /// Запоздалый renderer прежнего claim не может освободить право, уже
  /// переданное другому владельцу.
  void releaseInitiatorClaim(IntentionInitiatorPresentationClaim claim) {
    final entry = _entries[claim.token];
    if (entry == null || !identical(entry.initiatorClaim, claim)) {
      return;
    }

    _releaseInitiatorEntry(entry);
  }

  void _releaseInitiatorEntry(_PresentationEntry entry) {
    entry.initiatorReleased = true;
    entry.initiatorClaim = null;
    _dispatchAppPresentation();
  }

  GraphAppPresentationRegistration registerAppPresentation() {
    final registration = GraphAppPresentationRegistration._(this);
    if (_shutdownCompleter?.isCompleted ?? false) {
      registration._isReleased = true;
    } else {
      _registrations.add(registration);
    }
    return registration;
  }

  /// Атомарно подтверждает фактическое предъявление действующим владельцем.
  ///
  /// Claim освобождённого или сменившегося владельца бездействует.
  void confirmPresentation(IntentionPresentationClaim claim) {
    final entry = _entries[claim.token];
    if (entry == null || !identical(entry, claim._entry)) {
      return;
    }

    switch (claim) {
      case IntentionInitiatorPresentationClaim():
        if (!identical(entry.initiatorClaim, claim)) {
          return;
        }
        _discardEntry(entry);
      case IntentionAppPresentationClaim(:final _registration):
        if (!identical(entry.appClaim, claim)) {
          return;
        }
        if (identical(_registration._issued, claim)) {
          _registration._issued = null;
        }
        _discardEntry(entry);
        _dispatchAppPresentation();
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

  Future<IntentionAppPresentationClaim?> _requestAppClaim(
    GraphAppPresentationRegistration registration,
  ) {
    if (registration._isReleased) {
      return Future.value(null);
    }
    final existing = registration._request;
    if (existing != null) {
      return existing.future;
    }

    final request = Completer<IntentionAppPresentationClaim?>();
    registration._request = request;
    _dispatchAppPresentation();
    return request.future;
  }

  void _releaseRegistration(GraphAppPresentationRegistration registration) {
    if (registration._isReleased) {
      return;
    }
    registration._isReleased = true;
    _registrations.remove(registration);

    final issued = registration._issued;
    registration._issued = null;
    if (issued != null && identical(issued._entry.appClaim, issued)) {
      issued._entry.appClaim = null;
    }
    final request = registration._request;
    registration._request = null;
    if (request != null && !request.isCompleted) {
      request.complete(null);
    }
    _dispatchAppPresentation();
  }

  void _dispatchAppPresentation() {
    if (_registrations.isEmpty) {
      return;
    }
    final active = _registrations.first;
    final request = active._request;
    if (request == null || active._issued != null) {
      return;
    }
    final entry = _nextAppPresentableEntry();
    final completion = entry?.completion;
    if (entry == null || completion == null) {
      return;
    }

    final claim = IntentionAppPresentationClaim._(
      entry.token,
      completion,
      entry,
      active,
    );
    entry.appClaim = claim;
    active._issued = claim;
    active._request = null;
    request.complete(claim);
  }

  _PresentationEntry? _nextAppPresentableEntry() {
    for (final entry in _entries.values) {
      final completion = entry.completion;
      if (completion == null || entry.appClaim != null) {
        continue;
      }
      final belongsToApp = switch (completion.result) {
        ResultSuccess() => true,
        ResultFailure() => entry.initiatorReleased,
      };
      if (belongsToApp) {
        return entry;
      }
    }
    return null;
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
    _dispatchAppPresentation();
  }

  void _discardEntry(_PresentationEntry entry) {
    if (identical(_entries[entry.token], entry)) {
      _entries.remove(entry.token);
    }
  }

  void _completeShutdownIfDrained() {
    final shutdown = _shutdownCompleter;
    if (shutdown == null || shutdown.isCompleted || _inFlight.isNotEmpty) {
      return;
    }

    _entries.clear();
    for (final registration in _registrations.toList(growable: false)) {
      registration._isReleased = true;
      registration._issued = null;
      final request = registration._request;
      registration._request = null;
      if (request != null && !request.isCompleted) {
        request.complete(null);
      }
    }
    _registrations.clear();
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
  IntentionAppPresentationClaim? appClaim;
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
