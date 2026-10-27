import 'dart:math' as math;
import 'dart:ui' show SemanticsRole, clampDouble;

import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';
import '../doable_shadows.dart';
import '../doable_type.dart';
import '../text_metrics.dart';

/// Вариант меню строки; значение и готовые подписи задаёт потребитель.
final class SelectRowItem<T extends Object> {
  const SelectRowItem({required this.value, required this.label, this.count});

  /// Значение, которое строка возвращает при выборе варианта; для строки оно
  /// непрозрачно и только сравнивается с выбранным.
  final T value;
  final String label;

  /// Уже отформатированное потребителем число; без него вариант показан
  /// только названием.
  final String? count;
}

/// Строка листа: название параметра слева, выбранное значение справа и меню
/// вариантов над строкой.
///
/// Длинные название и значение переносятся, а строка растёт. Меню выровнено
/// по правому краю всей строки, включая [trailing], стоит на 4 над ней в
/// корневом слое поверх листа и не шире строки; его ширину задаёт самый
/// длинный вариант.
///
/// Выбранное значение хранит потребитель. Выбор другого варианта закрывает
/// меню и вызывает обработчик; выбор текущего, касание вне меню и системное
/// «назад» только закрывают меню. Касание, закрывающее меню, не достаётся
/// элементу под ним, в том числе [trailing]. Пока меню открыто, «назад» не
/// закрывает маршрут, в котором стоит строка.
///
/// Строка владеет фокусом своей кнопки: открытое меню возвращает его туда.
final class SelectRow<T extends Object> extends StatelessWidget {
  /// Доступная строка с меню [items], в котором выбрано [value].
  ///
  /// [controller] открывает и закрывает меню; [onOpen] сообщает об открытии,
  /// например чтобы закрыть меню соседней строки. [trailing] — один элемент
  /// управления справа от строки, вне её кнопки.
  SelectRow({
    required String label,
    required List<SelectRowItem<T>> items,
    required T value,
    required ValueChanged<T> onChanged,
    required MenuController controller,
    VoidCallback? onOpen,
    Widget? trailing,
    super.key,
  }) : assert(
         items.where((item) => item.value == value).length == 1,
         'Выбран ровно один вариант меню.',
       ),
       _parts = _MenuParts(
         label: label,
         items: items,
         value: value,
         onChanged: onChanged,
         controller: controller,
         onOpen: onOpen,
         trailing: trailing,
       );

  /// Строка, значение которой закреплено контекстом: подпись [value] без
  /// меню и пояснение причины [note] под строкой.
  SelectRow.disabled({
    required String label,
    required String value,
    required String note,
    super.key,
  }) : _parts = _FixedParts<T>(label: label, value: value, note: note);

  final _RowParts<T> _parts;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: DoableMetrics.space1),
    child: switch (_parts) {
      final _MenuParts<T> parts => _MenuRow(parts),
      final _FixedParts<T> parts => _FixedRow(parts),
    },
  );
}

sealed class _RowParts<T extends Object> {
  const _RowParts();
}

final class _MenuParts<T extends Object> extends _RowParts<T> {
  const _MenuParts({
    required this.label,
    required this.items,
    required this.value,
    required this.onChanged,
    required this.controller,
    required this.onOpen,
    required this.trailing,
  });

  final String label;
  final List<SelectRowItem<T>> items;
  final T value;
  final ValueChanged<T> onChanged;
  final MenuController controller;
  final VoidCallback? onOpen;
  final Widget? trailing;
}

final class _FixedParts<T extends Object> extends _RowParts<T> {
  const _FixedParts({
    required this.label,
    required this.value,
    required this.note,
  });

  final String label;
  final String value;
  final String note;
}

/// Толщина линии над строкой.
const double _lineWidth = 1;

/// Зазор между строкой и меню над ней.
const double _menuGap = DoableMetrics.space1;

final class _MenuRow<T extends Object> extends StatefulWidget {
  const _MenuRow(this.parts);

  final _MenuParts<T> parts;

  @override
  State<_MenuRow<T>> createState() => _MenuRowState<T>();
}

final class _MenuRowState<T extends Object> extends State<_MenuRow<T>> {
  final _focusNode = FocusNode(debugLabel: 'SelectRow');
  var _isOpen = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _toggle() {
    final controller = widget.parts.controller;
    if (controller.isOpen) {
      controller.close();
    } else {
      controller.open();
    }
  }

