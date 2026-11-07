import '../../domain/intention_id.dart';

/// Контекст запуска панели определяет её начальные данные и завершение.
sealed class IntentionCreationLaunch {
  const IntentionCreationLaunch();
}

final class IntentionCreationStandalone extends IntentionCreationLaunch {
  const IntentionCreationStandalone();
}

final class IntentionCreationForSearch extends IntentionCreationLaunch {
  const IntentionCreationForSearch({
    required this.initialTitle,
    required this.onCreated,
  });

  final String initialTitle;
  final void Function(IntentionId id, String title) onCreated;
}

final class IntentionCreationForPathStart extends IntentionCreationLaunch {
  const IntentionCreationForPathStart({
    required this.initialTitle,
    required this.onCreated,
  });

  final String initialTitle;
  final void Function(IntentionId id) onCreated;
}
