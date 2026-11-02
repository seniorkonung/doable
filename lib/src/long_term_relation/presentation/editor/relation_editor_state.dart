import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../intention/domain/intention_id.dart';
import '../../application/intention_relation_group.dart';
import '../../application/long_term_relation_command.dart';
import '../../application/long_term_relation_projection.dart';
import '../../domain/long_term_relation.dart';
import '../../domain/long_term_relation_description.dart';
import '../../domain/long_term_relation_id.dart';

/// Типизированный источник черновика формы связи.
sealed class RelationEditorContext {
  const RelationEditorContext();
}

/// Самостоятельное создание связи без заранее выбранных участников.
final class RelationBlankCreationContext extends RelationEditorContext {
  const RelationBlankCreationContext();
}

/// Контекст группы связей, из которой открыт черновик создания связи.
///
/// Направление группы задаёт роль текущего намерения: исходящая группа
/// предвыбирает его исходным участником, входящая — связанным. Тип группы
/// становится начальным типом формы. Роли и тип остаются доступными для
/// замены, поэтому контекст задаёт только начало черновика, а не
/// окончательную связь.
final class RelationCreationContext extends RelationEditorContext {
  const RelationCreationContext({
    required this.participant,
    required this.group,
  }) : super();

  /// Снимок текущего намерения, уже загруженный подробным просмотром.
  final RelationParticipantSummary participant;
  final IntentionRelationGroup group;

  RelationParticipantSummary? get initialSourceParticipant =>
      switch (group.direction) {
        RelationDirection.outgoing => participant,
        RelationDirection.incoming => null,
      };

  RelationParticipantSummary? get initialRelatedParticipant =>
      switch (group.direction) {
        RelationDirection.outgoing => null,
        RelationDirection.incoming => participant,
      };

  LongTermRelationType get initialType => group.type;

  @override
  bool operator ==(Object other) =>
      other is RelationCreationContext &&
      other.participant.id == participant.id &&
      other.participant.title == participant.title &&
      other.participant.archiveState == participant.archiveState &&
      other.group == group;

  @override
  int get hashCode => Object.hash(
    participant.id,
    participant.title,
    participant.archiveState,
    group,
  );
}

/// Выбор, без которого команда создания связи не может быть составлена.
enum RelationDraftRequirement {
  sourceParticipant,
  relatedParticipant,
  type,
  priority,
}

/// Готовность черновика к отправке.
///
/// Отсутствие выбора типа или приоритета — отдельный вариант, а не значение
/// по умолчанию: приоритет связи выбирается пользователем явно.
sealed class RelationDraftCompleteness {
  const RelationDraftCompleteness();
}

/// Все обязательные части выбраны, пара участников известна.
final class RelationDraftComplete extends RelationDraftCompleteness {
  const RelationDraftComplete({
    required this.sourceIntentionId,
    required this.relatedIntentionId,
    required this.type,
    required this.priority,
  });

  final IntentionId sourceIntentionId;
  final IntentionId relatedIntentionId;
  final LongTermRelationType type;
  final RelationPriority priority;
}

/// Черновик ещё не описывает команду; перечислен недостающий выбор.
final class RelationDraftIncomplete extends RelationDraftCompleteness {
  RelationDraftIncomplete(Set<RelationDraftRequirement> missing)
    : missing = Set.unmodifiable(missing);

  final Set<RelationDraftRequirement> missing;
}

/// Почему участник не принят графом в момент сохранения.
enum RelationParticipantRejection { missing, archived }

/// Безопасная причина, по которой связь не сохранена.
sealed class RelationEditorFailure {
  const RelationEditorFailure();

  /// Доступен ли обычный повтор той же отправки.
  bool get canRetry => false;
}

/// Введённое описание отклонено до отправки команды.
final class RelationEditorDescriptionInvalid extends RelationEditorFailure {
  const RelationEditorDescriptionInvalid(this.failure);

  final LongTermRelationTextValidationFailure failure;
}

/// Участник выбранной роли отсутствует или архивирован.
final class RelationEditorParticipantRejected extends RelationEditorFailure {
  const RelationEditorParticipantRejected({
    required this.role,
    required this.intentionId,
    required this.rejection,
  });

  final RelationParticipantRole role;
  final IntentionId intentionId;
  final RelationParticipantRejection rejection;
}

/// Направленная пара уже занята существующей связью.
///
/// Идентификатор позволяет открыть её без изменения.
final class RelationEditorPairOccupied extends RelationEditorFailure {
  const RelationEditorPairOccupied(this.existingRelationId);