  void _handleOpen() {
    setState(() => _isOpen = true);
    widget.parts.onOpen?.call();
  }

  void _handleClose() {
    if (mounted) setState(() => _isOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    final parts = widget.parts;
    final colors = Theme.of(context).extension<DoableColors>()!;
    final selected = parts.items.firstWhere(
      (item) => item.value == parts.value,
    );

    // MenuAnchor закрывает меню только клавишей Escape, а системное «назад»
    // получает маршрут, в котором стоит строка. Пока меню открыто, маршрут
    // не закрывается, а запрос закрывает только меню:
    // https://api.flutter.dev/flutter/widgets/PopScope-class.html
    return PopScope<Object?>(
      canPop: !_isOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) parts.controller.close();
      },
      child: _Line(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final geometry = _MenuGeometry.of(
              context,
              items: parts.items,
              value: parts.value,
              rowWidth: constraints.maxWidth,
            );
            return Row(
              spacing: DoableMetrics.space1,
              children: [
                Expanded(
                  child: MenuAnchor(
                    controller: parts.controller,
                    childFocusNode: _focusNode,
                    useRootOverlay: true,
                    // Касание вне меню только закрывает его:
                    // https://api.flutter.dev/flutter/material/MenuAnchor/consumeOutsideTap.html
                    consumeOutsideTap: true,
                    // Тень плоскости рисуется за её пределами.
                    clipBehavior: Clip.none,
                    onOpen: _handleOpen,
                    onClose: _handleClose,
                    style: const MenuStyle(
                      alignment: Alignment.topLeft,
                      backgroundColor: WidgetStatePropertyAll(
                        Colors.transparent,
                      ),
                      surfaceTintColor: WidgetStatePropertyAll(
                        Colors.transparent,
                      ),
                      shadowColor: WidgetStatePropertyAll(Colors.transparent),
                      elevation: WidgetStatePropertyAll(0),
                      padding: WidgetStatePropertyAll(EdgeInsets.zero),
                      shape: WidgetStatePropertyAll(RoundedRectangleBorder()),
                      minimumSize: WidgetStatePropertyAll(Size.zero),
                      maximumSize: WidgetStatePropertyAll(Size.infinite),
                      // Плотность не сдвигает начало привязки:
                      // https://api.flutter.dev/flutter/material/MenuStyle/visualDensity.html
                      visualDensity: VisualDensity.standard,
                    ),
                    // Начало привязки — верхний левый угол кнопки, который
                    // совпадает с левым краем строки и стоит под её линией.
                    alignmentOffset: Offset(
                      constraints.maxWidth - geometry.width,
                      -_lineWidth - _menuGap - geometry.height,
                    ),
                    menuChildren: [
                      _MenuPanel(
                        label: parts.label,
                        items: parts.items,
                        value: parts.value,
                        geometry: geometry,
                        onSelected: (picked) {
                          if (picked != parts.value) parts.onChanged(picked);
                        },
                      ),
                    ],
                    child: _RowButton(
                      label: parts.label,
                      value: selected.label,
                      valueColor: colors.ink,
                      focusNode: _focusNode,
                      expanded: _isOpen,
                      onPressed: _toggle,
                    ),
                  ),
                ),
                ?parts.trailing,
              ],
            );
          },
        ),
      ),
    );
  }
}

final class _FixedRow<T extends Object> extends StatelessWidget {
  const _FixedRow(this.parts);

  final _FixedParts<T> parts;

  /// Пояснение заходит на нижний отступ строки, как в макете.
  static const double _noteOverlap = 6;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Line(
          child: _RowButton(
            label: parts.label,
            value: parts.value,
            valueColor: colors.muted,
            hint: parts.note,
            focusNode: null,
            expanded: null,
            onPressed: null,
          ),
        ),
        Transform.translate(
          offset: const Offset(0, -_noteOverlap),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              DoableMetrics.space2,
              0,
              DoableMetrics.space2,
              DoableMetrics.space3 - _noteOverlap,
            ),
            child: ExcludeSemantics(
              child: Text(
                parts.note,
                style: DoableType.hint.copyWith(color: colors.muted),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Линия `hairline` над строкой.
final class _Line extends StatelessWidget {
  const _Line({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.hairline)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: _lineWidth),
        child: child,
      ),
    );
  }
}

