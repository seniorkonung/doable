import 'dart:math' as math;
import 'dart:ui' show clampDouble, lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'intention_creation_sheet_mode.dart';

/// Модальная нижняя панель создания намерения над страницей, с которой
/// начато создание.
///
/// Панель отвечает только за модальность и геометрию: модальный фон над
/// страницей под ней, высоту в выбранном владельцем режиме, закреплённые
/// ручку и основное действие и вход и выход вместе со своим маршрутом. В
/// компактном режиме высота следует за содержимым в пределах доступной
/// области и оставляет видимым участок страницы над панелью; в развёрнутом
/// панель занимает всю доступную высоту. Клавиатура и безопасные отступы
/// меняют только доступную область, но не режим.
///
/// Режим принадлежит владельцу. Кнопка размера и свайп по ручке передают
/// ему намерение через [onExpand] и [onCollapse]; свайп вниз из компактного
/// режима, нажатие вне панели, кнопка закрытия и действие экранного диктора
/// передаются через [onCloseRequested]. Сама панель свой маршрут не
/// закрывает. Прокрутка полей режим не меняет и панель не закрывает.
final class IntentionCreationSheet extends StatefulWidget {
  const IntentionCreationSheet({
    required this.mode,
    required this.onExpand,
    required this.onCollapse,
    required this.onCloseRequested,
    required this.closeLabel,
    required this.expandLabel,
    required this.collapseLabel,
    required this.header,
    required this.fields,
    required this.footer,
    super.key,
  });

  /// Режим размера, выбранный владельцем.
  final IntentionCreationSheetMode mode;

  /// Запрос развернуть компактную панель.
  final VoidCallback onExpand;

  /// Запрос свернуть развёрнутую панель.
  final VoidCallback onCollapse;

  /// Запрос закрытия: кнопкой, свайпом вниз из компактного режима, нажатием
  /// вне панели или действием экранного диктора.
  final VoidCallback onCloseRequested;

  /// Подсказка кнопки закрытия и доступное название модального фона.
  final String closeLabel;

  /// Подсказка кнопки размера в компактном режиме.
  final String expandLabel;

  /// Подсказка кнопки размера в развёрнутом режиме.
  final String collapseLabel;

  /// Заголовок формы. Прокручивается вместе с полями, чтобы при тесной
  /// доступной области место оставалось полям.
  final Widget header;

  /// Поля формы. Прокручиваются, когда не помещаются в доступную высоту.
  final Widget fields;

  /// Закреплённая нижняя часть с основным действием формы.
  final Widget footer;

  @override
  State<IntentionCreationSheet> createState() => _IntentionCreationSheetState();
}

