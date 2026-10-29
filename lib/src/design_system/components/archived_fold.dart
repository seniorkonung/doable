import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';
import '../doable_type.dart';

/// Строка в конце списка, которая сворачивает архивные элементы: значок
/// архива, подпись, число и шеврон.
///
/// Шеврон смотрит вниз у свёрнутого архива и вверх у раскрытого, поворот
/// анимирован. Кнопка высотой `tap-min` стоит у левого края, а её область
/// нажатия выходит на 4 вверх и вниз за строку: в списке строка занимает 36,
/// и соседние строки сохраняют отступ `space-2`. Подпись, доступное название,
/// которое называет группу, число и состояние задаёт потребитель.
final class ArchivedFold extends StatelessWidget {
  const ArchivedFold({
    required this.text,
    required this.count,
    required this.open,
    required this.label,
    required this.onToggle,
    super.key,
  }) : assert(count >= 0);

  /// Подпись строки, например «Архив».
  final String text;

  /// Число архивных элементов.
  final int count;

  /// Архивные элементы показаны.
  final bool open;

  /// Доступное название кнопки, оно называет группу.
  final String label;

  final VoidCallback onToggle;

  static const double _overhang =
      (DoableMetrics.tapMin - DoableMetrics.controlHeightSm) / 2;
  static const double _iconSize = 14;
  static const double _chevronSize = 16;
  static const double _gap = 6;
  static const Duration _turnDuration = Duration(milliseconds: 180);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final style = DoableType.label.copyWith(color: colors.muted);

    return _VerticalOverhang(
      extent: _overhang,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        // Высота строки не зависит от того, ограничил ли её родитель.
        heightFactor: 1,
        child: MergeSemantics(
          child: Semantics(
            label: label,
            button: true,
            enabled: true,
            expanded: open,
            child: TextButton(
              onPressed: onToggle,
              style: TextButton.styleFrom(
                foregroundColor: colors.muted,
                minimumSize: const Size(0, DoableMetrics.tapMin),
                padding: const EdgeInsets.symmetric(
                  horizontal: DoableMetrics.space1,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(DoableMetrics.radiusSm),
                ),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: ExcludeSemantics(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: _gap,
                  children: [
                    DoableIcon(
                      DoableIconData.archive,
                      size: _iconSize,
                      color: colors.muted,
                    ),
                    Flexible(child: Text(text, style: style)),
                    Text(
                      '$count',
                      style: style.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    AnimatedRotation(
                      turns: open ? .5 : 0,
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : _turnDuration,
                      child: DoableIcon(
                        DoableIconData.chevronDown,
                        size: _chevronSize,
                        color: colors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Занимает в родителе на `2 * extent` меньше высоты ребёнка: ребёнок выходит
/// за свои границы на [extent] вверх и вниз, рисуется там и принимает касания.
final class _VerticalOverhang extends SingleChildRenderObjectWidget {
  const _VerticalOverhang({required this.extent, required Widget super.child});

  final double extent;

  @override
  _RenderVerticalOverhang createRenderObject(BuildContext context) =>
      _RenderVerticalOverhang(extent: extent);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderVerticalOverhang renderObject,
  ) {
    renderObject.extent = extent;
  }
}

final class _RenderVerticalOverhang extends RenderShiftedBox {
  _RenderVerticalOverhang({required this._extent}) : super(null);

  double _extent;
  set extent(double value) {
    if (value == _extent) return;
    _extent = value;
    markNeedsLayout();
  }

  BoxConstraints _childConstraints(BoxConstraints constraints) =>
      constraints.copyWith(
        minHeight: constraints.minHeight + 2 * _extent,
        maxHeight: constraints.maxHeight + 2 * _extent,
      );

  Size _sizeFor(BoxConstraints constraints, Size childSize) =>
      constraints.constrain(
        Size(childSize.width, math.max(0, childSize.height - 2 * _extent)),
      );

  @override
  double computeMinIntrinsicHeight(double width) =>
      math.max(0, child!.getMinIntrinsicHeight(width) - 2 * _extent);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      math.max(0, child!.getMaxIntrinsicHeight(width) - 2 * _extent);

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
    (child.parentData! as BoxParentData).offset = Offset(0, -_extent);
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
