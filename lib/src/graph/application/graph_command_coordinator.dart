import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../daily_choice/application/daily_choice_command.dart';
import '../../daily_choice/application/daily_choice_result.dart';
import '../../daily_choice/domain/daily_choice_id.dart';
import '../../intention/application/intention_command.dart';
import '../../intention/application/intention_catalog.dart';
import '../../intention/application/intention_result.dart';
import '../../intention/domain/intention_id.dart';
import '../../long_term_relation/application/long_term_relation_command.dart';
import '../../long_term_relation/domain/long_term_relation_id.dart';
import '../../tag/application/tag_command.dart';
import '../../tag/application/tag_result.dart';
import '../../tag/domain/tag_id.dart';
import 'blocking_relation_reference.dart';
import 'delete_blocking_relations.dart';
import 'graph_command_result.dart';
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

final class LongTermRelationCreationFormKey extends GraphCommandKey {
  LongTermRelationCreationFormKey();
}

final class ExistingLongTermRelationKey extends GraphCommandKey {
  const ExistingLongTermRelationKey(this.relationId);

  final LongTermRelationId relationId;

  @override
  bool operator ==(Object other) =>
      other is ExistingLongTermRelationKey && other.relationId == relationId;

  @override
  int get hashCode => relationId.hashCode;
}

final class DailyChoiceCreationFormKey extends GraphCommandKey {
  DailyChoiceCreationFormKey();
}

final class ExistingDailyChoiceKey extends GraphCommandKey {
  const ExistingDailyChoiceKey(this.choiceId);

  final DailyChoiceId choiceId;

  @override
  bool operator ==(Object other) =>
      other is ExistingDailyChoiceKey && other.choiceId == choiceId;

  @override
  int get hashCode => Object.hash(ExistingDailyChoiceKey, choiceId);
}

final class TagCreationFormKey extends GraphCommandKey {
  TagCreationFormKey();
}

final class ExistingTagKey extends GraphCommandKey {
  const ExistingTagKey(this.tagId);

  final TagId tagId;

  @override
  bool operator ==(Object other) =>
      other is ExistingTagKey && other.tagId == tagId;

  @override
  int get hashCode => Object.hash(ExistingTagKey, tagId);
}

sealed class GraphOperationToken {
  const GraphOperationToken();
}

final class IntentionOperationToken extends GraphOperationToken {
  IntentionOperationToken._();

  @override
  String toString() => 'IntentionOperationToken';
}

final class LongTermRelationOperationToken extends GraphOperationToken {
  LongTermRelationOperationToken._();

  @override
  String toString() => 'LongTermRelationOperationToken';
}

final class BlockingRelationsDeleteOperationToken extends GraphOperationToken {
  BlockingRelationsDeleteOperationToken._();

  @override
  String toString() => 'BlockingRelationsDeleteOperationToken';
}

final class DailyChoiceOperationToken extends GraphOperationToken {
  DailyChoiceOperationToken._();

  @override
  String toString() => 'DailyChoiceOperationToken';
}

final class TagOperationToken extends GraphOperationToken {
  TagOperationToken._();

  @override
  String toString() => 'TagOperationToken';
}

sealed class GraphCommandCompletion {
  const GraphCommandCompletion();

  GraphOperationToken get token;
  ConfirmedGraphChangePackage? get confirmedChange;

  GraphRevision? get revision => confirmedChange?.revision;

  /// Отличает отказ от успеха без знания конкретной предметной операции.
  ///
  /// Владение предъявлением одинаково для намерений и связей: успех сразу
  /// принадлежит оболочке, а отказ — открытой экранной сессии инициатора.
  bool get isFailure;
}

final class IntentionCommandCompletion extends GraphCommandCompletion {
  const IntentionCommandCompletion._({
    required this.token,
    required this.kind,
    required this.target,
    required this.confirmedResult,
  });

  @override
  final IntentionOperationToken token;
  final IntentionCommandKind kind;
  final IntentionOperationTarget target;
  final Result<ConfirmedGraphResult<IntentionCommandSuccess>> confirmedResult;

