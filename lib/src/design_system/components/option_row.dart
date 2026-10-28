import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';
import '../doable_type.dart';

/// Взаимоисключающие состояния конца строки варианта.
enum OptionRowTrailing { none, selected, forward }

/// Тон строки: обычный или опасный для разрушительного варианта.
enum OptionRowTone { normal, danger }

/// Ход операции, которую выполняет строка.
final class OptionRowProgress {
  const OptionRowProgress({required this.share, required this.label});

  /// Выполненная доля от 0 до 1.
  final double share;

  /// Ход для экранного диктора, например «42 %».
  final String label;
}

/// Вариант со значком, названием и пояснением; выбор обрабатывает потребитель.
/// Текст переносится, а высота строки растёт от минимальных 60 dp.
final class OptionRow extends StatelessWidget {
  const OptionRow({
    required this.icon,
    required this.name,
    required this.onPressed,
    this.hint,
    this.trailing = OptionRowTrailing.none,
    this.tone = OptionRowTone.normal,
    this.progress,
    this.autofocus = false,
    super.key,
  });

  final DoableIconData icon;
  final String name;

  /// Пояснение под названием; без него строка показывает только название.
  final String? hint;

  /// Без обработчика строка недоступна: значок и название приглушены, а
  /// экранный диктор объявляет недоступность состоянием строки.
  final VoidCallback? onPressed;
  final OptionRowTrailing trailing;

  /// Опасный тон окрашивает плитку, значок и название доступной строки;
  /// пояснение остаётся приглушённым и называет, что сохранится.
  final OptionRowTone tone;

  /// Ход операции строки: кольцо вокруг значка, которое экранный диктор
  /// читает значением строки.
  final OptionRowProgress? progress;
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
    final danger = tone == OptionRowTone.danger && onPressed != null;
    final ink = onPressed == null
        ? colors.grip
        : danger
        ? colors.danger
        : colors.ink;
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
        enabled: onPressed != null,
        selected: switch (trailing) {
          OptionRowTrailing.none => false,
          OptionRowTrailing.selected => true,
          OptionRowTrailing.forward => null,
        },
        value: progress?.label,
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
                        color: selected
                            ? colors.accent
                            : danger
                            ? colors.dangerSoft
                            : colors.fill,
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          DoableIcon(
                            icon,
                            size: 22,
                            color: selected ? colors.onAccent : ink,
                          ),
                          if (progress case final progress?)
                            Positioned.fill(
                              // Ход читается значением строки.
                              child: ExcludeSemantics(
                                child: CircularProgressIndicator(
                                  value: progress.share,
                                ),
                              ),
                            ),
                        ],
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
                            style: DoableType.action.copyWith(color: ink),
                          ),
                          if (hint case final hint?)
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
