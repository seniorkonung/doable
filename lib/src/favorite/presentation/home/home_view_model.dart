import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../graph/application/graph_change.dart';
import '../../../graph/application/graph_command_coordinator.dart';
import '../../../graph/application/graph_command_result.dart';
import '../../../graph/application/graph_revision.dart';
import '../../../graph/application/personal_graph_repository_provider.dart';
import '../../../intention/application/intention_catalog.dart';
import '../../../intention/domain/intention.dart';
import '../../../intention/domain/intention_id.dart';
import '../../application/favorite_intentions.dart';
import 'home_state.dart';

part 'home_view_model.g.dart';

/// Вид подтверждённого пакета, который повторяет обновление Главной.
enum _RefreshTrigger {
  /// Только пакет, затрагивающий избранное: показанное актуально либо снимка
  /// ещё нет.
  favoriteChange,

  /// Пакет любого состава: показанный снимок не обновлён, и неактуальность
  /// длится до успешного получения.
  anyPackage,
}

@riverpod
final class HomeViewModel extends _$HomeViewModel {
  static const _maxStaleReads = 8;

  late FavoriteReadContract _favorites;
  StreamSubscription<GraphCommandCompletion>? _completions;
  int _generation = 0;
  _RefreshTrigger _refreshTrigger = _RefreshTrigger.favoriteChange;

  /// Ревизия последнего подтверждённого пакета, потребовавшего обновления:
  /// снимок старше неё не публикуется.
  GraphRevision? _requiredRevision;
  Future<void>? _activeRequest;

  /// Пакет, пришедший во время чтения, требует ещё одного чтения, если
  /// текущее его не отразит.
  bool _refreshNeeded = false;
  int _staleReadAttempts = 0;

  /// Изменения счётчиков связей намерений вне показанного списка, пришедшие
  /// во время чтения: получаемый снимок может содержать такое намерение.
  final _countRevisionsDuringRead = <IntentionId, GraphRevision>{};

  @override
  HomeState build() {
    unawaited(_completions?.cancel());
    _favorites = ref.watch(personalGraphRepositoryProvider);
    final coordinator = ref.watch(graphCommandCoordinatorProvider.notifier);
    _generation++;
    _refreshTrigger = _RefreshTrigger.favoriteChange;
    _requiredRevision = null;
    _activeRequest = null;
    _refreshNeeded = false;
    _staleReadAttempts = 0;
    _countRevisionsDuringRead.clear();
    _completions = coordinator.completions.listen(_onCompletion);
    ref.onDispose(() => unawaited(_completions?.cancel()));
    unawaited(_startRead());
    return const HomeLoading();
  }

  /// Повтор доступен только при недоступности — первоначального получения
  /// либо обновления показанного снимка; при остальных состояниях чтение не
  /// запускается.
  Future<void> retry() {
    switch (state) {
      case HomeUnavailable():
        state = const HomeLoading();
      case HomeLoaded(freshness: HomeFreshnessStale(canRetry: true)) &&
          final current:
        state = current.withFreshness(const HomeFreshnessRefreshing());
      case HomeLoading() ||
          HomeLoaded() ||
          HomeCorruption() ||
          HomeUnexpected():
        return Future.value();
    }
    _staleReadAttempts = 0;
    return _startRead();
  }

  /// Перечитывает полный снимок, когда подтверждённый пакет затрагивает
  /// избранное, а пока показанный снимок не обновлён — при пакете любого
  /// состава; согласование не зависит от предъявления результата операции.
  void _onCompletion(GraphCommandCompletion completion) {
    if (!ref.mounted) return;
    final package = completion.confirmedChange;
    if (package == null) return;
    final current = state;
    final affectsFavorites = _affectsFavorites(package, current);
    switch (_refreshTrigger) {
      case _RefreshTrigger.favoriteChange:
        if (!affectsFavorites) return;
      case _RefreshTrigger.anyPackage:
        break;
    }
    final required = _requiredRevision;
    if (required == null ||
        switch (package.revision.compareTo(required)) {
          GraphRevisionOrder.newer || GraphRevisionOrder.differentEpoch => true,
          GraphRevisionOrder.older || GraphRevisionOrder.same => false,
        }) {
      _requiredRevision = package.revision;
    }
    _staleReadAttempts = 0;
    switch (current) {
      case HomeLoaded(freshness: HomeFreshnessCurrent()):
        if (!_precedes(current.revision, package.revision)) return;
        state = current.withFreshness(const HomeFreshnessRefreshing());
      case HomeLoaded(freshness: HomeFreshnessStale()):
        state = current.withFreshness(const HomeFreshnessRefreshing());
      case HomeUnavailable() || HomeCorruption() || HomeUnexpected():
        state = const HomeLoading();
      case HomeLoaded(freshness: HomeFreshnessRefreshing()) || HomeLoading():
        break;
    }
    if (_activeRequest == null) {
      unawaited(_startRead());
    } else {
      _refreshNeeded = true;
    }
  }

