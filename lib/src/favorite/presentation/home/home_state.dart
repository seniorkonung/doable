import '../../../graph/application/graph_revision.dart';
import '../../application/favorite_intentions.dart';

sealed class HomeState {
  const HomeState();
}

/// Список ещё получается: это не пустая Главная и не отказ.
final class HomeLoading extends HomeState {
  const HomeLoading();
}

/// Актуальность показанного подтверждённого снимка.
sealed class HomeFreshness {
  const HomeFreshness();
}

final class HomeFreshnessCurrent extends HomeFreshness {
  const HomeFreshnessCurrent();
}

final class HomeFreshnessRefreshing extends HomeFreshness {
  const HomeFreshnessRefreshing();
}

/// Снимок не обновлён: [failure] — причина отказа последнего обновления.
final class HomeFreshnessStale extends HomeFreshness {
  const HomeFreshnessStale(this.failure);

  final FavoriteIntentionsReadFailure failure;
  bool get canRetry => failure is FavoriteIntentionsUnavailableFailure;
}

/// Успешно полученный полный снимок избранного на одной ревизии.
sealed class HomeLoaded extends HomeState {
  const HomeLoaded({required this.revision, required this.freshness});

  final GraphRevision revision;
  final HomeFreshness freshness;
}

/// Все активные избранные намерения в едином ручном порядке; список не пуст.
final class HomeList extends HomeLoaded {
  HomeList({
    required List<FavoriteIntentionRow> items,
    required super.revision,
    super.freshness = const HomeFreshnessCurrent(),
  }) : items = List.unmodifiable(items);

  final List<FavoriteIntentionRow> items;
}

enum HomeEmptyReason {
  /// В личном графе нет ни одного избранного намерения.
  noFavorites,

  /// Избранные намерения существуют, но все они архивированы.
  allArchived,
}

final class HomeEmpty extends HomeLoaded {
  const HomeEmpty({
    required this.reason,
    required super.revision,
    super.freshness = const HomeFreshnessCurrent(),
  });

  final HomeEmptyReason reason;
}

/// Доказанно устранимый отказ первоначального получения: доступен повтор.
final class HomeUnavailable extends HomeState {
  const HomeUnavailable();
}

/// Повреждение сохранённых данных избранного: повтор не восстанавливает.
final class HomeCorruption extends HomeState {
  const HomeCorruption();
}

/// Отказ, который нельзя доказанно классифицировать: повтор не предлагается.
final class HomeUnexpected extends HomeState {
  const HomeUnexpected();
}
