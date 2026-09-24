import '../../graph/application/graph_command_result.dart';
import '../../graph/application/graph_revision.dart';
import '../../intention/domain/intention.dart';
import '../../long_term_relation/application/long_term_relation_projection.dart';
import 'choice_path_draft.dart';

enum ChoicePathContinuationQueryValidationFailure { pageSizeOutOfRange }

final class ChoicePathContinuationQueryValidationException
    implements Exception {
  const ChoicePathContinuationQueryValidationException(this.failure);

  final ChoicePathContinuationQueryValidationFailure failure;
}

/// Непрозрачное продолжение одной порции. Репозиторий привязывает его к своему
/// экземпляру, направлению, полному черновику, размеру порции, ревизии и ключу.
abstract interface class ChoicePathContinuationCursor {}

final class ChoicePathContinuationQuery {
  factory ChoicePathContinuationQuery({
    required ChoicePathDraft draft,
    int pageSize = defaultPageSize,
    ChoicePathContinuationCursor? cursor,
  }) {
    if (pageSize < minPageSize || pageSize > maxPageSize) {
      throw const ChoicePathContinuationQueryValidationException(
        ChoicePathContinuationQueryValidationFailure.pageSizeOutOfRange,
      );
    }
    return ChoicePathContinuationQuery._(draft, pageSize, cursor);
  }

  const ChoicePathContinuationQuery._(this.draft, this.pageSize, this.cursor);

  static const minPageSize = 1;
  static const maxPageSize = 100;
  static const defaultPageSize = 50;

  final ChoicePathDraft draft;
  final int pageSize;
  final ChoicePathContinuationCursor? cursor;

  ChoicePathDraftDirection get direction => draft.direction;
}

/// Подтверждённый снимок текущего шага и одной порции допустимых переходов.
/// Пустой список без курсора означает доказанное отсутствие продолжения, но
/// не отсутствие самого текущего намерения и не ошибку чтения.
final class ChoicePathContinuationsPage {
  ChoicePathContinuationsPage({
    required this.draft,
    required this.current,
    required Iterable<LongTermRelationSummary> items,
    required this.nextCursor,
    required this.revision,
  }) : items = List<LongTermRelationSummary>.unmodifiable(
         List<LongTermRelationSummary>.of(items)..sort(_compareContinuations),
       ) {
    if (current.id != draft.currentIntentionId ||
        current.archiveState != IntentionArchiveState.active) {
      throw ArgumentError.value(current, 'current');
    }
  }

  final ChoicePathDraft draft;
  final Intention current;
  final List<LongTermRelationSummary> items;
  final ChoicePathContinuationCursor? nextCursor;
  final GraphRevision revision;

  ChoicePathDraftDirection get direction => draft.direction;

  /// После перехода верхний обход требует готового конца, а нижний допускает
  /// основание любой готовности. Репозиторий проверяет фиксированное действие.
  bool get canConfirm => switch (draft) {
    ChoicePathDraftProgress() => current.readiness == IntentionReadiness.ready,
    ChoicePathDraftBottomProgress() => true,
    ChoicePathDraftStart() || ChoicePathDraftBottomStart() => false,
  };
}

int _compareContinuations(
  LongTermRelationSummary left,
  LongTermRelationSummary right,
) {
  final leftRelation = left.relation;
  final rightRelation = right.relation;
  final group = leftRelation.type.index.compareTo(rightRelation.type.index);
  if (group != 0) return group;
  final priority = leftRelation.priority.index.compareTo(
    rightRelation.priority.index,
  );
  if (priority != 0) return priority;
  return leftRelation.creationSequence.compareTo(
    rightRelation.creationSequence,
  );
}

sealed class ChoicePathContinuationFailure implements GraphCommandFailure {
  const ChoicePathContinuationFailure();
}

/// Некорректный запрос или курсор от другого запроса либо репозитория.
final class ChoicePathContinuationValidationFailure
    extends ChoicePathContinuationFailure {
  const ChoicePathContinuationValidationFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.validation;
}

/// Отсутствует исходное или достигнутое намерение.
final class ChoicePathContinuationIntentionNotFoundFailure
    extends ChoicePathContinuationFailure {
  const ChoicePathContinuationIntentionNotFoundFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.notFound;
}

/// Префикс устарел либо ревизия порции больше не актуальна.
final class ChoicePathContinuationSnapshotExpired
    extends ChoicePathContinuationFailure {
  const ChoicePathContinuationSnapshotExpired();

  @override
  GraphFailureCategory get category => GraphFailureCategory.conflict;
}

final class ChoicePathContinuationUnavailableFailure
    extends ChoicePathContinuationFailure {
  const ChoicePathContinuationUnavailableFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unavailable;
}

final class ChoicePathContinuationCorruptionFailure
    extends ChoicePathContinuationFailure {
  const ChoicePathContinuationCorruptionFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.corruption;
}

final class ChoicePathContinuationUnexpectedFailure
    extends ChoicePathContinuationFailure {
  const ChoicePathContinuationUnexpectedFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unexpected;
}

typedef ChoicePathContinuationResult =
    GraphResult<ChoicePathContinuationsPage, ChoicePathContinuationFailure>;
typedef ChoicePathContinuationSuccess =
    GraphResultSuccess<
      ChoicePathContinuationsPage,
      ChoicePathContinuationFailure
    >;
typedef ChoicePathContinuationError =
    GraphResultFailure<
      ChoicePathContinuationsPage,
      ChoicePathContinuationFailure
    >;
