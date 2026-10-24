import 'dart:math' as math;

import 'package:flutter/material.dart' hide Badge;
import 'package:flutter/rendering.dart';

import '../doable_colors.dart';
import '../doable_type.dart';
import 'badge.dart';
import 'tag_chip.dart';

/// Последняя линия строки списка: метки, затем теги, сколько поместится,
/// и число остальных «+N». Линия не переносится и не создаёт узлов экранного
/// диктора: метки и теги называет доступное название строки.
final class TagLine extends MultiChildRenderObjectWidget {
  /// [tags] — все теги в порядке показа: под фильтром обязательные идут
  /// первыми, чтобы уступать место последними.
  TagLine({
    required List<TagChip> tags,
    List<Badge> marks = const [],
    super.key,
  }) : _markCount = marks.length,
       super(children: [...marks, ...tags]);

  final int _markCount;

  @override
  RenderTagLine createRenderObject(BuildContext context) => RenderTagLine(
    markCount: _markCount,
    countStyle: _countStyle(context),
    textScaler: MediaQuery.textScalerOf(context),
  );

  @override
  void updateRenderObject(BuildContext context, RenderTagLine renderObject) {
    renderObject
      ..markCount = _markCount
      ..countStyle = _countStyle(context)
      ..textScaler = MediaQuery.textScalerOf(context);
  }

  static TextStyle _countStyle(BuildContext context) =>
      DoableType.caption.copyWith(
        color: Theme.of(context).extension<DoableColors>()!.muted,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}

final class _TagLineParentData extends ContainerBoxParentData<RenderBox> {}

/// Раскладка [TagLine] за один проход: теги измеряются один раз, а место под
/// число считается по его настоящей ширине при текущем масштабе текста.
final class RenderTagLine extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _TagLineParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _TagLineParentData> {
  RenderTagLine({
    required this._markCount,
    required this._countStyle,
    required this._textScaler,
  });

  static const _gap = 6.0;

  int _markCount;

  set markCount(int value) {
    if (_markCount == value) return;
    _markCount = value;
    markNeedsLayout();
  }

  TextStyle get countStyle => _countStyle;
  TextStyle _countStyle;

  set countStyle(TextStyle value) {
    if (_countStyle == value) return;
    _countStyle = value;
    markNeedsLayout();
  }

  TextScaler _textScaler;

  set textScaler(TextScaler value) {
    if (_textScaler == value) return;
    _textScaler = value;
    markNeedsLayout();
  }

  /// Число тегов, которые не поместились и показаны как «+N»; 0 — видны все.
  int get hiddenTagCount => _hiddenTagCount;
  int _hiddenTagCount = 0;

  // Линия раскладывается слева направо: приложение говорит только на языках
  // с таким письмом.
  final _count = TextPainter(textDirection: TextDirection.ltr);
  final _tagsClip = LayerHandle<ClipRectLayer>();
  Rect _tagsArea = Rect.zero;
  bool _tagsOverflow = false;
  Offset _countOffset = Offset.zero;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _TagLineParentData) {
      child.parentData = _TagLineParentData();
    }
  }

  // Строка числа ниже чипа: оба набраны `caption`, а у чипа ещё поля сверху
  // и снизу.
  // Поэтому высоту линии задают метки и теги.
  @override
  double computeMinIntrinsicHeight(double width) => _intrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) => _intrinsicHeight(width);

  double _intrinsicHeight(double width) {
    var height = 0.0;
    for (final child in getChildrenAsList()) {
      height = math.max(height, child.getMaxIntrinsicHeight(width));
    }
    return height;
  }

  @override
  void performLayout() {
    final children = getChildrenAsList();
    final marks = children.take(_markCount);
    final tags = children.skip(_markCount).toList();
    final childConstraints = BoxConstraints(maxWidth: constraints.maxWidth);
    var height = 0.0;
    for (final child in children) {
      child.layout(childConstraints, parentUsesSize: true);
      height = math.max(height, child.size.height);
    }

    var x = 0.0;
    for (final mark in marks) {
      _place(mark, x, height);
      x += mark.size.width + _gap;
    }
    if (tags.isEmpty) {
      _hiddenTagCount = 0;
      _tagsArea = Rect.zero;
      _tagsOverflow = false;
      size = constraints.constrain(Size(math.max(0, x - _gap), height));
      return;
    }

    final tagsStart = x;
    final room = constraints.maxWidth - tagsStart;
    var used = 0.0;
    var shown = 0;
    for (final (index, tag) in tags.indexed) {
      final end = used + (index == 0 ? 0 : _gap) + tag.size.width;
      final rest = tags.length - index - 1;
      final countRoom = rest == 0 ? 0 : _gap + _layoutCount(rest);
      if (end + countRoom > room) break;
      _place(tag, tagsStart + end - tag.size.width, height);
      used = end;
      shown = index + 1;
    }
    // Первый тег виден всегда, даже если не помещается.
    if (shown == 0) {
      _place(tags.first, tagsStart, height);
      used = tags.first.size.width;
      shown = 1;
    }

    _hiddenTagCount = tags.length - shown;
    final tagsRoom = _hiddenTagCount == 0
        ? room
        : room - _gap - _layoutCount(_hiddenTagCount);
    _tagsOverflow = used > tagsRoom;
    final tagsWidth = math.max(0.0, math.min(used, tagsRoom));
    _tagsArea = Rect.fromLTWH(tagsStart, 0, tagsWidth, height);
    if (_hiddenTagCount == 0) {
      size = constraints.constrain(Size(_tagsArea.right, height));
      return;
    }
    _countOffset = Offset(_tagsArea.right + _gap, (height - _count.height) / 2);
    size = constraints.constrain(Size(_countOffset.dx + _count.width, height));
  }

  void _place(RenderBox child, double x, double lineHeight) {
    (child.parentData! as _TagLineParentData).offset = Offset(
      x,
      (lineHeight - child.size.height) / 2,
    );
  }

  double _layoutCount(int hidden) {
    _count
      ..text = TextSpan(text: '+$hidden', style: _countStyle)
      ..textScaler = _textScaler
      ..layout();
    return _count.width;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    var child = firstChild;
    for (var index = 0; index < _markCount && child != null; index++) {
      _paintChild(context, offset, child);
      child = childAfter(child);
    }
    final firstTag = child;

    void paintTags(PaintingContext context, Offset offset) {
      var tag = firstTag;
      final shown = childCount - _markCount - _hiddenTagCount;
      for (var index = 0; index < shown && tag != null; index++) {
        _paintChild(context, offset, tag);
        tag = childAfter(tag);
      }
    }

    if (_tagsOverflow) {
      _tagsClip.layer = context.pushClipRect(
        needsCompositing,
        offset,
        _tagsArea,
        paintTags,
        oldLayer: _tagsClip.layer,
      );
    } else {
      _tagsClip.layer = null;
      paintTags(context, offset);
    }
    if (_hiddenTagCount > 0) {
      _count.paint(context.canvas, offset + _countOffset);
    }
  }

  void _paintChild(PaintingContext context, Offset offset, RenderBox child) {
    context.paintChild(
      child,
      offset + (child.parentData! as _TagLineParentData).offset,
    );
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {}

  @override
  void dispose() {
    _tagsClip.layer = null;
    _count.dispose();
    super.dispose();
  }
}
