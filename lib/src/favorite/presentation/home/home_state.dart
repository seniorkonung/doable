import '../../../graph/application/graph_revision.dart';
import '../../../intention/domain/intention.dart';
import '../../../intention/domain/intention_id.dart';
import '../../application/favorite_intentions.dart';
import '../../domain/favorite_order.dart';

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

/// Перестановка показанного списка.
sealed class HomeReorder {
  const HomeReorder();
}

/// Принятой перестановки нет: показан подтверждённый порядок.
final class HomeReorderIdle extends HomeReorder {
  const HomeReorderIdle();
}

/// Принятая перестановка, запрошенное положение которой ещё не подтверждено
/// цельным снимком: список показывает его с признаком сохранения.
sealed class HomeReorderPending extends HomeReorder {
  const HomeReorderPending({
    required this.intentionId,
    required this.placement,
  });

  final IntentionId intentionId;

  /// Запрошенное положение относительно показанного подтверждённого снимка.
  /// Пока опора остаётся в списке, это размещение команды; если
  /// подтверждённое изменение скрыло опору, — после её ближайшего
  /// показанного предшественника.
  final FavoritePlacement placement;
}

/// Запись выполняется.
final class HomeReorderSaving extends HomeReorderPending {
  const HomeReorderSaving({
    required super.intentionId,
    required super.placement,
  });
}

/// Запись подтверждена на ревизии [revision], а цельного снимка не старше неё
/// ещё нет: показанный подтверждённый снимок несёт прежний порядок.
///
/// Отказ обновления ожидание не прекращает: неактуальный список показывает
/// записанное положение, не выдавая его за подтверждённый снимок, до
/// успешного чтения.
final class HomeReorderAwaitingSnapshot extends HomeReorderPending {
  const HomeReorderAwaitingSnapshot({
    required super.intentionId,
    required super.placement,
    required this.revision,
  });

  final GraphRevision revision;
}

/// Успешно полученный полный снимок избранного на одной ревизии.
sealed class HomeLoaded extends HomeState {
  const HomeLoaded({required this.revision, required this.freshness});

  final GraphRevision revision;
  final HomeFreshness freshness;

  /// Тот же подтверждённый снимок с другой актуальностью.
  HomeLoaded withFreshness(HomeFreshness freshness);
}

/// Все активные избранные намерения в едином ручном порядке; список не пуст.
final class HomeList extends HomeLoaded {
  HomeList({
    required List<FavoriteIntentionRow> items,
    required super.revision,
    super.freshness = const HomeFreshnessCurrent(),
    this.reorder = const HomeReorderIdle(),
  }) : items = List.unmodifiable(items);

  /// Последний подтверждённый снимок в едином ручном порядке.
  final List<FavoriteIntentionRow> items;
  final HomeReorder reorder;

  /// Порядок, который показывает Главная: запрошенное положение принятой
  /// перестановки, пока его не подтвердил цельный снимок, иначе
  /// подтверждённый снимок.
  late final List<FavoriteIntentionRow> displayedItems = switch (reorder) {
    HomeReorderIdle() => items,
    HomeReorderPending(:final intentionId, :final placement) =>
      reorderedItems(intentionId, placement) ?? items,
  };

  /// Перестановку принимает только текущий подтверждённый список без
  /// принятой перестановки.
  bool get acceptsReorder => switch (this) {
    HomeList(freshness: HomeFreshnessCurrent(), reorder: HomeReorderIdle()) =>
      true,
    HomeList() => false,
  };

  /// Подтверждённый список после перемещения [intentionId] по правилу единого
  /// порядка либо `null`, если перемещение не меняет положение намерения в
  /// списке или отклоняется правилом. Все строки списка активны, поэтому
  /// правило над ними совпадает с правилом над видимой частью полного
  /// порядка.
  List<FavoriteIntentionRow>? reorderedItems(
    IntentionId intentionId,
    FavoritePlacement placement,
  ) {
    final shownOrder = FavoriteOrder([
      for (final row in items)
        FavoriteOrderEntry(
          intentionId: row.id,
          archiveState: IntentionArchiveState.active,
        ),
    ]);
    switch (moveInFavoriteOrder(
      shownOrder,
      intentionId: intentionId,
      placement: placement,
    )) {
      case FavoriteOrderMoveApplied(:final order):
        final rows = {for (final row in items) row.id: row};
        return List.unmodifiable([
          for (final id in order.intentionIds) rows[id]!,
        ]);
      case FavoriteOrderMoveWithoutChange() || FavoriteOrderMoveRejected():
        return null;
    }
  }

  @override
  HomeList withFreshness(HomeFreshness freshness) => HomeList(
    items: items,
    revision: revision,
    freshness: freshness,
    reorder: reorder,
  );

  /// Тот же подтверждённый снимок с другим состоянием перестановки.
  HomeList withReorder(HomeReorder reorder) => HomeList(
    items: items,
    revision: revision,
    freshness: freshness,
    reorder: reorder,
  );
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

  @override
  HomeEmpty withFreshness(HomeFreshness freshness) =>
      HomeEmpty(reason: reason, revision: revision, freshness: freshness);
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