  /// Затрагивает избранное каталожная мутация с отметкой в снимке до или
  /// после либо изменение счётчиков связей намерения из показанного списка.
  bool _affectsFavorites(ConfirmedGraphChangePackage package, HomeState shown) {
    final shownIds = switch (shown) {
      HomeList(:final items) => {for (final row in items) row.id},
      _ => const <IntentionId>{},
    };
    var affects = false;
    for (final change in package.changes) {
      switch (change) {
        case IntentionCatalogMutation(:final before, :final after):
          affects =
              affects ||
              before?.summary.favoriteMark == FavoriteMark.favorite ||
              after?.summary.favoriteMark == FavoriteMark.favorite;
        case IntentionRelationCountsChanged(:final intentionId):
          if (shownIds.contains(intentionId)) {
            affects = true;
          } else if (_activeRequest != null) {
            _countRevisionsDuringRead[intentionId] = package.revision;
          }
        case GraphChange():
          break;
      }
    }
    return affects;
  }

  /// Одновременно выполняется не больше одного чтения: пакеты, пришедшие во
  /// время него, дают следующее чтение после его завершения.
  Future<void> _startRead() {
    final active = _activeRequest;
    if (active != null) return active;
    _refreshNeeded = false;
    final future = _load(_generation);
    _activeRequest = future;
    unawaited(
      future.whenComplete(() {
        if (!identical(_activeRequest, future)) return;
        _activeRequest = null;
        if (!ref.mounted) return;
        if (_refreshNeeded) {
          unawaited(_startRead());
        } else {
          _countRevisionsDuringRead.clear();
        }
      }),
    );
    return future;
  }

  /// Ответ публикуется, только пока [generation] остаётся текущим: ответ
  /// прежнего чтения не заменяет состояние нового. Снимок старше требуемой
  /// ревизии не публикуется, а чтение повторяется ограниченное число раз.
  Future<void> _load(int generation) async {
    final result = await _read();
    if (!ref.mounted || generation != _generation) return;
    switch (result) {
      case GraphResultSuccess(:final value):
        final current = state;
        final precedesShown =
            current is HomeLoaded &&
            value.revision.compareTo(current.revision) ==
                GraphRevisionOrder.older;
        final required = _requiredRevision;
        if ((required != null && _precedes(value.revision, required)) ||
            precedesShown ||
            _missesCountChange(value)) {
          if (++_staleReadAttempts >= _maxStaleReads) {
            _refreshNeeded = false;
            _readFailure(const FavoriteIntentionsUnavailableFailure());
          } else {
            _refreshNeeded = true;
          }
          return;
        }
        _refreshNeeded = false;
        _staleReadAttempts = 0;
        _refreshTrigger = _RefreshTrigger.favoriteChange;
        state = _loaded(value);
      case GraphResultFailure(:final failure):
        // Пакет, пришедший во время отказавшего чтения, даёт ещё одно.
        if (_refreshNeeded) return;
        _readFailure(failure);
    }
  }

  /// Снимок содержит намерение, счётчики связей которого изменились во время
  /// чтения позже ревизии снимка.
  bool _missesCountChange(FavoriteIntentionsSnapshot snapshot) {
    var misses = false;
    for (final row in snapshot.items) {
      final changed = _countRevisionsDuringRead[row.id];
      if (changed == null || !_precedes(snapshot.revision, changed)) continue;
      final required = _requiredRevision;
      if (required == null || _precedes(required, changed)) {
        _requiredRevision = changed;
      }
      misses = true;
    }
    return misses;
  }

  /// Отказ обновления сохраняет показанный снимок неактуальным с причиной;
  /// отказ без показанного снимка остаётся отказом получения.
  void _readFailure(FavoriteIntentionsReadFailure failure) {
    final current = state;
    switch (current) {
      case HomeLoaded():
        _refreshTrigger = _RefreshTrigger.anyPackage;
        state = current.withFreshness(HomeFreshnessStale(failure));
      case HomeLoading() ||
          HomeUnavailable() ||
          HomeCorruption() ||
          HomeUnexpected():
        state = switch (failure) {
          FavoriteIntentionsUnavailableFailure() => const HomeUnavailable(),
          FavoriteIntentionsCorruptionFailure() => const HomeCorruption(),
          FavoriteIntentionsUnexpectedFailure() => const HomeUnexpected(),
        };
    }
  }

  bool _precedes(GraphRevision revision, GraphRevision other) =>
      switch (revision.compareTo(other)) {
        GraphRevisionOrder.older || GraphRevisionOrder.differentEpoch => true,
        GraphRevisionOrder.same || GraphRevisionOrder.newer => false,
      };

  Future<FavoriteIntentionsResult> _read() async {
    try {
      return await _favorites.getFavoriteIntentions();
    } on Object {
      return const FavoriteIntentionsError(
        FavoriteIntentionsUnexpectedFailure(),
      );
    }
  }

  HomeLoaded _loaded(FavoriteIntentionsSnapshot snapshot) {
    if (snapshot.items.isNotEmpty) {
      return HomeList(items: snapshot.items, revision: snapshot.revision);
    }
    return HomeEmpty(
      reason: snapshot.archivedCount == 0
          ? HomeEmptyReason.noFavorites
          : HomeEmptyReason.allArchived,
      revision: snapshot.revision,
    );
  }
}