/// Кнопка строки: название и значение. Без [onPressed] строка недоступна и
/// не показывает селектор.
final class _RowButton extends StatefulWidget {
  const _RowButton({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.focusNode,
    required this.expanded,
    required this.onPressed,
    this.hint,
  });

  final String label;
  final String value;
  final Color valueColor;
  final String? hint;
  final FocusNode? focusNode;

  /// Открыто ли меню; null у строки без меню.
  final bool? expanded;
  final VoidCallback? onPressed;

  @override
  State<_RowButton> createState() => _RowButtonState();
}

final class _RowButtonState extends State<_RowButton> {
  var _focused = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_handleHighlightMode);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_handleHighlightMode);
    super.dispose();
  }

  // Открытие меню касанием переводит фокус на кнопку; кольцо фокуса нужно
  // только при управлении с клавиатуры.
  void _handleHighlightMode(FocusHighlightMode mode) {
    if (_focused) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final radius = BorderRadius.circular(DoableMetrics.radiusSm);
    final enabled = widget.onPressed != null;
    final showsFocus =
        _focused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

    // Название и значение объявляются одной кнопкой:
    // https://api.flutter.dev/flutter/widgets/Semantics/Semantics.html
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      expanded: widget.expanded,
      label: widget.label,
      value: widget.value,
      hint: widget.hint,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: showsFocus
              ? [
                  BoxShadow(color: colors.accent, spreadRadius: 4),
                  BoxShadow(color: colors.bg, spreadRadius: 2),
                ]
              : null,
        ),
        child: InkWell(
          focusNode: widget.focusNode,
          borderRadius: radius,
          onTap: widget.onPressed,
          onFocusChange: (focused) => setState(() => _focused = focused),
          focusColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DoableMetrics.space1,
                vertical: DoableMetrics.space2,
              ),
              child: ExcludeSemantics(
                child: LayoutBuilder(
                  builder: (context, constraints) => Row(
                    spacing: DoableMetrics.space3,
                    children: [
                      // Название занимает не больше половины строки, а
                      // значение — всё оставшееся место.
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: constraints.maxWidth / 2,
                        ),
                        child: Text(
                          widget.label,
                          style: DoableType.body.copyWith(color: colors.muted),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          widget.value,
                          textAlign: TextAlign.end,
                          style: DoableType.section.copyWith(
                            color: widget.valueColor,
                          ),
                        ),
                      ),
                      if (enabled)
                        DoableIcon(
                          DoableIconData.selector,
                          size: 16,
                          color: colors.muted,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Размеры меню до его раскладки: по ним меню встаёт над строкой и у её
/// правого края. Измерение и отрисовка используют одни стили и ширины.
final class _MenuGeometry {
  const _MenuGeometry({required this.width, required this.height});

  final double width;
  final double height;

  static const double minWidth = 228;
  static const double padding = 6;
  static const double radius = 20;
  static const double itemMinHeight = 48;
  static const double itemPaddingVertical = 13;
  static const double itemPaddingHorizontal = DoableMetrics.space3;
  static const double checkSize = 18;
  static const double gap = DoableMetrics.space3;

  /// Стили текста пункта без цвета. Они не наследуют стиль по умолчанию:
  /// у строки он не тот, что внутри кнопки пункта, и иначе измерение
  /// разошлось бы с отрисовкой.
  static TextStyle nameStyle({required bool selected}) => DoableType.action
      .copyWith(inherit: false, fontWeight: selected ? FontWeight.w600 : null);

  static final TextStyle countStyle = DoableType.label.copyWith(
    inherit: false,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  static _MenuGeometry of<T extends Object>(
    BuildContext context, {
    required List<SelectRowItem<T>> items,
    required T value,
    required double rowWidth,
  }) {
    double countWidth(SelectRowItem<T> item) => switch (item.count) {
      final count? =>
        gap + widestTextWidth(context, texts: [count], style: countStyle),
      null => 0,
    };
    const itemChrome = 2 * itemPaddingHorizontal + checkSize + gap;

    var widest = 0.0;
    for (final item in items) {
      final name = widestTextWidth(
        context,
        texts: [item.label],
        style: nameStyle(selected: item.value == value),
      );
      widest = math.max(widest, itemChrome + name + countWidth(item));
    }
    final width = clampDouble(
      2 * padding + widest,
      math.min(minWidth, rowWidth),
      rowWidth,
    );

    var height = 2 * padding;
    for (final item in items) {
      final nameWidth = width - 2 * padding - itemChrome - countWidth(item);
      final nameHeight = tallestTextHeight(
        context,
        texts: [item.label],
        style: nameStyle(selected: item.value == value),
        maxWidth: nameWidth,
      );
      final countHeight = switch (item.count) {
        final count? => tallestTextHeight(
          context,
          texts: [count],
          style: countStyle,
          maxWidth: double.infinity,
        ),
        null => 0.0,
      };
      final content = math.max(checkSize, math.max(nameHeight, countHeight));
      height += math.max(itemMinHeight, content + 2 * itemPaddingVertical);
    }
    return _MenuGeometry(width: width, height: height);
  }
}

/// Плоскость меню со всеми вариантами — единственный элемент [MenuAnchor].
final class _MenuPanel<T extends Object> extends StatelessWidget {
  const _MenuPanel({
    required this.label,
    required this.items,
    required this.value,
    required this.geometry,
    required this.onSelected,
  });

  final String label;
  final List<SelectRowItem<T>> items;
  final T value;
  final _MenuGeometry geometry;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<DoableColors>()!;
    final shadows = theme.extension<DoableShadows>()!;

    return Semantics(
      container: true,
      explicitChildNodes: true,
      role: SemanticsRole.menu,
      label: label,
      child: SizedBox(
        width: geometry.width,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.raised,
            borderRadius: BorderRadius.circular(_MenuGeometry.radius),
            // В макете обводка — тень без смещения снаружи плоскости.
            border: Border.all(
              color: colors.hairline,
              strokeAlign: BorderSide.strokeAlignOutside,
            ),
            boxShadow: shadows.shadowFloat,
          ),
          child: Padding(
            padding: const EdgeInsets.all(_MenuGeometry.padding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final item in items)
                  _item(item, colors, selected: item.value == value),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(
    SelectRowItem<T> item,
    DoableColors colors, {
    required bool selected,
  }) => MenuItemButton(
    // Обработчик вызывается после закрытия меню:
    // https://api.flutter.dev/flutter/material/MenuItemButton/closeOnActivate.html
    onPressed: () => onSelected(item.value),
    style: ButtonStyle(
      backgroundColor: WidgetStatePropertyAll(
        selected ? colors.fill : Colors.transparent,
      ),
      foregroundColor: WidgetStatePropertyAll(colors.ink),
      minimumSize: const WidgetStatePropertyAll(
        Size(0, _MenuGeometry.itemMinHeight),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(
          horizontal: _MenuGeometry.itemPaddingHorizontal,
          vertical: _MenuGeometry.itemPaddingVertical,
        ),
      ),
      shape: const WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(DoableMetrics.radiusMd),
          ),
        ),
      ),
      side: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.focused)
            ? BorderSide(
                color: colors.accent,
                width: 2,
                strokeAlign: BorderSide.strokeAlignOutside,
              )
            : BorderSide.none,
      ),
      visualDensity: VisualDensity.standard,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      alignment: AlignmentDirectional.centerStart,
    ),
    // Выбранность и принадлежность взаимоисключающему набору сливаются с
    // кнопкой пункта.
    child: Semantics(
      role: SemanticsRole.menuItemRadio,
      checked: selected,
      inMutuallyExclusiveGroup: true,
      child: Row(
        children: [
          SizedBox.square(
            dimension: _MenuGeometry.checkSize,
            child: selected
                ? DoableIcon(
                    DoableIconData.check,
                    size: _MenuGeometry.checkSize,
                    color: colors.ink,
                  )
                : null,
          ),
          const SizedBox(width: _MenuGeometry.gap),
          Expanded(
            child: Text(
              item.label,
              style: _MenuGeometry.nameStyle(selected: selected)
                  .copyWith(color: colors.ink),
            ),
          ),
          if (item.count case final count?) ...[
            const SizedBox(width: _MenuGeometry.gap),
            Text(
              count,
              style: _MenuGeometry.countStyle.copyWith(color: colors.muted),
            ),
          ],
        ],
      ),
    ),
  );
}
