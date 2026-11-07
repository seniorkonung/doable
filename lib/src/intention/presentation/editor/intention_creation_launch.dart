import '../../domain/intention.dart';
import '../../domain/intention_id.dart';

/// Контекст запуска панели определяет её начальные данные и завершение.
sealed class IntentionCreationLaunch {
  const IntentionCreationLaunch();
}

final class IntentionCreationStandalone extends IntentionCreationLaunch {
  const IntentionCreationStandalone();
}

/// Место нового намерения относительно намерения страницы поиска участника.
enum CreatedIntentionPlacement {
  /// Ниже намерения страницы: по умолчанию вспомогательное, доступны оба вида.
  belowPage,

  /// Выше намерения страницы: входящей связи не будет, поэтому только
  /// главное.
  abovePage,
}

final class IntentionCreationForSearch extends IntentionCreationLaunch {
  const IntentionCreationForSearch({
    required this.initialTitle,
    required this.placement,
    required this.onCreated,
  });

  final String initialTitle;
  final CreatedIntentionPlacement placement;

  /// Получает вид, выбранный в панели: намерение создано главным, а выбранный
  /// вид применяет поиск вместе со связью.
  final void Function(IntentionId id, String title, IntentionKind kind)
  onCreated;
}

final class IntentionCreationForPathStart extends IntentionCreationLaunch {
  const IntentionCreationForPathStart({
    required this.initialTitle,
    required this.onCreated,
  });

  final String initialTitle;
  final void Function(IntentionId id) onCreated;
}
