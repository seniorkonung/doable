import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';
import '../doable_type.dart';

/// Вариант группы; значение и готовую подпись задаёт потребитель.
final class OptionGroupItem<T extends Object> {
  const OptionGroupItem({
    required this.value,
    required this.label,
    this.count,
    this.icon,
  });

  final T value;
  final String label;

  /// Уже отформатированное потребителем число.
  final String? count;
  final DoableIconData? icon;
}

/// Группа пилюль для листа. Выбранное значение хранит потребитель.
final class OptionGroup<T extends Object> extends StatelessWidget {
  const OptionGroup({
    required this.caption,
    required this.items,
    required this.value,
    required ValueChanged<T> this.onChanged,
    super.key,
  }) : note = null;

  /// Значение закреплено контекстом; причина недоступности обязательна.
  const OptionGroup.disabled({
    required this.caption,
    required this.items,
    required this.value,
    required String this.note,
    super.key,
  }) : assert(note != ''),
       onChanged = null;

  final String caption;
  final List<OptionGroupItem<T>> items;
  final T value;
  final ValueChanged<T>? onChanged;
  final String? note;

  @override
  Widget build(BuildContext context) {
    assert(items.where((item) => item.value == value).length == 1);
    final colors = Theme.of(context).extension<DoableColors>()!;

    // Группа и состояния вариантов объявляются отдельно от видимой подписи:
    // https://api.flutter.dev/flutter/widgets/Semantics/Semantics.html
    return Semantics(
      container: true,
      explicitChildNodes: true,
      role: SemanticsRole.radioGroup,
      label: caption,
      enabled: onChanged != null,
      hint: note,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DoableMetrics.space2,
        children: [
          ExcludeSemantics(
            child: Text(
              caption,
              style: DoableType.caption.copyWith(color: colors.muted),
            ),
          ),
          // При крупном тексте все пилюли растут до высоты самой высокой:
          // https://api.flutter.dev/flutter/widgets/IntrinsicHeight-class.html
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: DoableMetrics.space2,
              children: [
                for (final item in items)
                  Expanded(
                    child: _OptionPill(
                      item: item,
                      selected: item.value == value,
                      onPressed: onChanged == null
                          ? null
                          : () => onChanged!(item.value),
                    ),
                  ),
              ],
            ),
          ),
          if (note case final note?)
            ExcludeSemantics(
              child: Text(
                note,
                style: DoableType.caption.copyWith(color: colors.muted),
              ),
            ),
        ],
      ),
    );
  }
}

final class _OptionPill<T extends Object> extends StatefulWidget {
  const _OptionPill({
    required this.item,
    required this.selected,
    required this.onPressed,
  });

  final OptionGroupItem<T> item;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  State<_OptionPill<T>> createState() => _OptionPillState<T>();
}

final class _OptionPillState<T extends Object> extends State<_OptionPill<T>> {
  var _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final radius = BorderRadius.circular(DoableMetrics.radiusFull);
    final enabled = widget.onPressed != null;
    final foreground = switch ((enabled, widget.selected)) {
      (true, _) => colors.ink,
      (false, true) => colors.muted,
      (false, false) => colors.grip,
    };
    final style = widget.selected
        ? DoableType.section
        : DoableType.row.copyWith(letterSpacing: -0.15);

    return Semantics(
      container: true,
      checked: widget.selected,
      inMutuallyExclusiveGroup: true,
      enabled: enabled,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: _focused && enabled
              ? [
                  BoxShadow(color: colors.accent, spreadRadius: 4),
                  BoxShadow(color: colors.bg, spreadRadius: 2),
                ]
              : null,
        ),
        child: Material(
          color: widget.selected ? colors.fill : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: widget.selected
                ? BorderSide.none
                : BorderSide(color: colors.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: radius,
            onTap: widget.onPressed,
            onFocusChange: (focused) => setState(() => _focused = focused),
            focusColor: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: DoableMetrics.tapMin,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: DoableMetrics.space2,
                  vertical: 12,
                ),
                child: Center(
                  widthFactor: 1,
                  heightFactor: 1,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.item.icon case final icon?) ...[
                        DoableIcon(icon, size: 16, color: colors.muted),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(
                          widget.item.label,
                          textAlign: TextAlign.center,
                          style: style.copyWith(color: foreground),
                        ),
                      ),
                      if (widget.item.count case final count? when enabled) ...[
                        const SizedBox(width: 6),
                        Text(
                          count,
                          style: DoableType.label.copyWith(
                            color: colors.muted,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
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
