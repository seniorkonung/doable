import '../../../graph/application/graph_command_coordinator.dart';
import '../../../intention/domain/intention_id.dart';
import '../../../long_term_relation/domain/long_term_relation_id.dart';
import '../../application/confirmed_choice_path.dart';
import '../../application/daily_choice_details.dart';
import '../../application/daily_choice_result.dart';
import '../../domain/daily_choice.dart';

/// Целое предложение для одной замены. Смысл каждого перехода остаётся в
/// ConfirmedChoicePath и повторно сверяется с графом во время записи.
final class DailyChoicePathReplaceProposal {
  DailyChoicePathReplaceProposal(this.path) {
    final steps = path.steps;
    final visited = <IntentionId>{steps.first.sourceIntentionId};
    final relations = <LongTermRelationId>{};
    var current = steps.first.sourceIntentionId;
    for (final step in steps) {
      if (step.sourceIntentionId != current ||
          !visited.add(step.relatedIntentionId) ||
          !relations.add(step.relationId)) {
        throw ArgumentError.value(path, 'path');
      }
      current = step.relatedIntentionId;
    }
  }

  final ConfirmedChoicePath path;
  IntentionId get sourceIntentionId => path.steps.first.sourceIntentionId;
  IntentionId get selectedIntentionId => path.steps.last.relatedIntentionId;
}

sealed class DailyChoicePathReplaceState {
  const DailyChoicePathReplaceState();
}

final class DailyChoicePathReplaceLoading extends DailyChoicePathReplaceState {
  const DailyChoicePathReplaceLoading();
}

final class DailyChoicePathReplaceChoosing extends DailyChoicePathReplaceState {
  const DailyChoicePathReplaceChoosing(this.details);

  final DailyChoiceDetails details;
}

final class DailyChoicePathReplaceReady extends DailyChoicePathReplaceState {
  const DailyChoicePathReplaceReady(this.details, this.proposal);

  final DailyChoiceDetails details;
  final DailyChoicePathReplaceProposal proposal;
  ConfirmedChoicePath get path => proposal.path;
}

final class DailyChoicePathReplaceSubmitting
    extends DailyChoicePathReplaceState {
  const DailyChoicePathReplaceSubmitting(this.details, this.proposal);

  final DailyChoiceDetails details;
  final DailyChoicePathReplaceProposal proposal;
}

final class DailyChoicePathReplaceSucceeded
    extends DailyChoicePathReplaceState {
  const DailyChoicePathReplaceSucceeded(this.choice);

  /// Только подтверждённое репозиторием состояние после commit.
  final DailyChoice choice;
}

final class DailyChoicePathReplaceNotFound extends DailyChoicePathReplaceState {
  const DailyChoicePathReplaceNotFound({this.failurePresentation});

  final GraphInitiatorPresentationClaim? failurePresentation;
}

final class DailyChoicePathReplaceReadFailed
    extends DailyChoicePathReplaceState {
  const DailyChoicePathReplaceReadFailed(this.failure);

  final DailyChoiceReadFailure failure;
  bool get canRetry => failure is DailyChoiceReadUnavailableFailure;
}

final class DailyChoicePathReplaceRejected extends DailyChoicePathReplaceState {
  const DailyChoicePathReplaceRejected(
    this.details,
    this.proposal,
    this.failure, {
    this.failurePresentation,
  });

  final DailyChoiceDetails details;
  final DailyChoicePathReplaceProposal proposal;
  final DailyChoiceCommandFailure failure;
  final GraphInitiatorPresentationClaim? failurePresentation;
  bool get canRetry => failure is DailyChoiceUnavailableFailure;
}