  final LongTermRelationId existingRelationId;
}

/// Оба участника оказались одним намерением.
final class RelationEditorSameParticipants extends RelationEditorFailure {
  const RelationEditorSameParticipants();
}

/// Доказанно устранимая недоступность хранилища.
final class RelationEditorUnavailable extends RelationEditorFailure {
  const RelationEditorUnavailable();

  @override
  bool get canRetry => true;
}

/// Повреждение сохранённых данных: повтор не поможет.
final class RelationEditorCorruption extends RelationEditorFailure {
  const RelationEditorCorruption();
}

/// Неизвестная причина отказа без утверждений о данных.
final class RelationEditorUnexpected extends RelationEditorFailure {
  const RelationEditorUnexpected();
}

/// Состояние отправки текущего черновика.
sealed class RelationEditorOperation {
  const RelationEditorOperation();
}

/// Отправка не выполняется, исправление доступно.
final class RelationEditorIdle extends RelationEditorOperation {
  const RelationEditorIdle();
}

/// Принятая отправка выполняется; вторая команда не принимается.
final class RelationEditorSubmitting extends RelationEditorOperation {
  const RelationEditorSubmitting();
}

/// Сохранение подтверждено графом.
final class RelationEditorSucceeded extends RelationEditorOperation {
  const RelationEditorSucceeded(this.relation);

  final LongTermRelation relation;
}

/// Сохранение не выполнено; черновик сохранён для исправления.
final class RelationEditorFailed extends RelationEditorOperation {
  const RelationEditorFailed(this.failure);

  final RelationEditorFailure failure;
}

/// Однократный сигнал формы для навигации.
sealed class RelationEditorEvent {
  const RelationEditorEvent();
}

/// Право одной формы продолжать создание независимо от удаления маршрута.
enum RelationEditorSessionState { active, left }

/// Связь создана: форма может быть закрыта.
final class RelationEditorCreated extends RelationEditorEvent {
  const RelationEditorCreated(this.relationId);

  final LongTermRelationId relationId;
}

/// Черновик одной открытой формы создания связи.
///
/// Черновик хранит только выбор пользователя и исход последней отправки.
/// Подтверждённой связью он не становится: успех отмечается отдельным
/// состоянием операции и событием навигации.
final class RelationEditorState {
  const RelationEditorState({
    required this.context,
    required this.sourceParticipant,
    required this.relatedParticipant,
    required this.sourceRevision,
    required this.relatedRevision,
    required this.type,
    required this.priority,
    required this.description,
    required this.operation,
    required this.event,
    this.failurePresentation,
    this.sessionState = RelationEditorSessionState.active,
  });

  factory RelationEditorState.initial(RelationEditorContext context) =>
      switch (context) {
        RelationBlankCreationContext() => RelationEditorState(
          context: context,
          sourceParticipant: null,
          relatedParticipant: null,
          sourceRevision: null,
          relatedRevision: null,
          type: null,
          priority: null,
          description: '',
          operation: const RelationEditorIdle(),
          event: null,
        ),
        final RelationCreationContext creation => RelationEditorState(
          context: context,
          sourceParticipant: creation.initialSourceParticipant,
          relatedParticipant: creation.initialRelatedParticipant,
          sourceRevision: null,
          relatedRevision: null,
          type: creation.initialType,
          priority: null,
          description: '',
          operation: const RelationEditorIdle(),
          event: null,
        ),
      };

  final RelationEditorContext context;
  final RelationEditorSessionState sessionState;

  bool get canEdit =>
      sessionState == RelationEditorSessionState.active &&
      (operation is RelationEditorIdle || operation is RelationEditorFailed);

  final RelationParticipantSummary? sourceParticipant;
  final RelationParticipantSummary? relatedParticipant;
  final GraphRevision? sourceRevision;
  final GraphRevision? relatedRevision;
  GraphRevision? revisionFor(RelationParticipantRole role) => switch (role) {
    RelationParticipantRole.source => sourceRevision,
    RelationParticipantRole.related => relatedRevision,
  };

  bool needsNewBasis(
    RelationParticipantRole role,
    IntentionId id,
    GraphRevision revision,
  ) {
    final current = switch (role) {
      RelationParticipantRole.source => sourceParticipant,
      RelationParticipantRole.related => relatedParticipant,
    };
    final currentRevision = revisionFor(role);
    return current?.id == id &&
        currentRevision != null &&
        revision.compareTo(currentRevision) ==
            GraphRevisionOrder.differentEpoch;
  }

