import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';
import '../doable_type.dart';
import 'tag_dot.dart';

/// Выбор одного из девяти цветов тега или варианта «Без цвета».
/// Потребитель хранит [value], передаёт готовые подписи и решает,
/// когда объявлять смену цвета, через [announcesValue].
final class TagColorPicker extends StatelessWidget {
  const TagColorPicker({
    required this.value,
    required this.label,
    required this.colorLabel,
    required this.groupLabel,
    required this.onChanged,
    this.announcesValue = false,
    super.key,
  });

  final DoableTagColor? value;
  final String label;

  /// Название каждого варианта, включая `null` — «Без цвета».
  final String Function(DoableTagColor?) colorLabel;

  /// Доступное название группы образцов.
  final String groupLabel;
  final ValueChanged<DoableTagColor?> onChanged;

  /// Делает название выбранного варианта в шапке живой областью:
  /// экранный диктор объявляет каждое изменение этого названия.
  final bool announcesValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors =
        theme.extension<DoableColors>() ??
        switch (theme.brightness) {
          Brightness.light => DoableColors.light,
          Brightness.dark => DoableColors.dark,
        };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: DoableMetrics.tapMin),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: DoableType.row.copyWith(color: colors.ink),
                ),
              ),
              const SizedBox(width: DoableMetrics.space2),
              Expanded(
                child: Semantics(
                  container: announcesValue,
                  liveRegion: announcesValue,
                  child: Text(
                    colorLabel(value),
                    textAlign: TextAlign.end,
                    style: DoableType.body.copyWith(color: colors.muted),
                  ),
                ),
              ),
            ],
          ),
        ),
        Semantics(
          container: true,
          explicitChildNodes: true,
          label: groupLabel,
          child: Material(
            type: MaterialType.transparency,
            // Вложенная сетка не перехватывает прокрутку формы:
            // https://api.flutter.dev/flutter/widgets/GridView/GridView.count.html
            child: GridView.count(
              crossAxisCount: 5,
              mainAxisExtent: DoableMetrics.tapMin,
              shrinkWrap: true,
              primary: false,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              children: [
                for (final color in [null, ...DoableTagColor.values])
                  _swatch(color, colors),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _swatch(DoableTagColor? color, DoableColors colors) {
    final selected = color == value;

    return Semantics(
      container: true,
      label: colorLabel(color),
      button: true,
      selected: selected,
      child: InkResponse(
        onTap: () => onChanged(color),
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? colors.raised : null,
              border: selected ? Border.all(color: colors.ink, width: 2) : null,
            ),
            child: Padding(
              padding: const EdgeInsets.all(DoableMetrics.space1),
              child: SizedBox.square(
                dimension: 28,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color == null ? null : colors[color.token],
                    border: color == null
                        ? Border.all(color: colors.grip, width: 2)
                        : null,
                  ),
                  child: selected
                      ? Center(
                          child: DoableIcon(
                            DoableIconData.check,
                            size: 14,
                            color: color == null ? colors.ink : colors.bg,
                          ),
                        )
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
