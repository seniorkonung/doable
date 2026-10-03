import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Высота, которую компоновка поиска отводит выдаче под параметрами.
enum IntentionSearchResultsExtent {
  /// Пока параметры оставляют выдаче не меньше трети высоты, выдача занимает
  /// всё оставшееся место и страница не прокручивается. При нехватке места —
  /// увеличенный текст, открытая клавиатура, много условий по тегам — выдача
  /// получает всю высоту, а параметры и выдача прокручиваются вместе.
  remainingWhenSufficient,

  /// Выдача всегда получает всю высоту, а параметры и выдача прокручиваются
  /// вместе: прокрученная до конца выдача занимает всю область просмотра при
  /// любой высоте параметров.
  fullViewport,
}

/// Компоновка страницы поиска намерений: параметры поиска над выдачей.
///
/// Высоту выдачи определяет [resultsExtent]. Когда выдача получает всю высоту,
/// параметры и выдача прокручиваются вместе, поэтому ни поле названия, ни
/// условия, ни строки результата не переполняют экран.
final class IntentionSearchLayout extends StatefulWidget {
  const IntentionSearchLayout({
    required this.controls,
    required this.results,
    this.resultsExtent = IntentionSearchResultsExtent.remainingWhenSufficient,
    super.key,
  });

  /// Поле названия, условия по тегам и остальные параметры поиска.
  final Widget controls;

  /// Состояние выдачи с собственной прокруткой списка результатов.
  final Widget results;

  final IntentionSearchResultsExtent resultsExtent;

  @override
  State<IntentionSearchLayout> createState() => _IntentionSearchLayoutState();
}

final class _IntentionSearchLayoutState extends State<IntentionSearchLayout> {
  final _scrollController = _PageScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Продолжает прокрутку страницы, когда список выдачи дошёл до своего края
  /// под пальцем или во время инерции флинга.
  ///
  /// Страница проходит остаток пути, на который список ушёл бы за край, и
  /// продолжает оставшуюся инерцию. Без этого жест внутри списка не возвращал
  /// бы к параметрам поиска и не доводил бы до конца выдачи, скрытого за
  /// нижним краем экрана.
  bool _continuePageScroll(OverscrollNotification notification) {
    if (_continuesPage(notification)) {
      _scrollController.scrollWithin(notification.overscroll);
      if (notification.velocity != 0) {
        _scrollController.fling(notification.velocity);
      }
    }
    return false;
  }

  /// Передаёт странице флинг, начатый у края списка выдачи.
  ///
  /// Список, отпущенный у своего края с инерцией к этому краю, сам не
  /// прокручивается и не сообщает о выходе за край, поэтому инерцию
  /// продолжает страница.
  bool _continuePageFling(ScrollEndNotification notification) {
    final fingerVelocity = notification.dragDetails?.primaryVelocity;
    if (!_continuesPage(notification) || fingerVelocity == null) {
      return false;
    }
    // Палец, идущий вверх, прокручивает к концу.
    final velocity = -fingerVelocity;
    final metrics = notification.metrics;
    final atEdgeAhead = switch (velocity) {
      > 0 => metrics.pixels >= metrics.maxScrollExtent,
      < 0 => metrics.pixels <= metrics.minScrollExtent,
      _ => false,
    };
    if (atEdgeAhead) {
      _scrollController.fling(velocity);
    }
    return false;
  }

  /// Продолжает ли страница прокрутку из уведомления [notification]: оно
  /// пришло от самого списка выдачи, который прокручивается в том же
  /// направлении, что и страница.
  bool _continuesPage(ScrollNotification notification) =>
      notification.depth == 0 &&
      notification.metrics.axisDirection == AxisDirection.down &&
      _scrollController.hasClients;

  @override
  Widget build(BuildContext context) => CustomScrollView(
    controller: _scrollController,
    slivers: [
      SliverToBoxAdapter(child: widget.controls),
      _SliverSearchResults(
        extent: widget.resultsExtent,
        child: NotificationListener<OverscrollNotification>(
          onNotification: _continuePageScroll,
          child: NotificationListener<ScrollEndNotification>(
            onNotification: _continuePageFling,
            child: widget.results,
          ),
        ),
      ),
    ],
  );
}

/// Прокрутка страницы, которая продолжает жест, дошедший до края списка
/// выдачи.
final class _PageScrollController extends ScrollController {
  /// Позицию создаёт сам контроллер, поэтому её тип известен [fling].
  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => ScrollPositionWithSingleContext(
    physics: physics,
    context: context,
    initialPixels: initialScrollOffset,
    keepScrollOffset: keepScrollOffset,
    oldPosition: oldPosition,
    debugLabel: debugLabel,
  );

  /// Сдвигает страницу на [delta] в пределах её прокрутки.
  void scrollWithin(double delta) {
    for (final position in positions) {
      position.jumpTo(
        (position.pixels + delta).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
    }
  }

  /// Продолжает прокрутку страницы инерцией со скоростью [velocity] в
  /// пикселях в секунду; положительная скорость ведёт к концу.
  void fling(double velocity) {
    for (final position in positions) {
      (position as ScrollPositionWithSingleContext).goBallistic(velocity);
    }
  }
}

final class _SliverSearchResults extends SingleChildRenderObjectWidget {
  const _SliverSearchResults({
    required this.extent,
    required Widget super.child,
  });

  final IntentionSearchResultsExtent extent;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSliverSearchResults(extent);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSliverSearchResults renderObject,
  ) {
    renderObject.extent = extent;
  }
}

/// Выдача занимает остаток области просмотра либо всю её высоту.
final class _RenderSliverSearchResults extends RenderSliverSingleBoxAdapter {
  _RenderSliverSearchResults(this._extent);

  /// Наименьшая доля высоты, при которой выдача остаётся под параметрами.
  static const _minRemainingFraction = 1 / 3;

  IntentionSearchResultsExtent _extent;

  set extent(IntentionSearchResultsExtent value) {
    if (value == _extent) {
      return;
    }
    _extent = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final viewport = constraints.viewportMainAxisExtent;
    final remaining = viewport - constraints.precedingScrollExtent;
    final extent = switch (_extent) {
      IntentionSearchResultsExtent.fullViewport => viewport,
      IntentionSearchResultsExtent.remainingWhenSufficient =>
        remaining >= viewport * _minRemainingFraction ? remaining : viewport,
    };
    child!.layout(
      constraints.asBoxConstraints(minExtent: extent, maxExtent: extent),
    );
    geometry = SliverGeometry(
      scrollExtent: extent,
      paintExtent: calculatePaintOffset(constraints, from: 0, to: extent),
      cacheExtent: calculateCacheOffset(constraints, from: 0, to: extent),
      maxPaintExtent: extent,
      hasVisualOverflow:
          extent > constraints.remainingPaintExtent ||
          constraints.scrollOffset > 0,
    );
    setChildParentData(child!, constraints, geometry!);
  }
}
