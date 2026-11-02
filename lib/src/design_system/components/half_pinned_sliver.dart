import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Держит [child] у верхнего края вертикального списка, пока он занимает
/// не больше половины видимой высоты, а выше порога прокручивает его вместе
/// со списком, чтобы высокая шапка не закрывала тело.
///
/// Порог сравнивается на каждой раскладке внутри одного объекта, поэтому смена
/// высоты через порог не меняет дерево и сохраняет состояние [child]. Тело
/// проходит под закреплённым срезом, поэтому непрозрачный фон задаёт
/// потребитель.
final class HalfPinnedSliver extends SingleChildRenderObjectWidget {
  const HalfPinnedSliver({required Widget super.child, super.key});

  @override
  RenderHalfPinnedSliver createRenderObject(BuildContext context) =>
      RenderHalfPinnedSliver();
}

final class RenderHalfPinnedSliver extends RenderSliverSingleBoxAdapter {
  var _isPinned = false;

  @override
  void performLayout() {
    final child = this.child!;
    final constraints = this.constraints;
    child.layout(constraints.asBoxConstraints(), parentUsesSize: true);
    final extent = child.size.height;
    _isPinned = extent <= constraints.viewportMainAxisExtent / 2;
    final cacheExtent = calculateCacheOffset(constraints, from: 0, to: extent);
    if (_isPinned) {
      geometry = SliverGeometry(
        scrollExtent: extent,
        paintOrigin: constraints.overlap,
        paintExtent: math.min(
          extent,
          constraints.remainingPaintExtent - constraints.overlap,
        ),
        layoutExtent: clampDouble(
          extent - constraints.scrollOffset,
          0,
          constraints.remainingPaintExtent,
        ),
        maxPaintExtent: extent,
        maxScrollObstructionExtent: extent,
        cacheExtent: cacheExtent,
        hasVisualOverflow: true,
      );
      (child.parentData! as SliverPhysicalParentData).paintOffset = Offset.zero;
    } else {
      final paintExtent = calculatePaintOffset(
        constraints,
        from: 0,
        to: extent,
      );
      geometry = SliverGeometry(
        scrollExtent: extent,
        paintExtent: paintExtent,
        maxPaintExtent: extent,
        cacheExtent: cacheExtent,
        hasVisualOverflow:
            extent > constraints.remainingPaintExtent ||
            constraints.scrollOffset > 0,
      );
      setChildParentData(child, constraints, geometry!);
    }
  }

  @override
  double childMainAxisPosition(RenderBox child) =>
      _isPinned ? 0 : super.childMainAxisPosition(child);

  // Нажатие мимо частей ребёнка не должно проваливаться к телу под срезом.
  @override
  bool hitTestSelf({
    required double mainAxisPosition,
    required double crossAxisPosition,
  }) => true;

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    // Закреплённый срез не прокручивается, поэтому диктор видит его вне списка.
    if (_isPinned) {
      config.addTagForChildren(RenderViewport.excludeFromScrolling);
    }
  }
}
