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
import '../../application/favorite_order_command.dart';
import '../../domain/favorite_order.dart';
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
  late GraphCommandCoordinator _coordinator;
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

  /// Перестановка, принятая этой Главной, до её завершения и цельного снимка,
  /// подтверждающего запись.
  _HomeMove? _move;

  @override
  HomeState build() {
    unawaited(_completions?.cancel());
    _favorites = ref.watch(personalGraphRepositoryProvider);
    _coordinator = ref.watch(graphCommandCoordinatorProvider.notifier);
    _generation++;
    _refreshTrigger = _RefreshTrigger.favoriteChange;
    _requiredRevision = null;
    _activeRequest = null;
    _refreshNeeded = false;
    _staleReadAttempts = 0;
    _countRevisionsDuringRead.clear();
    _move = null;
    _completions = _coordinator.completions.listen(_onCompletion);
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

  /// Перемещает [intentionId] по текущему подтверждённому списку.
  ///
  /// Команду получает координатор, только пока показан текущий
  /// подтверждённый список без принятой перестановки и перемещение меняет
  /// положение намерения в этом списке; иначе перемещение не отправляется и
  /// не ставится в очередь. Пока запись не подтверждена цельным снимком,
  /// список показывает запрошенное положение с признаком сохранения. Отказ
  /// здесь не предъявляется: по ADR-0016 он сразу принадлежит общей
  /// поверхности.
  void move(IntentionId intentionId, FavoritePlacement placement) {
    final current = state;
    if (current is! HomeList || !current.acceptsReorder) return;
    final requested = current.reorderedItems(intentionId, placement);
    if (requested == null) return;
    switch (_coordinator.acceptFavoriteOrderMove(
      MoveFavoriteIntention(intentionId: intentionId, placement: placement),
    )) {
      case FavoriteOrderCommandAccepted(:final token):
        _move = _HomeMove(
          token: token,
          intentionId: intentionId,
          predecessors: [
            for (final row in requested.takeWhile(
              (row) => row.id != intentionId,
            ))
              row.id,
          ].reversed.toList(growable: false),
        );
        state = current.withReorder(_reorderIn(current.items));
      case FavoriteOrderCommandAlreadyRunning() ||
          GraphCommandCoordinatorDraining():
        break;
    }
  }

  /// Завершает перестановку этой Главной по её результату и перечитывает
  /// полный снимок, когда подтверждённый пакет затрагивает избранное, а пока
  /// показанный снимок не обновлён — при пакете любого состава; согласование
  /// не зависит от видимости Главной и предъявления результата операции.
  void _onCompletion(GraphCommandCompletion completion) {
    if (!ref.mounted) return;
    final move = _move;
    if (completion case FavoriteOrderCommandCompletion(:final token)
        when move != null && token == move.token) {
      _finishMove(move, completion);
    }
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
    if (current case HomeLoaded(freshness: HomeFreshnessCurrent())
        when !_precedes(current.revision, package.revision)) {
      return;
    }
    _requestSnapshot();
  }

  /// Завершает принятую перестановку по результату координатора.
  ///
  /// Подтверждённая запись ждёт цельного снимка не старше своей ревизии, а
  /// его чтение вызывает пакет изменения порядка. Успех без изменения и
  /// отказ возвращают последний подтверждённый порядок; конфликт
  /// актуального состояния дополнительно запрашивает актуальный снимок.
  /// Перемещение не повторяется.
  void _finishMove(_HomeMove move, FavoriteOrderCommandCompletion completion) {
    var conflict = false;
    switch (completion) {
      case FavoriteOrderConfirmedCompletion(
        success: FavoriteOrderMoved(:final change),
      ):
        _move = move.confirmedAt(change.revision);
      case FavoriteOrderConfirmedCompletion(success: FavoriteOrderUnchanged()):
        _move = null;
      case FavoriteOrderFailedCompletion(:final failure):
        _move = null;
        conflict = switch (failure) {
          FavoriteOrderConflictFailure() => true,
          FavoriteOrderInputFailure() ||
          FavoriteOrderUnavailableFailure() ||
          FavoriteOrderCorruptionFailure() ||
          FavoriteOrderUnexpectedFailure() => false,
        };
    }
    final current = state;
    if (current is HomeLoaded) {
      _settleMove(current.revision);
      state = _withMove(current);
    }
    if (conflict) {
      _staleReadAttempts = 0;
      _requestSnapshot();
    }
  }

  /// Запрашивает актуальный снимок: показанный остаётся с пометкой
  /// обновления, а вместо отказа получения показывается загрузка.
  void _requestSnapshot() {
    final current = state;
    switch (current) {
      case HomeLoaded(
        freshness: HomeFreshnessCurrent() || HomeFreshnessStale(),
      ):
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

  /// Затрагивает избранное изменение порядка, каталожная мутация с отметкой в
  /// снимке до или после либо изменение счётчиков связей намерения из
  /// показанного списка. Подтверждение прежнего порядка ничего не меняет.
  bool _affectsFavorites(ConfirmedGraphChangePackage package, HomeState shown) {
    final shownIds = switch (shown) {
      HomeList(:final items) => {for (final row in items) row.id},
      _ => const <IntentionId>{},
    };
    var affects = false;
    for (final change in package.changes) {
      switch (change) {
        case FavoriteOrderChangedChange():
          affects = true;
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
        _settleMove(value.revision);
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
  /// отказ без показанного снимка остаётся отказом получения. Перестановку
  /// отказ не завершает: подтверждённая запись ждёт цельного снимка до
  /// успешного чтения, поэтому неактуальный список не изображает её
  /// откатившейся, а записанное положение не становится подтверждённым
  /// снимком.
  void _readFailure(FavoriteIntentionsReadFailure failure) {
    final current = state;
    switch (current) {
      case HomeLoaded():
        _refreshTrigger = _RefreshTrigger.anyPackage;
        state = _withMove(current.withFreshness(HomeFreshnessStale(failure)));
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
      return HomeList(
        items: snapshot.items,
        revision: snapshot.revision,
        reorder: _reorderIn(snapshot.items),
      );
    }
    return HomeEmpty(
      reason: snapshot.archivedCount == 0
          ? HomeEmptyReason.noFavorites
          : HomeEmptyReason.allArchived,
      revision: snapshot.revision,
    );
  }

  /// Цельный снимок ревизии [snapshotRevision] не старше подтверждённой
  /// записи уже несёт её результат, и перестановка завершена.
  void _settleMove(GraphRevision snapshotRevision) {
    final confirmed = _move?.confirmedRevision;
    if (confirmed != null && !_precedes(snapshotRevision, confirmed)) {
      _move = null;
    }
  }

  /// Состояние перестановки над показанным подтверждённым снимком [items].
  HomeReorder _reorderIn(List<FavoriteIntentionRow> items) => switch (_move) {
    null => const HomeReorderIdle(),
    final move && _HomeMove(confirmedRevision: null) => HomeReorderSaving(
      intentionId: move.intentionId,
      placement: move.placementIn(items),
    ),
    final move && _HomeMove(:final GraphRevision confirmedRevision) =>
      HomeReorderAwaitingSnapshot(
        intentionId: move.intentionId,
        placement: move.placementIn(items),
        revision: confirmedRevision,
      ),
  };

  HomeLoaded _withMove(HomeLoaded loaded) => switch (loaded) {
    HomeList(:final items) => loaded.withReorder(_reorderIn(items)),
    HomeEmpty() => loaded,
  };
}

/// Перестановка, принятая координатором по запросу этой Главной.
final class _HomeMove {
  const _HomeMove({
    required this.token,
    required this.intentionId,
    required this.predecessors,
    this.confirmedRevision,
  });

  final FavoriteOrderOperationToken token;
  final IntentionId intentionId;

  /// Намерения, стоявшие перед перемещаемым в запрошенном положении при
  /// приёме, начиная с ближайшего: первое из них — опора команды, а при
  /// размещении первым список пуст.
  final List<IntentionId> predecessors;

  /// Ревизия подтверждённой записи; `null`, пока запись выполняется.
  final GraphRevision? confirmedRevision;

  /// Запрошенное положение в показанном списке [items]: сразу после
  /// ближайшего предшественника, который остаётся в списке, иначе первым.
  ///
  /// Подтверждённое изменение во время перестановки может скрыть опору
  /// архивированием. Запись всё равно ставит намерение сразу после неё во
  /// всём порядке, и в списке оно оказывается после ближайшего показанного
  /// предшественника опоры, а не на прежнем месте.
  FavoritePlacement placementIn(List<FavoriteIntentionRow> items) {
    final shown = {for (final row in items) row.id};
    for (final id in predecessors) {
      if (shown.contains(id)) return AfterFavoritePlacement(id);
    }
    return const FirstFavoritePlacement();
  }

  _HomeMove confirmedAt(GraphRevision revision) => _HomeMove(
    token: token,
    intentionId: intentionId,
    predecessors: predecessors,
    confirmedRevision: revision,
  );
}
