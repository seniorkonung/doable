import '../../graph/application/graph_command_result.dart';
import '../domain/intention_id.dart';
import 'intention_catalog.dart';
import 'intention_result.dart';

sealed class IntentionCommand
    implements GraphCommand<IntentionCommandSuccess, IntentionFailure> {
  const IntentionCommand();
}

final class CreateIntention extends IntentionCommand {
  const CreateIntention({required this.title, required this.description});

  final String title;
  final String? description;
}

sealed class ExistingIntentionCommand extends IntentionCommand {
  const ExistingIntentionCommand(this.id);

  final IntentionId id;
}

final class UpdateIntention extends ExistingIntentionCommand {
  const UpdateIntention({
    required IntentionId id,
    required this.title,
    required this.description,
  }) : super(id);

  final String title;
  final String? description;
}

final class EnableIntentionReadiness extends ExistingIntentionCommand {
  const EnableIntentionReadiness(super.id);
}

final class DisableIntentionReadiness extends ExistingIntentionCommand {
  const DisableIntentionReadiness(super.id);
}

final class ArchiveIntention extends ExistingIntentionCommand {
  const ArchiveIntention(super.id);
}

final class RestoreIntention extends ExistingIntentionCommand {
  const RestoreIntention(super.id);
}

final class DeleteIntention extends ExistingIntentionCommand {
  const DeleteIntention(super.id);
}
