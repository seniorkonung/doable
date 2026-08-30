import '../domain/intention_id.dart';

sealed class IntentionCommand {
  const IntentionCommand();
}

final class CreateIntention extends IntentionCommand {
  const CreateIntention({required this.title, required this.description});

  final String title;
  final String? description;
}

final class UpdateIntention extends IntentionCommand {
  const UpdateIntention({
    required this.id,
    required this.title,
    required this.description,
  });

  final IntentionId id;
  final String title;
  final String? description;
}

final class EnableIntentionReadiness extends IntentionCommand {
  const EnableIntentionReadiness(this.id);

  final IntentionId id;
}

final class DisableIntentionReadiness extends IntentionCommand {
  const DisableIntentionReadiness(this.id);

  final IntentionId id;
}

final class ArchiveIntention extends IntentionCommand {
  const ArchiveIntention(this.id);

  final IntentionId id;
}

final class RestoreIntention extends IntentionCommand {
  const RestoreIntention(this.id);

  final IntentionId id;
}

final class DeleteIntention extends IntentionCommand {
  const DeleteIntention(this.id);

  final IntentionId id;
}
