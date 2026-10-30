import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/intention_catalog.dart';
import '../../domain/intention_id.dart';
import '../catalog/intention_catalog_state.dart';

/// Хранитель места в списке выдачи поиска намерений.
///
/// Владеет прокруткой списка и ключами его строк. Новая выдача начинается с
/// верхней позиции, а пауза ввода, загрузка и отказы первой порции
/// показываются вместо строк сразу сверху. При обновлении выдачи без смены
/// параметров поиска хранитель сохраняет экранное положение видимого
/// намерения, а если оно исчезло из выдачи — ближайшего соседа. Пока видимая
/// строка не сместилась, хранитель не трогает прокрутку: `jumpTo` оборвал бы
/// инерцию и перетаскивание.
///
/// Выдача сообщает хранителю каждое состояние модели через [onCatalogChanged]
/// из `ref.listen`, до перестройки списка, каждую перестройку — через
/// [onListBuilt] и оборачивает каждую строку в [KeyedSubtree] с ключом
/// [keyFor].
final class ResultsScrollKeeper {
  /// [initial] — выдача, по которой список строится впервые; первая новая
  /// выдача после неё начнётся с верхней позиции. [keepScrollOffset]
  /// передаётся контроллеру прокрутки: сохранять ли смещение в [PageStorage].
  ResultsScrollKeeper({
    required AsyncValue<IntentionCatalogState> initial,
    required bool keepScrollOffset,
  }) : controller = ScrollController(keepScrollOffset: keepScrollOffset),
       _shown = initial,
       _query = _confirmedQuery(initial.value);

  final ScrollController controller;

  /// Выдача, по которой построен список. Она может отставать от модели:
  /// скрытая страница не перестраивается, пока её снова не покажут, и якорь
  /// ждёт перестройки по актуальной выдаче.
  AsyncValue<IntentionCatalogState> _shown;

  final _itemKeys = <IntentionId, GlobalKey>{};

  /// Запрос последней подтверждённой выдачи. Модель сохраняет его объект,
  /// пока согласует и продолжает ту же выдачу, а каждое чтение первой порции —
  /// после смены параметров, повтора или удаления исключённого тега — несёт
  /// новый запрос.
  IntentionCatalogQuery? _query;
  _VisualAnchor? _pendingVisualAnchor;
  bool _maintenanceScheduled = false;
  bool _disposed = false;

  /// Ключ строки намерения [id].
  GlobalKey keyFor(IntentionId id) =>
      _itemKeys.putIfAbsent(id, () => GlobalKey());

  /// Учитывает переход модели от [previous] к [next].
  ///
  /// Возвращает, началась ли новая выдача: тогда список уже переведён к
  /// верхней позиции, если он показан.
  bool onCatalogChanged(
    AsyncValue<IntentionCatalogState>? previous,
    AsyncValue<IntentionCatalogState> next,
  ) {
    final nextState = next.value;
    // Модель публикует каждую выдачу, в том числе когда список до неё не был
    // показан.
    var startsNewResults = false;
    final query = _confirmedQuery(nextState);
    if (query != null && !identical(query, _query)) {
      startsNewResults = _query != null;
      _query = query;
      if (startsNewResults) {
        _jumpToTop();
      }
    }
    // Состояние заменяет строки в той же прокрутке. Пока прокрутка движется,
    // смещение прежней выдачи не прижимается к краю сжавшегося содержимого,
    // и состояние возвращалось бы к началу пружиной.
    if (_showsStatusInsteadOfRows(next)) {
      _jumpToTop();
    }

    final previousState = previous?.value;
    if (nextState is! IntentionCatalogLoaded) {
      return startsNewResults;
    }
    if (_pendingVisualAnchor == null &&
        previousState is IntentionCatalogLoaded &&
        identical(previousState.query, nextState.query) &&
        _isShownResultsOf(nextState) &&
        _mayShiftVisibleRow(previousState, nextState)) {
      _pendingVisualAnchor = _captureVisualAnchor(previousState);
    }
    return startsNewResults;
  }

  /// Учитывает перестройку списка по выдаче [catalog]: после кадра строки уже
  /// разложены, и хранитель восстанавливает по ним место в списке.
  void onListBuilt(AsyncValue<IntentionCatalogState> catalog) {
    if (identical(catalog, _shown)) {
      return;
    }
    _shown = catalog;
    _scheduleMaintenance();
  }

  void dispose() {
    _disposed = true;
    controller.dispose();
  }

