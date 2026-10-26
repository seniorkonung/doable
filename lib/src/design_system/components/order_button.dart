import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';

/// Направление значка; смысл порядка задаёт потребитель.
enum OrderDirection { ascending, descending }

/// Круглая кнопка направления с готовым доступным названием.
///
/// Потребитель задаёт текущее [direction], название [label] с текущим порядком
/// и результатом нажатия и команду [onPressed]. Кнопка владеет своим фокусом;
/// правила сортировки и локализация остаются у потребителя.
final class OrderButton extends StatefulWidget {
  const OrderButton({
    required this.direction,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final OrderDirection direction;
  final String label;
  final VoidCallback onPressed;

  @override
  State<OrderButton> createState() => _OrderButtonState();
}

final class _OrderButtonState extends State<OrderButton> {
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocus);
    FocusManager.instance.addHighlightModeListener(_handleHighlightMode);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_handleHighlightMode);
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocus() => setState(() {});

  void _handleHighlightMode(FocusHighlightMode mode) {
    if (_focusNode.hasFocus) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final showsFocus =
        _focusNode.hasFocus &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: showsFocus
            ? [
                BoxShadow(color: colors.accent, spreadRadius: 4),
                BoxShadow(color: colors.bg, spreadRadius: 2),
              ]
            : null,
      ),
      // Название, роль и команда нажатия принадлежат одной кнопке:
      // https://api.flutter.dev/flutter/widgets/MergeSemantics-class.html
      child: MergeSemantics(
        child: Semantics(
          label: widget.label,
          // IconButton сохраняет команды клавиатуры и действие диктора:
          // https://api.flutter.dev/flutter/material/IconButton-class.html
          child: IconButton.filledTonal(
            focusNode: _focusNode,
            onPressed: widget.onPressed,
            style: IconButton.styleFrom(
              fixedSize: const Size.square(DoableMetrics.tapMin),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.standard,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: const CircleBorder(),
              backgroundColor: colors.fill,
              foregroundColor: colors.ink,
              focusColor: Colors.transparent,
            ),
            icon: DoableIcon(
              switch (widget.direction) {
                OrderDirection.ascending => DoableIconData.sortAsc,
                OrderDirection.descending => DoableIconData.sortDesc,
              },
              size: 20,
              color: colors.ink,
            ),
          ),
        ),
      ),
    );
  }
}