  Result<IntentionCommandSuccess> get result => switch (confirmedResult) {
    ResultSuccess(:final value) => ResultSuccess(value.value),
    ResultFailure(:final failure) => ResultFailure(failure),
  };

  @override
  ConfirmedGraphChangePackage? get confirmedChange => switch (confirmedResult) {
    ResultSuccess(:final value) => value,
    ResultFailure() => null,
  };

  @override
  bool get isFailure => switch (confirmedResult) {
    ResultSuccess() => false,
    ResultFailure() => true,
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

enum LongTermRelationCommandKind { create, update, archive, restore, delete }

final class LongTermRelationCommandCompletion extends GraphCommandCompletion {
  const LongTermRelationCommandCompletion._({
    required this.token,
    required this.kind,
    required this.target,
    required this.confirmedResult,
  });

  @override
  final LongTermRelationOperationToken token;
  final LongTermRelationCommandKind kind;
  final LongTermRelationOperationTarget target;
  final LongTermRelationCommandResult confirmedResult;

  GraphResult<LongTermRelationCommandSuccess, LongTermRelationCommandFailure>
  get result => switch (confirmedResult) {
    GraphResultSuccess(:final value) => GraphResultSuccess(value.value),
    GraphResultFailure(:final failure) => GraphResultFailure(failure),
  };

  @override
  ConfirmedGraphChangePackage? get confirmedChange => switch (confirmedResult) {
    GraphResultSuccess(:final value) => value,
    GraphResultFailure() => null,
  };

  @override
  bool get isFailure => switch (confirmedResult) {
    GraphResultSuccess() => false,
    GraphResultFailure() => true,
  };
}

final class BlockingRelationsDeleteCompletion extends GraphCommandCompletion {
  const BlockingRelationsDeleteCompletion._({
    required this.token,
    required this.intentionId,
    required this.presentationTitle,
    required this.result,
  });

  @override
  final BlockingRelationsDeleteOperationToken token;
  final IntentionId intentionId;
  final String presentationTitle;
  final DeleteBlockingRelationsResult result;

  @override
  ConfirmedGraphChangePackage? get confirmedChange => switch (result) {
    GraphResultSuccess(:final value) => value,
    GraphResultFailure() => null,
  };

  @override
  bool get isFailure => switch (result) {
    GraphResultSuccess() => false,
    GraphResultFailure() => true,
  };
}

enum DailyChoiceCommandKind { create, update, replace, delete }

final class DailyChoiceCommandCompletion extends GraphCommandCompletion {
  const DailyChoiceCommandCompletion._({
    required this.token,
    required this.kind,
    required this.confirmedResult,
  });

  @override
  final DailyChoiceOperationToken token;
  final DailyChoiceCommandKind kind;
  final DailyChoiceCommandResult confirmedResult;

  GraphResult<DailyChoiceCommandSuccess, DailyChoiceCommandFailure>
  get result => switch (confirmedResult) {
    GraphResultSuccess(:final value) => GraphResultSuccess(value.value),
    GraphResultFailure(:final failure) => GraphResultFailure(failure),
  };

  @override
  ConfirmedGraphChangePackage? get confirmedChange => switch (confirmedResult) {
    GraphResultSuccess(:final value) => value,
    GraphResultFailure() => null,
  };

  @override
  bool get isFailure => confirmedResult is GraphResultFailure;
}

enum TagCommandKind { create, rename, delete }

final class TagCommandCompletion extends GraphCommandCompletion {
  const TagCommandCompletion._({
    required this.token,
    required this.kind,
    required this.confirmedResult,
  });

  @override
  final TagOperationToken token;
  final TagCommandKind kind;
  final TagCommandResult confirmedResult;

  GraphResult<TagCommandSuccess, TagCommandFailure> get result =>
      switch (confirmedResult) {
        GraphResultSuccess(:final value) => GraphResultSuccess(value.value),
        GraphResultFailure(:final failure) => GraphResultFailure(failure),
      };

  @override
  ConfirmedGraphChangePackage? get confirmedChange => switch (confirmedResult) {
    GraphResultSuccess(:final value) => value,
    GraphResultFailure() => null,
  };

  @override
  bool get isFailure => confirmedResult is GraphResultFailure;
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

sealed class LongTermRelationOperationTarget {
  const LongTermRelationOperationTarget();
}

final class CreatingLongTermRelationOperationTarget
    extends LongTermRelationOperationTarget {
  const CreatingLongTermRelationOperationTarget();
}

final class ExistingLongTermRelationOperationTarget
    extends LongTermRelationOperationTarget {
  const ExistingLongTermRelationOperationTarget(this.relationId);

  final LongTermRelationId relationId;
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

sealed class LongTermRelationCommandStart {
  const LongTermRelationCommandStart();
}

final class LongTermRelationCommandAccepted
    extends LongTermRelationCommandStart {
  const LongTermRelationCommandAccepted({
    required this.token,
    required this.future,
  });

  final LongTermRelationOperationToken token;
  final Future<LongTermRelationCommandCompletion> future;
}

final class LongTermRelationCommandAlreadyRunning
    extends LongTermRelationCommandStart {
  const LongTermRelationCommandAlreadyRunning();
}

sealed class BlockingRelationsDeleteStart {
  const BlockingRelationsDeleteStart();
}

sealed class DailyChoiceCommandStart {
  const DailyChoiceCommandStart();
}

final class DailyChoiceCommandAccepted extends DailyChoiceCommandStart {
  const DailyChoiceCommandAccepted({required this.token, required this.future});

  final DailyChoiceOperationToken token;
  final Future<DailyChoiceCommandCompletion> future;
}

final class DailyChoiceCommandAlreadyRunning extends DailyChoiceCommandStart {
  const DailyChoiceCommandAlreadyRunning();
}

sealed class TagCommandStart {
  const TagCommandStart();
}

final class TagCommandAccepted extends TagCommandStart {
  const TagCommandAccepted({required this.token, required this.future});

  final TagOperationToken token;
  final Future<TagCommandCompletion> future;
}

final class TagCommandAlreadyRunning extends TagCommandStart {
  const TagCommandAlreadyRunning();
}

final class BlockingRelationsDeleteAccepted
    extends BlockingRelationsDeleteStart {
  const BlockingRelationsDeleteAccepted({
    required this.token,
    required this.future,
  });

  final BlockingRelationsDeleteOperationToken token;
  final Future<BlockingRelationsDeleteCompletion> future;
}

final class BlockingRelationsDeleteAlreadyRunning
    extends BlockingRelationsDeleteStart {
  const BlockingRelationsDeleteAlreadyRunning();
}

final class GraphCommandCoordinatorDraining extends IntentionCommandStart
    implements
        LongTermRelationCommandStart,
        BlockingRelationsDeleteStart,
        DailyChoiceCommandStart,
        TagCommandStart {
  const GraphCommandCoordinatorDraining();
}

/// Исключительное право конкретного владельца предъявить terminal outcome.
///
/// Удержание claim само по себе не означает предъявления: подтверждать его
/// может только компонент, получивший свидетельство первого доступного кадра.
sealed class GraphPresentationClaim {
  const GraphPresentationClaim._(this.token, this.completion, this._entry);

  final GraphOperationToken token;
  final GraphCommandCompletion completion;
  final _PresentationEntry _entry;
}

/// Право открытой экранной сессии предъявить собственную ошибку.
final class GraphInitiatorPresentationClaim extends GraphPresentationClaim {
  const GraphInitiatorPresentationClaim._(
    super.token,
    super.completion,
    super._entry,
  ) : super._();
}

/// Право оболочки предъявить success либо fallback-ошибку.
final class GraphAppPresentationClaim extends GraphPresentationClaim {
  const GraphAppPresentationClaim._(
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
  Completer<GraphAppPresentationClaim?>? _request;
  GraphAppPresentationClaim? _issued;
  var _isReleased = false;

  /// Запрашивает следующий доступный app-результат в порядке публикации.
  ///
  /// Возвращает `null`, если регистрация освобождена или coordinator завершил
  /// работу до выдачи.
  Future<GraphAppPresentationClaim?> nextClaim() =>
      _coordinator._requestAppClaim(this);

  void release() => _coordinator._releaseRegistration(this);
}

@Riverpod(keepAlive: true)
final class GraphCommandCoordinator extends _$GraphCommandCoordinator {
  final _completionController =
      StreamController<GraphCommandCompletion>.broadcast(sync: true);
  // Публикация завершений последовательна в порядке принятия, поэтому порядок
  // вставки совпадает с порядком публикации terminal outcome.
  final _entries = <GraphOperationToken, _PresentationEntry>{};
  final _registrations = <GraphAppPresentationRegistration>[];
  final _gates = <GraphCommandKey, _PresentationEntry>{};
  final _inFlight = <Future<void>>{};
  late GraphCommandRepository _repository;
  Future<void> _publicationTail = Future<void>.value();
  var _isDraining = false;
  Completer<void>? _shutdownCompleter;

  @override
  void build() {
    _repository = ref.watch(personalGraphRepositoryProvider);
  }

  Stream<GraphCommandCompletion> get completions =>
      _completionController.stream;

  Stream<IntentionCommandCompletion> get intentionCompletions =>
      _completionController.stream
          .where((completion) => completion is IntentionCommandCompletion)
          .map((completion) => completion as IntentionCommandCompletion);

  bool isRunning(IntentionId intentionId) =>
      isKeyRunning(ExistingIntentionKey(intentionId));

  bool isRelationRunning(LongTermRelationId relationId) =>
      isKeyRunning(ExistingLongTermRelationKey(relationId));

  bool isDailyChoiceRunning(DailyChoiceId choiceId) =>
      isKeyRunning(ExistingDailyChoiceKey(choiceId));

  bool isTagRunning(TagId tagId) => isKeyRunning(ExistingTagKey(tagId));

  bool isKeyRunning(GraphCommandKey key) => _gates.containsKey(key);

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

  LongTermRelationCommandStart acceptRelationCreation(
    LongTermRelationCreationFormKey formKey,
    CreateLongTermRelation command,
  ) => _acceptRelation(
    key: formKey,
    command: command,
    kind: LongTermRelationCommandKind.create,
    target: const CreatingLongTermRelationOperationTarget(),
  );

  LongTermRelationCommandStart acceptRelationUpdate(
    UpdateLongTermRelation command,
  ) => _acceptRelation(
    key: ExistingLongTermRelationKey(command.relationId),
    command: command,
    kind: LongTermRelationCommandKind.update,
    target: ExistingLongTermRelationOperationTarget(command.relationId),
  );

  LongTermRelationCommandStart acceptRelationArchive(
    ArchiveLongTermRelation command,
  ) => _acceptRelation(
    key: ExistingLongTermRelationKey(command.relationId),
    command: command,
    kind: LongTermRelationCommandKind.archive,
    target: ExistingLongTermRelationOperationTarget(command.relationId),
  );

  LongTermRelationCommandStart acceptRelationRestore(
    RestoreLongTermRelation command,
  ) => _acceptRelation(
    key: ExistingLongTermRelationKey(command.relationId),
    command: command,
    kind: LongTermRelationCommandKind.restore,
    target: ExistingLongTermRelationOperationTarget(command.relationId),
  );

  LongTermRelationCommandStart acceptRelationDelete(
    DeleteLongTermRelation command,
  ) => _acceptRelation(
    key: ExistingLongTermRelationKey(command.relationId),
    command: command,
    kind: LongTermRelationCommandKind.delete,
    target: ExistingLongTermRelationOperationTarget(command.relationId),
  );

  DailyChoiceCommandStart acceptDailyChoiceCreation(
    DailyChoiceCreationFormKey formKey,
    CreateDailyChoice command,
  ) => _acceptDailyChoice(formKey, command, DailyChoiceCommandKind.create);

  DailyChoiceCommandStart acceptDailyChoiceUpdate(
    UpdateDailyChoiceFields command,
  ) => _acceptDailyChoice(
    ExistingDailyChoiceKey(command.choiceId),
    command,
    DailyChoiceCommandKind.update,
  );

  DailyChoiceCommandStart acceptDailyChoiceReplace(
    ReplaceDailyChoicePath command,
  ) => _acceptDailyChoice(
    ExistingDailyChoiceKey(command.choiceId),
    command,
    DailyChoiceCommandKind.replace,
  );

  DailyChoiceCommandStart acceptDailyChoiceDelete(DeleteDailyChoice command) =>
      _acceptDailyChoice(
        ExistingDailyChoiceKey(command.choiceId),
        command,
        DailyChoiceCommandKind.delete,
      );

  TagCommandStart acceptTagCreation(
    TagCreationFormKey formKey,
    CreateTag command,
  ) => _acceptTag(formKey, command, TagCommandKind.create);

  TagCommandStart acceptTagRename(RenameTag command) =>
      _acceptTag(ExistingTagKey(command.tagId), command, TagCommandKind.rename);

  TagCommandStart acceptTagDelete(DeleteTag command) =>
      _acceptTag(ExistingTagKey(command.tagId), command, TagCommandKind.delete);

  TagCommandStart _acceptTag(
    GraphCommandKey key,
    TagCommand command,
    TagCommandKind kind,
  ) {
    final token = TagOperationToken._();
    final acceptance = _acceptOperation(
      keys: {key},
      entry: _PresentationEntry(token),
      execute: () async => TagCommandCompletion._(
        token: token,
        kind: kind,
        confirmedResult: await _executeTag(command),
      ),
    );
    return switch (acceptance) {
      _GraphCommandAccepted(:final future) => TagCommandAccepted(
        token: token,
        future: future.then((completion) => completion as TagCommandCompletion),
      ),
      _GraphCommandAlreadyRunning() => const TagCommandAlreadyRunning(),
      _GraphCommandDraining() => const GraphCommandCoordinatorDraining(),
    };
  }

  DailyChoiceCommandStart _acceptDailyChoice(
    GraphCommandKey key,
    DailyChoiceCommand command,
    DailyChoiceCommandKind kind,
  ) {
    final token = DailyChoiceOperationToken._();
    final acceptance = _acceptOperation(
      keys: {key},
      entry: _PresentationEntry(token),
      execute: () async => DailyChoiceCommandCompletion._(
        token: token,
        kind: kind,
        confirmedResult: await _executeDailyChoice(command),
      ),
    );
    return switch (acceptance) {
      _GraphCommandAccepted(:final future) => DailyChoiceCommandAccepted(
        token: token,
        future: future.then(
          (completion) => completion as DailyChoiceCommandCompletion,
        ),
      ),
      _GraphCommandAlreadyRunning() => const DailyChoiceCommandAlreadyRunning(),
      _GraphCommandDraining() => const GraphCommandCoordinatorDraining(),
    };
  }

  BlockingRelationsDeleteStart acceptBlockingRelationsDelete(
    DeleteBlockingRelations command, {
    required String presentationTitle,
  }) {
    final token = BlockingRelationsDeleteOperationToken._();
    final acceptance = _acceptOperation(
      keys: {
        ExistingIntentionKey(command.intentionId),
        for (final reference in command.references)
          switch (reference) {
            LongTermBlockingRelationReference(:final id) =>
              ExistingLongTermRelationKey(id),
            DailyChoiceBlockingRelationReference(:final id) =>
              ExistingDailyChoiceKey(id),
          },
      },
      entry: _PresentationEntry(token),
      execute: () async => BlockingRelationsDeleteCompletion._(
        token: token,
        intentionId: command.intentionId,
        presentationTitle: presentationTitle,
        result: await _executeBlockingRelationsDelete(command),
      ),
    );
    return switch (acceptance) {
      _GraphCommandAccepted(:final future) => BlockingRelationsDeleteAccepted(
        token: token,
        future: future.then(
          (completion) => completion as BlockingRelationsDeleteCompletion,
        ),
      ),
      _GraphCommandAlreadyRunning() =>
        const BlockingRelationsDeleteAlreadyRunning(),
      _GraphCommandDraining() => const GraphCommandCoordinatorDraining(),
    };
  }

  LongTermRelationCommandStart _acceptRelation({
    required GraphCommandKey key,
    required LongTermRelationCommand command,
    required LongTermRelationCommandKind kind,
    required LongTermRelationOperationTarget target,
  }) {
    final token = LongTermRelationOperationToken._();
    final acceptance = _acceptOperation(
      keys: {key},
      entry: _PresentationEntry(token),
      execute: () async {
        final result = await _executeLongTermRelation(command);
        return LongTermRelationCommandCompletion._(
          token: token,
          kind: kind,
          target: target,
          confirmedResult: result,
        );
      },
    );
    return switch (acceptance) {
      _GraphCommandAccepted(:final future) => LongTermRelationCommandAccepted(
        token: token,
        future: future.then(
          (completion) => completion as LongTermRelationCommandCompletion,
        ),
      ),
      _GraphCommandAlreadyRunning() =>
        const LongTermRelationCommandAlreadyRunning(),
      _GraphCommandDraining() => const GraphCommandCoordinatorDraining(),
    };
  }

  IntentionCommandStart _accept(
    GraphCommandKey key,
    IntentionCommand command,
    IntentionOperationTarget target,
  ) {
    final token = IntentionOperationToken._();
    final kind = _kindOf(command);
    final acceptance = _acceptOperation(
      keys: {key},
      entry: _PresentationEntry(token),
      execute: () async {
        final result = await _executeIntention(command);
        return IntentionCommandCompletion._(
          token: token,
          kind: kind,
          target: target,
          confirmedResult: result,
        );
      },
    );
    return switch (acceptance) {
      _GraphCommandAccepted(:final future) => IntentionCommandAccepted(
        token: token,
        future: future.then(
          (completion) => completion as IntentionCommandCompletion,
        ),
      ),
      _GraphCommandAlreadyRunning() => const IntentionCommandAlreadyRunning(),
      _GraphCommandDraining() => const GraphCommandCoordinatorDraining(),
    };
  }

  _GraphCommandAcceptance _acceptOperation({
    required Set<GraphCommandKey> keys,
    required _PresentationEntry entry,
    required Future<GraphCommandCompletion> Function() execute,
  }) {
    if (_isDraining) {
      return const _GraphCommandDraining();
    }

    if (keys.any(_gates.containsKey)) {
      return const _GraphCommandAlreadyRunning();
    }

    for (final key in keys) {
      _gates[key] = entry;
    }
    _entries[entry.token] = entry;
    final operationFuture = Future<GraphCommandCompletion>.sync(execute);

    final completionCompleter = Completer<GraphCommandCompletion>();
    late final Future<void> tracked;
    final publication = _publicationTail.then<void>((_) async {
      final completion = await operationFuture;
      entry.completion = completion;
      for (final key in keys) {
        if (identical(_gates[key], entry)) {
          _gates.remove(key);
        }
      }
      _completionController.add(completion);
      completionCompleter.complete(completion);
      _dispatchAppPresentation();
    });
    _publicationTail = publication;
    tracked = publication.whenComplete(() {
      _inFlight.remove(tracked);
      _completeShutdownIfDrained();
    });
    _inFlight.add(tracked);

    return _GraphCommandAccepted(completionCompleter.future);
  }

  /// Выдаёт открытой экранной сессии право предъявить её failure.
  ///
  /// Success инициатору не выдаётся: он сразу принадлежит оболочке. После
  /// освобождения сессии или выдачи права оболочке возвращает `null`.
  GraphInitiatorPresentationClaim? claimInitiatorFailure(
    GraphOperationToken token,
  ) {
    final entry = _entries[token];
    final completion = entry?.completion;
    if (entry == null ||
        completion == null ||
        !completion.isFailure ||
        entry.initiatorReleased ||
        entry.appClaim != null) {
      return null;
    }

    return entry.initiatorClaim ??= GraphInitiatorPresentationClaim._(
      token,
      completion,
      entry,
    );
  }

  /// Завершает экранную сессию инициатора.
  ///
  /// Неподтверждённая ошибка становится доступной оболочке в своём прежнем
  /// порядке; прежний initiator claim больше не может её подтвердить.
  void releaseInitiatorPresentation(GraphOperationToken token) {
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
  void releaseInitiatorClaim(GraphInitiatorPresentationClaim claim) {
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
  void confirmPresentation(GraphPresentationClaim claim) {
    final entry = _entries[claim.token];
    if (entry == null || !identical(entry, claim._entry)) {
      return;
    }

    switch (claim) {
      case GraphInitiatorPresentationClaim():
        if (!identical(entry.initiatorClaim, claim)) {
          return;
        }
        _discardEntry(entry);
      case GraphAppPresentationClaim(:final _registration):
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

  Future<GraphAppPresentationClaim?> _requestAppClaim(
    GraphAppPresentationRegistration registration,
  ) {
    if (registration._isReleased) {
      return Future.value(null);
    }
    final existing = registration._request;
    if (existing != null) {
      return existing.future;
    }

    final request = Completer<GraphAppPresentationClaim?>();
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

    final claim = GraphAppPresentationClaim._(
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
      final belongsToApp = !completion.isFailure || entry.initiatorReleased;
      if (belongsToApp) {
        return entry;
      }
    }
    return null;
  }

  Future<Result<ConfirmedGraphResult<IntentionCommandSuccess>>>
  _executeIntention(IntentionCommand command) async {
    try {
      return await _repository.execute(command);
    } on Object {
      return const ResultFailure<ConfirmedGraphResult<IntentionCommandSuccess>>(
        IntentionUnexpectedFailure(),
      );
    }
  }

  Future<LongTermRelationCommandResult> _executeLongTermRelation(
    LongTermRelationCommand command,
  ) async {
    try {
      return await _repository.execute(command);
    } on Object {
      return const GraphCommandFailed<
        LongTermRelationCommandSuccess,
        LongTermRelationCommandFailure
      >(LongTermRelationUnexpectedFailure());
    }
  }

  Future<DeleteBlockingRelationsResult> _executeBlockingRelationsDelete(
    DeleteBlockingRelations command,
  ) async {
    try {
      return await _repository.execute(command);
    } on Object {
      return const GraphCommandFailed<
        BlockingRelationsDeleted,
        DeleteBlockingRelationsFailure
      >(DeleteBlockingRelationsUnexpectedFailure());
    }
  }

  Future<DailyChoiceCommandResult> _executeDailyChoice(
    DailyChoiceCommand command,
  ) async {
    try {
      return await _repository.execute(command);
    } on Object {
      return const GraphCommandFailed<
        DailyChoiceCommandSuccess,
        DailyChoiceCommandFailure
      >(DailyChoiceUnexpectedFailure());
    }
  }

  Future<TagCommandResult> _executeTag(TagCommand command) async {
    try {
      return await _repository.execute(command);
    } on Object {
      return const TagCommandFailed(TagUnexpectedFailure());
    }
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
  _PresentationEntry(this.token);

  final GraphOperationToken token;
  GraphCommandCompletion? completion;
  bool initiatorReleased = false;
  GraphInitiatorPresentationClaim? initiatorClaim;
  GraphAppPresentationClaim? appClaim;
}

sealed class _GraphCommandAcceptance {
  const _GraphCommandAcceptance();
}

final class _GraphCommandAccepted extends _GraphCommandAcceptance {
  const _GraphCommandAccepted(this.future);

  final Future<GraphCommandCompletion> future;
}

final class _GraphCommandAlreadyRunning extends _GraphCommandAcceptance {
  const _GraphCommandAlreadyRunning();
}

final class _GraphCommandDraining extends _GraphCommandAcceptance {
  const _GraphCommandDraining();
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
