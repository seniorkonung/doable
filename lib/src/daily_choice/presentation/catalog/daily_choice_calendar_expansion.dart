import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../design_system/doable_colors.dart';

/// Раскладка двух представлений календаря без сжатия их содержимого.
///
/// Оба ребёнка получают одну ширину и естественную высоту в текущем проходе;
/// обрезка и видимость следуют той же степени раскрытия, что и высота.
/// Раскрытое представление надвигается снизу на неделю и закрывает её
/// непрозрачным фоном, поэтому надписи двух представлений не накладываются.
final class DailyChoiceCalendarExpansion extends StatelessWidget {
  const DailyChoiceCalendarExpansion({
    super.key,
    required this.progress,
    required this.week,
    required this.expanded,
    required this.onExtentChanged,
  });

  final double progress;
  final Widget week;
  final Widget expanded;

  /// Измеренная разность высот. Вызывается при раскладке; обработчик сохраняет
  /// значение для следующего события жеста, не запрашивая перестроения.
  final ValueChanged<double> onExtentChanged;

  @override
  Widget build(BuildContext context) => ClipRect(
    child: _ExpansionLayout(
      progress: progress,
      onExtentChanged: onExtentChanged,
      children: [
        _MeasuredOffstage(
          offstage: progress == 1,
          child: ExcludeFocus(
            excluding: progress != 0,
            child: Opacity(opacity: 1 - progress, child: week),
          ),
        ),
        _MeasuredOffstage(
          offstage: progress == 0,
          child: ExcludeFocus(
            excluding: progress != 1,
            // Фон вне прозрачности: проявляются только надписи, а неделя под
            // ними закрыта при любой степени раскрытия.
            // https://api.flutter.dev/flutter/widgets/Opacity-class.html
            child: ColoredBox(
              color: Theme.of(context).extension<DoableColors>()!.bg,
              child: Opacity(opacity: progress, child: expanded),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Скрытое представление измеряется заранее, чтобы первое движение жеста
/// использовало естественные высоты даже до следующего кадра.
/// https://api.flutter.dev/flutter/widgets/Offstage-class.html
final class _MeasuredOffstage extends Offstage {
  const _MeasuredOffstage({required super.offstage, required super.child});

  @override
  RenderOffstage createRenderObject(BuildContext context) =>
      _RenderMeasuredOffstage(offstage: offstage);
}

final class _RenderMeasuredOffstage extends RenderOffstage {
  _RenderMeasuredOffstage({required super.offstage});

  @override
  bool get sizedByParent => false;

  @override
  void performLayout() {
    child!.layout(constraints, parentUsesSize: true);
    size = child!.size;
  }
}

final class _ExpansionLayout extends MultiChildRenderObjectWidget {
  const _ExpansionLayout({
    required this.progress,
    required this.onExtentChanged,
    required super.children,
  });

  final double progress;
  final ValueChanged<double> onExtentChanged;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderExpansionLayout(progress, onExtentChanged);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderExpansionLayout renderObject,
  ) {
    renderObject.progress = progress;
    renderObject.onExtentChanged = onExtentChanged;
  }
}

final class _ExpansionParentData extends ContainerBoxParentData<RenderBox> {}

final class _RenderExpansionLayout extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ExpansionParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ExpansionParentData> {
  _RenderExpansionLayout(this._progress, this.onExtentChanged);

  double _progress;
  ValueChanged<double> onExtentChanged;

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
    onExtentChanged(expanded.size.height - week.size.height);
    // Край раскрытого представления начинает путь от нижнего края недели.
    (expanded.parentData! as _ExpansionParentData).offset = Offset(
      0,
      (1 - _progress) * week.size.height,
    );
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
