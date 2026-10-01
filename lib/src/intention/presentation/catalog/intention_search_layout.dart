import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Компоновка страницы поиска намерений: параметры поиска над выдачей.
///
/// Пока параметры оставляют выдаче не меньше трети высоты, выдача занимает
/// всё оставшееся место и страница не прокручивается. При нехватке места —
/// увеличенный текст, открытая клавиатура, много условий по тегам — выдача
/// получает полную высоту, а параметры и выдача прокручиваются вместе, поэтому
/// ни поле названия, ни условия, ни строки результата не переполняют экран.
final class IntentionSearchLayout extends StatefulWidget {
  const IntentionSearchLayout({
    required this.controls,
    required this.results,
    super.key,
  });

  /// Поле названия, условия по тегам и остальные параметры поиска.
  final Widget controls;

  /// Состояние выдачи с собственной прокруткой списка результатов.
  final Widget results;

  @override
  State<IntentionSearchLayout> createState() => _IntentionSearchLayoutState();
}

final class _IntentionSearchLayoutState extends State<IntentionSearchLayout> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Продолжает прокрутку страницы, когда список выдачи дошёл до своего края.
  ///
  /// Без этого жест внутри списка не возвращал бы к параметрам поиска и не
  /// доводил бы до конца выдачи, скрытого за нижним краем экрана.
  bool _continuePageScroll(OverscrollNotification notification) {
    if (notification.depth == 0 &&
        notification.metrics.axis == Axis.vertical &&
        notification.dragDetails != null &&
        _scrollController.hasClients) {
      final position = _scrollController.position;
      position.jumpTo(
        (position.pixels + notification.overscroll).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => CustomScrollView(
    controller: _scrollController,
    slivers: [
      SliverToBoxAdapter(child: widget.controls),
      _SliverSearchResults(
        child: NotificationListener<OverscrollNotification>(
          onNotification: _continuePageScroll,
          child: widget.results,
        ),
      ),
    ],
  );
}

final class _SliverSearchResults extends SingleChildRenderObjectWidget {
  const _SliverSearchResults({required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSliverSearchResults();
}

/// Выдача занимает остаток области просмотра либо всю её высоту.
final class _RenderSliverSearchResults extends RenderSliverSingleBoxAdapter {
  /// Наименьшая доля высоты, при которой выдача остаётся под параметрами.
  static const _minRemainingFraction = 1 / 3;

  @override
  void performLayout() {
    final viewport = constraints.viewportMainAxisExtent;
    final remaining = viewport - constraints.precedingScrollExtent;
    final extent = remaining >= viewport * _minRemainingFraction
        ? remaining
        : viewport;
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
