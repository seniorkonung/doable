import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Отдаёт ребёнку ширину на [extent] больше своей: лишняя полоса лежит
/// за концом строки, рисуется там и принимает касания, пока родитель
/// шире строки на эту полосу, например поле содержимого с отступами.
final class EndOverhang extends SingleChildRenderObjectWidget {
  const EndOverhang({
    required this.extent,
    required Widget super.child,
    super.key,
  });

  final double extent;

  @override
  RenderEndOverhang createRenderObject(BuildContext context) =>
      RenderEndOverhang(
        extent: extent,
        textDirection: Directionality.of(context),
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderEndOverhang renderObject,
  ) {
    renderObject
      ..extent = extent
      ..textDirection = Directionality.of(context);
  }
}

final class RenderEndOverhang extends RenderShiftedBox {
  RenderEndOverhang({required this._extent, required this._textDirection})
    : super(null);

  double _extent;
  set extent(double value) {
    if (value == _extent) return;
    _extent = value;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  BoxConstraints _childConstraints(BoxConstraints constraints) =>
      constraints.copyWith(
        minWidth: constraints.minWidth + _extent,
        maxWidth: constraints.maxWidth + _extent,
      );

  Size _sizeFor(BoxConstraints constraints, Size childSize) =>
      constraints.constrain(
        Size(math.max(0, childSize.width - _extent), childSize.height),
      );

  @override
  double computeMinIntrinsicWidth(double height) =>
      math.max(0, child!.getMinIntrinsicWidth(height) - _extent);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      math.max(0, child!.getMaxIntrinsicWidth(height) - _extent);

  @override
  double computeMinIntrinsicHeight(double width) =>
      child!.getMinIntrinsicHeight(width + _extent);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      child!.getMaxIntrinsicHeight(width + _extent);

  @override
  Size computeDryLayout(BoxConstraints constraints) => _sizeFor(
    constraints,
    child!.getDryLayout(_childConstraints(constraints)),
  );

  @override
  void performLayout() {
    final child = this.child!;
    child.layout(_childConstraints(constraints), parentUsesSize: true);
    size = _sizeFor(constraints, child.size);
    (child.parentData! as BoxParentData).offset = switch (_textDirection) {
      TextDirection.ltr => Offset.zero,
      TextDirection.rtl => Offset(-_extent, 0),
    };
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final child = this.child!;
    final childOffset = (child.parentData! as BoxParentData).offset;
    if (!(childOffset & child.size).contains(position) ||
        !hitTestChildren(result, position: position)) {
      return false;
    }
    result.add(BoxHitTestEntry(this, position));
    return true;
  }
}