  /// Повторяет выбор выдачи: загрузка и ошибка модели показываются вместо
  /// данных.
  static bool _showsStatusInsteadOfRows(
    AsyncValue<IntentionCatalogState> catalog,
  ) => catalog.when(
    skipLoadingOnReload: false,
    skipLoadingOnRefresh: false,
    data: (state) => switch (state) {
      IntentionCatalogDebouncing() ||
      IntentionCatalogUnavailable() ||
      IntentionCatalogCorruption() ||
      IntentionCatalogUnexpected() => true,
      IntentionCatalogInvalidFilter() ||
      IntentionCatalogLoaded() ||
      IntentionCatalogEmpty() => false,
    },
    error: (_, _) => true,
    loading: () => true,
  );

  static IntentionCatalogQuery? _confirmedQuery(IntentionCatalogState? state) =>
      switch (state) {
        IntentionCatalogConfirmedState(:final query) => query,
        _ => null,
      };

  void _jumpToTop() {
    // Список начинается с верхней позиции: отложенный якорь прежней выдачи
    // больше не действует.
    _pendingVisualAnchor = null;
    if (controller.hasClients) {
      controller.jumpTo(0);
    }
  }

  /// Построен ли список по выдаче того же запроса, что и [state].
  ///
  /// Скрытая страница не перестраивается, поэтому выдача, начатая под закрытой
  /// страницей, ещё не показана: построенные строки и их ключи принадлежат
  /// прежней выдаче, и якорь по ним указал бы чужое место. Новая выдача
  /// начинается сверху, пока список не перестроен по её запросу.
  bool _isShownResultsOf(IntentionCatalogLoaded state) {
    final shown = _shown.value;
    return shown is IntentionCatalogLoaded &&
        identical(shown.query, state.query);
  }

  /// Может ли переход от [previous] к [next] сдвинуть видимую строку.
  ///
  /// Строки, добавленные за прежней выдачей, и отметки занятых пар этих новых
  /// строк видимую строку не сдвигают. Отметка прежней строки сдвигает: она
  /// добавляет строке или убирает у неё линию меток, и строки под ней
  /// смещаются.
  bool _mayShiftVisibleRow(
    IntentionCatalogLoaded previous,
    IntentionCatalogLoaded next,
  ) {
    final previousItems = previous.items;
    final nextItems = next.items;
    if (nextItems.length < previousItems.length) {
      return true;
    }
    for (var index = 0; index < previousItems.length; index++) {
      if (!identical(previousItems[index], nextItems[index])) {
        return true;
      }
    }
    // Карту создаёт заново каждое состояние, поэтому отметки сравниваются по
    // содержимому.
    return previousItems.any(
      (item) => previous.pairOccupants[item.id] != next.pairOccupants[item.id],
    );
  }

  _VisualAnchor? _captureVisualAnchor(IntentionCatalogLoaded state) {
    if (!controller.hasClients) {
      return null;
    }
    final items = state.items;
    final currentOffset = controller.position.pixels;
    for (var index = 0; index < items.length; index++) {
      final extent = _builtItemExtent(items[index].id);
      if (extent == null) {
        continue;
      }
      // Верх списка может прийтись на промежуток между строками: тогда якорем
      // становится ближайшая строка ниже, а сдвиг внутри неё отрицателен.
      if (extent.end > currentOffset) {
        return _VisualAnchor(
          candidateIds: _idsByDistance(items, index),
          itemStart: extent.start,
          offsetWithinItem: currentOffset - extent.start,
          remainingApproaches: _VisualAnchor.maxApproaches,
        );
      }
    }
    return null;
  }

  /// Строка [index] и её соседи от ближних к дальним: якорь ждёт перестройки
  /// списка, и за это время из выдачи могут уйти и она, и ближайшие соседи.
  List<IntentionId> _idsByDistance(List<IntentionSummary> items, int index) => [
    items[index].id,
    for (var distance = 1; distance < items.length; distance++) ...[
      if (index + distance < items.length) items[index + distance].id,
      if (index - distance >= 0) items[index - distance].id,
    ],
  ];

