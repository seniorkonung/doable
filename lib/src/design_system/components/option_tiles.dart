import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';
import '../doable_type.dart';

/// Плитка выбора с готовыми названием и пояснением; [id] для плиток
/// непрозрачен и только сравнивается с выбранным.
final class OptionTile<T extends Object> {
  const OptionTile({
    required this.id,
    required this.icon,
    required this.title,
    required this.hint,
  });

  final T id;
  final DoableIconData icon;
  final String title;
  final String hint;
}

/// Две плитки взаимоисключающего выбора в равных колонках; обе высотой с
/// более высокую. Выбранную плитку хранит потребитель.
///
/// Нажатие на невыбранную плитку вызывает [onChange], а на выбранную ничего
/// не делает.
final class OptionTiles<T extends Object> extends StatelessWidget {
  const OptionTiles({
    required this.first,
    required this.second,
    required this.value,
    required this.onChange,
    required this.label,
    super.key,
  });

  final OptionTile<T> first;
  final OptionTile<T> second;
  final T value;

  /// Без обработчика плитки недоступны: экранный диктор объявляет
  /// недоступность их состоянием.
  final ValueChanged<T>? onChange;

  /// Доступное название пары.
  final String label;

  @override
  Widget build(BuildContext context) {
    assert(first.id != second.id);
    assert(value == first.id || value == second.id);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: label,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DoableMetrics.space2,
          children: [
            for (final tile in [first, second])
              Expanded(
                child: _Tile(
                  tile: tile,
                  selected: tile.id == value,
                  onChange: onChange,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

final class _Tile<T extends Object> extends StatefulWidget {
  const _Tile({
    required this.tile,
    required this.selected,
    required this.onChange,
  });

  final OptionTile<T> tile;
  final bool selected;
  final ValueChanged<T>? onChange;

  @override
  State<_Tile<T>> createState() => _TileState<T>();
}

final class _TileState<T extends Object> extends State<_Tile<T>> {
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

  // Кольцо фокуса нужно только при управлении с клавиатуры.
  void _handleHighlightMode(FocusHighlightMode mode) {
    if (_focused) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final tile = widget.tile;
    final selected = widget.selected;
    final onChange = widget.onChange;
    const radius = BorderRadius.all(Radius.circular(DoableMetrics.radiusLg));
    final showsFocus =
        _focused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

    final decoration = BoxDecoration(
      color: selected ? colors.fill : null,
      border: selected ? null : Border.all(color: colors.hairline),
      borderRadius: radius,
      boxShadow: showsFocus
          ? [
              BoxShadow(color: colors.accent, spreadRadius: 4),
              BoxShadow(color: colors.bg, spreadRadius: 2),
            ]
          : null,
    );

    return MergeSemantics(
      child: Semantics(
        button: true,
        enabled: onChange != null,
        selected: selected,
        inMutuallyExclusiveGroup: true,
        // Плоскость, кольца и отклик нажатия рисуются в порядке потомков,
        // поэтому область прокрутки их обрезает. На Material предка они
        // рисовались бы под всем его содержимым и без этой обрезки:
        // https://api.flutter.dev/flutter/material/InkWell-class.html
        child: DecoratedBox(
          decoration: decoration,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: switch (onChange) {
                null => null,
                final onChange => () {
                  if (!selected) onChange(tile.id);
                },
              },
              borderRadius: radius,
              focusColor: Colors.transparent,
              onFocusChange: (focused) => setState(() => _focused = focused),
              // Рамка лежит внутри плитки и сдвигает содержимое на свою
              // толщину.
              child: Padding(
                padding: decoration.padding.add(
                  const EdgeInsets.all(DoableMetrics.space3),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 6,
                  children: [
                    Row(
                      spacing: DoableMetrics.space2,
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: selected ? colors.accent : colors.fill,
                          ),
                          alignment: Alignment.center,
                          child: DoableIcon(
                            tile.icon,
                            size: 20,
                            color: selected ? colors.onAccent : colors.ink,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            tile.title,
                            style: DoableType.section.copyWith(
                              color: colors.ink,
                            ),
                          ),
                        ),
                        if (selected)
                          DoableIcon(
                            DoableIconData.check,
                            size: 18,
                            color: colors.accent,
                          ),
                      ],
                    ),
                    Text(
                      tile.hint,
                      style: DoableType.hint.copyWith(color: colors.muted),
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
