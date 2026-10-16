import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Раскладка двух представлений календаря без сжатия их содержимого.
///
/// Оба ребёнка получают одну ширину и естественную высоту в текущем проходе;
/// обрезка и видимость следуют той же степени раскрытия, что и высота.
final class DailyChoiceCalendarExpansion extends StatelessWidget {
  const DailyChoiceCalendarExpansion({
    super.key,
    required this.progress,
    required this.week,
    required this.expanded,
  });

  final double progress;
  final Widget week;
  final Widget expanded;

  @override
  Widget build(BuildContext context) => ClipRect(
    child: _ExpansionLayout(
      progress: progress,
      children: [
        Opacity(opacity: 1 - progress, child: week),
        Opacity(opacity: progress, child: expanded),
      ],
    ),
  );
}

final class _ExpansionLayout extends MultiChildRenderObjectWidget {
  const _ExpansionLayout({required this.progress, required super.children});

  final double progress;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderExpansionLayout(progress);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderExpansionLayout renderObject,
  ) => renderObject.progress = progress;
}

final class _ExpansionParentData extends ContainerBoxParentData<RenderBox> {}

final class _RenderExpansionLayout extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ExpansionParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ExpansionParentData> {
  _RenderExpansionLayout(this._progress);

  double _progress;

  set progress(double value) {
    if (_progress == value) return;
    _progress = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ExpansionParentData) {
      child.parentData = _ExpansionParentData();
    }
  }

  @override
  void performLayout() {
    // Измерение при фиксированной ширине, без отложенного setState:
    // https://api.flutter.dev/flutter/rendering/RenderBox-class.html
    final childConstraints = BoxConstraints.tightFor(
      width: constraints.maxWidth,
    );
    final week = firstChild!;
    final expanded = lastChild!;
    week.layout(childConstraints, parentUsesSize: true);
    expanded.layout(childConstraints, parentUsesSize: true);
    size = constraints.constrain(
      Size(
        constraints.maxWidth,
        week.size.height +
            _progress * (expanded.size.height - week.size.height),
      ),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