  IntentionId? get sourceIntentionId => sourceParticipant?.id;
  IntentionId? get relatedIntentionId => relatedParticipant?.id;
  final LongTermRelationType? type;
  final RelationPriority? priority;
  final String description;
  final RelationEditorOperation operation;
  final RelationEditorEvent? event;

  /// Право открытой формы предъявить текущую ошибку; подтверждается страницей
  /// только по кадру с видимым сообщением.
  final GraphInitiatorPresentationClaim? failurePresentation;

  RelationDraftCompleteness get completeness {
    final source = sourceIntentionId;
    final related = relatedIntentionId;
    final selectedType = type;
    final selectedPriority = priority;
    final missing = <RelationDraftRequirement>{
      if (source == null) RelationDraftRequirement.sourceParticipant,
      if (related == null) RelationDraftRequirement.relatedParticipant,
      if (selectedType == null) RelationDraftRequirement.type,
      if (selectedPriority == null) RelationDraftRequirement.priority,
    };
    if (source == null ||
        related == null ||
        selectedType == null ||
        selectedPriority == null) {
      return RelationDraftIncomplete(missing);
    }
    return RelationDraftComplete(
      sourceIntentionId: source,
      relatedIntentionId: related,
      type: selectedType,
      priority: selectedPriority,
    );
  }

  bool get canRetry => switch (operation) {
    RelationEditorFailed(:final failure) => failure.canRetry,
    RelationEditorIdle() ||
    RelationEditorSubmitting() ||
    RelationEditorSucceeded() => false,
  };

  /// Есть ли явная правка относительно исходного снимка формы.
  ///
  /// Недопустимый текст считается правкой, чтобы отправка могла показать
  /// точную ошибку валидации и сохранить введённое значение.
  bool get hasChanges => switch (context) {
    RelationBlankCreationContext() =>
      sourceParticipant != null ||
          relatedParticipant != null ||
          type != null ||
          priority != null ||
          description.isNotEmpty,
    final RelationCreationContext creation =>
      sourceParticipant != creation.initialSourceParticipant ||
          relatedParticipant != creation.initialRelatedParticipant ||
          type != creation.initialType ||
          priority != null ||
          description.isNotEmpty,
  };

  bool get canSubmit =>
      sessionState == RelationEditorSessionState.active &&
      completeness is RelationDraftComplete &&
      (operation is RelationEditorIdle || canRetry);

  RelationEditorState withParticipant(
    RelationParticipantRole role,
    GraphSnapshot<RelationParticipantSummary> selected,
  ) {
    final participant = selected.value;
    final currentParticipant = switch (role) {
      RelationParticipantRole.source => sourceParticipant,
      RelationParticipantRole.related => relatedParticipant,
    };
    final identityChanged = currentParticipant?.id != participant.id;
    if (!identityChanged && !_isNewer(role, selected.revision)) {
      return this;
    }
    final nextOperation = _operationAfter(
      (failure) => _isCorrectedByParticipant(role, identityChanged, failure),
    );
    return _copyWith(
      sourceParticipant: switch (role) {
        RelationParticipantRole.source => participant,
        RelationParticipantRole.related => sourceParticipant,
      },
      relatedParticipant: switch (role) {
        RelationParticipantRole.source => relatedParticipant,
        RelationParticipantRole.related => participant,
      },
      sourceRevision: role == RelationParticipantRole.source
          ? selected.revision
          : sourceRevision,
      relatedRevision: role == RelationParticipantRole.related
          ? selected.revision
          : relatedRevision,
      operation: nextOperation,
    );
  }

  RelationEditorState withType(LongTermRelationType value) =>
      _copyWith(type: value, operation: operation);

  RelationEditorState withPriority(RelationPriority value) =>
      _copyWith(priority: value, operation: operation);

  RelationEditorState withDescription(String value) => _copyWith(
    description: value,
    operation: _operationAfter(_isCorrectedByDescription),
  );

