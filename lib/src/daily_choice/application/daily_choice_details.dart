import '../../graph/application/graph_command_result.dart';
import '../../graph/application/graph_revision.dart';
import '../../intention/domain/intention.dart';
import '../../long_term_relation/domain/long_term_relation.dart';
import '../../long_term_relation/domain/long_term_relation_description.dart';
import '../domain/daily_choice.dart';

final class DailyChoicePathStepDetails {
  const DailyChoicePathStepDetails({
    required this.step,
    required this.relation,
    required this.description,
    required this.source,
    required this.related,
  });

  final ChoicePathStep step;
  final LongTermRelation relation;
  final LongTermRelationDescription? description;
  final Intention source;
  final Intention related;
}

final class DailyChoiceDetails {
  DailyChoiceDetails({
    required this.choice,
    required this.source,
    required this.selected,
    required Iterable<DailyChoicePathStepDetails> path,
  }) : path = List.unmodifiable(path);

  final DailyChoice choice;
  final Intention source;
  final Intention selected;
  final List<DailyChoicePathStepDetails> path;
}

sealed class DailyChoiceReadFailure implements GraphCommandFailure {
  const DailyChoiceReadFailure();
}

final class DailyChoiceReadCorruptionFailure extends DailyChoiceReadFailure {
  const DailyChoiceReadCorruptionFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.corruption;
}

final class DailyChoiceReadUnavailableFailure extends DailyChoiceReadFailure {
  const DailyChoiceReadUnavailableFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unavailable;
}

final class DailyChoiceReadUnexpectedFailure extends DailyChoiceReadFailure {
  const DailyChoiceReadUnexpectedFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unexpected;
}

typedef DailyChoiceReadResult =
    GraphResult<GraphSnapshot<DailyChoiceDetails?>, DailyChoiceReadFailure>;
typedef DailyChoiceReadSuccess =
    GraphResultSuccess<
      GraphSnapshot<DailyChoiceDetails?>,
      DailyChoiceReadFailure
    >;
typedef DailyChoiceReadError =
    GraphResultFailure<
      GraphSnapshot<DailyChoiceDetails?>,
      DailyChoiceReadFailure
    >;
