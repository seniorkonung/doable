import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';
import '../doable_type.dart';

/// Строка с заголовком того, что лежит под ней, и «Добавить» у правого края.
///
/// Область нажатия «Добавить» выходит за край строки и принимает касания
/// там, пока родитель строки шире её на эту полосу, например поле содержимого
/// с отступами.
final class AddRow extends StatelessWidget {
  /// Насколько область нажатия «Добавить» выходит за край содержимого.
  static const double _addOverhang = 6;
  static const double _addRadius = 18;
  static const double _plusSize = 18;

  /// Строка с заголовком, как шапка блока тегов. Без обработчика «Добавить»
  /// выключено и остаётся на своём месте.
  const AddRow({
    required this.title,
    required this.addText,
    required this.addLabel,
    required this.onAdd,
    this.addKey,
    super.key,
  });

  final String title;

  /// Видимая подпись «Добавить».
  final String addText;

  /// Доступное название «Добавить»: что именно оно добавляет.
  final String addLabel;

  /// Без обработчика «Добавить» окрашено `grip`, как выключенная текстовая
  /// кнопка, и объявляется недоступным.
  final VoidCallback? onAdd;

  /// Ключ области нажатия «Добавить», по нему её находят сценарии экрана.
  final Key? addKey;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;

    return _EndOverhang(
      extent: _addOverhang,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: DoableMetrics.tapMin),
        child: Row(
          spacing: DoableMetrics.space3,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: DoableMetrics.space1,
                ),
                child: Text(
                  title,
                  style: DoableType.row.copyWith(color: colors.ink),
                ),
              ),
            ),
            TextButton(
              key: addKey,
              onPressed: onAdd,
              style: TextButton.styleFrom(
                foregroundColor: colors.accent,
                disabledForegroundColor: colors.grip,
                minimumSize: const Size(0, DoableMetrics.tapMin),
                // Слово кончается в space-1 от края содержимого.
                padding: const EdgeInsetsDirectional.only(
                  start: _addOverhang,
                  end: DoableMetrics.space1 + _addOverhang,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_addRadius),
                ),
                textStyle: DoableType.section,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: DoableMetrics.space1,
                children: [
                  DoableIcon(
                    DoableIconData.plusSmall,
                    size: _plusSize,
                    color: onAdd == null ? colors.grip : colors.accent,
                  ),
                  Text(addText, semanticsLabel: addLabel),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Отдаёт ребёнку ширину на [extent] больше своей: лишняя полоса лежит
/// за концом строки, рисуется там и принимает касания.
final class _EndOverhang extends SingleChildRenderObjectWidget {
  const _EndOverhang({required this.extent, required Widget super.child});

  final double extent;

  @override
  _RenderEndOverhang createRenderObject(BuildContext context) =>
      _RenderEndOverhang(
        extent: extent,
        textDirection: Directionality.of(context),
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderEndOverhang renderObject,
  ) {
    renderObject
      ..extent = extent
      ..textDirection = Directionality.of(context);
  }
}

final class _RenderEndOverhang extends RenderShiftedBox {
  _RenderEndOverhang({required this._extent, required this._textDirection})
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
