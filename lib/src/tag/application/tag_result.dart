import '../../graph/application/graph_command_result.dart';
import '../../graph/application/graph_revision.dart';
import '../domain/tag.dart';
import '../domain/tag_id.dart';
import '../domain/tag_name.dart';
import 'tag_change.dart';

sealed class TagCommandFailure implements GraphCommandFailure {
  const TagCommandFailure();
}

final class TagNameInputFailure extends TagCommandFailure {
  const TagNameInputFailure(this.reason);

  final TagNameFailureReason reason;

  @override
  GraphFailureCategory get category => GraphFailureCategory.validation;
}

final class TagNameOccupiedFailure extends TagCommandFailure {
  const TagNameOccupiedFailure(this.existingTagId);

  final TagId existingTagId;

  @override
  GraphFailureCategory get category => GraphFailureCategory.conflict;
}

final class TagNotFoundFailure extends TagCommandFailure {
  const TagNotFoundFailure(this.tagId);

  final TagId tagId;

  @override
  GraphFailureCategory get category => GraphFailureCategory.notFound;
}

final class TagUnavailableFailure extends TagCommandFailure {
  const TagUnavailableFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unavailable;
}

final class TagCorruptionFailure extends TagCommandFailure {
  const TagCorruptionFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.corruption;
}

final class TagUnexpectedFailure extends TagCommandFailure {
  const TagUnexpectedFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unexpected;
}

/// Каждому исходу соответствует ровно одно типизированное изменение.
/// Репозиторий создаёт подтверждённый пакет после commit одной транзакции.
sealed class TagCommandSuccess implements GraphCommandOutcome {
  const TagCommandSuccess();

  TagChange get change;

  @override
  Iterable<GraphChange> get changes => [change];
}

final class TagCreated extends TagCommandSuccess {
  const TagCreated(this.change);

  @override
  final TagCreatedChange change;
  Tag get tag => change.after;
}

final class TagRenamed extends TagCommandSuccess {
  const TagRenamed(this.change);

  @override
  final TagRenamedChange change;
  Tag get before => change.before;
  Tag get after => change.after;
}

final class TagUnchanged extends TagCommandSuccess {
  const TagUnchanged(this.change);

  @override
  final TagUnchangedChange change;
  Tag get tag => change.tag;
}

final class TagDeleted extends TagCommandSuccess {
  const TagDeleted(this.change);

  @override
  final TagDeletedChange change;
  TagId get tagId => change.tagId;
}

typedef TagCommandResult =
    GraphCommandResult<TagCommandSuccess, TagCommandFailure>;
typedef TagCommandSucceeded =
    GraphCommandSucceeded<TagCommandSuccess, TagCommandFailure>;
typedef TagCommandFailed =
    GraphCommandFailed<TagCommandSuccess, TagCommandFailure>;
