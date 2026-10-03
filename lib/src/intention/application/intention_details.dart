import '../../long_term_relation/application/relation_counts.dart';
import '../domain/intention.dart';

final class IntentionDetails {
  const IntentionDetails({
    required this.intention,
    required this.relationCounts,
    required this.favoriteMark,
  });

  final Intention intention;
  final RelationCounts relationCounts;

  /// Подтверждённая отметка избранного именно этого намерения.
  /// [FavoriteMark.notFavorite] означает проверенное отсутствие отметки.
  final FavoriteMark favoriteMark;

  int get activeRelationCount => relationCounts.active;
}