  /// Новое чтение, запущенное после обнаружения другой эпохи, задаёт основу.
  RelationEditorState withNewBasis(
    RelationParticipantRole role,
    GraphSnapshot<RelationParticipantSummary> snapshot,
    GraphRevision expectedRevision,
  ) {
    final currentId = switch (role) {
      RelationParticipantRole.source => sourceIntentionId,
      RelationParticipantRole.related => relatedIntentionId,
    };
    final currentRevision = revisionFor(role);
    if (currentId != snapshot.value.id ||
        currentRevision == null ||
        currentRevision.compareTo(expectedRevision) !=
            GraphRevisionOrder.same) {
      return this;
    }
    final order = snapshot.revision.compareTo(currentRevision);
    if (order == GraphRevisionOrder.older || order == GraphRevisionOrder.same) {
      return this;
    }
    return RelationEditorState(
      context: context,
      sessionState: sessionState,
      sourceParticipant: role == RelationParticipantRole.source
          ? snapshot.value
          : sourceParticipant,
      relatedParticipant: role == RelationParticipantRole.related
          ? snapshot.value
          : relatedParticipant,
      sourceRevision: role == RelationParticipantRole.source
          ? snapshot.revision
          : sourceRevision,
      relatedRevision: role == RelationParticipantRole.related
          ? snapshot.revision
          : relatedRevision,
      type: type,
      priority: priority,
      description: description,
      operation: operation,
      event: event,
      failurePresentation: failurePresentation,
    );
  }

  bool _isNewer(RelationParticipantRole role, GraphRevision revision) {
    final current = revisionFor(role);
    return current == null ||
        revision.compareTo(current) == GraphRevisionOrder.newer;
  }

  RelationEditorState withOperation(
    RelationEditorOperation value, {
    RelationEditorEvent? event,
    GraphInitiatorPresentationClaim? failurePresentation,
    RelationEditorSessionState? sessionState,
  }) => RelationEditorState(
    context: context,
    sessionState: sessionState ?? this.sessionState,
    sourceParticipant: sourceParticipant,
    relatedParticipant: relatedParticipant,
    sourceRevision: sourceRevision,
    relatedRevision: relatedRevision,
    type: type,
    priority: priority,
    description: description,
    operation: value,
    event: event,
    failurePresentation: failurePresentation,
  );

  RelationEditorState withoutEvent() => RelationEditorState(
    context: context,
    sessionState: sessionState,
    sourceParticipant: sourceParticipant,
    relatedParticipant: relatedParticipant,
    sourceRevision: sourceRevision,
    relatedRevision: relatedRevision,
    type: type,
    priority: priority,
    description: description,
    operation: operation,
    event: null,
    failurePresentation: failurePresentation,
  );

  RelationEditorState _copyWith({
    required RelationEditorOperation operation,
    RelationParticipantSummary? sourceParticipant,
    RelationParticipantSummary? relatedParticipant,
    GraphRevision? sourceRevision,
    GraphRevision? relatedRevision,
    LongTermRelationType? type,
    RelationPriority? priority,
    String? description,
  }) => RelationEditorState(
    context: context,
    sessionState: sessionState,
    sourceParticipant: sourceParticipant ?? this.sourceParticipant,
    relatedParticipant: relatedParticipant ?? this.relatedParticipant,
    sourceRevision: sourceRevision ?? this.sourceRevision,
    relatedRevision: relatedRevision ?? this.relatedRevision,
    type: type ?? this.type,
    priority: priority ?? this.priority,
    description: description ?? this.description,
    operation: operation,
    event: null,
    failurePresentation: operation is RelationEditorFailed
        ? failurePresentation
        : null,
  );

  /// Возвращает состояние операции после правки черновика.
  ///
  /// Правка снимает только ту ошибку, которую она действительно устраняет:
  /// остальные причины остаются видимыми и продолжают блокировать отправку.
  RelationEditorOperation _operationAfter(
    bool Function(RelationEditorFailure failure) corrects,
  ) {
    final current = operation;
    if (current is! RelationEditorFailed) {
      return current;
    }
    return corrects(current.failure) ? const RelationEditorIdle() : current;
  }

  static bool _isCorrectedByDescription(RelationEditorFailure failure) =>
      switch (failure) {
        RelationEditorDescriptionInvalid() => true,
        RelationEditorParticipantRejected() ||
        RelationEditorPairOccupied() ||
        RelationEditorSameParticipants() ||
        RelationEditorUnavailable() ||
        RelationEditorCorruption() ||
        RelationEditorUnexpected() => false,
      };

  static bool _isCorrectedByParticipant(
    RelationParticipantRole role,
    bool identityChanged,
    RelationEditorFailure failure,
  ) => switch (failure) {
    RelationEditorParticipantRejected(role: final rejected) => rejected == role,
    // Занятость пары и самосвязь зависят только от участников.
    RelationEditorPairOccupied() ||
    RelationEditorSameParticipants() => identityChanged,
    RelationEditorDescriptionInvalid() ||
    RelationEditorUnavailable() ||
    RelationEditorCorruption() ||
    RelationEditorUnexpected() => false,
  };
}
