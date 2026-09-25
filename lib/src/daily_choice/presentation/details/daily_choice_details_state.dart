import '../../../graph/application/graph_revision.dart';
import '../../application/daily_choice_details.dart';

sealed class DailyChoiceDetailsState {
  const DailyChoiceDetailsState();
}

final class DailyChoiceDetailsLoading extends DailyChoiceDetailsState {
  const DailyChoiceDetailsLoading();
}

final class DailyChoiceDetailsLoaded extends DailyChoiceDetailsState {
  const DailyChoiceDetailsLoaded(this.details, this.revision);

  final DailyChoiceDetails details;
  final GraphRevision revision;
}

final class DailyChoiceDetailsNotFound extends DailyChoiceDetailsState {
  const DailyChoiceDetailsNotFound();
}

final class DailyChoiceDetailsUnavailable extends DailyChoiceDetailsState {
  const DailyChoiceDetailsUnavailable();
}

final class DailyChoiceDetailsCorruption extends DailyChoiceDetailsState {
  const DailyChoiceDetailsCorruption();
}

final class DailyChoiceDetailsUnexpected extends DailyChoiceDetailsState {
  const DailyChoiceDetailsUnexpected();
}
