import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';
import '../doable_shadows.dart';
import '../doable_type.dart';

/// Половина переключателя с подготовленным доступным названием.
final class SegmentItem<T extends Object> {
  const SegmentItem({
    required this.id,
    required this.label,
    required this.semanticLabel,
    this.icon,
    this.disabled = false,
  });

  final T id;
  final String label;
  final String semanticLabel;
  final DoableIconData? icon;
  final bool disabled;
}

/// Две равные половины взаимоисключающего выбора; значение хранит потребитель.
final class SegmentedControl<T extends Object> extends StatelessWidget {
  const SegmentedControl({
    required this.first,
    required this.second,
    required this.value,
    required this.onChange,
    required this.label,
    super.key,
  });

  final SegmentItem<T> first;
  final SegmentItem<T> second;
  final T value;
  final ValueChanged<T>? onChange;
  final String label;

  @override
  Widget build(BuildContext context) {
    assert(first.id != second.id);
    assert(value == first.id || value == second.id);
    final colors = Theme.of(context).extension<DoableColors>()!;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.fill,
          borderRadius: BorderRadius.circular(DoableMetrics.radiusMd),
        ),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Row(
            spacing: 2,
            children: [
              for (final item in [first, second])
                Expanded(
                  child: _Segment(
                    item: item,
                    selected: item.id == value,
                    onChange: onChange,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _Segment<T extends Object> extends StatefulWidget {
  const _Segment({
    required this.item,
    required this.selected,
    required this.onChange,
  });

  final SegmentItem<T> item;
  final bool selected;
  final ValueChanged<T>? onChange;

  @override
  State<_Segment<T>> createState() => _SegmentState<T>();
}

final class _SegmentState<T extends Object> extends State<_Segment<T>> {
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

  void _handleHighlightMode(FocusHighlightMode mode) {
    if (_focused) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final shadows = Theme.of(context).extension<DoableShadows>()!;
    final enabled = widget.onChange != null && !widget.item.disabled;
    final selected = widget.selected;
    final color = enabled
        ? (selected ? colors.ink : colors.muted)
        : (selected && !widget.item.disabled ? colors.muted : colors.grip);
    final focused =
        _focused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    const radius = BorderRadius.all(Radius.circular(11));
    return Semantics(
      container: true,
      label: widget.item.semanticLabel,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      enabled: enabled,
      onTap: enabled
          ? () {
              if (!selected) widget.onChange!(widget.item.id);
            }
          : null,
      child: ExcludeSemantics(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          constraints: const BoxConstraints(minHeight: 38),
          decoration: BoxDecoration(
            color: selected ? colors.raised : null,
            borderRadius: radius,
            boxShadow: focused
                ? [
                    BoxShadow(color: colors.accent, spreadRadius: 4),
                    BoxShadow(color: colors.bg, spreadRadius: 2),
                  ]
                : (selected ? shadows.sm : null),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: radius,
              focusColor: Colors.transparent,
              onFocusChange: (focused) => setState(() => _focused = focused),
              onTap: enabled
                  ? () {
                      if (!selected) widget.onChange!(widget.item.id);
                    }
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.item.icon case final icon?) ...[
                      DoableIcon(icon, size: 16, color: color),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        widget.item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: (selected ? DoableType.section : DoableType.row)
                            .copyWith(color: color, letterSpacing: -0.15),
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
