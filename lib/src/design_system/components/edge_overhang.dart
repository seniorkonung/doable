import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Отдаёт ребёнку ширину на [start] и [end] больше своей: лишние полосы лежат
/// за началом и за концом строки, рисуются там и принимают касания, пока
/// родитель шире строки на эти полосы, например поле содержимого с отступами.
final class EdgeOverhang extends SingleChildRenderObjectWidget {
  const EdgeOverhang({
    required Widget super.child,
    this.start = 0,
    this.end = 0,
    super.key,
  });

  final double start;
  final double end;

  @override
  RenderEdgeOverhang createRenderObject(BuildContext context) =>
      RenderEdgeOverhang(
        start: start,
        end: end,
        textDirection: Directionality.of(context),
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderEdgeOverhang renderObject,
  ) {
    renderObject
      ..start = start
      ..end = end
      ..textDirection = Directionality.of(context);
  }
}

final class RenderEdgeOverhang extends RenderShiftedBox {
  RenderEdgeOverhang({
    required this._start,
    required this._end,
    required this._textDirection,
  }) : super(null);

  double _start;
  set start(double value) {
    if (value == _start) return;
    _start = value;
    markNeedsLayout();
  }

  double _end;
  set end(double value) {
    if (value == _end) return;
    _end = value;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  double get _extent => _start + _end;

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
    // Ребёнок сдвинут к стороне, на которую выходит его лишняя полоса.
    (child.parentData! as BoxParentData).offset = switch (_textDirection) {
      TextDirection.ltr => Offset(-_start, 0),
      TextDirection.rtl => Offset(-_end, 0),
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