  void _scheduleMaintenance() {
    if (_maintenanceScheduled) {
      return;
    }
    _maintenanceScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maintenanceScheduled = false;
      if (_disposed) {
        return;
      }
      _restoreVisualAnchor();
      _pruneItemKeys();
    });
  }

  void _restoreVisualAnchor() {
    final anchor = _pendingVisualAnchor;
    _pendingVisualAnchor = null;
    final state = _shown.value;
    if (anchor == null ||
        !controller.hasClients ||
        state is! IntentionCatalogLoaded) {
      return;
    }

    final targetIndex = _anchorTargetIndex(anchor, state.items);
    if (targetIndex == null) {
      return;
    }
    final position = controller.position;
    final exact = _builtItemExtent(state.items[targetIndex].id);
    if (exact != null) {
      // Сосед, занявший место ушедшей строки, тоже уже на месте. Смещение
      // прокрутки здесь не показатель: за время ожидания кадра его меняет сама
      // идущая прокрутка.
      if (!nearEqual(
        exact.start,
        anchor.itemStart,
        Tolerance.defaultTolerance.distance,
      )) {
        _jumpWithinExtent(position, exact.start + anchor.offsetWithinItem);
      }
      return;
    }

    // Много строк, вставленных или удалённых перед якорем, уводят его за
    // пределы построенной области списка. Сначала приближаемся к нему по
    // размеру построенных строк, а точное положение восстанавливаем в
    // следующем кадре, когда якорь уже построен.
    final estimate = _estimateItemStart(state.items, targetIndex);
    if (estimate == null || anchor.remainingApproaches == 0) {
      return;
    }
    _jumpWithinExtent(position, estimate + anchor.offsetWithinItem);
    _pendingVisualAnchor = anchor.afterApproach();
    _scheduleMaintenance();
  }

  int? _anchorTargetIndex(_VisualAnchor anchor, List<IntentionSummary> items) {
    final indexes = {for (final (index, item) in items.indexed) item.id: index};
    for (final id in anchor.candidateIds) {
      final index = indexes[id];
      if (index != null) {
        return index;
      }
    }
    return null;
  }

  double? _estimateItemStart(List<IntentionSummary> items, int targetIndex) {
    ({int index, _ItemExtent extent})? first;
    ({int index, _ItemExtent extent})? last;
    for (var index = 0; index < items.length; index++) {
      final extent = _builtItemExtent(items[index].id);
      if (extent == null) {
        continue;
      }
      first ??= (index: index, extent: extent);
      last = (index: index, extent: extent);
    }
    if (first == null || last == null) {
      return null;
    }
    final averageExtent =
        (last.extent.end - first.extent.start) / (last.index - first.index + 1);
    if (targetIndex > last.index) {
      return last.extent.end + (targetIndex - last.index - 1) * averageExtent;
    }
    return first.extent.start - (first.index - targetIndex) * averageExtent;
  }

  _ItemExtent? _builtItemExtent(IntentionId id) {
    final renderObject = _itemKeys[id]?.currentContext?.findRenderObject();
    if (renderObject == null || !renderObject.attached) {
      return null;
    }
    final viewport = RenderAbstractViewport.maybeOf(renderObject);
    if (viewport == null) {
      return null;
    }
    final revealed = viewport.getOffsetToReveal(renderObject, 0);
    return (
      start: revealed.offset,
      end: revealed.offset + revealed.rect.height,
    );
  }

  void _jumpWithinExtent(ScrollPosition position, double target) {
    position.jumpTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
  }

  void _pruneItemKeys() {
    final state = _shown.value;
    if (state is! IntentionCatalogLoaded) {
      return;
    }
    final currentIds = state.items.map((item) => item.id).toSet();
    _itemKeys.removeWhere((id, _) => !currentIds.contains(id));
  }
}

/// Положение строки в прокручиваемой области списка.
typedef _ItemExtent = ({double start, double end});

final class _VisualAnchor {
  const _VisualAnchor({
    required this.candidateIds,
    required this.itemStart,
    required this.offsetWithinItem,
    required this.remainingApproaches,
  });

  /// Предел кадров приближения к якорю за пределами построенной области.
  static const maxApproaches = 3;

  final List<IntentionId> candidateIds;

  /// Начало строки в содержимом списка, когда запомнен якорь.
  final double itemStart;

  /// Сдвиг верха списка от начала строки; отрицателен, когда верх списка
  /// пришёлся на промежуток перед строкой.
  final double offsetWithinItem;
  final int remainingApproaches;

  _VisualAnchor afterApproach() => _VisualAnchor(
    candidateIds: candidateIds,
    itemStart: itemStart,
    offsetWithinItem: offsetWithinItem,
    remainingApproaches: remainingApproaches - 1,
  );
}
