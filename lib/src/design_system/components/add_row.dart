import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';
import '../doable_type.dart';

/// Строка о том, что лежит под ней: заголовок или подсказка и «Добавить»
/// у правого края.
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
  AddRow({
    required String title,
    required String addText,
    required String addLabel,
    required VoidCallback? onAdd,
    Key? addKey,
    super.key,
  }) : _lead = _Title(title),
       _add = _Add(text: addText, label: addLabel, onAdd: onAdd, key: addKey);

  /// Строка с подсказкой об открытом списке и «Добавить».
  AddRow.hint({
    required String hint,
    required String addText,
    required String addLabel,
    required VoidCallback onAdd,
    Key? addKey,
    super.key,
  }) : _lead = _Hint(hint),
       _add = _Add(text: addText, label: addLabel, onAdd: onAdd, key: addKey);

  /// Строка с одной подсказкой: добавить в список нечего.
  AddRow.hintOnly({required String hint, super.key})
    : _lead = _Hint(hint),
      _add = null;

  /// Строка с одним «Добавить» у правого края.
  AddRow.addOnly({
    required String addText,
    required String addLabel,
    required VoidCallback onAdd,
    Key? addKey,
    super.key,
  }) : _lead = null,
       _add = _Add(text: addText, label: addLabel, onAdd: onAdd, key: addKey);

  final _Lead? _lead;
  final _Add? _add;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final lead = _lead;
    final add = _add;

    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: DoableMetrics.tapMin),
      child: Row(
        spacing: DoableMetrics.space3,
        children: [
          if (lead == null)
            const Spacer()
          else
            Expanded(
              child: Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: DoableMetrics.space1,
                ),
                child: switch (lead) {
                  _Title(:final text) => Text(
                    text,
                    style: DoableType.row.copyWith(color: colors.ink),
                  ),
                  _Hint(:final text) => Text(
                    text,
                    style: DoableType.hint.copyWith(color: colors.muted),
                  ),
                },
              ),
            ),
          if (add != null)
            TextButton(
              key: add.key,
              onPressed: add.onAdd,
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
                    color: add.onAdd == null ? colors.grip : colors.accent,
                  ),
                  Text(add.text, semanticsLabel: add.label),
                ],
              ),
            ),
        ],
      ),
    );

    return add == null ? row : _EndOverhang(extent: _addOverhang, child: row);
  }
}

sealed class _Lead {
  const _Lead(this.text);

  final String text;
}

final class _Title extends _Lead {
  const _Title(super.text);
}

final class _Hint extends _Lead {
  const _Hint(super.text);
}

final class _Add {
  const _Add({
    required this.text,
    required this.label,
    required this.onAdd,
    required this.key,
  });

  final String text;
  final String label;
  final VoidCallback? onAdd;
  final Key? key;
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
