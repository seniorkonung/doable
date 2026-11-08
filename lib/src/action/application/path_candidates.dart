import '../../graph/application/graph_command_result.dart';
import '../../graph/application/graph_revision.dart';
import '../../intention/domain/intention.dart';
import '../../long_term_relation/domain/long_term_relation.dart';
import '../domain/action_path.dart';

/// Продолжение несёт ревизию, участок и последний ключ порядка. Содержимое
/// скрыто от клиента.
abstract interface class PathCandidatesCursor {}

/// Одна порция кандидатов половины [half] для последнего намерения целого
/// начального участка черновика [draft]. Размер порции ограничен
/// [minPageSize]–[maxPageSize]; иначе выбрасывается [RangeError].
final class PathCandidatesQuery {
  factory PathCandidatesQuery({
    required ActionPath draft,
    required LongTermRelationType half,
    int pageSize = defaultPageSize,
    PathCandidatesCursor? cursor,
  }) {
    RangeError.checkValueInInterval(pageSize, minPageSize, maxPageSize);
    return PathCandidatesQuery._(draft, half, pageSize, cursor);
  }

  const PathCandidatesQuery._(
    this.draft,
    this.half,
    this.pageSize,
    this.cursor,
  );

  static const minPageSize = 1;
  static const maxPageSize = 100;
  static const defaultPageSize = 50;

  final ActionPath draft;
  final LongTermRelationType half;
  final int pageSize;
  final PathCandidatesCursor? cursor;
}

/// Звено участка: активная связь от предыдущего намерения и само намерение.
final class PathSegmentStep {
  const PathSegmentStep({required this.relation, required this.intention});

  final LongTermRelation relation;
  final Intention intention;
}

/// Целый начальный участок черновика: намерения от корневого до первого
/// разрыва с текущими данными. Все намерения и связи участка активны.
final class PathSegment {
  PathSegment({required this.root, required Iterable<PathSegmentStep> steps})
    : steps = List.unmodifiable(steps);

  final Intention root;
  final List<PathSegmentStep> steps;

  Intention get last => steps.isEmpty ? root : steps.last.intention;
}

/// Кандидат — намерение, к которому от последнего намерения участка ведёт
/// активная связь [relation], и его текущее название.
final class PathCandidate {
  const PathCandidate({required this.relation, required this.title});

  final LongTermRelation relation;
  final String title;
}

/// Точные числа кандидатов обеих половин без намерений участка.
final class PathCandidateCounts {
  const PathCandidateCounts({required this.need, required this.can});

  final int need;
  final int can;
}

/// Прочитанное состояние черновика на одном подтверждённом снимке.
sealed class PathCandidatesRead {
  const PathCandidatesRead({required this.revision});

  final GraphRevision revision;
}

/// Корневое намерение черновика удалено или в архиве: целый начальный
/// участок пуст, и продолжать путь не от чего.
final class EmptyPathSegment extends PathCandidatesRead {
  const EmptyPathSegment({required super.revision});
}

/// Кандидаты идут по приоритету связи от P1 к P4, затем по порядку создания
/// связей.
sealed class PathCandidatesPage extends PathCandidatesRead {
  PathCandidatesPage({
    required List<PathCandidate> items,
    required this.nextCursor,
    required super.revision,
  }) : items = List.unmodifiable(items);

  final List<PathCandidate> items;
  final PathCandidatesCursor? nextCursor;
}

/// Участок, числа обеих половин и первая порция получены на одном снимке.
final class PathCandidatesFirstPage extends PathCandidatesPage {
  PathCandidatesFirstPage({
    required this.segment,
    required this.counts,
    required super.items,
    required super.nextCursor,
    required super.revision,
  });

  final PathSegment segment;
  final PathCandidateCounts counts;
}

final class PathCandidatesContinuationPage extends PathCandidatesPage {
  PathCandidatesContinuationPage({
    required super.items,
    required super.nextCursor,
    required super.revision,
  });
}

sealed class PathCandidatesReadFailure implements GraphCommandFailure {
  const PathCandidatesReadFailure();
}

/// Ревизия продолжения больше не совпадает с текущим снимком.
final class PathCandidatesSnapshotExpired extends PathCandidatesReadFailure {
  const PathCandidatesSnapshotExpired();

  @override
  GraphFailureCategory get category => GraphFailureCategory.conflict;
}

final class PathCandidatesUnavailableFailure extends PathCandidatesReadFailure {
  const PathCandidatesUnavailableFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unavailable;
}

final class PathCandidatesCorruptionFailure extends PathCandidatesReadFailure {
  const PathCandidatesCorruptionFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.corruption;
}

final class PathCandidatesUnexpectedFailure extends PathCandidatesReadFailure {
  const PathCandidatesUnexpectedFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unexpected;
}

typedef PathCandidatesResult =
    GraphResult<PathCandidatesRead, PathCandidatesReadFailure>;
typedef PathCandidatesSuccess =
    GraphResultSuccess<PathCandidatesRead, PathCandidatesReadFailure>;
typedef PathCandidatesError =
    GraphResultFailure<PathCandidatesRead, PathCandidatesReadFailure>;
