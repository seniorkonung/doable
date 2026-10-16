import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';
import '../doable_type.dart';

/// Взаимоисключающие состояния конца строки варианта.
enum OptionRowTrailing { none, selected, forward }

/// Вариант со значком, названием и пояснением; выбор обрабатывает потребитель.
/// Текст переносится, а высота строки растёт от минимальных 60 dp.
final class OptionRow extends StatelessWidget {
  const OptionRow({
    required this.icon,
    required this.name,
    required this.hint,
    required this.onPressed,
    this.trailing = OptionRowTrailing.none,
    this.autofocus = false,
    super.key,
  });

  final DoableIconData icon;
  final String name;
  final String hint;
  final VoidCallback onPressed;
  final OptionRowTrailing trailing;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors =
        theme.extension<DoableColors>() ??
        switch (theme.brightness) {
          Brightness.light => DoableColors.light,
          Brightness.dark => DoableColors.dark,
        };
    final selected = trailing == OptionRowTrailing.selected;
    final trailingIcon = switch (trailing) {
      OptionRowTrailing.none => null,
      OptionRowTrailing.selected => DoableIcon(
        DoableIconData.check,
        size: 20,
        color: colors.accent,
      ),
      OptionRowTrailing.forward => DoableIcon(
        DoableIconData.chevronRight,
        size: 20,
        color: colors.muted,
      ),
    };
    final borderRadius = BorderRadius.circular(DoableMetrics.radiusLg);

    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: switch (trailing) {
          OptionRowTrailing.none => false,
          OptionRowTrailing.selected => true,
          OptionRowTrailing.forward => null,
        },
        child: Material(
          color: selected ? colors.fill : Colors.transparent,
          borderRadius: borderRadius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            autofocus: autofocus,
            borderRadius: borderRadius,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 60),
              child: Padding(
                padding: const EdgeInsets.all(DoableMetrics.space2),
                child: Row(
                  children: [
                    Container(
                      width: DoableMetrics.controlHeight,
                      height: DoableMetrics.controlHeight,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected ? colors.accent : colors.fill,
                      ),
                      child: Center(
                        child: DoableIcon(
                          icon,
                          size: 22,
                          color: selected ? colors.onAccent : colors.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: DoableMetrics.space3),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: DoableType.action.copyWith(
                              color: colors.ink,
                            ),
                          ),
                          Text(
                            hint,
                            style: DoableType.hint.copyWith(
                              color: colors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (trailingIcon != null)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          start: DoableMetrics.space3,
                          end: DoableMetrics.space1,
                        ),
                        child: trailingIcon,
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