final class _IntentionCreationSheetState extends State<IntentionCreationSheet>
    with SingleTickerProviderStateMixin {
  /// Участок страницы под строкой состояния, который компактная панель
  /// оставляет видимым при любой высоте содержимого: контекст, над которым
  /// открыто создание. Это отступ, а не доля экрана.
  static const _visibleContextExtent = 72.0;

  /// Наименьший видимый участок страницы над компактной панелью. До него
  /// участок уступает место закреплённым частям панели, когда клавиатура и
  /// увеличенный текст оставляют слишком мало высоты.
  static const _minVisibleContextExtent = 24.0;

  /// Наибольшая ширина панели на широком экране.
  static const _maxWidth = 640.0;

  static const _resizeDuration = Duration(milliseconds: 250);

  /// Скорость, начиная с которой короткий свайп по ручке считается
  /// намерением сменить размер.
  static const _minFlingVelocity = 700.0;

  /// Путь медленного свайпа по ручке, начиная с которого он считается
  /// намерением сменить размер.
  static const _minDragDistance = 40.0;

  /// Доля перехода от компактного режима (0) к развёрнутому (1).
  late final AnimationController _expansion = AnimationController(
    vsync: this,
    duration: _resizeDuration,
    value: _expansionOf(widget.mode),
  );

  var _dragDistance = 0.0;

  @override
  void didUpdateWidget(IntentionCreationSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.mode != oldWidget.mode) {
      final target = _expansionOf(widget.mode);
      if (MediaQuery.disableAnimationsOf(context)) {
        _expansion.value = target;
      } else {
        _expansion.animateTo(target, curve: Curves.easeOutCubic);
      }
    }
  }

  @override
  void dispose() {
    _expansion.dispose();
    super.dispose();
  }

  static double _expansionOf(IntentionCreationSheetMode mode) => switch (mode) {
    IntentionCreationSheetMode.compact => 0,
    IntentionCreationSheetMode.expanded => 1,
  };

  void _toggleMode() => switch (widget.mode) {
    IntentionCreationSheetMode.compact => widget.onExpand(),
    IntentionCreationSheetMode.expanded => widget.onCollapse(),
  };

  void _startDrag(DragStartDetails details) => _dragDistance = 0;

  void _updateDrag(DragUpdateDetails details) =>
      _dragDistance += details.primaryDelta ?? 0;

  /// Вверх разворачивает компактную панель; вниз сворачивает развёрнутую, а
  /// из компактной запрашивает закрытие.
  void _endDrag(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final direction = velocity.abs() >= _minFlingVelocity
        ? velocity.sign
        : _dragDistance.abs() >= _minDragDistance
        ? _dragDistance.sign
        : 0.0;
    if (direction < 0) {
      switch (widget.mode) {
        case IntentionCreationSheetMode.compact:
          widget.onExpand();
        case IntentionCreationSheetMode.expanded:
          break;
      }
    } else if (direction > 0) {
      switch (widget.mode) {
        case IntentionCreationSheetMode.compact:
          widget.onCloseRequested();
        case IntentionCreationSheetMode.expanded:
          widget.onCollapse();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final colors = Theme.of(context).colorScheme;
    final animation =
        ModalRoute.of(context)?.animation ?? kAlwaysCompleteAnimation;
    final isExpanded = switch (widget.mode) {
      IntentionCreationSheetMode.compact => false,
      IntentionCreationSheetMode.expanded => true,
    };
    return Stack(
      fit: StackFit.expand,
      children: [
        // Фон закрывает страницу под панелью от нажатий, а модальный барьер
        // маршрута — от фокуса и экранного диктора.
        FadeTransition(
          opacity: animation,
          child: ModalBarrier(
            color: colors.scrim.withValues(alpha: 0.32),
            semanticsLabel: widget.closeLabel,
            onDismiss: widget.onCloseRequested,
          ),
        ),
        Padding(
          // Доступная панели область — над клавиатурой и под строкой
          // состояния.
          padding: EdgeInsets.only(
            top: media.padding.top,
            bottom: media.viewInsets.bottom,
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SlideTransition(
              position: animation.drive(
                Tween(
                  begin: const Offset(0, 1),
                  end: Offset.zero,
                ).chain(CurveTween(curve: Curves.easeOutCubic)),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _maxWidth),
                child: Material(
                  key: const ValueKey('intention-creation-sheet'),
                  color: colors.surfaceContainerLow,
                  elevation: 1,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  // Клавиатура и строка состояния уже учтены положением
                  // панели; внутри остаётся только нижний безопасный отступ.
                  child: MediaQuery(
                    data: media
                        .removePadding(removeTop: true)
                        .removeViewInsets(removeBottom: true),
                    child: SafeArea(
                      top: false,
                      child: _SheetLayout(
                        expansion: _expansion,
                        visibleContextExtent: _visibleContextExtent,
                        minVisibleContextExtent: _minVisibleContextExtent,
                        topBar: _TopBar(
                          isExpanded: isExpanded,
                          resizeLabel: isExpanded
                              ? widget.collapseLabel
                              : widget.expandLabel,
                          closeLabel: widget.closeLabel,
                          onResize: _toggleMode,
                          onClose: widget.onCloseRequested,
                          onDragStart: _startDrag,
                          onDragUpdate: _updateDrag,
                          onDragEnd: _endDrag,
                        ),
                        body: SingleChildScrollView(
                          key: const ValueKey(
                            'intention-creation-sheet-fields',
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [widget.header, widget.fields],
                          ),
                        ),
                        // Прокручивается, только если сама не помещается в
                        // тесную доступную область, и не переполняет панель.
                        footer: SingleChildScrollView(
                          primary: false,
                          child: widget.footer,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Закреплённая верхняя полоса: ручка для свайпа и кнопки размера и закрытия,
/// доступные без жеста.
final class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.isExpanded,
    required this.resizeLabel,
    required this.closeLabel,
    required this.onResize,
    required this.onClose,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final bool isExpanded;
  final String resizeLabel;
  final String closeLabel;
  final VoidCallback onResize;
  final VoidCallback onClose;
  final GestureDragStartCallback onDragStart;
  final GestureDragUpdateCallback onDragUpdate;
  final GestureDragEndCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // Нажатия и свайпы полосы не считаются нажатием вне поля ввода: смена
    // размера сохраняет фокус и клавиатуру.
    return TextFieldTapRegion(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Свайп по ручке — дополнительный способ: те же действия экранному
        // диктору дают кнопки, поэтому полоса не выдаёт себя прокручиваемой.
        excludeFromSemantics: true,
        onVerticalDragStart: onDragStart,
        onVerticalDragUpdate: onDragUpdate,
        onVerticalDragEnd: onDragEnd,
        child: SizedBox(
          height: kMinInteractiveDimension,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                key: const ValueKey('intention-creation-sheet-handle'),
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: const ValueKey('intention-creation-sheet-resize'),
                      tooltip: resizeLabel,
                      onPressed: onResize,
                      icon: Icon(
                        isExpanded
                            ? Icons.close_fullscreen
                            : Icons.open_in_full,
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('intention-editor-close'),
                      tooltip: closeLabel,
                      onPressed: onClose,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _SheetSlot { topBar, body, footer }

/// Раскладка панели: закреплённые верхняя полоса и нижняя часть и
/// прокручиваемые между ними поля.
///
/// Нижняя часть с основным действием получает своё место первой после
/// полосы, поля — оставшееся. В компактном режиме ([expansion] = 0) высота
/// полей следует за содержимым в пределах доступной высоты за вычетом
/// [visibleContextExtent]; в развёрнутом (1) панель занимает всю доступную
/// высоту. Промежуточные значения плавно переводят высоту между ними.
///
/// Если закреплённые части не помещаются в компактное ограничение, видимый
/// участок страницы уменьшается ради них, но не меньше чем до
/// [minVisibleContextExtent]: основное действие и управление размером
/// остаются доступными, а поля — прокручиваемыми.
final class _SheetLayout
    extends SlottedMultiChildRenderObjectWidget<_SheetSlot, RenderBox> {
  const _SheetLayout({
    required this.expansion,
    required this.visibleContextExtent,
    required this.minVisibleContextExtent,
    required this.topBar,
    required this.body,
    required this.footer,
  });

  final Animation<double> expansion;
  final double visibleContextExtent;
  final double minVisibleContextExtent;
  final Widget topBar;
  final Widget body;
  final Widget footer;

  @override
  Iterable<_SheetSlot> get slots => _SheetSlot.values;

  @override
  Widget childForSlot(_SheetSlot slot) => switch (slot) {
    _SheetSlot.topBar => topBar,
    _SheetSlot.body => body,
    _SheetSlot.footer => footer,
  };

  @override
  _RenderSheetLayout createRenderObject(BuildContext context) =>
      _RenderSheetLayout(
        expansion: expansion,
        visibleContextExtent: visibleContextExtent,
        minVisibleContextExtent: minVisibleContextExtent,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSheetLayout renderObject,
  ) {
    renderObject
      ..expansion = expansion
      ..visibleContextExtent = visibleContextExtent
      ..minVisibleContextExtent = minVisibleContextExtent;
  }
}

final class _RenderSheetLayout extends RenderBox
    with SlottedContainerRenderObjectMixin<_SheetSlot, RenderBox> {
  _RenderSheetLayout({
    required this._expansion,
    required this._visibleContextExtent,
    required this._minVisibleContextExtent,
  });

  Animation<double> _expansion;

  set expansion(Animation<double> value) {
    if (identical(value, _expansion)) {
      return;
    }
    if (attached) {
      _expansion.removeListener(markNeedsLayout);
      value.addListener(markNeedsLayout);
    }
    _expansion = value;
    markNeedsLayout();
  }

  double _visibleContextExtent;

  set visibleContextExtent(double value) {
    if (value == _visibleContextExtent) {
      return;
    }
    _visibleContextExtent = value;
    markNeedsLayout();
  }

  double _minVisibleContextExtent;

  set minVisibleContextExtent(double value) {
    if (value == _minVisibleContextExtent) {
      return;
    }
    _minVisibleContextExtent = value;
    markNeedsLayout();
  }

  RenderBox get _topBar => childForSlot(_SheetSlot.topBar)!;

  RenderBox get _body => childForSlot(_SheetSlot.body)!;

  RenderBox get _footer => childForSlot(_SheetSlot.footer)!;

  /// Порядок обхода совпадает с расположением сверху вниз.
  @override
  Iterable<RenderBox> get children => [
    for (final slot in _SheetSlot.values) ?childForSlot(slot),
  ];

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _expansion.addListener(markNeedsLayout);
  }

  @override
  void detach() {
    _expansion.removeListener(markNeedsLayout);
    super.detach();
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! BoxParentData) {
      child.parentData = BoxParentData();
    }
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    assert(
      debugCannotComputeDryLayout(
        reason: 'Компактная высота панели зависит от раскладки полей.',
      ),
    );
    return Size.zero;
  }

  @override
  void performLayout() {
    assert(
      constraints.hasBoundedHeight,
      'Панели нужна ограниченная доступная высота.',
    );
    final expansion = clampDouble(_expansion.value, 0, 1);
    final width = constraints.maxWidth;
    final available = constraints.maxHeight;
    var topHeight = _layoutChild(_topBar, width, maxHeight: available);
    var footerHeight = _layoutChild(
      _footer,
      width,
      maxHeight: math.max(0, available - topHeight),
    );
    final compactLimit = math.max(
      0.0,
      math.max(
        available - _visibleContextExtent,
        math.min(
          topHeight + footerHeight,
          available - _minVisibleContextExtent,
        ),
      ),
    );
    final limit = lerpDouble(compactLimit, available, expansion)!;
    if (topHeight + footerHeight > limit) {
      // Тесная область: нижняя часть прокручивается в оставшемся месте.
      topHeight = _layoutChild(_topBar, width, maxHeight: limit);
      footerHeight = _layoutChild(
        _footer,
        width,
        maxHeight: math.max(0, limit - topHeight),
      );
    }
    final fixedHeight = topHeight + footerHeight;
    final expandedBodyHeight = math.max(0.0, available - fixedHeight);
    final double bodyHeight;
    if (expansion == 1) {
      bodyHeight = _layoutChild(
        _body,
        width,
        minHeight: expandedBodyHeight,
        maxHeight: expandedBodyHeight,
      );
    } else {
      final compactBodyHeight = _layoutChild(
        _body,
        width,
        maxHeight: math.max(0, compactLimit - fixedHeight),
      );
      if (expansion == 0) {
        bodyHeight = compactBodyHeight;
      } else {
        final height = lerpDouble(
          compactBodyHeight,
          expandedBodyHeight,
          expansion,
        )!;
        bodyHeight = _layoutChild(
          _body,
          width,
          minHeight: height,
          maxHeight: height,
        );
      }
    }

    _position(_body, topHeight);
    _position(_footer, topHeight + bodyHeight);
    size = constraints.constrain(
      Size(width, topHeight + bodyHeight + footerHeight),
    );
  }

  double _layoutChild(
    RenderBox child,
    double width, {
    required double maxHeight,
    double minHeight = 0,
  }) {
    child.layout(
      BoxConstraints(
        minWidth: width,
        maxWidth: width,
        minHeight: minHeight,
        maxHeight: maxHeight,
      ),
      parentUsesSize: true,
    );
    return child.size.height;
  }

  void _position(RenderBox child, double top) =>
      (child.parentData! as BoxParentData).offset = Offset(0, top);

  @override
  void paint(PaintingContext context, Offset offset) {
    for (final child in children) {
      context.paintChild(
        child,
        offset + (child.parentData! as BoxParentData).offset,
      );
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final child in children.toList().reversed) {
      final childOffset = (child.parentData! as BoxParentData).offset;
      final isHit = result.addWithPaintOffset(
        offset: childOffset,
        position: position,
        hitTest: (result, transformed) =>
            child.hitTest(result, position: transformed),
      );
      if (isHit) {
        return true;
      }
    }
    return false;
  }
}
